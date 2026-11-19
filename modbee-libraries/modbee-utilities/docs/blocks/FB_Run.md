# FB_Run — One run of any equipment

One run of any equipment: a held request or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a part or a power cut; a restart starts it over from zero with the equipment kept running. Its `bRunCommand` drives the equipment.

Offers `I_Run`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` | `FALSE` | held request: the run lasts while it is held |
| in | `bStart` | `BOOL R_EDGE` |  | rising edge: a latched run |
| in | `bStop` | `BOOL R_EDGE` |  | rising edge: ends the run; wins over a start |
| in | `bRestart` | `BOOL R_EDGE` |  | the active run starts over from zero (the equipment keeps running) |
| in | `bResetFaults` | `BOOL R_EDGE` |  | rising edge: reset trips whose cause has gone |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE ends the run and refuses a start |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: a new run waits |
| in | `bPause` | `BOOL` |  | held: no run command, no counting |
| in | `bAbort` | `BOOL R_EDGE` |  | rising edge: ends the run with eAbortStopReason |
| in | `eAbortStopReason` | `E_StopReason` | `E_StopReason.Abort` | the stop reason bAbort gives |
| in | `bEquipmentRunning` | `BOOL` |  | the equipment runs (or ipEquipment's own running) |
| in | `ipEquipment` | `I_Equipment` |  | optional: the equipment this run drives (Request every scan; Ladder-ready) |
| in | `refData` | `REFERENCE TO ST_RunData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bRunCommand` | `BOOL` |  | run the equipment |
| out | `bBusy` | `BOOL` |  | a run is active |
| out | `bPaused` | `BOOL` |  | the run is paused |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | HMI: start a run (acts once, cleared by the block) |
| `bCmdStop` | `BOOL` |  | HMI: stop the run (acts once, cleared by the block) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `bCmdRestart` | `BOOL` |  | HMI: the active run starts over from zero (acts once, cleared by the block) |

**Settings `set`** (`ST_RunSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bStopAfterRunTime` | `BOOL` |  | the run ends after tRunTime of running |
| `tRunTime` | `TIME` | `T#1h` | run time for bStopAfterRunTime |
| `tMaxTimeFromStart` | `TIME` |  | 0 = no cap |
| `tMaxPauseBeforeEnd` | `TIME` |  | 0 = no limit |
| `eAfterPowerCut` | `E_RunResume` |  | Resume (go on from the kept progress), Restart or None (the run ends) |
| `tHeldRunTimeout` | `TIME` | `T#1m` | after a power cut a held run goes on only if its request is back within this |
| `tProgressSaveInterval` | `TIME` | `T#1h` | the progress is kept on events and at least this often |

**Status `sts`** (`ST_RunSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now |
| `eErrorId` | `E_UtError` |  | the first error since the last reset (first-out) |
| `eStopReason` | `E_StopReason` |  | why the last run ended |
| `bBusy` | `BOOL` |  | a run is active now |
| `bPaused` | `BOOL` |  | the run is paused |
| `bWaitingForPermissive` | `BOOL` |  | a new run waits for the permissive |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_RunDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tElapsedTime` | `TIME` |  | run time counted (while the equipment runs) |
| `tTimeLeft` | `TIME` |  | time left in the run (or the delay running now) |
| `tPausedFor` | `TIME` |  | how long the current pause has lasted (0 while not paused) |
| `tInPhaseFor` | `TIME` |  | since the run started (active) or ended (idle); a restart starts it over |

**Totals `tot`** (`ST_RunTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nRunCount` | `UDINT` |  | runs counted (kept) |
| `tLastRunTime` | `TIME` |  | the last run's counted time |

## How it works

One run of any equipment: a held request, or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a part, or a power cut.

Detail (det): `tElapsedTime` (time counted), `tTimeLeft` (`set.bStopAfterRunTime`), `tPausedFor` (the current pause), `tInPhaseFor` (since the run started or ended; a restart starts it over).

Restart (`bRestart` / `bCmdRestart`): the active run ends with stop reason Restart (counted, logged) and a new run starts in the same scan: time from zero, its parts start over ([`FB_RunVolume`](FB_RunVolume.md) takes a new start total), latched as before, `bRunCommand` not dropped. A stop in the same scan wins; no run active: nothing happens. `nActRunId` changes at every start, a restart too: observers and parts see a new run by it.

Power cut: the progress is kept on events and every `set.tProgressSaveInterval`. `set.eAfterPowerCut` Resume: a latched run goes on from its progress; a held one goes on if its request is back within `set.tHeldRunTimeout`, else it ends (PowerCut). Restart: the same from zero. None: it ends (PowerCut).

Parts: a trip ends it (Fault); a signal pauses it; Done ends it normally ([`FB_RunVolume`](FB_RunVolume.md)'s target); Cap ends it at a part's safety time cap (stop reason TimeCap, a warning RunCapped until a reset or the next run); a hold makes a new run wait. Its parts: [`FB_RunVolume`](FB_RunVolume.md) (volume target, safety cap), [`FB_RunPause`](FB_RunPause.md) (operator pause / resume), [`FB_RunGate`](FB_RunGate.md) (wait for a permissive), [`FB_LevelCheck`](FB_LevelCheck.md) (source low, destination full); observer [`FB_RunLog`](FB_RunLog.md).

## Example

A timed irrigation run on pump 1.

| Pin | Wire |
| --- | --- |
| `bStart` | `DI_RunStart` |
| `bStop` | `DI_RunStop` |
| `bEquipmentRunning` | `DI_P1_Running` |
| `refData` | `stRun` |
| `bRunCommand` | the level control's `bDemand` (or the pump) |

Set `stRun.set.bStopAfterRunTime := TRUE` and `tRunTime`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `bIsBusy : BOOL`: a run is active now
- property `tActElapsed : TIME`: run time counted in this run
- property `eActStopReason : E_StopReason`: why it last stopped (None while one runs)
- property `nActRunId : UDINT`: the run's number: it changes at every start, a restart too (a new run)

## See also

[FB_RunVolume](FB_RunVolume.md), [FB_RunPause](FB_RunPause.md), [FB_RunGate](FB_RunGate.md), [FB_RunStyle](FB_RunStyle.md), [FB_RunLog](FB_RunLog.md)

**Back to** [the index](../README.md).
