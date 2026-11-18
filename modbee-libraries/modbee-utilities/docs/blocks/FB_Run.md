# FB_Run — One run of any equipment

One run of any equipment: a held request or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a part or a power cut; a restart starts it over from zero with the equipment kept running. Its `bRunCmd` drives the equipment.

Offers `I_Run`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` | `FALSE` | held request: the run lasts while it is held |
| in | `bStart` | `BOOL R_EDGE` |  | rising edge: a latched run Acts on its rising edge. |
| in | `bStop` | `BOOL R_EDGE` |  | rising edge: ends it, wins Acts on its rising edge. |
| in | `bRestart` | `BOOL R_EDGE` |  | the active run starts over from zero (the equipment keeps running) Acts on its rising edge. |
| in | `bReset` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE ends the run and refuses a start |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: a new run waits |
| in | `bPause` | `BOOL` |  | held: no run command, no counting |
| in | `bAbort` | `BOOL R_EDGE` |  | rising edge: ends it with eAbortCode Acts on its rising edge. |
| in | `eAbortCode` | `E_StopReason` | `E_StopReason.Abort` | The stop reason `bAbort` gives |
| in | `bEquipRunning` | `BOOL` |  | the equipment runs (or ipTarget's own running) |
| in | `ipTarget` | `I_Equipment` |  | optional: the equipment this run drives (Request every scan; Ladder-ready). The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_RunData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRunCmd` | `BOOL` |  |  |
| out | `bActive` | `BOOL` |  | Active now |
| out | `bPaused` | `BOOL` |  | Paused (status) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | Start (HMI command; acts once, cleared by the block) |
| `bCmdStop` | `BOOL` |  | Stop (HMI command; acts once, cleared by the block) |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |
| `bCmdRestart` | `BOOL` |  | Restart the active run from zero (HMI command; acts once, cleared by the block) |

**Settings `set`** (`ST_RunSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bByTime` | `BOOL` |  |  |
| `tRunTime` | `TIME` | `T#1h` | Time in this run |
| `tMaxTime` | `TIME` |  | 0 = no cap |
| `tMaxPause` | `TIME` |  | 0 = no limit |
| `eResume` | `E_RunResume` |  |  |
| `tResumeWindow` | `TIME` | `T#1m` |  |
| `tProgressSave` | `TIME` | `T#1h` |  |

**Status `sts`** (`ST_RunSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | The first error since the last reset (first-out) |
| `eStopReason` | `E_StopReason` |  | why the last run ended |
| `bActive` | `BOOL` |  | Active now |
| `bPaused` | `BOOL` |  | Paused (status) |
| `bWaiting` | `BOOL` |  | a new run waits for the permissive |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Details `det`** (`ST_RunDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tElapsed` | `TIME` |  | run time counted (while the equipment runs) |
| `tTimeLeft` | `TIME` |  | set.bByTime |
| `tPaused` | `TIME` |  | how long the current pause has lasted (0 while not paused) |
| `tPhaseTime` | `TIME` |  | since the run started (active) or ended (idle); a restart starts it over |

**Totals `tot`** (`ST_RunTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nRuns` | `UDINT` |  | Runs counted |
| `tLastRun` | `TIME` |  | the last run's counted time |

## How it works

One run of any equipment: a held request, or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a part, or a power cut.

Detail (det): `tElapsed` (time counted), `tTimeLeft` (`set.bByTime`), `tPaused` (the current pause), `tPhaseTime` (since the run started or ended; a restart starts it over).

Restart (`bRestart` / `bCmdRestart`): the active run ends with stop reason Restart (counted, logged) and a new run starts in the same scan: time from zero, its parts start over ([`FB_RunVolume`](FB_RunVolume.md) takes a new start total), latched as before, `bRunCmd` not dropped. A stop in the same scan wins; no run active: nothing happens. `nActRunId` changes at every start, a restart too: observers and parts see a new run by it.

Power cut: the progress is kept on events and every `set.tProgressSave`. `set.eResume` Resume: a latched run goes on from its progress; a held one goes on if its request is back within `set.tResumeWindow`, else it ends (PowerCut). Restart: the same from zero. None: it ends (PowerCut).

Parts: a trip ends it (Fault); a signal pauses it; Done ends it normally ([`FB_RunVolume`](FB_RunVolume.md)'s target); Cap ends it at a part's safety time cap (stop reason TimeCap, a warning RunCapped until a reset or the next run); a hold makes a new run wait. Its parts: [`FB_RunVolume`](FB_RunVolume.md) (volume target, safety cap), [`FB_RunPause`](FB_RunPause.md) (operator pause / resume), [`FB_RunGate`](FB_RunGate.md) (wait for a permissive), [`FB_LevelCheck`](FB_LevelCheck.md) (source low, destination full); observer [`FB_RunLog`](FB_RunLog.md).

## Example

A timed irrigation run on pump 1.

| Pin | Wire |
| --- | --- |
| `bStart` | `DI_RunStart` |
| `bStop` | `DI_RunStop` |
| `bEquipRunning` | `DI_P1_Running` |
| `refData` | `stRun` |
| `bRunCmd` | the level control's `bDemand` (or the pump) |

Set `stRun.set.bByTime := TRUE` and `tRunTime`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `bIsActive : BOOL`
- property `tActElapsed : TIME`
- property `eActStopReason : E_StopReason`
- property `nActRunId : UDINT`

## See also

[FB_RunVolume](FB_RunVolume.md), [FB_RunPause](FB_RunPause.md), [FB_RunGate](FB_RunGate.md), [FB_RunStyle](FB_RunStyle.md), [FB_RunLog](FB_RunLog.md)

**Back to** [the index](../README.md).
