(* UT_VALVE_CORE — what every valve shares (private; held as `core` by
UT_VALVE and UT_VALVE_3POS, and through UT_VALVE by FLOAT / MOD): the mode,
the Auto request (the Open pin per set.input, OpenCmd / CloseCmd edges,
the owner's link), Hand targets, the safe position decision, protections,
reset, exercise, the stroke count and the status. It speaks one language to
every variant: Aim (UT_VALVE_AIM) = OFF (every output off), HOLD (stay /
stop where it is), SAFE, REST, RUN (the run position; RunPos = the owner's
ReqPos when a number), HAND (go to HandTarget, -1 = stop where it is).

The variant tells the core where the valve is (AtRest, Away, IsMoving,
PosNow, Confirmed), its travel causes (Causes), its own protections (Ext),
its Hand targets (HandOpen / HandRest / SafePos) and its settings faults
(CfgFault / CfgHand / CfgAuto / CfgWarn / CfgId). The record's settings
are kept and checked by the variant (decision 28 / 62). *)

FUNCTION_BLOCK UT_VALVE_CORE
  VAR_INPUT
    Open : BOOL; (* the Auto request pin (per set.input) *)
    OpenCmd : BOOL; (* plain BOOL: the edge is taken here *)
    CloseCmd : BOOL;
    Reset : BOOL; (* one scan *)
    Interlock : BOOL := TRUE;
    Permissive : BOOL := TRUE;
    Mode : INT := -1;
    ExpectAuto : BOOL;
    Exercise : BOOL; (* one scan *)
    SwHand : BOOL;
    SwAuto : BOOL;
    LocalOpen : BOOL; (* one scan each *)
    LocalClose : BOOL;
    LocalStop : BOOL;
    LocalPos : INT := -1; (* 3POS: a Hand position this scan *)
    DriveFault : BOOL;
    ActRemote : BOOL := TRUE;
    Causes : UT_VALVE_CAUSES;
    Ext : UT_PROT_EXT_SUM;
    StrokeDone : BOOL;
    AtRest : BOOL; (* at the rest position (last scan) *)
    Away : BOOL; (* asked away from the safe position (last scan) *)
    IsMoving : BOOL;
    HandOpen : REAL; (* Hand target of an open command (variant units) *)
    HandRest : REAL; (* Hand target of a close command *)
    SafePos : REAL; (* the safe position in the same units (-1 = stay) *)
    PosNow : REAL; (* the position / target now (bumpless Hand) *)
    HasTarget : BOOL; (* PULSE_TIMER has the block's own target (no) *)
    CfgFault : BOOL;
    CfgHand : BOOL;
    CfgAuto : BOOL;
    CfgWarn : BOOL;
    CfgId : UT_FAULT;
    VarStatus : UT_STATUS := UT_ST_IDLE;
    VarTime : TIME;
    Confirmed : BOOL;
    SpringOpen : BOOL; (* outputs off leave the valve open (SPRING_NO) *)
  END_VAR
  VAR_OUTPUT
    Aim : UT_VALVE_AIM;
    HandTarget : REAL; (* -1 = stop where it is *)
    RunPos : REAL; (* the owner's ReqPos (NaN = none) *)
    Fault : BOOL;
    Warning : BOOL;
    Ready : BOOL;
    Auto : BOOL;
    Hand : BOOL;
    Linked : BOOL;
    DriveTrip : BOOL; (* drive / torque tripped (motorised: stop where it is) *)
    TripCleared : BOOL; (* one scan: a trip cleared (re-drive, not latching) *)
    Forget : BOOL; (* one scan: a reset (latching: the requested position is the true one) *)
    FreshCmd : BOOL; (* one scan: an operator / owner command (latching: re-send the pulse) *)
    Exercising : BOOL;
    CurMode : UT_MODE;
    TimeLeft : TIME;
    StopReason : UT_STOP;
    PowerUp : BOOL;
    ResetReq : BOOL;
    CurStatus : UT_STATUS; (* for the plug's methods (they may not read Data) *)
    CurFault : UT_FAULT;
    CurLocked : BOOL;
    CurNe : UT_NE107;
  END_VAR
  VAR_IN_OUT
    Data : UT_VALVE_DATA;
  END_VAR
  VAR NON_RETAIN
    started : BOOL;
  END_VAR
  VAR
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    sOpenT : UT_PROT_ST;
    sCloseT : UT_PROT_ST;
    sBoth : UT_PROT_ST;
    sLost : UT_PROT_ST;
    sNoMove : UT_PROT_ST;
    sDrive : UT_PROT_ST;
    sTorque : UT_PROT_ST;
    sLocal : UT_PROT_ST;
    sSlow : UT_PROT_ST;
    tCur : TIME;
    x : BOOL;
    supervise : BOOL;
    oos : BOOL;
    isHand : BOOL;
    isAuto : BOOL;
    tripped : BOOL;
    trippedPrev : BOOL;
    resetDone : BOOL;
    mustCycle : BOOL;
    cfgOn : BOOL;
    cfgWhich : UT_FAULT;
    cfgWarnId : UT_FAULT;
    hOpenCmd : BOOL;
    hCloseCmd : BOOL;
    hCmdOpen : BOOL;
    hCmdClose : BOOL;
    hCmdStop : BOOL;
    hCmdEx : BOOL;
    hCmdReset : BOOL;
    hPreset : BOOL;
    reqOpen : BOOL;
    reqClose : BOOL;
    reqStop : BOOL;
    autoRun : BOOL;
    stopHold : BOOL;
    held : BOOL;
    ignored : BOOL;
    exPhase : INT; (* 0 none, 1 going, 2 holding, 3 returning *)
    exAt : TIME;
    restSince : TIME;
    safeWhy : UT_STOP;
    safeWhyPrev : UT_STOP;
    awayPrev : BOOL;
    handPrev : BOOL;
    tripCode : DWORD;
    tripPrev : DWORD;
    newBits : DWORD;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    stTime : TIME;
    have : BOOL;
    vHeld : BOOL;
    vNormal : BOOL;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    nan : REAL;
    linkCalls : INT;
    linkLapse : INT := 2;
    linkOpen : BOOL;
    linkOpenPrev : BOOL;
    linkPos : REAL;
    linkOwner : STRING(12);
    twoOwners : BOOL;
  END_VAR


(* the body of every valve's Request *)
METHOD PUBLIC Link : BOOL
  VAR_INPUT
    ReqOpen : BOOL;
    ReqPos : REAL;
    Owner : STRING(12);
  END_VAR
  linkCalls := linkCalls + 1;
  linkOpen := ReqOpen;
  linkPos := ReqPos;
  linkOwner := Owner;
  Link := NOT Fault AND linkCalls <= 1;
END_METHOD

tCur := TIME();
PowerUp := NOT started;
IF PowerUp THEN
  nan := zero / zero;
  restSince := tCur;
  hOpenCmd := OpenCmd;           (* a command held at power-up is not one *)
  hCloseCmd := CloseCmd;
  hCmdOpen := Data.cmdOpen;
  hCmdClose := Data.cmdClose;
  Data.simulate := FALSE;
END_IF;
started := TRUE;

(* the link *)
twoOwners := linkCalls > 1;
IF linkCalls > 0 THEN
  linkLapse := 0;
ELSIF linkLapse < 2 THEN
  linkLapse := linkLapse + 1;
END_IF;
linkCalls := 0;
Linked := linkLapse < 2;
IF NOT Linked THEN
  linkOpen := FALSE;
  linkPos := nan;
END_IF;
IF linkPos = linkPos THEN
  RunPos := linkPos;
ELSE
  RunPos := nan;
END_IF;

(* the mode *)
modeSel(SwAuto := SwAuto, SwHand := SwHand, ForceOff := FALSE, HandOn := FALSE, HandToOff := FALSE,
        AllowOOS := TRUE, Source := Data.set.modeSource, ModeReq := Mode, PowerUp := Data.set.powerUp,
        HandPowerUp := UT_HPU_KEEP, HandMax := T#0s, CmdMode := Data.cmdMode, Choice := Data.set.mode);
CurMode := modeSel.Mode;
isHand := CurMode = UT_MODE_HAND;
isAuto := CurMode = UT_MODE_AUTO;
oos := CurMode = UT_MODE_OOS;
ResetReq := Reset OR (Data.cmdReset AND NOT hCmdReset) OR (Data.set.resetByOff AND modeSel.EnteredOff);
hCmdReset := Data.cmdReset;
Data.cmdReset := FALSE;
Forget := Reset OR (Data.cmdReset AND NOT hCmdReset);

(* commands: each acts once (held or rewritten: once); a stop wins *)
reqStop := LocalStop OR (Data.cmdStop AND NOT hCmdStop);
reqOpen := (LocalOpen OR (Data.cmdOpen AND NOT hCmdOpen) OR (OpenCmd AND NOT hOpenCmd)) AND NOT reqStop;
reqClose := (LocalClose OR (Data.cmdClose AND NOT hCmdClose) OR (CloseCmd AND NOT hCloseCmd)) AND NOT reqStop;
IF reqClose THEN
  reqOpen := FALSE;              (* close wins *)
END_IF;
hCmdStop := Data.cmdStop;
hCmdOpen := Data.cmdOpen;
hCmdClose := Data.cmdClose;
hOpenCmd := OpenCmd;
hCloseCmd := CloseCmd;
Data.cmdStop := FALSE;
Data.cmdOpen := FALSE;
Data.cmdClose := FALSE;
FreshCmd := reqOpen OR reqClose OR LocalPos > 0 OR (Linked AND linkOpen <> linkOpenPrev);
linkOpenPrev := linkOpen;
IF Data.cmdPreset AND NOT hPreset THEN
  Data.tot.strokes := Data.presetStrokes;
END_IF;
hPreset := Data.cmdPreset;
Data.cmdPreset := FALSE;

(* protections: none out of service or simulated *)
supervise := NOT oos AND NOT Data.simulate;
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.openTimeout, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.openTimeout, Sts := Data.sts.openTimeout, St := sOpenT);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.closeTimeout, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.closeTimeout, Sts := Data.sts.closeTimeout, St := sCloseT);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.bothLimits, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.bothLimits, Sts := Data.sts.bothLimits, St := sBoth);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.positionLost, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.positionLost, Sts := Data.sts.positionLost, St := sLost);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.noMovement, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.noMovement, Sts := Data.sts.noMovement, St := sNoMove);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND DriveFault, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.drive, Sts := Data.sts.drive, St := sDrive);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.torque, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.torque, Sts := Data.sts.torque, St := sTorque);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND NOT ActRemote, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.actLocal, Sts := Data.sts.actLocal, St := sLocal);
x := UT_PROT_RUN(TNow := tCur, Cause := supervise AND Causes.slowStroke, ResetReq := ResetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.slowStroke, Sts := Data.sts.slowStroke, St := sSlow);
tripped := sOpenT.trip OR sCloseT.trip OR sBoth.trip OR sLost.trip OR sNoMove.trip OR sDrive.trip OR sTorque.trip
           OR sLocal.trip OR sSlow.trip OR Ext.trip <> 0;
