(* FB_SpeedLoop — constant pressure / flow / level with a speed drive. It owns its pump: while asked to run it
requests the pump (an FB_Pump on an FB_MotorVsd, an FB_MotorVsd, or an FB_Group) at the speed that holds the value
at the setpoint.

Pins: bRun (control wanted), ipProcessValue (the pressure or level; stHighProcessValueFault always watches it), ipFlow (the flow: Flow
control, the flow limit, sleep on low flow; unwired = none), ipEquipment (the pump it drives), fSetpoint (the setpoint
while set.eSetpointFrom = Pin), nSetpointPreset (0 Normal, 1 Low, 2 High while wired; -1 = the kept set.eSetpointPreset),
fExternalSpeedPct (the speed of an external PID while set.eSpeedFrom = External; < 0 = not wired), bAddPumpPossible (an
owner can still add a pump: stLowAtMaxSpeedFault waits until it cannot), refData -> fSpeedSetpointPct (the speed asked, %),
bEquipmentRunning (the pump runs), bAtSetpoint, bPipeFilled, fShortOfSetpoint, bAtMaxSpeed, bAtMinSpeed, eLoopPhase, bAddPumpNeeded, bDropPumpNeeded, plus
FB_Object's outputs.

What the speed follows (set.eControlBy): Pv, the PID on ipProcessValue; Flow, the PID on ipFlow; Fixed, a fixed speed (no
PID; a bad sensor does not stop it). Presets Normal / Low / High: Pv set.fSetpoint / fSetpointLow / fSetpointHigh, Flow
set.fFlowSetpoint / fFlowSetpointLow / fFlowSetpointHigh, Fixed set.fFixedSpeedPct / fFixedSpeedLowPct / fFixedSpeedHighPct (a Low or High
setpoint of 0 uses the Normal one). Pv control takes its setpoint from the record (set.eSetpointFrom = Record) or
the fSetpoint pin (Pin). A setpoint in use of 0 (or not a number), a missing measurement or a missing fExternalSpeedPct is a
configuration fault while bRun: no run.
    speed = fKp * (e + 1/tTi * integral(e dt) + tTd * de/dt)      (% speed)
e = sp - value (set.bReverseActing: value - sp, for a level emptied by the pump); inside set.fDeadband e = 0.
Anti-windup: the integral stays inside the output limits and stops while a limit or the rate limit holds the
output. Bumpless: whenever the loop takes the output back (a start, the end of manual, fallback or a fill),
the integral is loaded from the speed it has. A start begins at set.fStartSpeedPct (limited to the speed range:
0 = set.fMinSpeedPct). set.fMaxSpeedChangeRate limits the output change (% per set.eRateUnit, 0 = no limit); set.fSetpointRampRate
ramps the setpoint (units per set.eRateUnit, 0 = a step). set.eSpeedFrom = External: the speed follows fExternalSpeedPct
(held at the last value while it is not a number), with the same limits, protections and sleep.
Manual (the record's bCmdSelectManual / bCmdSelectAuto, kept in set.bManualSelected): set.fManualSpeedPct; the protections still act.

Phases (eLoopPhase): Idle -> Filling (optional) -> Control -> Boost -> Sleep -> Control; Fallback at a fixed speed
after a hunting trip or with a failed sensor; Manual at the manual (or Fixed control's) speed.
Pipe fill (set.stPipeFill; Pv control, not reverse acting): eFillMode Fixed runs at fSpeedSetpointPct until the value reaches
fFilledAbove (0 = 90 % of the setpoint); Ramp raises the setpoint from the value at fSetpointRiseRate (per set.eRateUnit) to the
setpoint. A fill longer than stFillTimeoutFault's delay acts per stFillTimeoutFault (FillTimeout). After a manual or fallback
spell the fill runs again only if the line has not been full in this run. bPipeFilled: the line is full.
Sleep (set.stSleep.bSleepAllowed): satisfied (within fAtSetpointBand of the setpoint, or past it) at or below fSpeedSetpointPct, or
with the flow below fSleepBelowFlow (0 = not used), for tSleepDelay: the setpoint is raised by fBoostPctOfSetpoint % for tBoostTime, then
the pump stops (eState Waiting). It wakes when the value is fWakeWhenShortBy short of the setpoint for tWakeDelay,
after at least tMinSleepTime.
Flow limit (set.fMaxFlow, 0 = off): the speed is brought down to hold the flow below it (sts.bFlowLimiting).
Protections (each a ST_ProtectionSet: off / warn / trip / signal, delay, reset; F_Protect):
  stHighProcessValueFault       Pv above set.fHighProcessValueAbove (0 = off; clears set.fHighProcessValueDeadband below it): a trip stops the pump
                 (PressureHigh); a warning holds the minimum speed while it lasts.
  stLowAtMaxSpeedFault     the value below set.fLowAtMaxSpeedBelow (0 = half the setpoint, direct acting only) at the top speed in
                 control, while no more pump can be added (bAddPumpPossible FALSE): a burst main (LowAtMax).
  stPipeFill.stFillTimeoutFault  the pipe fill took too long (FillTimeout).
  stSetpointNotReachedFault  in control, not at a speed limit, the value outside fAtSetpointBand of the setpoint (NotReaching).
  stHuntingFault      more than set.nMaxCrossings (1..15) crossings of the setpoint (each a swing beyond fMinSwing) in
                 set.tHuntWindow (0 = off) (Hunting): a trip runs at set.fFallbackSpeedPct (Fallback) until reset.
A bad or unfitted measurement under control: the speed is held at once; past set.stProcessValueBadFault's delay set.eWhenValueBad
Hold (the last speed; a sleeping pump stays asleep), Substitute (set.fFallbackSpeedPct) or Stop (SensorBad). Control
resumes when stProcessValueBadFault clears (its tAutoRecoverAfter: the sensor good this long).
Restart: after a reset that was needed (Manual reset, or a Retry lockout) the loop waits for bRun to cycle,
unless set.bRestartAfterReset.
bAtSetpoint: in control, boost or sleep, the value within set.fAtSetpointBand of the setpoint in use.
fShortOfSetpoint: how far the value is short of the setpoint (set.bReverseActing: above it), 0 when not good; with Fixed
control Pv against the setpoint in use (0 when that is 0), for a fixed-speed set staged on bands; with
bAtMaxSpeed (at the top of the speed range, not held by the flow limit) and bAtMinSpeed it feeds FB_Cascade's staging.
bAddPumpNeeded: in control at the top speed and short of the setpoint by more than fAtSetpointBand for set.tAddOrDropPumpDelay;
bDropPumpNeeded: in control at the minimum speed for set.tAddOrDropPumpDelay (hints for an owner adding or dropping pumps;
a highPv warning stops both). bPipeFilled can drive a pump's prime-done input; stLowAtMaxSpeedFault is the lost-prime check.
Detail (det): the PID's parts fP / fI / fD (% speed) and tInPhaseFor (time in the present phase).
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back
(sts.bSettingRefused / eSettingRefusedErrorId, a warning until a reset). *)

FUNCTION_BLOCK FB_SpeedLoop EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL; (* control wanted *)
    ipProcessValue : I_Measurement; (* Pv control, stHighProcessValueFault (Flow / Fixed control: may be unwired) *)
    ipFlow : I_Measurement; (* Flow control, flow limit, sleep on flow (unwired = none) *)
    ipEquipment : I_Equipment; (* required *)
    fSetpoint : REAL; (* the setpoint while set.eSetpointFrom = Pin *)
    nSetpointPreset : INT := -1; (* 0 Normal, 1 Low, 2 High while wired; -1 = the kept set.eSetpointPreset *)
    fExternalSpeedPct : REAL := -1.0; (* External: the speed, %; < 0 = not wired *)
    bAddPumpPossible : BOOL; (* an owner can still add a pump: stLowAtMaxSpeedFault waits *)
    refData : REFERENCE TO ST_SpeedLoopData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fSpeedSetpointPct : REAL; (* the speed asked, % *)
    bEquipmentRunning : BOOL; (* the pump runs *)
    bAtSetpoint : BOOL; (* within fAtSetpointBand of the setpoint *)
    bPipeFilled : BOOL; (* the pipe fill is done in this run *)
    fShortOfSetpoint : REAL; (* short of the setpoint by (direction applied; 0 when not good) *)
    bAtMaxSpeed : BOOL; (* at the top speed, not held by the flow limit *)
    bAtMinSpeed : BOOL; (* at the minimum speed *)
    eLoopPhase : E_LoopPhase; (* the phase now *)
    bAddPumpNeeded : BOOL; (* at the top speed and short of the setpoint for set.tAddOrDropPumpDelay *)
    bDropPumpNeeded : BOOL; (* at the minimum speed for set.tAddOrDropPumpDelay *)
  END_VAR
  VAR RETAIN
    stKept : ST_SpeedLoopSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWPvBad : ST_ProtectionWork;
    stWHigh : ST_ProtectionWork;
    stWLow : ST_ProtectionWork;
    stWFill : ST_ProtectionWork;
    stWReach : ST_ProtectionWork;
    stWHunt : ST_ProtectionWork;
    fbSpRamp : FB_Ramp;
    fbFillRamp : FB_Ramp;
    tLast : TIME;
    fSpd : LREAL; (* the speed now *)
    fI : LREAL; (* the integral part *)
    fErrPrev : LREAL;
    bPreload : BOOL; (* bumpless: load the integral from the speed next time *)
    fFlowCap : LREAL;
    fHoldSpeed : LREAL;
    fExtHeld : LREAL;
    fSpAct : REAL;
    fSpBoost : REAL;
    bFilledRun : BOOL;
    bMustCycle : BOOL;
    bHighOn : BOOL;
    bHi : BOOL; (* last scan: at the top limit *)
    bLo : BOOL; (* last scan: at the bottom limit *)
    bOverride : BOOL; (* last scan: a highPv warning holds the minimum *)
    tSleepSince : TIME;
    tBoostStart : TIME;
    tSleepStart : TIME;
    tWakeSince : TIME;
    nHuntSide : INT;
    nHuntCur : INT;
    nHuntPrev : INT;
    tHuntAt : TIME;
    tHuntLast : TIME;
    tPhaseSince : TIME;
    ePhasePrev : E_LoopPhase;
    tMoreSince : TIME;
    tLessSince : TIME;
  END_VAR
  VAR_TEMP
    fDt : LREAL;
    fPerS : LREAL;
    fRateS : LREAL;
    fStepMax : LREAL;
    fCapRate : LREAL;
    fLoS : LREAL;
    fHiS : LREAL;
    fE : LREAL;
    fP : LREAL;
    fD : LREAL;
    fDi : LREAL;
    fCand : LREAL;
    fWant : LREAL;
    fTiS : LREAL;
    fTdS : LREAL;
    fCv : REAL;
    fPvV : REAL;
    fFlowV : REAL;
    fErrT : REAL;
    fSpTarget : REAL;
    fFillTarget : REAL;
    fUse : REAL;
    fLowSp : REAL;
    fHb : REAL;
    eUse : E_LoopPreset;
    ePrev : E_LoopPhase;
    bCvGood : BOOL;
    bPvOk : BOOL;
    bFlowOk : BOOL;
    bPvAlarm : BOOL;
    bCfgBad : BOOL;
    bFixedOn : BOOL;
    bDriveOn : BOOL;
    bSatisfied : BOOL;
    bTripStop : BOOL;
    bLowOn : BOOL;
    bReq : BOOL;
    bAsk : BOOL;
    bX : BOOL;
    bResetReq : BOOL;
    bTargetRuns : BOOL;
    eCfgId : E_UtError;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.fMinSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMaxSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMinSpeedPct <= refData.set.fMaxSpeedPct) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (refData.set.fKp >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tTi >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tTd >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fSetpointRampRate >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fManualSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fManualSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fFallbackSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fFallbackSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fSetpoint = refData.set.fSetpoint) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fSetpointLow = refData.set.fSetpointLow) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fSetpointHigh = refData.set.fSetpointHigh) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fFlowSetpoint = refData.set.fFlowSetpoint) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fFlowSetpointLow = refData.set.fFlowSetpointLow) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fFlowSetpointHigh = refData.set.fFlowSetpointHigh) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fFixedSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fFixedSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fFixedSpeedLowPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fFixedSpeedLowPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fFixedSpeedHighPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fFixedSpeedHighPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fDeadband >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fStartSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fStartSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMaxSpeedChangeRate >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fAtSetpointBand >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.stPipeFill.fFillSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stPipeFill.fFillSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stPipeFill.fFilledAbove >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stPipeFill.fSetpointRiseRate >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fSleepBelowSpeedPct >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fSleepBelowSpeedPct <= REAL#100.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fSleepBelowFlow >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fWakeWhenShortBy >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fBoostPctOfSetpoint >= REAL#0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.fBoostPctOfSetpoint <= REAL#100.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.tSleepDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.tBoostTime >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.tWakeDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stSleep.tMinSleepTime >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fMaxFlow >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fHighProcessValueDeadband >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fHighProcessValueAbove = refData.set.fHighProcessValueAbove) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.fLowAtMaxSpeedBelow = refData.set.fLowAtMaxSpeedBelow) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.nMaxCrossings >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nMaxCrossings <= 15) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tHuntWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fMinSwing >= REAL#0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tAddOrDropPumpDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.eWhenValueBad = E_OnBadValue.Hold OR refData.set.eWhenValueBad = E_OnBadValue.Substitute
             OR refData.set.eWhenValueBad = E_OnBadValue.Stop) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipEquipment = NULL THEN
  fSpeedSetpointPct := REAL#0.0;
  bEquipmentRunning := FALSE;
  bError := TRUE;
  IF ipEquipment = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  tLast := tNow;
  tHuntAt := tNow;
  tHuntLast := tNow;
  fSpAct := refData.set.fSetpoint;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF refData.bCmdSelectManual THEN refData.set.bManualSelected := TRUE; refData.bCmdSelectManual := FALSE; END_IF;
