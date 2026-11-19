(* FB_DigitalIn — a switch, float or contact, cleaned up: debounce, an alarm on a state, chatter detection.
Pins: bRawIn (the raw input; NC: NOT at the pin), eInputQuality (its quality from the IO map), bResetFaults (reset a Manual alarm)
-> bSignal (the clean signal), bStateAlarm, bChattering, bGood, plus FB_Object's bError / bWarning / eErrorId / eState.
refData: its record.
  debounce  bSignal follows the input once it has held its new state for set.tDebounceOnTime (turning on) or tDebounceOffTime
            (turning off)
  chatter   more than set.nChatterChanges clean changes within set.tChatterWindow: bSignal holds its last stable value,
            not good, a warning (Chatter), until the input has been steady for tChatterWindow (count 0 = off)
  alarm     a warning (StateAlarm) on the chosen state of bSignal (set.eAlarmWhen), after set.tAlarmDelay; it clears per
            set.eAlarmResetMode (Auto when bSignal returns; Manual holds until a reset)
  eInputQuality      NotFitted / Unused: not on this site: bSignal FALSE, no alarm, eState Off; any other bad quality: bSignal
            held, not good, bError IoBad
Totals (tot): nChangeCount of the clean input, tTotalOnTime while bSignal is TRUE; running totals (no day rollover: the board
has no clock; SCADA makes days), kept hourly; bCmdResetTotals clears them. Simulation is an IO map force.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_DigitalIn EXTENDS FB_Object
  VAR_INPUT
    bRawIn : BOOL; (* the raw input (NC: NOT at the pin) *)
    eInputQuality : E_IoQ := E_IoQ.Ok; (* quality from the IO map row *)
    bResetFaults : BOOL R_EDGE; (* reset a Manual alarm *)
    refData : REFERENCE TO ST_DigitalInData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bSignal : BOOL; (* clean signal *)
    bGood : BOOL; (* bSignal is usable *)
    bStateAlarm : BOOL; (* the state alarm (a warning) *)
    bChattering : BOOL; (* too many changes; bSignal holds its last stable value *)
  END_VAR
  VAR RETAIN
    stKept : ST_DigitalInSet;
    stKeptTot : ST_DigitalInTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stProt : ST_ProtectionSet;
    stProtSts : ST_ProtectionSts;
    stWork : ST_ProtectionWork;
    tPrev : TIME;
    tKeptAt : TIME;
    bRawPrev : BOOL;
    tRawSince : TIME;
    bStable : BOOL;
    bStablePrev : BOOL;
    tWinStart : TIME;
    nWinCount : INT;
    tQSince : TIME;
    bQOut : BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bNotFitted : BOOL;
    bQBad : BOOL;
    bRaw : BOOL;
    bResetReq : BOOL;
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_DigitalInSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tDebounceOnTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tDebounceOffTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tAlarmDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nChatterChanges >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tChatterWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eAlarmWhen = E_DiAlarm.None OR stS.eAlarmWhen = E_DiAlarm.WhenTrue
             OR stS.eAlarmWhen = E_DiAlarm.WhenFalse) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eAlarmResetMode = E_ResetMode.Auto OR stS.eAlarmResetMode = E_ResetMode.Retry
             OR stS.eAlarmResetMode = E_ResetMode.Manual) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_DigitalInSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bGood := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bNotFitted := eInputQuality = E_IoQ.Unused OR eInputQuality = E_IoQ.NotFitted;
bQBad := NOT bNotFitted AND NOT (eInputQuality = E_IoQ.Ok OR eInputQuality = E_IoQ.Forced);
bRaw := bRawIn AND NOT bNotFitted;

(* kept settings and totals; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tPrev := tNow;
  tKeptAt := tNow;
  bRawPrev := bRaw;
  tRawSince := tNow;
  bStable := bRaw;
  bStablePrev := bRaw;
  tQSince := tNow;
  bQOut := bRaw;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bResetReq := bResetFaults OR SystemReset();
IF refData.bCmdResetFaults THEN
  bResetReq := TRUE;
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* debounce, and chatter: more than nChatterChanges clean changes in a window *)
IF bNotFitted THEN                (* not on this site: off, nothing held *)
  bStable := FALSE;
  bRawPrev := FALSE;
  bChattering := FALSE;
  nWinCount := 0;
