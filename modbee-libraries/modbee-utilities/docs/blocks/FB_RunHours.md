# FB_RunHours — Run hours and service interval

A run-hour and start meter with a service interval, for anything that runs.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunning` | `BOOL` |  | It runs (status) |
| in | `bResetService` | `BOOL R_EDGE` |  | the service is done Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_RunHoursData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fHours` | `LREAL` |  | lifetime |
| out | `bServiceDue` | `BOOL` |  | a warning, ServiceDue |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunHoursData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetService` | `BOOL` |  | cleared by the block |
| `bCmdPreset` | `BOOL` |  | cleared by the block |
| `fPresetHours` | `LREAL` |  | 0 .. 1E7 |
| `tCurrentRun` | `TIME` |  | detail |

**Settings `set`** (`ST_RunHoursSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fServiceInterval` | `LREAL` |  | hours between services (0 = off) |

**Status `sts`** (`ST_RunHoursSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fHours` | `LREAL` |  | lifetime |
| `fServiceHours` | `LREAL` |  | since the last service |
| `fServiceLeft` | `LREAL` |  |  |
| `bServiceDue` | `BOOL` |  | a warning, ServiceDue |
| `tLastRun` | `TIME` |  | written at each run end |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Totals `tot`** (`ST_RunHoursTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nTotalMs` | `LINT` |  |  |
| `nServiceMs` | `LINT` |  |  |
| `nStarts` | `UDINT` |  | Starts, lifetime (kept) |

## How it works

A run-hour and start meter with a service interval, for anything that runs (a blower, a heater, a drive not driven through [`FB_Motor`](FB_Motor.md)). Hours are counted exactly (whole milliseconds, the rest carried: [`F_HoursAdd`](F_HoursAdd.md)) into the lifetime and since-service totals, kept hourly and at each stop.

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Run hours of a blower with a 2000-hour service interval.

| Pin | Wire |
| --- | --- |
| `bRunning` | `DI_Blower_Running` |
| `bResetService` | `DI_ServiceDone` |
| `refData` | `stBlowerHours` |
| `bServiceDue` | a lamp |

**Back to** [the index](../README.md).
