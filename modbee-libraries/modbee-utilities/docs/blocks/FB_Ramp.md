# FB_Ramp — Rate-limited setpoint

A rate-limited setpoint: the output moves toward the input at a set rate.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fSetpoint` | `REAL` |  | target |
| in | `fRampUpRate` | `REAL` | `10.0` | units per eRateUnit rising (0 = jump) |
| in | `fRampDownRate` | `REAL` | `10.0` | units per eRateUnit falling (0 = jump) |
| in | `eRateUnit` | `E_RateUnit` | `E_RateUnit.PerSec` | the rates are per second, minute, hour or day |
| in | `bFollowAtOnce` | `BOOL` |  | fOut follows fSetpoint at once |
| out | `fOut` | `REAL` |  | the ramped value |
| out | `bRamping` | `BOOL` |  | fOut is still moving toward fSetpoint |
| out | `bInputNotANumber` | `BOOL` |  | fSetpoint or a rate is not a number: fOut is held |

## How it works

Rate-limited setpoint.

`fOut` moves toward `fSetpoint` at `fRampUpRate` (rising) or `fRampDownRate` (falling), in units per `eRateUnit` (second by default; minute, hour or day), and stops exactly on `fSetpoint` (no overshoot). A rate of 0, or infinity, means no limit: `fOut` jumps. The sign of a rate is ignored.

`fOut` starts at 0 after a restart and ramps to `fSetpoint`. `bFollowAtOnce` makes `fOut` follow `fSetpoint` at once (for example while the drive is stopped), and the ramp carries on from there when `bFollowAtOnce` goes FALSE.

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to the next scan, so the rate is exact at any task interval.

A value that is not a number (`fSetpoint` NaN or infinite, a rate NaN) holds `fOut` where it is and sets `bInputNotANumber`; the time it lasted does not count, so `fOut` does not catch up with a jump afterwards.

## Example

A setpoint that changes at most 0.2 bar per second.

| Pin | Wire |
| --- | --- |
| `fSetpoint` | `fHmiSetpoint` |
| `fRampUpRate` | 0.2 |
| `fRampDownRate` | 0.2 |
| `fOut` | the loop's setpoint |

**Back to** [the index](../README.md).
