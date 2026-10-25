(* UT_MOTOR_VSD EXTENDS UT_MOTOR — a variable speed drive over hard-wired IO.
Everything of UT_MOTOR (modes, Hand / Jog, protections, the plug, totals,
Data) plus the speed reference. Inherited pins here: Q = drive run command;
Feedback = drive running relay; DriveFault = drive fault relay; Jog runs at
jogSpeed; Ready also needs DriveReady.

Speed asked for: Jog -> jogSpeed; Hand -> the HandSpeed pin when wired,
else Vsd.set.handSpeed (kept); Auto linked -> the owner's ReqSpeed (NaN =
AutoSpeed); Auto -> AutoSpeed. A NaN keeps the last good one. Clamped to
minSpeed..maxSpeed; a target inside the skip band holds at its edge, the
ramp jumps over it; ramped by accelRate / decelRate (0 = the drive ramps),
exact at any rate (LREAL, whole-ms steps). A start begins from minSpeed.

Drive protections: speedDev (|reference - SpeedFb| past sp while running,
SpeedFb wired), driveNotReady (the ready relay lost while running). Drive
reset: DriveReset pulses on an operator reset, and with autoDriveReset once
per AUTO / RETRY attempt of a drive trip whose relay is still on; the relay
dropping within resetPulse + 2 s clears the trip at once.
AtSpeed: at the reference by SpeedFb, else driveRamp after the reference
stopped changing. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_MOTOR_VSD EXTENDS UT_MOTOR
  VAR_INPUT
    AutoSpeed : REAL := 100.0; (* Auto speed % when the owner gives none (NaN keeps the last good) *)
    HandSpeed : REAL := -1.0; (* Hand speed % from a pot; < 0 / NaN = Vsd.set.handSpeed *)
    DriveReady : BOOL := TRUE; (* the drive's ready relay *)
    SpeedFb : REAL := -1.0; (* actual speed %, -1 = not wired *)
  END_VAR
  VAR_OUTPUT
    SpeedRef : REAL; (* reference % after clamp, skip band, ramp *)
    SpeedRefRaw : UINT; (* scaled to rawMin..rawMax (a Modbus register) *)
    SpeedRefScaled : REAL; (* scaled to rawMin..rawMax, not rounded (an analog output: V or mA) *)
    DriveReset : BOOL; (* reset pulse to the drive *)
    AtSpeed : BOOL;
  END_VAR
  VAR_IN_OUT
    Vsd : UT_MOTOR_VSD_DATA;
  END_VAR
  VAR RETAIN
    vKeptSet : UT_MOTOR_VSD_SET;
    vKeptGood : BOOL;
  END_VAR
  VAR
    vKeep : UT_KEEP;
    vOk : BOOL;
    vFault : UT_FAULT;
    vHand : UT_FAULT;
    vWarn : UT_FAULT;
    handWired : BOOL;
    sDev : UT_PROT_ST;
    sNotReady : UT_PROT_ST;
    xb : BOOL;
    vNow : TIME;
    tPrev : TIME;
    dMs : LINT;
    dS : LREAL;
    perS : LREAL;
    sp : REAL;
    wantSpd : REAL; (* the last good speed request *)
    lo : REAL;
    hi : REAL;
    bandOn : BOOL;
    target : REAL;
    targetPrev : REAL;
    targetAt : TIME; (* when the target last changed (driveRamp) *)
    ramp : LREAL;
    runWas : BOOL;
    pulsing : BOOL;
    pulseAt : TIME;
    clearUntil : TIME; (* a dropped relay within this clears the drive trip *)
    armed : BOOL; (* a drive retry wait is counting *)
    skipHeld : BOOL;
    rawR : REAL;
    sc : BOOL;
    spdShown : REAL;
  END_VAR


METHOD PUBLIC OVERRIDE IsVsd : BOOL
  IsVsd := TRUE;
END_METHOD
METHOD PUBLIC OVERRIDE GetSpeed : REAL
  IF NOT Running THEN
    GetSpeed := 0.0;
  ELSIF SpeedFb >= 0.0 AND SpeedFb <= 3.4E38 THEN
    GetSpeed := SpeedFb;
  ELSE
    GetSpeed := SpeedRef;
  END_IF;
END_METHOD

vNow := TIME();
vKeep();
IF vKeep.RestoreSet THEN
  Vsd.set := vKeptSet;
END_IF;
handWired := HandSpeed >= 0.0 AND HandSpeed <= 100.0;
vOk := UT_MOTOR_VSD_CHECK(HandWired := handWired, S := Vsd.set, Fault => vFault, Hand => vHand, Warn => vWarn);
IF NOT vOk AND vKeptGood AND NOT vKeep.FirstBoot THEN
  IF vFault <> UT_F_NONE THEN Vsd.sts.refused := vFault;
  ELSIF vHand <> UT_F_NONE THEN Vsd.sts.refused := vHand;
  ELSE Vsd.sts.refused := vWarn;
  END_IF;
  Vsd.set := vKeptSet;
  vOk := UT_MOTOR_VSD_CHECK(HandWired := handWired, S := Vsd.set, Fault => vFault, Hand => vHand, Warn => vWarn);
END_IF;
IF vKeep.SaveSet AND (vOk OR NOT vKeptGood) THEN
  vKeptSet := Vsd.set;
  vKeptGood := vOk;
END_IF;
CASE Vsd.set.rateUnit OF
UT_PER_SEC: perS := 1.0;
UT_PER_MIN: perS := 60.0;
UT_PER_HOUR: perS := 3600.0;
UT_PER_DAY: perS := 86400.0;
ELSE
  perS := 0.0;
END_CASE;

(* hooks for the base *)
vCfgFault := vFault <> UT_F_NONE;
vCfgHand := vHand <> UT_F_NONE;
vCfgWarn := vWarn <> UT_F_NONE;
IF vCfgFault THEN vCfgId := vFault; ELSIF vCfgHand THEN vCfgId := vHand; ELSE vCfgId := vWarn; END_IF;
vStartBlock := NOT DriveReady;
vStartDone := AtSpeed;           (* the current mask and startTooLong count from at speed *)
IF NOT DriveReady THEN
  vStatus := UT_ST_DRIVE_NOT_READY;
ELSIF skipHeld AND runReq THEN
  vStatus := UT_ST_SKIP_EDGE;
ELSE
  vStatus := UT_ST_IDLE;
END_IF;
(* the drive's own protections (from last scan's reference) *)
xb := UT_PROT_EXT_CLEAR(Sum := vTrip);
xb := UT_LEVEL_RUN(TNow := vNow, In := ABS(SpeedRef - SpeedFb), Good := TRUE, High := TRUE, UseIn := TRUE, Switch := FALSE,
                   Enable := curMode <> UT_MODE_OOS AND SpeedFb >= 0.0 AND Running AND NOT Data.simulate
                             AND vNow - targetAt >= Vsd.set.driveRamp,
                   Release := FALSE, ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Level := Vsd.set.speedDev,
                   Sts := Vsd.sts.speedDev, St := sDev);
