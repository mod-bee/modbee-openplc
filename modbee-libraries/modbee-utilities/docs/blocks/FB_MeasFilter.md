# FB_MeasFilter — Measurement filter

Placed after a measurement: smooths it, cuts off creep below a low limit and clamps it.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipIn` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `refData` | `REFERENCE TO ST_MeasFilterData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fValue` | `REAL` |  | The filtered value |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasFilterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | detail: the value out |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_MeasFilterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tFilter` | `TIME` |  | 0 = no filter |
| `eMode` | `E_FilterMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `fLowCutoff` | `REAL` |  | \|value\| below this reads 0 (0 = off) |
| `bClamp` | `BOOL` |  |  |
| `fClampMin` | `REAL` |  |  |
| `fClampMax` | `REAL` | `100.0` |  |

## Lists

- `E_FilterMode`: `Lowpass`, `Average`, `BlockAvg` (default `E_FilterMode.Lowpass`)

## How it works

Smooths and shapes a measurement: `set.tFilter` ([`FB_Filter`](FB_Filter.md), `set.eMode`), then below `set.fLowCutoff` (> 0) reads 0 (a flow meter's creep), then with `set.bClamp` held to `fClampMin`..fClampMax. A bad input holds the filter (the time not counted); `bIsGood` is the input's.

## Example

Smooth a noisy flow reading before the loop uses it.

| Pin | Wire |
| --- | --- |
| `ipIn` | `fbFlowRaw` |
| `refData` | `stFlowFilter` |

Wire `fbFlowFilter` (not `fbFlowRaw`) to the consumers.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
