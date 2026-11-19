(* F_TimeBuild — days, hours, minutes, seconds and milliseconds to a TIME
(function).

Lets an HMI enter a delay as separate numbers (e.g. 2 h 30 min) and gives a
TIME. The parts are simply added, so they may exceed their natural range
(90 minutes is fine). A total beyond the largest TIME
(T#106751d23h47m16s854ms775us807ns) gives the largest TIME. *)

FUNCTION F_TimeBuild : TIME
  VAR_INPUT
    nDays : UDINT := 0; (* days *)
    nHours : UDINT := 0; (* hours *)
    nMinutes : UDINT := 0; (* minutes *)
    nSeconds : UDINT := 0; (* seconds *)
    nMilliseconds : UDINT := 0; (* milliseconds *)
  END_VAR
  VAR
    nMs : LINT; (* the total in milliseconds (cannot overflow) *)
  END_VAR


nMs := UDINT_TO_LINT(nDays) * 86400000
    + UDINT_TO_LINT(nHours) * 3600000
    + UDINT_TO_LINT(nMinutes) * 60000
    + UDINT_TO_LINT(nSeconds) * 1000
    + UDINT_TO_LINT(nMilliseconds);
IF nMs > 9223372036854 THEN
  F_TimeBuild := T#1d * 106751 + T#23h47m16s854ms775us807ns;
ELSE
  F_TimeBuild := LINT_TO_TIME(nMs);
END_IF;

END_FUNCTION