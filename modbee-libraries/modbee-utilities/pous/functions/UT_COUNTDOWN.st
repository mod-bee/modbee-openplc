(* UT_COUNTDOWN — time remaining on a timer (function).

Works with any timer: the standard TON / TOF / TP, or UT_TONR. Typical use
is showing "time left" on an HMI:

Remaining := UT_COUNTDOWN(PT := Delay.PT, ET := Delay.ET);

Returns PT - ET, never negative and never more than PT. A negative ET
counts as 0; a PT of 0 or less gives 0. *)

FUNCTION UT_COUNTDOWN : TIME
  VAR_INPUT
    PT : TIME := T#0s; (* timer preset (MyTon.PT) *)
    ET : TIME := T#0s; (* timer elapsed (MyTon.ET) *)
  END_VAR

IF PT <= T#0s OR ET >= PT THEN
  UT_COUNTDOWN := T#0s;
ELSIF ET <= T#0s THEN
  UT_COUNTDOWN := PT;
ELSE
  UT_COUNTDOWN := PT - ET;
END_IF;

END_FUNCTION