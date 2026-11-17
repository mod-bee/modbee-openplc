# FB_AnalogIn — Analog input

An analog reading to an engineering value with its health: 4-20 mA (NE43 fail bands), 0-20 mA, 0-10 V, custom or a value already in units, with a fault ride-through.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | raw value; the engineering value itself with Direct |
| in | `bInGood` | `BOOL` | `TRUE` | the source is healthy (IO module, comms, device) |
| in | `refData` | `REFERENCE TO ST_AnalogInData` |  | Its record (a variable of this type) |
| in | `stConfig` | `ST_AnalogInConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fValue` | `REAL` |  | engineering value; the last good one while the signal has failed |
| out | `fPercent` | `REAL` |  | fValue as a % of fEngMin..fEngMax |
| out | `fValueAlt` | `REAL` |  | fValue in the second unit (set.fAltFactor, fAltOffset) |
| out | `bGood` | `BOOL` |  | fValue is usable |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnalogInData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a latched fault (cleared by the block) |

**Settings `set`** (`ST_AnalogInSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bFitted` | `BOOL` | `TRUE` | FALSE: not on this site (not good, no fault) |
| `fEngMin` | `REAL` |  | engineering value at fRawMin |
| `fEngMax` | `REAL` | `100.0` | engineering value at fRawMax |
| `fTrim` | `REAL` |  | field zero trim, engineering units |
| `fAltFactor` | `REAL` | `1.0` | fValueAlt = fValue * fAltFactor + fAltOffset (a second unit) |
| `fAltOffset` | `REAL` |  | bar to psi: factor 14.5038 |
| `stFault` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#2s, eReset := E_ResetMode.Auto, tRecover := T#2s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_AnalogInSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | engineering value |
| `fValueAlt` | `REAL` |  | the value in the second unit |
| `bGood` | `BOOL` |  | The value can be trusted |
| `eSignal` | `E_AiStatus` |  |  |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `stFault` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_AnalogInDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRaw` | `REAL` |  |  |
| `fPercent` | `REAL` |  | of the span |

## Constants `ST_AnalogInConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_AnalogInConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSignal` | `E_AiSignal` |  |  |
| `fRawMin` | `REAL` |  | raw value at the bottom of the signal (4 mA, 0 mA, 0 V) |
| `fRawMax` | `REAL` | `65535.0` | raw value at the top of the signal (20 mA, 10 V) |
| `eUnit` | `E_Unit` |  | unit of fValue |
| `fCustomLowFail` | `REAL` | `-5.0` | Custom / Direct: fail low at or below this % of the span |
| `fCustomHighFail` | `REAL` | `105.0` | Custom / Direct: fail high at or above this % of the span |
| `tRetryWindow` | `TIME` | `T#1h` | a Retry fault counts its trips within this window |

## Lists

- `E_AiSignal`: `Current4To20`, `Current0To20`, `Voltage0To10`, `Custom`, `Direct` (default `Current4To20`)
- `E_AiStatus`: `Ok`, `UnderRange`, `OverRange`, `FailLow`, `FailHigh`, `InputBad`, `NotFitted` (default `Ok`)

## How it works

A raw analog reading (or a remote / computed value) to an engineering value with its health. Wire the instance to any `I_Measurement` pin.

Signal types (`stConfig.eSignal`); `fRawMin` / `fRawMax` are the raw values at the bottom and top of the signal:

```
  Current4To20  NE43: <= 3.6 mA fail low, 3.6-3.8 under range, 3.8-20.5 measurement, 20.5-21 over range,
                >= 21 fail high
  Current0To20, below 0 % / above 100 % of the span is under / over range (no fail bands: a live zero
  Voltage0To10  is needed to see a wire break)
  Custom        as 0-20 mA, plus fail bands at fCustomLowFail / fCustomHighFail % of the span
  Direct        fIn is already the engineering value (Modbus register, BeeBus value, a calculation): no raw
                scaling; the custom fail bands around fEngMin..fEngMax and the trim still apply
```

A failure (a fail band, not a number, `bInGood` FALSE) is ridden through for `set.stFault.tDelay` (the last good value held, still good, a warning), then per `set.stFault`: Trip = not good + error, Warn = good (held) + warning, Signal = not good, no alarm. Under / over range is a warning only. `fValue` always holds the last good value. `set.bFitted` FALSE: this input is not on this site: not good, not fitted, no fault.

Second unit: `fValueAlt` = `fValue` * `set.fAltFactor` + `set.fAltOffset` (bar to psi: factor 14.5038), also in `sts.fValueAlt`; it follows `fValue` (the held value while the signal has failed). A factor or offset that is not a finite number is a bad setting (put back).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

Moved out (decorators placed after it): filter, low cut-off, clamp, simulate, substitute, frozen check.

## Example

A 4-20 mA sump level transmitter on the first analog input.

| Pin | Wire |
| --- | --- |
| `fIn` | `INT_TO_REAL(%IW0)` (a conversion block in front) |
| `refData` | `stSumpLevel` |
| `stConfig` | `cfgSumpLevel` (the signal type, raw span, unit) |
| `fValue` | a display |

Wire `fbSumpLevel` to the `ipLevel` / `ipMeas` pins of the blocks that use the level.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`: an analog input has no switch bands (FB_LevelCheck compares its value)

**Back to** [the index](../README.md).
