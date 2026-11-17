# FB_MeasOverride — Measurement simulation and substitute

Placed after a measurement: simulation, and what a bad value shows (pass, hold or a substitute).

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipIn` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `refData` | `REFERENCE TO ST_MeasOverrideData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fValue` | `REAL` |  | The value passed on |
| out | `bGood` | `BOOL` |  | The value can be trusted |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasOverrideData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSimulate` | `BOOL` |  | never kept: off after a power cut |
| `fSimValue` | `REAL` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_MeasOverrideSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eOnBad` | `E_OnBadValue` |  |  |
| `fSubstitute` | `REAL` |  |  |

## Lists

- `E_OnBadValue`: `Pass`, `Hold`, `Substitute` (default `Pass`)

## How it works

Simulation and what a bad value shows. `bSimulate` (the record; never kept: off after a power cut) gives `fSimValue`, good, a warning (Simulated). While the input is bad, `set.eOnBad`: Pass (its value), Hold (the last good value) or Substitute (`set.fSubstitute`); `bIsGood` stays FALSE (a consumer still knows), only the value changes.

## Example

Simulate a level for commissioning, or hold the last good value when it fails.

| Pin | Wire |
| --- | --- |
| `ipIn` | `fbTankLevel` |
| `refData` | `stLevelOvr` |

Wire `fbLevelOvr` to the consumers.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
