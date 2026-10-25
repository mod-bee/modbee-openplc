(* UT_VALVE_3POS — three-position valve: a 3-way diverter (A / closed / B), a
spring-centred double solenoid, a three-coil valve, or a motorised valve with
a mid position (mid switch, or timed from an end). Offers the UT_I_VALVE
plug (ReqOpen with ReqPos 1..3; no number: position 3). Positions 1, 2, 3.

Auto: Pos1 / Pos2 / Pos3 held (TRUE = there, none = restPos) or pulse
(Valve3.set.posPulse: a rising edge goes there and stays); AutoPos 1..3 when no Pos
pin asks. Linked: the owner's position, its open off = restPos. Hand:
Local1..3 / cmdPos, LocalStop / cmdStop (motor: stop where it is), bumpless
on entry. Off / Interlock FALSE / a trip: safePosition; OOS / a config
fault: every output off (a spring-centred valve centres). Permissive FALSE:
no move away from the safe position starts.

Solenoid kinds hold their coil (SPRING_CENTRE: Out1 / Out3, none for 2;
THREE_COIL: Out1..3). MOTOR: Out1 drives toward 1, Out3 toward 3, a
reversal pause between; mid by Ls2, or timed (midTime, 0 = half
travelTime) from a known end (an unknown position goes to 1 first). Arrival
by the position's switch when fitted (useLs1..3), else after travelTime;
the travel faults are the core's. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_VALVE_3POS IMPLEMENTS UT_I_VALVE
  VAR_INPUT
    Pos1 : BOOL; (* Auto: go to 1 (held or pulse per Valve3.set.posPulse) *)
    Pos2 : BOOL;
    Pos3 : BOOL;
    AutoPos : INT := -1; (* Auto position 1..3 when no Pos pin asks; -1 / 0 = none *)
    Reset : BOOL R_EDGE;
    Interlock : BOOL := TRUE; (* FALSE: safePosition in every mode *)
    Permissive : BOOL := TRUE; (* FALSE: no move away from safe starts *)
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto, 3 OOS *)
    ExpectAuto : BOOL;
    Exercise : BOOL R_EDGE;
    Ls1 : BOOL; (* position switches (useLs1..3) *)
    Ls2 : BOOL;
    Ls3 : BOOL;
    DriveFault : BOOL;
    SwHand : BOOL;
    SwAuto : BOOL;
    Local1 : BOOL R_EDGE; (* Hand: go to n *)
    Local2 : BOOL R_EDGE;
    Local3 : BOOL R_EDGE;
    LocalStop : BOOL R_EDGE; (* Hand, motorised: stop where it is *)
  END_VAR
  VAR_OUTPUT
    IsOpen : BOOL; (* at the asked position, when that is not restPos *)
    IsClosed : BOOL; (* at restPos *)
    Out1 : BOOL;
    Out2 : BOOL;
    Out3 : BOOL;
    Moving : BOOL;
    Position : INT; (* 1..3 reached, -1 moving / unknown *)
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
    Valve3 : UT_VALVE3_DATA; (* (the catalogue's Pos3: the name is the Pos3 pin's) *)
  END_VAR
  VAR RETAIN
    keptSet : UT_VALVE_SET;
    keptGood : BOOL;
    keptSet3 : UT_VALVE3_SET;
    keptGood3 : BOOL;
    keptTot : UT_VALVE_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    core : UT_VALVE_CORE;
    travel : UT_TRAVEL_RUN;
    co : UT_CHANGEOVER_RUN;
    sum : UT_PROT_EXT_SUM;
    causes : UT_VALVE_CAUSES;
    ok : BOOL;
    ok3 : BOOL;
    cfgF : UT_FAULT;
    cfgW : UT_FAULT;
    id3 : UT_FAULT;
    tCur : TIME;
    x : BOOL;
    isMotor : BOOL;
    u1 : BOOL;
    u2 : BOOL;
    u3 : BOOL;
    l1 : BOOL;
    l2 : BOOL;
    l3 : BOOL;
    autoP : INT; (* the Auto position asked (0 none) *)
    pulseP : INT;
    h1 : BOOL;
    h2 : BOOL;
    h3 : BOOL;
    localP : INT;
    target : INT; (* 1..3, 0 hold / stop *)
    held : INT; (* solenoid: the coil held *)
    legAim : INT; (* motor: where this leg goes *)
    legUp : BOOL;
    legTimed : BOOL;
    driving : BOOL;
    pos : INT; (* known position (-1 unknown) *)
    lastEnd : INT; (* the last end / mid reached *)
    midT : TIME;
    atSw : BOOL;
    useSw : BOOL;
    otherSw : BOOL;
    leftSw : BOOL;
    travelT : TIME;
    vStatus : UT_STATUS := UT_ST_IDLE;
    vTime : TIME;
    mPos : REAL;
    mConfirmed : BOOL;
    mIsOpen : BOOL;
    mIsClosed : BOOL;
    mTimeLeft : TIME;
    mMoving : BOOL;
    Out1Prev : BOOL;
    Out3Prev : BOOL;
    tripped : BOOL;
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
  AtPosition := N >= 1 AND N <= 3 AND mPos = INT_TO_REAL(N);
