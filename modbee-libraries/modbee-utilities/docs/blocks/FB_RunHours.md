# FB_RunHours — Run hours and service interval

A run-hour and start meter with a service interval, for anything that runs.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunning` | `BOOL` |  | it runs |
| in | `bServiceDone` | `BOOL R_EDGE` |  | rising edge: the service is done |
| in | `refData` | `REFERENCE TO ST_RunHoursData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fRunHours` | `LREAL` |  | run hours, lifetime |
| out | `bServiceDue` | `BOOL` |  | the service is due (a warning) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunHoursData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdServiceDone` | `BOOL` |  | cleared by the block |
| `bCmdPresetHours` | `BOOL` |  | cleared by the block |
| `fPresetRunHours` | `LREAL` |  | 0 .. 1E7 |
| `tThisRunTime` | `TIME` |  | detail |

**Settings `set`** (`ST_RunHoursSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fServiceIntervalHours` | `LREAL` |  | hours between services (0 = off) |

**Status `sts`** (`ST_RunHoursSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRunHours` | `LREAL` |  | lifetime |
| `fHoursSinceService` | `LREAL` |  | since the last service |
| `fHoursToService` | `LREAL` |  | run hours left until the next service |
| `bServiceDue` | `BOOL` |  | the service is due (a warning, ServiceDue) |
| `tLastRunTime` | `TIME` |  | written at each run end |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Totals `tot`** (`ST_RunHoursTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRunHours` | `LREAL` |  | lifetime run hours (kept), as FB_Motor's tot.fRunHours |
| `fRunHoursSinceService` | `LREAL` |  | run hours since the last service (kept) |
| `nStartCount` | `UDINT` |  | starts, lifetime (kept) |

## How it works

A run-hour and start meter with a service interval, for anything that runs (a blower, a heater, a drive not driven through [`FB_Motor`](FB_Motor.md)). Hours are counted exactly (whole milliseconds, the rest carried: [`F_HoursAdd`](F_HoursAdd.md)) into the lifetime and since-service totals, kept hourly and at each stop.

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Run hours of a blower with a 2000-hour service interval.

| Pin | Wire |
| --- | --- |
| `bRunning` | `DI_Blower_Running` |
| `bServiceDone` | `DI_ServiceDone` |
| `refData` | `stBlowerHours` |
| `bServiceDue` | a lamp |

**Back to** [the index](../README.md).
