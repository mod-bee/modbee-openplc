# FB_Cascade — Pump staging on speed

Decides how many pumps of a group run on one header: staging by speed and pressure, by flow or by flow per pump, with or without VSDs, and a jockey pump for low demand.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fSpeedSetpointPct` | `REAL` |  | the shared speed %, from the loop |
| in | `bLoopRunning` | `BOOL` |  | the loop is running |
| in | `nDutyPumps` | `INT` | `2` | duty pumps in the group (FB_Group.nDutyMembers) |
| in | `nDutyPumpsRunning` | `INT` | `-1` | FB_Group.nDutyMembersRunning (-1 = not wired: no settled check) |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: no pump added |
| in | `fShortOfSetpoint` | `REAL` | `3.4E38` | the loop's fShortOfSetpoint (unwired: the speed alone) |
| in | `eLoopPhase` | `E_LoopPhase` | `E_LoopPhase.Control` | the loop's eLoopPhase |
| in | `ipHeaderFlow` | `I_Measurement` |  | the header flow (unwired = none). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `fRunningCapacity` | `REAL` |  | FB_Group.fRunningCapacity |
| in | `fJockeyCapacity` | `REAL` |  | FB_Group.fJockeyCapacity |
| in | `bJockeyReady` | `BOOL` |  | FB_Group.bJockeyReady |
| in | `refData` | `REFERENCE TO ST_CascadeData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `nExtraPumps` | `INT` |  | -> FB_Group.nExtraMembers (-1 = the jockey alone) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_CascadeData` (pin `refData`)

**Settings `set`** (`ST_CascadeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fAddPumpAtSpeedPct` | `REAL` | `95.0` | speed % at or above which a pump is added |
| `fDropPumpAtSpeedPct` | `REAL` | `40.0` | speed % at or below which one is dropped |
| `tAddPumpDelay` | `TIME` | `T#15s` | the add condition must last this long |
| `tDropPumpDelay` | `TIME` | `T#30s` | the drop condition must last this long |
| `eStageRule` | `E_StageBy` |  | how pumps are added: Pressure, Flow or PerPump |
| `bPumpsOnVsd` | `BOOL` | `TRUE` | the pumps follow the loop's speed (FALSE: fixed speed, the bands) |
| `fAddWhenShortBy` | `REAL` | `0.2` | VSD: add only when the value is short of the setpoint by more than this |
| `fFixedAddWhenShortBy` | `REAL` | `0.3` | no VSD: add when the value is this far short of the setpoint |
| `fFixedDropWhenPastBy` | `REAL` | `0.3` | no VSD: drop when the value is this far past the setpoint |
| `fAddAboveCapacityPct` | `REAL` | `90.0` | Flow and the jockey: add above this % of the running capacity |
| `fDropBelowCapacityPct` | `REAL` | `75.0` | Flow and the jockey: drop below this % of the capacity left |
| `fDropBelowFlowPerPump` | `REAL` |  | PerPump: the flow per pump, best efficiency band |
| `fAddAboveFlowPerPump` | `REAL` |  | PerPump: add a pump when the flow per running pump is above this (best efficiency band, high end) |

