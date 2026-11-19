(* FB_ValveFloat EXTENDS FB_ValvePos — a floating (three-point) valve or damper: raise / lower contacts only.
Everything of FB_ValvePos (where it goes, the feedback, the protections, Hand) plus the drive.
Pins added: refFloatingData (its record) -> bOpenOutput (open), bCloseOutput (close): never together, set.tReversingDeadTime between
them (FB_Changeover).
The position is the feedback when good, else estimated from the drive time (set.tFullStrokeTime for a full stroke),
re-synced at the ends by the end switches or by over-travel (set.tExtraDriveAtEnd of extra drive at 0 / 100 %);
homed by a full lower at power-up (set.bHomeAtPowerUp; until then the position is -1, not known) or on bCmdHomeNow.
Moves shorter than set.tShortestMove or inside the deadband are not made; a move never drives longer than a full
stroke and the over-travel (a stuck valve is not kept driving: it waits for a new aim). A hold (Off with
fSafePositionPct < 0, a trip with bHoldWhenTripped) stops where it is. Its settings are kept by the block (a retained
last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_ValveFloat EXTENDS FB_ValvePos
  VAR_INPUT
    refFloatingData : REFERENCE TO ST_ValveFloatData; (* the floating actuator record *)
  END_VAR
  VAR_OUTPUT
    bOpenOutput : BOOL; (* drive open *)
    bCloseOutput : BOOL; (* drive closed (never with bOpenOutput) *)
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


METHOD PRIVATE FloatWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_ValveFloatSet;
  END_VAR
  FloatWhy := E_UtError.None;
  IF NOT (stS.tFullStrokeTime > T#0s) THEN
    FloatWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tShortestMove >= T#0s) THEN
    FloatWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tExtraDriveAtEnd >= T#0s) THEN
    FloatWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tReversingDeadTime >= T#0s) THEN
    FloatWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE FloatOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ValveFloatSet;
  END_VAR
  FloatOk := FloatWhy(stS := stS) = E_UtError.None;
END_METHOD

(* before the valve's scan: the estimate from last scan's drive, the end switches *)
IF __ISVALIDREF(refFloatingData) AND __ISVALIDREF(refData) THEN
  IF bFloatFirst THEN
    IF nKeptFloatLayout = cLayout THEN
      refFloatingData.set := stKeptFloat;
    ELSE
      stKeptFloat := refFloatingData.set;
      nKeptFloatLayout := cLayout;
    END_IF;
    tPrev := TIME();
    bHomed := NOT refFloatingData.set.bHomeAtPowerUp;
  ELSIF FloatOk(stS := refFloatingData.set) THEN
    stKeptFloat := refFloatingData.set;
  ELSIF FloatOk(stS := stKeptFloat) THEN
    refFloatingData.sts.eSettingRefusedErrorId := FloatWhy(stS := refFloatingData.set);
    refFloatingData.set := stKeptFloat;
    refFloatingData.sts.bSettingRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refFloatingData.sts.bSettingRefused := FALSE;
    refFloatingData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  fStrokeMs := LINT_TO_REAL(TIME_TO_LINT(refFloatingData.set.tFullStrokeTime));
  IF fStrokeMs < 1.0 THEN
    fStrokeMs := 1.0;
  END_IF;
  nDMs := TIME_TO_LINT(TIME() - tPrev);
  tPrev := tPrev + LINT_TO_TIME(nDMs);
  IF bOpenOutput THEN
    fEst := fEst + 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs;
  ELSIF bCloseOutput THEN
    fEst := fEst - 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs;
  END_IF;
  fEst := LIMIT(0.0, fEst, 100.0);
  bEndO := refData.set.bOpenLimitSwitchFitted AND bOpenLimitSwitch;
  bEndC := refData.set.bClosedLimitSwitchFitted AND bClosedLimitSwitch;
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

IF NOT __ISVALIDREF(refFloatingData) OR NOT __ISVALIDREF(refData) THEN
  bOpenOutput := FALSE;
  bCloseOutput := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
fSp := LIMIT(0.0, fAim, 100.0);
bHold := bAimHold;

(* homing: at power-up (bHomeAtPowerUp) or bCmdHomeNow, a full lower and the over-travel *)
IF refFloatingData.bCmdHomeNow THEN
  refFloatingData.bCmdHomeNow := FALSE;
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
IF (fbCo.bSideAOutput OR fbCo.bSideBOutput) AND NOT bOutOnPrev THEN
  tPulseStart := tNow;            (* the drive actually came on *)
END_IF;
bOutOnPrev := fbCo.bSideAOutput OR fbCo.bSideBOutput;
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
       AND ((nDir = 1 AND (fEst <= 0.0 OR (bFbOk AND fPositionPct <= refData.set.fClosedAtOrBelowPct)))
            OR (nDir = 2 AND (fEst >= 100.0 OR (bFbOk AND fPositionPct >= refData.set.fOpenAtOrAbovePct)))) THEN
      bAtEndTime := TRUE;
      tEndSince := tNow;
    END_IF;
    IF (nDir = 1 AND bEndC) OR (nDir = 2 AND bEndO)
       OR (bAtEndTime AND tNow - tEndSince >= refFloatingData.set.tExtraDriveAtEnd) THEN
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
          AND tElapsed >= refFloatingData.set.tShortestMove THEN
      bStopNow := TRUE;           (* the aim moved off the end *)
    END_IF;
  ELSIF bOutOnPrev AND tElapsed >= refFloatingData.set.tShortestMove
        AND ((nDir = 2 AND fPositionPct >= fSp) OR (nDir = 1 AND fPositionPct <= fSp)) THEN
    bStopNow := TRUE;             (* there *)
  END_IF;
  IF tElapsed >= refFloatingData.set.tFullStrokeTime + refFloatingData.set.tExtraDriveAtEnd THEN
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
IF bCapped AND ABS(fSp - fCappedSp) > refData.set.fPositionDeadbandPct THEN
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
  ELSIF fSp > 0.0 AND fSp < 100.0 AND NOT bCapped AND fPositionPct >= 0.0 THEN
    fErr := fSp - fPositionPct;
    fDb := MAX(refData.set.fPositionDeadbandPct, 100.0 * LINT_TO_REAL(nDMs) / fStrokeMs);
    IF ABS(fErr) > fDb AND ABS(fErr) * fStrokeMs / 100.0 >= LINT_TO_REAL(TIME_TO_LINT(refFloatingData.set.tShortestMove)) THEN
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
fbCo(bRun := nDir <> 0, bSelectSideB := nDir = 2, bContactorFeedbackFitted := FALSE, tAToBDeadTime := refFloatingData.set.tReversingDeadTime,
     tBToADeadTime := refFloatingData.set.tReversingDeadTime);
bOpenOutput := fbCo.bSideBOutput;
bCloseOutput := fbCo.bSideAOutput;
bFloatFirst := FALSE;
refData.sts.fDemandPct := fSp;
refData.sts.fEstimatedPct := fEstimate;
refData.sts.bTravelling := nDir <> 0 OR fbCo.bPlannedGap;
refFloatingData.sts.bHomed := bHomed;
refFloatingData.sts.bHoming := bHoming;

END_FUNCTION_BLOCK