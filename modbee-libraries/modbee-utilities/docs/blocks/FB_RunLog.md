# FB_RunLog — Run log

Logs each run's time, volume and end reason, and counts the runs by how they ended. It only watches its run.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. An instance of a block that offers I_Run (FB_Run) |
| in | `ipMeter` | `I_Meter` |  | optional: the volume of each run. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `refData` | `REFERENCE TO ST_RunLogData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bRunEnded` | `BOOL` |  | one scan at each run end |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunLogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetCounters` | `BOOL` |  | clears the counts (cleared by the block) |

**Totals `tot`** (`ST_RunLogTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nRunCount` | `UDINT` |  | runs counted |
| `nDoneRunCount` | `UDINT` |  | runs that ended Done |
| `nStoppedRunCount` | `UDINT` |  | runs ended by a stop (Request, Manual, Off, Hand) |
| `nFaultedRunCount` | `UDINT` |  | runs ended by anything else: a fault, an interlock, an abort, a maximum |
| `nPowerCutRunCount` | `UDINT` |  | runs ended by a power cut |
| `tLastRunTime` | `TIME` |  | the last run's counted time |
| `tLastRunStartToEnd` | `TIME` |  | from its start to its end |
| `fLastRunVolume` | `LREAL` |  | in the meter's total unit (0 without a meter) |
| `eLastStopReason` | `E_StopReason` |  | why the last run ended |

## How it works

The last run's time, volume and end reason, and run counts by how they ended. An observer, not a part: it reads its run (`ipRun`) and changes nothing, so a missing rung never stops a run. Call it every scan after the run.

When the run ends: `tot.tLastRunTime` (counted run time), `tot.tLastRunStartToEnd` (from start to end, pauses included), `tot.fLastRunVolume` (from `ipMeter`'s total, optional), `tot.eLastStopReason`; `tot.nRunCount` and one of `nDoneRunCount` (Done), `nStoppedRunCount` (Request, Manual, Off, Hand, Restart), `nPowerCutRunCount` (PowerCut), `nFaultedRunCount` (any other reason: a fault, an interlock, an abort, a maximum). A restart (`ipRun.nActRunId` changes while it stays active) ends the run (Restart) and starts the next one. tot is kept over a power cut (written once per run end); `bCmdResetCounters` clears the counts.

## Example

Log every irrigation run.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stRunLog` |

**Back to** [the index](../README.md).
