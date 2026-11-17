# FB_StarterSoft — Soft starter top of ramp (a part)

A soft starter's top-of-ramp check, added to its motor as a part: a start that never reaches full speed trips the motor.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bTopOfRamp` | `BOOL` | `FALSE` | the starter's top-of-ramp relay (TRUE = at full speed) |
| in | `ipOwner` | `I_Equipment` |  | the motor (required). The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_StarterSoftData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bAtSpeed` | `BOOL` |  |  |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StarterSoftData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset its trip once the cause has gone (cleared by the block) |
| `stStartTooLong` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bAtSpeed` | `BOOL` |  | status: top of ramp |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_StarterSoftSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stStartTooLong` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#15s, eReset := E_ResetMode.Manual)` | a protection's settings ([protections](../conventions.md#protections)) |

## How it works

A soft starter's top-of-ramp check, as a part of its motor. The starter's run relay is the motor's `bFeedback`, its fault relay an [`FB_Protection`](FB_Protection.md) (`eErrorId` DriveFault). This part watches the top-of-ramp relay: the motor's run command on and no top of ramp for `set.stStartTooLong`'s delay is a trip (StartTooLong: the ramp never finished, a stalled or overloaded start). `bTopOfRamp` is the starter's top-of-ramp / bypass relay, TRUE = at full speed.

A soft stop: set the motor's `stStuck` delay longer than the starter's stop ramp (the run relay stays on while it ramps down).

## Example

A soft starter with a top-of-ramp relay.

| Pin | Wire |
| --- | --- |
| `bTopOfRamp` | `DI_SS1_TopOfRamp` |
| `ipOwner` | `fbMotor1` |
| `refData` | `stSoft1` |

The starter's run relay goes to the motor's `bFeedback`, its fault relay to an FB_Protection.

**Back to** [the index](../README.md).
