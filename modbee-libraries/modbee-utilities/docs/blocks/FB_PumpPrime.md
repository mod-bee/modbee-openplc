# FB_PumpPrime — Pump priming (a part)

Primes a pump at its start: masks the low pressure / no flow checks until the pipe is full (by pressure, flow, a contact or a run time), with a prime timeout.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the pump. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `ipPressure` | `I_Measurement` |  | the pressure the prime is proved by (optional). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipFlow` | `I_Measurement` |  | the flow the prime is proved by (optional). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bPipeFilled` | `BOOL` |  | the pipe is filled (ePrimeDoneBy Input) |
| in | `refData` | `REFERENCE TO ST_PumpPrimeData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bPriming` | `BOOL` |  | priming now |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PumpPrimeData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdPrimeNext` | `BOOL` |  | prime on the next start (cleared by the block) |
| `bCmdPrimeCancel` | `BOOL` |  | withdraw it (cleared by the block) |
| `bCmdResetFaults` | `BOOL` |  | reset a latched timeout (cleared by the block) |

**Settings `set`** (`ST_PumpPrimeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPrimeEveryStart` | `BOOL` |  | prime at every start |
| `ePrimeDoneBy` | `E_PrimeDone` |  | what proves the prime: Pressure, Flow, Input or RunTime |
| `fPrimedAbove` | `REAL` |  | Pressure / Flow: primed above this |
| `tPrimedHoldTime` | `TIME` | `T#2s` | the primed condition must last this long |
| `tPrimeRunTime` | `TIME` | `T#30s` | RunTime: primed after running this long |
| `tPrimeTimeout` | `TIME` | `T#60s` | priming always ends here |
| `stPrimeTimeoutFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#2m, nMaxRetriesBeforeLockout := 3)` | the prime did not finish in time (default Trip, Retry after 2 min, 3 tries); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_PumpPrimeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPriming` | `BOOL` |  | priming now |
| `bPrimeNext` | `BOOL` |  | the next start primes |
| `bPrimed` | `BOOL` |  | the last prime was done (FALSE: it timed out) |
| `tTimeLeft` | `TIME` |  | until the timeout (or the run time with RunTime) |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stPrimeTimeoutFault` | `ST_ProtectionSts` |  | the prime did not finish in time (default Trip, Retry after 2 min, 3 tries); a protection's status ([protections](../conventions.md#protections)) |

## Lists

- `E_PrimeDone`: `Pressure`, `Flow`, `Input`, `RunTime` (default `Pressure`)

## How it works

Priming a pump at its start, as a part of its [`FB_Pump`](FB_Pump.md).

- It primes on every start (`set.bPrimeEveryStart`) or on the next one (the record's `bCmdPrimeNext`; `bCmdPrimeCancel` withdraws it before that start, a prime already running carries on). A start is the owner's run command coming on (Evaluate's `bOwnerRunCommand`).
- Done by (`set.ePrimeDoneBy`): Pressure / Flow: the measurement good and above `set.fPrimedAbove` (a switch measurement with no value: its Low band clear), held `set.tPrimedHoldTime`; Input: `bPipeFilled` held `set.tPrimedHoldTime`; RunTime: after running `set.tPrimeRunTime`.
- While priming the part asks Mask: the pump's mask-at-start checks (low pressure, no flow) ignore their cause (the pump carries a part's Mask into the next scan).
- Priming always ends at `set.tPrimeTimeout` (not with RunTime): PrimeTimeout per `set.stPrimeTimeoutFault` (default Trip, Retry after 2 min, 3 tries), its cause present until the pump stops.
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
