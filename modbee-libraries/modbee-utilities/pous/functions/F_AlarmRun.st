(* F_AlarmRun — one alarm's engine (private to FB_AlarmTable and FB_Alarm): the condition stA.bIn after stS.tDelay (on)
and stS.tRecover (off); the reset rule (Auto clears itself; Manual latches until bRst with the condition gone;
Retry clears itself but locks out after stS.nMaxRetries raises within tRetryWindow); bAck acknowledges, bRst
acknowledges and resets, bSil silences; tRearm annunciates a standing alarm again. Returns TRUE on the scan it is
raised; stA.bSounding: it calls for the siren now. *)

FUNCTION F_AlarmRun : BOOL
  VAR_INPUT
    tNow : TIME;
    bAck : BOOL;
    bRst : BOOL;
    bSil : BOOL;
    tRetryWindow : TIME; (* 0 = until a reset *)
  END_VAR
  VAR_IN_OUT
    stS : ST_AlarmSet;
    stA : ST_Alarm;
  END_VAR
  VAR
    bRaise : BOOL;
    bLock : BOOL;
    tOnD : TIME;
    tOffD : TIME;
  END_VAR


bRaise := FALSE;
stA.bSounding := FALSE;
tOnD := MAX(stS.tDelay, T#0s);
tOffD := MAX(stS.tRecover, T#0s);
IF stA.bIn <> stA.bInPrev THEN
  stA.tChange := tNow;
END_IF;
stA.bInPrev := stA.bIn;
IF stS.eResponse = E_Response.Off THEN
  stA.bCond := FALSE;
  stA.eState := E_AlarmState.Off;
  stA.bUnacked := FALSE;
  stA.bSilenced := FALSE;
  stA.nRetries := 0;
ELSE
  IF stA.eState = E_AlarmState.Off THEN
    stA.eState := E_AlarmState.Normal;   (* switched on again *)
  END_IF;
  IF stA.bCond THEN
    IF NOT stA.bIn AND tNow - stA.tChange >= tOffD THEN
      stA.bCond := FALSE;
    END_IF;
  ELSIF stA.bIn AND tNow - stA.tChange >= tOnD THEN
    stA.bCond := TRUE;
    bRaise := TRUE;
  END_IF;
  (* the retry window ran out: count again *)
  IF stA.nRetries > 0 AND stA.eState <> E_AlarmState.Locked AND tRetryWindow > T#0s
     AND tNow - stA.tWin >= tRetryWindow THEN
    stA.nRetries := 0;
  END_IF;
  IF bRaise THEN
    bLock := FALSE;
    IF stS.eReset = E_ResetMode.Retry THEN
      IF stA.nRetries = 0 THEN
        stA.tWin := tNow;
      END_IF;
      IF stA.nRetries < 255 THEN
        stA.nRetries := stA.nRetries + 1;
      END_IF;
      bLock := stA.nRetries > stS.nMaxRetries OR stA.eState = E_AlarmState.Locked;
    END_IF;
    IF bLock THEN
      stA.eState := E_AlarmState.Locked;
    ELSE
      stA.eState := E_AlarmState.Active;
    END_IF;
    stA.bUnacked := TRUE;
    stA.bSilenced := FALSE;
  ELSIF stA.eState = E_AlarmState.Active AND NOT stA.bCond THEN
    IF stS.eReset = E_ResetMode.Manual THEN
      stA.eState := E_AlarmState.Latched;
    ELSIF stA.bUnacked THEN
      stA.eState := E_AlarmState.Returned;
    ELSE
      stA.eState := E_AlarmState.Normal;
    END_IF;
  END_IF;
  (* acknowledge and reset *)
  IF bAck AND stA.bUnacked THEN
    stA.bUnacked := FALSE;
    stA.tAck := tNow;
  END_IF;
  IF bRst AND NOT stA.bCond THEN
    stA.nRetries := 0;
    IF stA.eState <> E_AlarmState.Active THEN
      stA.eState := E_AlarmState.Normal;
    END_IF;
  END_IF;
  IF stA.eState = E_AlarmState.Returned AND NOT stA.bUnacked THEN
    stA.eState := E_AlarmState.Normal;
  END_IF;
  IF stS.eReset <> E_ResetMode.Manual AND stA.eState = E_AlarmState.Latched THEN
    stA.eState := E_AlarmState.Normal;   (* changed from Manual while latched *)
  END_IF;
  (* silence and re-arm *)
  stA.bSounding := stS.bSiren AND stA.bUnacked AND NOT stA.bSilenced
                   AND (stA.eState = E_AlarmState.Active
                        OR (stA.eState = E_AlarmState.Locked AND stA.bCond));
  IF bSil AND stA.bSounding THEN
    stA.bSilenced := TRUE;
    stA.tAck := tNow;
    stA.bSounding := FALSE;
  END_IF;
  IF stA.bCond AND (stA.bSilenced OR NOT stA.bUnacked) AND stS.tRearm > T#0s
     AND tNow - stA.tAck >= stS.tRearm THEN
    stA.bUnacked := TRUE;   (* still on: annunciate it again *)
    stA.bSilenced := FALSE;
    stA.tAck := tNow;
    stA.bSounding := stS.bSiren;
  END_IF;
END_IF;
stA.bQ := stA.eState = E_AlarmState.Active OR stA.eState = E_AlarmState.Latched
          OR stA.eState = E_AlarmState.Locked;
F_AlarmRun := bRaise;

END_FUNCTION