(* UT_VALVE_MOD — modulating valve or damper with a positioner (4-20 mA /
0-10 V): Out is the demand % (100 - demand when reverseActing), OutRaw the
same scaled to rawMin..rawMax (0 on a config fault). The position is the
feedback (PosFb) when good, else a travel estimate (the demand ramped at a
full stroke per strokeTime); never the demand alone.

Where it goes (UT_VALVE's core decides the Aim): Auto = Sp (e.g. a PID
output; NaN keeps the last good); OpenCmd / CloseCmd drive fully open /
closed (set.cmdPulse as UT_VALVE_FLOAT, decision 78); linked = the owner's
ReqPos (none: 100 %), its open off = restPos; Hand = HandSp when wired,
else the kept handPos (operator commands write it; bumpless on entry);
Off / Interlock / a trip = safePosition (< 0 stays; holdOnFault: a trip
holds the demand). tightShutoff / fullOpenAbove win over outMin / outMax;
rampRate limits the demand (0 = off). Feedback range and deviation:
UT_POS_FB_RUN. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_VALVE_MOD EXTENDS UT_VALVE
  VAR_INPUT
    Sp : REAL; (* Auto position %; NaN keeps the last good *)
    HandSp : REAL := -1.0; (* Hand position % from a pot; < 0 / NaN = set.handPos *)
    PosFb : UT_I_MEAS; (* position feedback; NULL = the travel estimate *)
  END_VAR
  VAR_OUTPUT
    Out : REAL; (* demand % (100 - demand when reverseActing) *)
    OutRaw : UINT; (* scaled; 0 on a config fault *)
  END_VAR
  VAR_IN_OUT
    Modul : UT_VALVE_MOD_DATA;
  END_VAR
  VAR RETAIN
    qKeptSet : UT_VALVE_MOD_SET;
    qKeptGood : BOOL;
  END_VAR
  VAR
    qKeep : UT_KEEP;
    dRamp : UT_RAMP; (* the demand ramp *)
    eRamp : UT_RAMP; (* the travel estimate *)
    qSt : UT_POS_FB_ST;
    qOk : BOOL;
    qFault : UT_FAULT;
    qWarn : UT_FAULT;
    qNow : TIME;
    qx : BOOL;
    fbFit : BOOL;
    fbV : REAL;
    fbG : BOOL;
    fbOk : BOOL;
    qLsO : BOOL;
    qLsC : BOOL;
    qIsO : BOOL;
    qIsC : BOOL;
    pos : REAL;
    req : REAL;
    demand : REAL;
    autoSp : REAL;
    ovr : INT; (* Auto command override: 0 none, 1 closed, 2 open *)
    hOc : BOOL;
    hCc : BOOL;
    htPrev : REAL := -2.0;
    handWired : BOOL;
    ramped : BOOL;
    qHold : BOOL;
    rate : REAL;
    raw : REAL;
    qMoving : BOOL;
    qStatus : UT_STATUS := UT_ST_IDLE;
    qTime : TIME;
    fp : REAL;
  END_VAR


qNow := TIME();
qKeep();
IF qKeep.RestoreSet THEN
  Modul.set := qKeptSet;
END_IF;
qOk := UT_VALVE_MOD_CHECK(S := Modul.set, Fault => qFault, Warn => qWarn);
IF NOT qOk AND qKeptGood AND NOT qKeep.FirstBoot THEN
  IF qFault <> UT_F_NONE THEN Modul.sts.refused := qFault; ELSE Modul.sts.refused := qWarn; END_IF;
  Modul.set := qKeptSet;
  qOk := UT_VALVE_MOD_CHECK(S := Modul.set, Fault => qFault, Warn => qWarn);
END_IF;
IF qKeep.SaveSet AND (qOk OR NOT qKeptGood) THEN
  qKeptSet := Modul.set;
  qKeptGood := qOk;
END_IF;

(* the feedback and the position in use *)
qLsO := Data.set.useOpenLs AND OpenLs AND NOT Data.simulate;
qLsC := Data.set.useClosedLs AND ClosedLs AND NOT Data.simulate;
fbFit := FALSE;
fbV := 0.0;
fbG := FALSE;
IF PosFb <> NULL THEN
  fbFit := PosFb.IsFitted();
  fbV := PosFb.GetValue();
  fbG := PosFb.GoodNow();
END_IF;
qx := UT_PROT_EXT_CLEAR(Sum := vTrip);
pos := UT_POS_FB_RUN(TNow := qNow, Fitted := fbFit, Value := fbV, Good := fbG, Target := demand, Estimate := eRamp.Out,
                     Settled := NOT dRamp.Ramping AND NOT eRamp.Ramping,
                     Supervise := core.CurMode <> UT_MODE_OOS AND NOT Data.simulate, LsOpen := qLsO, LsClosed := qLsC,
                     ResetReq := core.ResetReq, RetryWindow := Data.set.retryWindow, Set := Modul.set.pos,
                     Sts := Modul.sts.pos, St := qSt, Sum := vTrip, IsOpen => qIsO, IsClosed => qIsC, FbOk => fbOk);

(* hooks for the base *)
vOwnTravel := TRUE;
vPos := pos;
vMoving := qMoving;
vConfirmed := fbOk OR qLsO OR qLsC;
vIsOpen := qIsO;
vIsClosed := qIsC;
vAtRest := qIsC;
vPosNow := pos;
vHandOpen := 100.0;
vHandRest := 0.0;
IF Modul.set.safePosition < 0.0 THEN
  vSafePos := -1.0;
  fp := 0.0;
ELSE
  vSafePos := LIMIT(0.0, Modul.set.safePosition, 100.0);
  fp := vSafePos;
END_IF;
vAway := ABS(pos - fp) > 0.5;
vCauses.bothLimits := qLsO AND qLsC;
vStroke := FALSE;
vCfgFault := qFault <> UT_F_NONE;
vCfgHand := FALSE;
vCfgAuto := FALSE;
vCfgWarn := qWarn <> UT_F_NONE;
IF vCfgFault THEN vCfgId := qFault; ELSE vCfgId := qWarn; END_IF;
vStatus := qStatus;
vTime := qTime;

SUPER();

(* Auto: Sp, or OpenCmd / CloseCmd (decision 78) *)
IF Sp = Sp AND ABS(Sp) <= 3.4E38 THEN
  autoSp := LIMIT(0.0, Sp, 100.0);
END_IF;
IF NOT core.Auto OR core.Linked THEN
  ovr := 0;
ELSIF Data.set.cmdPulse THEN
  IF CloseCmd AND NOT hCc THEN
    IF ovr = 0 THEN ovr := 1; ELSE ovr := 0; END_IF;
  ELSIF OpenCmd AND NOT hOc THEN
    IF ovr = 0 THEN ovr := 2; ELSE ovr := 0; END_IF;
  END_IF;
ELSIF CloseCmd THEN
  ovr := 1;
ELSIF OpenCmd THEN
  ovr := 2;
ELSE
  ovr := 0;
END_IF;
hOc := OpenCmd;
hCc := CloseCmd;

(* Hand: the pin, else the kept handPos (an operator command writes it) *)
handWired := HandSp >= 0.0 AND HandSp <= 100.0;
IF core.HandTarget <> htPrev THEN
  htPrev := core.HandTarget;
  IF core.Hand THEN
    IF core.HandTarget >= 0.0 THEN
      Modul.set.handPos := LIMIT(0.0, core.HandTarget, 100.0);
    ELSIF pos >= 0.0 THEN
      Modul.set.handPos := pos;  (* stop: where it is *)
    END_IF;
  END_IF;
END_IF;

(* the request *)
ramped := FALSE;
qHold := FALSE;
req := demand;
CASE core.Aim OF
UT_VA_OFF:
  req := 0.0;
UT_VA_SAFE:
  IF (core.Fault AND Modul.set.holdOnFault) OR vSafePos < 0.0 THEN
    qHold := TRUE;
  ELSE
    req := vSafePos;
  END_IF;
UT_VA_REST:
  ramped := TRUE;
  IF core.Linked THEN req := Modul.set.restPos;
  ELSIF ovr = 1 THEN req := 0.0;
  ELSIF ovr = 2 THEN req := 100.0;
  ELSE req := autoSp;
  END_IF;
UT_VA_RUN:
  ramped := TRUE;
  IF core.Exercising THEN req := 100.0;
  ELSIF core.Linked THEN
    IF core.RunPos = core.RunPos THEN req := core.RunPos; ELSE req := 100.0; END_IF;
  ELSIF ovr = 1 THEN req := 0.0;
  ELSIF ovr = 2 THEN req := 100.0;
  ELSE req := autoSp;
  END_IF;
UT_VA_HAND:
  ramped := TRUE;
  IF handWired THEN req := HandSp; ELSE req := Modul.set.handPos; END_IF;
ELSE
  qHold := TRUE;                 (* HOLD: stay *)
END_CASE;
IF core.DriveTrip THEN
  qHold := TRUE;
END_IF;
IF qHold THEN
  req := demand;
ELSIF ramped THEN
  (* tight shutoff and full open win over the clamp *)
  IF Modul.set.tightShutoff > 0.0 AND req < Modul.set.tightShutoff THEN
    req := 0.0;
  ELSIF Modul.set.fullOpenAbove < 100.0 AND req > Modul.set.fullOpenAbove THEN
    req := 100.0;
  ELSE
    req := LIMIT(Modul.set.outMin, req, Modul.set.outMax);
  END_IF;
END_IF;
req := LIMIT(0.0, req, 100.0);
dRamp(In := req, RateUp := Modul.set.rampRate, RateDown := Modul.set.rampRate, RateUnit := Modul.set.rateUnit,
      Track := NOT ramped OR Modul.set.rampRate <= 0.0);
demand := dRamp.Out;

(* the signal *)
IF core.Aim = UT_VA_OFF THEN
  Out := 0.0;
ELSIF Modul.set.reverseActing THEN
  Out := 100.0 - demand;
ELSE
  Out := demand;
END_IF;
raw := UT_SCALE(In := Out, InMin := 0.0, InMax := 100.0, OutMin := Modul.set.rawMin, OutMax := Modul.set.rawMax);
IF NOT (raw >= 0.0) THEN
  raw := 0.0;
ELSIF raw > 65535.0 THEN
  raw := 65535.0;
END_IF;
IF qFault <> UT_F_NONE THEN
  raw := 0.0;
END_IF;
OutRaw := REAL_TO_UINT(raw);

(* the travel estimate: the demand at a full stroke per strokeTime *)
rate := 0.0;
IF Modul.set.strokeTime > T#0s THEN
  rate := 100000.0 / LINT_TO_REAL(TIME_TO_LINT(Modul.set.strokeTime));
END_IF;
eRamp(In := demand, RateUp := rate, RateDown := rate, RateUnit := UT_PER_SEC, Track := rate <= 0.0);
IF NOT fbOk THEN
  pos := eRamp.Out;
  qIsO := qLsO OR pos >= Modul.set.pos.openThreshold;
  qIsC := qLsC OR pos <= Modul.set.pos.closedThreshold;
  IF qLsO AND qLsC THEN
    qIsO := FALSE;
    qIsC := FALSE;
  END_IF;
END_IF;
IF fbOk THEN
  qMoving := dRamp.Ramping OR ABS(demand - pos) > Modul.set.pos.deadband;
ELSE
  qMoving := dRamp.Ramping OR eRamp.Ramping;
END_IF;

(* outputs and status (the base shows the status next scan) *)
Position := pos;
IsOpen := qIsO;
IsClosed := qIsC;
Moving := qMoving;
qTime := T#0s;
IF qMoving AND req > pos THEN
  qStatus := UT_ST_OPENING;
ELSIF qMoving THEN
  qStatus := UT_ST_CLOSING;
ELSIF qIsO THEN
  qStatus := UT_ST_OPEN;
ELSIF qIsC THEN
  qStatus := UT_ST_CLOSED;
ELSE
  qStatus := UT_ST_AT_POSITION;
END_IF;
IF qMoving AND rate > 0.0 THEN
  qTime := LINT_TO_TIME(REAL_TO_LINT(ABS(req - pos) / rate * 1000.0));
END_IF;
Modul.sts.demand := demand;
Modul.sts.handPos := Modul.set.handPos;

END_FUNCTION_BLOCK