# FB_Sequencer — Start / stop chain

A start / stop chain (conveyors, crushers, process trains): one step per machine, started in order with proven feedback, stopped in reverse, with fault cascades and an auto restart.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | held run request: its rise starts it, it must stay on for an auto restart |
| in | `bStart` | `BOOL R_EDGE` |  | rising edge: start the chain |
| in | `bStop` | `BOOL R_EDGE` |  | rising edge: stop the chain |
| in | `bAbortWhileHeld` | `BOOL` |  | level: everything off at once (e.g. NOT e-stop healthy) |
| in | `bPause` | `BOOL` |  | pause a start where it is |
| in | `bResetFaults` | `BOOL R_EDGE` |  | clear the fault |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE = abort |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE refuses a start |
| in | `refData` | `REFERENCE TO ST_SequencerData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aStepSettings` | `ARRAY[*] OF ST_SeqStepSet` |  | each machine's settings, in start order |
| in-out | `aSteps` | `ARRAY[*] OF ST_SeqStep` |  | each machine's live row: the block writes bRunCommand, the project bRunFeedback and bMachineReady |
| out | `bAllRunning` | `BOOL` |  | every step up |
| out | `bInTransition` | `BOOL` |  | starting, held or stopping |
| out | `nCurrentStep` | `INT` |  | the step being started or stopped (0 = none) |
| out | `bAutoRestartPending` | `BOOL` |  | auto restart countdown: wire to a pre-start siren |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SequencerData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | the HMI commands act once per write, then are cleared |
| `bCmdStop` | `BOOL` |  | HMI: stop (acts once, cleared by the block) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |

