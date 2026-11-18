# FB_SpeedLoop — Constant pressure / flow / level speed loop

Holds a pressure, flow or level by changing a pump's speed (PID), or runs it at a fixed speed: presets, pipe fill, sleep and wake, a flow limit, and protections for high pressure, a burst main, not reaching the setpoint, hunting and a failed sensor.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | control wanted |
| in | `ipPv` | `I_Measurement` |  | Pv control, stHighPv (Flow / Fixed control: may be unwired). A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipFlow` | `I_Measurement` |  | Flow control, flow limit, sleep on flow (unwired = none). A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipTarget` | `I_Equipment` |  | required. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `fSp` | `REAL` |  | the setpoint while set.eSpSource = Pin |
| in | `nPreset` | `INT` | `-1` | 0 Normal, 1 Low, 2 High while wired; -1 = the kept set.ePreset |
| in | `fExtSpeed` | `REAL` | `-1.0` | External: the speed, %; < 0 = not wired |
| in | `bMoreAvailable` | `BOOL` |  | an owner can still add a pump: stLowAtMax waits |
| in | `refData` | `REFERENCE TO ST_SpeedLoopData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fSpeed` | `REAL` |  | the speed asked, % |
| out | `bRunning` | `BOOL` |  | the pump runs |
| out | `bAtSetpoint` | `BOOL` |  |  |
| out | `bFilled` | `BOOL` |  | the pipe fill is done in this run |
| out | `fError` | `REAL` |  | short of the setpoint by (direction applied; 0 when not good) |
| out | `bAtMax` | `BOOL` |  | at the top speed, not held by the flow limit |
| out | `bAtMin` | `BOOL` |  | at the minimum speed |
| out | `ePhase` | `E_LoopPhase` |  | The phase now (status) |
| out | `bMoreNeeded` | `BOOL` |  | at the top speed and short of the setpoint for set.tStageDelay |
| out | `bLessNeeded` | `BOOL` |  | at the minimum speed for set.tStageDelay |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SpeedLoopData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdManual` | `BOOL` |  |  |
| `bCmdAuto` | `BOOL` |  |  |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_SpeedLoopSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSp` | `REAL` |  | Pv: the Normal setpoint, in the measurement's unit |
| `fKp` | `REAL` | `10.0` | % speed per unit of error |
| `tTi` | `TIME` | `T#5s` | integral time (0 = P only) |
| `bReverse` | `BOOL` |  | the value falls when the speed rises (a level being emptied) |
| `fMinSpeed` | `REAL` | `30.0` |  |
| `fMaxSpeed` | `REAL` | `100.0` |  |
| `fSpRamp` | `REAL` |  | setpoint units per eRateUnit (0 = a step) |
| `bManual` | `BOOL` |  | manual speed (kept) |
| `fManualSpeed` | `REAL` | `50.0` |  |
| `eOnBad` | `E_OnBad` |  |  |
| `fFailSpeed` | `REAL` | `50.0` | a failed sensor (Fixed) or a hunting trip: the fallback speed |
| `stPvBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `eControl` | `E_LoopControl` |  |  |
| `ePreset` | `E_LoopPreset` |  | the operator's preset (kept); the nPreset pin wins while wired |
| `eSpSource` | `E_SpSource` |  |  |
| `fSpLow` | `REAL` |  | Pv: Low (0 = fSp) |
| `fSpHigh` | `REAL` |  | Pv: High (0 = fSp) |
| `fFlowSp` | `REAL` |  | Flow: the Normal flow setpoint |
| `fFlowSpLow` | `REAL` |  | Flow: Low (0 = fFlowSp) |
| `fFlowSpHigh` | `REAL` |  | Flow: High (0 = fFlowSp) |
| `fFixedSpeed` | `REAL` | `100.0` | Fixed: Normal speed, % |
| `fFixedSpeedLow` | `REAL` | `50.0` | Fixed: Low speed, % |
| `fFixedSpeedHigh` | `REAL` | `100.0` | Fixed: High speed, % |
| `eSource` | `E_LoopSource` |  |  |
| `tTd` | `TIME` |  | derivative time (0 = none) |
| `fDeadband` | `REAL` |  | error ignored inside this |
| `fStartSpeed` | `REAL` |  | speed on start, % (limited to fMinSpeed .. fMaxSpeed: 0 = fMinSpeed) |
| `fRateLimit` | `REAL` | `5.0` | max output change, % per eRateUnit (0 = no limit) |
| `eRateUnit` | `E_RateUnit` |  | fRateLimit, fSpRamp and stFill.fRate: per second, minute, hour or day |
| `fAtSpBand` | `REAL` | `0.2` | bAtSetpoint band, +/- |
| `stFill` | `ST_LoopFillSet` |  | fields below |
| `stSleep` | `ST_LoopSleepSet` |  | fields below |
| `fFlowLimit` | `REAL` |  | the speed is reduced to hold the flow below this (0 = off) |
| `fHighPv` | `REAL` |  | Pv above this: stHighPv (0 = off) |
| `fHighPvDeadband` | `REAL` |  | ... clears this far below it |
| `stHighPv` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `fLowAtMax` | `REAL` |  | the value below this at the top speed: stLowAtMax (0 = half the setpoint) |
| `stLowAtMax` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#60s, eReset := E_ResetMode.Retry, tRecover := T#5m, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stNotReaching` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#2m, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stHunting` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `nHuntCycles` | `INT` | `6` | crossings allowed in tHuntWindow (1..15) |
| `tHuntWindow` | `TIME` | `T#60s` | (0 = the hunting check off) |
| `fHuntBand` | `REAL` | `0.3` | a crossing counts when the swing is more than this |
| `bRestartAfterReset` | `BOOL` |  | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `tStageDelay` | `TIME` | `T#30s` | bMoreNeeded / bLessNeeded after this long |

