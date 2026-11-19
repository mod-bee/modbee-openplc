(* F_Countdown — time remaining on any timer (TON / TOF / TP / FB_Tonr): tPresetTime - tElapsedTime, never negative, never more than tPresetTime. *)

FUNCTION F_Countdown : TIME
  VAR_INPUT
    tPresetTime : TIME := T#0s; (* the timer's preset (MyTon.PT) *)
    tElapsedTime : TIME := T#0s; (* its elapsed time (MyTon.ET) *)
  END_VAR

IF tPresetTime <= T#0s OR tElapsedTime >= tPresetTime THEN
  F_Countdown := T#0s;
ELSIF tElapsedTime <= T#0s THEN
  F_Countdown := tPresetTime;
ELSE
  F_Countdown := tPresetTime - tElapsedTime;
END_IF;

END_FUNCTION