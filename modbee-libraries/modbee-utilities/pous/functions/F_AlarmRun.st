(* F_AlarmRun — one alarm's engine (private to FB_AlarmTable and FB_Alarm): the condition stAlarm.bConditionPresent after stSettings.tTripDelay (on)
and stSettings.tAutoRecoverAfter (off); the reset rule (Auto clears itself; Manual latches until bResetRequest with the condition gone;
Retry clears itself but locks out after stSettings.nMaxRetriesBeforeLockout raises within tRetryCountWindow); bAcknowledge acknowledges, bResetRequest
acknowledges and resets, bSilence silences; tReAlarmAfter annunciates a standing alarm again. Returns TRUE on the scan it is
raised; stAlarm.bCallsForHorn: it calls for the horn now. *)

FUNCTION F_AlarmRun : BOOL
  VAR_INPUT
    tNow : TIME; (* TIME() of this scan *)
    bAcknowledge : BOOL; (* acknowledge this scan *)
    bResetRequest : BOOL; (* acknowledge and reset this scan *)
    bSilence : BOOL; (* silence this scan *)
    tRetryCountWindow : TIME; (* 0 = until a reset *)
  END_VAR
  VAR_IN_OUT
    stSettings : ST_AlarmSet; (* the row's settings (read only) *)
    stAlarm : ST_Alarm; (* the row's live data *)
  END_VAR
  VAR
    bRaise : BOOL;
    bLock : BOOL;
    tOnD : TIME;
    tOffD : TIME;
  END_VAR


bRaise := FALSE;
stAlarm.bCallsForHorn := FALSE;
tOnD := MAX(stSettings.tTripDelay, T#0s);
tOffD := MAX(stSettings.tAutoRecoverAfter, T#0s);
IF stAlarm.bConditionPresent <> stAlarm.bConditionLastScan THEN
  stAlarm.tConditionChangedAt := tNow;
END_IF;
stAlarm.bConditionLastScan := stAlarm.bConditionPresent;
IF stSettings.eActionOnFault = E_Response.Off THEN
  stAlarm.bConditionConfirmed := FALSE;
  stAlarm.eRowState := E_AlarmState.Off;
  stAlarm.bUnacknowledged := FALSE;
  stAlarm.bSilenced := FALSE;
  stAlarm.nRetriesUsed := 0;
ELSE
  IF stAlarm.eRowState = E_AlarmState.Off THEN
    stAlarm.eRowState := E_AlarmState.Normal;   (* switched on again *)
  END_IF;
  IF stAlarm.bConditionConfirmed THEN
    IF NOT stAlarm.bConditionPresent AND tNow - stAlarm.tConditionChangedAt >= tOffD THEN
      stAlarm.bConditionConfirmed := FALSE;
    END_IF;
  ELSIF stAlarm.bConditionPresent AND tNow - stAlarm.tConditionChangedAt >= tOnD THEN
    stAlarm.bConditionConfirmed := TRUE;
    bRaise := TRUE;
  END_IF;
  (* the retry window ran out: count again *)
  IF stAlarm.nRetriesUsed > 0 AND stAlarm.eRowState <> E_AlarmState.Locked AND tRetryCountWindow > T#0s
     AND tNow - stAlarm.tRetryWindowStartedAt >= tRetryCountWindow THEN
    stAlarm.nRetriesUsed := 0;
  END_IF;
  IF bRaise THEN
    bLock := FALSE;
    IF stSettings.eResetMode = E_ResetMode.Retry THEN
      IF stAlarm.nRetriesUsed = 0 THEN
        stAlarm.tRetryWindowStartedAt := tNow;
      END_IF;
      IF stAlarm.nRetriesUsed < 32767 THEN
        stAlarm.nRetriesUsed := stAlarm.nRetriesUsed + 1;
      END_IF;
      bLock := stAlarm.nRetriesUsed > stSettings.nMaxRetriesBeforeLockout OR stAlarm.eRowState = E_AlarmState.Locked;
    END_IF;
    IF bLock THEN
      stAlarm.eRowState := E_AlarmState.Locked;
    ELSE
      stAlarm.eRowState := E_AlarmState.Active;
    END_IF;
    stAlarm.bUnacknowledged := TRUE;
    stAlarm.bSilenced := FALSE;
  ELSIF stAlarm.eRowState = E_AlarmState.Active AND NOT stAlarm.bConditionConfirmed THEN
    IF stSettings.eResetMode = E_ResetMode.Manual THEN
      stAlarm.eRowState := E_AlarmState.Latched;
    ELSIF stAlarm.bUnacknowledged THEN
      stAlarm.eRowState := E_AlarmState.Returned;
    ELSE
      stAlarm.eRowState := E_AlarmState.Normal;
    END_IF;
  END_IF;
  (* acknowledge and reset *)
  IF bAcknowledge AND stAlarm.bUnacknowledged THEN
    stAlarm.bUnacknowledged := FALSE;
    stAlarm.tSilencedOrAcknowledgedAt := tNow;
  END_IF;
  IF bResetRequest AND NOT stAlarm.bConditionConfirmed THEN
    stAlarm.nRetriesUsed := 0;
    IF stAlarm.eRowState <> E_AlarmState.Active THEN
      stAlarm.eRowState := E_AlarmState.Normal;
    END_IF;
  END_IF;
  IF stAlarm.eRowState = E_AlarmState.Returned AND NOT stAlarm.bUnacknowledged THEN
    stAlarm.eRowState := E_AlarmState.Normal;
  END_IF;
  IF stSettings.eResetMode <> E_ResetMode.Manual AND stAlarm.eRowState = E_AlarmState.Latched THEN
    stAlarm.eRowState := E_AlarmState.Normal;   (* changed from Manual while latched *)
  END_IF;
  (* silence and re-arm *)
  stAlarm.bCallsForHorn := stSettings.bSoundsHorn AND stAlarm.bUnacknowledged AND NOT stAlarm.bSilenced
                   AND (stAlarm.eRowState = E_AlarmState.Active
                        OR (stAlarm.eRowState = E_AlarmState.Locked AND stAlarm.bConditionConfirmed));
  IF bSilence AND stAlarm.bCallsForHorn THEN
    stAlarm.bSilenced := TRUE;
    stAlarm.tSilencedOrAcknowledgedAt := tNow;
    stAlarm.bCallsForHorn := FALSE;
  END_IF;
  IF stAlarm.bConditionConfirmed AND (stAlarm.bSilenced OR NOT stAlarm.bUnacknowledged) AND stSettings.tReAlarmAfter > T#0s
     AND tNow - stAlarm.tSilencedOrAcknowledgedAt >= stSettings.tReAlarmAfter THEN
    stAlarm.bUnacknowledged := TRUE;   (* still on: annunciate it again *)
    stAlarm.bSilenced := FALSE;
    stAlarm.tSilencedOrAcknowledgedAt := tNow;
    stAlarm.bCallsForHorn := stSettings.bSoundsHorn;
  END_IF;
END_IF;
stAlarm.bAlarmOn := stAlarm.eRowState = E_AlarmState.Active OR stAlarm.eRowState = E_AlarmState.Latched
          OR stAlarm.eRowState = E_AlarmState.Locked;
F_AlarmRun := bRaise;

END_FUNCTION