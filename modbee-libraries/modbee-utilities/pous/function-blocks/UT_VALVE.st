(* UT_VALVE — a two-position valve, cylinder or damper (every kind of decision
4); the base of UT_VALVE_FLOAT and UT_VALVE_MOD (81b). Offers the UT_I_VALVE
plug: an owner (a zone, a route, a station) wires the instance to its Valve
pin and calls Request every scan. No Run pin (a valve opens).

Who moves it: OOS = every output off (spring kinds go to their spring side);
Off = the safe position; Hand = LocalOpen / LocalClose / LocalStop, cmdOpen /
cmdClose / cmdStop, OpenCmd / CloseCmd (bumpless entry; Interlock / a trip
set the Hand target safe); Auto linked = the owner's ReqOpen (own Open
ignored; CloseCmd / cmdClose hold it closed until the owner's open drops);
Auto = Open per set.input (HELD / TOGGLE / KEEPALIVE / PULSE_TIMER), OpenCmd
latch, CloseCmd. Every mode: Interlock FALSE / a trip -> safe; a config
fault -> outputs off; Permissive FALSE holds back a move away from safe.

Kinds (set.valveType): SPRING (NC solenoid / spring-return motor: OpenOut
held), SPRING_NO (NO solenoid: CloseOut held to close), DOUBLE_HELD (5/2:
OpenOut / CloseOut held), DOUBLE_PULSE (latching 3-wire or 2-wire H-bridge:
OpenOut / CloseOut pulses), MOTOR (OpenOut / CloseOut drive with a reversal
pause; driveHold keeps the drive on at the end). Open / closed: by the end
switch when fitted (useOpenLs / useClosedLs), else after openTime /
closeTime from the drive (UT_TRAVEL_RUN). Latching: no automatic re-pulse,
nothing sent at power-up (the last commanded position is kept, tot.lastPos),
a fresh command re-sends its pulse, Reset takes the requested position as
true and sends nothing.

Exercise (exerciseEnable): one open-hold-close cycle when resting in Auto
for exerciseEvery, or on the Exercise pin / cmdExercise; a request wins.
Settings kept; a bad write is put back (decision 62).

Variants (EXTENDS) set vOwnTravel and the hooks before SUPER(); the base
then runs the core and the common outputs and skips its two-position travel. *)

