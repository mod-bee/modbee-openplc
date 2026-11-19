(* Whole milliseconds of running since the last call, exact: the scan time is added only when the equipment was
running over it, and the part of a millisecond left is carried, so years of short scans lose nothing. *)

FUNCTION F_HoursAdd : LINT
  VAR_INPUT
    bRunning : BOOL; (* it runs *)
    tNow : TIME; (* TIME() of this scan *)
  END_VAR
  VAR_IN_OUT
    stAccumulator : ST_HoursAcc; (* your accumulator (one per counter) *)
  END_VAR
  VAR
    tElapsed : TIME;
    nMs : LINT;
  END_VAR


nMs := 0;
IF stAccumulator.bStarted THEN
  tElapsed := tNow - stAccumulator.tLastScanAt;
  IF stAccumulator.bRunningLastScan AND tElapsed > T#0s THEN
    stAccumulator.tUncountedRemainder := stAccumulator.tUncountedRemainder + tElapsed;
    nMs := TIME_TO_LINT(stAccumulator.tUncountedRemainder);
    stAccumulator.tUncountedRemainder := stAccumulator.tUncountedRemainder - LINT_TO_TIME(nMs);
  END_IF;
END_IF;
stAccumulator.bStarted := TRUE;
stAccumulator.tLastScanAt := tNow;
stAccumulator.bRunningLastScan := bRunning;
F_HoursAdd := nMs;

END_FUNCTION