(* F_Scale — linear scaling: fIn from fInMin..fInMax onto fOutMin..fOutMax (either may run backwards). bClamp: stay
within the output range. A zero / NaN / infinite span returns fOutMin and sets bSpanBad; a NaN fIn gives NaN. The
maths runs in LREAL. *)

FUNCTION F_Scale : REAL
  VAR_INPUT
    fIn : REAL;
    fInMin : REAL := 0.0;
    fInMax : REAL := 65535.0;
    fOutMin : REAL := 0.0;
    fOutMax : REAL := 100.0;
    bClamp : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    bSpanBad : BOOL;
  END_VAR
  VAR
    fSpan : LREAL;
    fPos : LREAL;
  END_VAR


fSpan := REAL_TO_LREAL(fInMax) - REAL_TO_LREAL(fInMin);
bSpanBad := NOT (ABS(fSpan) > LREAL#0.0 AND ABS(fSpan) <= LREAL#1.0E39)
            OR NOT (ABS(REAL_TO_LREAL(fOutMax) - REAL_TO_LREAL(fOutMin)) <= LREAL#1.0E39);
IF NOT (ABS(fSpan) > LREAL#0.0 AND ABS(fSpan) <= LREAL#1.0E39) THEN
  F_Scale := fOutMin;
  RETURN;
END_IF;
fPos := (REAL_TO_LREAL(fIn) - REAL_TO_LREAL(fInMin)) / fSpan;
IF bClamp THEN
  IF fPos < LREAL#0.0 THEN
    fPos := LREAL#0.0;
  ELSIF fPos > LREAL#1.0 THEN
    fPos := LREAL#1.0;
  END_IF;
END_IF;
IF fOutMax = fOutMin THEN
  F_Scale := fOutMin;
  IF NOT (fPos = fPos) THEN
    F_Scale := LREAL_TO_REAL(fPos);
  END_IF;
ELSE
  F_Scale := LREAL_TO_REAL(REAL_TO_LREAL(fOutMin) + fPos * (REAL_TO_LREAL(fOutMax) - REAL_TO_LREAL(fOutMin)));
END_IF;

END_FUNCTION