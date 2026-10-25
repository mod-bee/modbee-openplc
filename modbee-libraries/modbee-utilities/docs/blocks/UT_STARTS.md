# UT_STARTS — Start counter and restart inhibit

Counts starts, and protects motors from starting too often: a maximum number of
starts per hour, a minimum time between starts, and a longer wait after a failed
start. Starting current heats the windings, so too many starts in a short time
damages a motor. Wire `StartPermit` to the motor's `Permissive`.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Running` | BOOL | FALSE | Motor running (each rising edge = one start) |
| in | `StartFailed` | BOOL | FALSE | Rising edge: a start attempt failed (e.g. `Motor1.noFeedback.tripped`) |
| in | `Reset` | BOOL | FALSE | Rising edge: clears the inhibit (not the counters) |
| out | `StartPermit` | BOOL | | → motor `Permissive` |
| out | `Starts` | UDINT | | Lifetime starts |
| out | `PermitIn` | TIME | | Time until the next start is allowed |
| inout | `Data` | UT_STARTS_DATA | | |

## Record `UT_STARTS_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `saveEvery` | TIME | T#12h | How often the counts are saved for a power cut (`T#0s` = not kept). Presets, count resets and day rollovers are saved at once |
| `maxPerHour` | INT | 0 | Starts allowed within `window`. 0 or negative = unlimited, above 30 = 30. Use the motor maker's figure |
| `window` | TIME | T#1h | The sliding window `maxPerHour` counts over (0 = off; longer than 24 days counts as 24 days) |
| `minBetween` | TIME | T#0s | Minimum time from one start to the next (longer than 24 days counts as 24 days) |
| `failWait` | TIME | T#0s | Wait after a failed start (longer than 24 days counts as 24 days) |
| `cmdReset` | BOOL | | HMI: clear the inhibit (not the counts) |
| `cmdResetCount` | BOOL | | HMI: lifetime count to 0 |
| `cmdPreset` + `presetStarts` | BOOL + UDINT | | HMI: set the lifetime count (a preset in the same write as a count reset wins) |
| `cmdDayRollover` | BOOL | | Midnight pulse: today → yesterday |
| `total` | UDINT | | Status: lifetime starts |
| `lastHour` | INT | | Status: starts within the window now (shows at most 30) |
| `startPermit`, `permitIn` | BOOL, TIME | | Status: as the pins |
| `todayStarts`, `yesterdayStarts` | UDINT | | Status |

## How it works
- The next start is allowed at the latest of: the last start + `minBetween`, the
  last failed start + `failWait`, and, when `maxPerHour` starts are in the
  window, the oldest of them + `window`. The window slides: each start drops out
  exactly `window` after it was made.
- The block keeps the time of each of the last 30 starts as milliseconds on its own
  clock, which counts from its first scan. So `window`, `minBetween` and `failWait`
  can be at most 24 days: a longer setting counts as 24 days.
- **The permit never stops a running motor**: `StartPermit` stays TRUE while
  `Running` is TRUE, whatever it is wired to. A start made anyway (Hand, hard
  wiring) is still counted.
- A motor already running when the block first runs is not counted as a start.
- **Power cut**: the counts (lifetime, today, yesterday) are kept as of the last
  save (`saveEvery`; presets, count resets and day rollovers at once). The
  inhibit is not kept: after a power-up the window is empty and a start is
  allowed at once.