FUNCTION_BLOCK UT_VALVE IMPLEMENTS UT_I_VALVE
  VAR_INPUT
    Open : BOOL; (* Auto: open while TRUE (per set.input); ignored while linked *)
    OpenCmd : BOOL; (* rising: open (Auto latched; Hand open) *)
    CloseCmd : BOOL; (* rising: close in Auto and Hand; wins *)
    Reset : BOOL R_EDGE; (* reset trips whose cause has gone; latching: the requested position is true *)
    Interlock : BOOL := TRUE; (* FALSE: safe position in every mode *)
    Permissive : BOOL := TRUE; (* FALSE: no move away from safe starts *)
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto, 3 OOS *)
    ExpectAuto : BOOL;
    Exercise : BOOL R_EDGE; (* one exercise cycle when idle *)
    OpenLs : BOOL; (* limit switches / 5-wire end contacts *)
    ClosedLs : BOOL;
    DriveFault : BOOL; (* actuator thermal / fault relay *)
    TorqueOpen : BOOL; (* torque switch tripped = jammed *)
    TorqueClose : BOOL;
    ActRemote : BOOL := TRUE; (* FALSE: actuator in Local, not driven *)
    SwHand : BOOL;
    SwAuto : BOOL;
    LocalOpen : BOOL R_EDGE; (* Hand *)
    LocalClose : BOOL R_EDGE;
    LocalStop : BOOL R_EDGE; (* Hand, motorised: stop travel where it is *)
  END_VAR
  VAR_OUTPUT
    IsOpen : BOOL; (* by switch, or after openTime *)
    IsClosed : BOOL;
    OpenOut : BOOL;
    CloseOut : BOOL;
    Moving : BOOL;
    Position : REAL; (* 0 / 100, -1 moving / unknown *)
    Fault : BOOL;
    Warning : BOOL;
    Ready : BOOL;
    Auto : BOOL;
    Hand : BOOL;
    Linked : BOOL;
    State : UT_STATE;
  END_VAR
  VAR_IN_OUT
    Data : UT_VALVE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_VALVE_SET;
    keptGood : BOOL;
    keptTot : UT_VALVE_TOT;
  END_VAR
  VAR PROTECTED
    core : UT_VALVE_CORE; (* read by a variant after SUPER(): core.Aim, core.HandTarget, core.RunPos ... *)
    vOwnTravel : BOOL; (* the variant drives and reports the position *)
    vPos : REAL; (* its position % (-1 unknown) *)
    vMoving : BOOL;
    vConfirmed : BOOL;
    vIsOpen : BOOL;
    vIsClosed : BOOL;
    vAtRest : BOOL;
    vAway : BOOL;
    vPosNow : REAL;
    vHandOpen : REAL := 100.0;
    vHandRest : REAL;
    vSafePos : REAL;
    vCauses : UT_VALVE_CAUSES;
    vTrip : UT_PROT_EXT_SUM;
    vStroke : BOOL;
    vCfgFault : BOOL;
    vCfgHand : BOOL;
    vCfgAuto : BOOL;
    vCfgWarn : BOOL;
    vCfgId : UT_FAULT;
    vStatus : UT_STATUS := UT_ST_IDLE;
    vTime : TIME;
  END_VAR
  VAR
    keep : UT_KEEP;
    travel : UT_TRAVEL_RUN;
    co : UT_CHANGEOVER_RUN;
    ok : BOOL;
    cfgF : UT_FAULT;
    cfgW : UT_FAULT;
    tCur : TIME;
    isMotor : BOOL;
    latching : BOOL;
    useO : BOOL;
    useC : BOOL;
    lsO : BOOL;
    lsC : BOOL;
    safeT : INT; (* the safe target: 1 closed, 2 open, 0 stay *)
    springT : INT; (* where the spring takes it with the outputs off (0 none) *)
    target : INT; (* 1 closed, 2 open, 0 hold *)
    lastTarget : INT;
    coil : INT; (* held coil state *)
    pulseDir : INT;
    pulseAt : TIME;
    pulsedFor : INT;
    travelT : INT;
    go : BOOL;
    motorRun : BOOL;
    redrive : BOOL;
    assumeT : INT;
    slowCause : BOOL;
    permHeld : BOOL;
    causes : UT_VALVE_CAUSES;
    saveNow : BOOL;
    x : BOOL;
    mPos : REAL;
    mTimeLeft : TIME;
    mConfirmed : BOOL;
    mIsOpen : BOOL;
    mIsClosed : BOOL;
  END_VAR


METHOD PUBLIC Request : BOOL
  VAR_INPUT
    ReqOpen : BOOL;
    ReqPos : REAL;
    Owner : STRING(12);
  END_VAR
  Request := core.Link(ReqOpen := ReqOpen, ReqPos := ReqPos, Owner := Owner);
END_METHOD
METHOD PUBLIC IsOpenNow : BOOL
  IsOpenNow := mIsOpen;
END_METHOD
METHOD PUBLIC IsClosedNow : BOOL
  IsClosedNow := mIsClosed;
END_METHOD
METHOD PUBLIC IsConfirmed : BOOL
  IsConfirmed := mConfirmed;
END_METHOD
METHOD PUBLIC GetPosition : REAL
  GetPosition := mPos;
END_METHOD
METHOD PUBLIC AtPosition : BOOL
  VAR_INPUT
    N : INT;
  END_VAR
  IF N = 0 THEN
    AtPosition := mIsClosed;
  ELSIF N = 1 THEN
    AtPosition := mIsOpen;
  ELSE
    AtPosition := FALSE;
  END_IF;
END_METHOD
METHOD PUBLIC IsMoving : BOOL
  IsMoving := Moving;
END_METHOD
METHOD PUBLIC TimeToOpen : TIME
  TimeToOpen := mTimeLeft;
END_METHOD
METHOD PUBLIC IsReady : BOOL
  IsReady := Ready AND Auto;
END_METHOD
METHOD PUBLIC IsAuto : BOOL
  IsAuto := Auto;
END_METHOD
METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := core.CurStatus;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := core.CurFault;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := core.StopReason;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := Fault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := Warning;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := core.CurLocked;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := TRUE;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := core.CurNe;
END_METHOD

tCur := TIME();
keep(TotalsNow := saveNow);
saveNow := FALSE;
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := UT_VALVE_CHECK(TwoPos := NOT vOwnTravel, S := Data.set, Fault => cfgF, Warn => cfgW);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN Data.sts.refused := cfgF; ELSE Data.sts.refused := cfgW; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_VALVE_CHECK(TwoPos := NOT vOwnTravel, S := Data.set, Fault => cfgF, Warn => cfgW);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

