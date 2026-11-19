# FB_StarterSoft — Soft starter top of ramp (a part)

A soft starter's top-of-ramp check, added to its motor as a part: a start that never reaches full speed trips the motor.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bTopOfRamp` | `BOOL` | `FALSE` | the starter's top-of-ramp relay (TRUE = at full speed) |
| in | `ipOwner` | `I_Equipment` |  | the motor (required) |
| in | `refData` | `REFERENCE TO ST_StarterSoftData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bAtTopOfRamp` | `BOOL` |  | the starter is at full speed |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StarterSoftData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset its trip once the cause has gone (cleared by the block) |

**Settings `set`** (`ST_StarterSoftSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stStartTooLongFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#15s, eResetMode := E_ResetMode.Manual)` | top of ramp not reached in time; a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_StarterSoftSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stStartTooLongFault` | `ST_ProtectionSts` |  | top of ramp not reached in time; a protection's status ([protections](../conventions.md#protections)) |
| `bAtTopOfRamp` | `BOOL` |  | status: top of ramp |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

A soft starter's top-of-ramp check, as a part of its motor. The starter's run relay is the motor's `bRunFeedback`, its fault relay an [`FB_Protection`](FB_Protection.md) (`eErrorId` DriveFault). This part watches the top-of-ramp relay: the motor's run command on and no top of ramp for `set.stStartTooLongFault`'s delay is a trip (StartTooLong: the ramp never finished, a stalled or overloaded start). `bTopOfRamp` is the starter's top-of-ramp / bypass relay, TRUE = at full speed.

A soft stop: set the motor's `stStuckOnFault` delay longer than the starter's stop ramp (the run relay stays on while it ramps down).

## Example

A soft starter with a top-of-ramp relay.

| Pin | Wire |
| --- | --- |
| `bTopOfRamp` | `DI_SS1_TopOfRamp` |
| `ipOwner` | `fbMotor1` |
| `refData` | `stSoft1` |

The starter's run relay goes to the motor's `bRunFeedback`, its fault relay to an FB_Protection.

**Back to** [the index](../README.md).