IF refData.bCmdSelectAuto THEN refData.set.bManualSelected := FALSE; refData.bCmdSelectAuto := FALSE; END_IF;
bResetReq := refData.bCmdResetFaults OR SystemReset();
IF refData.bCmdResetFaults THEN refData.sts.bSettingRefused := FALSE; END_IF;
refData.bCmdResetFaults := FALSE;
fDt := TIME_TO_LREAL(tNow - tLast) / 1000.0;
IF fDt < 0.0 THEN fDt := 0.0; END_IF;
tLast := tNow;
CASE refData.set.eRateUnit OF
  E_RateUnit.PerMin: fPerS := 60.0;
  E_RateUnit.PerHour: fPerS := 3600.0;
  E_RateUnit.PerDay: fPerS := 86400.0;
ELSE
  fPerS := 1.0;
END_CASE;

(* the preset, the setpoint, the measurements *)
IF nSetpointPreset = 1 THEN
  eUse := E_LoopPreset.Low;
ELSIF nSetpointPreset = 2 THEN
  eUse := E_LoopPreset.High;
ELSIF nSetpointPreset = 0 THEN
  eUse := E_LoopPreset.Normal;
ELSE
  eUse := refData.set.eSetpointPreset;
END_IF;
bFixedOn := refData.set.eControlBy = E_LoopControl.Fixed AND NOT refData.set.bManualSelected;
IF refData.set.eControlBy = E_LoopControl.Flow THEN
  fSpTarget := refData.set.fFlowSetpoint;
  IF eUse = E_LoopPreset.Low AND refData.set.fFlowSetpointLow <> REAL#0.0 THEN
    fSpTarget := refData.set.fFlowSetpointLow;
  ELSIF eUse = E_LoopPreset.High AND refData.set.fFlowSetpointHigh <> REAL#0.0 THEN
    fSpTarget := refData.set.fFlowSetpointHigh;
  END_IF;
