(* UT_TIME_BUILD — days, hours, minutes, seconds and milliseconds to a TIME
(function).

Lets an HMI enter a delay as separate numbers (e.g. 2 h 30 min) and gives a
TIME. The parts are simply added, so they may exceed their natural range
(90 minutes is fine). A total beyond the largest TIME
(T#106751d23h47m16s854ms775us807ns) gives the largest TIME. *)

FUNCTION UT_TIME_BUILD : TIME
  VAR_INPUT
    Days : UDINT := 0;
    Hours : UDINT := 0;
    Minutes : UDINT := 0;
    Seconds : UDINT := 0;
    Millis : UDINT := 0;
  END_VAR
  VAR
    ms : LINT; (* the total in milliseconds (cannot overflow) *)
  END_VAR


ms := UDINT_TO_LINT(Days) * 86400000
    + UDINT_TO_LINT(Hours) * 3600000
    + UDINT_TO_LINT(Minutes) * 60000
    + UDINT_TO_LINT(Seconds) * 1000
    + UDINT_TO_LINT(Millis);
IF ms > 9223372036854 THEN
  UT_TIME_BUILD := T#1d * 106751 + T#23h47m16s854ms775us807ns;
ELSE
  UT_TIME_BUILD := LINT_TO_TIME(ms);
END_IF;

END_FUNCTION