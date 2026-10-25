# UT_STEP_SEQ — Timed / conditional step sequence

Runs a recipe of steps, each switching a set of outputs on for a time and/or until a
condition is met. Used for filter backwash, dairy CIP and vat wash cycles, tank
fill-mix-drain cycles, kiln and dryer cycles, and any "do this, then this" process.
Steps can jump and loop, and every step can have a timeout. A stop goes through a safe
end step (e.g. drain) rather than just dropping everything.

(For starting a chain of machines with feedbacks, use [UT_SEQUENCER](UT_SEQUENCER.md).)

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Start` | BOOL | FALSE | Rising edge: run from step 1 (also resumes an HMI pause) |
| in | `Stop` | BOOL | FALSE | Rising edge: go to `stopStep` (or end at once) |
| in | `Pause` | BOOL | FALSE | Hold. Outputs go to `pauseOutputs`, the step's time is kept |
| in | `Next` | BOOL | FALSE | Rising edge: end this step now (manual stepping, commissioning) |
| in | `Reset` | BOOL | FALSE | Rising edge: clear a fault |
| in | `Abort` | BOOL | FALSE | Level (e.g. `NOT EStopOk`): end at once with every output off, no stop steps; no start or jump while on |
| out | `Busy` | BOOL | | |
| out | `Done` | BOOL | | One scan when the recipe completes (not after a stop) |
| out | `CurrentStep` | INT | | Position running (0 = idle) |
| out | `Remaining` | TIME | | Time left in this step (time-based steps) |
| out | `Fault` | BOOL | | |
| inout | `Steps` | ARRAY[*] OF UT_STEP | | The recipe |
| inout | `Outputs` | ARRAY[*] OF BOOL | | Up to 32 outputs driven by the step patterns (elements past 32 stay off) |
| inout | `Data` | UT_STEP_SEQ_DATA | | |

Steps are numbered by **position**, 1 = the first element whatever the array's lower
bound; `next`, `stopStep`, `cmdJump`, `CurrentStep` and `timedOutStep` all use it. Bit n
of a pattern drives the (n+1)-th element of `Outputs`.

## Step slot `UT_STEP`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `outputs` | DWORD | 0 | Bit n = the (n+1)-th output on during this step |
| `duration` | TIME | T#0s | Time in the step (0 = the condition alone) |
| `waitCond` | BOOL | FALSE | Also wait for `cond` (with a duration: both) |
| `cond` | BOOL | FALSE | **You write it**: the step's condition (level reached, temperature up…) |
| `timeout` | TIME | T#0s | Longest time in the step (0 = none) |
| `onTimeout` | UT_STEP_TIMEOUT | UT_STEP_FAULT | `UT_STEP_FAULT` (0, hold here with a fault, outputs to `pauseOutputs`) · `UT_STEP_NEXT` (carry on) · `UT_STEP_STOP` (go to the stop step) |
| `next` | INT | 0 | Position to go to next (0 = the following step). Jumps and loops |
| `loops` | INT | 0 | With `next` pointing back (or at itself): repeat this many times, then carry on |
| `skip` | BOOL | FALSE | Pass over this step |
| `active` | BOOL | | Status: running now |
| `elapsed` | TIME | | Status: time in this step (paused time not counted) |
| `loopCount` | INT | | Status: repeats done in the current loop |

A step with neither a duration nor a condition lasts one scan.

## Record `UT_STEP_SEQ_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stopStep` | INT | 0 | Position of the safe end step for a stop (0 = end at once, outputs off) |
| `pauseOutputs` | DWORD | 0 | Outputs while paused or held on a timeout |
| `cmdStart` | BOOL | | HMI: start, or resume an HMI pause |
| `cmdStop` | BOOL | | HMI: stop |
| `cmdPause` | BOOL | | HMI: pause until a start |
| `cmdNext` | BOOL | | HMI: end this step now |
| `cmdReset` | BOOL | | HMI: clear a fault |
| `cmdJump` | INT | -1 | HMI: go to this position now (starts the recipe there when idle); -1 = none; bad values ignored. A jump during a stop leaves the stop steps, so a later Stop goes to `stopStep` again |
| `activeStep` | INT | | Status: position running (0 = idle) |
| `elapsed` | TIME | | Status: time in this step |
| `remaining` | TIME | | Status: time left in this step |
| `cycles` | UDINT | | Status: recipes completed since the PLC started |
| `busy` | BOOL | | Status |
| `paused` | BOOL | | Status |
| `stopping` | BOOL | | Status: running the stop steps |
| `timedOutStep` | INT | | Status: position of the last step that timed out (0 = none) |
| `stepTimeout` | BOOL | | Status: held on a step timeout (UT_STEP_FAULT) |
| `config` | BOOL | | Status: recipe refused (bad `next` or `stopStep`, endless loop, a negative `duration` or `timeout`, an unknown `onTimeout`) |
| `fault` | BOOL | | Status: any fault |
| `faultCode` | DWORD | | Status: bit 0 step timeout, bit 1 config |
| `statusCode` | UT_STATUS | | Status: what it is doing, or what holds it back (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | Status: the fault or the recipe setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Running: step`. The step is in `activeStep`, its time left in `remaining` |
| `lastResult` | UT_STOP | | Status: how the last run ended (`UT_STOP_NONE` = none since power-up; see below) |
| `configStep` | INT | | Status: with a refused recipe, the step whose `next` or setting is wrong (0 = none, or a problem that is not a step's) |

**How the last run ended** (`lastResult`, a `UT_STOP`; an HMI reads its number):
| `lastResult` | When |
| --- | --- |
| `UT_STOP_OPERATOR` | `Stop` or `cmdStop`, after the stop steps |
| `UT_STOP_DONE` | The recipe ran to its end |
| `UT_STOP_ABORTED` | The `Abort` pin |
| `UT_STOP_STEP_TIMEOUT` | A step timed out with `UT_STEP_STOP` (after the stop steps) |
| `UT_STOP_REFUSED` | A bad `next` met while running |

## How it works
- **Loops**: a step whose `next` points back repeats `loops` times, then carries on to
  the following step. Its `loopCount` goes back to 0 each time the loop is left, so
  loops nest. A jump back with `loops` = 0 would never end, so the recipe is refused.
- **Checks**: at a start or a jump the whole recipe is checked; a bad `next`, bad
  `stopStep` or endless loop is refused with a config fault and every output off. A
  `next` changed to a bad value while running is refused when it is used (outputs
  off, idle). `Reset` clears the flag; the next Start checks again.
- **Timeout FAULT** holds the step with `pauseOutputs`; `Reset` lets it carry on with a
  fresh timeout, `Next` moves on, Stop goes to the stop step.
- **Stop** goes to `stopStep` and carries on from there to the end (put the safe end
  steps last); a second Stop while stopping is ignored. A stop step timing out with
  `UT_STEP_STOP` ends the recipe.
- **Pause** (pin, or `cmdPause` until a Start) keeps the step's time; outputs go to
  `pauseOutputs`.
- **Abort** (a level, e.g. the e-stop chain healthy signal through NOT) ends a run at
  once with every output off, without the stop steps (`lastResult` `UT_STOP_ABORTED`). While it is on
  no Start or `cmdJump` is taken; after it drops, a fresh Start runs from step 1.
- **Power cut**: nothing is kept. It comes back idle with every output off (even if
  you declared the arrays RETAIN) and is never resumed by itself; `cmdJump` can start
  it at any step.
- Start and Stop in the same scan: no start. Commands held on act once.

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes. The one main
thing, in the order config, fault, held, normal, idle. The step is in `activeStep`
(`configStep` for a refused recipe), its time left in `remaining`. Name the steps on
the HMI, by position.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_IDLE` | | `Idle` | Not running |
| `UT_ST_STOPPING` | | `Stopping` | Running the stop steps |
| `UT_ST_RUN_STEP` | | `Running: step` | A step running |
| `UT_ST_PAUSED_INPUT` | | `Paused: Pause input` | `Pause` |
| `UT_ST_PAUSED_START` | | `Paused: press Start` | `cmdPause` |
| `UT_ST_WAIT_CONDITION` | | `Waiting: step condition` | Its time is done (or it has none) and it waits for `cond` |
| `UT_ST_FAULT_RESET` | `UT_F_STEP_TIMEOUT` | `Latched: step timed out` | Held on a step timeout (`onTimeout` FAULT); Reset or Next |
| `UT_ST_CONFIG` | `UT_F_BAD_NEXT` | `Config: next outside recipe` | A `next` below 0 or past the last step (`configStep`) |
| `UT_ST_CONFIG` | `UT_F_ENDLESS_LOOP` | `Config: endless loop` | A jump back with `loops` 0 (`configStep`) |
| `UT_ST_CONFIG` | `UT_F_STOP_STEP` | `Config: stop step` | `stopStep` outside the recipe |
| `UT_ST_CONFIG` | `UT_F_STEP_SETTING` | `Config: step setting` | A negative `duration` or `timeout`, an unknown `onTimeout` (`configStep`) |
| `UT_ST_CONFIG` | `UT_F_NO_STEPS` | `Config: no steps to run` | An empty `Steps` array |

## Bad settings
A negative step `duration` or `timeout`, or an unknown `onTimeout`, refuses the recipe at
a start or a jump like a bad `next` (`config`, `Config: step setting` with the step in
`configStep`, every output off).
