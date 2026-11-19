# FB_AnalogIn — Analog input

An analog reading to an engineering value with its health: 4-20 mA (NE43 fail bands), 0-20 mA, 0-10 V, custom or a value already in units, with a fault ride-through.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fRawIn` | `REAL` |  | raw value; the engineering value itself with Direct |
| in | `bInputGood` | `BOOL` | `TRUE` | the source is healthy (IO module, comms, device) |
| in | `refData` | `REFERENCE TO ST_AnalogInData` |  | the block's record |
| in | `stConfig` | `ST_AnalogInConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fValue` | `REAL` |  | engineering value; the last good one while the signal has failed |
| out | `bGood` | `BOOL` |  | fValue is usable |
| out | `fPctOfSpan` | `REAL` |  | fValue as a % of fValueAtSignalLow..fValueAtSignalHigh |
| out | `fValueSecondUnit` | `REAL` |  | fValue in the second unit (set.fSecondUnitFactor, fSecondUnitOffset) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnalogInData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a latched fault (cleared by the block) |

**Settings `set`** (`ST_AnalogInSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSensorFitted` | `BOOL` | `TRUE` | FALSE: not on this site (not good, no fault) |
| `fValueAtSignalLow` | `REAL` |  | engineering value at fRawAtSignalLow |
| `fValueAtSignalHigh` | `REAL` | `100.0` | engineering value at fRawAtSignalHigh |
| `fZeroTrim` | `REAL` |  | field zero trim, engineering units |
| `fSecondUnitFactor` | `REAL` | `1.0` | fValueSecondUnit = fValue * fSecondUnitFactor + fSecondUnitOffset (a second unit) |
| `fSecondUnitOffset` | `REAL` |  | second unit: the offset added after the factor |
| `stSignalFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#2s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#2s, nMaxRetriesBeforeLockout := 3)` | signal fault protection settings (under / over range, input bad); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_AnalogInSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | the value in engineering units |
| `fValueSecondUnit` | `REAL` |  | the value in the second unit |
| `bGood` | `BOOL` |  | the value can be trusted |
| `eSignalStatus` | `E_AiStatus` |  | the signal: Ok, UnderRange, OverRange, FailLow, FailHigh, InputBad, NotFitted |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stSignalFault` | `ST_ProtectionSts` |  | signal fault protection status; a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_AnalogInDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawValue` | `REAL` |  | the raw input value as read |
| `fPctOfSpan` | `REAL` |  | the value as a % of the span |

## Constants `ST_AnalogInConfig` (pin `stConfig`)

**Fields** (`ST_AnalogInConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSignalType` | `E_AiSignal` |  | the input signal: 4-20 mA, 0-20 mA, 0-10 V, Custom or Direct |
| `fRawAtSignalLow` | `REAL` |  | raw value at the bottom of the signal (4 mA, 0 mA, 0 V) |
| `fRawAtSignalHigh` | `REAL` | `65535.0` | raw value at the top of the signal (20 mA, 10 V) |
| `eUnit` | `E_Unit` |  | unit of fValue |
| `fCustomFailLowPct` | `REAL` | `-5.0` | Custom / Direct: fail low at or below this % of the span |
| `fCustomFailHighPct` | `REAL` | `105.0` | Custom / Direct: fail high at or above this % of the span |

Set once, at the variable's declaration (engineering constants, not changed while running).

## Lists

- `E_AiSignal`: `Current4To20`, `Current0To20`, `Voltage0To10`, `Custom`, `Direct` (default `Current4To20`)
- `E_AiStatus`: `Ok`, `UnderRange`, `OverRange`, `FailLow`, `FailHigh`, `InputBad`, `NotFitted` (default `Ok`)

## How it works

A raw analog reading (or a remote / computed value) to an engineering value with its health. Wire the instance to any `I_Measurement` pin.

Signal types (`stConfig.eSignalType`); `fRawAtSignalLow` / `fRawAtSignalHigh` are the raw values at the bottom and top of the signal:

```
  Current4To20  NE43: <= 3.6 mA fail low, 3.6-3.8 under range, 3.8-20.5 measurement, 20.5-21 over range,
                >= 21 fail high
  Current0To20, below 0 % / above 100 % of the span is under / over range (no fail bands: a live zero
  Voltage0To10  is needed to see a wire break)
  Custom        as 0-20 mA, plus fail bands at fCustomFailLowPct / fCustomFailHighPct % of the span
  Direct        fRawIn is already the engineering value (Modbus register, BeeBus value, a calculation): no raw
                scaling; the custom fail bands around fValueAtSignalLow..fValueAtSignalHigh and the trim still apply
```

A failure (a fail band, not a number, `bInputGood` FALSE) is ridden through for `set.stSignalFault.tTripDelay` (the last good value held, still good, a warning), then per `set.stSignalFault`: Trip = not good + error, Warn = good (held) + warning, Signal = not good, no alarm. Under / over range is a warning only. `fValue` always holds the last good value. `set.bSensorFitted` FALSE: this input is not on this site: not good, not fitted, no fault.

Second unit: `fValueSecondUnit` = `fValue` * `set.fSecondUnitFactor` + `set.fSecondUnitOffset` (bar to psi: factor 14.5038), also in `sts.fValueSecondUnit`; it follows `fValue` (the held value while the signal has failed). A factor or offset that is not a finite number is a bad setting (put back).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

Placed after it when needed: [`FB_MeasFilter`](FB_MeasFilter.md) (filter, low cut-off, clamp), [`FB_MeasOverride`](FB_MeasOverride.md) (simulate, substitute), [`FB_MeasFrozen`](FB_MeasFrozen.md) (frozen check).

## Example

A 4-20 mA sump level transmitter on the first analog input.

| Pin | Wire |
| --- | --- |
| `fRawIn` | `INT_TO_REAL(%IW0)` (a conversion block in front) |
| `refData` | `stSumpLevel` |
| `stConfig` | `cfgSumpLevel` (the signal type, raw span, unit) |
| `fValue` | a display |

Wire `fbSumpLevel` to the `ipLevel` / `ipMeasurement` pins of the blocks that use the level.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`: an analog input has no switch bands (FB_LevelCheck compares its value)
