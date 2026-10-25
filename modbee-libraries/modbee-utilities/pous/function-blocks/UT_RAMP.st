(* UT_RAMP — rate-limited setpoint.

Out moves toward In at RateUp (rising) or RateDown (falling), in units per
RateUnit (second by default; minute, hour or day), and stops exactly on In
(no overshoot). A rate of 0, or infinity,
means no limit: Out jumps. The sign of a rate is ignored.

Out starts at 0 after a restart and ramps to In. Track makes Out follow In
at once (for example while the drive is stopped), and the ramp carries on
from there when Track goes FALSE.

Time is measured from TIME() differences in whole milliseconds; the part of a
millisecond left over is carried to the next scan, so the rate is exact at
any task interval.

A value that is not a number (In NaN or infinite, a rate NaN) holds Out where
it is and sets BadInput; the time it lasted does not count, so Out does not
catch up with a jump afterwards. *)

FUNCTION_BLOCK UT_RAMP
  VAR_INPUT
    In : REAL; (* target *)
    RateUp : REAL := 10.0; (* units per RateUnit rising (0 = jump) *)
    RateDown : REAL := 10.0; (* units per RateUnit falling (0 = jump) *)
    RateUnit : UT_RATE_UNIT := UT_PER_SEC; (* the rates are per second, minute, hour or day *)
    Track : BOOL; (* Out follows In at once *)
  END_VAR
  VAR_OUTPUT
    Out : REAL;
    Ramping : BOOL; (* Out is still moving toward In *)
    BadInput : BOOL; (* In or a rate is not a number: Out is held *)
  END_VAR
  VAR
    started : BOOL;
    tPrev : TIME; (* time counted up to *)
    y : LREAL; (* the output, kept in LREAL so slow rates add up exactly *)
    x : LREAL;
    rateAbs : LREAL;
    dMs : LINT;
    dtS : LREAL;
    perS : LREAL; (* seconds per RateUnit *)
  END_VAR


BadInput := NOT (In = In) OR In > 3.4E38 OR In < -3.4E38
            OR NOT (RateUp = RateUp) OR NOT (RateDown = RateDown);
x := REAL_TO_LREAL(In);

IF NOT started OR BadInput THEN
  tPrev := TIME();               (* nothing to catch up on *)
  started := TRUE;
ELSE
  dMs := TIME_TO_LINT(TIME() - tPrev);         (* whole ms elapsed *)
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);        (* the part of a ms left over carries on *)
    CASE RateUnit OF
    UT_PER_MIN: perS := 60.0;
    UT_PER_HOUR: perS := 3600.0;
    UT_PER_DAY: perS := 86400.0;
    ELSE
      perS := 1.0;
    END_CASE;
    dtS := LINT_TO_LREAL(dMs) / 1000.0 / perS;
    IF x > y THEN
      rateAbs := ABS(REAL_TO_LREAL(RateUp));
      IF rateAbs = 0.0 THEN
        y := x;
      ELSE
        y := MIN(x, y + rateAbs * dtS);
      END_IF;
    ELSIF x < y THEN
      rateAbs := ABS(REAL_TO_LREAL(RateDown));
      IF rateAbs = 0.0 THEN
        y := x;
      ELSE
        y := MAX(x, y - rateAbs * dtS);
      END_IF;
    END_IF;
  END_IF;
END_IF;

IF Track AND NOT BadInput THEN
  y := x;
END_IF;
Out := LREAL_TO_REAL(y);
Ramping := NOT BadInput AND y <> x;

END_FUNCTION_BLOCK