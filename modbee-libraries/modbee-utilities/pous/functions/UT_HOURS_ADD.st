(* Whole milliseconds of running since the last call, exact: the scan time is
added only when the equipment was running over it, and the part of a
millisecond left is carried, so years of short scans lose nothing. *)

FUNCTION UT_HOURS_ADD : LINT
  VAR_INPUT
    Running : BOOL;
    TNow : TIME;
  END_VAR
  VAR_IN_OUT
    Acc : UT_HOURS_ACC;
  END_VAR
  VAR
    elapsed : TIME;
    ms : LINT;
  END_VAR


ms := 0;
IF Acc.started THEN
  elapsed := TNow - Acc.tPrev;
  IF Acc.runningPrev AND elapsed > T#0s THEN
    Acc.rest := Acc.rest + elapsed;
    ms := TIME_TO_LINT(Acc.rest);
    Acc.rest := Acc.rest - LINT_TO_TIME(ms);
  END_IF;
END_IF;
Acc.started := TRUE;
Acc.tPrev := TNow;
Acc.runningPrev := Running;
UT_HOURS_ADD := ms;

END_FUNCTION