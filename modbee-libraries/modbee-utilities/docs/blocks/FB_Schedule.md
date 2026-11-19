# FB_Schedule — Weekly schedule

A weekly time-of-day schedule (a local fallback; the platform holds the real calendar): time windows by day, overrides, hour and day pulses.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | AND-ed with set.bScheduleOn |
| in | `dtLocalTime` | `DT` | `DT#1970-01-01-00:00:00` | local time (optional): unwired = no clock, the schedule is off |
| in | `bOverrideOn` | `BOOL R_EDGE` |  | bScheduleActive on for set.tOverrideTime |
| in | `bOverrideOff` | `BOOL R_EDGE` |  | bScheduleActive off for set.tOverrideTime |
| in | `refData` | `REFERENCE TO ST_ScheduleData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aWindows` | `ARRAY[*] OF ST_SchedWindow` |  | the project's table, one row per time window (at most 16 kept) |
| out | `bScheduleActive` | `BOOL` |  | the schedule is on now |
| out | `nActiveWindow` | `INT` |  | the first window on, 1 = the first row; 0 none |
| out | `bHourPulse` | `BOOL` |  | one scan at each new hour |
| out | `bDayPulse` | `BOOL` |  | one scan at midnight |
| out | `bClockSynced` | `BOOL` |  | the clock is set and moving |
| out | `bOverrideActive` | `BOOL` |  | an override is on |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ScheduleData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdOverrideOn` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdOverrideOff` | `BOOL` |  | HMI: off now for tOverrideTime (acts once) |
| `bCmdCancelOverride` | `BOOL` |  | HMI: end the override (acts once) |

**Settings `set`** (`ST_ScheduleSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bScheduleOn` | `BOOL` | `TRUE` | the schedule works only while TRUE |
| `nUtcOffsetMinutes` | `INT` |  | minutes east of UTC added to the clock to give local time (-1440..1440), as F_LocalTime |
| `tOverrideTime` | `TIME` | `T#1h` | 0 = until the schedule next changes |

**Status `sts`** (`ST_ScheduleSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bScheduleActive` | `BOOL` |  | the schedule is on now |
| `bOverrideActive` | `BOOL` |  | an override is on |
| `dtNextChange` | `DT` |  | local; DT#1970-01-01-00:00:00 = none / no clock |
| `nDayOfWeek` | `INT` |  | 1 Monday ... 7 Sunday, 0 = no clock |
| `nActiveWindowBits` | `DWORD` |  | bit per window on now |
| `nBadSettingWindow` | `INT` |  | the first window with a bad setting (0 none) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_ScheduleDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tOverrideTimeLeft` | `TIME` |  | time left in the override |
| `tNextChangeTimeLeft` | `TIME` |  | time until the schedule next changes |
| `dtLocalTime` | `DT` |  | the local time the schedule uses (clock plus tUtcOffset) |

## Rows `ST_SchedWindow` (pin `aWindows`)

`aWindows` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SchedWindow`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bWindowOn` | `BOOL` | `TRUE` | this window is used |
| `nWeekdayBits` | `BYTE` | `16#7F` | bit 0 Monday ... bit 6 Sunday |
| `todStartTime` | `TOD` | `TOD#06:00:00` | start time of day (local) |
| `todStopTime` | `TOD` | `TOD#18:00:00` | earlier than todStartTime: crosses midnight |
| `nDaysBetweenRuns` | `INT` |  | 2 or more: every N-th day from dStartDate |
| `dStartDate` | `DATE` | `DATE#1970-01-01` | the first day counted for nDaysBetweenRuns |

## How it works

Weekly time-of-day schedule, a local fallback (the platform holds the real calendar). `aWindows` (the project's table, one row per time window, at most 16 kept): a window runs from `todStartTime` to `todStopTime` on each day in its `nWeekdayBits` bits (bit 0 Monday ... bit 6 Sunday); a `todStopTime` earlier than `todStartTime` crosses midnight (the part after midnight belongs to the day it started); `todStartTime` = `todStopTime` is empty. `nDaysBetweenRuns` N (2 or more) runs it only every N-th day from `dStartDate`. `bScheduleActive` is on inside any window; `nActiveWindow` is the first one on (1 = the first row), `sts.nActiveWindowBits` has a bit per window (bit 0 = the first row, up to 32).

Clock: `dtLocalTime`, local time from [`F_LocalTime`](F_LocalTime.md) (the boards have no real-time clock: unwired = no clock, the schedule is off); `set.nUtcOffsetMinutes` is added. `bClockSynced` is off when the clock is implausible ([`F_ClockOk`](F_ClockOk.md)) or has not moved for 5 s: the schedule is then off (an override still works), warning NoClock. `bHourPulse` / `bDayPulse` give one scan on each new hour / at midnight, never doubled by a clock set back.

Overrides (`bOverrideOn` / `bOverrideOff` pins, `bCmdOverrideOn` / `bCmdOverrideOff` / `bCmdCancelOverride`, each once per write): `bScheduleActive` on / off for `set.tOverrideTime` (0 = until the schedule next changes); Off wins, then Cancel, then On. `bEnable` FALSE (pin or `set.bScheduleOn`) cancels an override. `sts.dtNextChange` is the next time the schedule changes (within 8 days; DT#1970-01-01-00:00:00 = none or no clock).

Kept (a retained last-good copy, restored at power-up, a bad write put back): set and the window rows. A window with a bad setting and no good copy is left out: warning BadSetting, `sts.nBadSettingWindow` names it.

## Example

Irrigation windows by day. Declare `aWin : ARRAY[1..4] OF ST_SchedWindow`.

| Pin | Wire |
| --- | --- |
| `dtLocalTime` | the local time (F_LocalTime of the site clock) |
| `aWindows` | `aWin` |
| `refData` | `stSched` |
| `bScheduleActive` | the program's start |

**Back to** [the index](../README.md).
