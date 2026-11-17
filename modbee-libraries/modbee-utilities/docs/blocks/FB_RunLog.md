# FB_RunLog — Run log

Logs each run's time, volume and end reason, and counts the runs by how they ended. It only watches its run.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. The FB_Run instance |
| in | `ipMeter` | `I_Meter` |  | optional: the volume of each run. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `refData` | `REFERENCE TO ST_RunLogData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRunEnded` | `BOOL` |  | one scan at each run end |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunLogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetCounts` | `BOOL` |  | clears the counts (cleared by the block) |

**Totals `tot`** (`ST_RunLogTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nRuns` | `UDINT` |  | Runs counted |
| `nDone` | `UDINT` |  | Done |
| `nStopped` | `UDINT` |  | Request, Manual, Off, Hand, Restart |
| `nFaults` | `UDINT` |  | any other reason: a fault, an interlock, an abort, a maximum |
| `nPowerCuts` | `UDINT` |  | PowerCut |
| `tLastRun` | `TIME` |  | the last run's counted time |
| `tLastWall` | `TIME` |  | from its start to its end |
| `fLastVolume` | `LREAL` |  | in the meter's total unit (0 without a meter) |
| `eLastReason` | `E_StopReason` |  |  |

## How it works

The last run's time, volume and end reason, and run counts by how they ended. An observer, not a part: it reads its run (`ipRun`) and changes nothing, so a missing rung never stops a run. Call it every scan after the run.

When the run ends: `tot.tLastRun` (counted run time), `tot.tLastWall` (from start to end, pauses included), `tot.fLastVolume` (from `ipMeter`'s total, optional), `tot.eLastReason`; `tot.nRuns` and one of `nDone` (Done), `nStopped` (Request, Manual, Off, Hand, Restart), `nPowerCuts` (PowerCut), `nFaults` (any other reason: a fault, an interlock, an abort, a maximum). A restart (`ipRun.nActRunId` changes while it stays active) ends the run (Restart) and starts the next one. tot is kept over a power cut (written once per run end); `bCmdResetCounts` clears the counts.

## Example

Log every irrigation run.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stRunLog` |

**Back to** [the index](../README.md).
