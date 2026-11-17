# FB_MotorSimulate — Simulation of feedback

Tests a motor or valve without the plant: while simulating, the feedback follows the block's own output, with a warning so it is never mistaken for the real thing.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bQ` | `BOOL` | `FALSE` | the block's output (motor bQ, valve bOut ...) |
| in | `bRealFeedback` | `BOOL` |  | the field feedback contact |
| in | `refData` | `REFERENCE TO ST_MotorSimulateData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bFeedback` | `BOOL` |  | -> the block's feedback pin |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorSimulateData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSimulate` | `BOOL` |  | feedback follows the output (not kept) |

## How it works

Test equipment without the plant. Put it between the field feedback and the block's feedback pin: `bFeedback` := `bRealFeedback` normally; while the record's `bSimulate` is on, `bFeedback` follows `bQ` (the block's own output, one scan later), as if the contactor / valve answered. `bSimulate` is not kept: it is off after a power cut, and a reset of the system clears it. While it is on: a warning (Simulated), so a simulated machine is never mistaken for a real one.

## Example

Commissioning a motor before the contactor is wired.

| Pin | Wire |
| --- | --- |
| `bQ` | `fbMotor1.bQ` |
| `bRealFeedback` | `DI_M1_Aux` |
| `refData` | `stSim1` |
| `bFeedback` | the motor's `bFeedback` |

Set `stSim1.bSimulate := TRUE` from the HMI to simulate; it is off after a power cut.

**Back to** [the index](../README.md).
