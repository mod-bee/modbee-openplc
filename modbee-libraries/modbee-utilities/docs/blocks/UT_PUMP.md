# UT_PUMP — Pump control and protection

Decides **when** a pump should run and **protects the pump** using whatever
instruments the site has. Pressure, flow and suction can each be a switch, a
transducer/meter, both, or not fitted at all. Each has four levels (HH, H, L, LL):
H and L warn early that something is wrong, HH and LL trip. Every protection can
recover by itself, retry a set number of times, or latch, which you choose per
protection.

It drives a motor block: `RunCmd` → motor `AutoCmd`, `Healthy` → motor `Interlock`.
The motor block owns Hand/Off/Auto and the electrical protection (overload,
thermistor, feedback). Because `Healthy` is the motor's interlock, a pump trip
(dry run, high pressure…) stops the motor in **Hand** too. For speed-controlled
pumps, put [UT_SPEED_CTRL](UT_SPEED_CTRL.md) in front of it.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Demand` | BOOL | FALSE | Run request, in every mode: DEMAND runs while it is TRUE; EMPTY pumps down now to `stopPoint`; FILL fills now to `stopPoint` or the high float; TIMED runs the on/off cycle. From `UT_RUN_LIMIT.RunCmd`, `UT_SPEED_CTRL.Run`, `UT_ZONE_SEQ.PumpDemand`. Ignored while a station owns the pump |
| in | `Pv` | REAL | 0.0 | Level/pressure for the EMPTY/FILL control modes |
| in | `HighFloat` | BOOL | FALSE | High-level float, TRUE = made (EMPTY: runs the pump; FILL: stops it). Not used while a station owns the pump. A float that opens at high level: `NOT` at the pin |
| in | `Running` | BOOL | FALSE | Motor running (`UT_MOTOR.Running`) |
| in | `MotorReady` | BOOL | TRUE | Motor ready (`UT_MOTOR.Ready`) |
| in | `MotorAuto` | BOOL | TRUE | Motor in Auto (`UT_MOTOR.Auto`) |
| in | `Pressure` | REAL | 0.0 | Discharge pressure transducer (if `pressure.sensor` is analog) |
| in | `PressureHigh` | BOOL | FALSE | High-pressure switch, TRUE = pressure high (an NC contact: `NOT` at the pin) |
| in | `PressureLow` | BOOL | FALSE | Low-pressure switch, TRUE = pressure low (an NC contact: `NOT` at the pin) |
| in | `Flow` | REAL | 0.0 | Flow meter (if `flow.sensor` is analog) |
| in | `FlowSwitch` | BOOL | FALSE | Flow switch, TRUE = flow present. A contact that opens on flow: `NOT` at the pin |
| in | `Suction` | REAL | 0.0 | Suction pressure or source tank/well level (analog) |
| in | `DryRun` | BOOL | FALSE | Dry-run float / probe / low-suction switch, TRUE = dry. A float that is made with water (fail-safe on a broken wire): `NOT` at the pin |
| in | `SealLeak` | BOOL | FALSE | Seal-leak / moisture probe relay |
| in | `ExtFault` | BOOL | FALSE | Any other pump trip (bearing temperature relay, vibration switch…) |
| in | `PrimeDone` | BOOL | FALSE | Pipe filled, if not detected from pressure or flow (see `prime`) |
| in | `Reset` | BOOL | FALSE | Reset for MANUAL protections (panel button, rising edge) |
| in | `Inhibit` | BOOL | FALSE | Stops the pump's own runs at once and blocks them, without a fault: a system off, a tariff period. Status `Blocked: inhibit`. It does not stop a motor in Hand: for that use the motor's `Interlock` or `ForceOff` |
| in | `Permissive` | BOOL | TRUE | FALSE blocks a start (status `Not permitted`); a running pump carries on |
| in | `StartHold` | BOOL | FALSE | TRUE makes a start wait (status `Waiting: start hold`), e.g. while a stirrer pre-runs. Unlike `Permissive`, the pump stays `Available`: a station keeps it called and does not fail over to another pump. A running pump carries on |
| out | `RunCmd` | BOOL | | → motor `AutoCmd` |
| out | `Healthy` | BOOL | | → motor `Interlock`. FALSE = a pump trip is holding it off |
| out | `Available` | BOOL | | Healthy, motor ready and in Auto, not inhibited and permitted (or running): can run if asked (stations) |
| out | `Fault` | BOOL | | Any trip |
| out | `Warning` | BOOL | | Any warning (an abnormal condition to look at) |
| out | `Priming` | BOOL | | Pipe-fill phase |
| inout | `Data` | UT_PUMP_DATA | | The pump's record |

## Record `UT_PUMP_DATA`

### Control
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `pumpMode` | UT_PUMP_MODE | UT_PM_DEMAND | `UT_PM_DEMAND` (0): run while `Demand` · `UT_PM_EMPTY`: start when `Pv ≥ startPoint`, stop when `Pv ≤ stopPoint`; `Demand` pumps down now · `UT_PM_FILL`: start when `Pv ≤ startPoint`, stop when `Pv ≥ stopPoint`; `Demand` fills now · `UT_PM_TIMED`: cycles `onTime`/`offTime` while `Demand` (starting with the on phase) |
| `demandStopAtPv` | BOOL | FALSE | DEMAND: `Pv ≤ stopPoint` ends the demand as a normal stop (no fault): status `UT_ST_STOPPED_LOW` and `stopReason` `UT_STOP_LOW_LEVEL`. It runs again once `Pv ≥ startPoint` or when `Demand` is given again. The effluent sump's L stop in every mode |
| `startPoint` / `stopPoint` | REAL | 80.0 / 20.0 | EMPTY/FILL. Points the wrong way round (or equal, or not a number) → `setpoints` warning, no start |
| `onTime` / `offTime` | TIME | T#5m / T#5m | TIMED. `onTime` 0 = never runs; `offTime` 0 = runs continuously |
| `startDelay` / `stopDelay` | TIME | T#0s | The request must last this long to start / be gone this long to stop |
| `minRunTime` / `minOffTime` | TIME | T#0s | Anti-short-cycle (trips always stop at once). Power-up counts as a stop |
| `startMask` | TIME | T#10s | Low levels with `maskAtStart` ignored after the motor starts |
| `retryWindow` | TIME | T#1h | Window for RETRY counting (all protections) |
| `resetByOff` | BOOL | TRUE | The motor leaving Auto (selector to Off) resets MANUAL faults |
| `exerciseInterval` / `exerciseTime` | TIME | T#0s / T#30s | Anti-seize run of an idle pump (0 = off). Not while a station owns the pump, nor in FILL with the high float made |
| `highFloatHold` | TIME | T#2m | EMPTY: keep running this long after `HighFloat` clears, then `Pv` decides again |

### Measurements (each a [`UT_MEAS`](../conventions.md#ut_meas--a-measurement-that-might-be-a-switch-a-transmitter-both-or-nothing))
| Field | Default set-up | Typical use |
| --- | --- | --- |
| `pressure` | not installed · switch · high switch → HH, low switch → LL · `onlyWhenRunning` · low levels masked at start · **HH** trip RETRY (3, delay 1 s, recover 1 min) · **H** warn (5 s) · **L** warn (5 s) · **LL** trip RETRY (3, delay 2 s, recover 5 min) · placeholder sp 10 / 8 / 2 / 1, deadband 0.2 | HH = closed valve / deadhead. H = partial blockage. L = high demand / leak. LL = burst main / lost prime |
| `flow` | not installed · switch · low switch → LL (the block feeds it `NOT FlowSwitch`: no flow) · `onlyWhenRunning` · masked at start · **HH** off · **H** warn (5 s) · **L** warn (5 s) · **LL** trip RETRY (3, delay 2 s, recover 5 min) · placeholder sp 120 / 100 / 20 / 10, deadband 2 | LL = no flow (dry, air-locked, blocked). H = burst pipe / end of curve. L = clogging intake or impeller |
| `suction` | not installed · switch · low switch (the `DryRun` pin) → LL · checked when stopped too (blocks a start) · **LL** trip AUTO (delay 1 s, recover 2 min) · others off · placeholder sp 10 / 8 / 2 / 1, deadband 0.2 | Dry-run protection on the source: well, dam, tank, suction pressure |

Set the setpoints for the site: the values above are placeholders. The pressure and
flow switches are wired to `PressureHigh` / `PressureLow` and `FlowSwitch`; the
suction switch is `DryRun`. There are no NC settings: every switch pin is TRUE when it
signals (high, low, dry, flow present). Wire a contact that works the other way through
`NOT` at the pin.

### Other protections (each a `UT_PROTECTION`)
| Field | Default | Raised when |
| --- | --- | --- |
| `sealLeak` | WARN, AUTO | `SealLeak` input |
| `extFault` | TRIP, AUTO | `ExtFault` input |
| `primeTimeout` | TRIP, RETRY (3, recover **2 min**) | Not primed in `prime.timeout` |
| `maxRun` | OFF, `delay` **T#4h** (the maximum continuous run time), reset **MANUAL** | Ran too long: burst main, stuck float. MANUAL so a stuck run cannot repeat itself every `recover`. `maxRunLeft` counts down |
| `setpoints` | WARN | EMPTY/FILL points the wrong way round |

### Priming (`prime : UT_PUMP_PRIME`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enable` | BOOL | FALSE | Prime at every start |
| `doneBy` | UT_PRIME_DONE | UT_PRIME_PRESSURE | `UT_PRIME_PRESSURE`: pressure above L (transmitter above `pressure.lo.sp`, or the low-pressure switch clear) · `UT_PRIME_FLOW`: flow above L (meter above `flow.lo.sp`, or the flow switch showing flow) · `UT_PRIME_INPUT`: the `PrimeDone` pin |
| `timeout` | TIME | T#60s | Not primed in this time from the moment the motor runs → `primeTimeout` |
| `holdTime` | TIME | T#2s | The primed condition must last this long (with the motor running) |

