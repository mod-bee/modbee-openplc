# FB_RunPause — Run pause and resume (a part)

An operator pause and resume for a run, added to it. The pause ends with the run.

It is a **part**: it adds itself to its run (`ipRun`) and acts through the run. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. An instance of a block that offers I_Run (FB_Run) |
| in | `bPauseRun` | `BOOL R_EDGE` |  | rising edge: pause the run |
| in | `bResumeRun` | `BOOL R_EDGE` |  | rising edge: resume the run |
| in | `refData` | `REFERENCE TO ST_RunPauseData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bPaused` | `BOOL` |  | the run is paused |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunPauseData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdPause` | `BOOL` |  | cleared by the block |
| `bCmdResumeRun` | `BOOL` |  | cleared by the block |

**Status `sts`** (`ST_RunPauseSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPaused` | `BOOL` |  | the run is paused |

## How it works

Operator pause / resume of a run. `bPauseRun` (a rising edge, or the record's `bCmdPause`) pauses the run it belongs to; `bResumeRun` (or `bCmdResumeRun`) carries on. The pause ends with the run: a run that ends (done, aborted, its maximum time or [`FB_Run`](FB_Run.md)'s own `set.tMaxPauseBeforeEnd`) leaves no pause behind for the next one (no rung work-around needed). While paused the run is paused through the part list (`E_PartAction.Stop`): no run command, no counting.

## Example

A pause / resume pair of buttons on the panel.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `bPauseRun` | `DI_PausePB` |
| `bResumeRun` | `DI_ResumePB` |
| `refData` | `stRunPause` |

**Back to** [the index](../README.md).
