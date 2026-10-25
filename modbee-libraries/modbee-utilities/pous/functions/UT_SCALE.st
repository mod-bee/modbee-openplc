(* UT_SCALE — linear scaling, no record.

Maps In from the input range (InMin..InMax) onto the output range
(OutMin..OutMax) in a straight line. Either range may run backwards: swap
OutMin and OutMax to invert the output.

Clamp TRUE   In beyond either end gives that end's output
Clamp FALSE  the line carries on past the ends

A zero input span (InMin = InMax), or a span that is not a number, returns
OutMin and sets SpanBad. A NaN In gives NaN.
An infinite In gives the end value when clamped, and infinity when not.
The maths runs in LREAL so huge ranges do not overflow. *)

FUNCTION UT_SCALE : REAL
  VAR_INPUT
    In : REAL; (* the value to scale *)
    InMin : REAL := 0.0; (* input that gives OutMin *)
    InMax : REAL := 65535.0; (* input that gives OutMax *)
    OutMin : REAL := 0.0;
    OutMax : REAL := 100.0;
    Clamp : BOOL := TRUE; (* TRUE: stay within OutMin..OutMax *)
  END_VAR
  VAR_OUTPUT
    SpanBad : BOOL; (* input or output span zero, NaN or infinite: the result is OutMin *)
  END_VAR
  VAR
    span : LREAL;
    pos : LREAL; (* position along the input range, 0 at InMin, 1 at InMax *)
  END_VAR


span := REAL_TO_LREAL(InMax) - REAL_TO_LREAL(InMin);
SpanBad := NOT (ABS(span) > 0.0 AND ABS(span) <= 1.0E39)
           OR NOT (ABS(REAL_TO_LREAL(OutMax) - REAL_TO_LREAL(OutMin)) <= 1.0E39);
IF NOT (ABS(span) > 0.0 AND ABS(span) <= 1.0E39) THEN
  UT_SCALE := OutMin;
  RETURN;
END_IF;
pos := (REAL_TO_LREAL(In) - REAL_TO_LREAL(InMin)) / span;
IF Clamp THEN
  IF pos < 0.0 THEN
    pos := 0.0;
  ELSIF pos > 1.0 THEN
    pos := 1.0;
  END_IF;
END_IF;
IF OutMax = OutMin THEN
  UT_SCALE := OutMin;          (* a flat output, even for an infinite In *)
  IF NOT (pos = pos) THEN
    UT_SCALE := LREAL_TO_REAL(pos);   (* NaN stays NaN *)
  END_IF;
ELSE
  UT_SCALE := LREAL_TO_REAL(REAL_TO_LREAL(OutMin) + pos * (REAL_TO_LREAL(OutMax) - REAL_TO_LREAL(OutMin)));
END_IF;

END_FUNCTION