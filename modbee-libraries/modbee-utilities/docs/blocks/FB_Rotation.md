# FB_Rotation — Shaft speed, stall and belt slip (a part)

Watches a proximity sensor on a driven shaft, pulley or target wheel: the speed (rpm, rev/s, m/min, m/s), a stall, underspeed (belt slip), overspeed and pulses while stopped. Added to its motor as a part, a stall trips the motor.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSensor` | `BOOL` | `FALSE` | the proximity sensor |
| in | `bMachineRun` | `BOOL` |  | The machine runs. With `ipOwner` the owner's run command counts too |
| in | `bReset` | `BOOL R_EDGE` |  | reset a latched fault Acts on its rising edge. |
| in | `ipOwner` | `I_PartOwner` |  | Optional: the motor it protects (a stall then trips it) |
| in | `refData` | `REFERENCE TO ST_RotationData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bHealthy` | `BOOL` |  | No protection tripped (without an owner: wire it to what must stop) |
| out | `bRotating` | `BOOL` |  | pulses being seen |
| out | `fSpeed` | `REAL` |  | in set.eSpeedUnit (default rpm) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RotationData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a latched fault (once per write; cleared by the block) |

**Settings `set`** (`ST_RotationSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nPulsesPerRev` | `INT` | `1` | pulses per revolution, for rpm and rev/s |
| `eSpeedUnit` | `E_SpeedUnit` |  | rpm, rev/s, m/min, m/s |
| `fDistPerPulse` | `REAL` |  | m/min and m/s: travel per pulse, m |
| `tStartDelay` | `TIME` | `T#5s` | after a start, stall and underspeed are ignored this long |
| `tStallTime` | `TIME` | `T#3s` | no pulse this long while running = stalled |
| `fMinSpeed` | `REAL` |  | underspeed below this (0 = off) |
| `fMaxSpeed` | `REAL` |  | overspeed above this (0 = off) |
| `tSpeedDelay` | `TIME` | `T#5s` | under / over speed must last this long |
| `tFilterTime` | `TIME` | `T#1s` | the speed is measured over at least this |
| `tCoastDown` | `TIME` | `T#10s` | after a stop, pulses are expected this long |
| `tRetryWindow` | `TIME` | `T#1h` | Retry protections count their trips within this window |
| `stStall` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Manual, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stUnderspeed` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stOverspeed` | `ST_ProtectionSet` | `(eResponse := E_Response.Off, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stSensor` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_RotationSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSpeed` | `REAL` |  | in set.eSpeedUnit |
| `bRotating` | `BOOL` |  | pulses being seen |
| `bTooFast` | `BOOL` |  | pulses at the scan limit (5 s) |
| `bUnitBad` | `BOOL` |  | eSpeedUnit / fDistPerPulse not usable: speed 0, speed checks off |
| `stStall` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stUnderspeed` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stOverspeed` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stSensor` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Details `det`** (`ST_RotationDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPeriod` | `TIME` |  | between the last two pulses |
| `tTimeLeft` | `TIME` |  | the start delay left, or the acting protection's time left |

## Lists

- `E_SpeedUnit`: `Rpm`, `RevPerSec`, `MetrePerMin`, `MetrePerSec` (default `Rpm`)

## How it works

Shaft / belt speed monitor from a proximity sensor on the driven shaft, pulley or target wheel: the speed, a stall (no pulse for `set.tStallTime` while running: the sensor stuck on or stuck off, a broken coupling or belt), underspeed (belt slip, overload), overspeed, and pulses while the machine is stopped (a faulty sensor, or something else turning it).

A part of its motor (`ipOwner`, optional): a trip stops the motor through its part list. Without an owner it is a plain monitor: wire `bHealthy` where it is needed.

Running: the `bMachineRun` pin, or with an owner its run command (either).

Speed, in `set.eSpeedUnit`, from the pulse rate f (pulses per second):

```
  Rpm          rpm   = 60 x f / nPulsesPerRev  (the default)
  RevPerSec    rev/s = f / nPulsesPerRev       (Hz of the shaft)
  MetrePerMin  m/min = 60 x f x fDistPerPulse  (belt / chain line speed)
  MetrePerSec  m/s   = f x fDistPerPulse
```

`fMinSpeed`, `fMaxSpeed` and the speed are all in `eSpeedUnit`. f is measured from the first to the last pulse of a window at least `set.tFilterTime` long (one pulse period when the shaft is slower). Between pulses f falls as 1 / (time since the last pulse) once that is longer than the last period, so a stopping shaft is seen slowing down; after `tStallTime` with no pulse it is 0. A pulse is seen once per scan: the fastest measurable rate is 1 / (2 x scan time) pulses per second; `sts.bTooFast` (a warning, PulsesTooFast) for 5 s whenever pulses arrive at that limit.

An unknown `eSpeedUnit`, or a line speed with `fDistPerPulse` not above 0 (or not a number): `sts.bUnitBad`, a warning (BadSetting); the speed reads 0 and the under / over speed checks are off until it is fixed. The stall and sensor checks do not need the unit and still act.

Protections (`ST_ProtectionSet`, [`F_Protect`](F_Protect.md)):

```
  stStall       Trip, Manual  running, past tStartDelay and tStallTime, no pulse for tStallTime   -> Stall
  stUnderspeed  Warn, Auto    running, past tStartDelay, below fMinSpeed (> 0) for tSpeedDelay   -> Underspeed
  stOverspeed   Off           above fMaxSpeed (> 0) for tSpeedDelay                               -> Overspeed
  stSensor      Warn, Auto    pulses while stopped, tCoastDown after the stop                     -> PulsesWhileStopped
```

A trip or a signal acts on the owner (Trip / Stop); a warning shows on it. Reset: `bReset` (rising edge), the record's `bCmdReset` (once per write), the owner's reset, the system reset.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a set never good is BadSetting (`bError`) and the checks go on with it (`nPulsesPerRev` below 1 counts as 1).

Its rung stopping while a protection acts is PartLost on its owner.

## Example

A conveyor's tail pulley with a proximity sensor, 4 targets per revolution, protecting the conveyor motor.

| Pin | Wire |
| --- | --- |
| `bSensor` | `DI_TailPulleyProx` |
| `ipOwner` | `fbConveyorMotor` |
| `refData` | `stTailPulley` |
| `fSpeed` | a display (rpm) |

Set `stTailPulley.set.nPulsesPerRev := 4` and, for belt slip, `fMinSpeed`. Put this rung before the motor's rung. Without a motor block, wire `bMachineRun` to the machine's running signal and use `bHealthy`.

## See also

[FB_Motor](FB_Motor.md), [FB_Protection](FB_Protection.md)

**Back to** [the index](../README.md).
