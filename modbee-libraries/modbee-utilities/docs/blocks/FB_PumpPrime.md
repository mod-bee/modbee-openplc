# FB_PumpPrime — Pump priming (a part)

Primes a pump at its start: masks the low pressure / no flow checks until the pipe is full (by pressure, flow, a contact or a run time), with a prime timeout.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the pump. The owner's instance |
| in | `ipPressure` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipFlow` | `I_Measurement` |  | optional: the measurement the prime is done by. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `bPrimeDone` | `BOOL` |  | the pipe is filled (eDoneBy Input) |
| in | `refData` | `REFERENCE TO ST_PumpPrimeData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bPriming` | `BOOL` |  | Priming now |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PumpPrimeData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdPrimeNext` | `BOOL` |  | prime on the next start (cleared by the block) |
| `bCmdPrimeCancel` | `BOOL` |  | withdraw it (cleared by the block) |
| `bCmdReset` | `BOOL` |  | reset a latched timeout (cleared by the block) |

**Settings `set`** (`ST_PumpPrimeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEveryStart` | `BOOL` |  | prime at every start |
| `eDoneBy` | `E_PrimeDone` |  |  |
| `fDoneLevel` | `REAL` |  | Pressure / Flow: primed above this |
| `tHold` | `TIME` | `T#2s` | the primed condition must last this long |
| `tRunTime` | `TIME` | `T#30s` | RunTime: primed after running this long |
| `tTimeout` | `TIME` | `T#60s` | priming always ends here |
| `stTimeout` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Retry, tRecover := T#2m, nMaxRetries := 3)` | default Trip, Retry after 2 min, 3 tries; a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_PumpPrimeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPriming` | `BOOL` |  |  |
| `bPrimeNext` | `BOOL` |  | the next start primes |
| `bPrimed` | `BOOL` |  | the last prime was done (FALSE: it timed out) |
| `tTimeLeft` | `TIME` |  | until the timeout (or the run time with RunTime) |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stTimeout` | `ST_ProtectionSts` |  | default Trip, Retry after 2 min, 3 tries; a protection's status ([protections](../conventions.md#protections)) |

## Lists

- `E_PrimeDone`: `Pressure`, `Flow`, `Input`, `RunTime` (default `Pressure`)

## How it works

Priming a pump at its start, as a part of its [`FB_Pump`](FB_Pump.md).

- It primes on every start (`set.bEveryStart`) or on the next one (the record's `bCmdPrimeNext`; `bCmdPrimeCancel` withdraws it before that start, a prime already running carries on). A start is the owner's run command coming on (Evaluate's `bRunning`).
- Done by (`set.eDoneBy`): Pressure / Flow: the measurement good and above `set.fDoneLevel` (a switch measurement with no value: its Low band clear), held `set.tHold`; Input: `bPrimeDone` held `set.tHold`; RunTime: after running `set.tRunTime`.
- While priming the part asks Mask: the pump's mask-at-start checks (low pressure, no flow) ignore their cause (the pump carries a part's Mask into the next scan).
- Priming always ends at `set.tTimeout` (not with RunTime): PrimeTimeout per `set.stTimeout` (default Trip, Retry after 2 min, 3 tries), its cause present until the pump stops.
- Pressure / Flow with that measurement unwired or not fitted: a warning (BadSetting); the prime then ends at its timeout.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump that must prime before its low pressure check counts.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbPump1` |
| `ipPressure` | `fbPressure` |
| `refData` | `stPrime1` |
| `bPriming` | a lamp |

**Back to** [the index](../README.md).
