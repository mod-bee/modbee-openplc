# UT_FILTER — Smoothing filter

Smooths a noisy value (a level that sloshes, a flow that pulses, a pressure that
jumps) so alarms and controls don't chatter on the noise.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Noisy value |
| in | `Tc` | TIME | T#1s | Time constant (low-pass) or window length (averages) |
| in | `Mode` | UT_FILTER_MODE | UT_FILTER_LOWPASS | `UT_FILTER_LOWPASS` · `UT_FILTER_AVERAGE` · `UT_FILTER_BLOCK_AVG`, see below |
| in | `Reset` | BOOL | FALSE | Output jumps straight to `In` |
| out | `Out` | REAL | | Smoothed value |
| out | `BadInput` | BOOL | | `In` is NaN or infinite: `Out` is held |

## Modes
| Mode | What it does | Use it for |
| --- | --- | --- |
| `UT_FILTER_LOWPASS` | First order: after a step, `Out` has moved 63 % of the way after `Tc` and 95 % after 3 × `Tc` | General smoothing, fast to react |
| `UT_FILTER_AVERAGE` | Moving average of the last `Tc`, updated every scan: the `Tc` window being filled, plus the last whole window's share of the time still to fill. After a step, `Out` starts moving at once and reaches the new value at the end of the next window: `Tc` after the step when the step comes as a window starts, at most 2 × `Tc` after it otherwise (see below) | Levels with waves, flows with pulsation |
| `UT_FILTER_BLOCK_AVG` | Average of each `Tc` window, updated once at the end of each window | Logging, per-minute averages |

## How it works
- The first scan, `Reset`, and `Tc = 0` (or under 1 ms, or negative) pass `In` straight through.
- Changing `Mode` or `Tc` carries on from the present `Out`, without a jump.
- Timing uses real elapsed time, so the result is the same at any task
  interval, and it keeps working however long the PLC runs.
- A NaN or infinite `In` is ignored: `Out` holds, `BadInput` is set, and the time
  it lasted does not count. Filtering carries on from the held value when the
  input is good again. A NaN on the very first scan leaves `Out` at 0 until the
  first good value, which then passes straight through.
- The moving average keeps two sums: the window being filled, and the average of
  the last whole window. It takes the last window as even through its length, so it
  costs the same small memory at any task interval and any `Tc`. The windows follow
  each other from the first scan (and from a `Reset`, or a change of `Mode` or `Tc`).
  After a step part-way through a window, `Out` moves in a straight line until that
  window ends, then on in a second, slower straight line through the next window, and
  arrives at its end.

## Using it
```iecst
LevelFilt(In := Level, Tc := T#5s, Mode := UT_FILTER_AVERAGE);
LevelSmooth := LevelFilt.Out;
```