**Status `sts`** (`ST_CascadeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nExtraPumps` | `INT` |  | pumps wanted beyond the first (-1 = the jockey alone) |
| `tAddOrDropTimeLeft` | `TIME` |  | to the next change |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `eStageRuleInUse` | `E_StageBy` |  | the rule in use (Pressure on a fallback) |
| `bJockeyAlone` | `BOOL` |  | the jockey alone |
| `bPressureRuleFallback` | `BOOL` |  | the flow rule left the pressure short: the Pressure rule until the next start |
| `bFlowNotGood` | `BOOL` |  | Flow / PerPump without a good flow |
| `fFlowPerPump` | `REAL` |  | the flow per running duty pump (0 with no good flow) |

## Lists

- `E_LoopPhase`: `Idle`, `Filling`, `Control`, `Boost`, `Sleep`, `Fallback`, `Manual` (default `Idle`)
- `E_StageBy`: `Pressure`, `Flow`, `PerPump` (default `Pressure`)

## How it works

The staging of a pump cascade on one header holding a pressure or a flow. A cascade is built from blocks: [`FB_SpeedLoop`](FB_SpeedLoop.md) (the PID, the setpoint, sleep, the protections) drives an [`FB_Group`](FB_Group.md) of pumps (the group passes the loop's speed to every pump it calls: one shared speed; rotation, failover, swap, staged stop, the jockey) and

`FB_Cascade` decides how many: `nExtraPumps` -> `FB_Group.nExtraMembers`. A fixed-speed set uses [`FB_SpeedLoop`](FB_SpeedLoop.md) with Fixed control (its `fShortOfSetpoint` still compares Pv with the setpoint) and `set.bPumpsOnVsd` FALSE here.

Staging, one pump at a time, only while the loop is in Control (Manual speed: none added or dropped); the need must last `set.tAddPumpDelay` (add) or `set.tDropPumpDelay` (drop); after a change the next one waits the delay again; a pump is added only when the group has settled (`nDutyPumpsRunning` has reached 1 + `nExtraPumps`) and `bPermissive` is on. `set.eStageRule`:

```
  Pressure  set.bPumpsOnVsd: add with the speed at or above set.fAddPumpAtSpeedPct and the value short of the setpoint by more
            than set.fAddWhenShortBy; drop at or below set.fDropPumpAtSpeedPct (set it to the loop's
            minimum for "at the minimum only") when not short. No VSD (set.bPumpsOnVsd FALSE): add when the value is
            set.fFixedAddWhenShortBy short of the setpoint, drop when it is set.fFixedDropWhenPastBy past it.
  Flow      add above set.fAddAboveCapacityPct % of the running capacity (fRunningCapacity); drop below set.fDropBelowCapacityPct % of the
            capacity left after the drop.
  PerPump   add when the flow per running pump is above set.fAddAboveFlowPerPump (and stays above set.fDropBelowFlowPerPump with one
            more); drop below set.fDropBelowFlowPerPump (and stays below set.fAddAboveFlowPerPump with one fewer).
```

Flow / PerPump also add on the Pressure rule (the pressure is never left short: a warning PvStaging and the Pressure rule until the set next starts from none) and fall back to Pressure with a bad or missing meter (warning SensorBad) or unusable settings (no capacity known, `fAddAboveFlowPerPump` not above `fDropBelowFlowPerPump`: warning BadSetting).

Jockey (an [`FB_Group`](FB_Group.md) member with `I_Pump` role Jockey, `bJockeyReady`): a start from none begins with the jockey alone (`nExtraPumps` -1; not while the loop fills the pipe). It hands over to a duty pump when it cannot keep up: the flow above `fAddAboveCapacityPct` % of `fJockeyCapacity`, or the Pressure rule (short of pressure below its capacity: the jockey is skipped until the next start). With one duty pump left and the demand falling (the flow below `fDropBelowCapacityPct` % of `fJockeyCapacity`, or the Pressure drop rule) the set hands back to the jockey. The group keeps the jockey on until the duty pump runs. `bLoopRunning` FALSE drops them all ([`FB_Group`](FB_Group.md)'s `set.eStopOrder` decides at once or staged). A burst main: an [`FB_LevelCheck`](FB_LevelCheck.md) (High) on the header flow meter as a part of the group. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back (`sts.bSettingRefused` / `sts.eSettingRefusedErrorId`, a warning until a reset).

## Example

A booster set: FB_SpeedLoop drives FB_Group; FB_Cascade decides how many pumps run.

| Pin | Wire |
| --- | --- |
| `fSpeedSetpointPct` | `fbLoop.fSpeedSetpointPct` |
| `bLoopRunning` | `fbLoop.bRunning` |
| `nDutyPumps` | `fbGroup.nDutyMembers` |
| `nDutyPumpsRunning` | `fbGroup.nDutyMembersRunning` |
| `fShortOfSetpoint` | `fbLoop.fShortOfSetpoint` |
| `eLoopPhase` | `fbLoop.eLoopPhase` |
| `refData` | `stCascade` |
| `nExtraPumps` | `fbGroup.nExtraMembers` |

**Back to** [the index](../README.md).