resetDone := sOpenT.reset OR sCloseT.reset OR sBoth.reset OR sLost.reset OR sNoMove.reset OR sDrive.reset
             OR sTorque.reset OR sLocal.reset OR sSlow.reset OR Ext.resetDone;
DriveTrip := sDrive.trip OR sTorque.trip;
TripCleared := trippedPrev AND NOT tripped;
trippedPrev := tripped;

(* settings: the core's own, and the variant's *)
cfgWarnId := UT_F_NONE;
IF Data.set.retryWindow < T#0s THEN cfgWarnId := UT_F_RETRY_WINDOW;
ELSIF NOT (Data.set.powerUp = UT_PU_LAST OR Data.set.powerUp = UT_PU_OFF) THEN cfgWarnId := UT_F_POWERUP;
ELSIF modeSel.BadSetting THEN cfgWarnId := UT_F_MODE_CHOICE;
ELSIF Data.set.exerciseEvery < T#0s OR Data.set.exerciseTime < T#0s THEN cfgWarnId := UT_F_EXERCISE;
ELSIF Data.set.strokeWarn < T#0s THEN cfgWarnId := UT_F_STROKE_WARN;
ELSIF sOpenT.badSetting OR sCloseT.badSetting THEN cfgWarnId := UT_F_TRAVEL_TIME;
ELSIF sBoth.badSetting THEN cfgWarnId := UT_F_BOTH_LIMITS;
ELSIF sLost.badSetting THEN cfgWarnId := UT_F_POS_LOST;
ELSIF sNoMove.badSetting THEN cfgWarnId := UT_F_NO_MOVEMENT;
ELSIF sDrive.badSetting THEN cfgWarnId := UT_F_ACTUATOR;
ELSIF sTorque.badSetting THEN cfgWarnId := UT_F_TORQUE;
ELSIF sLocal.badSetting THEN cfgWarnId := UT_F_ACT_LOCAL;
ELSIF sSlow.badSetting THEN cfgWarnId := UT_F_SLOW_STROKE;
ELSIF Ext.cfgId <> UT_F_NONE THEN cfgWarnId := Ext.cfgId;
ELSIF CfgWarn THEN cfgWarnId := CfgId;
END_IF;
cfgOn := CfgFault OR twoOwners
       OR NOT (Data.set.modeSource = UT_SRC_HMI OR Data.set.modeSource = UT_SRC_SWITCH OR Data.set.modeSource = UT_SRC_REMOTE)
       OR (isHand AND CfgHand) OR (isAuto AND (CfgAuto OR (NOT Linked AND runIn.BadSetting)));
