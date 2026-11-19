(* FB_Ramp — rate-limited setpoint.

fOut moves toward fSetpoint at fRampUpRate (rising) or fRampDownRate (falling), in units per
eRateUnit (second by default; minute, hour or day), and stops exactly on fSetpoint
(no overshoot). A rate of 0, or infinity,
means no limit: fOut jumps. The sign of a rate is ignored.

fOut starts at 0 after a restart and ramps to fSetpoint. bFollowAtOnce makes fOut follow fSetpoint
at once (for example while the drive is stopped), and the ramp carries on
from there when bFollowAtOnce goes FALSE.

Time is measured from TIME() differences in whole milliseconds; the part of a
millisecond left over is carried to the next scan, so the rate is exact at
any task interval.

A value that is not a number (fSetpoint NaN or infinite, a rate NaN) holds fOut where
it is and sets bInputNotANumber; the time it lasted does not count, so fOut does not
catch up with a jump afterwards. *)

FUNCTION_BLOCK FB_Ramp
  VAR_INPUT
    fSetpoint : REAL; (* target *)
    fRampUpRate : REAL := 10.0; (* units per eRateUnit rising (0 = jump) *)
    fRampDownRate : REAL := 10.0; (* units per eRateUnit falling (0 = jump) *)
    eRateUnit : E_RateUnit := E_RateUnit.PerSec; (* the rates are per second, minute, hour or day *)
    bFollowAtOnce : BOOL; (* fOut follows fSetpoint at once *)
  END_VAR
  VAR_OUTPUT
    fOut : REAL; (* the ramped value *)
    bRamping : BOOL; (* fOut is still moving toward fSetpoint *)
    bInputNotANumber : BOOL; (* fSetpoint or a rate is not a number: fOut is held *)
  END_VAR
  VAR
    bStarted : BOOL;
    tPrev : TIME; (* time counted up to *)
    fY : LREAL; (* the output, kept in LREAL so slow rates add up exactly *)
    fX : LREAL;
    fRateAbs : LREAL;
    dMs : LINT;
    dtS : LREAL;
    fPerS : LREAL; (* seconds per eRateUnit *)
  END_VAR


bInputNotANumber := NOT (fSetpoint = fSetpoint) OR fSetpoint > 3.4E38 OR fSetpoint < -3.4E38
            OR NOT (fRampUpRate = fRampUpRate) OR NOT (fRampDownRate = fRampDownRate);
fX := REAL_TO_LREAL(fSetpoint);

IF NOT bStarted OR bInputNotANumber THEN
  tPrev := TIME();               (* nothing to catch up on *)
  bStarted := TRUE;
ELSE
  dMs := TIME_TO_LINT(TIME() - tPrev);         (* whole ms elapsed *)
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);        (* the part of a ms left over carries on *)
    CASE eRateUnit OF
    E_RateUnit.PerMin: fPerS := 60.0;
    E_RateUnit.PerHour: fPerS := 3600.0;
    E_RateUnit.PerDay: fPerS := 86400.0;
    ELSE
      fPerS := 1.0;
    END_CASE;
    dtS := LINT_TO_LREAL(dMs) / 1000.0 / fPerS;
    IF fX > fY THEN
      fRateAbs := ABS(REAL_TO_LREAL(fRampUpRate));
      IF fRateAbs = 0.0 THEN
        fY := fX;
      ELSE
        fY := MIN(fX, fY + fRateAbs * dtS);
      END_IF;
    ELSIF fX < fY THEN
      fRateAbs := ABS(REAL_TO_LREAL(fRampDownRate));
      IF fRateAbs = 0.0 THEN
        fY := fX;
      ELSE
        fY := MAX(fX, fY - fRateAbs * dtS);
      END_IF;
    END_IF;
  END_IF;
END_IF;

IF bFollowAtOnce AND NOT bInputNotANumber THEN
  fY := fX;
END_IF;
fOut := LREAL_TO_REAL(fY);
bRamping := NOT bInputNotANumber AND fY <> fX;

END_FUNCTION_BLOCK