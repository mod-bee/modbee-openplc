# FB_IrrDefer — Wet-weather defer

The wet-weather inhibit: says when not to irrigate (rain, wet soil, a lost sensor, a manual or remote defer), why, and to send the effluent to storage instead.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRainSwitch` | `BOOL` |  | a rain switch |
| in | `bSoilWetSwitch` | `BOOL` |  | a soil moisture switch |
| in | `bRainSwitchGood` | `BOOL` | `TRUE` | the rain sensor is healthy (FALSE = lost: defers, a warning) |
| in | `bSoilWetSwitchGood` | `BOOL` | `TRUE` | the soil sensor is healthy (FALSE = lost) |
| in | `bManualDefer` | `BOOL` |  | defer from the panel |
| in | `bRemoteDefer` | `BOOL` |  | defer from the platform (SCADA) |
| in | `ipSoilMoisture` | `I_Measurement` |  | NULL = bSoilWetSwitch / bSoilWetSwitchGood. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_IrrDeferData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bDeferIrrigation` | `BOOL` |  | do not irrigate |
| out | `eDeferReason` | `E_Defer` |  | why it defers |
| out | `bSendToStorage` | `BOOL` |  | to the route: send the water to storage |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IrrDeferData` (pin `refData`)

**Settings `set`** (`ST_IrrDeferSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRainSensorFitted` | `BOOL` | `TRUE` | the rain sensor is fitted and used |
| `bSoilSensorFitted` | `BOOL` | `TRUE` | the soil sensor is fitted and used |
| `tDeferDelay` | `TIME` | `T#1m` | rain, wet soil or a lost sensor must last this long to defer |
| `tClearDelay` | `TIME` | `T#1h` | every weather cause must be gone this long before irrigation is allowed again (the soil drains) |
| `bStorageFitted` | `BOOL` | `TRUE` | a storage is fitted: bSendToStorage follows bDeferIrrigation |
| `fSoilWetAtPct` | `REAL` | `35.0` | soil transmitter: wet at or above, % |
| `fSoilDryBelowPct` | `REAL` | `30.0` | dry again below |
| `bManualDefer` | `BOOL` |  | HMI defer |

**Status `sts`** (`ST_IrrDeferSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bDeferred` | `BOOL` |  | irrigation is deferred now |
| `eDeferReason` | `E_Defer` |  | why: Manual, Remote, Rain, Soil, RainLost, SoilLost or Setting |
| `fSoilMoisturePct` | `REAL` |  | NaN = none |
| `bSoilIsWet` | `BOOL` |  | the soil reads wet |
| `tTimeLeft` | `TIME` |  | time left in the defer or clear delay |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_Defer`: `None`, `Manual`, `Remote`, `Rain`, `Soil`, `RainLost`, `SoilLost`, `Setting` (default `None`)

## How it works

The wet-weather / defer-irrigation inhibit: says when not to irrigate, why, and to send the effluent to storage instead.

## Example

A rain switch and a soil moisture transmitter.

| Pin | Wire |
| --- | --- |
| `bRainSwitch` | `DI_RainSwitch` |
| `ipSoilMoisture` | `fbSoil` |
| `bManualDefer` | `DI_DeferSwitch` |
| `refData` | `stDefer` |
| `bDeferIrrigation` | the zone program's hold |
| `bSendToStorage` | the route's `bSendToStorage` |

**Back to** [the index](../README.md).
