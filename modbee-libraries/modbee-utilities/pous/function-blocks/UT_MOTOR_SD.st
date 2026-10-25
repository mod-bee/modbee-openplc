(* UT_MOTOR_SD EXTENDS UT_MOTOR — a star-delta starter. Everything of UT_MOTOR
plus the star -> delta sequence. Inherited pins here: Q = main contactor;
Feedback = main contactor aux; Jog does the full star -> delta changeover
while held. DriveFault and TopOfRamp are not used.

Sequence: main and star together; star for starTime (or, with
starCurrentPct > 0, until the star current has risen above and fallen
back below that % FLC), and the main confirmed; star off; the open
transition (transitionTime, and with useStarDeltaFb the star aux open);
delta on. Star and Delta are never on together (UT_CHANGEOVER_RUN). A
contactor aux that does not follow its coil within changeoverTime trips
`changeover` (MANUAL). The start is done in delta (current mask, start too
long). Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_MOTOR_SD EXTENDS UT_MOTOR
  VAR_INPUT
    FeedbackStar : BOOL; (* star contactor aux *)
    FeedbackDelta : BOOL; (* delta contactor aux *)
  END_VAR
  VAR_OUTPUT
    Star : BOOL; (* never with Delta *)
    Delta : BOOL;
  END_VAR
  VAR_IN_OUT
    Sd : UT_MOTOR_SD_DATA;
  END_VAR
  VAR RETAIN
    sKeptSet : UT_MOTOR_SD_SET;
    sKeptGood : BOOL;
  END_VAR
  VAR
    sKeep : UT_KEEP;
    sOk : BOOL;
    sFault : UT_FAULT;
    co : UT_CHANGEOVER_RUN;
    sChg : UT_PROT_ST;
    sNow : TIME;
    starAt : TIME;
    starWas : BOOL;
    seenHigh : BOOL;
    toDelta : BOOL;
    sb : BOOL;
  END_VAR


sNow := TIME();
sKeep();
IF sKeep.RestoreSet THEN
  Sd.set := sKeptSet;
END_IF;
sFault := UT_F_NONE;
IF Sd.set.starTime <= T#0s THEN
  sFault := UT_F_STAR_TIME;
ELSIF Sd.set.transitionTime < T#0s THEN
  sFault := UT_F_TRANSITION_TIME;
ELSIF NOT (Sd.set.starCurrentPct >= 0.0 AND Sd.set.starCurrentPct <= 3.4E38) THEN
  sFault := UT_F_STAR_CURRENT;
ELSIF Sd.set.starCurrentPct > 0.0 AND NOT (Data.set.fullLoadCurrent > 0.0) THEN
  sFault := UT_F_STAR_NEEDS_FLC;
ELSIF Sd.set.changeoverTime <= T#0s THEN
  sFault := UT_F_CHANGEOVER_TIME;
ELSIF NOT UT_PROT_OK(P := Sd.set.changeover) THEN
  sFault := UT_F_CHANGEOVER;
END_IF;
sOk := sFault = UT_F_NONE;
IF NOT sOk AND sKeptGood AND NOT sKeep.FirstBoot THEN
  Sd.sts.refused := sFault;
  Sd.set := sKeptSet;
  sFault := UT_F_NONE;           (* the kept copy passed this check *)
  sOk := TRUE;
END_IF;
IF sKeep.SaveSet AND (sOk OR NOT sKeptGood) THEN
  sKeptSet := Sd.set;
  sKeptGood := sOk;
END_IF;

(* the star time, or the star current risen and fallen (from last scan) *)
IF Star AND NOT starWas THEN
  starAt := sNow;
  seenHigh := FALSE;
END_IF;
starWas := Star;
IF Star AND Sd.set.starCurrentPct > 0.0 THEN
  IF Data.sts.currentPct >= Sd.set.starCurrentPct THEN
    seenHigh := TRUE;
  ELSIF seenHigh AND Running THEN
    toDelta := TRUE;
  END_IF;
END_IF;
IF Star AND sNow - starAt >= Sd.set.starTime AND Running THEN
  toDelta := TRUE;               (* the main confirmed *)
END_IF;
IF NOT runReq THEN
  toDelta := FALSE;
END_IF;

(* hooks for the base *)
vCfgFault := sFault <> UT_F_NONE AND sFault <> UT_F_CHANGEOVER;
vCfgWarn := sFault = UT_F_CHANGEOVER;
vCfgId := sFault;
vStartBlock := co.StartBlock AND NOT runReq;
vStartDone := Delta;
IF Star AND NOT toDelta THEN
  vStatus := UT_ST_STAR;
  vTime := Sd.set.starTime - (sNow - starAt);
ELSIF Star AND sNow - starAt >= Sd.set.starTime AND NOT Running THEN
  vStatus := UT_ST_WAIT_MAIN_FB;
  vTime := T#0s;
ELSIF co.Waiting <> UT_ST_IDLE THEN
  vStatus := co.Waiting;
  vTime := co.TimeLeft;
ELSE
  vStatus := UT_ST_IDLE;
  vTime := T#0s;
END_IF;
sb := UT_PROT_EXT_CLEAR(Sum := vTrip);
sb := UT_PROT_RUN(TNow := sNow, Cause := curMode <> UT_MODE_OOS AND co.Cause, ResetReq := resetReq,
                  RetryWindow := Data.set.retryWindow, Prot := Sd.set.changeover, Sts := Sd.sts.changeover, St := sChg);
sb := UT_PROT_EXT(Bit := 16#200, Id := UT_F_CHANGEOVER, Reset := Sd.set.changeover.reset, St := sChg,
                  Sts := Sd.sts.changeover, Sum := vTrip);

SUPER();

(* star with the main; delta once the star time is done and the main confirmed *)
co(Run := runReq, WantB := toDelta, FbA := FeedbackStar, FbB := FeedbackDelta,
   UseFb := Sd.set.useStarDeltaFb AND NOT Data.simulate, GapAB := Sd.set.transitionTime, GapBA := Sd.set.transitionTime,
   OpenTime := Sd.set.changeoverTime, PowerUp := powerUp);
Star := co.QA;
Delta := co.QB;
Sd.sts.inStar := Star;

END_FUNCTION_BLOCK