# FB_MotorJog — Jog (inch) button

A held jog (inch) button for a motor in Hand: the motor runs while the button is held, and stops when it is let go.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bJog` | `BOOL` | `FALSE` | the held jog button |
| in | `bJogRev` | `BOOL` |  | jog in reverse (a reversing motor, FB_MotorRev) |
| in | `ipMotor` | `I_Equipment` |  | required. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_MotorJogData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bJogging` | `BOOL` |  | the jog is being sent |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorJogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLimited` | `BOOL` |  | tJogMax ended the jog: release bJog |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Settings `set`** (`ST_MotorJogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tJogMax` | `TIME` |  | longest jog (0 = no limit) |

## How it works

A held jog (inch) button for a motor in Hand.

While `bJog` is held and the motor is in Hand (and not already running from a Hand start), the motor runs: past its trips, restart delay and permissive; only Off and the motor's `bInterlock` stop it. Releasing `bJog` stops it at once. `set.tJogMax` (0 = none) ends a jog that is held too long; `bJog` must be released before the next.

A jog is a held button on the panel only: an HMI cannot hold a jog (a lost link would keep it running).

## Example

A conveyor with a jog button on the panel door.

| Pin | Wire |
| --- | --- |
| `bJog` | `DI_JogPB` (held) |
| `ipMotor` | `fbConveyor` |
| `refData` | `stJog` |

Put the motor in Hand to jog. Set `stJog.set.tJogMax` to end a jog held too long.

**Back to** [the index](../README.md).
