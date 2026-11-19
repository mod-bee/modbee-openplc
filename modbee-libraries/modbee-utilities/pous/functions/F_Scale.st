(* F_Scale — linear scaling: fIn from fInputLow..fInputHigh onto fOutputLow..fOutputHigh (either may run backwards). bClampToOutput: stay
within the output range. A zero / NaN / infinite span returns fOutputLow and sets bInputSpanBad; a NaN fIn gives NaN. The
maths runs in LREAL. *)

FUNCTION F_Scale : REAL
  VAR_INPUT
    fIn : REAL; (* the value *)
    fInputLow : REAL := 0.0; (* input range, low *)
    fInputHigh : REAL := 65535.0; (* input range, high *)
    fOutputLow : REAL := 0.0; (* output range, low *)
    fOutputHigh : REAL := 100.0; (* output range, high (either range may run backwards) *)
    bClampToOutput : BOOL := TRUE; (* stay within the output range *)
  END_VAR
  VAR_OUTPUT
    bInputSpanBad : BOOL; (* the input span is zero or not a number *)
  END_VAR
  VAR
    fSpan : LREAL;
    fPos : LREAL;
  END_VAR


fSpan := REAL_TO_LREAL(fInputHigh) - REAL_TO_LREAL(fInputLow);
bInputSpanBad := NOT (ABS(fSpan) > LREAL#0.0 AND ABS(fSpan) <= LREAL#1.0E39)
            OR NOT (ABS(REAL_TO_LREAL(fOutputHigh) - REAL_TO_LREAL(fOutputLow)) <= LREAL#1.0E39);
IF NOT (ABS(fSpan) > LREAL#0.0 AND ABS(fSpan) <= LREAL#1.0E39) THEN
  F_Scale := fOutputLow;
  RETURN;
END_IF;
fPos := (REAL_TO_LREAL(fIn) - REAL_TO_LREAL(fInputLow)) / fSpan;
IF bClampToOutput THEN
  IF fPos < LREAL#0.0 THEN
    fPos := LREAL#0.0;
  ELSIF fPos > LREAL#1.0 THEN
    fPos := LREAL#1.0;
  END_IF;
END_IF;
IF fOutputHigh = fOutputLow THEN
  F_Scale := fOutputLow;
  IF NOT (fPos = fPos) THEN
    F_Scale := LREAL_TO_REAL(fPos);
  END_IF;
ELSE
  F_Scale := LREAL_TO_REAL(REAL_TO_LREAL(fOutputLow) + fPos * (REAL_TO_LREAL(fOutputHigh) - REAL_TO_LREAL(fOutputLow)));
END_IF;

END_FUNCTION