# FB_AnalogOut — Analog output

An engineering demand to an analog output card: clamp, ramp, a fail value on the interlock, Manual / Auto, the raw value for the card.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | engineering demand (Auto) |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: fFailValue at once (or hold) |
| in | `bManual` | `BOOL` |  | held: Manual while TRUE (a panel switch; not kept) |
| in | `refData` | `REFERENCE TO ST_AnalogOutData` |  | Its record (a variable of this type) |
| in | `stConfig` | `ST_AnalogOutConfig` |  | the card's raw span (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fOut` | `REAL` |  | engineering value actually output |
| out | `nOutRaw` | `UINT` |  | for %QW |
| out | `bLimited` | `BOOL` |  | clamped or ramping |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnalogOutData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdManual` | `BOOL` |  | choose Manual (cleared by the block) |
| `bCmdAuto` | `BOOL` |  | choose Auto (cleared by the block) |
| `bCmdReset` | `BOOL` |  | clear bRefused (cleared by the block) |
| `nRaw` | `UINT` |  | detail: nOutRaw |

**Settings `set`** (`ST_AnalogOutSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fEngMin` | `REAL` |  | engineering value at fRawMin |
| `fEngMax` | `REAL` | `100.0` | engineering value at fRawMax |
| `fOutMin` | `REAL` |  | lowest output (clamp) |
| `fOutMax` | `REAL` | `100.0` | highest output (clamp) |
| `fRampUp` | `REAL` |  | engineering units per eRateUnit rising (0 = off) |
| `fRampDown` | `REAL` |  | falling (0 = off) |
| `eRateUnit` | `E_RateUnit` |  |  |
| `fFailValue` | `REAL` |  | output while bInterlock is FALSE |
| `bHoldOnInterlock` | `BOOL` |  | TRUE: hold the output instead |
| `bManual` | `BOOL` |  | Manual chosen (kept) |
| `fManualValue` | `REAL` |  | output in Manual (kept) |

**Status `sts`** (`ST_AnalogOutSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOut` | `REAL` |  | the engineering value output |
| `bManual` | `BOOL` |  | in Manual now (pin or kept choice) |
| `bBadInput` | `BOOL` |  | the demand is not a number: output held |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by bCmdReset) |

## Constants `ST_AnalogOutConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_AnalogOutConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawMin` | `REAL` |  | raw value at fEngMin |
| `fRawMax` | `REAL` | `65535.0` | raw value at fEngMax |

## How it works

An engineering demand to an analog output card.

Auto: `fOut` follows `fIn`. Manual (the `bManual` pin held, or the kept choice `set.bManual` from `bCmdManual` / `bCmdAuto`): `fOut` is `set.fManualValue`; at the change to Manual, `fManualValue` takes the present `fOut` (bumpless). The demand is clamped to `fOutMin`..fOutMax and ramped by `fRampUp` / `fRampDown` (engineering units per `eRateUnit`; 0 = no ramp; [`FB_Ramp`](FB_Ramp.md), exact at any rate). `bInterlock` FALSE gives `fFailValue` at once (or holds), in Manual too; when it returns the output ramps back from there. A NaN demand holds the output (warning ValueBad). `nOutRaw` = `fRawMin`..fRawMax over `fEngMin`..fEngMax, clamped to 0..65535. A span that is not usable: `bError` BadSetting, `fOut` at `fEngMin`. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A speed reference to a 0-10 V output.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbLoop.fSpeed` |
| `bInterlock` | `fbSystem.bNotOff` |
| `refData` | `stAo1` |
| `stConfig` | `cfgAo1` |
| `nOutRaw` | `%QW0` |

**Back to** [the index](../README.md).
