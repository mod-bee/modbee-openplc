(* UT_CHANGEOVER_RUN — switch between two contactors A / B that must never be on
together (reversing, two-speed, star -> delta). Private shared piece.

Run with WantB FALSE drives A, with WantB TRUE drives B. Changing over: the
energised side drops first, then the dead time (GapAB from A to B, GapBA from
B to A) runs and, with UseFb, the other contactor's aux must have opened,
before the new side closes. QA and QB are never TRUE together. At power-up
both sides wait one full gap (the motor may still be turning).

Cause: with UseFb, an aux that does not follow its coil within OpenTime
(welded, not pulled in) - the owner's changeover protection. *)

FUNCTION_BLOCK UT_CHANGEOVER_RUN
  VAR_INPUT
    Run : BOOL;
    WantB : BOOL; (* FALSE: side A (fwd / low / star), TRUE: side B (rev / high / delta) *)
    FbA : BOOL; (* A contactor aux *)
    FbB : BOOL; (* B contactor aux *)
    UseFb : BOOL; (* supervise the auxes *)
    GapAB : TIME; (* dead time A off -> B on *)
    GapBA : TIME; (* dead time B off -> A on *)
    OpenTime : TIME := T#1s; (* a contactor must open / close within this *)
    PowerUp : BOOL; (* first scan: both sides wait one gap *)
  END_VAR
  VAR_OUTPUT
    QA : BOOL;
    QB : BOOL;
    InGap : BOOL; (* a planned gap: the owner keeps feedback supervision quiet *)
    StartBlock : BOOL; (* dead time, or the other contactor not open yet *)
    Cause : BOOL; (* an aux wrong for the sequence *)
    Waiting : UT_STATUS; (* UT_ST_DEAD_TIME / UT_ST_WAIT_OPEN / UT_ST_IDLE *)
    TimeLeft : TIME; (* gap left *)
  END_VAR
  VAR
    side : SINT; (* 0 none, 1 A, 2 B *)
    lastSide : SINT; (* the side that was on last (3: unknown at power-up) *)
    target : SINT;
    offAt : TIME;
    onAt : TIME;
    gap : TIME;
    now : TIME;
    otherOpen : BOOL;
  END_VAR


now := TIME();
IF PowerUp THEN
  side := 0;
  lastSide := 3;
  offAt := now;
END_IF;
IF NOT Run THEN
  target := 0;
ELSIF WantB THEN
  target := 2;
ELSE
  target := 1;
END_IF;
IF side <> 0 AND side <> target THEN
  lastSide := side;
  side := 0;
  offAt := now;
END_IF;
Waiting := UT_ST_IDLE;
TimeLeft := T#0s;
IF side = 0 AND target <> 0 THEN
  IF lastSide = 3 THEN
    IF GapAB > GapBA THEN gap := GapAB; ELSE gap := GapBA; END_IF;
  ELSIF lastSide = 1 AND target = 2 THEN
    gap := GapAB;
  ELSIF lastSide = 2 AND target = 1 THEN
    gap := GapBA;
  ELSE
    gap := T#0s;
  END_IF;
  IF target = 1 THEN
    otherOpen := NOT UseFb OR NOT FbB;
  ELSE
    otherOpen := NOT UseFb OR NOT FbA;
  END_IF;
  IF now - offAt < gap THEN
    Waiting := UT_ST_DEAD_TIME;
    TimeLeft := gap - (now - offAt);
  ELSIF NOT otherOpen THEN
    Waiting := UT_ST_WAIT_OPEN;
  ELSE
    side := target;
    onAt := now;
    lastSide := target;
  END_IF;
END_IF;
QA := side = 1;
QB := side = 2;
StartBlock := side = 0 AND target <> 0;
InGap := StartBlock OR (side <> 0 AND now - onAt < OpenTime);
Cause := FALSE;
IF UseFb THEN
  IF QA AND NOT FbA AND now - onAt >= OpenTime THEN Cause := TRUE; END_IF;
  IF QB AND NOT FbB AND now - onAt >= OpenTime THEN Cause := TRUE; END_IF;
  IF NOT QA AND FbA AND now - offAt >= OpenTime AND lastSide <> 3 THEN Cause := TRUE; END_IF;
  IF NOT QB AND FbB AND now - offAt >= OpenTime AND lastSide <> 3 THEN Cause := TRUE; END_IF;
END_IF;

END_FUNCTION_BLOCK