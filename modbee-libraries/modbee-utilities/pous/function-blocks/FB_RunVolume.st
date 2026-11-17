(* FB_RunVolume — a volume target for a run, as a part of it (DESIGN-0.2.md section 5.8).

Pins: ipRun (the run, required), ipMeter (the meter it counts on, required), refData.
When the run starts, the meter's total is the start; the run ends Done when set.fTarget has been delivered
(0 = no target: it only watches the meter). Meter failed: while the run is running, the meter not good, or its
total not rising for set.stMeterFailed's delay, trips the run (MeterFailed). The delivered volume and what is
left are in its status.
A run with a volume target always has a safety time cap on its counted time: the target at set.fMinFlow (the
least flow expected, per hour in the meter's unit) takes at most fTarget / fMinFlow hours; with fMinFlow 0 the
cap is set.tDefaultCap (sts.bDefaultCap shows it). When the run's counted time reaches the cap before the
target, the run ends with stop reason TimeCap and the warning RunCapped (E_PartAction.Cap). The run's own
set.tMaxTime still applies: whichever is first ends the run. sts.tCap shows the cap in use. *)

FUNCTION_BLOCK FB_RunVolume EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    ipMeter : I_Meter; (* required *)
    refData : REFERENCE TO ST_RunVolumeData;
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
    fLastTotal : LREAL;
    bRose : BOOL; (* the meter's total rose on the last scan *)
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
    bTrip : BOOL;
  END_VAR
  eErrorId := E_UtError.MeterFailed;
  IF NOT __ISVALIDREF(refData) OR ipMeter = NULL THEN
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND refData.sts.stMeterFailed.eState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  (* each rise restarts the delay: meter failed = not good, or no rise, for the whole delay while running *)
  bTrip := F_Protect(tNow := TIME(), bCause := bRunning AND (NOT ipMeter.bIsGood OR NOT bRose),
                     bResetReq := bResetWanted, tRetryWindow := T#1h,
                     stSet := refData.set.stMeterFailed, stSts := refData.sts.stMeterFailed, stWork := stWork);
  IF stWork.bTrip THEN
    Evaluate := E_PartAction.Trip;
  ELSIF ipRun.bIsActive AND bActivePrev AND refData.set.fTarget > 0.0 AND refData.sts.fDelivered >= refData.set.fTarget THEN
    (* bActivePrev: its rung has seen this run start, so fDelivered is this run's *)
    Evaluate := E_PartAction.Done;
  ELSIF ipRun.bIsActive AND bActivePrev AND refData.set.fTarget > 0.0 AND refData.sts.tCap > T#0s
        AND ipRun.tActElapsed >= refData.sts.tCap THEN
    Evaluate := E_PartAction.Cap;
    eErrorId := E_UtError.RunCapped;
  ELSIF stWork.bWarn THEN
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
  bActivePrev := ipRun.bIsActive;
  fLastTotal := ipMeter.fActTotal;
  bFirstScan := FALSE;
ELSIF refData.set.fTarget >= 0.0 AND refData.set.stMeterFailed.tDelay >= T#0s AND refData.set.fMinFlow >= 0.0
      AND refData.set.fMinFlow <= REAL#3.4E38 AND refData.set.tDefaultCap > T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
END_IF;
IF NOT bAdded THEN
  ipRun.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
IF ipRun.bIsActive AND NOT bActivePrev THEN
  fStart := ipMeter.fActTotal;    // a new run
END_IF;
bActivePrev := ipRun.bIsActive;
bRose := ipMeter.fActTotal > fLastTotal;
fLastTotal := ipMeter.fActTotal;
IF ipRun.bIsActive THEN
  refData.sts.fDelivered := ipMeter.fActTotal - fStart;
  IF refData.set.fTarget > refData.sts.fDelivered THEN
    refData.sts.fLeft := refData.set.fTarget - refData.sts.fDelivered;
  ELSE
    refData.sts.fLeft := 0.0;
  END_IF;
END_IF;
(* the safety time cap of a volume target *)
refData.sts.bDefaultCap := FALSE;
refData.sts.tCap := T#0s;
IF refData.set.fTarget > 0.0 THEN
  IF refData.set.fMinFlow > 0.0 THEN
    fCapMs := refData.set.fTarget * 3600000.0 / REAL_TO_LREAL(refData.set.fMinFlow);
    IF fCapMs < 10.0 THEN fCapMs := 10.0; END_IF;
    IF fCapMs > 8.64E7 * 365.0 THEN fCapMs := 8.64E7 * 365.0; END_IF;
    refData.sts.tCap := LINT_TO_TIME(LREAL_TO_LINT(fCapMs));
  ELSE
    refData.sts.tCap := refData.set.tDefaultCap;
    refData.sts.bDefaultCap := TRUE;
  END_IF;
END_IF;
bCalled := TRUE;
bError := stWork.bTrip;
bWarning := stWork.bWarn;
IF bError OR bWarning THEN eErrorId := E_UtError.MeterFailed; ELSE eErrorId := E_UtError.None; END_IF;

END_FUNCTION_BLOCK