Priming starts when the motor is seen running (the rising edge of `Running`), so the
motor's restart delay, a start inhibit or the contactor time never count as priming
time, and lasts until primed or the pump stops. While priming, low levels with
`maskAtStart` are masked and `Priming` is TRUE (a VSD can run a fill speed from it);
`primeLeft` counts down the time left and the status shows `Priming: 1 m 20 s left`.

**Prime next start only** (`cmdPrimeNext`): sets `primeNext`; the next start primes
as with `enable`. `primeNext` clears after a completed prime and stays set if the run
stops before the prime completes (or times out). It is not kept over a power cut.
`cmdPrimeCancel` (or the `PrimeCancel` pin) withdraws it before that start; a prime
already running carries on.

A prime that can never finish is a configuration fault (status `Config: prime needs
pressure installed` / `Config: prime needs flow installed`, the pump is held off):
with `enable` or `primeNext`, `doneBy` PRESSURE or FLOW names a measurement that is
not installed, or a switch with no low switch.

### Diagnosis (warnings that point at the likely cause)
`diagnosis : UT_PUMP_DIAG`, from the levels in effect (H or HH = high, L or LL = low),
first match wins:
| Value | Pattern | Likely cause |
| --- | --- | --- |
| `UT_DIAG_NORMAL` (0) | | |
| `UT_DIAG_BLOCKED` | pressure high + flow low | closed valve, blocked line, deadhead |
| `UT_DIAG_BURST` | pressure low + flow high | burst pipe, open hydrant |
| `UT_DIAG_SUCTION` | suction low (L or LL) | source running low, blocked foot valve or strainer |
| `UT_DIAG_NO_LIFT` | pressure low + flow low | air lock, dry, worn impeller, wrong rotation |

