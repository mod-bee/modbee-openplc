# FB_SpeedLoop — Constant pressure / flow / level speed loop

Holds a pressure, flow or level by changing a pump's speed (PID), or runs it at a fixed speed: presets, pipe fill, sleep and wake, a flow limit, and protections for high pressure, a burst main, not reaching the setpoint, hunting and a failed sensor.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | control wanted |
| in | `ipProcessValue` | `I_Measurement` |  | Pv control, stHighProcessValueFault (Flow / Fixed control: may be unwired). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipFlow` | `I_Measurement` |  | Flow control, flow limit, sleep on flow (unwired = none). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipEquipment` | `I_Equipment` |  | required |
| in | `fSetpoint` | `REAL` |  | the setpoint while set.eSetpointFrom = Pin |
| in | `nSetpointPreset` | `INT` | `-1` | 0 Normal, 1 Low, 2 High while wired; -1 = the kept set.eSetpointPreset |
| in | `fExternalSpeedPct` | `REAL` | `-1.0` | External: the speed, %; < 0 = not wired |
| in | `bAddPumpPossible` | `BOOL` |  | an owner can still add a pump: stLowAtMaxSpeedFault waits |
| in | `refData` | `REFERENCE TO ST_SpeedLoopData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fSpeedSetpointPct` | `REAL` |  | the speed asked, % |
| out | `bEquipmentRunning` | `BOOL` |  | the pump runs |
| out | `bAtSetpoint` | `BOOL` |  | within fAtSetpointBand of the setpoint |
| out | `bPipeFilled` | `BOOL` |  | the pipe fill is done in this run |
| out | `fShortOfSetpoint` | `REAL` |  | short of the setpoint by (direction applied; 0 when not good) |
| out | `bAtMaxSpeed` | `BOOL` |  | at the top speed, not held by the flow limit |
| out | `bAtMinSpeed` | `BOOL` |  | at the minimum speed |
| out | `eLoopPhase` | `E_LoopPhase` |  | the phase now |
| out | `bAddPumpNeeded` | `BOOL` |  | at the top speed and short of the setpoint for set.tAddOrDropPumpDelay |
| out | `bDropPumpNeeded` | `BOOL` |  | at the minimum speed for set.tAddOrDropPumpDelay |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SpeedLoopData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdSelectManual` | `BOOL` |  | HMI: manual speed (acts once, cleared by the block) |
| `bCmdSelectAuto` | `BOOL` |  | HMI: automatic control (acts once, cleared by the block) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |

**Settings `set`** (`ST_SpeedLoopSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSetpoint` | `REAL` |  | Pv: the Normal setpoint, in the measurement's unit |
| `fKp` | `REAL` | `10.0` | % speed per unit of error |
| `tTi` | `TIME` | `T#5s` | integral time (0 = P only) |
| `bReverseActing` | `BOOL` |  | the value falls when the speed rises (a level being emptied) |
| `fMinSpeedPct` | `REAL` | `30.0` | lowest speed while running, % |
| `fMaxSpeedPct` | `REAL` | `100.0` | highest speed, % |
| `fSetpointRampRate` | `REAL` |  | setpoint units per eRateUnit (0 = a step) |
| `bManualSelected` | `BOOL` |  | manual speed (kept) |
| `fManualSpeedPct` | `REAL` | `50.0` | speed in manual, % |
| `eWhenValueBad` | `E_OnBadValue` | `E_OnBadValue.Hold` | a bad value under control: Hold, Substitute (fFallbackSpeedPct) or Stop |
| `fFallbackSpeedPct` | `REAL` | `50.0` | a failed sensor (eWhenValueBad Substitute) or a hunting trip: the fallback speed |
| `stProcessValueBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the controlled value is bad; a protection's settings ([protections](../conventions.md#protections)) |
| `eControlBy` | `E_LoopControl` |  | what is controlled: Pv (the measurement), Flow or Fixed speed |
| `eSetpointPreset` | `E_LoopPreset` |  | the operator's preset (kept); the nSetpointPreset pin wins while wired |
| `eSetpointFrom` | `E_SpSource` |  | where the setpoint comes from: Record or Pin |
| `fSetpointLow` | `REAL` |  | Pv: Low (0 = fSetpoint) |
| `fSetpointHigh` | `REAL` |  | Pv: High (0 = fSetpoint) |
| `fFlowSetpoint` | `REAL` |  | Flow: the Normal flow setpoint |
| `fFlowSetpointLow` | `REAL` |  | Flow: Low (0 = fFlowSetpoint) |
| `fFlowSetpointHigh` | `REAL` |  | Flow: High (0 = fFlowSetpoint) |
| `fFixedSpeedPct` | `REAL` | `100.0` | Fixed: Normal speed, % |
| `fFixedSpeedLowPct` | `REAL` | `50.0` | Fixed: Low speed, % |
| `fFixedSpeedHighPct` | `REAL` | `100.0` | Fixed: High speed, % |
| `eSpeedFrom` | `E_LoopSource` |  | Pid (this loop) or External (fExternalSpeedPct) |
| `tTd` | `TIME` |  | derivative time (0 = none) |
| `fDeadband` | `REAL` |  | error ignored inside this |
| `fStartSpeedPct` | `REAL` |  | speed on start, % (limited to fMinSpeedPct .. fMaxSpeedPct: 0 = fMinSpeedPct) |
| `fMaxSpeedChangeRate` | `REAL` | `5.0` | max output change, % per eRateUnit (0 = no limit) |
| `eRateUnit` | `E_RateUnit` |  | fMaxSpeedChangeRate, fSetpointRampRate and stPipeFill.fSetpointRiseRate: per second, minute, hour or day |
| `fAtSetpointBand` | `REAL` | `0.2` | bAtSetpoint band, +/- |
| `stPipeFill` | `ST_LoopFillSet` |  | pipe fill at start: settings; fields below |
| `stSleep` | `ST_LoopSleepSet` |  | sleep on low demand: settings; fields below |
| `fMaxFlow` | `REAL` |  | the speed is reduced to hold the flow below this (0 = off) |
| `fHighProcessValueAbove` | `REAL` |  | Pv above this: stHighProcessValueFault (0 = off) |
| `fHighProcessValueDeadband` | `REAL` |  | ... clears this far below it |
| `stHighProcessValueFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 0)` | the controlled value is too high; a protection's settings ([protections](../conventions.md#protections)) |
| `fLowAtMaxSpeedBelow` | `REAL` |  | the value below this at the top speed: stLowAtMaxSpeedFault (0 = half the setpoint) |
| `stLowAtMaxSpeedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#60s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#5m, nMaxRetriesBeforeLockout := 3)` | low value at the top speed: a burst or lost suction; a protection's settings ([protections](../conventions.md#protections)) |
| `stSetpointNotReachedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#2m, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 0)` | the setpoint is not reached; a protection's settings ([protections](../conventions.md#protections)) |
| `stHuntingFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#0s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 0)` | the loop hunts (too many crossings); a protection's settings ([protections](../conventions.md#protections)) |
| `nMaxCrossings` | `INT` | `6` | crossings allowed in tHuntWindow (1..15) |
| `tHuntWindow` | `TIME` | `T#60s` | (0 = the hunting check off) |
| `fMinSwing` | `REAL` | `0.3` | a crossing counts when the swing is more than this |
| `bRestartAfterReset` | `BOOL` |  | after a needed reset, restart without bRun cycling |
| `tAddOrDropPumpDelay` | `TIME` | `T#30s` | bAddPumpNeeded / bDropPumpNeeded after this long |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**`stPipeFill`** (`ST_LoopFillSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eFillMode` | `E_FillMode` |  | pipe fill at start: Off, Fixed (a fixed speed) or Ramp (a rising setpoint) |
| `fFillSpeedPct` | `REAL` | `50.0` | Fixed: the speed while filling, % |
| `fFilledAbove` | `REAL` |  | the fill is done at this value (0 = 90 % of the setpoint) |
| `fSetpointRiseRate` | `REAL` | `0.1` | Ramp: setpoint rise, units per eRateUnit |
| `stFillTimeoutFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#10m, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 2)` | the fill did not finish in time (FillTimeout); a protection's settings ([protections](../conventions.md#protections)) |

**`stSleep`** (`ST_LoopSleepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSleepAllowed` | `BOOL` |  | sleep when the demand has gone |
| `fSleepBelowSpeedPct` | `REAL` | `35.0` | at or below this speed (and satisfied) ... |
| `fSleepBelowFlow` | `REAL` |  | ... or the flow below this (0 = not used) ... |
| `tSleepDelay` | `TIME` | `T#30s` | ... for this long: boost, then sleep |
| `fBoostPctOfSetpoint` | `REAL` | `5.0` | % of the setpoint added before sleeping |
| `tBoostTime` | `TIME` | `T#10s` | how long the boost lasts |
| `fWakeWhenShortBy` | `REAL` | `0.3` | wake when the value is this far short of the setpoint ... |
| `tWakeDelay` | `TIME` | `T#2s` | ... for this long |
| `tMinSleepTime` | `TIME` | `T#30s` | sleep at least this long |

**Status `sts`** (`ST_SpeedLoopSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now |
| `eErrorId` | `E_UtError` |  | the first error since the last reset (first-out) |
| `fSpeedSetpointPct` | `REAL` |  | the speed asked, % |
| `fProcessValue` | `REAL` |  | the value under control (the flow with Flow control) |
| `fSetpointInUse` | `REAL` |  | the setpoint in use (ramped, fill ramp, boost) |
| `bInManual` | `BOOL` |  | manual speed now |
| `bProcessValueBad` | `BOOL` |  | the controlled value is bad |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stProcessValueBadFault` | `ST_ProtectionSts` |  | the controlled value is bad; a protection's status ([protections](../conventions.md#protections)) |
| `eLoopPhase` | `E_LoopPhase` |  | Idle, Filling, Control, Boost, Sleep, Fallback or Manual |
| `eSetpointPresetInUse` | `E_LoopPreset` |  | the preset in use: Normal, Low or High |
| `bAtSetpoint` | `BOOL` |  | within fAtSetpointBand of the setpoint |
| `bPipeFilled` | `BOOL` |  | the pipe fill is done in this run |
| `bSleeping` | `BOOL` |  | asleep on low demand |
| `bFlowLimiting` | `BOOL` |  | the speed is held back by fMaxFlow |
| `nCrossingCount` | `INT` |  | setpoint crossings counted in the window |
| `stHighProcessValueFault` | `ST_ProtectionSts` |  | the controlled value is too high; a protection's status ([protections](../conventions.md#protections)) |
| `stLowAtMaxSpeedFault` | `ST_ProtectionSts` |  | low value at the top speed: a burst or lost suction; a protection's status ([protections](../conventions.md#protections)) |
| `stFillTimeoutFault` | `ST_ProtectionSts` |  | fill timeout status; a protection's status ([protections](../conventions.md#protections)) |
| `stSetpointNotReachedFault` | `ST_ProtectionSts` |  | the setpoint is not reached; a protection's status ([protections](../conventions.md#protections)) |
| `stHuntingFault` | `ST_ProtectionSts` |  | the loop hunts (too many crossings); a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_SpeedLoopDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fProportionalPart` | `REAL` |  | the PID's parts, % speed |
| `fIntegralPart` | `REAL` |  | the PID's integral part, % speed |
| `fDerivativePart` | `REAL` |  | the PID's derivative part, % speed |
| `tInPhaseFor` | `TIME` |  | time in the present phase |

## Lists

- `E_FillMode`: `Off`, `Fixed`, `Ramp` (default `Off`)
- `E_LoopControl`: `Pv`, `Flow`, `Fixed` (default `Pv`)
- `E_LoopPhase`: `Idle`, `Filling`, `Control`, `Boost`, `Sleep`, `Fallback`, `Manual` (default `Idle`)
- `E_LoopPreset`: `Normal`, `Low`, `High` (default `Normal`)
- `E_LoopSource`: `Pid`, `External` (default `Pid`)
- `E_SpSource`: `Record`, `Pin` (default `Record`)

## How it works

Constant pressure / flow / level with a speed drive. It owns its pump: while asked to run it requests the pump (an [`FB_Pump`](FB_Pump.md) on an [`FB_MotorVsd`](FB_MotorVsd.md), an [`FB_MotorVsd`](FB_MotorVsd.md), or an [`FB_Group`](FB_Group.md)) at the speed that holds the value at the setpoint.

What the speed follows (`set.eControlBy`): Pv, the PID on `ipProcessValue`; Flow, the PID on `ipFlow`; Fixed, a fixed speed (no PID; a bad sensor does not stop it). Presets Normal / Low / High: Pv `set.fSetpoint` / `fSetpointLow` / `fSetpointHigh`, Flow `set.fFlowSetpoint` / `fFlowSetpointLow` / `fFlowSetpointHigh`, Fixed `set.fFixedSpeedPct` / `fFixedSpeedLowPct` / `fFixedSpeedHighPct` (a Low or High setpoint of 0 uses the Normal one). Pv control takes its setpoint from the record (`set.eSetpointFrom` = Record) or the `fSetpoint` pin (Pin). A setpoint in use of 0 (or not a number), a missing measurement or a missing `fExternalSpeedPct` is a configuration fault while `bRun`: no run. speed = `fKp` * (e + 1/`tTi` * integral(e dt) + `tTd` * de/dt)      (% speed) e = sp - value (`set.bReverseActing`: value - sp, for a level emptied by the pump); inside `set.fDeadband` e = 0.

Anti-windup: the integral stays inside the output limits and stops while a limit or the rate limit holds the output. Bumpless: whenever the loop takes the output back (a start, the end of manual, fallback or a fill), the integral is loaded from the speed it has. A start begins at `set.fStartSpeedPct` (limited to the speed range: 0 = `set.fMinSpeedPct`). `set.fMaxSpeedChangeRate` limits the output change (% per `set.eRateUnit`, 0 = no limit); `set.fSetpointRampRate` ramps the setpoint (units per `set.eRateUnit`, 0 = a step). `set.eSpeedFrom` = External: the speed follows `fExternalSpeedPct` (held at the last value while it is not a number), with the same limits, protections and sleep.

Manual (the record's `bCmdSelectManual` / `bCmdSelectAuto`, kept in `set.bManualSelected`): `set.fManualSpeedPct`; the protections still act.

Phases (`eLoopPhase`): Idle -> Filling (optional) -> Control -> Boost -> Sleep -> Control; Fallback at a fixed speed after a hunting trip or with a failed sensor; Manual at the manual (or Fixed control's) speed.

Pipe fill (`set.stPipeFill`; Pv control, not reverse acting): `eFillMode` Fixed runs at `fSpeedSetpointPct` until the value reaches `fFilledAbove` (0 = 90 % of the setpoint); Ramp raises the setpoint from the value at `fSetpointRiseRate` (per `set.eRateUnit`) to the setpoint. A fill longer than `stFillTimeoutFault`'s delay acts per `stFillTimeoutFault` (FillTimeout). After a manual or fallback spell the fill runs again only if the line has not been full in this run. `bPipeFilled`: the line is full.

Sleep (`set.stSleep.bSleepAllowed`): satisfied (within `fAtSetpointBand` of the setpoint, or past it) at or below `fSpeedSetpointPct`, or with the flow below `fSleepBelowFlow` (0 = not used), for `tSleepDelay`: the setpoint is raised by `fBoostPctOfSetpoint` % for `tBoostTime`, then the pump stops (`eState` Waiting). It wakes when the value is `fWakeWhenShortBy` short of the setpoint for `tWakeDelay`, after at least `tMinSleepTime`.

Flow limit (`set.fMaxFlow`, 0 = off): the speed is brought down to hold the flow below it (`sts.bFlowLimiting`).

Protections (each a `ST_ProtectionSet`: off / warn / trip / signal, delay, reset; [`F_Protect`](F_Protect.md)):

```
  stHighProcessValueFault       Pv above set.fHighProcessValueAbove (0 = off; clears set.fHighProcessValueDeadband below it): a trip stops the pump
                 (PressureHigh); a warning holds the minimum speed while it lasts.
  stLowAtMaxSpeedFault     the value below set.fLowAtMaxSpeedBelow (0 = half the setpoint, direct acting only) at the top speed in
                 control, while no more pump can be added (bAddPumpPossible FALSE): a burst main (LowAtMax).
  stPipeFill.stFillTimeoutFault  the pipe fill took too long (FillTimeout).
  stSetpointNotReachedFault  in control, not at a speed limit, the value outside fAtSetpointBand of the setpoint (NotReaching).
  stHuntingFault      more than set.nMaxCrossings (1..15) crossings of the setpoint (each a swing beyond fMinSwing) in
                 set.tHuntWindow (0 = off) (Hunting): a trip runs at set.fFallbackSpeedPct (Fallback) until reset.
```

A bad or unfitted measurement under control: the speed is held at once; past `set.stProcessValueBadFault`'s delay `set.eWhenValueBad` Hold (the last speed; a sleeping pump stays asleep), Fixed (`set.fFallbackSpeedPct`) or Stop (SensorBad). Control resumes when `stProcessValueBadFault` clears (its `tAutoRecoverAfter`: the sensor good this long).

Restart: after a reset that was needed (Manual reset, or a Retry lockout) the loop waits for `bRun` to cycle, unless `set.bRestartAfterReset`. `bAtSetpoint`: in control, boost or sleep, the value within `set.fAtSetpointBand` of the setpoint in use. `fShortOfSetpoint`: how far the value is short of the setpoint (`set.bReverseActing`: above it), 0 when not good; with Fixed control Pv against the setpoint in use (0 when that is 0), for a fixed-speed set staged on bands; with `bAtMaxSpeed` (at the top of the speed range, not held by the flow limit) and `bAtMinSpeed` it feeds [`FB_Cascade`](FB_Cascade.md)'s staging. `bAddPumpNeeded`: in control at the top speed and short of the setpoint by more than `fAtSetpointBand` for `set.tAddOrDropPumpDelay`; `bDropPumpNeeded`: in control at the minimum speed for `set.tAddOrDropPumpDelay` (hints for an owner adding or dropping pumps; a highPv warning stops both). `bPipeFilled` can drive a pump's prime-done input; `stLowAtMaxSpeedFault` is the lost-prime check.

Detail (det): the PID's parts `fP` / `fI` / `fD` (% speed) and `tInPhaseFor` (time in the present phase).

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back (`sts.bSettingRefused` / `eSettingRefusedErrorId`, a warning until a reset).

## Example

A constant-pressure supply on one VSD pump.

| Pin | Wire |
| --- | --- |
| `bRun` | `fbSystem.bIsAuto` |
| `ipProcessValue` | `fbPressure` (an FB_AnalogIn) |
| `ipEquipment` | `fbPump1` (an FB_Pump on an FB_MotorVsd) |
| `refData` | `stLoop` |

Set the setpoint, `fKp` and `tTi` in `stLoop.set`.

**Back to** [the index](../README.md).
