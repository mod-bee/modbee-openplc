(* FB_SpeedLoop — constant pressure / flow / level with a speed drive (DESIGN-0.2.md section 5.5; src-v2
UT_SPEED_CTRL + UT_SPEED_CTRL_RUN, the field-proven loop). It owns its pump: while asked to run it requests the
pump (an FB_Pump on an FB_MotorVsd, an FB_MotorVsd, or an FB_Group) at the speed that holds the value at the
setpoint.

Pins: bRun (control wanted), ipPv (the pressure or level; stHighPv always watches it), ipFlow (the flow: Flow
control, the flow limit, sleep on low flow; unwired = none), ipTarget (the pump it drives), fSp (the setpoint
while set.eSpSource = Pin), nPreset (0 Normal, 1 Low, 2 High while wired; -1 = the kept set.ePreset),
fExtSpeed (the speed of an external PID while set.eSource = External; < 0 = not wired), bMoreAvailable (an
owner can still add a pump: stLowAtMax waits until it cannot), refData -> fSpeed (the speed asked, %),
bRunning (the pump runs), bAtSetpoint, bFilled, fError, bAtMax, bAtMin, ePhase, bMoreNeeded, bLessNeeded, plus
FB_Object's outputs.

What the speed follows (set.eControl): Pv, the PID on ipPv; Flow, the PID on ipFlow; Fixed, a fixed speed (no
PID; a bad sensor does not stop it). Presets Normal / Low / High: Pv set.fSp / fSpLow / fSpHigh, Flow
set.fFlowSp / fFlowSpLow / fFlowSpHigh, Fixed set.fFixedSpeed / fFixedSpeedLow / fFixedSpeedHigh (a Low or High
setpoint of 0 uses the Normal one). Pv control takes its setpoint from the record (set.eSpSource = Record) or
the fSp pin (Pin). A setpoint in use of 0 (or not a number), a missing measurement or a missing fExtSpeed is a
configuration fault while bRun: no run.
    speed = fKp * (e + 1/tTi * integral(e dt) + tTd * de/dt)      (% speed)
e = sp - value (set.bReverse: value - sp, for a level emptied by the pump); inside set.fDeadband e = 0.
Anti-windup: the integral stays inside the output limits and stops while a limit or the rate limit holds the
output. Bumpless: whenever the loop takes the output back (a start, the end of manual, fallback or a fill),
the integral is loaded from the speed it has. A start begins at set.fStartSpeed (limited to the speed range:
0 = set.fMinSpeed). set.fRateLimit limits the output change (% per set.eRateUnit, 0 = no limit); set.fSpRamp
ramps the setpoint (units per set.eRateUnit, 0 = a step). set.eSource = External: the speed follows fExtSpeed
(held at the last value while it is not a number), with the same limits, protections and sleep.
Manual (the record's bCmdManual / bCmdAuto, kept in set.bManual): set.fManualSpeed; the protections still act.

Phases (ePhase): Idle -> Filling (optional) -> Control -> Boost -> Sleep -> Control; Fallback at a fixed speed
after a hunting trip or with a failed sensor; Manual at the manual (or Fixed control's) speed.
Pipe fill (set.stFill; Pv control, not reverse acting): eMode Fixed runs at fSpeed until the value reaches
fTarget (0 = 90 % of the setpoint); Ramp raises the setpoint from the value at fRate (per set.eRateUnit) to the
setpoint. A fill longer than stTimeout's delay acts per stTimeout (FillTimeout). After a manual or fallback
spell the fill runs again only if the line has not been full in this run. bFilled: the line is full.
Sleep (set.stSleep.bEnable): satisfied (within fAtSpBand of the setpoint, or past it) at or below fSpeed, or
with the flow below fFlow (0 = not used), for tDelay: the setpoint is raised by fBoost % for tBoostTime, then
the pump stops (eState Waiting). It wakes when the value is fWakeDrop short of the setpoint for tWakeDelay,
after at least tMinSleep.
Flow limit (set.fFlowLimit, 0 = off): the speed is brought down to hold the flow below it (sts.bFlowLimiting).
Protections (each a ST_ProtectionSet: off / warn / trip / signal, delay, reset; F_Protect):
  stHighPv       Pv above set.fHighPv (0 = off; clears set.fHighPvDeadband below it): a trip stops the pump
                 (PressureHigh); a warning holds the minimum speed while it lasts.
  stLowAtMax     the value below set.fLowAtMax (0 = half the setpoint, direct acting only) at the top speed in
                 control, while no more pump can be added (bMoreAvailable FALSE): a burst main (LowAtMax).
  stFill.stTimeout  the pipe fill took too long (FillTimeout).
  stNotReaching  in control, not at a speed limit, the value outside fAtSpBand of the setpoint (NotReaching).
  stHunting      more than set.nHuntCycles (1..15) crossings of the setpoint (each a swing beyond fHuntBand) in
                 set.tHuntWindow (0 = off) (Hunting): a trip runs at set.fFailSpeed (Fallback) until reset.
A bad or unfitted measurement under control: the speed is held at once; past set.stPvBad's delay set.eOnBad
Hold (the last speed; a sleeping pump stays asleep), Fixed (set.fFailSpeed) or Stop (SensorBad). Control
resumes when stPvBad clears (its tRecover: the sensor good this long).
Restart: after a reset that was needed (Manual reset, or a Retry lockout) the loop waits for bRun to cycle,
unless set.bRestartAfterReset.
bAtSetpoint: in control, boost or sleep, the value within set.fAtSpBand of the setpoint in use.
fError: how far the value is short of the setpoint (set.bReverse: above it), 0 when not good; with Fixed
control Pv against the setpoint in use (0 when that is 0), for a fixed-speed set staged on bands; with
bAtMax (at the top of the speed range, not held by the flow limit) and bAtMin it feeds FB_Cascade's staging.
bMoreNeeded: in control at the top speed and short of the setpoint by more than fAtSpBand for set.tStageDelay;
bLessNeeded: in control at the minimum speed for set.tStageDelay (hints for an owner adding or dropping pumps;
a highPv warning stops both). bFilled can drive a pump's prime-done input; stLowAtMax is the lost-prime check.
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back
(sts.bRefused, a warning until a reset). *)

FUNCTION_BLOCK FB_SpeedLoop EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL;
    ipPv : I_Measurement; (* Pv control, stHighPv (Flow / Fixed control: may be unwired) *)
    ipFlow : I_Measurement; (* Flow control, flow limit, sleep on flow (unwired = none) *)
    ipTarget : I_Equipment; (* required *)
    fSp : REAL; (* the setpoint while set.eSpSource = Pin *)
    nPreset : INT := -1; (* 0 Normal, 1 Low, 2 High while wired; -1 = the kept set.ePreset *)
    fExtSpeed : REAL := -1.0; (* External: the speed, %; < 0 = not wired *)
    bMoreAvailable : BOOL; (* an owner can still add a pump: stLowAtMax waits *)
    refData : REFERENCE TO ST_SpeedLoopData;
  END_VAR
  VAR_OUTPUT
    fSpeed : REAL;
    bRunning : BOOL;
    bAtSetpoint : BOOL;
    bFilled : BOOL; (* the pipe fill is done in this run *)
    fError : REAL; (* short of the setpoint by (direction applied; 0 when not good) *)
    bAtMax : BOOL; (* at the top speed, not held by the flow limit *)
    bAtMin : BOOL; (* at the minimum speed *)
    ePhase : E_LoopPhase;
    bMoreNeeded : BOOL; (* at the top speed and short of the setpoint for set.tStageDelay *)
    bLessNeeded : BOOL; (* at the minimum speed for set.tStageDelay *)
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


METHOD PRIVATE SetOk : BOOL
  SetOk := refData.set.fMinSpeed >= REAL#0.0 AND refData.set.fMaxSpeed <= REAL#100.0
           AND refData.set.fMinSpeed <= refData.set.fMaxSpeed AND refData.set.fKp >= REAL#0.0
           AND refData.set.tTi >= T#0s AND refData.set.tTd >= T#0s AND refData.set.fSpRamp >= REAL#0.0
           AND refData.set.fManualSpeed >= REAL#0.0 AND refData.set.fManualSpeed <= REAL#100.0
           AND refData.set.fFailSpeed >= REAL#0.0 AND refData.set.fFailSpeed <= REAL#100.0
           AND refData.set.fSp = refData.set.fSp                  // not NaN
           AND refData.set.fSpLow = refData.set.fSpLow AND refData.set.fSpHigh = refData.set.fSpHigh
           AND refData.set.fFlowSp = refData.set.fFlowSp AND refData.set.fFlowSpLow = refData.set.fFlowSpLow
           AND refData.set.fFlowSpHigh = refData.set.fFlowSpHigh
           AND refData.set.fFixedSpeed >= REAL#0.0 AND refData.set.fFixedSpeed <= REAL#100.0
           AND refData.set.fFixedSpeedLow >= REAL#0.0 AND refData.set.fFixedSpeedLow <= REAL#100.0
           AND refData.set.fFixedSpeedHigh >= REAL#0.0 AND refData.set.fFixedSpeedHigh <= REAL#100.0
           AND refData.set.fDeadband >= REAL#0.0 AND refData.set.fStartSpeed >= REAL#0.0
           AND refData.set.fStartSpeed <= REAL#100.0 AND refData.set.fRateLimit >= REAL#0.0
           AND refData.set.fAtSpBand >= REAL#0.0
           AND refData.set.stFill.fSpeed >= REAL#0.0 AND refData.set.stFill.fSpeed <= REAL#100.0
           AND refData.set.stFill.fTarget >= REAL#0.0 AND refData.set.stFill.fRate >= REAL#0.0
           AND refData.set.stSleep.fSpeed >= REAL#0.0 AND refData.set.stSleep.fSpeed <= REAL#100.0
           AND refData.set.stSleep.fFlow >= REAL#0.0 AND refData.set.stSleep.fWakeDrop >= REAL#0.0
           AND refData.set.stSleep.fBoost >= REAL#0.0 AND refData.set.stSleep.fBoost <= REAL#100.0
           AND refData.set.stSleep.tDelay >= T#0s AND refData.set.stSleep.tBoostTime >= T#0s
           AND refData.set.stSleep.tWakeDelay >= T#0s AND refData.set.stSleep.tMinSleep >= T#0s
           AND refData.set.fFlowLimit >= REAL#0.0 AND refData.set.fHighPvDeadband >= REAL#0.0
           AND refData.set.fHighPv = refData.set.fHighPv AND refData.set.fLowAtMax = refData.set.fLowAtMax
           AND refData.set.nHuntCycles >= 1 AND refData.set.nHuntCycles <= 15 AND refData.set.tHuntWindow >= T#0s
           AND refData.set.fHuntBand >= REAL#0.0 AND refData.set.tStageDelay >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipTarget = NULL THEN
  fSpeed := REAL#0.0;
  bRunning := FALSE;
  bError := TRUE;
  IF ipTarget = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  fSpAct := refData.set.fSp;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF refData.bCmdManual THEN refData.set.bManual := TRUE; refData.bCmdManual := FALSE; END_IF;
IF refData.bCmdAuto THEN refData.set.bManual := FALSE; refData.bCmdAuto := FALSE; END_IF;
bResetReq := refData.bCmdReset OR SystemReset();
IF refData.bCmdReset THEN refData.sts.bRefused := FALSE; END_IF;
refData.bCmdReset := FALSE;
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
IF nPreset = 1 THEN
  eUse := E_LoopPreset.Low;
ELSIF nPreset = 2 THEN
  eUse := E_LoopPreset.High;
ELSIF nPreset = 0 THEN
  eUse := E_LoopPreset.Normal;
ELSE
  eUse := refData.set.ePreset;
END_IF;
bFixedOn := refData.set.eControl = E_LoopControl.Fixed AND NOT refData.set.bManual;
IF refData.set.eControl = E_LoopControl.Flow THEN
  fSpTarget := refData.set.fFlowSp;
  IF eUse = E_LoopPreset.Low AND refData.set.fFlowSpLow <> REAL#0.0 THEN
    fSpTarget := refData.set.fFlowSpLow;
  ELSIF eUse = E_LoopPreset.High AND refData.set.fFlowSpHigh <> REAL#0.0 THEN
    fSpTarget := refData.set.fFlowSpHigh;
  END_IF;
ELSIF refData.set.eSpSource = E_SpSource.Pin THEN
  fSpTarget := fSp;
ELSIF eUse = E_LoopPreset.Low AND refData.set.fSpLow <> REAL#0.0 THEN
  fSpTarget := refData.set.fSpLow;
ELSIF eUse = E_LoopPreset.High AND refData.set.fSpHigh <> REAL#0.0 THEN
  fSpTarget := refData.set.fSpHigh;
ELSE
  fSpTarget := refData.set.fSp;
END_IF;
IF bFixedOn THEN
  CASE eUse OF
    E_LoopPreset.Low: fUse := refData.set.fFixedSpeedLow;
    E_LoopPreset.High: fUse := refData.set.fFixedSpeedHigh;
  ELSE
    fUse := refData.set.fFixedSpeed;
  END_CASE;
ELSE
  fUse := refData.set.fManualSpeed;
END_IF;
bPvOk := FALSE;
fPvV := REAL#0.0;
IF ipPv <> NULL THEN                 // IEC AND does not short-circuit: test NULL on its own
  IF ipPv.bIsFitted AND ipPv.bHasValue AND ipPv.bIsGood THEN
    fPvV := ipPv.fActValue;
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
IF refData.set.eControl = E_LoopControl.Flow THEN
  fCv := fFlowV;
  bCvGood := bFlowOk;
ELSE
  fCv := fPvV;
  bCvGood := bPvOk OR refData.set.eControl = E_LoopControl.Fixed;
END_IF;

(* what the control needs: no run without it *)
eCfgId := E_UtError.None;
IF refData.set.eControl = E_LoopControl.Pv AND ipPv = NULL THEN
  eCfgId := E_UtError.NoMeasurement;
ELSIF refData.set.eControl = E_LoopControl.Flow AND ipFlow = NULL THEN
  eCfgId := E_UtError.NoMeasurement;
ELSIF refData.set.eControl <> E_LoopControl.Fixed
      AND (NOT (fSpTarget = fSpTarget) OR ABS(fSpTarget) > REAL#3.4E38 OR fSpTarget = REAL#0.0) THEN
  eCfgId := E_UtError.BadSetting;
ELSIF refData.set.eSource = E_LoopSource.External AND refData.set.eControl <> E_LoopControl.Fixed
      AND NOT (fExtSpeed >= REAL#0.0) THEN
  eCfgId := E_UtError.NoExtSpeed;
END_IF;
bCfgBad := eCfgId <> E_UtError.None;
IF bCfgBad THEN
  fLoS := 0.0;
  fHiS := 0.0;
ELSE
  fLoS := refData.set.fMinSpeed;
  fHiS := refData.set.fMaxSpeed;
END_IF;
fRateS := refData.set.fRateLimit / fPerS;
IF refData.set.bReverse THEN
  fErrT := fCv - fSpTarget;
ELSE
  fErrT := fSpTarget - fCv;
END_IF;
IF NOT bCvGood OR refData.set.eControl = E_LoopControl.Fixed THEN fErrT := REAL#0.0; END_IF;
bSatisfied := bCvGood AND fErrT <= refData.set.fAtSpBand;
bTargetRuns := ipTarget.bIsRunning;
bDriveOn := (ePhase = E_LoopPhase.Filling OR ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost
             OR ePhase = E_LoopPhase.Fallback OR ePhase = E_LoopPhase.Manual) AND bTargetRuns;

(* the protections, from last scan's phase and speed *)
bX := F_Protect(tNow := tNow, bCause := bRun AND NOT bCfgBad AND NOT bCvGood, bResetReq := bResetReq,
                tRetryWindow := T#1h, stSet := refData.set.stPvBad, stSts := refData.sts.stPvBad, stWork := stWPvBad);
bPvAlarm := stWPvBad.bActive AND bRun AND NOT bCfgBad;
IF refData.set.fHighPv <> REAL#0.0 AND bPvOk THEN
  bHighOn := fPvV > refData.set.fHighPv OR (bHighOn AND fPvV > refData.set.fHighPv - refData.set.fHighPvDeadband);
ELSE
  bHighOn := FALSE;
END_IF;
bX := F_Protect(tNow := tNow, bCause := bRun AND NOT bCfgBad AND bHighOn, bResetReq := bResetReq,
                tRetryWindow := T#1h, stSet := refData.set.stHighPv, stSts := refData.sts.stHighPv, stWork := stWHigh);
fLowSp := refData.set.fLowAtMax;
IF fLowSp = REAL#0.0 THEN
  fLowSp := fSpAct - REAL#0.5 * ABS(fSpAct);   // half the setpoint (direct acting only)
END_IF;
bLowOn := bCvGood AND bDriveOn AND bHi AND NOT bMoreAvailable AND refData.set.eControl <> E_LoopControl.Fixed
          AND (refData.set.fLowAtMax <> REAL#0.0 OR NOT refData.set.bReverse)
          AND (ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost OR ePhase = E_LoopPhase.Manual)
          AND fCv < fLowSp;
bX := F_Protect(tNow := tNow, bCause := bRun AND NOT bCfgBad AND bLowOn, bResetReq := bResetReq,
                tRetryWindow := T#1h, stSet := refData.set.stLowAtMax, stSts := refData.sts.stLowAtMax, stWork := stWLow);
bX := F_Protect(tNow := tNow, bCause := ePhase = E_LoopPhase.Filling AND bDriveOn, bResetReq := bResetReq,
                tRetryWindow := T#1h, stSet := refData.set.stFill.stTimeout, stSts := refData.sts.stFill, stWork := stWFill);
bX := F_Protect(tNow := tNow, bCause := ePhase = E_LoopPhase.Control AND bDriveOn AND bCvGood AND NOT bOverride
                                        AND ABS(fCv - fSpAct) > refData.set.fAtSpBand AND NOT bHi AND NOT bLo,
                bResetReq := bResetReq, tRetryWindow := T#1h, stSet := refData.set.stNotReaching,
                stSts := refData.sts.stNotReaching, stWork := stWReach);
bX := F_Protect(tNow := tNow, bCause := refData.set.tHuntWindow > T#0s AND refData.sts.nHuntCount > refData.set.nHuntCycles,
                bResetReq := bResetReq, tRetryWindow := T#1h, stSet := refData.set.stHunting,
                stSts := refData.sts.stHunting, stWork := stWHunt);
bTripStop := stWFill.bTrip OR stWHigh.bTrip OR stWLow.bTrip OR stWReach.bTrip
             OR (bPvAlarm AND refData.set.eOnBad = E_OnBad.Stop);
(* only a reset that was needed (Manual, or a Retry lockout) asks for bRun to cycle *)
IF (stWFill.bReset OR stWHigh.bReset OR stWLow.bReset OR stWReach.bReset OR stWHunt.bReset)
   AND ePhase = E_LoopPhase.Idle AND NOT refData.set.bRestartAfterReset THEN
  bMustCycle := TRUE;
END_IF;
IF NOT bRun THEN bMustCycle := FALSE; END_IF;
bReq := bRun AND NOT bCfgBad AND NOT bMustCycle;

(* the phase *)
ePrev := ePhase;
IF NOT bReq OR bTripStop THEN
  ePhase := E_LoopPhase.Idle;
  bFilledRun := FALSE;
ELSIF refData.set.bManual OR bFixedOn THEN
  IF ePhase = E_LoopPhase.Idle OR ePhase = E_LoopPhase.Sleep THEN
    fSpd := LIMIT(fLoS, refData.set.fStartSpeed, fHiS);
    fFlowCap := fHiS;
  END_IF;
  ePhase := E_LoopPhase.Manual;      // the operator's / fixed speed; the protections still act
ELSIF bPvAlarm AND refData.set.eOnBad = E_OnBad.Hold AND ePhase = E_LoopPhase.Sleep THEN
  ;                                  // holding: a sleeping pump stays asleep
ELSIF bPvAlarm OR stWHunt.bTrip THEN
  IF ePhase <> E_LoopPhase.Fallback THEN
    IF bPvAlarm AND refData.set.eOnBad = E_OnBad.Hold AND ePhase <> E_LoopPhase.Idle THEN
      fHoldSpeed := fSpd;
    ELSIF bPvAlarm AND refData.set.eOnBad = E_OnBad.Hold THEN
      fHoldSpeed := refData.set.fStartSpeed;
    ELSE
      fHoldSpeed := refData.set.fFailSpeed;
    END_IF;
    IF ePhase = E_LoopPhase.Idle OR ePhase = E_LoopPhase.Sleep THEN
      fSpd := LIMIT(fLoS, refData.set.fStartSpeed, fHiS);
    END_IF;
    ePhase := E_LoopPhase.Fallback;
  ELSIF bPvAlarm AND refData.set.eOnBad = E_OnBad.Fixed THEN
    fHoldSpeed := refData.set.fFailSpeed;
  ELSIF NOT bPvAlarm THEN
    fHoldSpeed := refData.set.fFailSpeed;   // a hunting trip: always the fallback speed
  END_IF;
ELSE
  CASE ePhase OF
  E_LoopPhase.Idle:
    fSpd := LIMIT(fLoS, refData.set.fStartSpeed, fHiS);
    bPreload := TRUE;
    fFlowCap := fHiS;
    fSpAct := fSpTarget;
    IF refData.set.stFill.eMode <> E_FillMode.Off AND NOT refData.set.bReverse
       AND refData.set.eControl = E_LoopControl.Pv THEN
      ePhase := E_LoopPhase.Filling;
      IF refData.set.stFill.eMode = E_FillMode.Ramp AND bCvGood THEN fSpAct := MIN(fCv, fSpTarget); END_IF;
    ELSE
      ePhase := E_LoopPhase.Control;
    END_IF;
  E_LoopPhase.Fallback, E_LoopPhase.Manual:
    IF refData.set.stFill.eMode <> E_FillMode.Off AND NOT refData.set.bReverse
       AND refData.set.eControl = E_LoopControl.Pv AND NOT bFilledRun THEN
      ePhase := E_LoopPhase.Filling;   // the line is not full yet: the fill first
      IF refData.set.stFill.eMode = E_FillMode.Ramp AND bCvGood THEN fSpAct := MIN(fCv, fSpTarget); END_IF;
    ELSE
      ePhase := E_LoopPhase.Control;
      bPreload := TRUE;                // bumpless: carry on from the speed now
    END_IF;
  E_LoopPhase.Boost:
    IF fErrT > refData.set.stSleep.fWakeDrop OR NOT refData.set.stSleep.bEnable THEN
      ePhase := E_LoopPhase.Control;   // the demand came back during the boost
    ELSIF tNow - tBoostStart >= refData.set.stSleep.tBoostTime THEN
      ePhase := E_LoopPhase.Sleep;
      tSleepStart := tNow;
      tWakeSince := tNow;
    END_IF;
  E_LoopPhase.Sleep:
    IF NOT (bCvGood AND fErrT > refData.set.stSleep.fWakeDrop) THEN
      tWakeSince := tNow;
    END_IF;
    IF NOT refData.set.stSleep.bEnable
       OR (tNow - tWakeSince >= refData.set.stSleep.tWakeDelay AND tNow - tSleepStart >= refData.set.stSleep.tMinSleep
           AND bCvGood AND fErrT > refData.set.stSleep.fWakeDrop) THEN
      ePhase := E_LoopPhase.Control;
      fSpd := LIMIT(fLoS, refData.set.fStartSpeed, fHiS);
      bPreload := TRUE;
      fFlowCap := fHiS;
    END_IF;
  ELSE
    ;                                  // Filling, Control: below
  END_CASE;
END_IF;

(* the fill's end and the sleep check *)
IF refData.set.stFill.fTarget > REAL#0.0 THEN
  fFillTarget := refData.set.stFill.fTarget;
ELSE
  fFillTarget := REAL#0.9 * fSpTarget;
END_IF;
IF ePhase = E_LoopPhase.Filling AND ePrev = E_LoopPhase.Filling AND bCvGood AND fCv >= fFillTarget
   AND (refData.set.stFill.eMode = E_FillMode.Fixed OR fSpAct >= fSpTarget) THEN
  ePhase := E_LoopPhase.Control;
  bPreload := TRUE;
  bFilledRun := TRUE;
END_IF;
IF ePhase <> E_LoopPhase.Idle AND bCvGood AND fCv >= fFillTarget THEN
  bFilledRun := TRUE;                  // at the fill target: the line is full whatever the phase
END_IF;
IF ePhase = E_LoopPhase.Control AND ePrev = E_LoopPhase.Control AND refData.set.stSleep.bEnable AND bDriveOn
   AND bSatisfied AND (fSpd <= refData.set.stSleep.fSpeed
                       OR (refData.set.stSleep.fFlow > REAL#0.0 AND bFlowOk AND fFlowV < refData.set.stSleep.fFlow)) THEN
  IF tNow - tSleepSince >= refData.set.stSleep.tDelay THEN
    IF refData.set.bReverse THEN
      fSpBoost := fSpTarget - ABS(fSpTarget) * refData.set.stSleep.fBoost / REAL#100.0;
    ELSE
      fSpBoost := fSpTarget + ABS(fSpTarget) * refData.set.stSleep.fBoost / REAL#100.0;
    END_IF;
    IF refData.set.stSleep.fBoost > REAL#0.0 AND refData.set.stSleep.tBoostTime > T#0s THEN
      ePhase := E_LoopPhase.Boost;
      tBoostStart := tNow;
    ELSE
      ePhase := E_LoopPhase.Sleep;
      tSleepStart := tNow;
      tWakeSince := tNow;
    END_IF;
  END_IF;
ELSE
  tSleepSince := tNow;
END_IF;

(* the setpoint in use *)
IF ePhase = E_LoopPhase.Filling AND refData.set.stFill.eMode = E_FillMode.Ramp THEN
  IF ePrev <> E_LoopPhase.Filling THEN
    fbFillRamp(fIn := fSpAct, bTrack := TRUE);          // the fill starts from the value
  ELSE
    fbFillRamp(fIn := fSpTarget, fRateUp := refData.set.stFill.fRate, fRateDown := REAL#0.0,
               eRateUnit := refData.set.eRateUnit, bTrack := FALSE);
  END_IF;
  fSpAct := fbFillRamp.fOut;
  fbSpRamp(fIn := fSpAct, bTrack := TRUE);
ELSIF ePhase = E_LoopPhase.Boost THEN
  fSpAct := fSpBoost;
  fbSpRamp(fIn := fSpAct, bTrack := TRUE);
ELSIF ePhase = E_LoopPhase.Idle OR ePhase = E_LoopPhase.Sleep OR ePhase = E_LoopPhase.Manual
      OR refData.set.fSpRamp <= REAL#0.0 OR bCfgBad THEN
  fbSpRamp(fIn := fSpTarget, bTrack := TRUE);
  fSpAct := fbSpRamp.fOut;
ELSE
  fbSpRamp(fIn := fSpTarget, fRateUp := refData.set.fSpRamp, fRateDown := refData.set.fSpRamp,
           eRateUnit := refData.set.eRateUnit, bTrack := FALSE);
  fSpAct := fbSpRamp.fOut;
END_IF;

(* the limits: the flow limit lowers the top *)
IF fRateS > 0.0 THEN fCapRate := fRateS; ELSE fCapRate := 5.0; END_IF;
IF refData.set.fFlowLimit > REAL#0.0 AND bFlowOk AND bDriveOn THEN
  IF fFlowV > refData.set.fFlowLimit THEN
    IF fFlowCap > fSpd THEN fFlowCap := fSpd; END_IF;   // start bringing it down from where it is
    fFlowCap := fFlowCap - fCapRate * MIN(1.0, (fFlowV - refData.set.fFlowLimit) / (0.2 * refData.set.fFlowLimit)) * fDt;
  ELSE
    fFlowCap := fFlowCap + fCapRate * MIN(1.0, (refData.set.fFlowLimit - fFlowV) / (0.2 * refData.set.fFlowLimit)) * fDt;
  END_IF;
  fFlowCap := LIMIT(fLoS, fFlowCap, fHiS);
  fHiS := fFlowCap;
ELSE
  fFlowCap := fHiS;
END_IF;
bOverride := stWHigh.bWarn AND ePhase <> E_LoopPhase.Idle AND ePhase <> E_LoopPhase.Sleep;
IF fRateS > 0.0 THEN fStepMax := fRateS * fDt; ELSE fStepMax := 1.0E30; END_IF;

(* the output *)
fTiS := TIME_TO_LREAL(refData.set.tTi) / 1000.0;
fTdS := TIME_TO_LREAL(refData.set.tTd) / 1000.0;
IF bCvGood THEN
  IF refData.set.bReverse THEN fE := fCv - fSpAct; ELSE fE := fSpAct - fCv; END_IF;
  IF ABS(fE) <= refData.set.fDeadband THEN fE := 0.0; END_IF;
ELSE
  fE := 0.0;
END_IF;
IF ePhase = E_LoopPhase.Idle OR ePhase = E_LoopPhase.Sleep THEN
  fSpd := 0.0;
  bPreload := TRUE;
  fI := 0.0;
ELSIF bOverride THEN
  fSpd := fLoS;                        // overpressure warning: straight to the minimum
  bPreload := TRUE;
ELSIF NOT bTargetRuns THEN
  bPreload := TRUE;                    // the drive has not started: hold the speed
ELSIF ePhase = E_LoopPhase.Manual THEN
  fWant := LIMIT(fLoS, fUse, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF ePhase = E_LoopPhase.Fallback THEN
  fWant := LIMIT(fLoS, fHoldSpeed, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF ePhase = E_LoopPhase.Filling AND refData.set.stFill.eMode = E_FillMode.Fixed THEN
  fWant := LIMIT(fLoS, refData.set.stFill.fSpeed, fHiS);
  fSpd := fSpd + LIMIT(-fStepMax, fWant - fSpd, fStepMax);
  bPreload := TRUE;
ELSIF NOT bCvGood THEN
  bPreload := TRUE;                    // the sensor is bad, not yet past its delay: hold the speed
ELSIF refData.set.eSource = E_LoopSource.External THEN
  IF fExtSpeed >= REAL#0.0 AND fExtSpeed <= REAL#3.4E38 THEN
    fExtHeld := fExtSpeed;
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
  IF fHiS < refData.set.fMaxSpeed THEN
    fI := MIN(fI, fHiS);               // the flow limit takes the integral down with it
  END_IF;
  fSpd := fWant;
END_IF;
IF ePhase <> E_LoopPhase.Idle AND ePhase <> E_LoopPhase.Sleep THEN
  IF NOT (fSpd = fSpd) THEN fSpd := fLoS; END_IF;
  fSpd := LIMIT(fLoS, fSpd, fHiS);
END_IF;
bAsk := ePhase = E_LoopPhase.Filling OR ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost
        OR ePhase = E_LoopPhase.Fallback OR ePhase = E_LoopPhase.Manual;
IF bAsk THEN fSpeed := LREAL_TO_REAL(fSpd); ELSE fSpeed := REAL#0.0; END_IF;
bHi := bAsk AND fSpd >= fHiS - 0.01;
bLo := bAsk AND fSpd <= fLoS + 0.01;
refData.sts.bFlowLimiting := bAsk AND fHiS < refData.set.fMaxSpeed AND bHi;
bAtMax := bHi AND NOT refData.sts.bFlowLimiting;
bAtMin := bLo;
bFilled := ePhase <> E_LoopPhase.Idle
           AND (bFilledRun OR refData.set.stFill.eMode = E_FillMode.Off OR refData.set.bReverse
                OR refData.set.eControl <> E_LoopControl.Pv
                OR ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost OR ePhase = E_LoopPhase.Sleep);
ipTarget.Request(bRun := bAsk, bHold := FALSE, fSpeed := fSpeed);
bRunning := bAsk AND ipTarget.bIsRunning;

(* hunting: crossings of the setpoint, each a swing beyond half the band either side *)
fHb := refData.set.fHuntBand / REAL#2.0;
IF (ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost) AND bAsk AND bTargetRuns AND bCvGood THEN
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
  refData.sts.nHuntCount := nHuntCur + REAL_TO_INT(INT_TO_REAL(nHuntPrev)
      * (REAL#1.0 - TIME_TO_REAL(tNow - tHuntAt) / TIME_TO_REAL(refData.set.tHuntWindow)));
ELSE
  nHuntCur := 0;
  nHuntPrev := 0;
  tHuntAt := tNow;
  refData.sts.nHuntCount := 0;
END_IF;

(* staging hints for an owner with more pumps *)
IF NOT (ePhase = E_LoopPhase.Control AND bAsk AND bTargetRuns AND bAtMax AND NOT bOverride
        AND fErrT > refData.set.fAtSpBand) THEN
  tMoreSince := tNow;
END_IF;
IF NOT (ePhase = E_LoopPhase.Control AND bAsk AND bTargetRuns AND bLo AND NOT bOverride) THEN
  tLessSince := tNow;
END_IF;
bMoreNeeded := ePhase = E_LoopPhase.Control AND bAtMax AND tNow - tMoreSince >= refData.set.tStageDelay;
bLessNeeded := ePhase = E_LoopPhase.Control AND bLo AND tNow - tLessSince >= refData.set.tStageDelay;

bAtSetpoint := (ePhase = E_LoopPhase.Control OR ePhase = E_LoopPhase.Boost OR ePhase = E_LoopPhase.Sleep)
               AND bCvGood AND ABS(fCv - fSpAct) <= refData.set.fAtSpBand;
fError := fErrT;
IF refData.set.eControl = E_LoopControl.Fixed AND bPvOk AND fSpTarget <> REAL#0.0 THEN
  IF refData.set.bReverse THEN fError := fPvV - fSpTarget; ELSE fError := fSpTarget - fPvV; END_IF;
END_IF;

(* status *)
bError := stWFill.bTrip OR stWHigh.bTrip OR stWLow.bTrip OR stWReach.bTrip OR stWHunt.bTrip
          OR (bPvAlarm AND refData.set.eOnBad = E_OnBad.Stop) OR (bCfgBad AND bRun);
bWarning := NOT bError AND (stWFill.bWarn OR stWHigh.bWarn OR stWLow.bWarn OR stWReach.bWarn OR stWHunt.bWarn
                            OR bPvAlarm OR refData.sts.bRefused);
IF stWHigh.bTrip OR stWHigh.bWarn THEN
  eErrorId := E_UtError.PressureHigh;
ELSIF stWLow.bTrip OR stWLow.bWarn THEN
  eErrorId := E_UtError.LowAtMax;
ELSIF bPvAlarm THEN
  eErrorId := E_UtError.SensorBad;
ELSIF stWFill.bTrip OR stWFill.bWarn THEN
  eErrorId := E_UtError.FillTimeout;
ELSIF stWReach.bTrip OR stWReach.bWarn THEN
  eErrorId := E_UtError.NotReaching;
ELSIF stWHunt.bTrip OR stWHunt.bWarn THEN
  eErrorId := E_UtError.Hunting;
ELSIF bCfgBad AND bRun THEN
  eErrorId := eCfgId;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault;
ELSIF NOT bRun THEN eState := E_State.Off;
ELSIF ePhase = E_LoopPhase.Sleep THEN eState := E_State.Waiting;
ELSIF bRunning THEN eState := E_State.Running;
ELSIF bAsk THEN eState := E_State.Starting;
ELSE eState := E_State.Held; END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.fSpeed := fSpeed;
refData.sts.fPv := fCv;
refData.sts.fSpNow := fSpAct;
refData.sts.bManual := refData.set.bManual;
refData.sts.bPvBad := stWPvBad.bActive;
refData.sts.ePhase := ePhase;
refData.sts.ePresetUsed := eUse;
refData.sts.bAtSetpoint := bAtSetpoint;
refData.sts.bFilled := bFilled;
refData.sts.bSleeping := ePhase = E_LoopPhase.Sleep;
bFirstScan := FALSE;

END_FUNCTION_BLOCK