IF twoOwners THEN
  cfgWhich := UT_F_TWO_OWNERS;
ELSIF NOT (Data.set.modeSource = UT_SRC_HMI OR Data.set.modeSource = UT_SRC_SWITCH OR Data.set.modeSource = UT_SRC_REMOTE) THEN
  cfgWhich := UT_F_MODE_SOURCE;
ELSIF CfgFault OR CfgHand OR CfgAuto THEN
  cfgWhich := CfgId;
ELSE
  cfgWhich := UT_F_RUN_STYLE;
END_IF;
Fault := ((tripped AND NOT oos) OR cfgOn);
Warning := NOT oos AND (sOpenT.warn OR sCloseT.warn OR sBoth.warn OR sLost.warn OR sNoMove.warn OR sDrive.warn
           OR sTorque.warn OR sLocal.warn OR sSlow.warn OR Ext.warn <> 0 OR cfgWarnId <> UT_F_NONE
           OR (ExpectAuto AND NOT isAuto) OR ignored OR modeSel.SwFault OR Data.simulate);

(* after a reset that needed one, the request cycles (unless restartAfterReset) *)
IF resetDone AND NOT Data.set.restartAfterReset THEN
  mustCycle := TRUE;
END_IF;

(* the Auto request *)
runIn(Run := Open, Start := reqOpen AND isAuto, Stop := reqClose AND isAuto, CmdStart := FALSE, CmdStop := FALSE,
      Drop := NOT isAuto OR NOT Interlock OR tripped, Linked := Linked, TargetDone := FALSE, HasTarget := HasTarget,
      Set := Data.set.input);
