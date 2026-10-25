(* UT_MOTOR_2SPD EXTENDS UT_MOTOR — a two-speed starter (Dahlander or separate
windings). Everything of UT_MOTOR plus the speed choice. Inherited pins
here: Hand Start runs at the kept Hand speed (set.handHigh); Jog at
jogSpeed; Q = TRUE while either speed runs; the per-speed feedbacks
confirm running (Feedback, DriveFault, TopOfRamp not used).

Speed: Jog -> jogSpeed; Hand -> handHigh (LocalLow / LocalHigh / cmdLow /
cmdHigh choose it and start); Auto linked -> the owner's ReqSpeed (NaN =
AutoHigh; <= lowSpeedPct = low, above = high); Auto -> AutoHigh. With
startInLow a start to high runs low for lowStartTime first. Low and high
are never on together: low -> high waits speedChangeDelay, high -> low
downChangeDelay (0 = speedChangeDelay). Bridge (Dahlander star point) only
with high. A contactor aux that does not follow within changeoverTime trips
`changeover`. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_MOTOR_2SPD EXTENDS UT_MOTOR
  VAR_INPUT
    AutoHigh : BOOL; (* Auto speed when the owner gives none *)
    FeedbackLow : BOOL;
    FeedbackHigh : BOOL;
    LocalLow : BOOL R_EDGE; (* Hand start / change to low *)
    LocalHigh : BOOL R_EDGE; (* Hand start / change to high *)
  END_VAR
  VAR_OUTPUT
    RunLow : BOOL;
    RunHigh : BOOL; (* never with RunLow *)
    Bridge : BOOL; (* Dahlander: only with RunHigh *)
    HighSpeed : BOOL;
  END_VAR
  VAR_IN_OUT
    Spd : UT_MOTOR_2SPD_DATA;
  END_VAR
  VAR RETAIN
    pKeptSet : UT_MOTOR_2SPD_SET;
    pKeptGood : BOOL;
  END_VAR
  VAR
    pKeep : UT_KEEP;
    pOk : BOOL;
    pFault : UT_FAULT;
    co : UT_CHANGEOVER_RUN;
    pChg : UT_PROT_ST;
    pNow : TIME;
    hLow : BOOL;
    hHigh : BOOL;
    wantHigh : BOOL;
    lowFirst : BOOL;
    runAt : TIME;
    runWasP : BOOL;
    pb : BOOL;
    lowPct : REAL;
  END_VAR


METHOD PUBLIC OVERRIDE GetSpeed : REAL
  IF NOT Running THEN
    GetSpeed := 0.0;
  ELSIF HighSpeed THEN
    GetSpeed := 100.0;
  ELSE
    GetSpeed := lowPct;              (* a method may not read the in-out *)
  END_IF;
END_METHOD

pNow := TIME();
pKeep();
IF pKeep.RestoreSet THEN
  Spd.set := pKeptSet;
END_IF;
pFault := UT_F_NONE;
IF Spd.set.speedChangeDelay < T#0s OR Spd.set.downChangeDelay < T#0s THEN
  pFault := UT_F_SPEED_CHANGE;
ELSIF Spd.set.startInLow AND Spd.set.lowStartTime < T#0s THEN
  pFault := UT_F_LOW_START_TIME;
ELSIF NOT (Spd.set.lowSpeedPct > 0.0 AND Spd.set.lowSpeedPct < 100.0) THEN
  pFault := UT_F_LOW_SPEED_PCT;
ELSIF Spd.set.changeoverTime <= T#0s THEN
  pFault := UT_F_CHANGEOVER_TIME;
ELSIF NOT UT_PROT_OK(P := Spd.set.changeover) OR NOT (Spd.set.jogSpeed = UT_JOG_LOW OR Spd.set.jogSpeed = UT_JOG_HIGH) THEN
  pFault := UT_F_CHANGEOVER;
END_IF;
pOk := pFault = UT_F_NONE;
IF NOT pOk AND pKeptGood AND NOT pKeep.FirstBoot THEN
  Spd.sts.refused := pFault;
  Spd.set := pKeptSet;
  pFault := UT_F_NONE;
  pOk := TRUE;