### HMI commands
| Field | Type | Meaning |
| --- | --- | --- |
| `cmdReset` | BOOL | Reset MANUAL protections |
| `cmdExercise` | BOOL | Exercise run now (if idle and available) |
| `cmdPrimeNext` | BOOL | Prime on the next start only (sets `primeNext`) |
| `cmdPrimeCancel` | BOOL | Withdraw prime next start (clears `primeNext`) |

Each acts once, on its rising edge, and is cleared by the block; a held command acts
once.

### Status fields
`state : UT_STATE` (FAULT · STARTING · WARNING · ON · STOPPING · OFF), `runCmd`,
`demand` (asked to run, after the delays), `running`, `healthy`, `available`,
`priming`, `masked`, `runTime : TIME` (this run), `exercising`, `highFloat` (the high
float is acting: EMPTY made or in its hold, FILL made), `pvBad` (`Pv` not a number in
EMPTY/FILL: the last decision is held), `configBad` (a setting is invalid, bit 18),
`stationOwned`, `diagnosis`, `fault`, `warning`, `faultCode : DWORD`, `faultId : UT_FAULT`
(the first trip by the bit order below, else the first warning),
`statusCode : UT_STATUS` and `statusText : STRING(30)` (what it is doing or what holds
it back, see [Status](#status)).

More status fields:
| Field | Type | Meaning |
| --- | --- | --- |
| `demandStopAtPv` | BOOL | Setting, see Control |
| `cmdPrimeNext` | BOOL | HMI command, see Priming |
| `cmdPrimeCancel` | BOOL | HMI command, see Priming |
| `primeNext` | BOOL | A one-shot prime is armed |
| `primeLeft` | TIME | The prime's time still to run while priming: `prime.runTime` when done by TIME, else up to `prime.timeout` (0 otherwise) |
| `maxRunLeft` | TIME | Time before `maxRun` trips (0 when it is OFF, tripped or the pump is stopped) |
| `timeLeft` | TIME | The countdown that goes with the status: a delay, priming, a fault's recover / retry wait… (0 = none) |
| `timeLeftOf` | UT_STATUS | The `statusCode` that countdown belongs to (`UT_ST_IDLE` = none) |
| `phaseTime` | TIME | Time in the current phase: running (`runTime`) or stopped (`idleTime`) |
| `idleTime` | TIME | Time since the pump last ran (0 while running) |
| `nextExerciseIn` | TIME | Time to the next exercise run (0 when exercise is off, or running) |
| `inhibited` | BOOL | The `Inhibit` pin is holding its runs off |
| `startHold` | BOOL | `StartHold` is making a start wait (FALSE while the run command is on). A station does not fail over from a pump while this is set |
| `stopReason` | UT_STOP | Why the last run ended (below) |
| `lastFaultCode` / `lastFault` | DWORD / UT_FAULT | The trip bits and the name of the last trip, kept after it clears until the next trip |
| `trips` | UDINT | Trips since power-up |

### Stop reasons (`stopReason`)
The shared reasons ([conventions](../conventions.md#why-it-stopped)) and the pump's own:
| `stopReason` | Words ([UT_STOP_TEXT](UT_STOP_TEXT.md)) | When the run ended |
| --- | --- | --- |
| `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` | The request dropped (`Demand`, the level reached the stop point, a TIMED off phase) |
| `UT_STOP_OPERATOR` | `Stopped: operator` | A Hand run ended |
| `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` | The motor left Auto while the pump was running it |
| `UT_STOP_FAULT` | `Stopped: fault` | A pump trip (`lastFault` says which) |
| `UT_STOP_MAX_RUN` | `Stopped: max run time` | `maxRun` tripped |
| `UT_STOP_INHIBITED` | `Stopped: inhibited` | The `Inhibit` pin |
| `UT_STOP_GROUP` | `Stopped: group` | The station stopped it |
| `UT_STOP_LOW_LEVEL` | `Stopped: low level` | `Demand` reached the stop point (DEMAND with `demandStopAtPv`, or an EMPTY pump-down) |
| `UT_STOP_FULL` | `Stopped: full` | FILL: the high float, or `Demand` filled to the stop point |
| `UT_STOP_EXERCISE_DONE` | `Done: exercise` | An exercise run finished |
| `UT_STOP_BY_MOTOR` | `Stopped: by the motor` | The motor stopped while commanded (its trip, interlock, feedback): the motor's own `stopReason` says why |

Group fields, written by [UT_PUMP_STATION](UT_PUMP_STATION.md): `grpActive` (set by the
station every scan, cleared by the pump), `grpRun`, `grpRank`, `grpSkipped`, and
`grpRunTime : TIME` (the run time the station has counted since power-up, for its
HOURS rotation; the station sets it back to 0 on its first scan after a power cut, also in a `RETAIN` record).

### Fault code bits (lowest = most important; `faultId` names the first trip, else the first warning)
| Bit | Protection | `faultId` (words) |
| --- | --- | --- |
| 0 | `suction.loLo` | `UT_F_DRY_RUN` (dry run) |
| 1 | `pressure.hiHi` | `UT_F_PRESSURE_HH` (pressure HH) |
| 2 | `pressure.loLo` | `UT_F_PRESSURE_LL` (pressure LL) |
| 3 | `flow.loLo` | `UT_F_NO_FLOW` (no flow) |
| 4 | `flow.hiHi` | `UT_F_FLOW_HH` (flow HH) |
| 5 | `suction.hiHi` | `UT_F_SUCTION_HH` (suction HH) |
| 6 | `primeTimeout` | `UT_F_PRIME` (failed to prime) |
| 7 | `extFault` | `UT_F_EXTERNAL` (external fault) |
| 8 | `maxRun` | `UT_F_MAX_RUN` (ran too long) |
| 9 | `sealLeak` | `UT_F_SEAL_LEAK` (seal leak) |
| 10–15 | `pressure.hi`, `pressure.lo`, `flow.hi`, `flow.lo`, `suction.hi`, `suction.lo` | `UT_F_PRESSURE_H`, `UT_F_PRESSURE_L`, `UT_F_FLOW_H`, `UT_F_FLOW_L`, `UT_F_SUCTION_H`, `UT_F_SUCTION_L` (pressure high … suction low) |
| 16 | `setpoints` | `UT_F_POINTS` (start/stop points) |
| 17 | `Pv` not a number or infinite (EMPTY/FILL, own control): a warning, the last decision is held | `UT_F_PV_BAD` (Pv not a number) |
| 18 | A setting is invalid: a **trip** for a configuration fault, else a warning | The setting (configuration faults, below), or `UT_F_SETTING` (a setting) |
| 19 | A fitted pressure, flow or suction transmitter reads NaN or infinite: a warning (its levels hold; a switch with `UT_SENSOR_BOTH` still acts) | `UT_F_SENSOR_BAD` (sensor bad) |

### Invalid settings
- **Configuration fault** (bit 18 as a trip: `Healthy` FALSE, the pump is held off until
  it is fixed): an unknown `pumpMode`; a fitted measurement with an unknown `sensor`,
  `highSwitch` (only NONE, HH, H) or `lowSwitch` (only NONE, L, LL); an unknown
  `response` in any level or protection; with `prime.enable` or `primeNext`, an unknown
  `prime.doneBy`, or a `doneBy` measurement that is not installed (or a switch with no
  low switch).
  Each of these would switch a protection off without telling anyone.
- **Warning** (bit 18 as a warning, the pump runs): a negative time (it acts as 0); a
  level or protection with a bad setpoint, deadband or time (`BadSetting` of its check);
  an unknown `reset` (acts as AUTO).
- Start/stop points the wrong way round or not a number: the `setpoints` protection
  (bit 16, WARN by default) and no start from `Pv`.

### Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the pump is doing,
or what holds it back, so a technician can see on the HMI why it is not running
without opening the program. The most important reason wins: configuration > fault >
held / waiting > warning > running > idle. A pump asked to run (a request, an
exercise, or its run command) that is not running always shows a held, fault or
configuration status, or `UT_ST_STARTING` while its run command is out and the
motor's run feedback is not yet in. A warning shows over "Running" so it is seen.
The countdown is in `timeLeft`, and `timeLeftOf` says which status it belongs to.
The text is rebuilt only when the status or the fault changes (or when the text has
been cleared). A pump with `Demand` TRUE never says `Idle`. The numbers are in
[conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE` | `Idle` | Nothing asks it to run |
| `UT_ST_OFF_NOT_AUTO` | `Off: motor not in Auto` | Nothing asks it to run, and the motor is not in Auto |
| `UT_ST_RUN_AUTO` | `Running: Auto` | Running on its own request |
| `UT_ST_RUN_HAND` | `Running: Hand` | Running with the motor not in Auto |
| `UT_ST_STARTING` | `Starting` | Run command out, run feedback not yet in |
| `UT_ST_STOPPING` | `Stopping` | Run command off, the motor still running |
| `UT_ST_RUN_GROUP` | `Running: group` | A [UT_PUMP_STATION](UT_PUMP_STATION.md) runs it; `grpRank` is its place |
| `UT_ST_EXERCISING` | `Exercising` | An exercise run (`timeLeft`) |
| `UT_ST_IDLE_GROUP` | `Idle: in group` | A station owns it and has not called it |
| `UT_ST_PRIMING` | `Priming` | Filling the pipe; `timeLeft` is the time before `primeTimeout` |
| `UT_ST_HIGH_FLOAT` | `Running: high float` | EMPTY: the high float runs it (made, then `highFloatHold`, counting in `timeLeft`) |
| `UT_ST_MIN_RUN` | `Running: min run time` | The request has gone; `minRunTime` keeps it on (`timeLeft`) |
| `UT_ST_STOP_DELAY` | `Running: stop delay` | The request has gone; `stopDelay` keeps it on (`timeLeft`) |
| `UT_ST_RUN_TIMED` | `Running: timed` | TIMED: the on time (`timeLeft`) |
| `UT_ST_RUN_DEMAND` | `Running: demand` | EMPTY / FILL: `Demand` runs it (pump down / fill up), not the level |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | Asked to run, `Permissive` is FALSE |
| `UT_ST_START_HOLD` | `Waiting: start hold` | Asked to run, `StartHold` is TRUE (shown after `Not permitted`) |
| `UT_ST_MIN_OFF` | `Waiting: min off time` | Asked to run inside `minOffTime` (`timeLeft`) |
| `UT_ST_START_DELAY` | `Waiting: start delay` | Asked to run, `startDelay` not over (`timeLeft`) |
| `UT_ST_INHIBITED` | `Blocked: inhibit` | Asked to run (or `Demand` TRUE), `Inhibit` is on |
| `UT_ST_MOTOR_NOT_AUTO` | `Blocked: motor not in Auto` | Asked to run, the motor is in Off, Hand or OOS |
| `UT_ST_MOTOR_NOT_READY` | `Blocked: motor not ready` | Asked to run, the motor is not ready (its trip, interlock, permissive or restart delay: the motor's own status says which) |
| `UT_ST_FULL` | `Blocked: high float (full)` | FILL: the high float is made |
| `UT_ST_TIMED_REST` | `Waiting: timed rest` | TIMED: the off time (`timeLeft`) |
| `UT_ST_STOPPED_LOW` | `Stopped: low level` | `Demand` is TRUE but its run reached the stop point; it runs again at the start point or a new `Demand` |
| `UT_ST_STOPPED_FULL` | `Stopped: full` | As above, in FILL |
| `UT_ST_WARNING` | `Warning: <fault>` | A protection set to WARN (e.g. `Warning: seal leak`), bit 17 (`Warning: Pv not a number`) or bit 19 (`Warning: sensor bad`) |
| `UT_ST_WARN_SETTING` | `Setting: <setting>` | Bit 18 as a warning: a safe value is used |
| `UT_ST_FAULT` | `Fault: <fault>` | A trip with AUTO reset, e.g. `Fault: dry run`; `timeLeft` while the recover time counts |
| `UT_ST_FAULT_RETRY` | `Retrying: <fault>` | A RETRY trip: the protection's `retries` of `maxRetries`, and the wait left in `timeLeft` |
| `UT_ST_FAULT_RESET` | `Latched: <fault>` | A MANUAL trip |
| `UT_ST_FAULT_LOCKED` | `Locked: <fault>` | A RETRY trip past `maxRetries` |
| `UT_ST_CONFIG` | `Config: <setting>` | It will not run until fixed (settings below) |

`<fault>` is `faultId`: the first trip by the bit order above, else the first warning.
`<setting>` with `UT_ST_CONFIG` is one of: `UT_F_PUMP_MODE` (pump mode) ·
`UT_F_PRIME_DONEBY` (prime doneBy) · `UT_F_PRIME_NEEDS_PRES` (prime: no pressure) ·
`UT_F_PRIME_NEEDS_FLOW` (prime: no flow) · `UT_F_PRESSURE_SENSOR` /
`UT_F_FLOW_SENSOR` / `UT_F_SUCTION_SENSOR` (sensor or switch level unknown) ·
`UT_F_RESPONSE` (response unknown) · `UT_F_POINTS` (start/stop points wrong way
round). With `UT_ST_WARN_SETTING` it is the setting found, or `UT_F_SETTING` (`a
setting`).

## How it works
- **Run request**: a station's `grpRun` while a station owns the record, otherwise
  the `pumpMode` and `Demand`. Then `startDelay` / `stopDelay`, then exercise. `RunCmd`
  follows it with `minRunTime` / `minOffTime`; any pump trip, and `Inhibit`, drop it at
  once; `Permissive` FALSE holds back a start; so does `StartHold`, which keeps the
  pump available.
- **Demand in every mode.** DEMAND: runs while `Demand` is TRUE (with
  `demandStopAtPv` until `Pv ≤ stopPoint`). EMPTY: `Demand` pumps down now, to
  `stopPoint`, with the protections kept ("run now"). FILL: `Demand` fills now, to
  `stopPoint` or the high float. After such a stop a held `Demand` runs again once
  `Pv` is back at `startPoint` (the level control would start it there anyway), or
  when it is given again (a new rising edge). A `Pv` that is not a number holds it.
- **Station**: the station sets `grpActive` every scan and the pump clears it after
  reading it, so if the station block stops being called the pump is back on its own
  mode from the next scan. On its first scan after power-up the pump ignores
  `grpRun` (a retained record must not start every pump at once).
- **Resets** of MANUAL protections (and RETRY ones whose retries are used up): the
  `Reset` pin, `cmdReset`, or the motor leaving Auto (`resetByOff`). Refused while the
  cause is still there. A reset clears faults only: the event counts
  (`count` in each protection) are kept.
- **Exercise**: an idle pump that is healthy, ready and in Auto runs `exerciseTime`
  after `exerciseInterval` without running (or on `cmdExercise`). A real request
  takes over from an exercise.
- A `Pv` that is not a number (NaN, infinity) holds the pump as it is (the last good
  decision) and raises a warning (bit 17, `pvBad`). The floats still act.
- **High float** (`HighFloat`, own control only, ignored while a station owns the
  pump). EMPTY: overflow backup. The pump runs while the float is made, whatever `Pv`
  says, and `highFloatHold` after it clears. After that `Pv` decides again: a good `Pv`
  above the stop point keeps it running down to the stop point; a stuck or bad `Pv`
  lets it stop, and the float catches the next rise. A float stuck made keeps the pump
  running until its dry-run protection (`DryRun`) stops it, so fit one. FILL: the tank
  is full, the pump stops while the float is made (its own `stopDelay` / `minRunTime`
  still apply) and is not exercised. DEMAND and TIMED: not used.

### Power cut
Nothing is kept: every protection starts clear, with no retries used. A latched
(MANUAL) trip is forgotten; a fault that is still there trips again before the pump
can start. `primeNext`, `stopReason`, the last fault and `trips` start again. Power-up
counts as a stop for `minOffTime`.

Keep your record `RETAIN` (or write the settings every scan) so the settings are
there on the first scan.

## Examples of set-ups
| Site | Settings |
| --- | --- |
| Sump pump with a dry-run float only | `suction.installed := TRUE` (switch). Everything else not installed |
| Bore pump, pressure switch high only, auto recovery | `pressure.installed := TRUE`, `pressure.highSwitch := UT_LVL_HIHI`, `pressure.lowSwitch := UT_LVL_NONE`, `pressure.hiHi.reset := UT_RST_AUTO` |
| Irrigation pump with transducer + flow meter | `pressure.sensor := UT_SENSOR_ANALOG`, the four setpoints; `flow.sensor := UT_SENSOR_ANALOG`, setpoints; `prime.enable := TRUE` |
| Effluent sump pump, L stop in every mode, irrigation runs from [UT_RUN_LIMIT](UT_RUN_LIMIT.md) | `pumpMode := UT_PM_DEMAND`, `demandStopAtPv := TRUE`, `stopPoint := L`, `startPoint := H`; `Demand := SumpEmpty OR RunLimit.RunCmd OR ManualRun`; `Inhibit := SystemOff`; `maxRun.response := UT_RESP_TRIP` (4 h, MANUAL) |
| Booster with pressure switch **and** transducer | `pressure.sensor := UT_SENSOR_BOTH`. Either one raises its level (the switch backs up the transducer) |

## Using it
```iecst
Pump1(Demand := LevelHigh, Running := M1.Running, MotorReady := M1.Ready, MotorAuto := M1.Auto,
      DryRun := LowFloat, PressureHigh := P1_HiPS, Data := Pump1Data);
M1(AutoCmd := Pump1.RunCmd, Feedback := P1_Aux, Overload := P1_OL,
   Interlock := Pump1.Healthy, Data := Motor1);
```
