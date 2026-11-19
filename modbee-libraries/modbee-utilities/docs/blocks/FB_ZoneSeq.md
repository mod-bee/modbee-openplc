# FB_ZoneSeq — Irrigation zone program

An irrigation or wash-down program: the zones watered in turn, by time or by volume, in a safe valve and pump order, with a master valve, repeats, rain action, cycles and soak, a pump wait, a dosing hook and a resume after a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` | `FALSE` | held: the program runs while held |
| in | `bStart` | `BOOL R_EDGE` |  | rising edge: a latched program run |
| in | `bStop` | `BOOL R_EDGE` |  | rising edge: ends it; wins over a start |
| in | `bPause` | `BOOL` |  | held: the pump stops and the valves close as at the end; the zone keeps its progress |
| in | `bSkipZone` | `BOOL R_EDGE` |  | rising edge: the watering zone is done now |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE ends the program and refuses a start |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE holds back the start of the program or of the next zone |
| in | `bSourceAtStopLevel` | `BOOL` |  | the source is at its stop level: ends the program |
| in | `bIrrigatorTripped` | `BOOL` |  | the irrigator's fail-safe: ends the program and refuses a start |
| in | `ipPump` | `I_Equipment` |  | the pump, a group or a level control (optional) |
| in | `bPumpRunning` | `BOOL` |  | with no ipPump: the pump runs |
| in | `bPumpFaulted` | `BOOL` |  | the supply has tripped: no water counts and the wait for it runs |
| in | `bDeferIrrigation` | `BOOL` |  | rain (or wet soil): acts per set.eActionOnDefer |
| in | `ipMeter` | `I_Meter` |  | the flow meter for zones by volume and the flow check (optional). An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `ipMasterValve` | `I_Equipment` |  | the master valve (optional) |
| in | `nRunOnlyZone` | `INT` |  | at the start: 0 = the program, n = only zone n (index in aZones) |
| in | `nDoseRequest` | `INT` | `-1` | at the start: -1 = bDoseByDefault, 0 = no, 1 = dose this run |
| in | `tRunTime` | `TIME` |  | at the start: each zone's water time this run (0 = its own set.tWaterTime) |
| in | `refData` | `REFERENCE TO ST_ZoneSeqData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aZones` | `ARRAY[*] OF FB_Zone` |  | the FB_Zone instances, in run order (ARRAY[1..n] OF FB_Zone) |
| out | `bPumpRunCommand` | `BOOL` |  | ask for the pump (with no ipPump) |
| out | `bBusy` | `BOOL` |  | the program is on |
| out | `nZoneWatering` | `INT` |  | the zone watering (0 = none) |
| out | `bDosingAllowed` | `BOOL` |  | dosing may run now |
| out | `bDosingPaused` | `BOOL` |  | pause the injection now: no zone watering with the pump running, or the zone may not be dosed |
| out | `fZonePressureSetpoint` | `REAL` |  | the watering zone's pressure setpoint |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ZoneSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | HMI: start the program (acts once, cleared by the block) |
| `bCmdStop` | `BOOL` |  | HMI: stop the program (acts once, cleared by the block) |
| `bCmdSkipZone` | `BOOL` |  | HMI: the watering zone is done now (acts once) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `nCmdRunOnlyZone` | `INT` | `-1` | run only this zone (index in aZones): a start; then -1 |
| `bCmdPause` | `BOOL` |  | pause (latched until bCmdResume, or the program ends); cleared by the block |
| `bCmdResume` | `BOOL` |  | cleared by the block |

**Settings `set`** (`ST_ZoneSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPumpStartDelay` | `TIME` | `T#3s` | after the first valve opens, the pump starts this long later |
| `tValveOverlap` | `TIME` | `T#5s` | the next zone's valve opens this long before the last one closes |
| `tValveCloseDelay` | `TIME` | `T#5s` | after the pump stops, the valve closes this long later |
| `tValveProveTimeout` | `TIME` | `T#30s` | a valve must prove open within this |
| `tMasterCloseDelay` | `TIME` |  | the master valve closes this long after the last zone valve |
| `tFlushTime` | `TIME` | `T#2m` | dosing stops this long before a zone cycle ends |
| `tPumpWaitTimeout` | `TIME` |  | no pump this long ends the program (0 = wait for ever) |
| `bPumpWaitSkipsZone` | `BOOL` |  | ... or skips the zone |
| `bDoseByDefault` | `BOOL` |  | runs dose by default (nDoseRequest -1) |
| `nPasses` | `INT` | `1` | the program runs this many passes (1..100) |
| `eActionOnDefer` | `E_RainAction` |  | what bDeferIrrigation does |
| `fDefaultPressureSetpoint` | `REAL` |  | the pressure setpoint of a zone with none of its own |
| `eAfterPowerCut` | `E_RunResume` | `E_RunResume.Resume` | a program that was on at a power cut |
| `tHeldRunTimeout` | `TIME` | `T#1m` | a held run: its bRun must be back within this, else it ends |
| `tMaxVolumeCycleTime` | `TIME` |  | the cap of a zone cycle whose only target is a volume (0 = worked out) |
| `tDefaultTimeCap` | `TIME` | `T#2h` | ... when there is no tMaxVolumeCycleTime and no zone minimum flow |
| `tMaxPauseBeforeEnd` | `TIME` |  | a pause this long ends the program (0 = no limit) |
| `tProgressSaveInterval` | `TIME` |  | keep the zone's progress this often while watering (0 = on events only) |

