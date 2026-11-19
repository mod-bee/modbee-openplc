# FB_LevelControl — Level control: empty, fill or timed

Keeps a level by driving a pump or a group: EMPTY (a sump, a wet well), FILL (a tank) or TIMED (on / off with no level), with high-high and low-low levels, a demand run, a moving start level and an action for a bad level.

Offers `I_LevelControl`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | the process may run (e.g. the system not Off) |
| in | `bDemand` | `BOOL` |  | pump down / fill now, past the start level, to fDemandStopLevel |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: nothing is requested |
| in | `ipLevel` | `I_Measurement` |  | required. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipEquipment` | `I_Equipment` |  | required |
| in | `fSpeedSetpointPct` | `REAL` | `-1.0` | the speed asked of the target (< 0 = its own) |
| in | `refData` | `REFERENCE TO ST_LevelControlData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bEquipmentRunning` | `BOOL` |  | it asks and the pump runs |
| out | `bLevelCalls` | `BOOL` |  | the level calls for pumping |
| out | `bAtStopLevel` | `BOOL` |  | at or past the stop level |
| out | `bHighHigh` | `BOOL` |  | at or past the high-high level |
| out | `bLowLow` | `BOOL` |  | at or past the low-low level |
| out | `bDemandActive` | `BOOL` |  | a demand is running (-> FB_Stages bDemand) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelControlData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdDemand` | `BOOL` |  | as the bDemand pin, latched until the demand level is reached |
| `bCmdEndDemand` | `BOOL` |  | ends a latched demand |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `bCmdResetTotals` | `BOOL` |  | the cycle count back to 0 (cleared) |