ignored := FALSE;
held := FALSE;
IF isAuto AND Linked THEN
  ignored := Open OR reqOpen;
  IF reqClose THEN
    stopHold := TRUE;
  END_IF;
  IF NOT linkOpen THEN
    stopHold := FALSE;
    mustCycle := FALSE;
  END_IF;
  held := stopHold AND linkOpen;
  autoRun := linkOpen AND NOT stopHold;
ELSIF isAuto THEN
  stopHold := FALSE;
  autoRun := runIn.Request AND NOT runIn.BadSetting;
  IF NOT autoRun THEN
    mustCycle := FALSE;
  END_IF;
ELSE
  stopHold := FALSE;
  autoRun := FALSE;
END_IF;
IF isHand THEN
  mustCycle := FALSE;            (* the operator commands it again (the Hand target goes safe below) *)
ELSIF NOT isAuto THEN
  mustCycle := FALSE;
END_IF;

(* exercise: one cycle when resting in Auto; any request ends it *)
IF NOT (isAuto AND AtRest AND NOT autoRun AND NOT IsMoving) OR exPhase > 0 THEN
  restSince := tCur;
END_IF;
IF Data.set.exerciseEnable AND exPhase = 0 AND isAuto AND NOT autoRun AND AtRest AND Interlock AND Permissive
   AND NOT tripped AND NOT cfgOn
   AND (Exercise OR (Data.cmdExercise AND NOT hCmdEx)
        OR (Data.set.exerciseEvery > T#0s AND tCur - restSince >= Data.set.exerciseEvery)) THEN
  exPhase := 1;
  exAt := tCur;
END_IF;
hCmdEx := Data.cmdExercise;
Data.cmdExercise := FALSE;
IF exPhase > 0 AND (autoRun OR NOT isAuto OR NOT Interlock OR tripped OR cfgOn) THEN
  exPhase := 0;                  (* a request wins *)
END_IF;
CASE exPhase OF
1: IF NOT IsMoving AND NOT AtRest AND tCur - exAt > T#0s THEN exPhase := 2; exAt := tCur; END_IF;
2: IF tCur - exAt >= Data.set.exerciseTime THEN exPhase := 3; END_IF;
3: IF AtRest AND NOT IsMoving THEN
     exPhase := 0;
     Data.sts.stopReason := UT_STOP_EXERCISE_DONE;
   END_IF;
END_CASE;
Exercising := exPhase > 0;

(* the Hand target: bumpless on entry; interlock / trip / reset -> safe *)
IF modeSel.Changed AND isHand THEN
  HandTarget := PosNow;
END_IF;
IF isHand THEN
  IF NOT Interlock OR tripped OR resetDone THEN
    HandTarget := SafePos;       (* no surprise move when it clears *)
  ELSIF reqStop THEN
    HandTarget := -1.0;
  ELSIF reqClose THEN
    IF Permissive OR HandRest = SafePos THEN
      HandTarget := HandRest;
    END_IF;
  ELSIF reqOpen THEN
    IF Permissive OR HandOpen = SafePos THEN
      HandTarget := HandOpen;
    END_IF;
  ELSIF LocalPos > 0 THEN
    IF Permissive OR INT_TO_REAL(LocalPos) = SafePos THEN
      HandTarget := INT_TO_REAL(LocalPos);
    END_IF;
  END_IF;
END_IF;

(* what the valve should do *)
IF oos OR cfgOn OR NOT ActRemote THEN
  Aim := UT_VA_OFF;
ELSIF CurMode = UT_MODE_OFF OR NOT Interlock OR tripped OR mustCycle THEN
  Aim := UT_VA_SAFE;
ELSIF isHand THEN
  Aim := UT_VA_HAND;
ELSIF autoRun OR exPhase = 1 OR exPhase = 2 THEN
  Aim := UT_VA_RUN;
ELSE
  Aim := UT_VA_REST;
END_IF;
(* Permissive FALSE: a move away from the safe position does not start *)
IF NOT Permissive AND Aim = UT_VA_RUN AND NOT Away THEN
  Aim := UT_VA_HOLD;
END_IF;

(* why it last went back to safe / rest *)
IF tripped OR cfgOn THEN
  safeWhy := UT_STOP_FAULT;
ELSIF NOT Interlock THEN
  safeWhy := UT_STOP_INTERLOCK;
ELSIF CurMode = UT_MODE_OFF OR oos THEN
  safeWhy := UT_STOP_SWITCHED_OFF;
ELSIF held THEN
  safeWhy := UT_STOP_OPERATOR;
ELSE
  safeWhy := UT_STOP_NONE;
END_IF;
IF awayPrev AND NOT Away AND Data.sts.stopReason <> UT_STOP_EXERCISE_DONE THEN
  IF safeWhyPrev <> UT_STOP_NONE THEN
    Data.sts.stopReason := safeWhyPrev;
  ELSIF handPrev THEN
    Data.sts.stopReason := UT_STOP_OPERATOR;
  ELSIF runIn.AliveLost THEN
    Data.sts.stopReason := UT_STOP_COMMS_LOST;
  ELSE
    Data.sts.stopReason := UT_STOP_DEMAND_ENDED;
  END_IF;
END_IF;
IF Away AND NOT awayPrev THEN
  Data.sts.stopReason := UT_STOP_NONE;
END_IF;
awayPrev := Away;
safeWhyPrev := safeWhy;
handPrev := isHand;

IF StrokeDone THEN
  Data.tot.strokes := Data.tot.strokes + 1;
END_IF;

Auto := isAuto;
Hand := isHand;
Ready := (isHand OR isAuto) AND NOT tripped AND NOT cfgOn AND Interlock AND Permissive AND NOT mustCycle
         AND ActRemote AND NOT held;

(* fault code, last trip *)
Data.sts.faultCode := Ext.tripped;
IF cfgOn OR cfgWarnId <> UT_F_NONE THEN Data.sts.faultCode := Data.sts.faultCode OR 16#100; END_IF;
IF Data.sts.slowStroke.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#800; END_IF;
IF Data.sts.actLocal.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#400; END_IF;
IF Data.sts.torque.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#200; END_IF;
IF Data.sts.drive.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#20; END_IF;
IF Data.sts.noMovement.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#10; END_IF;
IF Data.sts.positionLost.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#8; END_IF;
IF Data.sts.bothLimits.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#4; END_IF;
IF Data.sts.closeTimeout.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2; END_IF;
IF Data.sts.openTimeout.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1; END_IF;
tripCode := Ext.trip;
IF sOpenT.trip THEN tripCode := tripCode OR 16#1; END_IF;
IF sCloseT.trip THEN tripCode := tripCode OR 16#2; END_IF;
IF sBoth.trip THEN tripCode := tripCode OR 16#4; END_IF;
IF sLost.trip THEN tripCode := tripCode OR 16#8; END_IF;
IF sNoMove.trip THEN tripCode := tripCode OR 16#10; END_IF;
IF sDrive.trip THEN tripCode := tripCode OR 16#20; END_IF;
IF cfgOn THEN tripCode := tripCode OR 16#100; END_IF;
IF sTorque.trip THEN tripCode := tripCode OR 16#200; END_IF;
IF sLocal.trip THEN tripCode := tripCode OR 16#400; END_IF;
IF sSlow.trip THEN tripCode := tripCode OR 16#800; END_IF;
newBits := tripCode AND NOT tripPrev;
tripPrev := tripCode;
IF newBits <> 0 AND NOT oos THEN
  Data.sts.trips := Data.sts.trips + 1;
  Data.sts.lastFaultCode := tripCode;
  IF (newBits AND 16#1) <> 0 THEN Data.sts.lastFault := UT_F_OPEN_TIMEOUT;
  ELSIF (newBits AND 16#2) <> 0 THEN Data.sts.lastFault := UT_F_CLOSE_TIMEOUT;
  ELSIF (newBits AND 16#4) <> 0 THEN Data.sts.lastFault := UT_F_BOTH_LIMITS;
  ELSIF (newBits AND 16#8) <> 0 THEN Data.sts.lastFault := UT_F_POS_LOST;
  ELSIF (newBits AND 16#10) <> 0 THEN Data.sts.lastFault := UT_F_NO_MOVEMENT;
  ELSIF (newBits AND 16#20) <> 0 THEN Data.sts.lastFault := UT_F_ACTUATOR;
  ELSIF (newBits AND 16#200) <> 0 THEN Data.sts.lastFault := UT_F_TORQUE;
  ELSIF (newBits AND 16#400) <> 0 THEN Data.sts.lastFault := UT_F_ACT_LOCAL;
  ELSIF (newBits AND 16#800) <> 0 THEN Data.sts.lastFault := UT_F_SLOW_STROKE;
  ELSIF (newBits AND 16#100) <> 0 THEN Data.sts.lastFault := cfgWhich;
  ELSE Data.sts.lastFault := Ext.tripId;
  END_IF;
END_IF;

(* status: config > fault > held / waiting > warning > normal > idle *)
vHeld := VarStatus = UT_ST_DEAD_TIME OR VarStatus = UT_ST_NOT_HOMED OR VarStatus = UT_ST_MOVE_TIMEOUT
         OR VarStatus = UT_ST_NOT_PERMITTED;
vNormal := NOT vHeld AND VarStatus <> UT_ST_IDLE;
have := TRUE;
stF := UT_F_NONE;
stTime := T#0s;
IF cfgOn THEN
  stCode := UT_ST_CONFIG;
  stF := cfgWhich;
ELSIF tripped AND NOT oos THEN
  IF sOpenT.trip THEN stF := UT_F_OPEN_TIMEOUT; stCode := UT_PROT_STATUS(Reset := Data.set.openTimeout.reset, Sts := Data.sts.openTimeout); stTime := Data.sts.openTimeout.timeLeft;
  ELSIF sCloseT.trip THEN stF := UT_F_CLOSE_TIMEOUT; stCode := UT_PROT_STATUS(Reset := Data.set.closeTimeout.reset, Sts := Data.sts.closeTimeout); stTime := Data.sts.closeTimeout.timeLeft;
  ELSIF sBoth.trip THEN stF := UT_F_BOTH_LIMITS; stCode := UT_PROT_STATUS(Reset := Data.set.bothLimits.reset, Sts := Data.sts.bothLimits); stTime := Data.sts.bothLimits.timeLeft;
  ELSIF sLost.trip THEN stF := UT_F_POS_LOST; stCode := UT_PROT_STATUS(Reset := Data.set.positionLost.reset, Sts := Data.sts.positionLost); stTime := Data.sts.positionLost.timeLeft;
  ELSIF sNoMove.trip THEN stF := UT_F_NO_MOVEMENT; stCode := UT_PROT_STATUS(Reset := Data.set.noMovement.reset, Sts := Data.sts.noMovement); stTime := Data.sts.noMovement.timeLeft;
  ELSIF sDrive.trip THEN stF := UT_F_ACTUATOR; stCode := UT_PROT_STATUS(Reset := Data.set.drive.reset, Sts := Data.sts.drive); stTime := Data.sts.drive.timeLeft;
  ELSIF sTorque.trip THEN stF := UT_F_TORQUE; stCode := UT_PROT_STATUS(Reset := Data.set.torque.reset, Sts := Data.sts.torque); stTime := Data.sts.torque.timeLeft;
  ELSIF sLocal.trip THEN stF := UT_F_ACT_LOCAL; stCode := UT_PROT_STATUS(Reset := Data.set.actLocal.reset, Sts := Data.sts.actLocal); stTime := Data.sts.actLocal.timeLeft;
  ELSIF sSlow.trip THEN stF := UT_F_SLOW_STROKE; stCode := UT_PROT_STATUS(Reset := Data.set.slowStroke.reset, Sts := Data.sts.slowStroke); stTime := Data.sts.slowStroke.timeLeft;
  ELSE stF := Ext.tripId; stCode := Ext.tripStatus; stTime := Ext.tripTime;
  END_IF;
ELSIF oos THEN
  stCode := UT_ST_OOS;
ELSIF NOT ActRemote THEN
  stCode := UT_ST_ACT_LOCAL;
ELSIF NOT Interlock THEN
  stCode := UT_ST_INTERLOCK;
ELSIF isAuto AND held THEN
  stCode := UT_ST_HELD_BY_LINK;
ELSIF isAuto AND mustCycle THEN
  stCode := UT_ST_MUST_CYCLE;
ELSIF (isHand OR isAuto) AND vHeld THEN
  stCode := VarStatus;
  stTime := VarTime;
ELSE
  have := FALSE;
END_IF;
IF NOT have AND Warning THEN
  have := TRUE;
  stCode := UT_ST_WARNING;
  IF sOpenT.warn THEN stF := UT_F_OPEN_TIMEOUT;
  ELSIF sCloseT.warn THEN stF := UT_F_CLOSE_TIMEOUT;
  ELSIF sBoth.warn THEN stF := UT_F_BOTH_LIMITS;
  ELSIF sLost.warn THEN stF := UT_F_POS_LOST;
  ELSIF sNoMove.warn THEN stF := UT_F_NO_MOVEMENT;
  ELSIF sDrive.warn THEN stF := UT_F_ACTUATOR;
  ELSIF sTorque.warn THEN stF := UT_F_TORQUE;
  ELSIF sLocal.warn THEN stF := UT_F_ACT_LOCAL;
  ELSIF sSlow.warn THEN stF := UT_F_SLOW_STROKE;
  ELSIF Ext.warn <> 0 THEN stF := Ext.warnId;
  ELSIF ExpectAuto AND NOT isAuto THEN stF := UT_F_NOT_AUTO;
  ELSIF ignored THEN stF := UT_F_RUN_IGNORED;
  ELSIF modeSel.SwFault THEN stF := UT_F_SELECTOR;
  ELSIF Data.simulate THEN stCode := UT_ST_SIMULATED; stF := UT_F_SIMULATED;
  ELSE
    stCode := UT_ST_WARN_SETTING;
    stF := cfgWarnId;
  END_IF;
END_IF;
IF NOT have THEN
  IF Exercising THEN
    stCode := UT_ST_EXERCISING;
  ELSIF (isHand OR isAuto) AND vNormal THEN
    stCode := VarStatus;
    stTime := VarTime;
  ELSIF isAuto AND Linked AND Away THEN
    stCode := UT_ST_RUN_LINKED;
  ELSIF isHand OR isAuto THEN
    stCode := UT_ST_IDLE;
  ELSE
    stCode := UT_ST_OFF;
  END_IF;
END_IF;
IF stTime < T#0s THEN
  stTime := T#0s;
END_IF;
TimeLeft := stTime;
Data.det.timeLeft := stTime;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
StopReason := Data.sts.stopReason;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault,
                               Check := NOT isAuto OR NOT ActRemote OR Data.simulate OR Exercising,
                               OutOfSpec := Warning, Maint := sSlow.warn OR sSlow.trip);
Data.sts.mode := CurMode;
Data.sts.linked := Linked;
Data.sts.held := held;
IF Linked THEN
  Data.sts.owner := linkOwner;
ELSE
  Data.sts.owner := '';
END_IF;
Data.sts.ready := Ready;
Data.sts.interlocked := NOT Interlock;
Data.sts.notPermitted := NOT Permissive;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.configBad := cfgOn;
Data.sts.notAuto := ExpectAuto AND NOT isAuto;
Data.sts.selectorFault := modeSel.SwFault;
Data.sts.exercising := Exercising;
Data.sts.confirmed := Confirmed;
CurStatus := stCode;
CurFault := stF;
CurLocked := Data.sts.openTimeout.locked OR Data.sts.closeTimeout.locked OR Data.sts.bothLimits.locked
             OR Data.sts.positionLost.locked OR Data.sts.noMovement.locked OR Data.sts.drive.locked
             OR Data.sts.torque.locked OR Data.sts.actLocal.locked OR Data.sts.slowStroke.locked OR Ext.locked;
CurNe := Data.sts.ne107;

END_FUNCTION_BLOCK