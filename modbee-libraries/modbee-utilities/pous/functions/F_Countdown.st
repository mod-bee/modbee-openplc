(* F_Countdown — time remaining on any timer (TON / TOF / TP / FB_Tonr): tPT - tET, never negative, never more than tPT. *)

FUNCTION F_Countdown : TIME
  VAR_INPUT
    tPT : TIME := T#0s; (* the timer's preset (MyTon.PT) *)
    tET : TIME := T#0s; (* its elapsed time (MyTon.ET) *)
  END_VAR

IF tPT <= T#0s OR tET >= tPT THEN
  F_Countdown := T#0s;
ELSIF tET <= T#0s THEN
  F_Countdown := tPT;
ELSE
  F_Countdown := tPT - tET;
END_IF;

END_FUNCTION