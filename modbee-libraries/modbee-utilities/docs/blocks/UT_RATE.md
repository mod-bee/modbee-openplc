# UT_RATE — Rate of change

Measures how fast a value is changing (level rise in a wet well, temperature climb,
pressure decay in a leak test) and alarms on rising or falling too fast.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Value |
| in | `Reset` | BOOL | FALSE | Restart the measurement |
| out | `Rate` | REAL | | Change per `unit` |
| out | `RisingFast` | BOOL | | Rate > `riseLimit` (after `alarmDelay`) |
| out | `FallingFast` | BOOL | | Rate < −`fallLimit` (after `alarmDelay`) |
| inout | `Data` | UT_RATE_DATA | | Settings and status |

## Record `UT_RATE_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `unit` | UT_RATE_UNIT | UT_PER_MIN | `UT_PER_SEC` · `UT_PER_MIN` · `UT_PER_HOUR` · `UT_PER_DAY` |
| `window` | TIME | T#10s | Rate measured over this window (0 = off) |
| `filterTime` | TIME | T#0s | Smooths `Rate` further (low-pass time constant), 0 = none |
| `riseLimit` | REAL | 0.0 | `RisingFast` above this rate (0 = off) |
| `fallLimit` | REAL | 0.0 | `FallingFast` when falling faster than this (0 = off) |
| `alarmDelay` | TIME | T#5s | The rate must stay past a limit this long |
| `rate`, `risingFast`, `fallingFast` | | | Status: copies of the outputs |
| `ready` | BOOL | | Status: a full window has been measured |
| `badInput` | BOOL | | Status: `In` is NaN or infinite, `Rate` is held |

## How it works
- `Rate` is the slope of the best straight line through the readings of the last
  `window` (a trend line), so noise largely cancels. A steady ramp gives exactly
  its rate at any task interval. `Rate` updates every scan.
- After a start, a `Reset` or a change of `window`, `Rate` is 0 and the alarms are
  off until one full window has been measured (`ready`).
- A sudden step shows as a short bump (peak about 1.7 × step ÷ window) lasting
  about one window. Use `alarmDelay` or a longer window to ride through steps.
- The alarms clear as soon as the rate is back within the limit.
- The window is kept as ten slices, so memory is the same at any task interval.
  Keep the window longer than a scan; a shorter one gives 0.
- A NaN or infinite `In` is ignored: `Rate` holds, `badInput` is set, and the time
  it lasted does not count.

## Using it
```iecst
WellRise(In := WetWellLevel, Data := WellRiseCfg);   (* riseLimit := 0.5 m/min *)
InflowAlarm := WellRise.RisingFast;
```
