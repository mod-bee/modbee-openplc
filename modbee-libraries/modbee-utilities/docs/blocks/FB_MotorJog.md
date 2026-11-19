# FB_MotorJog — Jog (inch) button

A held jog (inch) button for a motor in Hand: the motor runs while the button is held, and stops when it is let go.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bJogButton` | `BOOL` | `FALSE` | the held jog button |
| in | `bJogReverse` | `BOOL` |  | jog in reverse (a reversing motor, FB_MotorRev) |
| in | `ipMotor` | `I_Motor` |  | required. An instance of a block that offers I_Motor (FB_Motor, FB_Motor2Speed, FB_MotorRev, FB_MotorStarDelta, FB_MotorVsd, ...) |
| in | `refData` | `REFERENCE TO ST_MotorJogData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bJogging` | `BOOL` |  | the jog is being sent |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorJogData` (pin `refData`)

**Settings `set`** (`ST_MotorJogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tMaxJogTime` | `TIME` |  | longest jog (0 = no limit) |

**Status `sts`** (`ST_MotorJogSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bJogTimeUp` | `BOOL` |  | tMaxJogTime ended the jog: release bJogButton |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

A held jog (inch) button for a motor in Hand.

While `bJogButton` is held and the motor is in Hand (and not already running from a Hand start), the motor runs: past its trips, restart delay and permissive; only Off and the motor's `bInterlock` stop it. Releasing `bJogButton` stops it at once. `set.tMaxJogTime` (0 = none) ends a jog that is held too long; `bJogButton` must be released before the next.

A jog is a held button on the panel only: an HMI cannot hold a jog (a lost link would keep it running).

## Example

A conveyor with a jog button on the panel door.

| Pin | Wire |
| --- | --- |
| `bJogButton` | `DI_JogPB` (held) |
| `ipMotor` | `fbConveyor` |
| `refData` | `stJog` |

Put the motor in Hand to jog. Set `stJog.set.tMaxJogTime` to end a jog held too long.

**Back to** [the index](../README.md).
