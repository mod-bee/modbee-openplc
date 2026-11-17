(* FB_LevelCheck — one alarm level on any measurement, as a part of its owner: low pressure, high pressure, no flow,
dry run, a high tank level ... one block for each level fitted.

Pins: bSwitch, ipMeas (the measurement: its value against set.fSetpoint, and / or one of its switch bands),
ipOwner (the equipment it acts on), refData. The direction (high or low), the setpoint with its deadband,
the band, "only while running" and "masked at start" are settings.
bSwitch: a switch wired straight to this rung that backs the value up (TRUE = past the level: a float, a pressure
switch); it acts like the band, also with a bad or unfitted value. With no ipMeas wired the check is the switch
alone (a flow switch, a float: no dummy measurement needed).
A bad measurement is ridden through for set.tBadRide (the state is held), then the value part lets go: the
sensor raises its own fault, and a switch band still acts. A measurement that is not fitted is no check.
It acts per its protection settings (off / warn / trip / signal, delay, reset). A signal is a stop without an
alarm (the owner stops and restarts with it); with set.bDoneWhenReached a signal ends the owner's run instead
(Done: a full destination ends a latched transfer run; for a held run keep the pause). Its rung stopping while it acts is PartLost on its owner. *)

FUNCTION_BLOCK FB_LevelCheck EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bSwitch : BOOL := FALSE; (* optional switch, TRUE = past the level (a backup, or the only signal) *)
    ipMeas : I_Measurement; (* optional: none wired = the switch alone *)
    ipOwner : I_PartOwner; (* required *)
    refData : REFERENCE TO ST_LevelCheckData;
  END_VAR
  VAR RETAIN
    stKept : ST_LevelCheckSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bBeyond : BOOL;
    bBand : BOOL;
    tBadSince : TIME;
    bWasGood : BOOL := TRUE;
    stWork : ST_ProtectionWork;
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
    bCause : BOOL;
    bTrip : BOOL;
    bOwnReset : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := refData.set.eErrorId;
  IF NOT bCalled AND refData.sts.eState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  bCause := bBeyond OR bBand;
  IF refData.set.bOnlyWhenRunning AND NOT bRunning THEN
    bCause := FALSE;
  END_IF;
  IF refData.set.bMaskAtStart AND bMasked THEN
    bCause := FALSE;
  END_IF;
  bOwnReset := refData.bCmdReset;
  refData.bCmdReset := FALSE;
  bTrip := F_Protect(tNow := TIME(), bCause := bCause, bResetReq := bResetWanted OR bOwnReset,
                     tRetryWindow := T#1h, stSet := refData.set, stSts := refData.sts, stWork := stWork);
  IF stWork.bTrip THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWork.bSignal AND refData.set.bDoneWhenReached THEN
    Evaluate := E_PartAction.Done;  (* the owner's run ends normally *)
  ELSIF stWork.bSignal THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWork.bWarn OR stWork.bBadSetting THEN
    Evaluate := E_PartAction.Warn;
  ELSE
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
  SetOk := refData.set.tDelay >= T#0s AND refData.set.tRecover >= T#0s AND refData.set.nMaxRetries >= 0
           AND refData.set.fDeadband >= 0.0 AND refData.set.tBadRide >= T#0s
           AND refData.set.fSetpoint = refData.set.fSetpoint;   // not NaN
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  IF ipOwner = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  bFirstScan := FALSE;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;

(* sample the measurement on this rung (none wired: the switch alone) *)
IF ipMeas = NULL THEN
  bBeyond := FALSE;
  bBand := FALSE;
  refData.sts.bBadHeld := FALSE;
ELSIF NOT ipMeas.bIsFitted THEN
  bBeyond := FALSE;
  bBand := FALSE;
  refData.sts.bBadHeld := FALSE;
ELSE
  IF refData.set.eBand <> E_Band.None THEN
    bBand := ipMeas.Band(eBand := refData.set.eBand);
  ELSE
    bBand := FALSE;
  END_IF;
  IF NOT refData.set.bUseValue OR NOT ipMeas.bHasValue THEN
    bBeyond := FALSE;
    refData.sts.bBadHeld := FALSE;
  ELSIF ipMeas.bIsGood THEN
    bWasGood := TRUE;
    refData.sts.bBadHeld := FALSE;
    IF refData.set.eDirection = E_LevelDir.High THEN
      bBeyond := ipMeas.fActValue > refData.set.fSetpoint
                 OR (bBeyond AND ipMeas.fActValue > refData.set.fSetpoint - refData.set.fDeadband);
    ELSE
      bBeyond := ipMeas.fActValue < refData.set.fSetpoint
                 OR (bBeyond AND ipMeas.fActValue < refData.set.fSetpoint + refData.set.fDeadband);
    END_IF;
  ELSE
    IF bWasGood THEN tBadSince := tNow; bWasGood := FALSE; END_IF;
    IF tNow - tBadSince >= refData.set.tBadRide THEN
      bBeyond := FALSE;           // let go of the value part: the sensor raises its own fault
      refData.sts.bBadHeld := FALSE;
    ELSE
      refData.sts.bBadHeld := TRUE;   // ride through: the state is held
    END_IF;
  END_IF;
END_IF;
bBand := bBand OR bSwitch;         (* the backup switch, also with a bad or unfitted value *)
refData.sts.bBeyond := bBeyond;
bCalled := TRUE;
bError := stWork.bTrip;
bWarning := stWork.bWarn;
IF bError OR bWarning THEN
  eErrorId := refData.set.eErrorId;
ELSE
  eErrorId := E_UtError.None;
END_IF;

END_FUNCTION_BLOCK