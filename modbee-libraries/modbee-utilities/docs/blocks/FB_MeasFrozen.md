# FB_MeasFrozen — Frozen measurement check

Placed after a measurement: warns (or trips) when a value that should move has not moved.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipIn` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `refData` | `REFERENCE TO ST_MeasFrozenData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bFrozen` | `BOOL` |  | The value has not moved |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasFrozenData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a held Manual trip (cleared by the block) |
| `stFrozen` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_MeasFrozenSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fBand` | `REAL` | `0.1` | a change larger than this is a change |
| `stFrozen` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#10m, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

## How it works

A measurement that should move but does not: no change larger than `set.fBand` for the protection's delay (`set.stFrozen`, default Warn after 10 min, Auto, recover 10 s): Warn = a warning (still good), Trip = not good, `bError`. Error Frozen. A change past the band restarts the wait; a bad input is not frozen.

## Example

Warn when the tank level has not moved for 10 minutes.

| Pin | Wire |
| --- | --- |
| `ipIn` | `fbTankLevel` |
| `refData` | `stFrozen` |
| `bFrozen` | a lamp |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
