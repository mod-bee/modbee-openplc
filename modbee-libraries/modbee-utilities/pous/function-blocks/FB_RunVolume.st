(* FB_RunVolume — a volume target for a run, as a part of it.

Pins: ipRun (the run, required), ipMeter (the meter it counts on, required), refData.
When the run starts (a restart too: ipRun.nActRunId changes), the meter's total is the start; the run ends Done when set.fVolumeSetpoint has been delivered
(0 = no target: it only watches the meter). Meter failed: while the run is running, the meter not good, or its
total not rising for set.stMeterFailedFault's delay, trips the run (MeterFailed). The delivered volume and what is
left are in its status.
A run with a volume target always has a safety time cap on its counted time: the target at set.fMinExpectedFlow (the
least flow expected, per hour in the meter's unit) takes at most fVolumeSetpoint / fMinExpectedFlow hours; with fMinExpectedFlow 0 the
cap is set.tDefaultTimeCap (sts.bDefaultTimeCapInUse shows it). When the run's counted time reaches the cap before the
target, the run ends with stop reason TimeCap and the warning RunCapped (E_PartAction.Cap). The run's own
set.tMaxTimeFromStart still applies: whichever is first ends the run. sts.tTimeCapInUse shows the cap in use.
A bad settings write is put back (sts.bSettingRefused / sts.eSettingRefusedErrorId) and warns its owner (SettingRefused) until the
run's reset. *)

FUNCTION_BLOCK FB_RunVolume EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    ipMeter : I_Meter; (* required *)
    refData : REFERENCE TO ST_RunVolumeData; (* the block's record *)
  END_VAR
  VAR RETAIN
    stKept : ST_RunVolumeSet;
    nKeptLayout : UINT;
    fStart : LREAL; (* the meter's total at the run's start (a run goes on over a power cut) *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR_TEMP
    fCapMs : LREAL;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bActivePrev : BOOL;
    nRunSeen : UDINT; (* ipRun.nActRunId when its rung last ran *)
    fLastTotal : LREAL;
    bRose : BOOL; (* the meter's total rose on the last scan *)
    stWork : ST_ProtectionWork;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.fVolumeSetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.stMeterFailedFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fMinExpectedFlow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMinExpectedFlow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tDefaultTimeCap > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
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
    bTrip : BOOL;
  END_VAR
  eErrorId := E_UtError.MeterFailed;
  IF NOT __ISVALIDREF(refData) OR ipMeter = NULL THEN
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND refData.sts.stMeterFailedFault.eFaultState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF bResetRequest THEN
    refData.sts.bSettingRefused := FALSE;
    refData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  (* each rise restarts the delay: meter failed = not good, or no rise, for the whole delay while running *)
  bTrip := F_Protect(tNow := TIME(), bConditionPresent := bOwnerRunCommand AND (NOT ipMeter.bIsGood OR NOT bRose),
                     bResetRequest := bResetRequest, tRetryCountWindow := refData.set.tRetryCountWindow,
                     stSettings := refData.set.stMeterFailedFault, stStatus := refData.sts.stMeterFailedFault, stWorking := stWork);
  IF stWork.bTripping THEN
    Evaluate := E_PartAction.Trip;
  ELSIF ipRun.bIsBusy AND bActivePrev AND nRunSeen = ipRun.nActRunId AND refData.set.fVolumeSetpoint > 0.0
        AND refData.sts.fDeliveredThisRun >= refData.set.fVolumeSetpoint THEN
    (* bActiveLastScan, nRunSeen: its rung has seen this run start, so fDeliveredThisRun is this run's *)
    Evaluate := E_PartAction.Done;
  ELSIF ipRun.bIsBusy AND bActivePrev AND nRunSeen = ipRun.nActRunId AND refData.set.fVolumeSetpoint > 0.0
        AND refData.sts.tTimeCapInUse > T#0s
        AND ipRun.tActElapsed >= refData.sts.tTimeCapInUse THEN
    Evaluate := E_PartAction.Cap;
    eErrorId := E_UtError.RunCapped;
  ELSIF stWork.bWarning THEN
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

IF NOT __ISVALIDREF(refData) OR ipRun = NULL OR ipMeter = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    fStart := ipMeter.fActTotal;
    nKeptLayout := cLayout;
  END_IF;
  bActivePrev := ipRun.bIsBusy;
  nRunSeen := ipRun.nActRunId;
  fLastTotal := ipMeter.fActTotal;
  bFirstScan := FALSE;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipRun.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
IF ipRun.bIsBusy AND (NOT bActivePrev OR ipRun.nActRunId <> nRunSeen) THEN
  fStart := ipMeter.fActTotal;    // a new run, or a restart
END_IF;
bActivePrev := ipRun.bIsBusy;
nRunSeen := ipRun.nActRunId;
bRose := ipMeter.fActTotal > fLastTotal;
fLastTotal := ipMeter.fActTotal;
IF ipRun.bIsBusy THEN
  refData.sts.fDeliveredThisRun := ipMeter.fActTotal - fStart;
  IF refData.set.fVolumeSetpoint > refData.sts.fDeliveredThisRun THEN
    refData.sts.fVolumeLeft := refData.set.fVolumeSetpoint - refData.sts.fDeliveredThisRun;
  ELSE
    refData.sts.fVolumeLeft := 0.0;
  END_IF;
END_IF;
(* the safety time cap of a volume target *)
refData.sts.bDefaultTimeCapInUse := FALSE;
refData.sts.tTimeCapInUse := T#0s;
IF refData.set.fVolumeSetpoint > 0.0 THEN
  IF refData.set.fMinExpectedFlow > 0.0 THEN
    fCapMs := refData.set.fVolumeSetpoint * 3600000.0 / REAL_TO_LREAL(refData.set.fMinExpectedFlow);
    IF fCapMs < 10.0 THEN fCapMs := 10.0; END_IF;
    IF fCapMs > 8.64E7 * 365.0 THEN fCapMs := 8.64E7 * 365.0; END_IF;
    refData.sts.tTimeCapInUse := LINT_TO_TIME(LREAL_TO_LINT(fCapMs));
  ELSE
    refData.sts.tTimeCapInUse := refData.set.tDefaultTimeCap;
    refData.sts.bDefaultTimeCapInUse := TRUE;
  END_IF;
END_IF;
bCalled := TRUE;
bError := stWork.bTripping;
bWarning := stWork.bWarning OR refData.sts.bSettingRefused;
IF bError OR stWork.bWarning THEN
  eErrorId := E_UtError.MeterFailed;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;

END_FUNCTION_BLOCK