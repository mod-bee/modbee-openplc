(* FB_ValveFloat EXTENDS FB_ValvePos — a floating (three-point) valve or damper: raise / lower contacts only.
Everything of FB_ValvePos (where it goes, the feedback, the protections, Hand) plus the drive.
Pins added: refFloat (its record) -> bRaiseOut (open), bLowerOut (close): never together, set.tReversal between
them (FB_Changeover).
The position is the feedback when good, else estimated from the drive time (set.tStroke for a full stroke),
re-synced at the ends by the end switches or by over-travel (set.tOverTravel of extra drive at 0 / 100 %);
homed by a full lower at power-up (set.bHomeOnStart; until then the position is -1, not known) or on bCmdHome.
Moves shorter than set.tMinPulse or inside the deadband are not made; a move never drives longer than a full
stroke and the over-travel (a stuck valve is not kept driving: it waits for a new aim). A hold (Off with
fSafePos < 0, a trip with bHoldOnFault) stops where it is. Its settings are kept by the block (a retained
last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveFloat EXTENDS FB_ValvePos
  VAR_INPUT
    refFloat : REFERENCE TO ST_ValveFloatData;
  END_VAR
  VAR_OUTPUT
    bRaiseOut : BOOL; (* drive open *)
    bLowerOut : BOOL; (* drive closed (never with bRaiseOut) *)
  END_VAR
  VAR RETAIN
    stKeptFloat : ST_ValveFloatSet;
    nKeptFloatLayout : UINT;
  END_VAR
  VAR
    fbCo : FB_Changeover;
    bFloatFirst : BOOL := TRUE;
    tPrev : TIME;
    fEst : REAL; (* the estimate from the drive time, % *)
    bHomed : BOOL;
    bHoming : BOOL;
    bHomeAsk : BOOL;
    nDir : SINT; (* 0 stopped, 1 lower, 2 raise *)
    bToEnd : BOOL; (* driving to an end (re-sync) *)
    bAtEndTime : BOOL;
    tEndSince : TIME;
    bSynced0 : BOOL;
    bSynced100 : BOOL;
    bOutOnPrev : BOOL;
    tPulseStart : TIME;
    bCapped : BOOL; (* a move ran its longest: wait for a new aim *)
    fCappedSp : REAL;
  END_VAR
  VAR_TEMP
    nDMs : LINT;
    fStrokeMs : REAL;
    fSp : REAL;
    bHold : BOOL;
    bStopNow : BOOL;
    tElapsed : TIME;
    nWant : SINT;
    fErr : REAL;
    fDb : REAL;
    bEndO : BOOL;
    bEndC : BOOL;
  END_VAR


METHOD PRIVATE FloatOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ValveFloatSet;
  END_VAR
  FloatOk := stS.tStroke > T#0s AND stS.tMinPulse >= T#0s AND stS.tOverTravel >= T#0s AND stS.tReversal >= T#0s;
END_METHOD

(* before the valve's scan: the estimate from last scan's drive, the end switches *)
IF __ISVALIDREF(refFloat) AND __ISVALIDREF(refData) THEN
  IF bFloatFirst THEN
    IF nKeptFloatLayout = cLayout THEN
      refFloat.set := stKeptFloat;
    ELSE
      stKeptFloat := refFloat.set;
      nKeptFloatLayout := cLayout;
    END_IF;
    tPrev := TIME();
    bHomed := NOT refFloat.set.bHomeOnStart;
  ELSIF FloatOk(stS := refFloat.set) THEN
    stKeptFloat := refFloat.set;
  ELSIF FloatOk(stS := stKeptFloat) THEN
    refFloat.set := stKeptFloat;
    refFloat.sts.bRefused := TRUE;
  END_IF;
  fStrokeMs := LINT_TO_REAL(TIME_TO_LINT(refFloat.set.tStroke));
  IF fStrokeMs < 1.0 THEN
    fStrokeMs := 1.0;
  END_IF;
  nDMs := TIME_TO_LINT(TIME() - tPrev);
  tPrev := tPrev + LINT_TO_TIME(nDMs);
  IF bRaiseOut THEN
    fEst := fEst + 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs;
  ELSIF bLowerOut THEN
    fEst := fEst - 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs;
  END_IF;
  fEst := LIMIT(0.0, fEst, 100.0);
  bEndO := refData.set.bUseOpenLs AND bOpenLs;
  bEndC := refData.set.bUseClosedLs AND bClosedLs;
  IF bEndC AND NOT bEndO THEN
    fEst := 0.0;                  (* an end switch re-syncs *)
    bHomed := TRUE;
  ELSIF bEndO AND NOT bEndC THEN
    fEst := 100.0;
  END_IF;
  IF bHomed THEN
    fEstimate := fEst;
  ELSE
    fEstimate := -1.0;            (* not known until homed *)
  END_IF;
  bSettled := nDir = 0 AND NOT bHoming;
  fDemand := fAim;
END_IF;

SUPER^();                         // the valve: modes, the aim, the feedback, protections

IF NOT __ISVALIDREF(refFloat) OR NOT __ISVALIDREF(refData) THEN
  bRaiseOut := FALSE;
  bLowerOut := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
fSp := LIMIT(0.0, fAim, 100.0);
bHold := bAimHold;

(* homing: at power-up (bHomeOnStart) or bCmdHome, a full lower and the over-travel *)
IF refFloat.bCmdHome THEN
  refFloat.bCmdHome := FALSE;
  bHomeAsk := TRUE;
END_IF;
IF bHomeAsk AND NOT bHold THEN
  bHomed := FALSE;
END_IF;
IF NOT bHomed AND NOT bFbOk AND NOT bHold AND NOT bHoming THEN
  bHoming := TRUE;
  bHomeAsk := FALSE;
  bToEnd := TRUE;
  bAtEndTime := FALSE;
  fEst := 100.0;                  (* assume the worst: a full stroke to go *)
  nDir := 0;
END_IF;

(* the move *)
IF (fbCo.bQA OR fbCo.bQB) AND NOT bOutOnPrev THEN
  tPulseStart := tNow;            (* the drive actually came on *)
END_IF;
bOutOnPrev := fbCo.bQA OR fbCo.bQB;
tElapsed := T#0s;
IF bOutOnPrev THEN
  tElapsed := tNow - tPulseStart;
END_IF;
bStopNow := FALSE;
IF bHold THEN
  bStopNow := nDir <> 0;
  bHoming := FALSE;
ELSIF nDir <> 0 THEN
  IF bToEnd THEN
    IF NOT bAtEndTime AND bOutOnPrev
       AND ((nDir = 1 AND (fEst <= 0.0 OR (bFbOk AND fPosition <= refData.set.fClosedThreshold)))
            OR (nDir = 2 AND (fEst >= 100.0 OR (bFbOk AND fPosition >= refData.set.fOpenThreshold)))) THEN
      bAtEndTime := TRUE;
      tEndSince := tNow;
    END_IF;
    IF (nDir = 1 AND bEndC) OR (nDir = 2 AND bEndO)
       OR (bAtEndTime AND tNow - tEndSince >= refFloat.set.tOverTravel) THEN
      bStopNow := TRUE;
      IF nDir = 1 THEN
        fEst := 0.0;
        bSynced0 := TRUE;
        bHomed := TRUE;
        bHoming := FALSE;
      ELSE
        fEst := 100.0;
        bSynced100 := TRUE;
      END_IF;
    ELSIF NOT bHoming AND ((nDir = 1 AND fSp > 0.0) OR (nDir = 2 AND fSp < 100.0))
          AND tElapsed >= refFloat.set.tMinPulse THEN
      bStopNow := TRUE;           (* the aim moved off the end *)
    END_IF;
  ELSIF bOutOnPrev AND tElapsed >= refFloat.set.tMinPulse
        AND ((nDir = 2 AND fPosition >= fSp) OR (nDir = 1 AND fPosition <= fSp)) THEN
    bStopNow := TRUE;             (* there *)
  END_IF;
  IF tElapsed >= refFloat.set.tStroke + refFloat.set.tOverTravel THEN
    bStopNow := TRUE;             (* never longer than a full stroke and the over-travel *)
    IF NOT bHoming AND (NOT bToEnd OR NOT bAtEndTime) THEN
      bCapped := TRUE;            (* stuck, or the end never came: do not keep driving it *)
      fCappedSp := fSp;
    END_IF;
    IF bHoming THEN
      fEst := 0.0;
      bHomed := TRUE;
      bHoming := FALSE;
      bSynced0 := TRUE;
    END_IF;
  END_IF;
END_IF;
IF bStopNow THEN
  nDir := 0;
END_IF;

(* a new move: past the deadband, at least a minimum pulse *)
IF bCapped AND ABS(fSp - fCappedSp) > refData.set.fDeadband THEN
  bCapped := FALSE;
END_IF;
IF nDir = 0 AND NOT bHold AND NOT bStopNow THEN
  nWant := 0;
  IF bHoming THEN
    nWant := 1;
  ELSIF fSp <= 0.0 AND NOT bSynced0 AND NOT bCapped THEN
    nWant := 1;
    bToEnd := TRUE;
  ELSIF fSp >= 100.0 AND NOT bSynced100 AND NOT bCapped THEN
    nWant := 2;
    bToEnd := TRUE;
  ELSIF fSp > 0.0 AND fSp < 100.0 AND NOT bCapped AND fPosition >= 0.0 THEN
    fErr := fSp - fPosition;
    fDb := MAX(refData.set.fDeadband, 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs);
    IF ABS(fErr) > fDb AND ABS(fErr) * fStrokeMs / 100.0 >= LINT_TO_REAL(TIME_TO_LINT(refFloat.set.tMinPulse)) THEN
      bToEnd := FALSE;
      IF fErr > 0.0 THEN nWant := 2; ELSE nWant := 1; END_IF;
    END_IF;
  END_IF;
  IF nWant <> 0 THEN
    nDir := nWant;
    bAtEndTime := FALSE;
    IF nWant = 2 THEN bSynced0 := FALSE; ELSE bSynced100 := FALSE; END_IF;
  END_IF;
END_IF;
fbCo(bRun := nDir <> 0, bWantB := nDir = 2, bUseFb := FALSE, tGapAB := refFloat.set.tReversal,
     tGapBA := refFloat.set.tReversal);
bRaiseOut := fbCo.bQB;
bLowerOut := fbCo.bQA;
bFloatFirst := FALSE;
refData.sts.fDemand := fSp;
refData.sts.fEstimate := fEstimate;
refData.sts.bMoving := nDir <> 0 OR fbCo.bInGap;
refFloat.sts.bHomed := bHomed;
refFloat.sts.bHoming := bHoming;

END_FUNCTION_BLOCK