END_METHOD
METHOD PUBLIC IsMoving : BOOL
  IsMoving := mMoving;
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
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
  Valve3.set := keptSet3;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := UT_VALVE_CHECK(TwoPos := FALSE, S := Data.set, Fault => cfgF, Warn => cfgW);
ok3 := UT_VALVE3_CHECK(S := Valve3.set, Id => id3);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN Data.sts.refused := cfgF; ELSE Data.sts.refused := cfgW; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_VALVE_CHECK(TwoPos := FALSE, S := Data.set, Fault => cfgF, Warn => cfgW);
END_IF;
IF NOT ok3 AND keptGood3 AND NOT keep.FirstBoot THEN
  Valve3.sts.refused := id3;
  Valve3.set := keptSet3;
  ok3 := UT_VALVE3_CHECK(S := Valve3.set, Id => id3);
END_IF;
IF keep.SaveSet THEN
  IF ok OR NOT keptGood THEN
    keptSet := Data.set;
    keptGood := ok;
  END_IF;
  IF ok3 OR NOT keptGood3 THEN
    keptSet3 := Valve3.set;
    keptGood3 := ok3;
  END_IF;
END_IF;
isMotor := Valve3.set.type3 = UT_V3_MOTOR;
u1 := Valve3.set.useLs1 AND NOT Data.simulate;
u2 := Valve3.set.useLs2 AND NOT Data.simulate;
u3 := Valve3.set.useLs3 AND NOT Data.simulate;
l1 := u1 AND Ls1;
l2 := u2 AND Ls2;
l3 := u3 AND Ls3;
midT := Valve3.set.midTime;
IF midT <= T#0s THEN
  midT := Valve3.set.travelTime / 2;
END_IF;

(* the Auto position *)
IF Valve3.set.posPulse THEN
  IF Pos1 AND NOT h1 THEN pulseP := 1;
  ELSIF Pos2 AND NOT h2 THEN pulseP := 2;
  ELSIF Pos3 AND NOT h3 THEN pulseP := 3;
  END_IF;
  autoP := pulseP;
ELSIF Pos1 THEN autoP := 1;
ELSIF Pos2 THEN autoP := 2;
ELSIF Pos3 THEN autoP := 3;
ELSE
  autoP := 0;
END_IF;
h1 := Pos1;
h2 := Pos2;
h3 := Pos3;
IF autoP = 0 AND AutoPos >= 1 AND AutoPos <= 3 THEN
  autoP := AutoPos;
END_IF;
(* Hand positions this scan *)
localP := -1;
IF Local1 THEN localP := 1;
ELSIF Local2 THEN localP := 2;
ELSIF Local3 THEN localP := 3;
ELSIF Valve3.cmdPos >= 1 AND Valve3.cmdPos <= 3 THEN localP := Valve3.cmdPos;
END_IF;
Valve3.cmdPos := -1;

