(* UT_VALVE_FLOAT — floating (three-point) valve or damper: raise / lower
contacts only (OpenOut = raise, CloseOut = lower, never together, a
reversal pause between them). The position is the feedback (PosFb) when
good, else estimated from the run time (strokeTime), re-synced at the ends
by over-travel or the end switches; homed by a full lower at power-up
(homeOnStart) or on cmdHome.

Where it goes (UT_VALVE's core decides the Aim): Auto = Sp (NaN keeps the
last good); OpenCmd / CloseCmd drive fully open / closed (set.cmdPulse:
a pulse latches, the same or the other command goes back to Sp; held: while
TRUE, close wins); linked = the owner's ReqPos (none: 100 %), its open off
= restPos; Hand = HandSp when wired, else the kept handPos (LocalOpen /
LocalClose / cmdOpen / cmdClose write 100 / 0 %, LocalStop / cmdStop the
position now; bumpless on entry); Off / Interlock / a trip = safePosition
(< 0 stays). Moves shorter than minPulse or inside the deadband are not
made. Feedback range and deviation: UT_POS_FB_RUN. Settings kept; a bad
write is put back. *)

FUNCTION_BLOCK UT_VALVE_FLOAT EXTENDS UT_VALVE
  VAR_INPUT
    Sp : REAL; (* Auto position %; NaN keeps the last good *)
    HandSp : REAL := -1.0; (* Hand position % from a pot; < 0 / NaN = set.handPos *)
    PosFb : UT_I_MEAS; (* position feedback; NULL = estimate from the run time *)
  END_VAR
  VAR_IN_OUT
    Floating : UT_VALVE_FLOAT_DATA;
  END_VAR
  VAR RETAIN
    fKeptSet : UT_VALVE_FLOAT_SET;
    fKeptGood : BOOL;
  END_VAR
  VAR
    fKeep : UT_KEEP;
    fco : UT_CHANGEOVER_RUN;
    fbSt : UT_POS_FB_ST;
    fOk : BOOL;
    fFault : UT_FAULT;
    fWarn : UT_FAULT;
    fNow : TIME;
    fPrev : TIME;
    fStarted : BOOL;
    fFirst : BOOL;
    fx : BOOL;
    dMs : LINT;
    strokeMs : REAL;
    est : REAL;
    homed : BOOL;
    homing : BOOL;
    homeAsk : BOOL;
    hHome : BOOL;
    fbFit : BOOL;
    fbV : REAL;
    fbG : BOOL;
    fbOk : BOOL;
    known : BOOL;
    fLsO : BOOL;
    fLsC : BOOL;
    fIsO : BOOL;
    fIsC : BOOL;
    pos : REAL;
    spW : REAL; (* where it is going, % *)
    autoSp : REAL; (* the last good Sp *)
    ovr : INT; (* Auto command override: 0 none, 1 closed, 2 open *)
    hOc : BOOL;
    hCc : BOOL;
    htPrev : REAL := -2.0;
    handWired : BOOL;
    fHold : BOOL;
    dir : INT; (* 0 still, 1 lower, 2 raise *)
    toEnd : BOOL;
    atEndTime : BOOL;
    endSince : TIME;
    pulseStart : TIME;
    outOnPrev : BOOL;
    elapsed : TIME;
    stopNow : BOOL;
    want : INT;
    err : REAL;
    dbEff : REAL;
    synced0 : BOOL;
    synced100 : BOOL;
    capped : BOOL;
    cappedSp : REAL;
    fStroke : BOOL;
    fCauses : UT_VALVE_CAUSES;
    fStatus : UT_STATUS := UT_ST_IDLE;
    fTime : TIME;
    fp : REAL;
  END_VAR


fNow := TIME();
fFirst := NOT fStarted;
IF NOT fStarted THEN
  fStarted := TRUE;
  fPrev := fNow;
  homed := NOT Floating.set.homeOnStart;
END_IF;
fKeep();
IF fKeep.RestoreSet THEN
  Floating.set := fKeptSet;
END_IF;
fOk := UT_VALVE_FLOAT_CHECK(S := Floating.set, Fault => fFault, Warn => fWarn);
IF NOT fOk AND fKeptGood AND NOT fKeep.FirstBoot THEN
  IF fFault <> UT_F_NONE THEN Floating.sts.refused := fFault; ELSE Floating.sts.refused := fWarn; END_IF;
  Floating.set := fKeptSet;
  fOk := UT_VALVE_FLOAT_CHECK(S := Floating.set, Fault => fFault, Warn => fWarn);
END_IF;
IF fKeep.SaveSet AND (fOk OR NOT fKeptGood) THEN
  fKeptSet := Floating.set;
  fKeptGood := fOk;
END_IF;
strokeMs := LINT_TO_REAL(TIME_TO_LINT(Floating.set.strokeTime));
IF strokeMs < 1.0 THEN
  strokeMs := 1.0;
END_IF;

(* the estimate: last scan's drive, whole ms (the rest carries on) *)
dMs := TIME_TO_LINT(fNow - fPrev);
fPrev := fPrev + LINT_TO_TIME(dMs);
IF OpenOut THEN
  est := est + 100.0 * LINT_TO_REAL(dMs) / strokeMs;
ELSIF CloseOut THEN
  est := est - 100.0 * LINT_TO_REAL(dMs) / strokeMs;
END_IF;
est := LIMIT(0.0, est, 100.0);
fLsO := Data.set.useOpenLs AND OpenLs AND NOT Data.simulate;
fLsC := Data.set.useClosedLs AND ClosedLs AND NOT Data.simulate;
IF fLsC AND NOT fLsO THEN
  est := 0.0;                    (* an end switch re-syncs *)
  homed := TRUE;
ELSIF fLsO AND NOT fLsC THEN
  est := 100.0;
END_IF;

(* the feedback and the position in use *)
fbFit := FALSE;
fbV := 0.0;
fbG := FALSE;
IF PosFb <> NULL THEN
  fbFit := PosFb.IsFitted();
  fbV := PosFb.GetValue();
  fbG := PosFb.GoodNow();
END_IF;
fx := UT_PROT_EXT_CLEAR(Sum := vTrip);
IF homed THEN
  pos := est;
ELSE
  pos := -1.0;
END_IF;
pos := UT_POS_FB_RUN(TNow := fNow, Fitted := fbFit, Value := fbV, Good := fbG, Target := spW, Estimate := pos,
                     Settled := dir = 0 AND NOT homing AND NOT fHold, Supervise := core.CurMode <> UT_MODE_OOS AND NOT Data.simulate,
                     LsOpen := fLsO, LsClosed := fLsC, ResetReq := core.ResetReq, RetryWindow := Data.set.retryWindow,
                     Set := Floating.set.pos, Sts := Floating.sts.pos, St := fbSt, Sum := vTrip,
                     IsOpen => fIsO, IsClosed => fIsC, FbOk => fbOk);
known := homed OR fbOk;

(* hooks for the base *)
vOwnTravel := TRUE;
vPos := pos;
vMoving := dir <> 0 OR fco.InGap;
vConfirmed := fbOk OR fLsO OR fLsC;
vIsOpen := fIsO;
vIsClosed := fIsC;
vAtRest := fIsC;
vPosNow := pos;
vHandOpen := 100.0;
vHandRest := 0.0;
IF Floating.set.safePosition < 0.0 THEN
  vSafePos := -1.0;
  fp := 0.0;
ELSE
  vSafePos := LIMIT(0.0, Floating.set.safePosition, 100.0);
  fp := vSafePos;
END_IF;
vAway := known AND ABS(pos - fp) > 0.5;
fCauses.bothLimits := fLsO AND fLsC;
fCauses.torque := (TorqueOpen AND OpenOut) OR (TorqueClose AND CloseOut);
fCauses.noMovement := capped;
vCauses := fCauses;
vStroke := fStroke;
fStroke := FALSE;
vCfgFault := fFault <> UT_F_NONE;
vCfgHand := FALSE;
vCfgAuto := FALSE;
vCfgWarn := fWarn <> UT_F_NONE;
IF vCfgFault THEN vCfgId := fFault; ELSE vCfgId := fWarn; END_IF;
vStatus := fStatus;
vTime := fTime;

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
      Floating.set.handPos := LIMIT(0.0, core.HandTarget, 100.0);
    ELSIF pos >= 0.0 THEN
      Floating.set.handPos := pos;   (* stop: where it is *)
    END_IF;
  END_IF;
END_IF;

(* where it goes *)
fHold := FALSE;
CASE core.Aim OF
UT_VA_SAFE:
  IF vSafePos < 0.0 THEN fHold := TRUE; ELSE spW := vSafePos; END_IF;
UT_VA_REST:
  IF core.Linked THEN spW := Floating.set.restPos;
  ELSIF ovr = 1 THEN spW := 0.0;
  ELSIF ovr = 2 THEN spW := 100.0;
  ELSE spW := autoSp;
  END_IF;
UT_VA_RUN:
  IF core.Exercising THEN spW := 100.0;
  ELSIF core.Linked THEN
    IF core.RunPos = core.RunPos THEN spW := LIMIT(0.0, core.RunPos, 100.0); ELSE spW := 100.0; END_IF;
  ELSIF ovr = 1 THEN spW := 0.0;
  ELSIF ovr = 2 THEN spW := 100.0;
  ELSE spW := autoSp;
  END_IF;
UT_VA_HAND:
  IF handWired THEN spW := HandSp; ELSE spW := Floating.set.handPos; END_IF;
ELSE
  fHold := TRUE;                 (* OFF / HOLD: stay *)
END_CASE;
IF core.DriveTrip THEN
  fHold := TRUE;                 (* the drive tripped: stop where it is *)
END_IF;
spW := LIMIT(0.0, spW, 100.0);

(* homing: at power-up (homeOnStart) or cmdHome, a full lower and the over-travel *)
IF Floating.cmdHome AND NOT hHome AND core.Aim <> UT_VA_SAFE THEN
  homeAsk := TRUE;
END_IF;
hHome := Floating.cmdHome;
Floating.cmdHome := FALSE;
IF homeAsk AND NOT fHold THEN
  homed := FALSE;
END_IF;
IF NOT known AND NOT fHold AND NOT homing THEN
  homing := TRUE;
  homeAsk := FALSE;
  toEnd := TRUE;
  atEndTime := FALSE;
  est := 100.0;                  (* assume the worst: a full stroke to go *)
  dir := 0;
END_IF;

(* the move *)
IF (fco.QA OR fco.QB) AND NOT outOnPrev THEN
  pulseStart := fNow;            (* the drive actually came on *)
END_IF;
outOnPrev := fco.QA OR fco.QB;
elapsed := T#0s;
IF outOnPrev THEN
  elapsed := fNow - pulseStart;
END_IF;
stopNow := FALSE;
IF fHold THEN
  stopNow := dir <> 0;
  homing := FALSE;
ELSIF dir <> 0 THEN
  IF toEnd THEN
    IF NOT atEndTime AND outOnPrev AND ((dir = 1 AND (est <= 0.0 OR (fbOk AND pos <= Floating.set.pos.closedThreshold)))
                                        OR (dir = 2 AND (est >= 100.0 OR (fbOk AND pos >= Floating.set.pos.openThreshold)))) THEN
      atEndTime := TRUE;
      endSince := fNow;
    END_IF;
    IF (dir = 1 AND fLsC) OR (dir = 2 AND fLsO) OR (atEndTime AND fNow - endSince >= Floating.set.overTravel) THEN
      stopNow := TRUE;
      fStroke := TRUE;
      IF dir = 1 THEN
        est := 0.0;
        synced0 := TRUE;
        homed := TRUE;
        homing := FALSE;
      ELSE
        est := 100.0;
        synced100 := TRUE;
      END_IF;
    ELSIF NOT homing AND ((dir = 1 AND spW > 0.0) OR (dir = 2 AND spW < 100.0))
          AND (elapsed >= Floating.set.minPulse OR core.Aim = UT_VA_SAFE) THEN
      stopNow := TRUE;           (* the request moved off the end *)
    END_IF;
  ELSIF outOnPrev AND (elapsed >= Floating.set.minPulse OR core.Aim = UT_VA_SAFE)
        AND ((dir = 2 AND pos >= spW) OR (dir = 1 AND pos <= spW)) THEN
    stopNow := TRUE;             (* there *)
  END_IF;
  IF elapsed >= Floating.set.strokeTime + Floating.set.overTravel THEN
    stopNow := TRUE;             (* never longer than a full stroke and the over-travel *)
    IF NOT homing AND (NOT toEnd OR NOT atEndTime) THEN
      capped := TRUE;            (* stuck, or the end never came: do not keep driving it *)
      cappedSp := spW;
    END_IF;
    IF homing THEN
      est := 0.0;
      homed := TRUE;
      homing := FALSE;
      synced0 := TRUE;
    END_IF;
  END_IF;
END_IF;
IF stopNow THEN
  dir := 0;
END_IF;

(* a new move: past the deadband, at least a minimum pulse *)
IF capped AND ABS(spW - cappedSp) > Floating.set.pos.deadband THEN
  capped := FALSE;
END_IF;
IF dir = 0 AND NOT fHold AND NOT stopNow THEN
  want := 0;
  IF homing THEN
    want := 1;
  ELSIF spW <= 0.0 AND NOT synced0 AND NOT capped THEN
    want := 1;
    toEnd := TRUE;
  ELSIF spW >= 100.0 AND NOT synced100 AND NOT capped THEN
    want := 2;
    toEnd := TRUE;
  ELSIF spW > 0.0 AND spW < 100.0 AND NOT capped AND pos >= 0.0 THEN
    err := spW - pos;
    dbEff := MAX(Floating.set.pos.deadband, 100.0 * LINT_TO_REAL(dMs) / strokeMs);
    IF ABS(err) > dbEff AND ABS(err) * strokeMs / 100.0 >= LINT_TO_REAL(TIME_TO_LINT(Floating.set.minPulse)) THEN
      toEnd := FALSE;
      IF err > 0.0 THEN want := 2; ELSE want := 1; END_IF;
    END_IF;
  END_IF;
  IF want <> 0 THEN
    dir := want;
    atEndTime := FALSE;
    IF want = 2 THEN synced0 := FALSE; ELSE synced100 := FALSE; END_IF;
  END_IF;
END_IF;
fco(Run := dir <> 0, WantB := dir = 2, FbA := FALSE, FbB := FALSE, UseFb := FALSE, GapAB := Data.set.reversalDelay,
    GapBA := Data.set.reversalDelay, PowerUp := fFirst);
OpenOut := fco.QB;
CloseOut := fco.QA;

(* outputs and status (the base shows the status next scan); the estimate after this scan's move *)
IF NOT fbOk THEN
  IF homed THEN pos := est; ELSE pos := -1.0; END_IF;
  fIsO := fLsO OR (pos >= 0.0 AND pos >= Floating.set.pos.openThreshold);
  fIsC := fLsC OR (pos >= 0.0 AND pos <= Floating.set.pos.closedThreshold);
  IF fLsO AND fLsC THEN
    fIsO := FALSE;
    fIsC := FALSE;
  END_IF;
END_IF;
known := homed OR fbOk;
Position := pos;
IsOpen := fIsO;
IsClosed := fIsC;
Moving := dir <> 0 OR fco.InGap;
fTime := T#0s;
IF homing THEN
  fStatus := UT_ST_HOMING;
ELSIF fco.InGap THEN
  fStatus := UT_ST_DEAD_TIME;
  fTime := fco.TimeLeft;
ELSIF dir = 2 THEN
  fStatus := UT_ST_OPENING;
  fTime := LINT_TO_TIME(REAL_TO_LINT(ABS(spW - pos) * strokeMs / 100.0));
ELSIF dir = 1 THEN
  fStatus := UT_ST_CLOSING;
  fTime := LINT_TO_TIME(REAL_TO_LINT(ABS(spW - pos) * strokeMs / 100.0));
ELSIF NOT known THEN
  fStatus := UT_ST_NOT_HOMED;
ELSIF fIsO THEN
  fStatus := UT_ST_OPEN;
ELSIF fIsC THEN
  fStatus := UT_ST_CLOSED;
ELSE
  fStatus := UT_ST_AT_POSITION;
END_IF;
Floating.sts.notHomed := NOT known;
Floating.sts.demand := spW;
Floating.sts.handPos := Floating.set.handPos;

END_FUNCTION_BLOCK