(* FB_PumpPrime — priming a pump at its start, as a part of its FB_Pump.

Pins: ipOwner (the pump), ipPressure / ipFlow (optional: the measurement the prime is done by), bPrimeDone
(the pipe is filled: a contact, for set.eDoneBy Input), refData -> bPriming, plus FB_Object's bError /
bWarning / eErrorId / eState.
- It primes on every start (set.bEveryStart) or on the next one (the record's bCmdPrimeNext; bCmdPrimeCancel
  withdraws it before that start, a prime already running carries on). A start is the owner's run command
  coming on (Evaluate's bRunning).
- Done by (set.eDoneBy): Pressure / Flow: the measurement good and above set.fDoneLevel (a switch measurement
  with no value: its Low band clear), held set.tHold; Input: bPrimeDone held set.tHold; RunTime: after running
  set.tRunTime.
- While priming the part asks Mask: the pump's mask-at-start checks (low pressure, no flow) ignore their cause
  (the pump carries a part's Mask into the next scan).
- Priming always ends at set.tTimeout (not with RunTime): PrimeTimeout per set.stTimeout (default Trip, Retry
  after 2 min, 3 tries), its cause present until the pump stops.
- Pressure / Flow with that measurement unwired or not fitted: a warning (BadSetting); the prime then ends at
  its timeout.
Its rung stopping while it acts is PartLost on its owner.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_PumpPrime EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the pump *)
    ipPressure : I_Measurement;
    ipFlow : I_Measurement;
    bPrimeDone : BOOL; (* the pipe is filled (eDoneBy Input) *)
    refData : REFERENCE TO ST_PumpPrimeData;
  END_VAR
  VAR_OUTPUT
    bPriming : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_PumpPrimeSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bCond : BOOL; (* the done condition, sampled on its rung *)
    bCfgBad : BOOL; (* the measurement it is done by is missing *)
    bOwnReset : BOOL;
    bRunPrev : BOOL;
    bThis : BOOL; (* this run primes *)
    bDone : BOOL;
    bTimedOut : BOOL;
    bCondPrev : BOOL;
    tStartAt : TIME;
    tCondAt : TIME;
    stWTimeout : ST_ProtectionWork;
  END_VAR


METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    tN : TIME;
    bNow : BOOL;
    bTrip : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (bPriming OR bTimedOut OR refData.sts.stTimeout.eState <> E_ProtState.Clear) THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF bRunning AND NOT bRunPrev THEN
    bThis := refData.set.bEveryStart OR refData.sts.bPrimeNext;   // a start
    tStartAt := tN;
    bDone := FALSE;
    bCondPrev := FALSE;
  END_IF;
  IF NOT bRunning THEN
    bTimedOut := FALSE;           // the cause is gone once the pump has stopped
  END_IF;
  bRunPrev := bRunning;
  IF bThis AND bRunning AND NOT bDone THEN
    IF refData.set.eDoneBy = E_PrimeDone.RunTime THEN
      bNow := tN - tStartAt >= refData.set.tRunTime;
    ELSE
      bNow := bCond;
    END_IF;
    IF bNow AND NOT bCondPrev THEN
      tCondAt := tN;
    END_IF;
    bCondPrev := bNow;
    IF bNow AND (refData.set.eDoneBy = E_PrimeDone.RunTime OR tN - tCondAt >= refData.set.tHold) THEN
      bDone := TRUE;
      refData.sts.bPrimed := TRUE;
      refData.sts.bPrimeNext := FALSE;
    ELSIF refData.set.eDoneBy <> E_PrimeDone.RunTime AND tN - tStartAt >= refData.set.tTimeout THEN
      bDone := TRUE;              // priming always ends at the timeout
      bTimedOut := TRUE;
      refData.sts.bPrimed := FALSE;
      refData.sts.bPrimeNext := FALSE;
    END_IF;
  END_IF;
  bPriming := bThis AND bRunning AND NOT bDone;
  IF bPriming THEN
    IF refData.set.eDoneBy = E_PrimeDone.RunTime THEN
      refData.sts.tTimeLeft := refData.set.tRunTime - (tN - tStartAt);
    ELSE
      refData.sts.tTimeLeft := refData.set.tTimeout - (tN - tStartAt);
    END_IF;
  ELSE
    refData.sts.tTimeLeft := T#0s;
  END_IF;
  refData.sts.bPriming := bPriming;
  bTrip := F_Protect(tNow := tN, bCause := bTimedOut, bResetReq := bResetWanted OR bOwnReset, tRetryWindow := T#1h,
                     stSet := refData.set.stTimeout, stSts := refData.sts.stTimeout, stWork := stWTimeout);
  bOwnReset := FALSE;
  IF stWTimeout.bTrip THEN
    eErrorId := E_UtError.PrimeTimeout;
    Evaluate := E_PartAction.Trip;
  ELSIF bPriming THEN
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.Mask;
  ELSIF stWTimeout.bSignal THEN
    eErrorId := E_UtError.PrimeTimeout;
    Evaluate := E_PartAction.Stop;
  ELSIF stWTimeout.bWarn THEN
    eErrorId := E_UtError.PrimeTimeout;
    Evaluate := E_PartAction.Warn;
  ELSIF bCfgBad OR stWTimeout.bBadSetting THEN
    eErrorId := E_UtError.BadSetting;
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNext : I_Part;
  END_VAR
  THIS^.ipNext := ipNext;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := refData.set.tHold >= T#0s AND refData.set.tTimeout >= T#0s
           AND refData.set.stTimeout.tDelay >= T#0s AND refData.set.stTimeout.tRecover >= T#0s
           AND refData.set.stTimeout.nMaxRetries >= 0 AND refData.set.fDoneLevel = refData.set.fDoneLevel
           AND (refData.set.eDoneBy <> E_PrimeDone.RunTime OR refData.set.tRunTime > T#0s);
END_METHOD

(* the done condition from one measurement: good and above the done level (a switch: its Low band clear) *)
METHOD PRIVATE MeasDone : BOOL
  VAR_INPUT
    ipM : I_Measurement;
  END_VAR
  IF ipM = NULL THEN
    MeasDone := FALSE;
  ELSIF NOT ipM.bIsFitted OR NOT ipM.bIsGood THEN
    MeasDone := FALSE;
  ELSIF ipM.bHasValue THEN
    MeasDone := ipM.fActValue > refData.set.fDoneLevel;
  ELSE
    MeasDone := NOT ipM.Band(eBand := E_Band.Low);
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  IF ipOwner = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;

(* commands *)
IF refData.bCmdPrimeNext THEN
  refData.sts.bPrimeNext := TRUE;
  refData.bCmdPrimeNext := FALSE;
END_IF;
IF refData.bCmdPrimeCancel THEN
  refData.sts.bPrimeNext := FALSE;   // a prime already running carries on
  refData.bCmdPrimeCancel := FALSE;
END_IF;
IF refData.bCmdReset THEN
  bOwnReset := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;

(* sample the done condition on this rung *)
CASE refData.set.eDoneBy OF
  E_PrimeDone.Pressure:
    bCond := MeasDone(ipM := ipPressure);
    bCfgBad := ipPressure = NULL;
    IF NOT bCfgBad THEN bCfgBad := NOT ipPressure.bIsFitted; END_IF;
  E_PrimeDone.Flow:
    bCond := MeasDone(ipM := ipFlow);
    bCfgBad := ipFlow = NULL;
    IF NOT bCfgBad THEN bCfgBad := NOT ipFlow.bIsFitted; END_IF;
  E_PrimeDone.Input:
    bCond := bPrimeDone;
    bCfgBad := FALSE;
ELSE
  bCond := FALSE;
  bCfgBad := FALSE;
END_CASE;
bCalled := TRUE;

(* status *)
bError := stWTimeout.bTrip;
bWarning := NOT bError AND (stWTimeout.bWarn OR bCfgBad OR stWTimeout.bBadSetting OR refData.sts.bRefused);
IF stWTimeout.bTrip OR stWTimeout.bWarn THEN
  eErrorId := E_UtError.PrimeTimeout;
ELSIF bCfgBad OR stWTimeout.bBadSetting THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bPriming THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK