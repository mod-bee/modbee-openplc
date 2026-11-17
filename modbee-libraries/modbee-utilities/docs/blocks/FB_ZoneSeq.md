# FB_ZoneSeq — Irrigation zone program

An irrigation or wash-down program: the zones watered in turn, by time or by volume, in a safe valve and pump order, with a master valve, repeats, rain action, cycles and soak, a pump wait, a dosing hook and a resume after a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` | `FALSE` | held: the program runs while held |
| in | `bStart` | `BOOL R_EDGE` |  | rising edge: a latched run Acts on its rising edge. |
| in | `bStop` | `BOOL R_EDGE` |  | rising edge: ends it, wins Acts on its rising edge. |
| in | `bPause` | `BOOL` |  | held: the pump stops and the valves close as at the end; the zone keeps its progress |
| in | `bSkip` | `BOOL R_EDGE` |  | rising edge: the watering zone is done now Acts on its rising edge. |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE ends the program and refuses a start |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE holds back the start of the program or of the next zone |
| in | `bLevelEnd` | `BOOL` |  | the source is at its stop level: ends the program |
| in | `bIrrigatorStop` | `BOOL` |  | the irrigator's fail-safe: ends the program and refuses a start |
| in | `ipPump` | `I_Equipment` |  | the pump, a group or a level control: optional. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `bPumpRunning` | `BOOL` |  | with no ipPump: the pump runs |
| in | `bPumpFault` | `BOOL` |  | the supply has tripped: no water counts and the wait for it runs |
| in | `bRainHold` | `BOOL` |  | rain (or wet soil): acts per set.eRainAction |
| in | `ipMeter` | `I_Meter` |  | for zones by volume and the flow check: optional. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `ipMasterValve` | `I_Equipment` |  | the master valve: optional. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `nRunZone` | `INT` |  | at the start: 0 = the program, n = only zone n, index in aZones |
| in | `nDoseReq` | `INT` | `-1` | at the start: -1 = set.bDose, 0 no, 1 dose this run |
| in | `refData` | `REFERENCE TO ST_ZoneSeqData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aZones` | `ARRAY[*] OF FB_Zone` |  | The FB_Zone instances, in run order (`ARRAY[1..n] OF FB_Zone`) |
| out | `bPumpDemand` | `BOOL` |  | Ask for the pump (with no `ipPump`) |
| out | `bActive` | `BOOL` |  | Active now |
| out | `nZone` | `INT` |  | the zone watering, 0 = none |
| out | `bDoseEnable` | `BOOL` |  |  |
| out | `bDoseHold` | `BOOL` |  |  |
| out | `fZoneSp` | `REAL` |  | the watering zone's pressure setpoint |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ZoneSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | Start (HMI command; acts once, cleared by the block) |
| `bCmdStop` | `BOOL` |  | Stop (HMI command; acts once, cleared by the block) |
| `bCmdSkip` | `BOOL` |  |  |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |
| `nCmdRunZone` | `INT` | `-1` | run only this zone (index in aZones): a start; then -1 |

**Settings `set`** (`ST_ZoneSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPumpStartDelay` | `TIME` | `T#3s` |  |
| `tValveOverlap` | `TIME` | `T#5s` |  |
| `tValveCloseDelay` | `TIME` | `T#5s` |  |
| `tValveProve` | `TIME` | `T#30s` |  |
| `tMasterCloseDelay` | `TIME` |  | the master valve closes this long after the last zone valve |
| `tFlushTime` | `TIME` | `T#2m` | dosing stops this long before a zone cycle ends |
| `tMaxPumpWait` | `TIME` |  | no pump this long ends the program (0 = wait for ever) |
| `bPumpWaitSkips` | `BOOL` |  | ... or skips the zone |
| `bDose` | `BOOL` |  | runs dose by default (nDoseReq -1) |
| `nRepeats` | `INT` | `1` | the program runs this many passes (1..100) |
| `eRainAction` | `E_RainAction` |  | what bRainHold does |
| `fDefaultSp` | `REAL` |  | the pressure setpoint of a zone with none of its own |
| `eResume` | `E_RunResume` | `E_RunResume.Resume` | a program that was on at a power cut |
| `tResumeWindow` | `TIME` | `T#1m` | a held run: its bRun must be back within this, else it ends |
| `tMaxTime` | `TIME` |  | the cap of a zone cycle whose only target is a volume (0 = worked out) |
| `tDefaultCap` | `TIME` | `T#2h` | ... when there is no tMaxTime and no zone minimum flow |