ELSIF refData.set.eSetpointFrom = E_SpSource.Pin THEN
  fSpTarget := fSetpoint;
ELSIF eUse = E_LoopPreset.Low AND refData.set.fSetpointLow <> REAL#0.0 THEN
  fSpTarget := refData.set.fSetpointLow;
ELSIF eUse = E_LoopPreset.High AND refData.set.fSetpointHigh <> REAL#0.0 THEN
  fSpTarget := refData.set.fSetpointHigh;
ELSE
  fSpTarget := refData.set.fSetpoint;
END_IF;
IF bFixedOn THEN
  CASE eUse OF
    E_LoopPreset.Low: fUse := refData.set.fFixedSpeedLowPct;
    E_LoopPreset.High: fUse := refData.set.fFixedSpeedHighPct;
  ELSE
    fUse := refData.set.fFixedSpeedPct;
  END_CASE;
ELSE
  fUse := refData.set.fManualSpeedPct;
END_IF;
bPvOk := FALSE;
fPvV := REAL#0.0;
IF ipProcessValue <> NULL THEN                 // IEC AND does not short-circuit: test NULL on its own
  IF ipProcessValue.bIsFitted AND ipProcessValue.bHasValue AND ipProcessValue.bIsGood THEN
    fPvV := ipProcessValue.fActValue;
    bPvOk := fPvV = fPvV AND ABS(fPvV) <= REAL#3.4E38;
  END_IF;
