(* Whole milliseconds of running since the last call, exact: the scan time is added only when the equipment was
running over it, and the part of a millisecond left is carried, so years of short scans lose nothing. *)

FUNCTION F_HoursAdd : LINT
  VAR_INPUT
    bRunning : BOOL;
    tNow : TIME;
  END_VAR
  VAR_IN_OUT
    stAcc : ST_HoursAcc;
  END_VAR
  VAR
    tElapsed : TIME;
    nMs : LINT;
  END_VAR


nMs := 0;
IF stAcc.bStarted THEN
  tElapsed := tNow - stAcc.tPrev;
  IF stAcc.bRunningPrev AND tElapsed > T#0s THEN
    stAcc.tRest := stAcc.tRest + tElapsed;
    nMs := TIME_TO_LINT(stAcc.tRest);
    stAcc.tRest := stAcc.tRest - LINT_TO_TIME(nMs);
  END_IF;
END_IF;
stAcc.bStarted := TRUE;
stAcc.tPrev := tNow;
stAcc.bRunningPrev := bRunning;
F_HoursAdd := nMs;

END_FUNCTION