END_IF;
IF pKeep.SaveSet AND (pOk OR NOT pKeptGood) THEN
  pKeptSet := Spd.set;
  pKeptGood := pOk;
END_IF;

(* Hand speed choice: the buttons and commands choose it (kept) and start *)
hLow := LocalLow OR Spd.cmdLow;
hHigh := LocalHigh OR Spd.cmdHigh;
Spd.cmdLow := FALSE;
Spd.cmdHigh := FALSE;
IF curMode = UT_MODE_HAND THEN
  IF hHigh THEN
    Spd.set.handHigh := TRUE;
  ELSIF hLow THEN
    Spd.set.handHigh := FALSE;
  END_IF;
END_IF;
vHandStart := hLow OR hHigh;

(* hooks for the base *)
vCfgFault := pFault <> UT_F_NONE AND pFault <> UT_F_CHANGEOVER;
vCfgWarn := pFault = UT_F_CHANGEOVER;
vCfgId := pFault;
vOwnFb := TRUE;
vFeedback := FeedbackLow OR FeedbackHigh;
vPlannedGap := co.InGap;
vStartBlock := co.StartBlock AND NOT runReq;
vStartDone := runReq AND NOT co.InGap AND HighSpeed = wantHigh;
IF lowFirst AND runReq THEN
  vStatus := UT_ST_LOW_FIRST;
  vTime := Spd.set.lowStartTime - (pNow - runAt);
ELSIF co.Waiting <> UT_ST_IDLE THEN
  vStatus := co.Waiting;
  vTime := co.TimeLeft;
ELSE
  vStatus := UT_ST_IDLE;
  vTime := T#0s;
END_IF;
pb := UT_PROT_EXT_CLEAR(Sum := vTrip);
pb := UT_PROT_RUN(TNow := pNow, Cause := curMode <> UT_MODE_OOS AND co.Cause, ResetReq := resetReq,
                  RetryWindow := Data.set.retryWindow, Prot := Spd.set.changeover, Sts := Spd.sts.changeover, St := pChg);
pb := UT_PROT_EXT(Bit := 16#200, Id := UT_F_CHANGEOVER, Reset := Spd.set.changeover.reset, St := pChg,
                  Sts := Spd.sts.changeover, Sum := vTrip);

SUPER();

(* the speed wanted *)
IF Jogging THEN
  wantHigh := Spd.set.jogSpeed = UT_JOG_HIGH;
ELSIF curMode = UT_MODE_HAND THEN
  wantHigh := Spd.set.handHigh;
ELSIF Linked AND linkSpeed = linkSpeed THEN
  wantHigh := linkSpeed > Spd.set.lowSpeedPct;
ELSE
  wantHigh := AutoHigh;
END_IF;
(* a start to high runs low first *)
IF runReq AND NOT runWasP THEN
  runAt := pNow;
  lowFirst := Spd.set.startInLow AND Spd.set.lowStartTime > T#0s AND wantHigh;
END_IF;
runWasP := runReq;
IF lowFirst AND (pNow - runAt >= Spd.set.lowStartTime OR NOT wantHigh) THEN
  lowFirst := FALSE;
END_IF;
co(Run := runReq, WantB := wantHigh AND NOT lowFirst, FbA := FeedbackLow, FbB := FeedbackHigh,
   UseFb := Data.set.useFeedback AND NOT Data.simulate, GapAB := Spd.set.speedChangeDelay,
   GapBA := SEL(Spd.set.downChangeDelay > T#0s, Spd.set.speedChangeDelay, Spd.set.downChangeDelay),
   OpenTime := Spd.set.changeoverTime, PowerUp := powerUp);
RunLow := co.QA;
RunHigh := co.QB;
Bridge := Spd.set.dahlander AND RunHigh;
HighSpeed := RunHigh;
Q := RunLow OR RunHigh;
Spd.sts.highSpeed := HighSpeed;
lowPct := Spd.set.lowSpeedPct;

END_FUNCTION_BLOCK