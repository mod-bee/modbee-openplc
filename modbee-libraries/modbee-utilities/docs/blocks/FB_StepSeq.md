# FB_StepSeq — Step sequence

A timed or conditional step sequence (backwash, CIP, fill-mix-drain): each step switches its outputs and lasts its time or until its condition, with jumps, loops and stop steps.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | held: run from step 1; its drop = a stop |
| in | `bStart` | `BOOL R_EDGE` |  | run from step 1 (resumes an HMI pause) Acts on its rising edge. |
| in | `bStop` | `BOOL R_EDGE` |  | go to the stop step (or end) Acts on its rising edge. |
| in | `bPause` | `BOOL` |  | hold: outputs to nPauseOutputs, time kept |
| in | `bNext` | `BOOL R_EDGE` |  | end this step now (manual stepping) Acts on its rising edge. |
| in | `bReset` | `BOOL R_EDGE` |  | clear a fault Acts on its rising edge. |
| in | `bAbort` | `BOOL` |  | level: end at once, every output off, no stop steps |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE = abort |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE holds back a start |
| in | `refData` | `REFERENCE TO ST_StepSeqData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aStepSet` | `ARRAY[*] OF ST_StepSet` |  | the recipe, one row per step, at most 16 kept |
| in-out | `aStep` | `ARRAY[*] OF ST_Step` |  | each step's live row: the project writes aStep[i].bCond, the step's wait condition |
| in-out | `aOutputs` | `ARRAY[*] OF BOOL` |  | the outputs |
| out | `bBusy` | `BOOL` |  | Running a dose, run or sequence |
| out | `bDone` | `BOOL` |  | one scan: the recipe completed |
| out | `nCurrentStep` | `INT` |  | position running (0 = idle) |
| out | `tRemaining` | `TIME` |  | time left in this step |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StepSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | the HMI commands act once per write, then are cleared |
| `bCmdStop` | `BOOL` |  | Stop (HMI command; acts once, cleared by the block) |
| `bCmdPause` | `BOOL` |  |  |
| `bCmdNext` | `BOOL` |  |  |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |
| `nCmdJump` | `INT` | `-1` | go to this position (start it there when idle); -1 = none |

**Settings `set`** (`ST_StepSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStopStep` | `INT` |  | position of the safe end step for a stop (0 = end at once, outputs off) |
| `nPauseOutputs` | `DWORD` |  | outputs while paused or held on a timeout |

**Status `sts`** (`ST_StepSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nActiveStep` | `INT` |  |  |
| `nCycles` | `UDINT` |  | Cycles completed since power-up |
| `bBusy` | `BOOL` |  | Running a dose, run or sequence |
| `bPaused` | `BOOL` |  | Paused (status) |
| `bStopping` | `BOOL` |  |  |
| `bStepTimeout` | `BOOL` |  |  |
| `nTimedOutStep` | `INT` |  |  |
| `bRecipeBad` | `BOOL` |  |  |
| `nConfigStep` | `INT` |  | the step the recipe problem is in (0 = the recipe as a whole) |
| `eLastResult` | `E_StopReason` |  |  |
| `tElapsed` | `TIME` |  | Time in the step or run so far |
| `tRemaining` | `TIME` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Rows `ST_StepSet` (pin `aStepSet`)

`aStepSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_StepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nOutputs` | `DWORD` |  | bit n = the (n+1)-th output on during this step |
| `tDuration` | `TIME` |  | time in the step (0 = the condition alone) |
| `bWaitCond` | `BOOL` |  | also wait for the step's bCond |
| `tTimeout` | `TIME` |  | the longest time in the step (0 = none) |
| `eOnTimeout` | `E_StepTimeout` |  | Hold (a fault), Next (carry on), Stop (the stop step) |
| `nNext` | `INT` |  | position to go to next (0 = the following step) |
| `nLoops` | `INT` |  | with nNext pointing back: repeat this many times, then carry on |
| `bSkip` | `BOOL` |  | pass over this step |

## Rows `ST_Step` (pin `aStep`)

`aStep` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Step`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCond` | `BOOL` |  |  |
| `bActive` | `BOOL` |  | Active now |
| `nLoopCount` | `INT` |  |  |

## Lists

- `E_StepTimeout`: `Hold`, `Next`, `Stop` (default `Hold`)

## How it works

A timed / conditional step sequence: backwash, CIP, fill-mix-drain, kiln and dryer cycles.

Tables the project declares (VAR_IN_OUT): `aStepSet` (the recipe, one row per step, at most 16 kept), `aStep` (each step's live row: the project writes `aStep`[i].bCond, the step's wait condition), `aOutputs` (the outputs). Each step switches on the outputs in its `nOutputs` pattern (bit n = the n-th element of `aOutputs`, counted from the first) and lasts `tDuration`, or until its `bCond` when `bWaitCond`, or both (the time AND the condition); a step with neither ends on the next scan. `tTimeout` caps a step; `eOnTimeout` then holds there with a fault (outputs to `set.nPauseOutputs` until a reset or `bNext`: StepTimeout), carries on, or goes to the stop step.

Positions count from 1 = the first element. `nNext` (0 = the following step) sends the sequence elsewhere; a jump back repeats `nLoops` times, then carries on (its count restarts each time the loop is left, so loops can nest); a jump back with `nLoops` 0 would never end and is refused (RecipeBad), as is an `nNext` or `set.nStopStep` outside the recipe; `bSkip` steps are passed over. A stop goes to `set.nStopStep` and carries on from there to the end (put the safe end steps last); `nStopStep` 0 ends at once with every output off. `bDone` pulses when the recipe completes without a stop (`sts.nCycles` counts them since power-up). `sts.eLastResult`: Done, Manual (a stop, after the stop steps), Abort, Fault (a step timeout sent to the stop steps, or a bad `nNext` met while running). `bRun` held runs it from step 1 and its drop is a stop; `bInterlock` FALSE acts as `bAbort`; `bPermissive` FALSE holds back a start. `bAbort` (a level) ends a run at once, every output off, no stop steps, and no start or jump while on. `bPause` (or `bCmdPause`, until a start) holds the step: outputs to `nPauseOutputs`, the step's time kept. After a power cut the sequence is idle with every output off and never resumes by itself (`nCmdJump` starts it at any step).

HMI commands act once per write. Kept (a retained last-good copy, restored at power-up, a bad write put back): set, and the recipe rows (up to 16).

## Example

A filter backwash: four steps on three valves. Declare `aStepSet : ARRAY[1..4] OF ST_StepSet`, `aStep : ARRAY[1..4] OF ST_Step` and `aOut : ARRAY[1..3] OF BOOL`.

| Pin | Wire |
| --- | --- |
| `bStart` | `DI_BackwashStart` |
| `bAbort` | `NOT DI_EStopHealthy` |
| `aStepSet` | `aStepSet` |
| `aStep` | `aStep` |
| `aOutputs` | `aOut` |
| `refData` | `stBackwash` |

Then `aOut[1]` drives valve 1, and so on, each on its own rung.

**Back to** [the index](../README.md).
