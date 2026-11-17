# FB_RunPause — Run pause and resume (a part)

An operator pause and resume for a run, added to it. The pause ends with the run.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. The FB_Run instance |
| in | `bPause` | `BOOL R_EDGE` |  | a rising edge, or the record's bCmdPause Acts on its rising edge. |
| in | `bResume` | `BOOL R_EDGE` |  | or bCmdResume Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_RunPauseData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bPaused` | `BOOL` |  | Paused (status) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunPauseData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdPause` | `BOOL` |  | cleared by the block |
| `bCmdResume` | `BOOL` |  | cleared by the block |
| `bPaused` | `BOOL` |  | status |

## How it works

Operator pause / resume of a run. `bPause` (a rising edge, or the record's `bCmdPause`) pauses the run it belongs to; `bResume` (or `bCmdResume`) carries on. The pause ends with the run: a run that ends (done, aborted, its maximum time or [`FB_Run`](FB_Run.md)'s own `set.tMaxPause`) leaves no pause behind for the next one (no rung work-around needed). While paused the run is paused through the part list (`E_PartAction.Stop`): no run command, no counting.

## Example

A pause / resume pair of buttons on the panel.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `bPause` | `DI_PausePB` |
| `bResume` | `DI_ResumePB` |
| `refData` | `stRunPause` |

**Back to** [the index](../README.md).
