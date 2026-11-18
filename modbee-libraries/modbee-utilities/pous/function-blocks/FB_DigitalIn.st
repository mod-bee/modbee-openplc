(* FB_DigitalIn — a switch, float or contact, cleaned up: debounce, an alarm on a state, chatter detection.
Pins: bIn (the raw input; NC: NOT at the pin), eInQ (its quality from the IO map), bReset (reset a Manual alarm)
-> bQ (the clean signal), bAlarm, bChatter, bGood, plus FB_Object's bError / bWarning / eErrorId / eState.
refData: its record.
  debounce  bQ follows the input once it has held its new state for set.tOnDelay (turning on) or tOffDelay
            (turning off)
  chatter   more than set.nChatterCount clean changes within set.tChatterTime: bQ holds its last stable value,
            not good, a warning (Chatter), until the input has been steady for tChatterTime (count 0 = off)
  alarm     a warning (StateAlarm) on the chosen state of bQ (set.eAlarmOn), after set.tAlarmDelay; it clears per
            set.eAlarmReset (Auto when bQ returns; Manual holds until a reset)
  eInQ      NotFitted / Unused: not on this site: bQ FALSE, no alarm, eState Off; any other bad quality: bQ
            held, not good, bError IoBad
Totals (tot): nChanges of the clean input, tOnTime while bQ is TRUE; running totals (no day rollover: the board
has no clock; SCADA makes days), kept hourly; bCmdResetTot clears them. Simulation is an IO map force.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_DigitalIn EXTENDS FB_Object
  VAR_INPUT
    bIn : BOOL; (* the raw input (NC: NOT at the pin) *)
    eInQ : E_IoQ := E_IoQ.Ok; (* quality from the IO map row *)
    bReset : BOOL R_EDGE; (* reset a Manual alarm *)
    refData : REFERENCE TO ST_DigitalInData;
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* clean signal *)
    bAlarm : BOOL;
    bChatter : BOOL; (* too many changes; bQ holds its last stable value *)
    bGood : BOOL; (* bQ is usable *)
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
  IF NOT (stS.tOnDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tOffDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tAlarmDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nChatterCount >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tChatterTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eAlarmOn = E_DiAlarm.None OR stS.eAlarmOn = E_DiAlarm.WhenTrue
             OR stS.eAlarmOn = E_DiAlarm.WhenFalse) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eAlarmReset = E_ResetMode.Auto OR stS.eAlarmReset = E_ResetMode.Retry
             OR stS.eAlarmReset = E_ResetMode.Manual) THEN
    SetWhy := E_UtError.ChoiceBad;
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
bNotFitted := eInQ = E_IoQ.Unused OR eInQ = E_IoQ.NotFitted;
bQBad := NOT bNotFitted AND NOT (eInQ = E_IoQ.Ok OR eInQ = E_IoQ.Forced);
bRaw := bIn AND NOT bNotFitted;

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
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bResetReq := bReset OR SystemReset();
IF refData.bCmdReset THEN
  bResetReq := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* debounce, and chatter: more than nChatterCount clean changes in a window *)
IF bNotFitted THEN                (* not on this site: off, nothing held *)
  bStable := FALSE;
  bRawPrev := FALSE;
  bChatter := FALSE;
  nWinCount := 0;
ELSIF NOT bQBad THEN              (* a bad input holds bQ *)
  IF bRaw <> bRawPrev THEN
    tRawSince := tNow;
  END_IF;
  bRawPrev := bRaw;
  IF refData.set.nChatterCount <= 0 THEN
    bChatter := FALSE;
    nWinCount := 0;
  ELSIF bChatter AND tNow - tRawSince >= refData.set.tChatterTime THEN
    bChatter := FALSE;
    nWinCount := 0;
  END_IF;
  IF bRaw <> bStable AND NOT bChatter THEN
    IF (bRaw AND tNow - tRawSince >= refData.set.tOnDelay)
       OR (NOT bRaw AND tNow - tRawSince >= refData.set.tOffDelay) THEN
      IF refData.set.nChatterCount > 0 THEN
        IF nWinCount = 0 OR tNow - tWinStart > refData.set.tChatterTime THEN
          tWinStart := tNow;
          nWinCount := 0;
        END_IF;
        nWinCount := nWinCount + 1;
        bChatter := nWinCount > refData.set.nChatterCount;
      END_IF;
      IF NOT bChatter THEN
        bStable := bRaw;
      END_IF;
    END_IF;
  END_IF;
END_IF;
bQ := bStable;
bGood := NOT (bChatter OR bQBad OR bNotFitted);

(* totals: running, kept hourly *)
IF refData.bCmdResetTot THEN
  refData.bCmdResetTot := FALSE;
  refData.tot.nChanges := 0;
  refData.tot.tOnTime := T#0s;
  stKeptTot := refData.tot;
END_IF;
IF bStable <> bStablePrev THEN
  refData.tot.nChanges := refData.tot.nChanges + 1;
END_IF;
bStablePrev := bStable;
IF bQ THEN
  refData.tot.tOnTime := refData.tot.tOnTime + (tNow - tPrev);
END_IF;
tPrev := tNow;
IF tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

(* the alarm on a state *)
IF refData.set.eAlarmOn = E_DiAlarm.None OR bNotFitted THEN
  stProt.eResponse := E_Response.Off;
ELSE
  stProt.eResponse := E_Response.Warn;
END_IF;
stProt.tDelay := refData.set.tAlarmDelay;
stProt.eReset := refData.set.eAlarmReset;
stProt.tRecover := T#0s;
stProt.nMaxRetries := 3;
F_Protect(tNow := tNow, bCause := (refData.set.eAlarmOn = E_DiAlarm.WhenTrue AND bQ)
                                  OR (refData.set.eAlarmOn = E_DiAlarm.WhenFalse AND NOT bQ),
          bResetReq := bResetReq, tRetryWindow := T#1h, stSet := stProt, stSts := stProtSts, stWork := stWork);
bAlarm := stWork.bWarn;
IF bQ <> bQOut THEN
  tQSince := tNow;
END_IF;
bQOut := bQ;
refData.det.tStateFor := tNow - tQSince;

(* errors *)
bError := bQBad;
bWarning := NOT bError AND (bChatter OR bAlarm OR NOT bOkSet OR refData.sts.bRefused);
IF bQBad THEN
  eErrorId := E_UtError.IoBad;
ELSIF bChatter THEN
  eErrorId := E_UtError.Chatter;
ELSIF bAlarm THEN
  eErrorId := E_UtError.StateAlarm;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bNotFitted THEN
  eState := E_State.Off;
ELSIF bChatter THEN
  eState := E_State.Held;
ELSIF bQ THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.bQ := bQ;
refData.sts.bAlarm := bAlarm;
refData.sts.bChatter := bChatter;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK