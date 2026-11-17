# FB_Cascade — Pump staging on speed

Decides how many pumps of a group run on one header: staging by speed and pressure, by flow or by flow per pump, with or without VSDs, and a jockey pump for low demand.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fSpeed` | `REAL` |  | the shared speed %, from the loop |
| in | `bRun` | `BOOL` |  | the loop is running |
| in | `nMembers` | `INT` | `2` | duty pumps in the group (FB_Group.nDuty) |
| in | `nRunning` | `INT` | `-1` | FB_Group.nDutyRunning (-1 = not wired: no settled check) |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: no pump added |
| in | `fError` | `REAL` | `3.4E38` | the loop's fError (unwired: the speed alone) |
| in | `ePhase` | `E_LoopPhase` | `E_LoopPhase.Control` | the loop's ePhase |
| in | `ipFlow` | `I_Measurement` |  | the header flow (unwired = none). A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `fCapacity` | `REAL` |  | FB_Group.fRunCapacity |
| in | `fJockeyCapacity` | `REAL` |  | FB_Group.fJockeyCapacity |
| in | `bJockeyReady` | `BOOL` |  | FB_Group.bJockeyReady |
| in | `refData` | `REFERENCE TO ST_CascadeData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `nExtra` | `INT` |  | -> FB_Group.nExtra (-1 = the jockey alone) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_CascadeData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nExtra` | `INT` |  | status |
| `tTimeLeft` | `TIME` |  | to the next change |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eStageUsed` | `E_StageBy` |  | the rule in use (Pressure on a fallback) |
| `bJockeyTurn` | `BOOL` |  | the jockey alone |
| `bPvStaging` | `BOOL` |  | the flow rule left the pressure short: the Pressure rule until the next start |
| `bFlowBad` | `BOOL` |  | Flow / PerPump without a good flow |

**Settings `set`** (`ST_CascadeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fStageAt` | `REAL` | `95.0` | speed % at or above which a pump is added |
| `fDestageAt` | `REAL` | `40.0` | speed % at or below which one is dropped |
| `tStageDelay` | `TIME` | `T#15s` | add |
| `tDestageDelay` | `TIME` | `T#30s` | drop |
| `eStageBy` | `E_StageBy` |  |  |
| `bVsd` | `BOOL` | `TRUE` | the pumps follow the loop's speed (FALSE: fixed speed, the bands) |
| `fShortBand` | `REAL` | `0.2` | VSD: add only when the value is short of the setpoint by more than this |
| `fAddBand` | `REAL` | `0.3` | no VSD: add when the value is this far short of the setpoint |
| `fDropBand` | `REAL` | `0.3` | no VSD: drop when the value is this far past the setpoint |
| `fAddPct` | `REAL` | `90.0` | Flow and the jockey: add above this % of the running capacity |
| `fDropPct` | `REAL` | `75.0` | Flow and the jockey: drop below this % of the capacity left |
| `fBepMin` | `REAL` |  | PerPump: the flow per pump, best efficiency band |
| `fBepMax` | `REAL` |  | and stays above set.fBepMin with one more |

## Lists

- `E_LoopPhase`: `Idle`, `Filling`, `Control`, `Boost`, `Sleep`, `Fallback`, `Manual` (default `Idle`)
- `E_StageBy`: `Pressure`, `Flow`, `PerPump` (default `Pressure`)

## How it works

The staging of a pump cascade on one header holding a pressure or a flow. In 0.2 a cascade is built from blocks: [`FB_SpeedLoop`](FB_SpeedLoop.md) (the PID, the setpoint, sleep, the protections) drives an [`FB_Group`](FB_Group.md) of pumps (the group passes the loop's speed to every pump it calls: one shared speed; rotation, failover, swap, staged stop, the jockey) and `FB_Cascade` decides how many: `nExtra` -> `FB_Group.nExtra`. A fixed-speed set uses [`FB_SpeedLoop`](FB_SpeedLoop.md) with Fixed control (its `fError` still compares Pv with the setpoint) and `set.bVsd` FALSE here.

Staging, one pump at a time, only while the loop is in Control (Manual speed: none added or dropped); the need must last `set.tStageDelay` (add) or `set.tDestageDelay` (drop); after a change the next one waits the delay again; a pump is added only when the group has settled (`nRunning` has reached 1 + `nExtra`) and `bPermissive` is on. `set.eStageBy`:

```
  Pressure  set.bVsd: add with the speed at or above set.fStageAt and the value short of the setpoint by more
            than set.fShortBand; drop at or below set.fDestageAt when not short. No VSD (set.bVsd FALSE): add when the value is
            set.fAddBand short of the setpoint, drop when it is set.fDropBand past it.
  Flow      add above set.fAddPct % of the running capacity (fCapacity); drop below set.fDropPct % of the
            capacity left after the drop.
  PerPump   add when the flow per running pump is above set.fBepMax (and stays above set.fBepMin with one
            more); drop below set.fBepMin (and stays below set.fBepMax with one fewer).
```

Flow / PerPump also add on the Pressure rule (the pressure is never left short: a warning PvStaging and the Pressure rule until the set next starts from none) and fall back to Pressure with a bad or missing meter (warning SensorBad) or unusable settings (no capacity known, `fBepMax` not above `fBepMin`: warning BadSetting).

Jockey (an [`FB_Group`](FB_Group.md) member with `I_Pump` role Jockey, `bJockeyReady`): a start from none begins with the jockey alone (`nExtra` -1; not while the loop fills the pipe). It hands over to a duty pump when it cannot keep up: the flow above `fAddPct` % of `fJockeyCapacity`, or the Pressure rule (short of pressure below its capacity: the jockey is skipped until the next start). With one duty pump left and the demand falling (the flow below `fDropPct` % of `fJockeyCapacity`, or the Pressure drop rule) the set hands back to the jockey. The group keeps the jockey on until the duty pump runs. `bRun` FALSE drops them all ([`FB_Group`](FB_Group.md)'s `set.eStop` decides at once or staged). A burst main: an [`FB_LevelCheck`](FB_LevelCheck.md) (High) on the header flow meter as a part of the group. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back (`bRefused`, a warning until a reset).

## Example

A booster set: FB_SpeedLoop drives FB_Group; FB_Cascade decides how many pumps run.

| Pin | Wire |
| --- | --- |
| `fSpeed` | `fbLoop.fSpeed` |
| `bRun` | `fbLoop.bRunning` |
| `nMembers` | `fbGroup.nDuty` |
| `nRunning` | `fbGroup.nDutyRunning` |
| `fError` | `fbLoop.fError` |
| `ePhase` | `fbLoop.ePhase` |
| `refData` | `stCascade` |
| `nExtra` | `fbGroup.nExtra` |

**Back to** [the index](../README.md).
