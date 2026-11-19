(* The site clock is set: a date from 2020 up to 2100 (a board that has not had the time yet starts at 1970). *)

FUNCTION F_ClockOk : BOOL
  VAR_INPUT
    dtClockUtc : DT; (* the controller clock (UTC) *)
  END_VAR

F_ClockOk := dtClockUtc >= DT#2020-01-01-00:00:00 AND dtClockUtc < DT#2100-01-01-00:00:00;

END_FUNCTION