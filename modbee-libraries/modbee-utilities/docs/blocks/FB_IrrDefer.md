# FB_IrrDefer — Wet-weather defer

The wet-weather inhibit: says when not to irrigate (rain, wet soil, a lost sensor, a manual or remote defer), why, and to send the effluent to storage instead.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRain` | `BOOL` |  | a rain switch |
| in | `bSoilWet` | `BOOL` |  | a moisture switch |
| in | `bRainOk` | `BOOL` | `TRUE` | The rain sensor is healthy (FALSE = lost: defers, a warning) |
| in | `bSoilOk` | `BOOL` | `TRUE` | the sensors' health; FALSE = lost |
| in | `bManual` | `BOOL` |  | panel |
| in | `bRemote` | `BOOL` |  | platform |
| in | `ipSoil` | `I_Measurement` |  | NULL = bSoilWet / bSoilOk. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `refData` | `REFERENCE TO ST_IrrDeferData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bDefer` | `BOOL` |  | do not irrigate |
| out | `eReason` | `E_Defer` |  | Why (status) |
| out | `bToStorage` | `BOOL` |  | -> the route |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IrrDeferData` (pin `refData`)

**Settings `set`** (`ST_IrrDeferSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bUseRain` | `BOOL` | `TRUE` |  |
| `bUseSoil` | `BOOL` | `TRUE` |  |
| `tOnDelay` | `TIME` | `T#1m` |  |
| `tClearDelay` | `TIME` | `T#1h` | the soil drains |
| `bStorage` | `BOOL` | `TRUE` | a storage is fitted: bToStorage follows bDefer |
| `fSoilWet` | `REAL` | `35.0` | soil transmitter: wet at or above, % |
| `fSoilDry` | `REAL` | `30.0` | dry again below |
| `bManualDefer` | `BOOL` |  | HMI defer |

**Status `sts`** (`ST_IrrDeferSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bDeferred` | `BOOL` |  |  |
| `eReason` | `E_Defer` |  | Why (status) |
| `fSoil` | `REAL` |  | NaN = none |
| `bSoilIsWet` | `BOOL` |  |  |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Lists

- `E_Defer`: `None`, `Manual`, `Remote`, `Rain`, `Soil`, `RainLost`, `SoilLost`, `Setting` (default `None`)

## How it works

The wet-weather / defer-irrigation inhibit: says when not to irrigate, why, and to send the effluent to storage instead.

## Example

A rain switch and a soil moisture transmitter.

| Pin | Wire |
| --- | --- |
| `bRain` | `DI_RainSwitch` |
| `ipSoil` | `fbSoil` |
| `bManual` | `DI_DeferSwitch` |
| `refData` | `stDefer` |
| `bDefer` | the zone program's hold |
| `bToStorage` | the route's `bToStorage` |

**Back to** [the index](../README.md).
