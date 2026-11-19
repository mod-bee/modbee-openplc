# FB_MeterSelect — One meter from two sources

One meter from two sources chosen at run time (a pulse meter or the tank level's meter): its total carries on smoothly when the source changes; wire it where one meter goes.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bUseMeterB` | `BOOL` | `FALSE` | FALSE: meter A, TRUE: meter B |
| in | `ipMeterA` | `I_Meter` |  | meter A. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `ipMeterB` | `I_Meter` |  | meter B. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `bPumpRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the total |
| in | `refData` | `REFERENCE TO ST_MeterSelectData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeterSelectData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotals` | `BOOL` |  | the total back to 0 (cleared) |

**Status `sts`** (`ST_MeterSelectSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bUsingMeterB` | `BOOL` |  | the source in use is meter B |
| `bGood` | `BOOL` |  | the meter in use can be trusted |
| `fFlowPerHour` | `REAL` |  | per hour (the source in use's) |

**Totals `tot`** (`ST_MeterSelectTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | the total, in the meters' unit (kept) |

## How it works

One meter from two sources, chosen at run time (a site setting): e.g. a pulse flow meter or the tank level's meter. It is a meter itself (`I_Meter`, so an `I_Measurement` too): wire it where one meter goes ([`FB_RunVolume`](FB_RunVolume.md), [`FB_RunLog`](FB_RunLog.md), [`FB_MeterCycle`](FB_MeterCycle.md), [`FB_LevelCheck`](FB_LevelCheck.md)).

## Example

Irrigation volume from the pulse meter or the tank level, chosen by a site setting.

| Pin | Wire |
| --- | --- |
| `bUseMeterB` | `stSite.bUseLevelMeter` |
| `ipMeterA` | `fbPulseMeter` |
| `ipMeterB` | `fbLevelMeter` |
| `bPumpRunning` | `DI_P1_Running` |
| `refData` | `stIrrMeter` |

Wire `fbIrrMeter` to FB_RunVolume's `ipMeter` and FB_MeterCycle's `ipMeter`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActTotal : LREAL`: the total in its unit
- property `fActFlowPerHour : REAL`: the flow per hour of the meter in use
- property `bIsGood : BOOL`: the meter in use can be trusted
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in the source in use's unit, no bands
- property `bHasValue : BOOL`: a value is available
- property `bIsFitted : BOOL`: fitted on this site
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
