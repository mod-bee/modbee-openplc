# FB_MeasFilter — Measurement filter

Placed after a measurement: smooths it, cuts off creep below a low limit and clamps it.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMeasurement` | `I_Measurement` |  | the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_MeasFilterData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fValue` | `REAL` |  | the filtered value |
| out | `bGood` | `BOOL` |  | fValue can be trusted (the source's bIsGood) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasFilterData` (pin `refData`)

**Settings `set`** (`ST_MeasFilterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tFilterTime` | `TIME` |  | 0 = no filter |
| `eFilterType` | `E_FilterMode` |  | Lowpass, Average or BlockAvg |
| `fZeroBelow` | `REAL` |  | \|value\| below this reads 0 (0 = off) |
| `bClampOn` | `BOOL` |  | clamp the value to fMinValue..fMaxValue |
| `fMinValue` | `REAL` |  | lowest value passed on (bClampOn) |
| `fMaxValue` | `REAL` | `100.0` | highest value passed on (bClampOn) |

**Status `sts`** (`ST_MeasFilterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | detail: the value out |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_FilterMode`: `Lowpass`, `Average`, `BlockAvg` (default `E_FilterMode.Lowpass`)

## How it works

Smooths and shapes a measurement: `set.tFilterTime` ([`FB_Filter`](FB_Filter.md), `set.eFilterType`), then below `set.fZeroBelow` (> 0) reads 0 (a flow meter's creep), then with `set.bClampOn` held to `fMinValue`..fMaxValue. A bad input holds the filter (the time not counted); `bIsGood` is the input's.

## Example

Smooth a noisy flow reading before the loop uses it.

| Pin | Wire |
| --- | --- |
| `ipMeasurement` | `fbFlowRaw` |
| `refData` | `stFlowFilter` |

Wire `fbFlowFilter` (not `fbFlowRaw`) to the consumers.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
