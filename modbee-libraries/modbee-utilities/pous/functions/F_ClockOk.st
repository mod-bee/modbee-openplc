(* The site clock is set: a date from 2020 up to 2100 (a board that has not had the time yet starts at 1970). *)

FUNCTION F_ClockOk : BOOL
  VAR_INPUT
    dtUtc : DT;
  END_VAR

F_ClockOk := dtUtc >= DT#2020-01-01-00:00:00 AND dtUtc < DT#2100-01-01-00:00:00;

END_FUNCTION