# FB_StepSeq — Step sequence

A timed or conditional step sequence (backwash, CIP, fill-mix-drain): each step switches its outputs and lasts its time or until its condition, with jumps, loops and stop steps.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | held: run from step 1; its drop = a stop |
| in | `bStart` | `BOOL R_EDGE` |  | run from step 1 (resumes an HMI pause) |
| in | `bStop` | `BOOL R_EDGE` |  | go to the stop step (or end) |
| in | `bPause` | `BOOL` |  | hold: outputs to nOutputsWhilePaused, time kept |
| in | `bNextStep` | `BOOL R_EDGE` |  | end this step now (manual stepping) |
| in | `bResetFaults` | `BOOL R_EDGE` |  | clear a fault |
| in | `bAbortWhileHeld` | `BOOL` |  | level: end at once, every output off, no stop steps |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE = abort |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE holds back a start |
| in | `refData` | `REFERENCE TO ST_StepSeqData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aStepSettings` | `ARRAY[*] OF ST_StepSet` |  | the recipe, one row per step (at most 16 kept) |
| in-out | `aSteps` | `ARRAY[*] OF ST_Step` |  | each step's live row: the project writes aSteps[i].bStepCondition |
| in-out | `aOutputs` | `ARRAY[*] OF BOOL` |  | the outputs the steps switch |
| out | `bBusy` | `BOOL` |  | the recipe is running |
| out | `bDone` | `BOOL` |  | one scan: the recipe completed |
| out | `nCurrentStep` | `INT` |  | position running (0 = idle) |
| out | `tTimeLeft` | `TIME` |  | time left in this step |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StepSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | the HMI commands act once per write, then are cleared |
| `bCmdStop` | `BOOL` |  | HMI: stop (acts once, cleared by the block) |
| `bCmdPause` | `BOOL` |  | HMI: pause (acts once, cleared by the block) |
| `bCmdNextStep` | `BOOL` |  | HMI: end this step now (acts once) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `nCmdJumpToStep` | `INT` | `-1` | go to this position (start it there when idle); -1 = none |

**Settings `set`** (`ST_StepSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nSafeStopStep` | `INT` |  | position of the safe end step for a stop (0 = end at once, outputs off) |
| `nOutputsWhilePaused` | `DWORD` |  | outputs while paused or held on a timeout |

**Status `sts`** (`ST_StepSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCurrentStep` | `INT` |  | the step running now (0 = idle) |
| `nCycleCount` | `UDINT` |  | cycles completed since power-up |
| `bBusy` | `BOOL` |  | the recipe is running |
| `bPaused` | `BOOL` |  | paused |
| `bStopping` | `BOOL` |  | running the stop steps |
| `bStepTimedOut` | `BOOL` |  | a step timed out (held as a fault) |
| `nTimedOutStep` | `INT` |  | the step that timed out |
| `bRecipeBad` | `BOOL` |  | the recipe has a bad setting |
| `nBadRecipeStep` | `INT` |  | the step the recipe problem is in (0 = the recipe as a whole) |
| `eStopReason` | `E_StopReason` |  | how the last cycle ended |
| `tElapsedTime` | `TIME` |  | time in the step so far |
| `tTimeLeft` | `TIME` |  | time left in the step |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_StepSet` (pin `aStepSettings`)

`aStepSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_StepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nOutputBits` | `DWORD` |  | bit n = the (n+1)-th output on during this step |
| `tStepTime` | `TIME` |  | time in the step (0 = the condition alone) |
| `bWaitForCondition` | `BOOL` |  | also wait for the step's bStepCondition |
| `tStepTimeout` | `TIME` |  | the longest time in the step (0 = none) |
| `eWhenTimedOut` | `E_StepTimeout` |  | Hold (a fault), Next (carry on), Stop (the stop step) |
| `nNextStep` | `INT` |  | position to go to next (0 = the following step) |
| `nLoops` | `INT` |  | with nNextStep pointing back: repeat this many times, then carry on |
| `bSkipStep` | `BOOL` |  | pass over this step |

## Rows `ST_Step` (pin `aSteps`)

`aSteps` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Step`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bStepCondition` | `BOOL` |  | the project writes it: the step's wait condition |
| `bStepActive` | `BOOL` |  | this step runs now |
| `nLoopCount` | `INT` |  | loops done on this step |

## Lists

- `E_StepTimeout`: `Hold`, `Next`, `Stop` (default `Hold`)

## How it works

A timed / conditional step sequence: backwash, CIP, fill-mix-drain, kiln and dryer cycles.

Tables the project declares (VAR_IN_OUT): `aStepSettings` (the recipe, one row per step, at most 16 kept), `aSteps` (each step's live row: the project writes `aSteps`[i].bStepCondition, the step's wait condition), `aOutputs` (the outputs). Each step switches on the outputs in its `nOutputBits` pattern (bit n = the n-th element of `aOutputs`, counted from the first) and lasts `tStepTime`, or until its `bStepCondition` when `bWaitForCondition`, or both (the time AND the condition); a step with neither ends on the next scan. `tStepTimeout` caps a step; `eWhenTimedOut` then holds there with a fault (outputs to `set.nOutputsWhilePaused` until a reset or `bNextStep`: StepTimeout), carries on, or goes to the stop step.

Positions count from 1 = the first element. `nNextStep` (0 = the following step) sends the sequence elsewhere; a jump back repeats `nLoops` times, then carries on (its count restarts each time the loop is left, so loops can nest); a jump back with `nLoops` 0 would never end and is refused (RecipeBad), as is an `nNextStep` or `set.nSafeStopStep` outside the recipe; `bSkipStep` steps are passed over. A stop goes to `set.nSafeStopStep` and carries on from there to the end (put the safe end steps last); `nSafeStopStep` 0 ends at once with every output off. `bDone` pulses when the recipe completes without a stop (`sts.nCycleCount` counts them since power-up). `sts.eStopReason`: Done, Manual (a stop, after the stop steps), Abort, Fault (a step timeout sent to the stop steps, or a bad `nNextStep` met while running). `bRun` held runs it from step 1 and its drop is a stop; `bInterlock` FALSE acts as `bAbortWhileHeld`; `bPermissive` FALSE holds back a start. `bAbortWhileHeld` (a level) ends a run at once, every output off, no stop steps, and no start or jump while on. `bPause` (or `bCmdPause`, until a start) holds the step: outputs to `nOutputsWhilePaused`, the step's time kept. After a power cut the sequence is idle with every output off and never resumes by itself (`nCmdJumpToStep` starts it at any step).

HMI commands act once per write. Kept (a retained last-good copy, restored at power-up, a bad write put back): set, and the recipe rows (up to 16).

## Example

A filter backwash: four steps on three valves. Declare `aStepSettings : ARRAY[1..4] OF ST_StepSet`, `aSteps : ARRAY[1..4] OF ST_Step` and `aOut : ARRAY[1..3] OF BOOL`.

| Pin | Wire |
| --- | --- |
| `bStart` | `DI_BackwashStart` |
| `bAbortWhileHeld` | `NOT DI_EStopHealthy` |
| `aStepSettings` | `aStepSettings` |
| `aSteps` | `aSteps` |
| `aOutputs` | `aOut` |
| `refData` | `stBackwash` |

Then `aOut[1]` drives valve 1, and so on, each on its own rung.

**Back to** [the index](../README.md).
