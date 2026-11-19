(* FB_MotorCurrent — a motor's current from a CT, as a part of its motor. Off until set.fFullLoadCurrent (the motor's
full-load current, in the CT's unit) is set.
- fCurrentPct: the current as % of full load. bCurrentProvesRun: at or above set.fProvesRunAbovePct; wire it to the motor's
  bFeedback when the CT, not an auxiliary contact, proves the motor runs.
- stHighCurrentFault (overload by current, default Off) and stLowCurrentFault (dry run / broken belt, default Off): % of full load with
  a deadband, checked once the motor runs (bIsRunning) and set.tMaskAfterStart has passed (sts.tStartMaskTimeLeft: the time
  left of the mask).
- stLockedRotorFault (a locked rotor, default Off): the current still at or above its % while the motor's run
  command is on, for its delay.
- stCurrentBadFault (default a warning): the current is not good while monitoring is wanted; high / low / start checks
  then wait (they never act on a bad reading).
Pins: ipCurrentSensor (the CT, I_Measurement), ipOwner (the motor, I_Equipment, required), refData -> fCurrentPct,
bCurrentProvesRun, plus FB_Object's outputs. It adds itself to its motor on its first call; the motor evaluates it
in its own cycle and stops on a trip. A check that is acting when this rung stops being called raises PartLost.
Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_MotorCurrent EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipCurrentSensor : I_Measurement; (* the CT *)
    ipOwner : I_Equipment; (* the motor (required) *)
    refData : REFERENCE TO ST_MotorCurrentData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fCurrentPct : REAL; (* of full load (0 while not monitoring or not good) *)
    bCurrentProvesRun : BOOL; (* at or above set.fProvesRunAbovePct: wire to the motor's bFeedback for run by current *)
  END_VAR
  VAR RETAIN
    stKept : ST_MotorCurrentSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL; (* the rung ran since the owner's last Evaluate *)
    bGoodNow : BOOL; (* this scan's reading is good *)
    bMon : BOOL; (* monitoring is set up *)
    bHighNow : BOOL; (* past the level, with its deadband *)
    bLowNow : BOOL;
    bRunWas : BOOL;
    tRunSince : TIME;
    stWHigh : ST_ProtectionWork;
    stWLow : ST_ProtectionWork;
    stWStart : ST_ProtectionWork;
    stWBad : ST_ProtectionWork;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    fA : REAL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MotorCurrentSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fFullLoadCurrent >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFullLoadCurrent <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fProvesRunAbovePct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fProvesRunAbovePct <= 1000.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tMaskAfterStart >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stHighCurrentFault.fLevelPct >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stHighCurrentFault.fClearDeadbandPct >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLowCurrentFault.fLevelPct >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLowCurrentFault.fClearDeadbandPct >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLockedRotorFault.fLevelPct >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MotorCurrentSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

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
    bReset : BOOL;
    bAnyLevel : BOOL;
    bRunOk : BOOL;
    tN : TIME;
    bTrip : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (stWHigh.bActive OR stWLow.bActive OR stWStart.bActive OR stWBad.bActive) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  bReset := bResetRequest OR refData.bCmdResetFaults;
  refData.bCmdResetFaults := FALSE;
  (* how long it has run (the motor's own running, confirmed) *)
  bRunOk := ipOwner.bIsRunning;
  IF bRunOk AND NOT bRunWas THEN
    tRunSince := tN;
  END_IF;
  bRunWas := bRunOk;
  IF bRunOk AND tN - tRunSince < refData.set.tMaskAfterStart THEN
    refData.sts.tStartMaskTimeLeft := refData.set.tMaskAfterStart - (tN - tRunSince);
  ELSE
    refData.sts.tStartMaskTimeLeft := T#0s;
  END_IF;
  bAnyLevel := refData.set.stHighCurrentFault.eActionOnFault <> E_Response.Off OR refData.set.stLowCurrentFault.eActionOnFault <> E_Response.Off
               OR refData.set.stLockedRotorFault.eActionOnFault <> E_Response.Off;
  bTrip := F_Protect(tNow := tN, bConditionPresent := bMon AND bAnyLevel AND NOT bGoodNow, bResetRequest := bReset,
                     tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stCurrentBadFault, stStatus := refData.sts.stCurrentBadFault, stWorking := stWBad);
  bTrip := F_Protect(tNow := tN, bConditionPresent := bMon AND bGoodNow AND bRunOk AND tN - tRunSince >= refData.set.tMaskAfterStart
                                           AND bHighNow AND NOT bStartMaskOn,
                     bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stHighCurrentFault,
                     stStatus := refData.sts.stHighCurrentFault, stWorking := stWHigh);
  bTrip := F_Protect(tNow := tN, bConditionPresent := bMon AND bGoodNow AND bRunOk AND tN - tRunSince >= refData.set.tMaskAfterStart
                                           AND bLowNow AND NOT bStartMaskOn,
                     bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stLowCurrentFault,
                     stStatus := refData.sts.stLowCurrentFault, stWorking := stWLow);
  bTrip := F_Protect(tNow := tN, bConditionPresent := bMon AND bGoodNow AND bOwnerRunCommand
                                           AND fCurrentPct >= refData.set.stLockedRotorFault.fLevelPct,
                     bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stLockedRotorFault,
                     stStatus := refData.sts.stLockedRotorFault, stWorking := stWStart);
  IF stWStart.bTripping THEN
    eErrorId := E_UtError.StartTooLong;
    Evaluate := E_PartAction.Trip;
  ELSIF stWHigh.bTripping THEN
    eErrorId := E_UtError.CurrentHigh;
    Evaluate := E_PartAction.Trip;
  ELSIF stWLow.bTripping THEN
    eErrorId := E_UtError.CurrentLow;
    Evaluate := E_PartAction.Trip;
  ELSIF stWBad.bTripping THEN
    eErrorId := E_UtError.CurrentBad;
    Evaluate := E_PartAction.Trip;
  ELSIF stWStart.bSignalling OR stWHigh.bSignalling OR stWLow.bSignalling OR stWBad.bSignalling THEN
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.Stop;
  ELSIF stWStart.bWarning OR stWHigh.bWarning OR stWLow.bWarning OR stWBad.bWarning THEN
    IF stWStart.bWarning THEN eErrorId := E_UtError.StartTooLong;
    ELSIF stWHigh.bWarning THEN eErrorId := E_UtError.CurrentHigh;
    ELSIF stWLow.bWarning THEN eErrorId := E_UtError.CurrentLow;
    ELSE eErrorId := E_UtError.CurrentBad;
    END_IF;
    Evaluate := E_PartAction.Warn;
  ELSIF stWStart.bSettingBad OR stWHigh.bSettingBad OR stWLow.bSettingBad OR stWBad.bSettingBad THEN
    eErrorId := E_UtError.BadSetting;
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
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

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  fCurrentPct := 0.0;
  bCurrentProvesRun := FALSE;
  bError := TRUE;
  IF ipOwner = NULL THEN
    eErrorId := E_UtError.NoMotor;            // a part without an owner protects nothing
  ELSE
    eErrorId := E_UtError.NoRecord;
  END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;

(* the reading *)
fA := 0.0;
bGoodNow := FALSE;
IF ipCurrentSensor <> NULL THEN
  IF ipCurrentSensor.bIsFitted THEN
    fA := ipCurrentSensor.fActValue;
    bGoodNow := ipCurrentSensor.bIsGood AND ABS(fA) <= REAL#3.4E38;
  END_IF;
END_IF;
bMon := ipCurrentSensor <> NULL AND refData.set.fFullLoadCurrent > 0.0 AND refData.set.fFullLoadCurrent <= REAL#3.4E38;
IF bMon AND bGoodNow THEN
  fCurrentPct := fA / refData.set.fFullLoadCurrent * 100.0;
ELSE
  fCurrentPct := 0.0;
END_IF;
bCurrentProvesRun := bMon AND bGoodNow AND fCurrentPct >= refData.set.fProvesRunAbovePct;
(* the levels, with their deadbands *)
IF fCurrentPct >= refData.set.stHighCurrentFault.fLevelPct THEN
  bHighNow := TRUE;
ELSIF fCurrentPct < refData.set.stHighCurrentFault.fLevelPct - refData.set.stHighCurrentFault.fClearDeadbandPct THEN
  bHighNow := FALSE;
END_IF;
IF fCurrentPct <= refData.set.stLowCurrentFault.fLevelPct THEN
  bLowNow := TRUE;
ELSIF fCurrentPct > refData.set.stLowCurrentFault.fLevelPct + refData.set.stLowCurrentFault.fClearDeadbandPct THEN
  bLowNow := FALSE;
END_IF;
refData.sts.fCurrent := fA;
refData.sts.fCurrentPct := fCurrentPct;
refData.sts.bCurrentProvesRun := bCurrentProvesRun;

bError := stWHigh.bTripping OR stWLow.bTripping OR stWStart.bTripping OR stWBad.bTripping;
bWarning := NOT bError AND (stWHigh.bWarning OR stWLow.bWarning OR stWStart.bWarning OR stWBad.bWarning OR refData.sts.bSettingRefused);
IF stWStart.bTripping OR stWStart.bWarning THEN
  eErrorId := E_UtError.StartTooLong;
ELSIF stWHigh.bTripping OR stWHigh.bWarning THEN
  eErrorId := E_UtError.CurrentHigh;
ELSIF stWLow.bTripping OR stWLow.bWarning THEN
  eErrorId := E_UtError.CurrentLow;
ELSIF stWBad.bTripping OR stWBad.bWarning THEN
  eErrorId := E_UtError.CurrentBad;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bMon THEN
  eState := E_State.Off;
ELSIF bCurrentProvesRun THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK