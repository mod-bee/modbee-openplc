# UT_RAMP — Rate-limited setpoint

Moves an output toward a target at a set rate: soft speed changes, gentle valve
moves, setpoint ramps for heating.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Target |
| in | `RateUp` | REAL | 10.0 | Units per `RateUnit` rising (0 = jump) |
| in | `RateDown` | REAL | 10.0 | Units per `RateUnit` falling (0 = jump) |
| in | `RateUnit` | UT_RATE_UNIT | UT_PER_SEC | The rates are per second (`UT_PER_SEC`), minute, hour or day, e.g. a temperature setpoint ramped in °C per minute |
| in | `Track` | BOOL | FALSE | Output follows `In` immediately (e.g. while stopped) |
| out | `Out` | REAL | | The ramped value |
| out | `Ramping` | BOOL | | `Out` ≠ `In`: still moving |
| out | `BadInput` | BOOL | | `In` or a rate is not a number: `Out` is held |

## How it works
- `Out` moves toward `In` at `RateUp` or `RateDown` and stops exactly on `In`. It
  never overshoots, and a target reversed mid-ramp turns straight round.
- A rate of 0 (or infinity) means no limit: `Out` jumps. The sign of a rate is
  ignored, so −5 acts as 5.
- After a restart `Out` starts at **0** and ramps up to `In`. Wire `Track` to start
  from `In` instead; when `Track` goes FALSE the ramp carries on from there.
- Timing uses real elapsed time, so the rate is the same at any task interval,
  and very slow rates (0.001 per second) still add up exactly.
- A NaN or infinite `In`, or a NaN rate, holds `Out` where it is and sets
  `BadInput` (`Ramping` is FALSE meanwhile). The time it lasted does not count,
  so `Out` does not jump to catch up afterwards. `Track` does not follow a bad `In`.

## Using it
```iecst
SpeedRamp(In := SpeedSP, RateUp := 5.0, RateDown := 10.0, Track := NOT Running);
DriveSpeed := SpeedRamp.Out;   (* Hz, 5 Hz/s up, 10 Hz/s down *)
```