**Status `sts`** (`ST_ZoneSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | The first error since the last reset (first-out) |
| `ePhase` | `E_ZonePhase` |  | The phase now (status) |
| `nZone` | `INT` |  | the zone watering, 0 = none |
| `bActive` | `BOOL` |  | Active now |
| `eStopReason` | `E_StopReason` |  | Why it last stopped |
| `nRunZone` | `INT` |  | the one zone of this run (0 = the program) |
| `nPass` | `INT` |  | the pass running |
| `bRainHold` | `BOOL` |  | wire FB_IrrDefer's bDefer to it; its bToStorage goes to the route |
| `bMasterWanted` | `BOOL` |  |  |
| `bDoseOn` | `BOOL` |  |  |
| `tPumpWait` | `TIME` |  | the time with no water for want of the pump |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Lists

- `E_RainAction`: `Pause`, `Skip`, `Cancel`, `Ignore` (default `Pause`)
- `E_ZonePhase`: `Idle`, `Opening`, `Watering`, `Changing`, `Ending`, `Paused`, `Soaking` (default `Idle`)

## How it works

An irrigation / wash-down zone program: the zones (`aZones`, the project's [`FB_Zone`](FB_Zone.md) instances in run order, each with its own valve and settings) watered in turn, by time or by volume, in a safe valve and pump order.

Order, so the pump never deadheads or hammers:

```
  start   the zone's valve (and the master valve) opens; once they are proven, set.tPumpStartDelay later the pump
          is asked;
  change  the next zone's valve opens; once it is proven, set.tValveOverlap later the last one closes;
  end     the pump is released; the valves close once set.tValveCloseDelay has passed AND the pump has stopped; the
          master valve set.tMasterCloseDelay after the last zone valve.
```

Water counts only while the pump runs and has no fault, for the zone watering (not during a change: the overlap is hydraulic). A zone's valve not proven within `set.tValveProve`: that zone is skipped (a warning). A zone whose rung is not called is not in the program. A master valve that is refused, faulted or not open within `set.tValveProve` ends the program (stop reason Fault, error MasterValve) until a reset or the next start.

Zone cycles: a zone with `set.nCycles` > 1 gives its water in cycles; when a cycle is given and no other zone is ready, the pump stops and the valves close as at the end (phase Soaking) until a zone has soaked (`set.tSoakTime`) and is ready again; the program ends when no zone has water left.

Zone cycle cap: a cycle whose only target is a volume ends at a time cap (see [`FB_Zone`](FB_Zone.md): `set.tMaxTime`, else the volume at the zone's minimum flow, else `set.tDefaultCap`) with a warning RunCapped, so a dry meter cannot water for ever.

Flow check: the zone watering is told the meter's flow every scan (see [`FB_Zone`](FB_Zone.md)); a zone that trips on it is out of the program (a warning ZoneFlow).

Pump wait: with no pump running (or `bPumpFault`) while a zone should water, the time is counted (`sts.tPumpWait`); at `set.tMaxPumpWait` (0 = wait for ever) the program ends (stop reason PumpFault, error PumpWait) or, with `set.bPumpWaitSkips`, that zone is skipped (a warning).

One zone: `nRunZone` (at the start), the record's `nCmdRunZone` (a start, then -1) or a start while idle runs only that zone (it need not be enabled), one pass.

Dosing hook: `bDoseEnable` = this run doses (`nDoseReq` / `set.bDose`, read at the start): wire it to `FB_Dose.bRun`. `bDoseHold` = pause the injection now: no zone is watering with the pump running, or the zone may not be dosed ([`FB_Zone`](FB_Zone.md) `set.bDose`), or its cycle has `set.tFlushTime` or less to run (the pipe is flushed with clean water before the valve closes): wire it to `FB_Dose.bHold`.

End reasons (`sts.eStopReason`): Done, Request (stop, held run dropped), Interlock, LevelEnd, IrrigatorStop, PumpFault (the pump wait), Fault (the master valve).

Repeats: `set.nRepeats` (1..100) runs the whole program that many times (a one-zone run is one pass); `sts.nPass`.

Rain: `bRainHold` (wire [`FB_IrrDefer`](FB_IrrDefer.md)'s `bDefer` to it; its `bToStorage` goes to the route) acts per `set.eRainAction`: Pause holds the program (pump off, valves closed as at the end; the zones keep their progress) until it is gone; Skip ends the zone watering and every zone not yet done (the program ends Done); Cancel ends the program (stop reason Rain); Ignore does nothing. The active zone's pressure setpoint is `fZoneSp`: the zone's `set.fPressure`, else `set.fDefaultSp` (wire it to [`FB_SpeedLoop`](FB_SpeedLoop.md)'s `fSp` pin, with its `set.eSpSource` Pin).

Power cut: the program's place (running, latched or held, the zone, the pass, a one-zone run, the dose choice) is kept at each start, change of zone, new pass and end; each zone keeps its own progress. After a cut, `set.eResume`: Resume goes on at the same zone (its valves start closed, its time and cycles kept); a latched run goes on at once, a held one when its `bRun` is back within `set.tResumeWindow`, else it ends (PowerCut); Restart does the same from the first zone and pass; None ends it (stop reason PowerCut). At most the water of the last hour in a zone is repeated (the zone saves its watered time hourly).

## Example

Four zones watered by volume from one pump.

| Pin | Wire |
| --- | --- |
| `bStart` | `fbSchedule.bActive` |
| `bStop` | `DI_ProgramStop` |
| `bPermissive` | `NOT fbDefer.bDefer` |
| `aZones` | `aZones` |
| `ipPump` | `fbPump1` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stZones` |

## See also

[FB_Zone](FB_Zone.md), [FB_Schedule](FB_Schedule.md), [FB_IrrDefer](FB_IrrDefer.md), [FB_Route](FB_Route.md)

**Back to** [the index](../README.md).