END_IF;
bFlowOk := FALSE;
fFlowV := REAL#0.0;
IF ipFlow <> NULL THEN
  IF ipFlow.bIsFitted AND ipFlow.bHasValue AND ipFlow.bIsGood THEN
    fFlowV := ipFlow.fActValue;
    bFlowOk := fFlowV = fFlowV AND ABS(fFlowV) <= REAL#3.4E38;
  END_IF;
END_IF;
IF refData.set.eControlBy = E_LoopControl.Flow THEN
  fCv := fFlowV;
  bCvGood := bFlowOk;
ELSE
  fCv := fPvV;
  bCvGood := bPvOk OR refData.set.eControlBy = E_LoopControl.Fixed;
END_IF;

(* what the control needs: no run without it *)
eCfgId := E_UtError.None;
IF refData.set.eControlBy = E_LoopControl.Pv AND ipProcessValue = NULL THEN
  eCfgId := E_UtError.NoMeasurement;
ELSIF refData.set.eControlBy = E_LoopControl.Flow AND ipFlow = NULL THEN
  eCfgId := E_UtError.NoMeasurement;
ELSIF refData.set.eControlBy <> E_LoopControl.Fixed
      AND (NOT (fSpTarget = fSpTarget) OR ABS(fSpTarget) > REAL#3.4E38 OR fSpTarget = REAL#0.0) THEN
  eCfgId := E_UtError.BadSetting;
ELSIF refData.set.eSpeedFrom = E_LoopSource.External AND refData.set.eControlBy <> E_LoopControl.Fixed
      AND NOT (fExternalSpeedPct >= REAL#0.0) THEN
  eCfgId := E_UtError.NoExtSpeed;
END_IF;
bCfgBad := eCfgId <> E_UtError.None;
IF bCfgBad THEN
  fLoS := 0.0;
  fHiS := 0.0;
ELSE
  fLoS := refData.set.fMinSpeedPct;
  fHiS := refData.set.fMaxSpeedPct;
END_IF;
fRateS := refData.set.fMaxSpeedChangeRate / fPerS;
IF refData.set.bReverseActing THEN
  fErrT := fCv - fSpTarget;
ELSE
  fErrT := fSpTarget - fCv;
END_IF;
IF NOT bCvGood OR refData.set.eControlBy = E_LoopControl.Fixed THEN fErrT := REAL#0.0; END_IF;
bSatisfied := bCvGood AND fErrT <= refData.set.fAtSetpointBand;
bTargetRuns := ipEquipment.bIsRunning;
bDriveOn := (eLoopPhase = E_LoopPhase.Filling OR eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost
             OR eLoopPhase = E_LoopPhase.Fallback OR eLoopPhase = E_LoopPhase.Manual) AND bTargetRuns;

(* the protections, from last scan's phase and speed *)
bX := F_Protect(tNow := tNow, bConditionPresent := bRun AND NOT bCfgBad AND NOT bCvGood, bResetRequest := bResetReq,
                tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stProcessValueBadFault, stStatus := refData.sts.stProcessValueBadFault, stWorking := stWPvBad);
bPvAlarm := stWPvBad.bActive AND bRun AND NOT bCfgBad;
IF refData.set.fHighProcessValueAbove <> REAL#0.0 AND bPvOk THEN
  bHighOn := fPvV > refData.set.fHighProcessValueAbove OR (bHighOn AND fPvV > refData.set.fHighProcessValueAbove - refData.set.fHighProcessValueDeadband);
ELSE
  bHighOn := FALSE;
END_IF;
bX := F_Protect(tNow := tNow, bConditionPresent := bRun AND NOT bCfgBad AND bHighOn, bResetRequest := bResetReq,
                tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stHighProcessValueFault, stStatus := refData.sts.stHighProcessValueFault, stWorking := stWHigh);
fLowSp := refData.set.fLowAtMaxSpeedBelow;
IF fLowSp = REAL#0.0 THEN
  fLowSp := fSpAct - REAL#0.5 * ABS(fSpAct);   // half the setpoint (direct acting only)
END_IF;
bLowOn := bCvGood AND bDriveOn AND bHi AND NOT bAddPumpPossible AND refData.set.eControlBy <> E_LoopControl.Fixed
          AND (refData.set.fLowAtMaxSpeedBelow <> REAL#0.0 OR NOT refData.set.bReverseActing)
          AND (eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost OR eLoopPhase = E_LoopPhase.Manual)
          AND fCv < fLowSp;
bX := F_Protect(tNow := tNow, bConditionPresent := bRun AND NOT bCfgBad AND bLowOn, bResetRequest := bResetReq,
                tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stLowAtMaxSpeedFault, stStatus := refData.sts.stLowAtMaxSpeedFault, stWorking := stWLow);
bX := F_Protect(tNow := tNow, bConditionPresent := eLoopPhase = E_LoopPhase.Filling AND bDriveOn, bResetRequest := bResetReq,
                tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stPipeFill.stFillTimeoutFault, stStatus := refData.sts.stFillTimeoutFault, stWorking := stWFill);
bX := F_Protect(tNow := tNow, bConditionPresent := eLoopPhase = E_LoopPhase.Control AND bDriveOn AND bCvGood AND NOT bOverride
                                        AND ABS(fCv - fSpAct) > refData.set.fAtSetpointBand AND NOT bHi AND NOT bLo,
                bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stSetpointNotReachedFault,
                stStatus := refData.sts.stSetpointNotReachedFault, stWorking := stWReach);
bX := F_Protect(tNow := tNow, bConditionPresent := refData.set.tHuntWindow > T#0s AND refData.sts.nCrossingCount > refData.set.nMaxCrossings,
                bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stHuntingFault,
                stStatus := refData.sts.stHuntingFault, stWorking := stWHunt);
bTripStop := stWFill.bTripping OR stWHigh.bTripping OR stWLow.bTripping OR stWReach.bTripping
             OR (bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Stop);
(* only a reset that was needed (Manual, or a Retry lockout) asks for bRun to cycle *)
IF (stWFill.bResetDone OR stWHigh.bResetDone OR stWLow.bResetDone OR stWReach.bResetDone OR stWHunt.bResetDone)
   AND eLoopPhase = E_LoopPhase.Idle AND NOT refData.set.bRestartAfterReset THEN
  bMustCycle := TRUE;
END_IF;
IF NOT bRun THEN bMustCycle := FALSE; END_IF;
bReq := bRun AND NOT bCfgBad AND NOT bMustCycle;

(* the phase *)
ePrev := eLoopPhase;
IF NOT bReq OR bTripStop THEN
  eLoopPhase := E_LoopPhase.Idle;
  bFilledRun := FALSE;
ELSIF refData.set.bManualSelected OR bFixedOn THEN
  IF eLoopPhase = E_LoopPhase.Idle OR eLoopPhase = E_LoopPhase.Sleep THEN
    fSpd := LIMIT(fLoS, refData.set.fStartSpeedPct, fHiS);
    fFlowCap := fHiS;
  END_IF;
  eLoopPhase := E_LoopPhase.Manual;      // the operator's / fixed speed; the protections still act
ELSIF bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Hold AND eLoopPhase = E_LoopPhase.Sleep THEN
  ;                                  // holding: a sleeping pump stays asleep
ELSIF bPvAlarm OR stWHunt.bTripping THEN
  IF eLoopPhase <> E_LoopPhase.Fallback THEN
    IF bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Hold AND eLoopPhase <> E_LoopPhase.Idle THEN
      fHoldSpeed := fSpd;
    ELSIF bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Hold THEN
      fHoldSpeed := refData.set.fStartSpeedPct;
    ELSE
      fHoldSpeed := refData.set.fFallbackSpeedPct;
    END_IF;
    IF eLoopPhase = E_LoopPhase.Idle OR eLoopPhase = E_LoopPhase.Sleep THEN
      fSpd := LIMIT(fLoS, refData.set.fStartSpeedPct, fHiS);
    END_IF;
    eLoopPhase := E_LoopPhase.Fallback;
  ELSIF bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Substitute THEN
    fHoldSpeed := refData.set.fFallbackSpeedPct;
  ELSIF NOT bPvAlarm THEN
    fHoldSpeed := refData.set.fFallbackSpeedPct;   // a hunting trip: always the fallback speed
  END_IF;
ELSE
  CASE eLoopPhase OF
  E_LoopPhase.Idle:
    fSpd := LIMIT(fLoS, refData.set.fStartSpeedPct, fHiS);
    bPreload := TRUE;
    fFlowCap := fHiS;
    fSpAct := fSpTarget;
    IF refData.set.stPipeFill.eFillMode <> E_FillMode.Off AND NOT refData.set.bReverseActing
       AND refData.set.eControlBy = E_LoopControl.Pv THEN
      eLoopPhase := E_LoopPhase.Filling;
      IF refData.set.stPipeFill.eFillMode = E_FillMode.Ramp AND bCvGood THEN fSpAct := MIN(fCv, fSpTarget); END_IF;
    ELSE
      eLoopPhase := E_LoopPhase.Control;
    END_IF;
  E_LoopPhase.Fallback, E_LoopPhase.Manual:
    IF refData.set.stPipeFill.eFillMode <> E_FillMode.Off AND NOT refData.set.bReverseActing
       AND refData.set.eControlBy = E_LoopControl.Pv AND NOT bFilledRun THEN
      eLoopPhase := E_LoopPhase.Filling;   // the line is not full yet: the fill first
      IF refData.set.stPipeFill.eFillMode = E_FillMode.Ramp AND bCvGood THEN fSpAct := MIN(fCv, fSpTarget); END_IF;
    ELSE
      eLoopPhase := E_LoopPhase.Control;
      bPreload := TRUE;                // bumpless: carry on from the speed now
    END_IF;
  E_LoopPhase.Boost:
    IF fErrT > refData.set.stSleep.fWakeWhenShortBy OR NOT refData.set.stSleep.bSleepAllowed THEN
      eLoopPhase := E_LoopPhase.Control;   // the demand came back during the boost
    ELSIF tNow - tBoostStart >= refData.set.stSleep.tBoostTime THEN
      eLoopPhase := E_LoopPhase.Sleep;
      tSleepStart := tNow;
      tWakeSince := tNow;
    END_IF;
  E_LoopPhase.Sleep:
    IF NOT (bCvGood AND fErrT > refData.set.stSleep.fWakeWhenShortBy) THEN
      tWakeSince := tNow;
    END_IF;
    IF NOT refData.set.stSleep.bSleepAllowed
       OR (tNow - tWakeSince >= refData.set.stSleep.tWakeDelay AND tNow - tSleepStart >= refData.set.stSleep.tMinSleepTime
           AND bCvGood AND fErrT > refData.set.stSleep.fWakeWhenShortBy) THEN
      eLoopPhase := E_LoopPhase.Control;
      fSpd := LIMIT(fLoS, refData.set.fStartSpeedPct, fHiS);
      bPreload := TRUE;
      fFlowCap := fHiS;
    END_IF;
  ELSE
    ;                                  // Filling, Control: below
  END_CASE;
END_IF;

(* the fill's end and the sleep check *)
IF refData.set.stPipeFill.fFilledAbove > REAL#0.0 THEN
  fFillTarget := refData.set.stPipeFill.fFilledAbove;
ELSE
  fFillTarget := REAL#0.9 * fSpTarget;
END_IF;
IF eLoopPhase = E_LoopPhase.Filling AND ePrev = E_LoopPhase.Filling AND bCvGood AND fCv >= fFillTarget
   AND (refData.set.stPipeFill.eFillMode = E_FillMode.Fixed OR fSpAct >= fSpTarget) THEN
  eLoopPhase := E_LoopPhase.Control;
  bPreload := TRUE;
  bFilledRun := TRUE;
END_IF;
IF eLoopPhase <> E_LoopPhase.Idle AND bCvGood AND fCv >= fFillTarget THEN
  bFilledRun := TRUE;                  // at the fill target: the line is full whatever the phase
END_IF;
IF eLoopPhase = E_LoopPhase.Control AND ePrev = E_LoopPhase.Control AND refData.set.stSleep.bSleepAllowed AND bDriveOn
   AND bSatisfied AND (fSpd <= refData.set.stSleep.fSleepBelowSpeedPct
                       OR (refData.set.stSleep.fSleepBelowFlow > REAL#0.0 AND bFlowOk AND fFlowV < refData.set.stSleep.fSleepBelowFlow)) THEN
  IF tNow - tSleepSince >= refData.set.stSleep.tSleepDelay THEN
    IF refData.set.bReverseActing THEN
      fSpBoost := fSpTarget - ABS(fSpTarget) * refData.set.stSleep.fBoostPctOfSetpoint / REAL#100.0;
    ELSE
      fSpBoost := fSpTarget + ABS(fSpTarget) * refData.set.stSleep.fBoostPctOfSetpoint / REAL#100.0;
    END_IF;
    IF refData.set.stSleep.fBoostPctOfSetpoint > REAL#0.0 AND refData.set.stSleep.tBoostTime > T#0s THEN
      eLoopPhase := E_LoopPhase.Boost;
      tBoostStart := tNow;
    ELSE
      eLoopPhase := E_LoopPhase.Sleep;
      tSleepStart := tNow;
      tWakeSince := tNow;
    END_IF;
  END_IF;
ELSE
  tSleepSince := tNow;
END_IF;

(* the setpoint in use *)
IF eLoopPhase = E_LoopPhase.Filling AND refData.set.stPipeFill.eFillMode = E_FillMode.Ramp THEN
  IF ePrev <> E_LoopPhase.Filling THEN
    fbFillRamp(fSetpoint := fSpAct, bFollowAtOnce := TRUE);          // the fill starts from the value
  ELSE
    fbFillRamp(fSetpoint := fSpTarget, fRampUpRate := refData.set.stPipeFill.fSetpointRiseRate, fRampDownRate := REAL#0.0,
               eRateUnit := refData.set.eRateUnit, bFollowAtOnce := FALSE);
  END_IF;
  fSpAct := fbFillRamp.fOut;
  fbSpRamp(fSetpoint := fSpAct, bFollowAtOnce := TRUE);
ELSIF eLoopPhase = E_LoopPhase.Boost THEN
  fSpAct := fSpBoost;
  fbSpRamp(fSetpoint := fSpAct, bFollowAtOnce := TRUE);
ELSIF eLoopPhase = E_LoopPhase.Idle OR eLoopPhase = E_LoopPhase.Sleep OR eLoopPhase = E_LoopPhase.Manual
      OR refData.set.fSetpointRampRate <= REAL#0.0 OR bCfgBad THEN
  fbSpRamp(fSetpoint := fSpTarget, bFollowAtOnce := TRUE);
  fSpAct := fbSpRamp.fOut;
ELSE
  fbSpRamp(fSetpoint := fSpTarget, fRampUpRate := refData.set.fSetpointRampRate, fRampDownRate := refData.set.fSetpointRampRate,
           eRateUnit := refData.set.eRateUnit, bFollowAtOnce := FALSE);
  fSpAct := fbSpRamp.fOut;
END_IF;

(* the limits: the flow limit lowers the top *)
IF fRateS > 0.0 THEN fCapRate := fRateS; ELSE fCapRate := 5.0; END_IF;
IF refData.set.fMaxFlow > REAL#0.0 AND bFlowOk AND bDriveOn THEN
  IF fFlowV > refData.set.fMaxFlow THEN
    IF fFlowCap > fSpd THEN fFlowCap := fSpd; END_IF;   // start bringing it down from where it is
    fFlowCap := fFlowCap - fCapRate * MIN(1.0, (fFlowV - refData.set.fMaxFlow) / (0.2 * refData.set.fMaxFlow)) * fDt;
  ELSE
    fFlowCap := fFlowCap + fCapRate * MIN(1.0, (refData.set.fMaxFlow - fFlowV) / (0.2 * refData.set.fMaxFlow)) * fDt;
  END_IF;
  fFlowCap := LIMIT(fLoS, fFlowCap, fHiS);
  fHiS := fFlowCap;
ELSE
  fFlowCap := fHiS;
END_IF;
bOverride := stWHigh.bWarning AND eLoopPhase <> E_LoopPhase.Idle AND eLoopPhase <> E_LoopPhase.Sleep;
IF fRateS > 0.0 THEN fStepMax := fRateS * fDt; ELSE fStepMax := 1.0E30; END_IF;

(* the output *)
fTiS := TIME_TO_LREAL(refData.set.tTi) / 1000.0;
fTdS := TIME_TO_LREAL(refData.set.tTd) / 1000.0;
IF bCvGood THEN
  IF refData.set.bReverseActing THEN fE := fCv - fSpAct; ELSE fE := fSpAct - fCv; END_IF;
  IF ABS(fE) <= refData.set.fDeadband THEN fE := 0.0; END_IF;
ELSE
  fE := 0.0;
END_IF;
IF eLoopPhase = E_LoopPhase.Idle OR eLoopPhase = E_LoopPhase.Sleep THEN
  fSpd := 0.0;
  bPreload := TRUE;
  fI := 0.0;
ELSIF bOverride THEN
  fSpd := fLoS;                        // overpressure warning: straight to the minimum
  bPreload := TRUE;
ELSIF NOT bTargetRuns THEN
  bPreload := TRUE;                    // the drive has not started: hold the speed
ELSIF eLoopPhase = E_LoopPhase.Manual THEN
  fWant := LIMIT(fLoS, fUse, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF eLoopPhase = E_LoopPhase.Fallback THEN
  fWant := LIMIT(fLoS, fHoldSpeed, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF eLoopPhase = E_LoopPhase.Filling AND refData.set.stPipeFill.eFillMode = E_FillMode.Fixed THEN
  fWant := LIMIT(fLoS, refData.set.stPipeFill.fFillSpeedPct, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF NOT bCvGood THEN
  bPreload := TRUE;                    // the sensor is bad, not yet past its delay: hold the speed
ELSIF refData.set.eSpeedFrom = E_LoopSource.External THEN
  IF fExternalSpeedPct >= REAL#0.0 AND fExternalSpeedPct <= REAL#3.4E38 THEN
    fExtHeld := fExternalSpeedPct;
  ELSIF bPreload THEN
    fExtHeld := fSpd;
  END_IF;
  bPreload := FALSE;
  fWant := LIMIT(fLoS, fExtHeld, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  fI := 0.0;
ELSE
  (* the PID *)
  fP := refData.set.fKp * fE;
  fDi := 0.0;
  fD := 0.0;
  IF bPreload THEN
    fI := fSpd - fP;                   // bumpless: carry on from the speed now
    fErrPrev := fE;
    bPreload := FALSE;
  ELSE
    IF fTdS > 0.0 AND fDt > 0.0 THEN fD := refData.set.fKp * fTdS * (fE - fErrPrev) / fDt; END_IF;
    IF fTiS > 0.0 THEN fDi := refData.set.fKp * fE * fDt / fTiS; END_IF;
  END_IF;
  IF fDt > 0.0 THEN fErrPrev := fE; END_IF;
  fCand := fP + fI + fDi + fD;
  IF NOT (fCand = fCand) THEN fCand := fSpd; END_IF;   // infinities of opposite sign: hold
  fWant := LIMIT(fLoS, fCand, fHiS);
  fWant := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  IF (fDi > 0.0 AND fWant >= fCand) OR (fDi < 0.0 AND fWant <= fCand) THEN   // anti-windup
    IF fDi > 0.0 THEN
      fI := MAX(fI, MIN(fI + fDi, fHiS));
    ELSE
      fI := MIN(fI, MAX(fI + fDi, fLoS));
    END_IF;
  END_IF;
  IF fHiS < refData.set.fMaxSpeedPct THEN
    fI := MIN(fI, fHiS);               // the flow limit takes the integral down with it
  END_IF;
  fSpd := fWant;
END_IF;
IF eLoopPhase <> E_LoopPhase.Idle AND eLoopPhase <> E_LoopPhase.Sleep THEN
  IF NOT (fSpd = fSpd) THEN fSpd := fLoS; END_IF;
  fSpd := LIMIT(fLoS, fSpd, fHiS);
END_IF;
bAsk := eLoopPhase = E_LoopPhase.Filling OR eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost
        OR eLoopPhase = E_LoopPhase.Fallback OR eLoopPhase = E_LoopPhase.Manual;
IF bAsk THEN fSpeedSetpointPct := LREAL_TO_REAL(fSpd); ELSE fSpeedSetpointPct := REAL#0.0; END_IF;
bHi := bAsk AND fSpd >= fHiS - 0.01;
bLo := bAsk AND fSpd <= fLoS + 0.01;
refData.sts.bFlowLimiting := bAsk AND fHiS < refData.set.fMaxSpeedPct AND bHi;
bAtMaxSpeed := bHi AND NOT refData.sts.bFlowLimiting;
bAtMinSpeed := bLo;
bPipeFilled := eLoopPhase <> E_LoopPhase.Idle
           AND (bFilledRun OR refData.set.stPipeFill.eFillMode = E_FillMode.Off OR refData.set.bReverseActing
                OR refData.set.eControlBy <> E_LoopControl.Pv
                OR eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost OR eLoopPhase = E_LoopPhase.Sleep);
ipEquipment.Request(bRun := bAsk, bHoldOff := FALSE, fSpeedSetpointPct := fSpeedSetpointPct);
bEquipmentRunning := bAsk AND ipEquipment.bIsRunning;

(* hunting: crossings of the setpoint, each a swing beyond half the band either side *)
fHb := refData.set.fMinSwing / REAL#2.0;
IF (eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost) AND bAsk AND bTargetRuns AND bCvGood THEN
  IF (fCv - fSpAct > fHb AND nHuntSide < 0) OR (fSpAct - fCv > fHb AND nHuntSide > 0) THEN
    IF nHuntCur < 32767 THEN nHuntCur := nHuntCur + 1; END_IF;
    tHuntLast := tNow;
  END_IF;
  IF fCv - fSpAct > fHb THEN
    nHuntSide := 1;
  ELSIF fSpAct - fCv > fHb THEN
    nHuntSide := -1;
  END_IF;
ELSE
  nHuntSide := 0;
END_IF;
IF refData.set.tHuntWindow > T#0s THEN
  IF tNow - tHuntLast > refData.set.tHuntWindow THEN
    nHuntCur := 0;                     // no crossing for a whole window: none left
    nHuntPrev := 0;
  END_IF;
  IF tNow - tHuntAt >= refData.set.tHuntWindow THEN
    IF tNow - tHuntAt >= refData.set.tHuntWindow + refData.set.tHuntWindow THEN
      nHuntPrev := 0;                  // a whole window without a scan of it
    ELSE
      nHuntPrev := nHuntCur;
    END_IF;
    nHuntCur := 0;
    tHuntAt := tNow;
  END_IF;
  refData.sts.nCrossingCount := nHuntCur + REAL_TO_INT(INT_TO_REAL(nHuntPrev)
      * (REAL#1.0 - TIME_TO_REAL(tNow - tHuntAt) / TIME_TO_REAL(refData.set.tHuntWindow)));
ELSE
  nHuntCur := 0;
  nHuntPrev := 0;
  tHuntAt := tNow;
  refData.sts.nCrossingCount := 0;
END_IF;

(* staging hints for an owner with more pumps *)
IF NOT (eLoopPhase = E_LoopPhase.Control AND bAsk AND bTargetRuns AND bAtMaxSpeed AND NOT bOverride
        AND fErrT > refData.set.fAtSetpointBand) THEN
  tMoreSince := tNow;
END_IF;
IF NOT (eLoopPhase = E_LoopPhase.Control AND bAsk AND bTargetRuns AND bLo AND NOT bOverride) THEN
  tLessSince := tNow;
END_IF;
bAddPumpNeeded := eLoopPhase = E_LoopPhase.Control AND bAtMaxSpeed AND tNow - tMoreSince >= refData.set.tAddOrDropPumpDelay;
bDropPumpNeeded := eLoopPhase = E_LoopPhase.Control AND bLo AND tNow - tLessSince >= refData.set.tAddOrDropPumpDelay;

bAtSetpoint := (eLoopPhase = E_LoopPhase.Control OR eLoopPhase = E_LoopPhase.Boost OR eLoopPhase = E_LoopPhase.Sleep)
               AND bCvGood AND ABS(fCv - fSpAct) <= refData.set.fAtSetpointBand;
fShortOfSetpoint := fErrT;
IF refData.set.eControlBy = E_LoopControl.Fixed AND bPvOk AND fSpTarget <> REAL#0.0 THEN
  IF refData.set.bReverseActing THEN fShortOfSetpoint := fPvV - fSpTarget; ELSE fShortOfSetpoint := fSpTarget - fPvV; END_IF;
END_IF;

(* status *)
bError := stWFill.bTripping OR stWHigh.bTripping OR stWLow.bTripping OR stWReach.bTripping OR stWHunt.bTripping
          OR (bPvAlarm AND refData.set.eWhenValueBad = E_OnBadValue.Stop) OR (bCfgBad AND bRun);
bWarning := NOT bError AND (stWFill.bWarning OR stWHigh.bWarning OR stWLow.bWarning OR stWReach.bWarning OR stWHunt.bWarning
                            OR bPvAlarm OR refData.sts.bSettingRefused);
IF stWHigh.bTripping OR stWHigh.bWarning THEN
  eErrorId := E_UtError.PressureHigh;
ELSIF stWLow.bTripping OR stWLow.bWarning THEN
  eErrorId := E_UtError.LowAtMax;
ELSIF bPvAlarm THEN
  eErrorId := E_UtError.SensorBad;
ELSIF stWFill.bTripping OR stWFill.bWarning THEN
  eErrorId := E_UtError.FillTimeout;
ELSIF stWReach.bTripping OR stWReach.bWarning THEN
  eErrorId := E_UtError.NotReaching;
ELSIF stWHunt.bTripping OR stWHunt.bWarning THEN
  eErrorId := E_UtError.Hunting;
ELSIF bCfgBad AND bRun THEN
  eErrorId := eCfgId;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault;
ELSIF NOT bRun THEN eState := E_State.Off;
ELSIF eLoopPhase = E_LoopPhase.Sleep THEN eState := E_State.Waiting;
ELSIF bEquipmentRunning THEN eState := E_State.Running;
ELSIF bAsk THEN eState := E_State.Starting;
ELSE eState := E_State.Held; END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.fSpeedSetpointPct := fSpeedSetpointPct;
refData.sts.fProcessValue := fCv;
refData.sts.fSetpointInUse := fSpAct;
refData.sts.bInManual := refData.set.bManualSelected;
refData.sts.bProcessValueBad := stWPvBad.bActive;
refData.sts.eLoopPhase := eLoopPhase;
refData.sts.eSetpointPresetInUse := eUse;
refData.sts.bAtSetpoint := bAtSetpoint;
refData.sts.bPipeFilled := bPipeFilled;
refData.sts.bSleeping := eLoopPhase = E_LoopPhase.Sleep;
IF eLoopPhase <> ePhasePrev OR bFirstScan THEN tPhaseSince := tNow; END_IF;
ePhasePrev := eLoopPhase;
refData.det.tInPhaseFor := tNow - tPhaseSince;
refData.det.fProportionalPart := LREAL_TO_REAL(fP);
refData.det.fIntegralPart := LREAL_TO_REAL(fI);
refData.det.fDerivativePart := LREAL_TO_REAL(fD);
bFirstScan := FALSE;

END_FUNCTION_BLOCK