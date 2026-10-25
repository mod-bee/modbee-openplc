# UT_SCHEDULE — Weekly time-of-day schedule

Switches an output on during time windows on chosen days (irrigation, lighting,
HVAC occupancy, off-peak pumping). It gives hour/day pulses for totals and reports,
and an operator override.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | TRUE | Off: `Active` off and any override cancelled |
| in | `Clock` | DT | DT#1970-01-01-00:00:00 | Real-time clock (an RTC block). Unwired: the controller clock (`CURRENT_DT`, UTC) |
| out | `Active` | BOOL | | Inside a window (or overridden on) |
| out | `Window` | INT | | Which window is active, by position: 1 = first element of the array, whatever its lower bound (0 = none) |
| out | `HourPulse` / `DayPulse` | BOOL | | One scan on each new hour / midnight (feed `Rollover` inputs) |
| out | `ClockOk` | BOOL | | `Clock` is a plausible, advancing time |
| inout | `Windows` | ARRAY[*] OF UT_SCHED_WINDOW | | The time windows |
| inout | `Data` | UT_SCHED_DATA | | |

## Window slot `UT_SCHED_WINDOW`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enable` | BOOL | TRUE | |
| `days` | BYTE | 16#7F | Bit 0 = Monday … bit 6 = Sunday |
| `start` | TOD | TOD#06:00:00 | |
| `stop` | TOD | TOD#18:00:00 | Earlier than `start`: the window crosses midnight |
| `everyDays` | INT | 0 | 2 or more: only every N-th day, counted from `startDate` (0 or 1 = every day `days` allows) |
| `startDate` | DATE | DATE#1970-01-01 | With `everyDays`: day 1 of the cycle; before it the window is off |

## Record `UT_SCHED_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `utcOffset` | TIME | T#0s | Added to the clock to give local time: `T#12h` NZST, `T#13h` NZDT, `-T#5h` (west of UTC). Leave 0 if the clock is already local |
| `overrideFor` | TIME | T#1h | How long an override lasts. 0 = until the schedule next switches |
| `cmdOverrideOn` | BOOL | | HMI: `Active` on for `overrideFor` |
| `cmdOverrideOff` | BOOL | | HMI: `Active` off for `overrideFor` |
| `cmdCancelOverride` | BOOL | | HMI: back to the schedule |
| `active` | BOOL | | *status*: `Active` |
| `overridden` | BOOL | | *status*: an override is in force |
| `overrideLeft` | TIME | | *status*: time left on a timed override |
| `nextChange` | DT | | *status*: local time the schedule next switches (DT#1970-01-01-00:00:00 = never, or no clock) |
| `dayOfWeek` | INT | | *status*: 1 Monday … 7 Sunday (0 = no clock) |
| `localTime` | DT | | *status*: the clock plus `utcOffset` |
| `nextChangeIn` | TIME | | *status*: time until `nextChange` (T#0s = never, or no clock) |

## How it works
- **Windows.** A window is on from `start` up to (not including) `stop`, on each day set
  in `days`. A window that crosses midnight belongs to the day it **starts**: Sunday
  22:00–02:00 runs Sunday night into Monday morning. `start` = `stop` is an empty
  window. Overlapping windows simply combine; `Window` shows the first active one.
  Times are handled to the second.
- **Every N days.** `everyDays` 2 runs a window every second day from `startDate`
  (irrigation on alternate days), 3 every third day, and so on, and only on days
  `days` also allows. `startDate` is day 1; before it the window is off. A window
  crossing midnight belongs to the day it starts. The cycle counts real days, so with
  `everyDays` 2 it is strictly alternate days: after a 31st it does not follow odd /
  even dates.
- **The clock.** Leave `Clock` unwired to use the controller clock. It is UTC, so set
  `utcOffset` for local time. Daylight saving isn't automatic: change `utcOffset`
  (or wire a local-time clock).
- **Clock fault.** `ClockOk` is off when the clock is before 2020 or from 2100, or hasn't
  moved for 5 s. The schedule is then off (`Active` off, `Window` 0) until the clock is
  good again. An operator override still works.
- **Pulses.** `HourPulse` and `DayPulse` are in local time. A clock set forward gives one
  of each, however far. A clock set back (daylight saving, a correction) never pulses an
  hour or day twice; set back by more than an hour (a day), the block follows the new time.
- **Override.** `cmdOverrideOn` / `cmdOverrideOff` hold `Active` on / off for
  `overrideFor`, then the schedule takes over again. With `overrideFor` = 0 the override
  lasts until the schedule next switches. If several commands arrive together, Off wins,
  then Cancel over On. Each command acts once and is cleared; a command held on (a Modbus
  coil, a debugger force) acts only once, so an override still ends.
- `nextChange` is worked out once a second, looking up to 8 days ahead (a window
  every 9 days or more may show "never" until it is within 8 days). `nextChangeIn`
  counts down to it, for an HMI countdown.
