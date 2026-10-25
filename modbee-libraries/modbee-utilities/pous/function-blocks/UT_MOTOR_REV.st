(* UT_MOTOR_REV EXTENDS UT_MOTOR — a reversing starter. Everything of UT_MOTOR
plus the direction. Inherited pins here: Start / LocalStart / cmdStart =
a Hand start in the last direction (forward after power-up); Jog = jog
forward (JogRev reverse; both held = none); Q = TRUE while either direction
runs; FeedbackFwd / FeedbackRev confirm running (Feedback, TopOfRamp not
used).

Direction: Jog / JogRev; Hand -> LocalRev / cmdRev = reverse start, cmdFwd =
forward start, else the last direction; Auto linked -> the owner's ReqSpeed
(NaN = AutoReverse; < 0 = reverse); Auto -> AutoReverse. Forward and reverse
are never on together: a change waits reversalDelay (UT_CHANGEOVER_RUN);
with stopBeforeReverse a direction change stops and needs a new start.
LimitFwd / LimitRev (end of travel): that direction stops and will not
start. A contactor aux that does not follow within changeoverTime trips
`changeover`. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_MOTOR_REV EXTENDS UT_MOTOR
  VAR_INPUT
    JogRev : BOOL; (* held: jog reverse (Hand only) *)
    AutoReverse : BOOL; (* Auto direction when the owner gives none *)
    FeedbackFwd : BOOL;
    FeedbackRev : BOOL;
    LimitFwd : BOOL; (* end of travel forward *)
    LimitRev : BOOL;
    LocalRev : BOOL R_EDGE; (* Hand start reverse *)
  END_VAR
  VAR_OUTPUT
    RunFwd : BOOL;
    RunRev : BOOL; (* never with RunFwd *)
    Reversed : BOOL;
  END_VAR
  VAR_IN_OUT
    Rev : UT_MOTOR_REV_DATA;
  END_VAR
  VAR RETAIN
    rKeptSet : UT_MOTOR_REV_SET;
    rKeptGood : BOOL;
  END_VAR
  VAR
    rKeep : UT_KEEP;
    rOk : BOOL;
    rFault : UT_FAULT;
    co : UT_CHANGEOVER_RUN;
    rChg : UT_PROT_ST;
    rNow : TIME;
    handRev : BOOL; (* the Hand direction (forward after power-up) *)
    wantRev : BOOL;
    wantRevPrev : BOOL;
    goFwd : BOOL;
    goRev : BOOL;
    limited : BOOL;
    rb : BOOL;
  END_VAR


METHOD PUBLIC OVERRIDE GetSpeed : REAL
  IF NOT Running THEN
    GetSpeed := 0.0;
  ELSIF Reversed THEN
    GetSpeed := -100.0;
  ELSE
    GetSpeed := 100.0;
  END_IF;
END_METHOD

rNow := TIME();
rKeep();
IF rKeep.RestoreSet THEN
  Rev.set := rKeptSet;
END_IF;
rFault := UT_F_NONE;
IF Rev.set.reversalDelay < T#0s THEN
  rFault := UT_F_REVERSAL_DELAY;
ELSIF Rev.set.changeoverTime <= T#0s THEN
  rFault := UT_F_CHANGEOVER_TIME;
ELSIF NOT UT_PROT_OK(P := Rev.set.changeover) THEN
  rFault := UT_F_CHANGEOVER;
END_IF;
rOk := rFault = UT_F_NONE;
IF NOT rOk AND rKeptGood AND NOT rKeep.FirstBoot THEN
  Rev.sts.refused := rFault;
  Rev.set := rKeptSet;
  rFault := UT_F_NONE;
  rOk := TRUE;
END_IF;
IF rKeep.SaveSet AND (rOk OR NOT rKeptGood) THEN
  rKeptSet := Rev.set;
  rKeptGood := rOk;
END_IF;
IF rKeep.PowerUp THEN
  handRev := FALSE;
END_IF;

(* Hand direction buttons and commands: choose it and start *)
goFwd := Rev.cmdFwd;
goRev := LocalRev OR Rev.cmdRev;
Rev.cmdFwd := FALSE;
Rev.cmdRev := FALSE;
IF curMode = UT_MODE_HAND THEN
  IF goRev THEN
    handRev := TRUE;
  ELSIF goFwd THEN
    handRev := FALSE;
  END_IF;
END_IF;
vHandStart := goFwd OR goRev;
vJog := JogRev;
vNoJog := Jog AND JogRev;        (* both held: no jog *)

(* the direction wanted (from this scan's mode and last scan's link) *)
IF curMode = UT_MODE_HAND AND JogRev AND NOT Jog THEN
  wantRev := TRUE;
ELSIF curMode = UT_MODE_HAND AND Jog THEN
  wantRev := FALSE;
ELSIF curMode = UT_MODE_HAND THEN
  wantRev := handRev;
ELSIF Linked AND linkSpeed = linkSpeed THEN
  wantRev := linkSpeed < 0.0;
ELSE
  wantRev := AutoReverse;
END_IF;
limited := (wantRev AND LimitRev) OR (NOT wantRev AND LimitFwd);

(* hooks for the base *)
vCfgFault := rFault <> UT_F_NONE AND rFault <> UT_F_CHANGEOVER;
vCfgWarn := rFault = UT_F_CHANGEOVER;
vCfgId := rFault;
vOwnFb := TRUE;
vFeedback := FeedbackFwd OR FeedbackRev;
vPlannedGap := co.InGap;
vStartBlock := co.StartBlock AND NOT runReq;
vHold := limited;
vStop := Rev.set.stopBeforeReverse AND runReq AND wantRev <> wantRevPrev;
vStartDone := runReq AND NOT co.InGap AND Reversed = wantRev;
IF limited THEN
  vStatus := UT_ST_AT_LIMIT;
  vTime := T#0s;
ELSIF co.Waiting <> UT_ST_IDLE THEN
  vStatus := co.Waiting;
  vTime := co.TimeLeft;
ELSE
  vStatus := UT_ST_IDLE;
  vTime := T#0s;
END_IF;
rb := UT_PROT_EXT_CLEAR(Sum := vTrip);
rb := UT_PROT_RUN(TNow := rNow, Cause := curMode <> UT_MODE_OOS AND co.Cause, ResetReq := resetReq,
                  RetryWindow := Data.set.retryWindow, Prot := Rev.set.changeover, Sts := Rev.sts.changeover, St := rChg);
rb := UT_PROT_EXT(Bit := 16#200, Id := UT_F_CHANGEOVER, Reset := Rev.set.changeover.reset, St := rChg,
                  Sts := Rev.sts.changeover, Sum := vTrip);

SUPER();

wantRevPrev := wantRev;
co(Run := runReq, WantB := wantRev, FbA := FeedbackFwd, FbB := FeedbackRev,
   UseFb := Data.set.useFeedback AND NOT Data.simulate, GapAB := Rev.set.reversalDelay, GapBA := Rev.set.reversalDelay,
   OpenTime := Rev.set.changeoverTime, PowerUp := powerUp);
RunFwd := co.QA;
RunRev := co.QB;
Reversed := RunRev;
Q := RunFwd OR RunRev;
Rev.sts.reverse := Reversed;
Rev.sts.atLimitFwd := LimitFwd;
Rev.sts.atLimitRev := LimitRev;

END_FUNCTION_BLOCK