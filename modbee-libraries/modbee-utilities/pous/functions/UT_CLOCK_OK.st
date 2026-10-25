(* The site clock is set: a date from 2020 up to 2100 (a board that has not
had the time yet starts at 1970). *)

FUNCTION UT_CLOCK_OK : BOOL
  VAR_INPUT
    Utc : DT;
  END_VAR

UT_CLOCK_OK := Utc >= DT#2020-01-01-00:00:00 AND Utc < DT#2100-01-01-00:00:00;

END_FUNCTION