ELSIF NOT bQBad THEN              (* a bad input holds bSignal *)
  IF bRaw <> bRawPrev THEN
    tRawSince := tNow;
  END_IF;
  bRawPrev := bRaw;
  IF refData.set.nChatterChanges <= 0 THEN
    bChattering := FALSE;
    nWinCount := 0;
  ELSIF bChattering AND tNow - tRawSince >= refData.set.tChatterWindow THEN
    bChattering := FALSE;
    nWinCount := 0;
  END_IF;
  IF bRaw <> bStable AND NOT bChattering THEN
    IF (bRaw AND tNow - tRawSince >= refData.set.tDebounceOnTime)
       OR (NOT bRaw AND tNow - tRawSince >= refData.set.tDebounceOffTime) THEN
      IF refData.set.nChatterChanges > 0 THEN
        IF nWinCount = 0 OR tNow - tWinStart > refData.set.tChatterWindow THEN
          tWinStart := tNow;
          nWinCount := 0;
        END_IF;
        nWinCount := nWinCount + 1;
        bChattering := nWinCount > refData.set.nChatterChanges;
      END_IF;
      IF NOT bChattering THEN
        bStable := bRaw;
      END_IF;
    END_IF;
  END_IF;
END_IF;
bSignal := bStable;
bGood := NOT (bChattering OR bQBad OR bNotFitted);

(* totals: running, kept hourly *)
IF refData.bCmdResetTotals THEN
  refData.bCmdResetTotals := FALSE;
  refData.tot.nChangeCount := 0;
  refData.tot.tTotalOnTime := T#0s;
  stKeptTot := refData.tot;
END_IF;
IF bStable <> bStablePrev THEN
  refData.tot.nChangeCount := refData.tot.nChangeCount + 1;
END_IF;
bStablePrev := bStable;
IF bSignal THEN
  refData.tot.tTotalOnTime := refData.tot.tTotalOnTime + (tNow - tPrev);
END_IF;
tPrev := tNow;
IF tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

(* the alarm on a state *)
IF refData.set.eAlarmWhen = E_DiAlarm.None OR bNotFitted THEN
  stProt.eActionOnFault := E_Response.Off;
ELSE
  stProt.eActionOnFault := E_Response.Warn;
END_IF;
stProt.tTripDelay := refData.set.tAlarmDelay;
stProt.eResetMode := refData.set.eAlarmResetMode;
stProt.tAutoRecoverAfter := T#0s;
stProt.nMaxRetriesBeforeLockout := 3;
F_Protect(tNow := tNow, bConditionPresent := (refData.set.eAlarmWhen = E_DiAlarm.WhenTrue AND bSignal)
                                  OR (refData.set.eAlarmWhen = E_DiAlarm.WhenFalse AND NOT bSignal),
          bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := stProt, stStatus := stProtSts, stWorking := stWork);
bStateAlarm := stWork.bWarning;
IF bSignal <> bQOut THEN
  tQSince := tNow;
END_IF;
bQOut := bSignal;
refData.det.tInStateFor := tNow - tQSince;

(* errors *)
bError := bQBad;
bWarning := NOT bError AND (bChattering OR bStateAlarm OR NOT bOkSet OR refData.sts.bSettingRefused);
IF bQBad THEN
  eErrorId := E_UtError.IoBad;
ELSIF bChattering THEN
  eErrorId := E_UtError.Chatter;
ELSIF bStateAlarm THEN
  eErrorId := E_UtError.StateAlarm;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bNotFitted THEN
  eState := E_State.Off;
ELSIF bChattering THEN
  eState := E_State.Held;
ELSIF bSignal THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.bSignal := bSignal;
refData.sts.bStateAlarm := bStateAlarm;
refData.sts.bChattering := bChattering;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK