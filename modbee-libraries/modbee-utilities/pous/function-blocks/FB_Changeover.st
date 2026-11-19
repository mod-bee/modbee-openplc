(* FB_Changeover — switch between two contactors A / B that must never be on together (reversing, two-speed, star
-> delta). The motor variants' shared piece; usable on its own.
bRun with bSelectSideB FALSE drives A, with bSelectSideB TRUE drives B. Changing over: the energised side drops first, then
the dead time (tAToBDeadTime from A to B, tBToADeadTime from B to A) runs and, with bContactorFeedbackFitted, the other contactor's aux must have
opened, before the new side closes. bSideAOutput and bSideBOutput are never TRUE together. At the first scan both sides wait one
full gap (the motor may still be turning).
bAuxWrong: with bContactorFeedbackFitted, an aux that does not follow its coil within tAuxFeedbackTimeout (welded, not pulled in): the owner's
changeover protection. bPlannedGap: a planned gap (and tAuxFeedbackTimeout after a side closes), so the owner keeps its
feedback supervision quiet. bStartHeld: the dead time, or the other contactor not open yet. *)

FUNCTION_BLOCK FB_Changeover
  VAR_INPUT
    bRun : BOOL; (* run: side A, or side B with bSelectSideB *)
    bSelectSideB : BOOL; (* FALSE: side A (fwd / low / star), TRUE: side B (rev / high / delta) *)
    bSideAFeedback : BOOL; (* A contactor aux *)
    bSideBFeedback : BOOL; (* B contactor aux *)
    bContactorFeedbackFitted : BOOL; (* supervise the auxes *)
    tAToBDeadTime : TIME; (* dead time A off -> B on *)
    tBToADeadTime : TIME; (* dead time B off -> A on *)
    tAuxFeedbackTimeout : TIME := T#1s; (* a contactor must open / close within this *)
  END_VAR
  VAR_OUTPUT
    bSideAOutput : BOOL; (* contactor A *)
    bSideBOutput : BOOL; (* contactor B (never with A) *)
    bPlannedGap : BOOL; (* a planned gap: the owner keeps feedback supervision quiet *)
    bStartHeld : BOOL; (* dead time, or the other contactor not open yet *)
    bAuxWrong : BOOL; (* an aux wrong for the sequence *)
    bInDeadTime : BOOL; (* waiting out the dead time *)
    bWaitingOtherOpen : BOOL; (* waiting for the other contactor to open *)
    tTimeLeft : TIME; (* gap left *)
  END_VAR
  VAR
    nSide : SINT; (* 0 none, 1 A, 2 B *)
    nLastSide : SINT := 3; (* the side that was on last (3: unknown at power-up) *)
    tOffAt : TIME;
    tOnAt : TIME;
    bStarted : BOOL;
  END_VAR
  VAR_TEMP
    tNow : TIME;
    nTarget : SINT;
    tGap : TIME;
    bOtherOpen : BOOL;
  END_VAR


tNow := TIME();
IF NOT bStarted THEN
  bStarted := TRUE;
  nSide := 0;
  nLastSide := 3;
  tOffAt := tNow;
END_IF;
IF NOT bRun THEN
  nTarget := 0;
ELSIF bSelectSideB THEN
  nTarget := 2;
ELSE
  nTarget := 1;
END_IF;
IF nSide <> 0 AND nSide <> nTarget THEN
  nLastSide := nSide;
  nSide := 0;
  tOffAt := tNow;
END_IF;
bInDeadTime := FALSE;
bWaitingOtherOpen := FALSE;
tTimeLeft := T#0s;
IF nSide = 0 AND nTarget <> 0 THEN
  IF nLastSide = 3 THEN
    tGap := MAX(tAToBDeadTime, tBToADeadTime);
  ELSIF nLastSide = 1 AND nTarget = 2 THEN
    tGap := tAToBDeadTime;
  ELSIF nLastSide = 2 AND nTarget = 1 THEN
    tGap := tBToADeadTime;
  ELSE
    tGap := T#0s;
  END_IF;
  IF nTarget = 1 THEN
    bOtherOpen := NOT bContactorFeedbackFitted OR NOT bSideBFeedback;
  ELSE
    bOtherOpen := NOT bContactorFeedbackFitted OR NOT bSideAFeedback;
  END_IF;
  IF tNow - tOffAt < tGap THEN
    bInDeadTime := TRUE;
    tTimeLeft := tGap - (tNow - tOffAt);
  ELSIF NOT bOtherOpen THEN
    bWaitingOtherOpen := TRUE;
  ELSE
    nSide := nTarget;
    tOnAt := tNow;
    nLastSide := nTarget;
  END_IF;
END_IF;
bSideAOutput := nSide = 1;
bSideBOutput := nSide = 2;
bStartHeld := nSide = 0 AND nTarget <> 0;
bPlannedGap := bStartHeld OR (nSide <> 0 AND tNow - tOnAt < tAuxFeedbackTimeout);
bAuxWrong := FALSE;
IF bContactorFeedbackFitted THEN
  IF bSideAOutput AND NOT bSideAFeedback AND tNow - tOnAt >= tAuxFeedbackTimeout THEN bAuxWrong := TRUE; END_IF;
  IF bSideBOutput AND NOT bSideBFeedback AND tNow - tOnAt >= tAuxFeedbackTimeout THEN bAuxWrong := TRUE; END_IF;
  IF NOT bSideAOutput AND bSideAFeedback AND tNow - tOffAt >= tAuxFeedbackTimeout AND nLastSide <> 3 THEN bAuxWrong := TRUE; END_IF;
  IF NOT bSideBOutput AND bSideBFeedback AND tNow - tOffAt >= tAuxFeedbackTimeout AND nLastSide <> 3 THEN bAuxWrong := TRUE; END_IF;
END_IF;

END_FUNCTION_BLOCK