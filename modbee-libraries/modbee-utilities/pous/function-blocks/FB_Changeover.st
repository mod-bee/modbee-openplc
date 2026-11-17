(* FB_Changeover — switch between two contactors A / B that must never be on together (reversing, two-speed, star
-> delta) (src-v2 UT_CHANGEOVER_RUN). The motor variants' shared piece; usable on its own.
bRun with bWantB FALSE drives A, with bWantB TRUE drives B. Changing over: the energised side drops first, then
the dead time (tGapAB from A to B, tGapBA from B to A) runs and, with bUseFb, the other contactor's aux must have
opened, before the new side closes. bQA and bQB are never TRUE together. At the first scan both sides wait one
full gap (the motor may still be turning).
bCause: with bUseFb, an aux that does not follow its coil within tOpenTime (welded, not pulled in): the owner's
changeover protection. bInGap: a planned gap (and tOpenTime after a side closes), so the owner keeps its
feedback supervision quiet. bStartBlock: the dead time, or the other contactor not open yet. *)

FUNCTION_BLOCK FB_Changeover
  VAR_INPUT
    bRun : BOOL;
    bWantB : BOOL; (* FALSE: side A (fwd / low / star), TRUE: side B (rev / high / delta) *)
    bFbA : BOOL; (* A contactor aux *)
    bFbB : BOOL; (* B contactor aux *)
    bUseFb : BOOL; (* supervise the auxes *)
    tGapAB : TIME; (* dead time A off -> B on *)
    tGapBA : TIME; (* dead time B off -> A on *)
    tOpenTime : TIME := T#1s; (* a contactor must open / close within this *)
  END_VAR
  VAR_OUTPUT
    bQA : BOOL;
    bQB : BOOL;
    bInGap : BOOL; (* a planned gap: the owner keeps feedback supervision quiet *)
    bStartBlock : BOOL; (* dead time, or the other contactor not open yet *)
    bCause : BOOL; (* an aux wrong for the sequence *)
    bDeadTime : BOOL; (* waiting out the dead time *)
    bWaitOpen : BOOL; (* waiting for the other contactor to open *)
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
ELSIF bWantB THEN
  nTarget := 2;
ELSE
  nTarget := 1;
END_IF;
IF nSide <> 0 AND nSide <> nTarget THEN
  nLastSide := nSide;
  nSide := 0;
  tOffAt := tNow;
END_IF;
bDeadTime := FALSE;
bWaitOpen := FALSE;
tTimeLeft := T#0s;
IF nSide = 0 AND nTarget <> 0 THEN
  IF nLastSide = 3 THEN
    tGap := MAX(tGapAB, tGapBA);
  ELSIF nLastSide = 1 AND nTarget = 2 THEN
    tGap := tGapAB;
  ELSIF nLastSide = 2 AND nTarget = 1 THEN
    tGap := tGapBA;
  ELSE
    tGap := T#0s;
  END_IF;
  IF nTarget = 1 THEN
    bOtherOpen := NOT bUseFb OR NOT bFbB;
  ELSE
    bOtherOpen := NOT bUseFb OR NOT bFbA;
  END_IF;
  IF tNow - tOffAt < tGap THEN
    bDeadTime := TRUE;
    tTimeLeft := tGap - (tNow - tOffAt);
  ELSIF NOT bOtherOpen THEN
    bWaitOpen := TRUE;
  ELSE
    nSide := nTarget;
    tOnAt := tNow;
    nLastSide := nTarget;
  END_IF;
END_IF;
bQA := nSide = 1;
bQB := nSide = 2;
bStartBlock := nSide = 0 AND nTarget <> 0;
bInGap := bStartBlock OR (nSide <> 0 AND tNow - tOnAt < tOpenTime);
bCause := FALSE;
IF bUseFb THEN
  IF bQA AND NOT bFbA AND tNow - tOnAt >= tOpenTime THEN bCause := TRUE; END_IF;
  IF bQB AND NOT bFbB AND tNow - tOnAt >= tOpenTime THEN bCause := TRUE; END_IF;
  IF NOT bQA AND bFbA AND tNow - tOffAt >= tOpenTime AND nLastSide <> 3 THEN bCause := TRUE; END_IF;
  IF NOT bQB AND bFbB AND tNow - tOffAt >= tOpenTime AND nLastSide <> 3 THEN bCause := TRUE; END_IF;
END_IF;

END_FUNCTION_BLOCK