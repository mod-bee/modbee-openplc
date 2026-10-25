# UT_ROTATION — Shaft / belt speed monitor (proximity sensor)

Watches a proximity sensor on a shaft, pulley or target wheel. It detects a stall
(sensor stuck on or off), underspeed (belt slip, overload) and overspeed, and
measures the speed: shaft speed in rpm or rev/s, or belt / chain line speed in
m/min or m/s. Wire `Healthy` to the motor's `Interlock` to stop on a stall.
Replaces rotationMonitor (Better Eggs).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Running` | BOOL | FALSE | Machine running (`UT_MOTOR.Running`) |
| in | `Sensor` | BOOL | FALSE | Proximity sensor |
| in | `Reset` | BOOL | FALSE | Rising edge: reset a latched fault |
| out | `Healthy` | BOOL | | No fault → motor `Interlock` |
| out | `Rotating` | BOOL | | Pulses being seen (one within `stallTime`) |
| out | `Speed` | REAL | | In `speedUnit` (rpm by default) |
| out | `Fault` | BOOL | | |
| inout | `Data` | UT_ROTATION_DATA | | |

## Record `UT_ROTATION_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `pulsesPerRev` | INT | 1 | Targets on the wheel, for rpm and rev/s (0 or negative counts as 1) |
| `speedUnit` | UT_SPEED_UNIT | UT_SPD_RPM | Unit of `Speed`, `speed`, `minSpeed` and `maxSpeed`: `UT_SPD_RPM` (0, rpm), `UT_SPD_RPS` (revolutions per second = Hz of the shaft), `UT_SPD_M_MIN` (line speed, m/min), `UT_SPD_M_S` (line speed, m/s) |
| `distPerPulse` | REAL | 0.0 | Line speed only: belt or chain travel per pulse, in m (e.g. a 0.3 m drum circumference with 2 targets = 0.15). Must be above 0 for m/min and m/s |
| `startDelay` | TIME | T#5s | After a start, stall and underspeed are ignored this long |
| `stallTime` | TIME | T#3s | No pulse this long while running = stalled |
| `minSpeed` / `maxSpeed` | REAL | 0.0 / 0.0 | Under / over speed limits, in `speedUnit` (0 = off) |
| `speedDelay` | TIME | T#5s | Under / over speed must last this long |
| `filterTime` | TIME | T#1s | Speed is measured over at least this long |
| `coastDown` | TIME | T#10s | After a stop, pulses are expected this long |
| `retryWindow` | TIME | T#1h | RETRY counts trips within this window |
| `stall` | UT_PROTECTION | TRIP · MANUAL | b0: a stalled conveyor usually needs a look |
| `underspeed` | UT_PROTECTION | WARN · AUTO | b1: belt slip |
| `overspeed` | UT_PROTECTION | OFF | b2 |
| `sensor` | UT_PROTECTION | WARN · AUTO | b3: pulses while stopped, after `coastDown` |
| *(invalid setting)* | | warning | b4: `wrnConfig`, see below |
| `cmdReset` | BOOL | | HMI reset (acts once, on its rising edge; cleared by the block) |
| `speed`, `rotating`, `period` | REAL, BOOL, TIME | | Status (`speed` in `speedUnit`; `period`: time between the last two pulses) |
| `wrnTooFast` | BOOL | | Pulses at the scan-rate limit (held 5 s) |
| `wrnConfig` | BOOL | | `speedUnit` unknown, or a line speed with `distPerPulse` not above 0 (or not a number) |
| `fault`, `warning`, `faultCode` | BOOL, BOOL, DWORD | | See [conventions](../conventions.md#protections--every-fault-works-the-same-way) |
| `timeLeft` | TIME | | The countdown the status shows: the start delay, or a recover / retry wait |
| `statusCode` | UT_STATUS | | What it is doing, or what is wrong (codes below) |
| `faultId` | UT_FAULT | | The fault, warning or setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | `statusCode` and `faultId` in words, e.g. `Latched: stalled` |

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers); `statusText` is the two in words.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_STOPPED` | | `Stopped` | Not running, no pulses |
| `UT_ST_RUNNING` | | `Running` | Running, past the start delay, no fault |
| `UT_ST_STILL_TURNING` | | `Stopped: still turning` | Not running, pulses still seen (coasting down) |
| `UT_ST_CHECKS_DELAY` | | `Starting: checks delayed` | Running, inside `startDelay` (`timeLeft` counts it down) |
| `UT_ST_WARNING` | `UT_F_PULSES_FAST` | `Warning: pulses too fast` | `wrnTooFast` |
| `UT_ST_WARNING` | the protection | `Warning: stalled` | A protection set to WARN: `UT_F_STALLED` (stalled), `UT_F_UNDERSPEED`, `UT_F_OVERSPEED`, `UT_F_PULSES_STOPPED` (turning when off) |
| `UT_ST_WARN_SETTING` | `UT_F_SPEED_UNIT` / `UT_F_DIST_PER_PULSE` | `Setting: speed unit` | `wrnConfig` |
| `UT_ST_FAULT` | the protection | `Fault: stalled` | A trip, AUTO reset (`timeLeft`: the recover still to go) |
| `UT_ST_FAULT_RETRY` | the protection | `Retrying: stalled` | A trip, RETRY with retries left (`timeLeft`: the wait) |
| `UT_ST_FAULT_LOCKED` | the protection | `Locked: stalled` | A trip, RETRY, retries used up: reset needed |
| `UT_ST_FAULT_RESET` | the protection | `Latched: stalled` | A trip, MANUAL: reset needed |

A trip comes first, then a warning, a bad setting, pulses too fast, starting,
running, coasting, stopped.

## How it works
- The pulse rate f (pulses per second) is measured from pulse to pulse over at
  least `filterTime`, so a slow shaft is accurate. While no pulse comes it falls
  (1 / time since the last pulse), so a stopping shaft is seen slowing; after
  `stallTime` it is 0. The speed, and the limits, are in `speedUnit`:

  | `speedUnit` | Speed |
  | --- | --- |
  | `UT_SPD_RPM` (default) | rpm = 60 × f / `pulsesPerRev` |
  | `UT_SPD_RPS` | rev/s (Hz) = f / `pulsesPerRev` |
  | `UT_SPD_M_MIN` | m/min = 60 × f × `distPerPulse` |
  | `UT_SPD_M_S` | m/s = f × `distPerPulse` |

  This divides by `pulsesPerRev`; the original multiplied.
- Example, a conveyor that should run at 45 m/min, with one target on a tail
  drum of 0.4 m circumference: `speedUnit := UT_SPD_M_MIN, distPerPulse := 0.4,
  minSpeed := 35.0` (belt slip below 35 m/min). The same drum in rpm:
  `minSpeed := 87.5` (35 / 0.4).
- The maximum measurable rate is set by the scan rate: 1 / (2 × scan time)
  pulses per second (60 / (2 × scan time × `pulsesPerRev`) rpm). The block warns
  (`wrnTooFast`) at it.
- **Invalid settings.** An unknown `speedUnit`, or a line speed with
  `distPerPulse` 0, negative or not a number, sets `wrnConfig`, `warning` and
  fault bit 4 (status `Setting: speed unit` or
  `Setting: distance per pulse`): the speed reads 0 and the under / over
  speed checks are off until it is fixed. The stall and sensor checks still act.
- A stall is seen with the sensor stuck ON or stuck OFF (no rising edge either way).
- Each protection is a `UT_PROTECTION`: change its response and reset as you like.
  Reset by the `Reset` pin or `cmdReset`, each on its rising edge: one held on (a
  Modbus coil left on) resets once; a reset while the shaft is still stalled is
  refused.