**Settings `set`** (`ST_SequencerSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStopOrder` | `E_SeqStopMode` |  | Reverse (last started first stopped), AllAtOnce or Forward |
| `eWhenStepLost` | `E_SeqLoss` |  | a running step loses its feedback: Cascade, StopAll or DownstreamOnly |
| `bAutoRestart` | `BOOL` |  | restart by itself after a fault stop (bRun held) |
| `tAutoRestartAfter` | `TIME` | `T#30s` | wait this long before an auto restart (bRestarting on: a pre-start horn) |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | auto restarts within tRetryCountWindow, then a reset is needed |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry counts trips within this window (0 = until a reset) |

**Status `sts`** (`ST_SequencerSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eChainState` | `E_SeqMode` |  | Idle, Starting, Running, Stopping, Aborted, Held or Partial |
| `nFirstFaultStep` | `INT` |  | the first faulted step (0 = none) |
| `bStepTimedOut` | `BOOL` |  | did not prove / did not stop |
| `bStepLostFeedback` | `BOOL` |  | lost its feedback |
| `bSettingBad` | `BOOL` |  | a step's setting is bad |
| `nBadSettingStep` | `INT` |  | the first step with a bad setting (0 = the chain's own) |
| `nRetriesUsed` | `INT` |  | auto restarts in this window |
| `bAutoRestartLocked` | `BOOL` |  | auto restarts used up: a reset is needed |
| `tAutoRestartTimeLeft` | `TIME` |  | time left before the auto restart |
| `tTimeLeft` | `TIME` |  | time left in the delay or phase running now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_SeqStepSet` (pin `aStepSettings`)

`aStepSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SeqStepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tNextStartDelay` | `TIME` | `T#2s` | after the feedback proves, wait this before the next step |
| `tNextStopDelay` | `TIME` | `T#2s` | after this step stops, wait this before the next stop |
| `tFeedbackTimeout` | `TIME` | `T#10s` | the feedback must come (start) or go (stop) within this (0 = no limit) |
| `bSkipStep` | `BOOL` |  | do not start this step (maintenance) |
| `bNoFeedbackFitted` | `BOOL` |  | no feedback: proved by tNextStartDelay alone |

## Rows `ST_SeqStep` (pin `aSteps`)

`aSteps` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SeqStep`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRunFeedback` | `BOOL` |  | running / proven |
| `bMachineReady` | `BOOL` | `TRUE` | healthy, could start |
| `bRunCommand` | `BOOL` |  | run this machine |
| `eStepState` | `E_SeqStepState` |  | Off, Starting, Running, Stopping, Fault or Bypassed |
| `tElapsedTime` | `TIME` |  | time in the step so far |
| `tTimeLeft` | `TIME` |  | its timeout while starting or stopping, its delay while the chain waits on it |

## Lists

- `E_SeqLoss`: `Cascade`, `StopAll`, `DownstreamOnly` (default `Cascade`)
- `E_SeqMode`: `Idle`, `Starting`, `Running`, `Stopping`, `Aborted`, `Held`, `Partial` (default `Idle`)
- `E_SeqStepState`: `Off`, `Starting`, `Running`, `Stopping`, `Fault`, `Bypassed` (default `Off`)
- `E_SeqStopMode`: `Reverse`, `AllAtOnce`, `Forward` (default `Reverse`)

## How it works

A start / stop chain: conveyors, crushing, process trains.

Tables the project declares (VAR_IN_OUT, the same size, at most 32): `aStepSettings` (each machine's settings, in START order) and `aSteps` (each machine's live row: the block writes `bRunCommand`, the project writes `bRunFeedback` and `bMachineReady` from the machine, e.g. m1.Request(`bRun` := `aSteps`[1].bRunCommand, `bPause` := FALSE); `aSteps`[1].bRunFeedback := m1.bIsRunning; `aSteps`[1].bMachineReady := m1.bIsReady). `bRun` (held) starts it and its drop stops it; `bStart` / `bStop` are edges; `bInterlock` FALSE = `bAbortWhileHeld`; `bPermissive` FALSE refuses a start. A start runs the steps one at a time: a step's `bRunCommand` goes on, its `bRunFeedback` must prove within `tFeedbackTimeout`, then `tNextStartDelay` passes before the next step (`bNoFeedbackFitted`: proved by the delay alone; `bSkipStep`: not started). A stop runs them per `set.eStopOrder` (Reverse: last started first stopped; AllAtOnce; Forward), each waiting for its feedback to go and then its `tNextStopDelay`. A step losing its feedback while running, or failing to prove at start, is a fault (FeedbackLost / NoFeedback) and `set.eWhenStepLost` decides what stops: Cascade (the failed step and every step after it at once, then the rest in reverse), StopAll, DownstreamOnly (the steps before it keep running: `sts.eChainState` Partial). A step whose feedback will not go when stopped holds the stop there and raises Stuck once its timeout has passed; `bAbortWhileHeld` is the way out. `bPause` pauses a START (never a stop). `bAbortWhileHeld` (a level) drops every `bRunCommand` at once.

Auto restart (`set.bAutoRestart`): after a fault stop it starts again by itself once every step is ready and `bRun` is still TRUE, after `set.tAutoRestartAfter` (`bAutoRestartPending` on: wire it to a pre-start siren), at most `set.nMaxRetriesBeforeLockout` times in `set.tRetryCountWindow`. A stop or abort cancels the run request, so it never restarts by itself after those.

Nothing is kept over a power cut but the settings: the chain comes back idle with every `bRunCommand` off and must be started again. Faults clear on a start, a stop or a reset. Kept (a retained last-good copy, a bad write put back): set, and the step rows packed into two DWORDs each (the times in 100 ms steps up to 109 min).

## Example

Three conveyors started in order. Declare `aStepSettings : ARRAY[1..3] OF ST_SeqStepSet` and `aSteps : ARRAY[1..3] OF ST_SeqStep`.

| Pin | Wire |
| --- | --- |
| `bRun` | `DI_ChainRun` |
| `bAbortWhileHeld` | `NOT DI_EStopHealthy` |
| `aStepSettings` | `aStepSettings` |
| `aSteps` | `aSteps` |
| `refData` | `stChain` |
| `bAutoRestartPending` | a pre-start siren |

On each machine's own rungs: `aSteps[1].bRunCommand` drives conveyor 1 (its owner request or its output); write `aSteps[1].bRunFeedback` from its running signal and `aSteps[1].bMachineReady` from its ready signal.

**Back to** [the index](../README.md).
