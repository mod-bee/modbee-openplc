(* FB_LevelCheck — one alarm level on any measurement, as a part of its owner: low pressure, high pressure, no flow,
dry run, a high tank level ... one block for each level fitted.

Pins: bBackupSwitch, ipMeasurement (the measurement: its value against set.fSetpoint, and / or one of its switch bands),
ipOwner (the equipment it acts on), refData. The direction (high or low), the setpoint with its deadband,
the band, "only while running" and "masked at start" are settings.
bBackupSwitch: a switch wired straight to this rung that backs the value up (TRUE = past the level: a float, a pressure
switch); it acts like the band, also with a bad or unfitted value. With no ipMeasurement wired the check is the switch
alone (a flow switch, a float: no dummy measurement needed).
A bad measurement is ridden through for set.tRideThroughBadValue (the state is held), then the value part lets go: the
sensor raises its own fault, and a switch band still acts. A measurement that is not fitted is no check.
It acts per its protection settings (off / warn / trip / signal, delay, reset). A signal is a stop without an
alarm (the owner stops and restarts with it); with set.bEndsRunWhenReached a signal ends the owner's run instead
(Done: a full destination ends a latched transfer run; for a held run keep the pause). Its rung stopping while it acts is PartLost on its owner.
bSuppress TRUE suppresses the check (no cause): an active one clears per its reset settings.
A bad settings write is put back (sts.bSettingRefused / sts.eSettingRefusedErrorId) and warns its owner (SettingRefused) until its
reset (bCmdResetFaults) or the owner's. *)

FUNCTION_BLOCK FB_LevelCheck EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bBackupSwitch : BOOL := FALSE; (* optional switch, TRUE = past the level (a backup, or the only signal) *)
    ipMeasurement : I_Measurement; (* optional: none wired = the switch alone *)
    ipOwner : I_PartOwner; (* required *)
    bSuppress : BOOL; (* TRUE: the check is suppressed (no cause; an active one clears per its reset) *)
    refData : REFERENCE TO ST_LevelCheckData; (* the block's record *)
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
    bOwnerRunCommand : BOOL;    // the owner is running (its run command)
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
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
  eErrorId := refData.set.eErrorRaised;
  IF NOT bCalled AND refData.sts.eFaultState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  bCause := bBeyond OR bBand;
  IF refData.set.bCheckOnlyWhenRunning AND NOT bOwnerRunCommand THEN
    bCause := FALSE;
  END_IF;
  IF refData.set.bUseStartMask AND bStartMaskOn THEN
    bCause := FALSE;
  END_IF;
  IF bSuppress THEN
    bCause := FALSE;              (* suppressed by the project (e.g. while a known condition holds) *)
  END_IF;
  bOwnReset := refData.bCmdResetFaults;
  refData.bCmdResetFaults := FALSE;
  IF bResetRequest OR bOwnReset THEN
    refData.sts.bSettingRefused := FALSE;
    refData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  bTrip := F_Protect(tNow := TIME(), bConditionPresent := bCause, bResetRequest := bResetRequest OR bOwnReset,
                     tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set, stStatus := refData.sts, stWorking := stWork);
  IF stWork.bTripping THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWork.bSignalling AND refData.set.bEndsRunWhenReached THEN
    Evaluate := E_PartAction.Done;  (* the owner's run ends normally *)
  ELSIF stWork.bSignalling THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWork.bWarning OR stWork.bSettingBad THEN
    Evaluate := E_PartAction.Warn;
  ELSIF refData.sts.bSettingRefused THEN
    eErrorId := E_UtError.SettingRefused;
    Evaluate := E_PartAction.Warn;
  ELSE
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNextPart : I_Part;    // the next part in the owner's chain
  END_VAR
  THIS^.ipNext := ipNextPart;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fDeadband >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tRideThroughBadValue >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fSetpoint = refData.set.fSetpoint) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
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
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;

(* sample the measurement on this rung (none wired: the switch alone) *)
IF ipMeasurement = NULL THEN
  bBeyond := FALSE;
  bBand := FALSE;
  refData.sts.bHeldOnBadValue := FALSE;
ELSIF NOT ipMeasurement.bIsFitted THEN
  bBeyond := FALSE;
  bBand := FALSE;
  refData.sts.bHeldOnBadValue := FALSE;
ELSE
  IF refData.set.eSwitchBand <> E_Band.None THEN
    bBand := ipMeasurement.Band(eBand := refData.set.eSwitchBand);
  ELSE
    bBand := FALSE;
  END_IF;
  IF NOT refData.set.bUseMeasuredValue OR NOT ipMeasurement.bHasValue THEN
    bBeyond := FALSE;
    refData.sts.bHeldOnBadValue := FALSE;
  ELSIF ipMeasurement.bIsGood THEN
    bWasGood := TRUE;
    refData.sts.bHeldOnBadValue := FALSE;
    IF refData.set.eCheckAboveOrBelow = E_LevelDir.High THEN
      bBeyond := ipMeasurement.fActValue > refData.set.fSetpoint
                 OR (bBeyond AND ipMeasurement.fActValue > refData.set.fSetpoint - refData.set.fDeadband);
    ELSE
      bBeyond := ipMeasurement.fActValue < refData.set.fSetpoint
                 OR (bBeyond AND ipMeasurement.fActValue < refData.set.fSetpoint + refData.set.fDeadband);
    END_IF;
  ELSE
    IF bWasGood THEN tBadSince := tNow; bWasGood := FALSE; END_IF;
    IF tNow - tBadSince >= refData.set.tRideThroughBadValue THEN
      bBeyond := FALSE;           // let go of the value part: the sensor raises its own fault
      refData.sts.bHeldOnBadValue := FALSE;
    ELSE
      refData.sts.bHeldOnBadValue := TRUE;   // ride through: the state is held
    END_IF;
  END_IF;
END_IF;
bBand := bBand OR bBackupSwitch;         (* the backup switch, also with a bad or unfitted value *)
refData.sts.bPastLevel := bBeyond;
bCalled := TRUE;
bError := stWork.bTripping;
bWarning := stWork.bWarning OR refData.sts.bSettingRefused;
IF bError OR stWork.bWarning THEN
  eErrorId := refData.set.eErrorRaised;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;

END_FUNCTION_BLOCK