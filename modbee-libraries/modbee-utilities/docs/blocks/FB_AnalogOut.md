# FB_AnalogOut — Analog output

An engineering demand to an analog output card: clamp, ramp, a fail value on the interlock, Manual / Auto, the raw value for the card.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fAutoDemand` | `REAL` |  | engineering demand (Auto) |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: fValueWhenInterlocked at once (or hold) |
| in | `bSelectorManual` | `BOOL` |  | held: Manual while TRUE (a panel switch; not kept) |
| in | `refData` | `REFERENCE TO ST_AnalogOutData` |  | the block's record |
| in | `stConfig` | `ST_AnalogOutConfig` |  | the card's raw span (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fOutput` | `REAL` |  | engineering value actually output |
| out | `nRawOutput` | `UINT` |  | for %QW |
| out | `bClampedOrRamping` | `BOOL` |  | clamped or ramping |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnalogOutData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdSelectManual` | `BOOL` |  | choose Manual (cleared by the block) |
| `bCmdSelectAuto` | `BOOL` |  | choose Auto (cleared by the block) |
| `bCmdClearRefused` | `BOOL` |  | clear bSettingRefused (cleared by the block) |
| `nRawOutput` | `UINT` |  | detail: nRawOutput |

**Settings `set`** (`ST_AnalogOutSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValueAtSignalLow` | `REAL` |  | engineering value at fRawAtSignalLow |
| `fValueAtSignalHigh` | `REAL` | `100.0` | engineering value at fRawAtSignalHigh |
| `fMinOutput` | `REAL` |  | lowest output (clamp) |
| `fMaxOutput` | `REAL` | `100.0` | highest output (clamp) |
| `fRampUpRate` | `REAL` |  | engineering units per eRateUnit rising (0 = off) |
| `fRampDownRate` | `REAL` |  | falling (0 = off) |
| `eRateUnit` | `E_RateUnit` |  | the time unit of the ramp rates: per second, minute, hour or day |
| `fValueWhenInterlocked` | `REAL` |  | output while bInterlock is FALSE |
| `bHoldWhenInterlocked` | `BOOL` |  | TRUE: hold the output instead |
| `bManualSelected` | `BOOL` |  | Manual chosen (kept) |
| `fManualOutput` | `REAL` |  | output in Manual (kept) |

**Status `sts`** (`ST_AnalogOutSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOutput` | `REAL` |  | the value output (engineering units) |
| `bInManual` | `BOOL` |  | in Manual now (pin or kept choice) |
| `bDemandNotANumber` | `BOOL` |  | the demand is not a number: output held |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by bCmdClearRefused) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Constants `ST_AnalogOutConfig` (pin `stConfig`)

**Fields** (`ST_AnalogOutConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawAtSignalLow` | `REAL` |  | raw value at fValueAtSignalLow |
| `fRawAtSignalHigh` | `REAL` | `65535.0` | raw value at fValueAtSignalHigh |

Set once, at the variable's declaration (engineering constants, not changed while running).

## How it works

An engineering demand to an analog output card.

Auto: `fOutput` follows `fAutoDemand`. Manual (the `bSelectorManual` pin held, or the kept choice `set.bManualSelected` from `bCmdSelectManual` / `bCmdSelectAuto`): `fOutput` is `set.fManualOutput`; at the change to Manual, `fManualOutput` takes the present `fOutput` (bumpless). The demand is clamped to `fMinOutput`..fMaxOutput and ramped by `fRampUpRate` / `fRampDownRate` (engineering units per `eRateUnit`; 0 = no ramp; [`FB_Ramp`](FB_Ramp.md), exact at any rate). `bInterlock` FALSE gives `fValueWhenInterlocked` at once (or holds), in Manual too; when it returns the output ramps back from there. A NaN demand holds the output (warning ValueBad). `nRawOutput` = `fRawAtSignalLow`..fRawAtSignalHigh over `fValueAtSignalLow`..fValueAtSignalHigh, clamped to 0..65535. A span that is not usable: `bError` BadSetting, `fOutput` at `fValueAtSignalLow`. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A speed reference to a 0-10 V output.

| Pin | Wire |
| --- | --- |
| `fAutoDemand` | `fbLoop.fSpeedSetpointPct` |
| `bInterlock` | `fbSystem.bNotOff` |
| `refData` | `stAo1` |
| `stConfig` | `cfgAo1` |
| `nRawOutput` | `%QW0` |

**Back to** [the index](../README.md).
