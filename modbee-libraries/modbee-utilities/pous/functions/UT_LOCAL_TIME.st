(* local time: Utc + OffsetMin, plus an hour while daylight saving is in force *)

FUNCTION UT_LOCAL_TIME : DT
  VAR_INPUT
    Utc : DT := DT#1970-01-01-00:00:00; (* the controller clock (UTC), e.g. CURRENT_DT *)
    OffsetMin : INT := 720; (* standard offset, minutes east of UTC (NZ 720) *)
    Dst : UT_DST_RULE := UT_DST_NZ; (* the daylight saving rule *)
  END_VAR
  VAR
    secs : LINT;
  END_VAR


secs := DT_TO_LINT(Utc) + INT_TO_LINT(OffsetMin) * 60;
IF UT_DST_ACTIVE(Utc := Utc, OffsetMin := OffsetMin, Dst := Dst) THEN
  secs := secs + 3600;
END_IF;
IF secs < 0 THEN
  secs := 0;                     (* before 1970: not a DT *)
END_IF;
UT_LOCAL_TIME := LINT_TO_DT(secs);

END_FUNCTION