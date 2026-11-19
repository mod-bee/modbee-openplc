(* local time: dtClockUtc + nUtcOffsetMinutes, plus an hour while daylight saving is in force *)

FUNCTION F_LocalTime : DT
  VAR_INPUT
    dtClockUtc : DT := DT#1970-01-01-00:00:00; (* the controller clock (UTC), e.g. CURRENT_DT *)
    nUtcOffsetMinutes : INT := 720; (* standard offset, minutes east of UTC (NZ 720) *)
    eDaylightSavingRule : E_DstRule := E_DstRule.Nz; (* the daylight saving rule *)
  END_VAR
  VAR
    nSecs : LINT;
  END_VAR


nSecs := DT_TO_LINT(dtClockUtc) + INT_TO_LINT(nUtcOffsetMinutes) * 60;
IF F_DstActive(dtClockUtc := dtClockUtc, nUtcOffsetMinutes := nUtcOffsetMinutes, eDaylightSavingRule := eDaylightSavingRule) THEN
  nSecs := nSecs + 3600;
END_IF;
IF nSecs < 0 THEN
  nSecs := 0;                     (* before 1970: not a DT *)
END_IF;
F_LocalTime := LINT_TO_DT(nSecs);

END_FUNCTION