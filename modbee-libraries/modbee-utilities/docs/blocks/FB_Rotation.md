# FB_Rotation — Shaft speed, stall and belt slip (a part)

Watches a proximity sensor on a driven shaft, pulley or target wheel: the speed (rpm, rev/s, m/min, m/s), a stall, underspeed (belt slip), overspeed and pulses while stopped. Added to its motor as a part, a stall trips the motor.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bProximitySensor` | `BOOL` | `FALSE` | the proximity sensor |
| in | `bMachineRunning` | `BOOL` |  | the machine runs (with an owner, its run command counts too) |
| in | `bResetFaults` | `BOOL R_EDGE` |  | reset a latched fault |
| in | `ipOwner` | `I_PartOwner` |  | optional: the motor it protects. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `refData` | `REFERENCE TO ST_RotationData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fSpeed` | `REAL` |  | in set.eSpeedUnit (default rpm) |
| out | `bRotating` | `BOOL` |  | pulses being seen |
| out | `bNoFaultTripped` | `BOOL` |  | no protection tripped |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RotationData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a latched fault (once per write; cleared by the block) |

**Settings `set`** (`ST_RotationSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nPulsesPerRevolution` | `INT` | `1` | pulses per revolution, for rpm and rev/s |
| `eSpeedUnit` | `E_SpeedUnit` |  | rpm, rev/s, m/min, m/s |
| `fDistancePerPulse` | `REAL` |  | m/min and m/s: travel per pulse, m |
| `tMaskAfterStart` | `TIME` | `T#5s` | after a start, stall and underspeed are ignored this long |
| `tStalledAfterNoPulse` | `TIME` | `T#3s` | no pulse this long while running = stalled |
| `fUnderspeedBelow` | `REAL` |  | underspeed below this (0 = off) |
| `fOverspeedAbove` | `REAL` |  | overspeed above this (0 = off) |
| `tMeasureSpeedOver` | `TIME` | `T#1s` | the speed is measured over at least this |
| `tCoastDownTime` | `TIME` | `T#10s` | after a stop, pulses are expected this long |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry counts trips within this window (0 = until a reset) |
| `stStallFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | no pulses while running; a protection's settings ([protections](../conventions.md#protections)) |
| `stUnderspeedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | speed below fUnderspeedBelow; a protection's settings ([protections](../conventions.md#protections)) |
| `stOverspeedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | speed above fOverspeedAbove; a protection's settings ([protections](../conventions.md#protections)) |
| `stPulsesWhileStoppedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#0s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | pulses while stopped (after the coast down): the sensor is suspect; a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_RotationSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSpeed` | `REAL` |  | in set.eSpeedUnit |
| `bRotating` | `BOOL` |  | pulses being seen |
| `bPulsesTooFast` | `BOOL` |  | pulses at the scan limit (5 s) |
| `bSpeedUnitBad` | `BOOL` |  | eSpeedUnit / fDistancePerPulse not usable: speed 0, speed checks off |
| `stStallFault` | `ST_ProtectionSts` |  | no pulses while running; a protection's status ([protections](../conventions.md#protections)) |
| `stUnderspeedFault` | `ST_ProtectionSts` |  | speed below fUnderspeedBelow; a protection's status ([protections](../conventions.md#protections)) |
| `stOverspeedFault` | `ST_ProtectionSts` |  | speed above fOverspeedAbove; a protection's status ([protections](../conventions.md#protections)) |
| `stPulsesWhileStoppedFault` | `ST_ProtectionSts` |  | pulses while stopped (after the coast down): the sensor is suspect; a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_RotationDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTimeBetweenPulses` | `TIME` |  | between the last two pulses |
| `tTimeLeft` | `TIME` |  | the start delay left, or the acting protection's time left |

## Lists

- `E_SpeedUnit`: `Rpm`, `RevPerSec`, `MetrePerMin`, `MetrePerSec` (default `Rpm`)

## How it works

Shaft / belt speed monitor from a proximity sensor on the driven shaft, pulley or target wheel: the speed, a stall (no pulse for `set.tStalledAfterNoPulse` while running: the sensor stuck on or stuck off, a broken coupling or belt), underspeed (belt slip, overload), overspeed, and pulses while the machine is stopped (a faulty sensor, or something else turning it).

A part of its motor (`ipOwner`, optional): a trip stops the motor through its part list. Without an owner it is a plain monitor: wire `bNoFaultTripped` where it is needed.

Running: the `bMachineRunning` pin, or with an owner its run command (either).

Speed, in `set.eSpeedUnit`, from the pulse rate f (pulses per second):

```
  Rpm          rpm   = 60 x f / nPulsesPerRevolution  (the default)
  RevPerSec    rev/s = f / nPulsesPerRevolution       (Hz of the shaft)
  MetrePerMin  m/min = 60 x f x fDistancePerPulse  (belt / chain line speed)
  MetrePerSec  m/s   = f x fDistancePerPulse
```

`fUnderspeedBelow`, `fOverspeedAbove` and the speed are all in `eSpeedUnit`. f is measured from the first to the last pulse of a window at least `set.tMeasureSpeedOver` long (one pulse period when the shaft is slower). Between pulses f falls as 1 / (time since the last pulse) once that is longer than the last period, so a stopping shaft is seen slowing down; after `tStalledAfterNoPulse` with no pulse it is 0. A pulse is seen once per scan: the fastest measurable rate is 1 / (2 x scan time) pulses per second; `sts.bPulsesTooFast` (a warning, PulsesTooFast) for 5 s whenever pulses arrive at that limit.

An unknown `eSpeedUnit`, or a line speed with `fDistancePerPulse` not above 0 (or not a number): `sts.bSpeedUnitBad`, a warning (BadSetting); the speed reads 0 and the under / over speed checks are off until it is fixed. The stall and sensor checks do not need the unit and still act.

Protections (`ST_ProtectionSet`, [`F_Protect`](F_Protect.md)):

```
  stStallFault       Trip, Manual  running, past tMaskAfterStart and tStalledAfterNoPulse, no pulse for tStalledAfterNoPulse   -> Stall
  stUnderspeedFault  Warn, Auto    running, past tMaskAfterStart, below fUnderspeedBelow (> 0) for its tTripDelay (5 s) -> Underspeed
  stOverspeedFault   Off           above fOverspeedAbove (> 0) for its tTripDelay (5 s)                           -> Overspeed
  stPulsesWhileStoppedFault      Warn, Auto    pulses while stopped, tCoastDownTime after the stop                     -> PulsesWhileStopped
```

A trip or a signal acts on the owner (Trip / Stop); a warning shows on it. Reset: `bResetFaults` (rising edge), the record's `bCmdResetFaults` (once per write), the owner's reset, the system reset.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a set never good is BadSetting (`bError`) and the checks go on with it (`nPulsesPerRevolution` below 1 counts as 1).

Its rung stopping while a protection acts is PartLost on its owner.

## Example

A conveyor's tail pulley with a proximity sensor, 4 targets per revolution, protecting the conveyor motor.

| Pin | Wire |
| --- | --- |
| `bProximitySensor` | `DI_TailPulleyProx` |
| `ipOwner` | `fbConveyorMotor` |
| `refData` | `stTailPulley` |
| `fSpeed` | a display (rpm) |

Set `stTailPulley.set.nPulsesPerRevolution := 4` and, for belt slip, `fUnderspeedBelow`. Put this rung before the motor's rung. Without a motor block, wire `bMachineRunning` to the machine's running signal and use `bNoFaultTripped`.

## See also

[FB_Motor](FB_Motor.md), [FB_Protection](FB_Protection.md)

**Back to** [the index](../README.md).