xb := UT_PROT_EXT(Bit := 16#100, Id := UT_F_SPEED_DEV, Reset := Vsd.set.speedDev.reset, St := sDev,
                  Sts := Vsd.sts.speedDev, Sum := vTrip);
xb := UT_PROT_RUN(TNow := vNow, Cause := curMode <> UT_MODE_OOS AND NOT DriveReady AND (runReq OR Vsd.sts.driveNotReady.tripped),
                  ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Vsd.set.driveNotReady,
                  Sts := Vsd.sts.driveNotReady, St := sNotReady);
xb := UT_PROT_EXT(Bit := 16#400, Id := UT_F_DRIVE_NOT_READY, Reset := Vsd.set.driveNotReady.reset, St := sNotReady,
                  Sts := Vsd.sts.driveNotReady, Sum := vTrip);
(* the drive fault relay dropping right after a reset pulse clears the trip at once *)
vDriveCleared := vNow < clearUntil AND NOT DriveFault AND Data.sts.drive.tripped;

SUPER();

(* the speed asked for *)
IF Jogging THEN
  sp := Vsd.set.jogSpeed;
ELSIF curMode = UT_MODE_HAND THEN
  IF handWired THEN
    sp := HandSpeed;
  ELSE
    sp := Vsd.set.handSpeed;
  END_IF;
ELSIF Linked AND linkSpeed = linkSpeed THEN
  sp := linkSpeed;
ELSE
  sp := AutoSpeed;
END_IF;
IF ABS(sp) <= 3.4E38 THEN
  wantSpd := sp;
END_IF;
lo := LIMIT(0.0, Vsd.set.minSpeed, 100.0);
hi := LIMIT(lo, Vsd.set.maxSpeed, 100.0);
target := LIMIT(lo, wantSpd, hi);
(* skip band: a target inside it holds at the edge on the reference's side *)
bandOn := Vsd.set.skipHigh > Vsd.set.skipLow;
skipHeld := FALSE;
IF bandOn AND target > Vsd.set.skipLow AND target < Vsd.set.skipHigh THEN
  IF (ramp >= Vsd.set.skipHigh OR Vsd.set.skipLow < lo) AND Vsd.set.skipHigh <= hi THEN
    target := Vsd.set.skipHigh;
    skipHeld := TRUE;
  ELSIF Vsd.set.skipLow >= lo THEN
    target := Vsd.set.skipLow;
    skipHeld := TRUE;
  END_IF;
END_IF;
IF target <> targetPrev THEN
  targetAt := vNow;
END_IF;
targetPrev := target;
(* ramp *)
IF NOT runReq THEN
  ramp := REAL_TO_LREAL(lo);     (* a start begins from the minimum speed *)
  SpeedRef := 0.0;
ELSE
  IF NOT runWas THEN
    tPrev := vNow;
    targetAt := vNow;
  END_IF;
  dS := 0.0;
  dMs := TIME_TO_LINT(vNow - tPrev);
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);
    IF perS > 0.0 THEN
      dS := LINT_TO_LREAL(dMs) / 1000.0 / perS;
    END_IF;
  END_IF;
  ramp := LIMIT(REAL_TO_LREAL(lo), ramp, REAL_TO_LREAL(hi));
  IF REAL_TO_LREAL(target) > ramp THEN
    IF Vsd.set.accelRate > 0.0 AND perS > 0.0 THEN
      ramp := MIN(REAL_TO_LREAL(target), ramp + REAL_TO_LREAL(Vsd.set.accelRate) * dS);
    ELSE
      ramp := REAL_TO_LREAL(target);
    END_IF;
    IF bandOn AND ramp > REAL_TO_LREAL(Vsd.set.skipLow) AND ramp < REAL_TO_LREAL(Vsd.set.skipHigh) THEN
      ramp := REAL_TO_LREAL(Vsd.set.skipHigh);   (* jump over the band *)
    END_IF;
  ELSIF REAL_TO_LREAL(target) < ramp THEN
    IF Vsd.set.decelRate > 0.0 AND perS > 0.0 THEN
      ramp := MAX(REAL_TO_LREAL(target), ramp - REAL_TO_LREAL(Vsd.set.decelRate) * dS);
    ELSE
      ramp := REAL_TO_LREAL(target);
    END_IF;
    IF bandOn AND ramp > REAL_TO_LREAL(Vsd.set.skipLow) AND ramp < REAL_TO_LREAL(Vsd.set.skipHigh) THEN
      ramp := REAL_TO_LREAL(Vsd.set.skipLow);
    END_IF;
  END_IF;
  SpeedRef := LREAL_TO_REAL(ramp);
END_IF;
runWas := runReq;
rawR := UT_SCALE(In := SpeedRef, InMin := 0.0, InMax := 100.0, OutMin := Vsd.set.rawMin, OutMax := Vsd.set.rawMax,
                 Clamp := TRUE, SpanBad => sc);
IF NOT (rawR >= 0.0) THEN
  rawR := 0.0;
ELSIF rawR > 65535.0 THEN
  rawR := 65535.0;
END_IF;
SpeedRefRaw := REAL_TO_UINT(rawR);
SpeedRefScaled := rawR;

(* drive reset: an operator reset, and one pulse per retry attempt *)
IF pulsing AND vNow - pulseAt >= Vsd.set.resetPulse THEN
  pulsing := FALSE;
END_IF;
IF Data.sts.drive.tripped AND Data.sts.drive.timeLeft > T#0s THEN
  armed := TRUE;
END_IF;
IF (resetReq AND DriveFault)
   OR (Vsd.set.autoDriveReset AND armed AND Data.sts.drive.tripped AND Data.sts.drive.timeLeft = T#0s AND DriveFault
       AND Data.set.drive.reset <> UT_RST_MANUAL) THEN
  pulsing := TRUE;
  pulseAt := vNow;
  clearUntil := vNow + Vsd.set.resetPulse + T#2s;
  armed := FALSE;
END_IF;
IF NOT Data.sts.drive.tripped THEN
  armed := FALSE;
END_IF;
DriveReset := pulsing;
Ready := Ready AND DriveReady;
Data.sts.ready := Ready;

IF SpeedFb >= 0.0 AND NOT Data.simulate THEN
  AtSpeed := Running AND ABS(SpeedRef - SpeedFb) <= Vsd.set.speedDev.sp;
ELSE
  AtSpeed := Running AND ramp = REAL_TO_LREAL(target) AND vNow - targetAt >= Vsd.set.driveRamp;
END_IF;
Vsd.sts.atSpeed := AtSpeed;
Vsd.sts.speedRef := SpeedRef;
Vsd.sts.speedFb := SpeedFb;
IF SpeedFb >= 0.0 AND SpeedFb <= 3.4E38 AND NOT Data.simulate AND Running THEN
  spdShown := SpeedFb;
ELSE
  spdShown := SpeedRef;
END_IF;
IF Vsd.set.ratedHz > 0.0 AND Vsd.set.ratedHz <= 3.4E38 THEN
  Vsd.sts.speedHz := spdShown / 100.0 * Vsd.set.ratedHz;
ELSE
  Vsd.sts.speedHz := 0.0;
END_IF;
IF Vsd.set.ratedRpm > 0.0 AND Vsd.set.ratedRpm <= 3.4E38 THEN
  Vsd.sts.speedRpm := spdShown / 100.0 * Vsd.set.ratedRpm;
ELSE
  Vsd.sts.speedRpm := 0.0;
END_IF;

END_FUNCTION_BLOCK