(* the travel causes (from last scan's move) *)
causes.openTimeout := travel.Timeout AND legAim <> Valve3.set.restPos;
causes.closeTimeout := travel.Timeout AND legAim = Valve3.set.restPos;
causes.bothLimits := travel.BothSw OR (l1 AND l3);
causes.positionLost := travel.Lost;
causes.noMovement := travel.NoMove;
x := UT_PROT_EXT_CLEAR(Sum := sum);
pos := travel.Pos;

core(Open := autoP > 0, OpenCmd := FALSE, CloseCmd := FALSE, Reset := Reset, Interlock := Interlock,
     Permissive := Permissive, Mode := Mode, ExpectAuto := ExpectAuto, Exercise := Exercise, SwHand := SwHand,
     SwAuto := SwAuto, LocalOpen := FALSE, LocalClose := FALSE, LocalStop := LocalStop AND isMotor, LocalPos := localP,
     DriveFault := DriveFault, ActRemote := TRUE, Causes := causes, Ext := sum, StrokeDone := travel.StrokeDone,
     AtRest := pos = Valve3.set.restPos, Away := target > 0 AND target <> Valve3.set.safePosition, IsMoving := mMoving,
     HandOpen := 3.0, HandRest := INT_TO_REAL(Valve3.set.restPos), SafePos := INT_TO_REAL(Valve3.set.safePosition),
     PosNow := INT_TO_REAL(pos), HasTarget := FALSE, CfgFault := (cfgF <> UT_F_NONE AND cfgF <> UT_F_MODE_SOURCE) OR NOT ok3,
     CfgHand := FALSE, CfgAuto := FALSE, CfgWarn := cfgW <> UT_F_NONE, CfgId := SEL(NOT ok3, SEL(cfgF <> UT_F_NONE, cfgW, cfgF), id3),
     VarStatus := vStatus, VarTime := vTime, Confirmed := travel.Confirmed, SpringOpen := FALSE, Data := Data);
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

(* where it should be *)
CASE core.Aim OF
UT_VA_SAFE: target := Valve3.set.safePosition;
UT_VA_REST: target := Valve3.set.restPos;
UT_VA_RUN:
  IF core.Exercising THEN
    IF Valve3.set.restPos = 3 THEN target := 1; ELSE target := 3; END_IF;
  ELSIF core.Linked THEN
    IF core.RunPos >= 0.5 AND core.RunPos <= 3.5 THEN target := REAL_TO_INT(core.RunPos); ELSE target := 3; END_IF;
  ELSIF autoP > 0 THEN
    target := autoP;
  ELSE
    target := Valve3.set.restPos;
  END_IF;
UT_VA_HAND:
  IF core.HandTarget >= 0.5 AND core.HandTarget <= 3.5 THEN target := REAL_TO_INT(core.HandTarget); ELSE target := 0; END_IF;
ELSE
  target := 0;                   (* OFF / HOLD *)
END_CASE;
IF core.DriveTrip AND isMotor THEN
  target := 0;                   (* the actuator failed: stop driving it *)
END_IF;
tripped := core.Aim = UT_VA_OFF;

(* the move *)
Out1 := FALSE;
Out2 := FALSE;
Out3 := FALSE;
IF NOT isMotor THEN
  IF tripped THEN
    held := 0;
  ELSIF target > 0 THEN
    held := target;
  END_IF;
  legAim := held;
  IF held = 0 AND Valve3.set.type3 = UT_V3_SPRING_CENTRE THEN
    legAim := 2;                 (* no coil: the spring centres it *)
  END_IF;
  driving := legAim > 0;
  IF Valve3.set.type3 = UT_V3_THREE_COIL THEN
    Out1 := held = 1;
    Out2 := held = 2;
    Out3 := held = 3;
  ELSE
    Out1 := held = 1;
    Out3 := held = 3;
  END_IF;
  travelT := Valve3.set.travelTime;
  legTimed := FALSE;
ELSE
  (* motor: one leg at a time toward the target (an unknown position finds 1 first) *)
  IF target = 0 THEN
    legAim := 0;
  ELSIF pos = target THEN
    legAim := target;
    lastEnd := target;
  ELSIF target = 2 AND NOT u2 THEN
    IF lastEnd = 1 OR lastEnd = 3 THEN
      legAim := 2;               (* mid by timing from a known end *)
    ELSE
      legAim := 1;
    END_IF;
  ELSE
    legAim := target;
  END_IF;
  IF pos >= 1 THEN
    lastEnd := pos;
  END_IF;
  legTimed := legAim = 2 AND NOT u2;
  IF legAim = 3 THEN
    legUp := TRUE;
  ELSIF legAim = 1 THEN
    legUp := FALSE;
  ELSIF legAim = 2 THEN
    legUp := lastEnd = 1;
  END_IF;
  IF legTimed THEN travelT := midT; ELSE travelT := Valve3.set.travelTime; END_IF;
  CASE legAim OF
  1: atSw := l1; useSw := u1; otherSw := l2 OR l3;
  2: atSw := l2; useSw := u2 AND NOT legTimed; otherSw := l1 OR l3;
  3: atSw := l3; useSw := u3; otherSw := l1 OR l2;
  ELSE
    atSw := FALSE; useSw := FALSE; otherSw := FALSE;
  END_CASE;
  leftSw := (lastEnd = 1 AND l1 AND legAim <> 1) OR (lastEnd = 3 AND l3 AND legAim <> 3);
  (* the leg on last scan's drive; the drive then stops in the arrival scan *)
  travel(Target := legAim, Go := Out1Prev OR Out3Prev, AtSw := atSw, UseSw := useSw, LeftSw := leftSw, OtherSw := otherSw,
         Travel := travelT, Assume := -1, Forget := tripped, PowerUp := core.PowerUp);
  pos := travel.Pos;
  IF pos >= 1 THEN
    lastEnd := pos;
  END_IF;
  driving := legAim > 0 AND pos <> legAim AND NOT tripped;
  co(Run := driving, WantB := legUp, FbA := FALSE, FbB := FALSE, UseFb := FALSE, GapAB := Data.set.reversalDelay,
     GapBA := Data.set.reversalDelay, PowerUp := core.PowerUp);
  Out1 := co.QA;
  Out3 := co.QB;
END_IF;
Out1Prev := Out1;
Out3Prev := Out3;
IF NOT isMotor THEN
  CASE legAim OF
  1: atSw := l1; useSw := u1; otherSw := l2 OR l3;
  2: atSw := l2; useSw := u2; otherSw := l1 OR l3;
  3: atSw := l3; useSw := u3; otherSw := l1 OR l2;
  ELSE
    atSw := FALSE; useSw := FALSE; otherSw := FALSE;
  END_CASE;
  leftSw := (lastEnd = 1 AND l1 AND legAim <> 1) OR (lastEnd = 3 AND l3 AND legAim <> 3);
  travel(Target := legAim, Go := driving, AtSw := atSw, UseSw := useSw, LeftSw := leftSw, OtherSw := otherSw,
         Travel := travelT, Assume := -1, Forget := tripped AND Valve3.set.type3 = UT_V3_THREE_COIL, PowerUp := core.PowerUp);
  pos := travel.Pos;
END_IF;

(* outputs *)
Position := pos;
Moving := travel.Moving OR (isMotor AND co.InGap) OR (isMotor AND driving);
IsClosed := pos = Valve3.set.restPos;
IsOpen := pos >= 1 AND pos = target AND target <> Valve3.set.restPos;
Fault := core.Fault;
Warning := core.Warning;
Ready := core.Ready;
Auto := core.Auto;
Hand := core.Hand;
Linked := core.Linked;
vTime := T#0s;
IF isMotor AND co.InGap THEN
  vStatus := UT_ST_DEAD_TIME;
  vTime := co.TimeLeft;
ELSIF Moving AND target = Valve3.set.restPos THEN
  vStatus := UT_ST_CLOSING;
  vTime := travel.TimeLeft;
ELSIF Moving THEN
  vStatus := UT_ST_OPENING;
  vTime := travel.TimeLeft;
ELSIF IsClosed THEN
  vStatus := UT_ST_CLOSED;
ELSIF pos >= 1 THEN
  vStatus := UT_ST_AT_POSITION;
ELSE
  vStatus := UT_ST_POS_UNKNOWN;
END_IF;
IF core.CurMode = UT_MODE_OOS THEN
  State := UT_STATE_OOS;
ELSIF Fault THEN
  State := UT_STATE_FAULT;
ELSIF NOT Interlock THEN
  State := UT_STATE_INTERLOCKED;
ELSIF Moving AND target <> Valve3.set.safePosition THEN
  State := UT_STATE_STARTING;
ELSIF Moving THEN
  State := UT_STATE_STOPPING;
ELSIF Warning THEN
  State := UT_STATE_WARNING;
ELSIF pos = Valve3.set.safePosition THEN
  State := UT_STATE_OFF;
ELSIF pos >= 1 THEN
  State := UT_STATE_ON;
ELSE
  State := UT_STATE_INVALID;
END_IF;
Data.sts.state := State;
Data.sts.isOpen := IsOpen;
Data.sts.isClosed := IsClosed;
Data.sts.moving := Moving;
Data.sts.position := INT_TO_REAL(pos);
Valve3.sts.targetPos := target;
Valve3.sts.actualPos := pos;
IF travel.StrokeDone THEN
  Valve3.sts.lastStroke := travel.StrokeTime;
END_IF;
mPos := INT_TO_REAL(pos);
mConfirmed := travel.Confirmed;
mIsOpen := IsOpen;
mIsClosed := IsClosed;
mTimeLeft := core.TimeLeft;
mMoving := Moving;

END_FUNCTION_BLOCK