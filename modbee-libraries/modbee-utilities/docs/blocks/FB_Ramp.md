# FB_Ramp — Rate-limited setpoint

A rate-limited setpoint: the output moves toward the input at a set rate.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | target |
| in | `fRateUp` | `REAL` | `10.0` | units per eRateUnit rising (0 = jump) |
| in | `fRateDown` | `REAL` | `10.0` | units per eRateUnit falling (0 = jump) |
| in | `eRateUnit` | `E_RateUnit` | `E_RateUnit.PerSec` | the rates are per second, minute, hour or day |
| in | `bTrack` | `BOOL` |  | fOut follows fIn at once |
| out | `fOut` | `REAL` |  | The ramped value |
| out | `bRamping` | `BOOL` |  | fOut is still moving toward fIn |
| out | `bBadInput` | `BOOL` |  | fIn or a rate is not a number: fOut is held |

## How it works

Rate-limited setpoint.

`fOut` moves toward `fIn` at `fRateUp` (rising) or `fRateDown` (falling), in units per `eRateUnit` (second by default; minute, hour or day), and stops exactly on `fIn` (no overshoot). A rate of 0, or infinity, means no limit: `fOut` jumps. The sign of a rate is ignored.

`fOut` starts at 0 after a restart and ramps to `fIn`. `bTrack` makes `fOut` follow `fIn` at once (for example while the drive is stopped), and the ramp carries on from there when `bTrack` goes FALSE.

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to the next scan, so the rate is exact at any task interval.

A value that is not a number (`fIn` NaN or infinite, a rate NaN) holds `fOut` where it is and sets `bBadInput`; the time it lasted does not count, so `fOut` does not catch up with a jump afterwards.

## Example

A setpoint that changes at most 0.1 bar per second.

| Pin | Wire |
| --- | --- |
| `fIn` | `fHmiSetpoint` |
| `fRateUp` | 0.1 |
| `fRateDown` | 0.1 |
| `fOut` | the loop's setpoint |

**Back to** [the index](../README.md).
