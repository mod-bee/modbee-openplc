# FB_MeasFrozen — Frozen measurement check

Placed after a measurement: warns (or trips) when a value that should move has not moved.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMeasurement` | `I_Measurement` |  | the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_MeasFrozenData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fValue` | `REAL` |  | the value passed on (the source's) |
| out | `bGood` | `BOOL` |  | fValue can be trusted: the source is good and not frozen past a trip |
| out | `bValueFrozen` | `BOOL` |  | the value has not moved for the delay |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeasFrozenData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a held Manual trip (cleared by the block) |

**Settings `set`** (`ST_MeasFrozenSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinChange` | `REAL` | `0.1` | a change larger than this is a change |
| `stFrozenFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#10m, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | frozen-value protection settings (the delay is how long without movement); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_MeasFrozenSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stFrozenFault` | `ST_ProtectionSts` |  | frozen-value protection status; a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

A measurement that should move but does not: no change larger than `set.fMinChange` for the protection's delay (`set.stFrozenFault`, default Warn after 10 min, Auto, recover 10 s): Warn = a warning (still good), Trip = not good, `bError`. Error Frozen. A change past the band restarts the wait; a bad input is not frozen.

## Example

Warn when the tank level has not moved for 10 minutes.

| Pin | Wire |
| --- | --- |
| `ipMeasurement` | `fbTankLevel` |
| `refData` | `stFrozen` |
| `bValueFrozen` | a lamp |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
