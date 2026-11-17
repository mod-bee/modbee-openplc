# FB_MeterSelect — One meter from two sources

One meter from two sources chosen at run time (a pulse meter or the tank level's meter): its total carries on smoothly when the source changes; wire it where one meter goes.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bUseB` | `BOOL` | `FALSE` | FALSE: meter A, TRUE: meter B |
| in | `ipMeterA` | `I_Meter` |  | A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `ipMeterB` | `I_Meter` |  | each a meter block: FB_PulseMeter, FB_RegisterMeter, FB_FlowTotal, FB_LevelMeter. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `bRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the total |
| in | `refData` | `REFERENCE TO ST_MeterSelectData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeterSelectData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotal` | `BOOL` |  | the total back to 0 (cleared) |

**Status `sts`** (`ST_MeterSelectSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bUsingB` | `BOOL` |  | the source in use is meter B |
| `bGood` | `BOOL` |  | The value can be trusted |
| `fRate` | `REAL` |  | per hour (the source in use's) |

**Totals `tot`** (`ST_MeterSelectTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | The total (kept) |

## How it works

One meter from two sources, chosen at run time (a site setting): e.g. a pulse flow meter or the tank level's meter. It is a meter itself (`I_Meter`, so an `I_Measurement` too): wire it where one meter goes ([`FB_RunVolume`](FB_RunVolume.md), [`FB_RunLog`](FB_RunLog.md), [`FB_MeterCycle`](FB_MeterCycle.md), [`FB_LevelCheck`](FB_LevelCheck.md)).

## Example

Irrigation volume from the pulse meter or the tank level, chosen by a site setting.

| Pin | Wire |
| --- | --- |
| `bUseB` | `stSite.bUseLevelMeter` |
| `ipMeterA` | `fbPulseMeter` |
| `ipMeterB` | `fbLevelMeter` |
| `bRunning` | `DI_P1_Running` |
| `refData` | `stIrrMeter` |

Wire `fbIrrMeter` to FB_RunVolume's `ipMeter` and FB_MeterCycle's `ipMeter`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActTotal : LREAL`
- property `fActRate : REAL`
- property `bIsGood : BOOL`
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in the source in use's unit, no bands
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
