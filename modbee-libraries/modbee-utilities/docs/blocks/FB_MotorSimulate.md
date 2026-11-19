# FB_MotorSimulate — Simulation of feedback

Tests a motor or valve without the plant: while simulating, the feedback follows the block's own output, with a warning so it is never mistaken for the real thing.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bOutput` | `BOOL` | `FALSE` | the block's output (motor bOutput, valve bOutput ...) |
| in | `bFieldFeedback` | `BOOL` |  | the field feedback contact |
| in | `refData` | `REFERENCE TO ST_MotorSimulateData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bFeedback` | `BOOL` |  | -> the block's feedback pin |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorSimulateData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSimulateFeedback` | `BOOL` |  | feedback follows the output (not kept) |

## How it works

Test equipment without the plant. Put it between the field feedback and the block's feedback pin: `bFeedback` := `bFieldFeedback` normally; while the record's `bSimulateFeedback` is on, `bFeedback` follows `bOutput` (the block's own output, one scan later), as if the contactor / valve answered. `bSimulateFeedback` is not kept: it is off after a power cut, and a reset of the system clears it. While it is on: a warning (Simulated), so a simulated machine is never mistaken for a real one.

## Example

Commissioning a motor before the contactor is wired.

| Pin | Wire |
| --- | --- |
| `bOutput` | `fbMotor1.bRunOutput` |
| `bFieldFeedback` | `DI_M1_Aux` |
| `refData` | `stSim1` |
| `bFeedback` | the motor's `bFeedback` |

Set `stSim1.bSimulateFeedback := TRUE` from the HMI to simulate; it is off after a power cut.

**Back to** [the index](../README.md).
