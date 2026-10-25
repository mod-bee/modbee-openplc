# UT_STATS — Minimum, maximum and average per period

Keeps min / max / time-weighted average of a value for the current period and the
previous one, for reports, dashboards and IoT uploads.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Value |
| in | `Enable` | BOOL | TRUE | Only collect while TRUE (e.g. only while running) |
| in | `Rollover` | BOOL | FALSE | Rising edge: close the period (e.g. hourly/daily pulse from `UT_SCHEDULE`) |
| out | `Minimum` / `Maximum` / `Average` | REAL | | Current period (0 while it has no samples) |
| inout | `Data` | UT_STATS_DATA | | |

## Record `UT_STATS_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `ignoreBelow` / `ignoreAbove` | REAL | 0.0 / 0.0 | Values below / above are left out (each 0 = off) |
| `cmdResetStats` | BOOL | | HMI: clear the current and the previous period (acts once, cleared; saved at once) |
| `minimum`, `maximum`, `average` | REAL | | Current period, as the pins |
| `minimumAt`, `maximumAt` | TIME | | Time into the period when the minimum / maximum happened |
| `samples` | UDINT | | Samples counted. 0 = empty period (the values then read 0) |
| `duration` | TIME | | Time collected (`Enable` TRUE) |
| `prevMinimum`, `prevMaximum`, `prevAverage`, `prevDuration` | | | The previous period |
| `prevSamples` | UDINT | | 0 = the previous period was empty |

## How it works
- **Time-weighted**: the value read each scan stands for the time since the
  previous scan, so a value that held for an hour weighs an hour, at any scan rate.
- Only samples taken while `Enable` is TRUE, that are numbers (not NaN or
  infinity) and are not left out by `ignoreBelow` / `ignoreAbove` count.
- `Rollover` (rising edge) moves the current period to `prev*` and starts a new one.
  A `Rollover` and a `cmdResetStats` in the same scan clear everything.
- **Power cut**: nothing is kept. Both periods start empty.
- The sum is accurate over long periods (compensated summation), even on boards
  where LREAL is 32-bit.

## Using it
```iecst
FlowStats(In := Flow.Value, Enable := PumpRunning, Rollover := Clock.DayPulse, Data := FlowStatsCfg);
```