isMotor := Data.set.valveType = UT_VT_MOTOR;
latching := Data.set.valveType = UT_VT_DOUBLE_PULSE;
useO := Data.set.useOpenLs AND NOT Data.simulate;
useC := Data.set.useClosedLs AND NOT Data.simulate;
lsO := useO AND OpenLs;
lsC := useC AND ClosedLs;
CASE Data.set.safePosition OF
UT_SAFE_OPEN: safeT := 2;
UT_SAFE_HOLD: safeT := 0;
ELSE
  safeT := 1;
END_CASE;
CASE Data.set.valveType OF
UT_VT_SPRING: springT := 1;
UT_VT_SPRING_NO: springT := 2;
ELSE
  springT := 0;
END_CASE;

IF NOT vOwnTravel THEN
  (* the two-position travel causes (from last scan's move) *)
  causes.openTimeout := travel.Timeout AND travelT = 2;
  causes.closeTimeout := travel.Timeout AND travelT = 1;
  causes.bothLimits := lsO AND lsC;
  causes.positionLost := travel.Lost;
  causes.noMovement := travel.NoMove;
  causes.torque := isMotor AND (TorqueOpen OR (TorqueClose AND NOT (Data.set.closeOnTorque AND travelT = 1)));
  IF travel.StrokeDone AND travel.Confirmed AND Data.set.strokeWarn > T#0s THEN
    slowCause := travel.StrokeTime > Data.set.strokeWarn;
  END_IF;
  IF Data.set.strokeWarn <= T#0s THEN
    slowCause := FALSE;
  END_IF;
  causes.slowStroke := slowCause;
  IF lastTarget > 0 THEN
    vPosNow := INT_TO_REAL(lastTarget);
  ELSE
    vPosNow := INT_TO_REAL(travel.Pos);
  END_IF;
  vHandOpen := 2.0;
  vHandRest := 1.0;
  IF safeT = 0 THEN vSafePos := -1.0; ELSE vSafePos := INT_TO_REAL(safeT); END_IF;
  vAtRest := travel.Pos = 1;
  vAway := lastTarget = 2 AND safeT <> 2;
  IF safeT = 2 THEN vAway := lastTarget = 1; END_IF;
  vCauses := causes;
  vStroke := travel.StrokeDone;
  vConfirmed := travel.Confirmed;
  vMoving := travel.Moving OR co.InGap;
  vCfgFault := cfgF <> UT_F_NONE AND cfgF <> UT_F_MODE_SOURCE;
  vCfgWarn := cfgW <> UT_F_NONE OR (Data.set.valveType = UT_VT_SPRING AND Data.set.safePosition = UT_SAFE_OPEN)
              OR (Data.set.valveType = UT_VT_SPRING_NO AND Data.set.safePosition = UT_SAFE_CLOSED);
  IF vCfgFault THEN
    vCfgId := cfgF;
  ELSIF cfgW <> UT_F_NONE THEN
    vCfgId := cfgW;
  ELSE
    vCfgId := UT_F_SAFE_VS_SPRING;
  END_IF;
  x := UT_PROT_EXT_CLEAR(Sum := vTrip);
ELSE
  (* a variant: the common settings faults join its own (its hooks are set again every scan) *)
  IF cfgF <> UT_F_NONE AND cfgF <> UT_F_MODE_SOURCE AND NOT vCfgFault THEN
    vCfgFault := TRUE;
    vCfgId := cfgF;
  ELSIF cfgW <> UT_F_NONE AND NOT (vCfgFault OR vCfgHand OR vCfgAuto OR vCfgWarn) THEN
    vCfgWarn := TRUE;
    vCfgId := cfgW;
  END_IF;
END_IF;

core(Open := Open, OpenCmd := OpenCmd, CloseCmd := CloseCmd, Reset := Reset, Interlock := Interlock,
     Permissive := Permissive, Mode := Mode, ExpectAuto := ExpectAuto, Exercise := Exercise, SwHand := SwHand,
     SwAuto := SwAuto, LocalOpen := LocalOpen, LocalClose := LocalClose, LocalStop := LocalStop, LocalPos := -1,
     DriveFault := DriveFault, ActRemote := ActRemote, Causes := vCauses, Ext := vTrip, StrokeDone := vStroke,
     AtRest := vAtRest, Away := vAway, IsMoving := vMoving, HandOpen := vHandOpen, HandRest := vHandRest,
     SafePos := vSafePos, PosNow := vPosNow, HasTarget := FALSE, CfgFault := vCfgFault, CfgHand := vCfgHand,
     CfgAuto := vCfgAuto, CfgWarn := vCfgWarn, CfgId := vCfgId, VarStatus := vStatus, VarTime := vTime,
     Confirmed := vConfirmed, SpringOpen := springT = 2, Data := Data);
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

IF NOT vOwnTravel THEN
  (* where it should be *)
  CASE core.Aim OF
  UT_VA_OFF: target := springT;
  UT_VA_HOLD: target := 0;
  UT_VA_SAFE: target := safeT;
  UT_VA_REST: target := 1;
  UT_VA_RUN: target := 2;
  ELSE
    IF core.HandTarget >= 1.5 THEN
      target := 2;
    ELSIF core.HandTarget >= 0.5 THEN
      target := 1;
    ELSE
      target := 0;
    END_IF;
  END_CASE;
  IF isMotor AND core.DriveTrip THEN
    target := 0;                 (* the actuator has failed: stop where it is *)
  END_IF;
  permHeld := core.Aim = UT_VA_HOLD AND NOT Permissive;
  IF core.PowerUp THEN
    lastTarget := target;        (* nothing sent at power-up *)
    pulsedFor := target;
    IF latching AND NOT useO AND NOT useC AND Data.tot.lastPos >= 1 THEN
      assumeT := USINT_TO_INT(Data.tot.lastPos);   (* the latch is where it was left *)
    END_IF;
  END_IF;
  (* a latching pulse on a change of target, or a fresh command; never on a trip clearing *)
  IF latching AND target > 0 AND (target <> lastTarget OR core.FreshCmd) AND core.Aim <> UT_VA_OFF
     AND NOT core.PowerUp THEN
    pulseDir := target;
    pulseAt := tCur;
    pulsedFor := target;
    Data.tot.lastPos := INT_TO_USINT(target);
    saveNow := TRUE;
  END_IF;
  IF latching AND core.Forget AND target > 0 THEN
    IF NOT useO AND NOT useC THEN
      assumeT := target;         (* the user has put it right: no pulse *)
    END_IF;
    pulsedFor := target;
    Data.tot.lastPos := INT_TO_USINT(target);
    saveNow := TRUE;
  END_IF;
  IF target > 0 AND core.Aim <> UT_VA_OFF THEN
    coil := target;
  ELSIF core.Aim = UT_VA_OFF THEN
    coil := 0;
  END_IF;
  redrive := core.TripCleared AND NOT latching;
  lastTarget := target;

  (* the motor: reversal pause, drive until the end (or held) *)
  motorRun := isMotor AND target > 0 AND core.Aim <> UT_VA_OFF AND (travel.Pos <> target OR Data.set.driveHold);
  co(Run := motorRun, WantB := target = 2, FbA := FALSE, FbB := FALSE, UseFb := FALSE,
     GapAB := Data.set.reversalDelay, GapBA := Data.set.reversalDelay, OpenTime := T#1s, PowerUp := core.PowerUp);

  (* the move *)
  travelT := target;
  IF redrive THEN
    travelT := 0;                (* one scan: the move starts again *)
  END_IF;
  CASE Data.set.valveType OF
  UT_VT_MOTOR:
    go := (target = 2 AND co.QB) OR (target = 1 AND co.QA);
  UT_VT_DOUBLE_PULSE:
    go := pulsedFor = target AND target > 0;
  ELSE
    go := target > 0;            (* coil change, or the spring *)
  END_CASE;
  IF travelT = 2 THEN
    travel(Target := travelT, Go := go, AtSw := lsO, UseSw := useO, LeftSw := lsC, OtherSw := lsC,
           Travel := Data.set.openTime, Assume := assumeT, Forget := FALSE, PowerUp := core.PowerUp);
  ELSE
    travel(Target := travelT, Go := go, AtSw := lsC OR (isMotor AND Data.set.closeOnTorque AND TorqueClose AND travelT = 1),
           UseSw := useC OR (isMotor AND Data.set.closeOnTorque), LeftSw := lsO, OtherSw := lsO,
           Travel := Data.set.closeTime, Assume := assumeT, Forget := FALSE, PowerUp := core.PowerUp);
  END_IF;
  assumeT := -1;

  (* outputs *)
  OpenOut := FALSE;
  CloseOut := FALSE;
  IF core.Aim <> UT_VA_OFF THEN
    CASE Data.set.valveType OF
    UT_VT_DOUBLE_HELD:
      OpenOut := coil = 2;
      CloseOut := coil = 1;
    UT_VT_DOUBLE_PULSE:
      OpenOut := pulseDir = 2 AND tCur - pulseAt < Data.set.openPulse;
      CloseOut := pulseDir = 1 AND tCur - pulseAt < Data.set.closePulse;
    UT_VT_MOTOR:
      OpenOut := co.QB;
      CloseOut := co.QA;
    UT_VT_SPRING_NO:
      CloseOut := coil = 1;
    ELSE
      OpenOut := coil = 2;
    END_CASE;
  END_IF;
  IF isMotor AND NOT Data.set.driveHold AND travel.Pos = target THEN
    OpenOut := FALSE;            (* arrived this scan: the drive stops now *)
    CloseOut := FALSE;
  END_IF;
  Data.sts.confirmed := travel.Confirmed;
  IsOpen := travel.Pos = 2 AND NOT (lsO AND lsC);
  IsClosed := travel.Pos = 1 AND NOT (lsO AND lsC);
  Moving := travel.Moving OR co.InGap;
  IF IsOpen THEN
    Position := 100.0;
  ELSIF IsClosed THEN
    Position := 0.0;
  ELSE
    Position := -1.0;
  END_IF;
  IF travel.StrokeDone AND travel.Confirmed THEN
    IF travelT = 2 THEN Data.sts.lastOpenStroke := travel.StrokeTime; ELSE Data.sts.lastCloseStroke := travel.StrokeTime; END_IF;
  END_IF;
  Data.det.travelElapsed := travel.Elapsed;
  (* where it is, for the status *)
  vTime := T#0s;
  IF co.InGap THEN
    vStatus := UT_ST_DEAD_TIME;
    vTime := co.TimeLeft;
  ELSIF travel.Moving AND travelT = 2 THEN
    vStatus := UT_ST_OPENING;
    vTime := travel.TimeLeft;
  ELSIF travel.Moving THEN
    vStatus := UT_ST_CLOSING;
    vTime := travel.TimeLeft;
  ELSIF permHeld THEN
    vStatus := UT_ST_NOT_PERMITTED;
  ELSIF IsOpen THEN
    vStatus := UT_ST_OPEN;
  ELSIF IsClosed THEN
    vStatus := UT_ST_CLOSED;
  ELSIF target = 0 AND travel.Pos < 0 AND NOT core.PowerUp AND lastTarget = 0 THEN
    vStatus := UT_ST_BETWEEN;
  ELSE
    vStatus := UT_ST_POS_UNKNOWN;
  END_IF;
  vIsOpen := IsOpen;
  vIsClosed := IsClosed;
  vPos := Position;
ELSE
  (* the variant's position *)
  IsOpen := vIsOpen;
  IsClosed := vIsClosed;
  Moving := vMoving;
  Position := vPos;
END_IF;

Fault := core.Fault;
Warning := core.Warning;
Ready := core.Ready;
Auto := core.Auto;
Hand := core.Hand;
Linked := core.Linked;
IF core.CurMode = UT_MODE_OOS THEN
  State := UT_STATE_OOS;
ELSIF Fault THEN
  State := UT_STATE_FAULT;
ELSIF NOT Interlock THEN
  State := UT_STATE_INTERLOCKED;
ELSIF Moving AND (IsOpen OR vStatus = UT_ST_OPENING) THEN
  State := UT_STATE_STARTING;
ELSIF Moving THEN
  State := UT_STATE_STOPPING;
ELSIF Warning THEN
  State := UT_STATE_WARNING;
ELSIF IsClosed THEN
  State := UT_STATE_OFF;
ELSIF IsOpen THEN
  State := UT_STATE_ON;
ELSE
  State := UT_STATE_INVALID;
END_IF;
Data.sts.state := State;
Data.sts.isOpen := IsOpen;
Data.sts.isClosed := IsClosed;
Data.sts.moving := Moving;
Data.sts.position := Position;
mPos := Position;
mTimeLeft := core.TimeLeft;
mConfirmed := vConfirmed;
mIsOpen := IsOpen;
mIsClosed := IsClosed;

END_FUNCTION_BLOCK