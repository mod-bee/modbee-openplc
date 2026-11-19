(* FB_LevelControl — keeps a level by driving a pump.

Pins: bEnable (the process may run: e.g. the system not Off), bDemand (pump down / fill now, past the start
level, to set.fDemandStopLevel), bInterlock (FALSE: nothing is requested), ipLevel (the level: a transmitter, a
vessel), ipEquipment (the pump it drives), fSpeedSetpointPct (the speed asked of the target while it asks, e.g. for VSD pumps;
< 0 = the target's own), plus FB_Object's outputs. refData: its record.
-> bEquipmentRunning (it asks and the pump runs), bLevelCalls (the level calls for pumping), bAtStopLevel (at or past the stop
level), bHighHigh, bLowLow.
EMPTY (sump, wet well): start at or above fStartLevel, stop at or below fStopLevel; bDemand runs it down to fDemandStopLevel;
at or above fHighHighLevel it always runs (overflow), also with bRunOnDemandOnly; at or below fLowLowLevel it never runs.
FILL (tank): start at or below fStartLevel, stop at or above fStopLevel; bDemand fills to fDemandStopLevel; at or above
fHighHighLevel it never runs (full); fLowLowLevel is an alarm level only.
TIMED: no level needed (ipLevel may be unwired): on for set.tOnTime, off for set.tOffTime, over and over (on first),
while bEnable.
set.fStartLevelVariation: the start level moves at random by up to this, either way, after each cycle (fat build-up
in a sump; used only when smaller than the start-stop gap). A held bDemand that reached set.fDemandStopLevel runs
again when the level is back at set.fDemandRestartLevel (0 = the start level). -> bDemandActive (for FB_Stages'
demand pumps).
bRunOnDemandOnly: the start / stop levels are not used, it runs on bDemand only (the high-high still acts in
EMPTY). A bad level is ridden through for its protection delay (the request held), then set.eWhenLevelBad:
Stop or RunOn (keeps the request as it was, for at most set.tMaxRunOnTime, then stops).
Parts (FB_LevelCheck, FB_Protection): a trip stops the request; a signal pauses it (source low, no flow);
its parts: float backup (FB_LevelFloats), cleaning (FB_SumpClean), exercise (FB_Exercise), booster (FB_Booster),
level checks (FB_LevelCheck); beside it: stages (FB_Stages -> FB_Group.nExtraMembers), the inflow estimate
(FB_VesselFlow). tot.nCycleCount counts each new call for pumping (kept over a power cut; bCmdResetTotals clears it).
No pump: while it asks and its target is neither available nor running (a pump or its motor in Hand or Off,
faulted, every group member out), it is in fault: bError, eErrorId NoneAvailable (a run it serves can end on
it, e.g. bInterlock := NOT fbStation.bError). It clears by itself when the target is available again.
Detail (det): tTimeLeft (RunOn: the run-on left under set.tMaxRunOnTime; TIMED: the on or off time left; else 0),
tInPhaseFor (since its request last changed: pumping or idle). *)

FUNCTION_BLOCK FB_LevelControl EXTENDS FB_Object IMPLEMENTS I_LevelControl
  VAR_INPUT
    bEnable : BOOL; (* the process may run (e.g. the system not Off) *)
    bDemand : BOOL; (* pump down / fill now, past the start level, to fDemandStopLevel *)
    bInterlock : BOOL := TRUE; (* FALSE: nothing is requested *)
    ipLevel : I_Measurement; (* required *)
    ipEquipment : I_Equipment; (* required *)
    fSpeedSetpointPct : REAL := -1.0; (* the speed asked of the target (< 0 = its own) *)
    refData : REFERENCE TO ST_LevelControlData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bEquipmentRunning : BOOL; (* it asks and the pump runs *)
    bLevelCalls : BOOL; (* the level calls for pumping *)
    bAtStopLevel : BOOL; (* at or past the stop level *)
    bHighHigh : BOOL; (* at or past the high-high level *)
    bLowLow : BOOL; (* at or past the low-low level *)
    bDemandActive : BOOL; (* a demand is running (-> FB_Stages bDemand) *)
  END_VAR
  VAR RETAIN
    stKept : ST_LevelControlSet;
    nKeptLayout : UINT;
    stKeptTot : ST_LevelControlTot; (* kept at each cycle and reset *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWLevelBad : ST_ProtectionWork;
    bDemandLatch : BOOL; (* a demand runs until its level *)
    bDemandPrev : BOOL;
    bReq : BOOL;
    bCycleWas : BOOL; (* the request last scan, for the cycle count *)
    fLevel : REAL;
    nRng : UDINT; (* the start variation's random numbers *)
    fOffset : REAL;
    bReqWas : BOOL;
    bFailedWas : BOOL;
    tFailedAt : TIME;
    bDemandWait : BOOL; (* a held demand reached its level: waits for the restart level *)
    bCycOn : BOOL; (* TIMED *)
    tCycAt : TIME;
    tPhaseSince : TIME; (* the request last changed *)
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bNoneAvail : BOOL; (* asked, and the target is neither available nor running *)
    bGood : BOOL;
    bFailed : BOOL;
    bEmpty : BOOL;
    bTrip : BOOL;
    bReached : BOOL;
    bTimed : BOOL;
    bRecovered : BOOL;
    bDemandHeld : BOOL;
    fStartNow : REAL;
    fRestart : REAL;
  END_VAR


PROPERTY PUBLIC fActHighHighLevel : REAL    // the high-high level in use
  GET
    IF __ISVALIDREF(refData) THEN fActHighHighLevel := refData.set.fHighHighLevel; ELSE fActHighHighLevel := 3.4E38; END_IF;
  END_GET
END_PROPERTY

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.stLevelBadFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stLevelBadFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.tMaxRunOnTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fStartLevelVariation >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fStartLevelVariation <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (ABS(refData.set.fDemandRestartLevel) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.eControlMode <> E_LevelMode.Timed
             OR (refData.set.tOnTime > T#0s AND refData.set.tOffTime >= T#0s)) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.bRunOnDemandOnly OR refData.set.eControlMode = E_LevelMode.Timed
             OR (refData.set.eControlMode = E_LevelMode.Empty AND refData.set.fStartLevel > refData.set.fStopLevel)
             OR (refData.set.eControlMode = E_LevelMode.Fill AND refData.set.fStartLevel < refData.set.fStopLevel)) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

bTimed := FALSE;
IF __ISVALIDREF(refData) THEN
  bTimed := refData.set.eControlMode = E_LevelMode.Timed;
END_IF;
IF NOT __ISVALIDREF(refData) OR (ipLevel = NULL AND NOT bTimed) OR ipEquipment = NULL THEN
  bEquipmentRunning := FALSE;
  bDemandActive := FALSE;
  bError := TRUE;
  IF ipEquipment = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  nRng := DWORD_TO_UDINT(DWORD#16#2545F491 XOR UDINT_TO_DWORD(LINT_TO_UDINT(TIME_TO_LINT(tNow))));
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
bReset := SystemReset() OR refData.bCmdResetFaults;
IF refData.bCmdResetFaults THEN
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bEmpty := refData.set.eControlMode = E_LevelMode.Empty;

(* the level: ridden through while bad for its delay, then eWhenLevelBad *)
bGood := bTimed;
IF ipLevel <> NULL THEN
  IF ipLevel.bIsFitted AND ipLevel.bHasValue AND ipLevel.bIsGood THEN
    bGood := TRUE;
    fLevel := ipLevel.fActValue;
  END_IF;
END_IF;
bTrip := F_Protect(tNow := tNow, bConditionPresent := NOT bGood, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stLevelBadFault, stStatus := refData.sts.stLevelBadFault, stWorking := stWLevelBad);
bFailed := stWLevelBad.bActive;
IF bFailed AND NOT bFailedWas THEN
  tFailedAt := tNow;
END_IF;
bFailedWas := bFailed;

(* the start in use: moved at random after each cycle *)
IF bReqWas AND NOT bReq THEN
  nRng := nRng * 1103515245 + 12345;
  IF refData.set.fStartLevelVariation > 0.0 AND refData.set.fStartLevelVariation < ABS(refData.set.fStartLevel - refData.set.fStopLevel) THEN
    fOffset := (UDINT_TO_REAL((nRng / 65536) MOD 32768) / 16383.5 - 1.0) * refData.set.fStartLevelVariation;
  ELSE
    fOffset := 0.0;
  END_IF;
END_IF;
IF refData.set.fStartLevelVariation <= 0.0 THEN
  fOffset := 0.0;
END_IF;
bReqWas := bReq;
fStartNow := refData.set.fStartLevel + fOffset;

(* levels *)
IF bEmpty THEN
  bHighHigh := fLevel >= refData.set.fHighHighLevel;
  bLowLow := fLevel <= refData.set.fLowLowLevel;
  bAtStopLevel := fLevel <= refData.set.fStopLevel;
  IF fLevel >= fStartNow THEN
    bLevelCalls := TRUE;
  ELSIF bAtStopLevel THEN
    bLevelCalls := FALSE;
  END_IF;
ELSE
  bHighHigh := fLevel >= refData.set.fHighHighLevel;
  bLowLow := fLevel <= refData.set.fLowLowLevel;
  bAtStopLevel := fLevel >= refData.set.fStopLevel;
  IF fLevel <= fStartNow THEN
    bLevelCalls := TRUE;
  ELSIF bAtStopLevel THEN
    bLevelCalls := FALSE;
  END_IF;
END_IF;
IF refData.set.bRunOnDemandOnly THEN
  bLevelCalls := FALSE;
END_IF;
IF bTimed THEN
  bHighHigh := FALSE;
  bLowLow := FALSE;
  bAtStopLevel := FALSE;
  IF NOT bEnable OR NOT bInterlock THEN
    bCycOn := TRUE;                 (* on first, when it may run again *)
    tCycAt := tNow;
  ELSIF bCycOn AND tNow - tCycAt >= refData.set.tOnTime AND refData.set.tOffTime > T#0s THEN
    bCycOn := FALSE;
    tCycAt := tNow;
  ELSIF NOT bCycOn AND tNow - tCycAt >= refData.set.tOffTime THEN
    bCycOn := TRUE;
    tCycAt := tNow;
  END_IF;
  bLevelCalls := bCycOn;
END_IF;

(* demand: the pin's rising edge or the record's command latches it until its level *)
IF (bDemand AND NOT bDemandPrev) OR refData.bCmdDemand THEN
  bDemandLatch := TRUE;
  refData.bCmdDemand := FALSE;
END_IF;
bDemandPrev := bDemand;
IF refData.bCmdEndDemand THEN
  bDemandLatch := FALSE;
  refData.bCmdEndDemand := FALSE;
END_IF;
bReached := NOT bTimed AND ((bEmpty AND fLevel <= refData.set.fDemandStopLevel) OR (NOT bEmpty AND fLevel >= refData.set.fDemandStopLevel));
(* a held demand: runs to its level, then waits for the restart level *)
fRestart := refData.set.fDemandRestartLevel;
IF fRestart = 0.0 THEN
  fRestart := fStartNow;
END_IF;
bRecovered := (bEmpty AND fLevel >= fRestart) OR (NOT bEmpty AND fLevel <= fRestart);
IF NOT bDemand THEN
  bDemandWait := FALSE;
ELSIF bReached THEN
  bDemandWait := TRUE;
ELSIF bDemandWait AND bRecovered THEN
  bDemandWait := FALSE;
END_IF;
bDemandHeld := bDemand AND NOT bReached AND NOT bDemandWait;
IF bDemandLatch AND NOT bFailed AND bReached THEN
  bDemandLatch := FALSE;          // the demand level is reached
END_IF;

(* parts *)
EvaluateParts(bRunning := bReq AND ipEquipment.bIsRunning, bResetWanted := bReset, bMasked := FALSE);

(* the request *)
IF NOT bFailed THEN
  bReq := bLevelCalls OR bDemandLatch OR bDemandHeld;
  IF bEmpty AND bHighHigh THEN
    bReq := TRUE;                 // overflow: always runs
  END_IF;
  IF bPartRun OR bPartRequest THEN
    bReq := TRUE;                 // a part asks it to run (the float backup; an exercise, a clean)
  END_IF;
  IF bEmpty AND bLowLow THEN
    bReq := FALSE;                // cut-out
  END_IF;
  IF NOT bEmpty AND bHighHigh THEN
    bReq := FALSE;                // full
  END_IF;
ELSIF bPartRun THEN
  bReq := TRUE;                   // the float backup runs it while the level is bad
ELSIF refData.set.eWhenLevelBad = E_LevelFail.Stop THEN
  bReq := FALSE;
ELSIF refData.set.tMaxRunOnTime > T#0s AND tNow - tFailedAt >= refData.set.tMaxRunOnTime THEN
  bReq := FALSE;                  // RunOn: as it was, for at most tMaxRunOnTime
END_IF;
IF NOT bEnable OR NOT bInterlock OR bPartTrip OR bPartStop THEN
  bReq := FALSE;
END_IF;
IF bPartHold AND NOT ipEquipment.bIsRunning THEN
  bReq := FALSE;                  // no new start
END_IF;
ipEquipment.Request(bRun := bReq, bHoldOff := FALSE, fSpeedSetpointPct := fSpeedSetpointPct,
                 bOverflowUrgent := bReq AND ((bEmpty AND bHighHigh) OR bPartRun));

(* the cycle count: each new call for pumping *)
IF bReq <> bCycleWas THEN
  tPhaseSince := tNow;
END_IF;
IF bReq AND NOT bCycleWas THEN
  refData.tot.nCycleCount := refData.tot.nCycleCount + 1;
  stKeptTot := refData.tot;
END_IF;
bCycleWas := bReq;
IF refData.bCmdResetTotals THEN
  refData.tot.nCycleCount := 0;
  stKeptTot := refData.tot;
  refData.bCmdResetTotals := FALSE;
END_IF;
bEquipmentRunning := bReq AND ipEquipment.bIsRunning;

(* status *)
bNoneAvail := bReq AND NOT ipEquipment.bIsAvailable AND NOT ipEquipment.bIsRunning;
bError := bPartTrip OR stWLevelBad.bTripping OR bNoneAvail;
bWarning := bPartWarn OR stWLevelBad.bWarning OR refData.sts.bSettingRefused;
IF bPartTrip THEN
  eErrorId := ePartTrip;
ELSIF stWLevelBad.bTripping THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bNoneAvail THEN
  eErrorId := E_UtError.NoneAvailable;
ELSIF stWLevelBad.bWarning THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bPartWarn THEN
  eErrorId := ePartWarn;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF NOT bEnable THEN
  eState := E_State.Off;
ELSIF bError THEN
  eState := E_State.Fault;
ELSIF NOT bInterlock OR bPartStop THEN
  eState := E_State.Held;
ELSIF bEquipmentRunning THEN
  eState := E_State.Running;
ELSIF bReq THEN
  eState := E_State.Starting;
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.bLevelCalls := bLevelCalls;
bDemandActive := bDemandLatch OR bDemandHeld;
refData.sts.bDemandActive := bDemandActive;
refData.sts.fStartLevelInUse := fStartNow;
refData.sts.bRunningOnBadLevel := bFailed AND bReq AND NOT bPartRun AND refData.set.eWhenLevelBad = E_LevelFail.RunOn;
refData.sts.bAtStopLevel := bAtStopLevel;
refData.sts.bHighHigh := bHighHigh;
refData.sts.bLowLow := bLowLow;
refData.sts.bRunCommand := bReq;
refData.det.tInPhaseFor := tNow - tPhaseSince;
refData.det.tTimeLeft := T#0s;
IF refData.sts.bRunningOnBadLevel AND refData.set.tMaxRunOnTime > T#0s THEN
  refData.det.tTimeLeft := MAX(T#0s, refData.set.tMaxRunOnTime - (tNow - tFailedAt));
ELSIF bTimed AND bEnable AND bInterlock THEN
  IF bCycOn THEN
    refData.det.tTimeLeft := MAX(T#0s, refData.set.tOnTime - (tNow - tCycAt));
  ELSE
    refData.det.tTimeLeft := MAX(T#0s, refData.set.tOffTime - (tNow - tCycAt));
  END_IF;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK