# FB_LevelMeter — Volume from a tank level

The volume a pump moves, worked out from the tank's level (with a high-water mark, so waves are never counted twice).

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipLevel` | `I_Measurement` |  | required. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bPumpRunning` | `BOOL` |  | the pump runs: only then is anything counted |
| in | `ipOtherMeter` | `I_Meter` |  | a meter on the tank's other inflow or outflow during the run, whose rise is added (optional). An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `refData` | `REFERENCE TO ST_LevelMeterData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotals` | `BOOL` |  | HMI: the total back to 0 (acts once, cleared by the block) |

**Settings `set`** (`ST_LevelMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCountLevelFall` | `BOOL` | `TRUE` | count the level's fall (a pump emptying the tank); FALSE: its rise |
| `fMinRiseToCount` | `REAL` |  | the moved volume must pass its highest value so far by this before it counts (waves never count twice) |
| `tRateWindow` | `TIME` | `T#1m` | the rate is worked out over this window |

**Status `sts`** (`ST_LevelMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | counting: the meter can be trusted |
| `fFlowPerHour` | `REAL` |  | per hour |
| `fDeliveredThisRun` | `LREAL` |  | this run so far |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Totals `tot`** (`ST_LevelMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | the total (kept) |

## How it works

The volume a pump moves, worked out from the tank's level.

## Example

The volume an irrigation pump moves, from the tank level.

| Pin | Wire |
| --- | --- |
| `ipLevel` | `fbTank` |
| `bPumpRunning` | `DI_P1_Running` |
| `refData` | `stLevelMeter` |

Set `stLevelMeter.set.bCountLevelFall := TRUE` (the pump empties the tank).

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActTotal : LREAL`: the lifetime total in its unit
- property `fActFlowPerHour : REAL`: the rate, per hour
- property `bIsGood : BOOL`: the value can be trusted now
- property `fActValue : REAL`: I_Measurement: the rate (per hour), unit None (the vessel's volume unit is not known here), no bands
- property `bHasValue : BOOL`: a value is available (fitted and read at least once)
- property `bIsFitted : BOOL`: fitted on this site
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
