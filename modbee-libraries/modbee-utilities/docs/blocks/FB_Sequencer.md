# FB_Sequencer — Start / stop chain

A start / stop chain (conveyors, crushers, process trains): one step per machine, started in order with proven feedback, stopped in reverse, with fault cascades and an auto restart.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | held run request: its rise starts it, it must stay on for an auto restart |
| in | `bStart` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bStop` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bAbort` | `BOOL` |  | level: everything off at once (e.g. NOT e-stop healthy) |
| in | `bHold` | `BOOL` |  | pause a start where it is |
| in | `bReset` | `BOOL R_EDGE` |  | clear the fault Acts on its rising edge. |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE = abort |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE refuses a start |
| in | `refData` | `REFERENCE TO ST_SequencerData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aStepSet` | `ARRAY[*] OF ST_SeqStepSet` |  | each machine's settings, in START order |
| in-out | `aStep` | `ARRAY[*] OF ST_SeqStep` |  | each machine's live row: the block writes bCmd, the project writes bFeedback and bReady from the machine, e.g. m1.Request(bRun := aStep[1].bCmd, bHold := FALSE); aStep[1].bFeedback := m1.bIsRunning; aStep[1].bReady := m1.bIsReady |
| out | `bRunning` | `BOOL` |  | every step up |
| out | `bBusy` | `BOOL` |  | starting, held or stopping |
| out | `nCurrentStep` | `INT` |  | the step being started or stopped (0 = none) |
| out | `bRestarting` | `BOOL` |  | auto restart countdown: wire to a pre-start siren |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SequencerData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | the HMI commands act once per write, then are cleared |
| `bCmdStop` | `BOOL` |  | Stop (HMI command; acts once, cleared by the block) |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_SequencerSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStopMode` | `E_SeqStopMode` |  | Reverse: last started first stopped; AllAtOnce; Forward |
| `eOnLoss` | `E_SeqLoss` |  |  |
| `bAutoRestart` | `BOOL` |  | restart by itself after a fault stop (bRun held) |
| `tRestartDelay` | `TIME` | `T#30s` | bRestarting on: wire it to a pre-start siren |
| `nMaxRetries` | `INT` | `3` | auto restarts within tRetryWindow, then a reset is needed |
| `tRetryWindow` | `TIME` | `T#1h` | Retry protections count their trips within this window |

**Status `sts`** (`ST_SequencerSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_SeqMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `nFaultStep` | `INT` |  | the first faulted step (0 = none) |
| `bFltTimeout` | `BOOL` |  | did not prove / did not stop |
| `bFltLoss` | `BOOL` |  | lost its feedback |
| `bFltConfig` | `BOOL` |  |  |
| `nConfigStep` | `INT` |  | the first step with a bad setting (0 = the chain's own) |
| `nRestarts` | `INT` |  | auto restarts in this window |
| `bRestartLocked` | `BOOL` |  |  |
| `tRestartIn` | `TIME` |  | Time left before a start is allowed (restart delay) |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Rows `ST_SeqStepSet` (pin `aStepSet`)

`aStepSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SeqStepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tStartDelay` | `TIME` | `T#2s` | after the feedback proves, wait this before the next step |
| `tStopDelay` | `TIME` | `T#2s` | after this step stops, wait this before the next stop |
| `tTimeout` | `TIME` | `T#10s` | the feedback must come (start) or go (stop) within this (0 = no limit) |
| `bBypass` | `BOOL` |  | do not start this step (maintenance) |
| `bNoFeedback` | `BOOL` |  | no feedback: proved by tStartDelay alone |

## Rows `ST_SeqStep` (pin `aStep`)

`aStep` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SeqStep`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bFeedback` | `BOOL` |  | running / proven |
| `bReady` | `BOOL` | `TRUE` | healthy, could start |
| `bCmd` | `BOOL` |  | run this machine |
| `eState` | `E_SeqStepState` |  | What it is doing now (status) |
| `tElapsed` | `TIME` |  | Time in the step or run so far |
| `tLeft` | `TIME` |  | its timeout while starting or stopping, its delay while the chain waits on it |

## Lists

- `E_SeqLoss`: `Cascade`, `StopAll`, `DownstreamOnly` (default `Cascade`)
- `E_SeqMode`: `Idle`, `Starting`, `Running`, `Stopping`, `Aborted`, `Held`, `Partial` (default `Idle`)
- `E_SeqStepState`: `Off`, `Starting`, `Running`, `Stopping`, `Fault`, `Bypassed` (default `Off`)
- `E_SeqStopMode`: `Reverse`, `AllAtOnce`, `Forward` (default `Reverse`)

## How it works

A start / stop chain: conveyors, crushing, process trains.

Tables the project declares (VAR_IN_OUT, the same size, at most 32): `aStepSet` (each machine's settings, in START order) and `aStep` (each machine's live row: the block writes `bCmd`, the project writes `bFeedback` and `bReady` from the machine, e.g. m1.Request(`bRun` := `aStep`[1].bCmd, `bHold` := FALSE); `aStep`[1].bFeedback := m1.bIsRunning; `aStep`[1].bReady := m1.bIsReady). `bRun` (held) starts it and its drop stops it; `bStart` / `bStop` are edges; `bInterlock` FALSE = `bAbort`; `bPermissive` FALSE refuses a start. A start runs the steps one at a time: a step's `bCmd` goes on, its `bFeedback` must prove within `tTimeout`, then `tStartDelay` passes before the next step (`bNoFeedback`: proved by the delay alone; `bBypass`: not started). A stop runs them per `set.eStopMode` (Reverse: last started first stopped; AllAtOnce; Forward), each waiting for its feedback to go and then its `tStopDelay`. A step losing its feedback while running, or failing to prove at start, is a fault (FeedbackLost / NoFeedback) and `set.eOnLoss` decides what stops: Cascade (the failed step and every step after it at once, then the rest in reverse), StopAll, DownstreamOnly (the steps before it keep running: `sts.eMode` Partial). A step whose feedback will not go when stopped holds the stop there and raises Stuck once its timeout has passed; `bAbort` is the way out. `bHold` pauses a START (never a stop). `bAbort` (a level) drops every `bCmd` at once.

Auto restart (`set.bAutoRestart`): after a fault stop it starts again by itself once every step is ready and `bRun` is still TRUE, after `set.tRestartDelay` (`bRestarting` on: wire it to a pre-start siren), at most `set.nMaxRetries` times in `set.tRetryWindow`. A stop or abort cancels the run request, so it never restarts by itself after those.

Nothing is kept over a power cut but the settings: the chain comes back idle with every `bCmd` off and must be started again. Faults clear on a start, a stop or a reset. Kept (a retained last-good copy, a bad write put back): set, and the step rows packed into two DWORDs each (the times in 100 ms steps up to 109 min).

## Example

Three conveyors started in order. Declare `aStepSet : ARRAY[1..3] OF ST_SeqStepSet` and `aStep : ARRAY[1..3] OF ST_SeqStep`.

| Pin | Wire |
| --- | --- |
| `bRun` | `DI_ChainRun` |
| `bAbort` | `NOT DI_EStopHealthy` |
| `aStepSet` | `aStepSet` |
| `aStep` | `aStep` |
| `refData` | `stChain` |
| `bRestarting` | a pre-start siren |

On each machine's own rungs: `aStep[1].bCmd` drives conveyor 1 (its owner request or its output); write `aStep[1].bFeedback` from its running signal and `aStep[1].bReady` from its ready signal.

**Back to** [the index](../README.md).
