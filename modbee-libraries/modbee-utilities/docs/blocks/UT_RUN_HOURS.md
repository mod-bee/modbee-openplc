# UT_RUN_HOURS — Run-hour meter with service interval

Counts running time for anything (motor, heater, lamp, filter), keeps it across
power loss, and flags when a service is due. Split out of pumpSelectionControl.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Running` | BOOL | FALSE | Equipment running (e.g. `UT_MOTOR.Running`) |
| in | `ResetService` | BOOL | FALSE | Rising edge: service done, restart the service count |
| out | `TotalHours` | REAL | | Lifetime hours |
| out | `ServiceDue` | BOOL | | Service hours ≥ interval |
| inout | `Data` | UT_RUN_HOURS_DATA | | |

## Record `UT_RUN_HOURS_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `serviceInterval` | REAL | 0.0 | Hours between services (0, negative or not a number = off) |
| `saveEvery` | TIME | T#12h | How often the hours are saved for a power cut (`T#0s` = not kept). Presets, service resets and day rollovers are saved at once |
| `cmdResetService` | BOOL | | HMI: service done |
| `cmdPreset` + `presetHours` | BOOL + REAL | | HMI: set the total (e.g. after replacing the PLC). 0 to 1E9 h; anything else is ignored |
| `cmdDayRollover` | BOOL | | Midnight pulse (from `UT_SCHEDULE` or the HMI): today → yesterday |
| `totalHours`, `serviceHours`, `serviceDue` | REAL, REAL, BOOL | | Status |
| `todayHours`, `yesterdayHours` | REAL | | Status: since / before the last day rollover |
| `currentRun` | TIME | | Status: length of this run (0 when stopped) |
| `lastRun` | TIME | | Status: length of the previous run |
| `serviceLeft` | REAL | | Status: hours to the next service; negative = overdue by that many hours; 0 when `serviceInterval` is off |

## How it works
- Time counts while `Running` is TRUE, from real elapsed time, so it is the same
  at any task rate. It is kept as whole milliseconds in a 64-bit integer plus the
  part of a millisecond left over, so it stays exact for centuries on every
  board (a REAL total would stop counting once it is large).
- The hours are saved for a power cut every `saveEvery`, so a power cut costs at
  most that much running time (plus the controller's own save period, see
  [conventions](../conventions.md#retained-data)). After a restart the block
  carries on from the saved hours from the first scan, without counting
  anything twice.
- Commands act once and are cleared; a command held on (a coil left on, a
  debugger force) acts once until it goes off again.