**Status `sts`** (`ST_ZoneSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now |
| `eErrorId` | `E_UtError` |  | the first error since the last reset (first-out) |
| `eZonePhase` | `E_ZonePhase` |  | Idle, Opening, Watering, Changing, Ending, Paused or Soaking |
| `nZoneWatering` | `INT` |  | the zone watering (0 = none) |
| `bBusy` | `BOOL` |  | the program is on |
| `eStopReason` | `E_StopReason` |  | why it last stopped |
| `nRunOnlyZone` | `INT` |  | the one zone of this run (0 = the program) |
| `nPassRunning` | `INT` |  | the pass running |
| `bDeferIrrigation` | `BOOL` |  | rain or wet soil holds the program (wire FB_IrrDefer.bDeferIrrigation) |
| `bMasterValveOpenCommand` | `BOOL` |  | the master valve is asked open |
| `bDosingAllowed` | `BOOL` |  | dosing is allowed now |
| `tWaitingForPump` | `TIME` |  | the time with no water for want of the pump |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `bPaused` | `BOOL` |  | held (bPause, bCmdPause, a rain pause, a resume wait) |
| `nRunCount` | `UDINT` |  | programs started since power-up |
| `fDeliveredThisRun` | `LREAL` |  | this program's water (the meter) |

**Details `det`** (`ST_ZoneSeqDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPassTimeLeft` | `TIME` |  | this pass's time left (the time zones not done) |
| `tInPhaseFor` | `TIME` |  | time in the present phase |

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

Water counts only while the pump runs and has no fault, for the zone watering (not during a change: the overlap is hydraulic). A zone's valve not proven within `set.tValveProveTimeout`: that zone is skipped (a warning). A zone whose rung is not called is not in the program. A master valve that is refused, faulted or not open within `set.tValveProveTimeout` ends the program (stop reason Fault, error MasterValve) until a reset or the next start.

Zone cycles: a zone with `set.nCycles` > 1 gives its water in cycles; when a cycle is given and no other zone is ready, the pump stops and the valves close as at the end (phase Soaking) until a zone has soaked (`set.tSoakTime`) and is ready again; the program ends when no zone has water left.

Zone cycle cap: a cycle whose only target is a volume ends at a time cap (see [`FB_Zone`](FB_Zone.md): `set.tMaxVolumeCycleTime`, else the volume at the zone's minimum flow, else `set.tDefaultTimeCap`) with a warning RunCapped, so a dry meter cannot water for ever.

Flow check: the zone watering is told the meter's flow every scan (see [`FB_Zone`](FB_Zone.md)); a zone that trips on it is out of the program (a warning ZoneFlow).

Pump wait: with no pump running (or `bPumpFaulted`) while a zone should water, the time is counted (`sts.tWaitingForPump`); at `set.tPumpWaitTimeout` (0 = wait for ever) the program ends (stop reason PumpFault, error PumpWait) or, with `set.bPumpWaitSkipsZone`, that zone is skipped (a warning).

One zone: `nRunOnlyZone` (at the start), the record's `nCmdRunOnlyZone` (a start, then -1) or a start while idle runs only that zone (it need not be enabled), one pass.

Dosing hook: `bDosingAllowed` = this run doses (`nDoseRequest` / `set.bDoseByDefault`, read at the start): wire it to `FB_Dose.bRun`. `bDosingPaused` = pause the injection now: no zone is watering with the pump running, or the zone may not be dosed ([`FB_Zone`](FB_Zone.md) `set.bDoseByDefault`), or its cycle has `set.tFlushTime` or less to run (the pipe is flushed with clean water before the valve closes): wire it to `FB_Dose.bPause`.

End reasons (`sts.eStopReason`): Done, Request (stop, held run dropped), Interlock, LevelEnd, IrrigatorStop, PumpFault (the pump wait), Fault (the master valve).

Repeats: `set.nPasses` (1..100) runs the whole program that many times (a one-zone run is one pass); `sts.nPassRunning`.

Rain: `bDeferIrrigation` (wire [`FB_IrrDefer`](FB_IrrDefer.md)'s `bDeferIrrigation` to it; its `bSendToStorage` goes to the route) acts per `set.eActionOnDefer`: Pause holds the program (pump off, valves closed as at the end; the zones keep their progress) until it is gone; Skip ends the zone watering and every zone not yet done (the program ends Done); Cancel ends the program (stop reason Rain); Ignore does nothing. The active zone's pressure setpoint is `fZonePressureSetpoint`: the zone's `set.fPressureSetpoint`, else `set.fDefaultPressureSetpoint` (wire it to [`FB_SpeedLoop`](FB_SpeedLoop.md)'s `fSetpoint` pin, with its `set.eSetpointFrom` Pin).

Power cut: the program's place (running, latched or held, the zone, the pass, a one-zone run, the dose choice) is kept at each start, change of zone, new pass and end; each zone keeps its own progress. After a cut, `set.eAfterPowerCut`: Resume goes on at the same zone (its valves start closed, its time and cycles kept); a latched run goes on at once, a held one when its `bRun` is back within `set.tHeldRunTimeout`, else it ends (PowerCut); Restart does the same from the first zone and pass; None ends it (stop reason PowerCut). At most the water of the last hour in a zone is repeated (the zone saves its watered time hourly).

Pause from the record: `bCmdPause` holds the program as `bPause` does, until `bCmdResume` (or the program ends); `set.tMaxPauseBeforeEnd` > 0: a pause that long ends the program (stop reason PauseMax). `set.tProgressSaveInterval` > 0: the watering zone's progress is kept that often (else on its events), so a power cut loses at most that much. Status: `sts.bPaused`, `sts.nRunCount` (programs started since power-up), `sts.fDeliveredThisRun` (this program's water); `det.tPassTimeLeft` (this pass's time left over the timed zones not done), `det.tInPhaseFor`. Each zone shows how it ended ([`FB_Zone`](FB_Zone.md) `sts.eLastOutcome`, `sts.bSkipped`).

## Example

Four zones watered by volume from one pump.

| Pin | Wire |
| --- | --- |
| `bStart` | `fbSchedule.bScheduleActive` |
| `bStop` | `DI_ProgramStop` |
| `bPermissive` | `NOT fbDefer.bDeferIrrigation` |
| `aZones` | `aZones` |
| `ipPump` | `fbPump1` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stZones` |

## See also

[FB_Zone](FB_Zone.md), [FB_Schedule](FB_Schedule.md), [FB_IrrDefer](FB_IrrDefer.md), [FB_Route](FB_Route.md)

**Back to** [the index](../README.md).
