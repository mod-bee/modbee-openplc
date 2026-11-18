# FB_Schedule — Weekly schedule

A weekly time-of-day schedule (a local fallback; the platform holds the real calendar): time windows by day, overrides, hour and day pulses.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | AND-ed with set.bEnable |
| in | `dtClock` | `DT` | `DT#1970-01-01-00:00:00` | local time (optional): unwired = no clock, the schedule is off |
| in | `bOverrideOn` | `BOOL R_EDGE` |  | bActive on for set.tOverrideFor Acts on its rising edge. |
| in | `bOverrideOff` | `BOOL R_EDGE` |  | bActive off for set.tOverrideFor Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_ScheduleData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aWindow` | `ARRAY[*] OF ST_SchedWindow` |  | the project's table, one row per time window, at most 16 kept |
| out | `bActive` | `BOOL` |  | Active now |
| out | `nWindow` | `INT` |  | the first window on, 1 = the first row; 0 none |
| out | `bHourPulse` | `BOOL` |  | One scan at each new hour |
| out | `bDayPulse` | `BOOL` |  | One scan at midnight |
| out | `bClockOk` | `BOOL` |  | The clock is set and moving |
| out | `bOverridden` | `BOOL` |  | An override is on |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ScheduleData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdOverrideOn` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdOverrideOff` | `BOOL` |  |  |
| `bCmdCancelOverride` | `BOOL` |  |  |

**Settings `set`** (`ST_ScheduleSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | Works only while TRUE |
| `tUtcOffset` | `TIME` |  | added to the clock to give local time (within 24 h) |
| `tOverrideFor` | `TIME` | `T#1h` | 0 = until the schedule next changes |

**Status `sts`** (`ST_ScheduleSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bActive` | `BOOL` |  | Active now |
| `bOverridden` | `BOOL` |  |  |
| `dtNextChange` | `DT` |  | local; DT#1970-01-01-00:00:00 = none / no clock |
| `nDayOfWeek` | `INT` |  | 1 Monday ... 7 Sunday, 0 = no clock |
| `nInMask` | `DWORD` |  | bit per window on now |
| `nConfigWindow` | `INT` |  | the first window with a bad setting (0 none) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Details `det`** (`ST_ScheduleDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tOverrideLeft` | `TIME` |  |  |
| `tNextChangeIn` | `TIME` |  |  |
| `dtLocal` | `DT` |  |  |

## Rows `ST_SchedWindow` (pin `aWindow`)

`aWindow` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SchedWindow`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | Works only while TRUE |
| `nDays` | `BYTE` | `16#7F` | bit 0 Monday ... bit 6 Sunday |
| `todStart` | `TOD` | `TOD#06:00:00` |  |
| `todStop` | `TOD` | `TOD#18:00:00` | earlier than todStart: crosses midnight |
| `nEveryDays` | `INT` |  | 2 or more: every N-th day from dStartDate |
| `dStartDate` | `DATE` | `DATE#1970-01-01` |  |

## How it works

Weekly time-of-day schedule, a local fallback (the platform holds the real calendar). `aWindow` (the project's table, one row per time window, at most 16 kept): a window runs from `todStart` to `todStop` on each day in its `nDays` bits (bit 0 Monday ... bit 6 Sunday); a `todStop` earlier than `todStart` crosses midnight (the part after midnight belongs to the day it started); `todStart` = `todStop` is empty. `nEveryDays` N (2 or more) runs it only every N-th day from `dStartDate`. `bActive` is on inside any window; `nWindow` is the first one on (1 = the first row), `sts.nInMask` has a bit per window (bit 0 = the first row, up to 32).

Clock: `dtClock`, local time from [`F_LocalTime`](F_LocalTime.md) (the boards have no real-time clock: unwired = no clock, the schedule is off); `set.tUtcOffset` is added. `bClockOk` is off when the clock is implausible ([`F_ClockOk`](F_ClockOk.md)) or has not moved for 5 s: the schedule is then off (an override still works), warning NoClock. `bHourPulse` / `bDayPulse` give one scan on each new hour / at midnight, never doubled by a clock set back.

Overrides (`bOverrideOn` / `bOverrideOff` pins, `bCmdOverrideOn` / `bCmdOverrideOff` / `bCmdCancelOverride`, each once per write): `bActive` on / off for `set.tOverrideFor` (0 = until the schedule next changes); Off wins, then Cancel, then On. `bEnable` FALSE (pin or `set.bEnable`) cancels an override. `sts.dtNextChange` is the next time the schedule changes (within 8 days; DT#1970-01-01-00:00:00 = none or no clock).

Kept (a retained last-good copy, restored at power-up, a bad write put back): set and the window rows. A window with a bad setting and no good copy is left out: warning BadSetting, `sts.nConfigWindow` names it.

## Example

Irrigation windows by day. Declare `aWin : ARRAY[1..4] OF ST_SchedWindow`.

| Pin | Wire |
| --- | --- |
| `dtClock` | the local time (F_LocalTime of the site clock) |
| `aWindow` | `aWin` |
| `refData` | `stSched` |
| `bActive` | the program's start |

**Back to** [the index](../README.md).