**`stFill`** (`ST_LoopFillSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_FillMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `fSpeed` | `REAL` | `50.0` | Fixed: the speed while filling, % |
| `fTarget` | `REAL` |  | the fill is done at this value (0 = 90 % of the setpoint) |
| `fRate` | `REAL` | `0.1` | Ramp: setpoint rise, units per eRateUnit |
| `stTimeout` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#10m, eReset := E_ResetMode.Retry, tRecover := T#10s, nMaxRetries := 2)` | FillTimeout; a protection's settings ([protections](../conventions.md#protections)) |

**`stSleep`** (`ST_LoopSleepSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` |  | sleep when the demand has gone |
| `fSpeed` | `REAL` | `35.0` | at or below this speed (and satisfied) ... |
| `fFlow` | `REAL` |  | ... or the flow below this (0 = not used) ... |
| `tDelay` | `TIME` | `T#30s` | ... for this long: boost, then sleep |
| `fBoost` | `REAL` | `5.0` | % of the setpoint added before sleeping |
| `tBoostTime` | `TIME` | `T#10s` | how long the boost lasts |
| `fWakeDrop` | `REAL` | `0.3` | wake when the value is this far short of the setpoint ... |
| `tWakeDelay` | `TIME` | `T#2s` | ... for this long |
| `tMinSleep` | `TIME` | `T#30s` | sleep at least this long |

**Status `sts`** (`ST_SpeedLoopSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | The first error since the last reset (first-out) |
| `fSpeed` | `REAL` |  | the speed asked, % |
| `fPv` | `REAL` |  | the value under control (the flow with Flow control) |
| `fSpNow` | `REAL` |  | the setpoint in use (ramped, fill ramp, boost) |
| `bManual` | `BOOL` |  |  |
| `bPvBad` | `BOOL` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stPvBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `ePhase` | `E_LoopPhase` |  | The phase now (status) |
| `ePresetUsed` | `E_LoopPreset` |  |  |
| `bAtSetpoint` | `BOOL` |  |  |
| `bFilled` | `BOOL` |  |  |
| `bSleeping` | `BOOL` |  |  |
| `bFlowLimiting` | `BOOL` |  |  |
| `nHuntCount` | `INT` |  |  |
| `stHighPv` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stLowAtMax` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stFill` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stNotReaching` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stHunting` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_SpeedLoopDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fP` | `REAL` |  | the PID's parts, % speed |
| `fI` | `REAL` |  |  |
| `fD` | `REAL` |  | % speed |
| `tPhaseTime` | `TIME` |  | time in the present phase |

## Lists

- `E_FillMode`: `Off`, `Fixed`, `Ramp` (default `Off`)
- `E_LoopControl`: `Pv`, `Flow`, `Fixed` (default `Pv`)
- `E_LoopPhase`: `Idle`, `Filling`, `Control`, `Boost`, `Sleep`, `Fallback`, `Manual` (default `Idle`)
- `E_LoopPreset`: `Normal`, `Low`, `High` (default `Normal`)
- `E_LoopSource`: `Pid`, `External` (default `Pid`)
- `E_OnBad`: `Hold`, `Fixed`, `Stop` (default `Hold`)
- `E_SpSource`: `Record`, `Pin` (default `Record`)

## How it works

Constant pressure / flow / level with a speed drive. It owns its pump: while asked to run it requests the pump (an [`FB_Pump`](FB_Pump.md) on an [`FB_MotorVsd`](FB_MotorVsd.md), an [`FB_MotorVsd`](FB_MotorVsd.md), or an [`FB_Group`](FB_Group.md)) at the speed that holds the value at the setpoint.

What the speed follows (`set.eControl`): Pv, the PID on `ipPv`; Flow, the PID on `ipFlow`; Fixed, a fixed speed (no PID; a bad sensor does not stop it). Presets Normal / Low / High: Pv `set.fSp` / `fSpLow` / `fSpHigh`, Flow `set.fFlowSp` / `fFlowSpLow` / `fFlowSpHigh`, Fixed `set.fFixedSpeed` / `fFixedSpeedLow` / `fFixedSpeedHigh` (a Low or High setpoint of 0 uses the Normal one). Pv control takes its setpoint from the record (`set.eSpSource` = Record) or the `fSp` pin (Pin). A setpoint in use of 0 (or not a number), a missing measurement or a missing `fExtSpeed` is a configuration fault while `bRun`: no run. speed = `fKp` * (e + 1/`tTi` * integral(e dt) + `tTd` * de/dt)      (% speed) e = sp - value (`set.bReverse`: value - sp, for a level emptied by the pump); inside `set.fDeadband` e = 0.

Anti-windup: the integral stays inside the output limits and stops while a limit or the rate limit holds the output. Bumpless: whenever the loop takes the output back (a start, the end of manual, fallback or a fill), the integral is loaded from the speed it has. A start begins at `set.fStartSpeed` (limited to the speed range: 0 = `set.fMinSpeed`). `set.fRateLimit` limits the output change (% per `set.eRateUnit`, 0 = no limit); `set.fSpRamp` ramps the setpoint (units per `set.eRateUnit`, 0 = a step). `set.eSource` = External: the speed follows `fExtSpeed` (held at the last value while it is not a number), with the same limits, protections and sleep.

Manual (the record's `bCmdManual` / `bCmdAuto`, kept in `set.bManual`): `set.fManualSpeed`; the protections still act.

Phases (`ePhase`): Idle -> Filling (optional) -> Control -> Boost -> Sleep -> Control; Fallback at a fixed speed after a hunting trip or with a failed sensor; Manual at the manual (or Fixed control's) speed.

Pipe fill (`set.stFill`; Pv control, not reverse acting): `eMode` Fixed runs at `fSpeed` until the value reaches `fTarget` (0 = 90 % of the setpoint); Ramp raises the setpoint from the value at `fRate` (per `set.eRateUnit`) to the setpoint. A fill longer than `stTimeout`'s delay acts per `stTimeout` (FillTimeout). After a manual or fallback spell the fill runs again only if the line has not been full in this run. `bFilled`: the line is full.

Sleep (`set.stSleep.bEnable`): satisfied (within `fAtSpBand` of the setpoint, or past it) at or below `fSpeed`, or with the flow below `fFlow` (0 = not used), for `tDelay`: the setpoint is raised by `fBoost` % for `tBoostTime`, then the pump stops (`eState` Waiting). It wakes when the value is `fWakeDrop` short of the setpoint for `tWakeDelay`, after at least `tMinSleep`.

Flow limit (`set.fFlowLimit`, 0 = off): the speed is brought down to hold the flow below it (`sts.bFlowLimiting`).

Protections (each a `ST_ProtectionSet`: off / warn / trip / signal, delay, reset; [`F_Protect`](F_Protect.md)):

```
  stHighPv       Pv above set.fHighPv (0 = off; clears set.fHighPvDeadband below it): a trip stops the pump
                 (PressureHigh); a warning holds the minimum speed while it lasts.
  stLowAtMax     the value below set.fLowAtMax (0 = half the setpoint, direct acting only) at the top speed in
                 control, while no more pump can be added (bMoreAvailable FALSE): a burst main (LowAtMax).
  stFill.stTimeout  the pipe fill took too long (FillTimeout).
  stNotReaching  in control, not at a speed limit, the value outside fAtSpBand of the setpoint (NotReaching).
  stHunting      more than set.nHuntCycles (1..15) crossings of the setpoint (each a swing beyond fHuntBand) in
                 set.tHuntWindow (0 = off) (Hunting): a trip runs at set.fFailSpeed (Fallback) until reset.
```

A bad or unfitted measurement under control: the speed is held at once; past `set.stPvBad`'s delay `set.eOnBad` Hold (the last speed; a sleeping pump stays asleep), Fixed (`set.fFailSpeed`) or Stop (SensorBad). Control resumes when `stPvBad` clears (its `tRecover`: the sensor good this long).

Restart: after a reset that was needed (Manual reset, or a Retry lockout) the loop waits for `bRun` to cycle, unless `set.bRestartAfterReset`. `bAtSetpoint`: in control, boost or sleep, the value within `set.fAtSpBand` of the setpoint in use. `fError`: how far the value is short of the setpoint (`set.bReverse`: above it), 0 when not good; with Fixed control Pv against the setpoint in use (0 when that is 0), for a fixed-speed set staged on bands; with `bAtMax` (at the top of the speed range, not held by the flow limit) and `bAtMin` it feeds [`FB_Cascade`](FB_Cascade.md)'s staging. `bMoreNeeded`: in control at the top speed and short of the setpoint by more than `fAtSpBand` for `set.tStageDelay`; `bLessNeeded`: in control at the minimum speed for `set.tStageDelay` (hints for an owner adding or dropping pumps; a highPv warning stops both). `bFilled` can drive a pump's prime-done input; `stLowAtMax` is the lost-prime check.

Detail (det): the PID's parts `fP` / `fI` / `fD` (% speed) and `tPhaseTime` (time in the present phase).

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back (`sts.bRefused` / `eRefusedWhy`, a warning until a reset).

## Example

A constant-pressure supply on one VSD pump.

| Pin | Wire |
| --- | --- |
| `bRun` | `fbSystem.bIsAuto` |
| `ipPv` | `fbPressure` (an FB_AnalogIn) |
| `ipTarget` | `fbPump1` (an FB_Pump on an FB_MotorVsd) |
| `refData` | `stLoop` |

Set the setpoint, `fKp` and `tTi` in `stLoop.set`.

**Back to** [the index](../README.md).