**Settings `set`** (`ST_LevelControlSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eControlMode` | `E_LevelMode` |  | Empty (sump, wet well), Fill (tank) or Timed |
| `bRunOnDemandOnly` | `BOOL` |  | the start / stop levels are not used: it runs on bDemand only (high-high still acts) |
| `fStartLevel` | `REAL` |  | start at this level (Empty: at or above; Fill: at or below) |
| `fStopLevel` | `REAL` |  | stop at this level (Empty: at or below; Fill: at or above) |
| `fDemandStopLevel` | `REAL` |  | a demand pumps down / fills to this level |
| `fHighHighLevel` | `REAL` | `3.4E38` | EMPTY: overflow run; FILL: full, no run (3.4E38 / -3.4E38: not used) |
| `fLowLowLevel` | `REAL` | `-3.4E38` | EMPTY: cut-out; FILL: alarm only |
| `eWhenLevelBad` | `E_LevelFail` |  | the level measurement fails: Stop, or RunOn for up to tMaxRunOnTime |
| `stLevelBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#10s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the level measurement is bad; a protection's settings ([protections](../conventions.md#protections)) |
| `tMaxRunOnTime` | `TIME` | `T#10m` | RunOn: the longest run-on on a failed level |
| `fStartLevelVariation` | `REAL` |  | the start moves at random by up to this each cycle (0 = off) |
| `fDemandRestartLevel` | `REAL` |  | a held demand reruns at this level (0 = the start level) |
| `tOnTime` | `TIME` | `T#5m` | TIMED |
| `tOffTime` | `TIME` | `T#5m` | Timed: off time |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_LevelControlSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now |
| `eErrorId` | `E_UtError` |  | the first error since the last reset (first-out) |
| `bLevelCalls` | `BOOL` |  | the level calls for pumping |
| `bDemandActive` | `BOOL` |  | a demand is running (for FB_Stages' demand pumps) |
| `bAtStopLevel` | `BOOL` |  | at or past the stop level |
| `bHighHigh` | `BOOL` |  | at or past the high-high level |
| `bLowLow` | `BOOL` |  | at or past the low-low level |
| `bRunCommand` | `BOOL` |  | what it asks of the pump |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stLevelBadFault` | `ST_ProtectionSts` |  | the level measurement is bad; a protection's status ([protections](../conventions.md#protections)) |
| `fStartLevelInUse` | `REAL` |  | the start level in use (with its variation) |
| `bRunningOnBadLevel` | `BOOL` |  | running on a failed level |

**Details `det`** (`ST_LevelControlDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTimeLeft` | `TIME` |  | RunOn: the run-on left; TIMED: the on / off time left |
| `tInPhaseFor` | `TIME` |  | since the request last changed (pumping / idle) |

**Totals `tot`** (`ST_LevelControlTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCycleCount` | `UDINT` |  | pumping cycles: each new call (pump-down / fill) |

## Lists

- `E_LevelFail`: `Stop`, `RunOn` (default `Stop`)
- `E_LevelMode`: `Empty`, `Fill`, `Timed` (default `Empty`)

## How it works

Keeps a level by driving a pump.

EMPTY (sump, wet well): start at or above `fStartLevel`, stop at or below `fStopLevel`; `bDemand` runs it down to `fDemandStopLevel`; at or above `fHighHighLevel` it always runs (overflow), also with `bRunOnDemandOnly`; at or below `fLowLowLevel` it never runs.

FILL (tank): start at or below `fStartLevel`, stop at or above `fStopLevel`; `bDemand` fills to `fDemandStopLevel`; at or above `fHighHighLevel` it never runs (full); `fLowLowLevel` is an alarm level only.

TIMED: no level needed (`ipLevel` may be unwired): on for `set.tOnTime`, off for `set.tOffTime`, over and over (on first), while `bEnable`. `set.fStartLevelVariation`: the start level moves at random by up to this, either way, after each cycle (fat build-up in a sump; used only when smaller than the start-stop gap). A held `bDemand` that reached `set.fDemandStopLevel` runs again when the level is back at `set.fDemandRestartLevel` (0 = the start level). -> `bDemandActive` (for [`FB_Stages`](FB_Stages.md)' demand pumps). `bRunOnDemandOnly`: the start / stop levels are not used, it runs on `bDemand` only (the high-high still acts in EMPTY). A bad level is ridden through for its protection delay (the request held), then `set.eWhenLevelBad`: Stop or RunOn (keeps the request as it was, for at most `set.tMaxRunOnTime`, then stops).

Parts ([`FB_LevelCheck`](FB_LevelCheck.md), [`FB_Protection`](FB_Protection.md)): a trip stops the request; a signal pauses it (source low, no flow); its parts: float backup ([`FB_LevelFloats`](FB_LevelFloats.md)), cleaning ([`FB_SumpClean`](FB_SumpClean.md)), exercise ([`FB_Exercise`](FB_Exercise.md)), booster ([`FB_Booster`](FB_Booster.md)), level checks ([`FB_LevelCheck`](FB_LevelCheck.md)); beside it: stages ([`FB_Stages`](FB_Stages.md) -> `FB_Group.nExtraMembers`), the inflow estimate ([`FB_VesselFlow`](FB_VesselFlow.md)). `tot.nCycleCount` counts each new call for pumping (kept over a power cut; `bCmdResetTotals` clears it).

No pump: while it asks and its target is neither available nor running (a pump or its motor in Hand or Off, faulted, every group member out), it is in fault: `bError`, `eErrorId` NoneAvailable (a run it serves can end on it, e.g. `bInterlock` := NOT `fbStation.bError`). It clears by itself when the target is available again.

Detail (det): `tTimeLeft` (RunOn: the run-on left under `set.tMaxRunOnTime`; TIMED: the on or off time left; else 0), `tInPhaseFor` (since its request last changed: pumping or idle).

## Example

A sump emptied by a duty / standby group.

| Pin | Wire |
| --- | --- |
| `bEnable` | `fbSystem.bIsAuto` |
| `ipLevel` | `fbSumpLevel` |
| `ipEquipment` | `fbGroup` |
| `refData` | `stLevelCtl` |
| `bHighHigh` | the high-level alarm |

In `stLevelCtl.set`: the mode `Empty`, the start and stop levels, the high-high and low-low.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActHighHighLevel : REAL`: the high-high level in use

## See also

[FB_Pump](FB_Pump.md), [FB_Group](FB_Group.md), [FB_LevelCheck](FB_LevelCheck.md), [FB_LevelFloats](FB_LevelFloats.md), [FB_Stages](FB_Stages.md), [FB_SumpClean](FB_SumpClean.md), [FB_Booster](FB_Booster.md)

**Back to** [the index](../README.md).
