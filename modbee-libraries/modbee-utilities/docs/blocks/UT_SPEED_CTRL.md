# UT_SPEED_CTRL — Constant pressure / flow / level with a speed drive

Holds a pressure, flow, level or temperature at a setpoint by varying a drive's
speed. Typical uses: irrigation and stock-water pumps on a VSD, booster sets,
constant-pressure town supply, borehole pumps, duct-pressure fans, cooling-tower fans.

It has the full set of field features: **pipe fill** (fill the mains gently before
regulating, which stops water hammer), **sleep / wake** (stop when demand stops and
restart on a pressure drop), a **flow limit**, and **guard rails against a badly
tuned or failing loop**: hunting detection with a fallback speed, a burst-pipe /
lost-prime check, an overpressure override, sensor-failure handling and output
rate limiting.

The control loop is **inside the block**, because pipe fill, sleep, overrides and
the fallback have to take the output away from the loop and hand it back without a
bump. If you'd rather use OpenPLC's `PID`, set `loop := UT_LOOP_EXTERNAL`; the block
then takes the speed from `ExtSpeed` (wire `Data.spActive` to the PID's setpoint) and
still applies every phase, limit and protection around it.

What the speed follows is a setting, `control`: the PID on `Pv` (pressure or level,
the default), the PID on the `Flow` pin, or a fixed speed. Each has three **presets**,
NORMAL, LOW and HIGH, chosen with `preset` by the operator, the HMI, SCADA or your
logic. For example a travelling irrigator working near the sump needs only a low
pressure: switch `preset` to LOW and the pump holds `spLow` instead of `sp`.

An operator can run the pump at a **manual speed** (`cmdManual`, `manualSpeed`) without
losing the overpressure and burst protections, which a drive's own Hand would bypass.

Chain: `UT_SPEED_CTRL.Run` → `UT_PUMP.Demand`; `UT_PUMP.RunCmd` → `UT_MOTOR_VSD.AutoCmd`;
`UT_SPEED_CTRL.Speed` → `UT_MOTOR_VSD.AutoSpeed`; `UT_MOTOR_VSD.Running` → `Running`.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | FALSE | Control wanted (a schedule, `UT_ZONE_SEQ.PumpDemand`, a switch) |
| in | `Pv` | REAL | 0.0 | The pressure or level, e.g. `UT_ANALOG_IN.Value`. Controlled with `control` PV; `highPv` always watches it, whatever `control` is |
| in | `PvGood` | BOOL | TRUE | Pressure / level sensor healthy (`UT_ANALOG_IN.Good`) |
| in | `Sp` | REAL | 0.0 | PV control: the setpoint when `spSource := UT_SP_PIN` (e.g. per-zone pressure from `UT_ZONE_SEQ`); it overrides `sp`, `spLow` and `spHigh` |
| in | `Running` | BOOL | TRUE | Drive running (`UT_MOTOR_VSD.Running`). Unwired: assumed running when asked |
| in | `Flow` | REAL | 0.0 | Flow: controlled with `control` FLOW; also for the flow limit and low-flow sleep (optional otherwise) |
| in | `ExtSpeed` | REAL | 0.0 | Speed % from an external PID (`loop := UT_LOOP_EXTERNAL`) |
| in | `Reset` | BOOL | FALSE | Rising edge: reset MANUAL protections |
| in | `MoreAvailable` | BOOL | FALSE | A group block can still add a pump ([UT_PUMP_CASCADE](UT_PUMP_CASCADE.md) wires it): `lowPvAtMax` waits until it cannot. Unwired: no change |
| out | `Run` | BOOL | | Pump wanted (→ `UT_PUMP.Demand` or `UT_MOTOR_VSD.AutoCmd`) |
| out | `Speed` | REAL | | Speed request % (→ `UT_MOTOR_VSD.AutoSpeed`); 0 when not running |
| out | `Phase` | UT_SC_PHASE | | `UT_SC_IDLE`, `UT_SC_FILLING`, `UT_SC_CONTROL`, `UT_SC_BOOST`, `UT_SC_SLEEP`, `UT_SC_FALLBACK`, `UT_SC_MANUAL` |
| out | `AtSetpoint` | BOOL | | The value under control (`pv`) within `atSpBand` (CONTROL, BOOST or SLEEP) |
| out | `MoreNeeded` | BOOL | | At max speed and still short of the band for `stageDelay`: one more pump |
| out | `LessNeeded` | BOOL | | At min speed for `stageDelay`: one less pump |
| out | `Fault` | BOOL | | A trip is in effect (the pump is stopped, or held at the fallback speed) |
| out | `Warning` | BOOL | | A warning, a failed sensor with FALLBACK / HOLD, or invalid settings |
| inout | `Data` | UT_SPEED_CTRL_DATA | | The controller's settings and status (below) |

## Record `UT_SPEED_CTRL_DATA`

### What the speed follows, and the presets
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `control` | UT_SC_CTRL | UT_SC_CTRL_PV | `UT_SC_CTRL_PV` (0): the PID holds `Pv` (pressure or level) at the setpoint. `UT_SC_CTRL_FLOW`: the PID holds the `Flow` pin at the flow setpoint. `UT_SC_CTRL_FIXED`: a fixed speed, no PID. See [Control](#control-pv-flow-or-fixed-and-the-presets) |
| `preset` | UT_SC_PRESET | UT_PRESET_NORMAL | Which setpoint or fixed speed is used: `UT_PRESET_NORMAL` (0), `UT_PRESET_LOW` or `UT_PRESET_HIGH`. Set by the operator, the HMI, SCADA or your logic |
| `sp` | REAL | 0.0 | PV: the NORMAL setpoint (e.g. bar). **Must be set.** 0 (or not a number) with `Enable` gives a `configBad` warning and no run |
| `spLow` / `spHigh` | REAL | 0.0 / 0.0 | PV: the LOW and HIGH setpoints. 0 = `sp` is used |
| `flowSp` | REAL | 0.0 | FLOW: the NORMAL flow setpoint, in the units of `Flow`. **Must be set** for FLOW: 0 (or not a number) with `Enable` gives `configBad` and no run |
| `flowSpLow` / `flowSpHigh` | REAL | 0.0 / 0.0 | FLOW: the LOW and HIGH flow setpoints. 0 = `flowSp` is used |
| `fixedSpeed` | REAL | 100.0 | FIXED: the NORMAL speed, % (e.g. run) |
| `fixedSpeedLow` | REAL | 50.0 | FIXED: the LOW speed, % (e.g. a slow run at low level) |
| `fixedSpeedHigh` | REAL | 100.0 | FIXED: the HIGH speed, % (e.g. priming) |

### Setpoint and loop
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `spSource` | UT_SP_SOURCE | UT_SP_RECORD | PV control: `UT_SP_RECORD` (0) uses `sp` / `spLow` / `spHigh` by `preset`; `UT_SP_PIN` uses the `Sp` pin, whatever the preset |
| `spRamp` | REAL | 0.0 | Setpoint change rate, units per `rateUnit` (0 = step) |
| `reverseActing` | BOOL | FALSE | FALSE: below setpoint → speed up (pressure, flow). TRUE: above setpoint → speed up (emptying a tank, cooling). The pipe fill is skipped |
| `loop` | UT_LOOP | UT_LOOP_INTERNAL | `UT_LOOP_INTERNAL` (0) or `UT_LOOP_EXTERNAL` |
| `kp` | REAL | 5.0 | % speed per unit of error (negative: `configBad`) |
| `ti` | TIME | T#5s | Integral time (0 = no integral) |
| `td` | TIME | T#0s | Derivative time (usually 0 for pumps) |
| `deadband` | REAL | 0.0 | Error ignored inside this |
| `minSpeed` / `maxSpeed` | REAL | 30.0 / 100.0 | % (minimum keeps the pump above its shut-off head and cooled). min > max: `configBad` |
| `startSpeed` | REAL | 40.0 | Speed on start, held until `Running`; the loop carries on from it |
| `rateLimit` | REAL | 5.0 | Max output change, % per `rateUnit` (0 = none). **Limits the damage a bad tune can do** |
| `rateUnit` | UT_RATE_UNIT | UT_PER_SEC | Time unit of every rate in the record, `rateLimit`, `spRamp` and `pipeFill.rate`: `UT_PER_SEC` (0, per second) or `UT_PER_MIN` (per minute); `UT_PER_HOUR` and `UT_PER_DAY` work too. Example: `rateLimit := 300.0, rateUnit := UT_PER_MIN` is the same as the default 5 %/s |
| `atSpBand` | REAL | 0.2 | ± band for `AtSetpoint`, sleep, staging and `notReaching` |

### Pipe fill `pipeFill : UT_SC_FILL_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `mode` | UT_FILL_MODE | UT_FILL_OFF | `UT_FILL_OFF` · `UT_FILL_FIXED` runs at `speed` · `UT_FILL_RAMP` ramps the setpoint from Pv to `sp` at `rate` under the loop |
| `speed` | REAL | 50.0 | FIXED: fill speed, % |
| `target` | REAL | 0.0 | The fill is complete when Pv reaches this (0 = 90 % of sp); RAMP also waits for the ramp to finish |
| `rate` | REAL | 0.1 | RAMP: setpoint rise, units per `rateUnit` (of the main record: per second by default) |
| `timeout` | UT_PROTECTION | TRIP · 10 min · RETRY (2) | The fill never completes (burst main, open valve). Each retry fills again |

The fill runs every time the pump starts from IDLE (Enable, or a restart after a
trip), not after a sleep. Leaving FALLBACK or MANUAL, a run whose line is not full
yet (no fill completed, and Pv never at the fill target since the start) fills
first, so a sensor that was bad at the start, or dipped during the fill, does not
skip it.

### Sleep / wake `sleep : UT_SC_SLEEP_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enable` | BOOL | FALSE | Sleep when the demand has gone. Switching it off wakes the pump |
| `speed` | REAL | 35.0 | At or below this speed ... |
| `flow` | REAL | 0.0 | ... or `Flow` below this (0 = not used) ... |
| `delay` | TIME | T#30s | ... with Pv not below the band, for this long: boost, then sleep |
| `boost` | REAL | 5.0 | % of sp added before sleeping (tops up the tank / accumulator). 0: sleep straight away |
| `boostTime` | TIME | T#10s | How long the boost lasts. If Pv falls `wakeDrop` below sp during it, the boost is dropped and the pump carries on |
| `wakeDrop` | REAL | 0.3 | Wake when Pv is this far below sp (above it, reverse acting) ... Not a number, infinite or negative: a setting warning and 0 is used, so the pump always wakes (as soon as Pv is below sp) |
| `wakeDelay` | TIME | T#2s | ... for this long ... |
| `minSleep` | TIME | T#30s | ... and the pump has slept at least this long |

### Limits and overrides (independent of the loop)
| Field | Bit | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `flowLimit` | | REAL | 0.0 | Speed is reduced to hold `Flow` at this (end-of-curve / sprinkler blow-out protection). The cap moves at up to `rateLimit` (per `rateUnit`; 5 %/s if 0), in proportion to the excess, full rate at 20 % over. The loop's integral is pulled down with it. 0 = off |
| `highPv` | 2 | UT_LEVEL | TRIP · AUTO · sp 0 | Overpressure (sp 0 = off). **WARN**: speed straight to `minSpeed` while high. **TRIP**: the pump stops; it restarts (with the fill) when the trip clears |
| `lowPvAtMax` | 3 | UT_LEVEL | TRIP · 60 s · RETRY (3, recover 5 min) · sp 0 | **On by default.** It waits while `MoreAvailable` (a group can still add a pump). At the top speed allowed (max, or the flow limit) with Pv still low in CONTROL / BOOST: a sensor stuck low, a burst pipe, lost prime, a worn pump. sp 0 = below **half the setpoint** in use (direct acting only); set `sp` for a fixed level (it then applies reverse acting too). `response := UT_RESP_OFF` turns it off. With a long main and no pipe fill, set `pipeFill` or a longer `delay` |
| `pipeFill.timeout` | 4 | UT_PROTECTION | see above | |
| `notReaching` | 5 | UT_PROTECTION | WARN · 2 min · AUTO | Pv outside `atSpBand` that long in CONTROL while not at a speed limit (undersized or badly tuned) |
| `hunting` | 6 | UT_PROTECTION | WARN · AUTO | The loop oscillates (below). **TRIP** = run at `fallbackSpeed` (phase FALLBACK) until it clears |
| `huntCycles` / `huntWindow` / `huntBand` | | INT / TIME / REAL | 6 / T#60s / 0.3 | Hunting = `huntCount` above `huntCycles` (1..15): Pv crossing sp more than that many times in about one `huntWindow`, each swing over `huntBand` peak to peak (a crossing counts once Pv is `huntBand/2` past sp the other way). `huntWindow` 0 = off. See [Hunting](#hunting) |
| `pvFail` | 1 | UT_PVFAIL | UT_PVFAIL_STOP | Sensor bad (`PvGood` FALSE, Pv NaN or infinite): `UT_PVFAIL_STOP` (0, fault, pump stops), `UT_PVFAIL_FALLBACK` (warning, run at `fallbackSpeed`), `UT_PVFAIL_HOLD` (warning, hold the last speed; a sleeping pump stays asleep) |
| `pvRecover` | | TIME | T#5s | The sensor must be good this long before control resumes |
| `fallbackSpeed` | | REAL | 60.0 | Used on sensor failure or a hunting trip |
| `stageDelay` | | TIME | T#30s | For `MoreNeeded` / `LessNeeded` |
| `retryWindow` | | TIME | T#1h | RETRY counts |
| `restartAfterReset` | | BOOL | FALSE | After a MANUAL reset of a stopped controller, restart without `Enable` cycling |
| `manualSpeed` | | REAL | 50.0 | Manual: the speed the operator sets, % (held inside `minSpeed`..`maxSpeed` and the flow limit). Not a number or outside 0..100: `minSpeed` and a setting warning (bit 7) |

Bit 0 of `faultCode` is `configBad` (no run). Bit 7 is a setting that is invalid but
has a safe fallback (a warning; it runs). `faultId` names the most important one:
`UT_F_OVERPRESSURE`, `UT_F_SENSOR_BAD`, `UT_F_LOW_AT_MAX` (burst), `UT_F_PIPE_FILL`,
`UT_F_HUNTING`, `UT_F_NOT_REACHING`, then the setting (bit 0: the setting named, below;
bit 7: `UT_F_SETTING`).

### Invalid settings
- **No run** (`configBad`, bit 0, a warning while `Enable`): an unknown `control`; with
  PV or FLOW, the setpoint in use (by `preset` and `spSource`) 0, not a number or
  infinite (so FLOW needs `flowSp`); `kp` negative or not a number; `minSpeed` / `maxSpeed` not a number,
  min < 0, max ≤ 0 or min > max; `startSpeed` or `fallbackSpeed` not a number;
  `rateLimit` negative or not a number; an unknown `rateUnit`.
- **Warning, safe value used** (bit 7, `Warning`): `sleep.wakeDrop` not a number,
  infinite or negative → 0; `atSpBand` → 0; `deadband` → 0; `spRamp` → 0 (a step);
  `td` negative → 0; `sleep.boost` outside 0..100 → no boost; an unknown `pvFail` →
  STOP (the safe side). Warned only (the block already acts safely): an unknown
  `spSource` (record sp), `loop` (internal) or `pipeFill.mode`; `ti` negative (no
  integral); `startSpeed` / `fallbackSpeed` outside min..max (clamped); `manualSpeed`, or
  the fixed speed in use, not a number or outside 0..100 (`minSpeed` used); `pipeFill.speed`
  or `sleep.speed` outside 0..100; `pipeFill.target`, `pipeFill.rate`, `sleep.flow`,
  `flowLimit`, `huntBand` negative or not a number; `huntCycles` outside 1..15; a
  negative `huntWindow`, `pvRecover`, `stageDelay` or sleep time; a protection with a
  bad time or setpoint.

### HMI
| Field | Type | Meaning |
| --- | --- | --- |
| `cmdReset` | BOOL | Reset MANUAL protections (acts once, cleared by the block) |
| `cmdManual` | BOOL | Run at `manualSpeed` instead of the loop (phase MANUAL), until `cmdAuto` |
| `cmdAuto` | BOOL | Back to the loop, bumpless (it carries on from the manual speed). With `cmdManual` in the same scan, `cmdAuto` wins |

Each command acts once, on its rising edge, and is cleared by the block.

**Manual speed** (phase `UT_SC_MANUAL`, `manual` TRUE): the pump runs at `manualSpeed`,
reached at the `rateLimit`. `Enable` still starts and stops it (manual stays selected
while it is off), and these still act: the overpressure override and trip (`highPv`),
`lowPvAtMax` at the top speed (burst / lost prime), the flow limit, the rate limit and
a failed sensor with `pvFail` STOP (the overpressure check needs the sensor). No pipe
fill, sleep, hunting or `notReaching` in manual; `MoreNeeded` / `LessNeeded` stay
FALSE. Manual is not kept over a power cut: the loop is back in control.

### Status fields
`spActive` (setpoint in use: ramped, fill ramp or boost), `pv` (the value under control
now: `Pv`, or `Flow` with FLOW control), `error` (in the acting direction), `pTerm`, `iTerm`, `dTerm`, `speed`, `phase`, `huntCount` (crossings in
about the last `huntWindow`, see [Hunting](#hunting)), `sleeping`, `flowLimiting`,
`pvBad`, `configBad` (no run), `fault`, `warning`, `faultCode : DWORD`,
`faultId : UT_FAULT`, `statusCode : UT_STATUS` and `statusText : STRING(30)` (what the
loop is doing or what holds it back, below), and (at the end of the record):

| Field | Type | Meaning |
| --- | --- | --- |
| `manual` | BOOL | Manual speed selected |
| `timeLeft` | TIME | The countdown in progress: the fill timeout (FILLING), the boost (BOOST), `minSleep` then the wake delay (SLEEP), the sleep delay, `MoreNeeded` / `LessNeeded`'s `stageDelay` while running under the loop, or the recover / retry wait of the tripped protection shown. 0 = none |
| `phaseTime` | TIME | Time in the current phase (the sleep time while asleep, the fill time while filling) |
| `stopReason` | UT_STOP | Why the pump last stopped (`Run` dropped): `UT_STOP_DEMAND_ENDED` (`Enable` off), `UT_STOP_FAULT` (a trip or a failed sensor with STOP), `UT_STOP_SETTING` (`configBad`), `UT_STOP_ASLEEP` (`Asleep: demand met`). `UT_STOP_NONE` = none since power-up. The words are [UT_STOP_TEXT](UT_STOP_TEXT.md)'s |
| `lastFaultCode` | DWORD | The trip bits (1 sensor, 2 overpressure, 3 low at max, 4 fill, 5 not reaching, 6 hunting) of the last trip, kept after it clears |
| `lastFault` | UT_FAULT | Its name, e.g. `UT_F_OVERPRESSURE` |
| `trips` | UDINT | Trips since power-up |

### Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the loop is
doing, or what holds it back. The most important reason wins: configuration > fault >
held / waiting > warning > running > idle. Enabled and not running, or running with
no drive feedback, it always shows a held, fault or configuration status. The words
hold no numbers: the setpoint in use is `spActive`, the speed `speed`, and the time
left `timeLeft`. The text is rebuilt only when the status or the fault changes. The
numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE_NOT_ENABLED` | `Idle: not enabled` | `Enable` FALSE |
| `UT_ST_HOLDING` | `Running: holding setpoint` | CONTROL: holding `spActive` at `speed` |
| `UT_ST_PIPE_FILL` | `Pipe fill` | FILLING, up to the fill target (`timeLeft`: the fill timeout) |
| `UT_ST_BOOST` | `Boost before sleep` | BOOST (`timeLeft`: the boost time left) |
| `UT_ST_MAX_SPEED` | `Max speed, below setpoint` | CONTROL at the top speed, Pv still short by more than `atSpBand` |
| `UT_ST_FLOW_LIMIT` | `Running: flow limit` | The flow limit holds the speed down |
| `UT_ST_FALLBACK` | `Running: fallback speed` | FALLBACK for any other reason |
| `UT_ST_MANUAL_SPEED` | `Running: manual speed` | MANUAL: the operator's speed |
| `UT_ST_FIXED_SPEED` | `Running: fixed speed` | `control` FIXED: running at the preset's fixed speed |
| `UT_ST_ENABLE_CYCLE` | `Waiting: Enable must cycle` | After a MANUAL reset of a stopped loop (unless `restartAfterReset`) |
| `UT_ST_DRIVE_NOT_RUNNING` | `Waiting: drive not running` | `Run` given, `Running` FALSE |
| `UT_ST_SLEEPING` | `Sleeping` | SLEEP; it wakes when Pv passes sp ∓ `wakeDrop` (`timeLeft`: `minSleep`, then the wake delay) |
| `UT_ST_WARNING` | `Warning: sensor bad` | The sensor failed with `pvFail` FALLBACK or HOLD (it runs), or in manual |
| `UT_ST_WARNING` | `Warning: <protection>` | A protection set to WARN, e.g. `Warning: overpressure` (speed at minimum) |
| `UT_ST_WARN_SETTING` | `Setting: a setting` | Bit 7: a setting is invalid, a safe value is used |
| `UT_ST_FAULT` | `Fault: <protection>` | A trip with AUTO reset, e.g. `Fault: overpressure` (`timeLeft` while the recover time counts) |
| `UT_ST_FAULT_RETRY` | `Retrying: <protection>` | A RETRY trip (the protection's `retries` of `maxRetries`, `timeLeft`) |
| `UT_ST_FAULT_RESET` | `Latched: <protection>` | A MANUAL trip |
| `UT_ST_FAULT_LOCKED` | `Locked: <protection>` | A RETRY trip past `maxRetries` |
| `UT_ST_FAULT` | `Fault: sensor bad` | The sensor failed with `pvFail` STOP: the pump stops |
| `UT_ST_CONFIG` | `Config: <setting>` | No run until fixed: `UT_F_SETTING` (an unknown `control`), `UT_F_SETPOINT` (the setpoint in use 0 or not a number: `sp`, `spLow`, `spHigh`, the `Sp` pin, or `flowSp` …), `UT_F_KP` (kp), `UT_F_MIN_MAX_SPEED` (min / max speed), `UT_F_RATE_LIMIT` (rate limit), `UT_F_RATE_UNIT` (rate unit), `UT_F_START_SPEED` (start/fallback speed) |

`<protection>` is `faultId`, most important first: `UT_F_OVERPRESSURE` (`highPv`),
then (after a failed sensor with STOP) `UT_F_LOW_AT_MAX` (`lowPvAtMax`, low at max
speed: burst?), `UT_F_PIPE_FILL` (pipe fill time), `UT_F_NOT_REACHING` (below
setpoint), `UT_F_HUNTING` (loop hunting: a hunting trip runs on at the fallback speed
and shows here).

### Hunting
A crossing is Pv passing the setpoint in use from more than `huntBand/2` on one side to
more than `huntBand/2` on the other. The block counts crossings in the `huntWindow`
under way, and starts a new window each time one has passed. `huntCount` is the
crossings of the window under way plus the last whole window's share of the time
still to go: just after a new window starts it is close to the last window's count,
and that part fades out as the new window runs. It drops to 0 once there has been no
crossing for a whole `huntWindow`. The `hunting` protection is raised while
`huntCount` is above `huntCycles`.

### Control: PV, FLOW or FIXED, and the presets
| `control` | The speed follows | Setpoint or speed by `preset` (NORMAL / LOW / HIGH) |
| --- | --- | --- |
| `UT_SC_CTRL_PV` (default) | The PID on `Pv`: a pressure or a level | `sp` / `spLow` / `spHigh` (0 = `sp`); the `Sp` pin instead with `spSource := UT_SP_PIN` |
| `UT_SC_CTRL_FLOW` | The PID on the `Flow` pin | `flowSp` / `flowSpLow` / `flowSpHigh` (0 = `flowSp`) |
| `UT_SC_CTRL_FIXED` | A fixed speed, no PID | `fixedSpeed` / `fixedSpeedLow` / `fixedSpeedHigh` (100 / 50 / 100 %) |

- `preset` can change at any time; the new setpoint is reached at `spRamp` (a step
  when 0), and a new fixed speed at `rateLimit`.
- **FLOW**: the flow is the value under control (`pv`, `spActive`, `AtSetpoint`,
  `notReaching`, hunting, the pipe-fill target and `lowPvAtMax` work on it), and a
  failed flow signal (not a number) is the sensor failure (`pvFail`). `highPv` still
  watches the `Pv` pin, so wire the pressure there to keep the overpressure
  protection.
- **FIXED**: the PID is not used. The pump runs at the preset's fixed speed (phase
  `UT_SC_MANUAL`, status `UT_ST_FIXED_SPEED`), held inside `minSpeed`..`maxSpeed` and
  reached at `rateLimit`. `PvGood` FALSE does not stop it. `highPv` still watches
  `Pv`, and the other protections act as with the manual speed: `lowPvAtMax` at the
  top speed, the flow limit, the rate limit; a `Pv` that is not a number still counts
  as a failed sensor (`pvFail`). No fill, sleep, hunting or `notReaching`. The
  operator's manual speed (`cmdManual`, `manualSpeed`) wins over the fixed speed
  until `cmdAuto`.

### On the HMI
Every PID value is in the record, for a tuning or overview screen: the settings
`kp`, `ti`, `td`, `deadband`, `minSpeed`, `maxSpeed`, `rateLimit` and `rateUnit` (the
ramp), `control` and `preset`; and the status `spActive`, `pv`, `speed`, `error`,
`pTerm`, `iTerm`, `dTerm` and `phase`.

The speed goes to the drive through [UT_MOTOR_VSD](UT_MOTOR_VSD.md): `Speed` to its
`AutoSpeed`, and its `SpeedRef` (%) or `SpeedRefRaw` (raw) to the analog output, or
through UT_IO_MAP_OUT. The drive's run, fault and ready relays are
UT_MOTOR_VSD's `Feedback`, `DriveFault` and `DriveReady`.

## How it works
1. `Enable` → `Run` with `Speed` = `startSpeed`, held there until `Running`. With the
   fill on, the fill phase runs until Pv reaches the fill target (or times out).
2. The loop is the standard PID form (as the IEC / CODESYS `PID`):
   `Speed = kp · (e + 1/ti · ∫e dt + td · de/dt)`, e = sp − Pv (Pv − sp reverse acting).
   It takes over **bumplessly**: the integral is loaded so it carries on from the speed
   it is given (after the start, the fill, an override or the fallback). The output is
   clamped to min/max and rate-limited. **Anti-windup**: the integral never integrates
   past the output limits, and stops while the output is held by a limit or by the
   rate limit.
3. Overrides act **outside** the loop: overpressure → min speed or stop; flow limit →
   speed capped. Each takes priority, and the loop follows without winding up.
4. Sleep when the demand has gone (boost, then stop); wake on a pressure drop. Hunting,
   a failed sensor or lost pressure at max speed trigger the protections above.
5. A trip that stops the pump goes to IDLE; it restarts (with the fill) when the trip
   clears by itself (AUTO / RETRY). After a MANUAL reset, `Enable` must go FALSE and
   back (unless `restartAfterReset`), like every device in the library.

Time comes from `TIME()` in whole milliseconds (the rest carried to the next scan),
so the loop, the ramps and every delay behave the same at any task interval.

## For block builders: UT_SPEED_CTRL_RUN
The loop is also a function, `UT_SPEED_CTRL_RUN`, which UT_SPEED_CTRL and
[UT_PUMP_CASCADE](UT_PUMP_CASCADE.md) run inside. A function has no instance of its
own, so the record is not copied: the block that owns the loop keeps its working state
in a `UT_SPEED_CTRL_ST` and passes it with the record every scan.

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable`, `Pv`, `PvGood`, `Sp`, `Running`, `Flow`, `ExtSpeed`, `Reset`, `MoreAvailable` | | | As the block's pins above (same defaults) |
| inout | `Data` | UT_SPEED_CTRL_DATA | | The loop's record |
| inout | `St` | UT_SPEED_CTRL_ST | | The loop's working state. Its `Run`, `Speed`, `Phase`, `AtSetpoint`, `MoreNeeded`, `LessNeeded`, `Fault` and `Warning` are the block's outputs. Not for HMIs |
| returns | | BOOL | | `Run` |

