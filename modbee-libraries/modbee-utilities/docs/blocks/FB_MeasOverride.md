# FB_MeasOverride — Measurement simulation and substitute

Placed after a measurement: simulation, and what a bad value shows (pass, hold or a substitute).

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMeasurement` | `I_Measurement` |  | the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_MeasOverrideData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fValue` | `REAL` |  | the value passed on |
| out | `bGood` | `BOOL` |  | the value can be trusted |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasOverrideData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSimulate` | `BOOL` |  | never kept: off after a power cut |
| `fSimulatedValue` | `REAL` |  | the value passed on while bSimulate |

**Settings `set`** (`ST_MeasOverrideSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eWhenValueBad` | `E_OnBadValue` |  | while the sensor is bad: Pass, Hold or Substitute |
| `fSubstituteValue` | `REAL` |  | the value used by Substitute |

**Status `sts`** (`ST_MeasOverrideSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

Simulation and what a bad value shows. `bSimulate` (the record; never kept: off after a power cut) gives `fSimulatedValue`, good, a warning (Simulated). While the input is bad, `set.eWhenValueBad`: Pass (its value), Hold (the last good value) or Substitute (`set.fSubstituteValue`); `bIsGood` stays FALSE (a consumer still knows), only the value changes.

## Example

Simulate a level for commissioning, or hold the last good value when it fails.

| Pin | Wire |
| --- | --- |
| `ipMeasurement` | `fbTankLevel` |
| `refData` | `stLevelOvr` |

Wire `fbLevelOvr` to the consumers.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
