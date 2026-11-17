# FB_LevelMeter — Volume from a tank level

The volume a pump moves, worked out from the tank's level (with a high-water mark, so waves are never counted twice).

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipLevel` | `I_Measurement` |  | required. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `bActive` | `BOOL` |  | the pump runs: only then is anything counted |
| in | `ipAdd` | `I_Meter` |  | optional: a meter on the tank's other inflow or outflow during the run, whose rise is added. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `refData` | `REFERENCE TO ST_LevelMeterData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotal` | `BOOL` |  |  |

**Settings `set`** (`ST_LevelMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCountFalls` | `BOOL` | `TRUE` | a pump emptying the tank |
| `fDeadband` | `REAL` |  | a high-water mark |
| `tRateWindow` | `TIME` | `T#1m` | The rate is worked out over this window |

**Status `sts`** (`ST_LevelMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | The value can be trusted |
| `fRate` | `REAL` |  | per hour |
| `fRunMoved` | `LREAL` |  | this run so far |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Totals `tot`** (`ST_LevelMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | The total (kept) |

## How it works

The volume a pump moves, worked out from the tank's level.

## Example

The volume an irrigation pump moves, from the tank level.

| Pin | Wire |
| --- | --- |
| `ipLevel` | `fbTank` |
| `bActive` | `DI_P1_Running` |
| `refData` | `stLevelMeter` |

Set `stLevelMeter.set.bCountFalls := TRUE` (the pump empties the tank).

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActTotal : LREAL`
- property `fActRate : REAL`
- property `bIsGood : BOOL`
- property `fActValue : REAL`: I_Measurement: the rate (per hour), unit None (the vessel's volume unit is not known here), no bands
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
