# UT_MOTOR — Motor starter (DOL / contactor / soft starter)

Controls and protects one motor started by a contactor, a soft starter or any
"run relay + run feedback" load (heater bank, fan, conveyor). Built in:
Hand/Off/Auto/Out-of-service, interlocks and permissives, overload, thermistor,
current monitoring, feedback supervision, welded-contactor detection and a
restart/backspin delay. Every protection can recover by itself, retry, or latch.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoCmd` | BOOL | FALSE | Run request from your logic (used in Auto) |
| in | `Feedback` | BOOL | FALSE | Contactor auxiliary / soft-starter "running" relay |
| in | `Overload` | BOOL | FALSE | Overload relay tripped (TRUE = tripped; a NC aux through NOT at the pin) |
| in | `Thermistor` | BOOL | FALSE | PTC relay / motor thermal switch tripped (a NC contact through NOT at the pin) |
| in | `DriveFault` | BOOL | FALSE | Soft-starter fault relay |
| in | `Current` | REAL | 0.0 | Motor current in amps (used if `fullLoadCurrent` > 0). NaN / infinite while a current protection is on: a warning (`wrnCurrentBad`) |
| in | `Interlock` | BOOL | TRUE | FALSE **stops** the motor in every mode (e.g. `UT_PUMP.Healthy`) |
| in | `Permissive` | BOOL | TRUE | FALSE **blocks starting** only (e.g. `UT_STARTS.StartPermit`) |
| in | `SwHand` / `SwAuto` | BOOL | FALSE | Selector switch (if `modeSource` uses it) |
| in | `LocalStart` | BOOL | FALSE | Local start pushbutton (Hand) |
| in | `LocalStop` | BOOL | FALSE | Local stop pushbutton (TRUE = pressed; a NC button through NOT at the pin) |
| in | `Reset` | BOOL | FALSE | Reset for MANUAL protections (rising edge) |
| out | `Run` | BOOL | | Contactor coil |
| out | `Running` | BOOL | | Run confirmed by feedback |
| out | `Fault` | BOOL | | A trip is holding it off |
| out | `Warning` | BOOL | | A protection set to warn is active, a bad current signal, or an invalid setting |
| out | `Ready` | BOOL | | Would start now if asked: healthy, permitted, in Auto or Hand, not waiting out `restartDelay` (stays TRUE while running) |
| out | `Auto` | BOOL | | In Auto mode |
| out | `State` | UT_STATE | | For HMIs |
| inout | `Data` | UT_MOTOR_DATA | | The motor's record |

Every input is TRUE = active (tripped, pressed). There is no NC setting: wire a
normally-closed contact through `NOT` at the pin or in the I/O mapping, e.g.
`Overload := NOT M1_OL_NC`.

## Record `UT_MOTOR_DATA` (shared by every UT_MOTOR* block)

### Settings
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `modeSource` | UT_MODE_SOURCE | UT_SRC_HMI | Where the mode comes from. The mode starts at **Off** and is retained |
| `useFeedback` | BOOL | TRUE | Supervise the run feedback |
| `fullLoadCurrent` | REAL | 0.0 | Motor FLC in A (0 = current monitoring off) |
| `currentStartMask` | TIME | T#5s | Ignore current after a start (inrush) |
| `restartDelay` | TIME | T#5s | Minimum off time before a start, counted from power-up too (anti-short-cycle, pump backspin, staggered restart after a power cut). `T#0s` = none |
| `restartAfterReset` | BOOL | FALSE | After a **MANUAL** reset, restart without the command cycling |
| `resetByOff` | BOOL | TRUE | Switching to Off resets MANUAL faults |
| `retryWindow` | TIME | T#1h | Window for RETRY counts. `T#0s` = no window: the count is cleared only by a reset or a power cycle |
| `localStopInAuto` | BOOL | TRUE | Local stop also stops in Auto (restart on the next `AutoCmd` rising edge) |
| `simulate` | BOOL | FALSE | The run feedback follows `Run` (so `noFeedback`, `feedbackLost` and `stuck` see the simulated feedback). Every other protection still acts: overload, thermistor, drive fault, `driveNotReady` and the current levels |
| `powerUp` | UT_POWERUP | UT_PU_LAST | After a power cut: `UT_PU_LAST` the mode comes back (Auto carries on); `UT_PU_OFF` back to Off, the operator selects it again. A Hand start is never kept either way. See [conventions](../conventions.md#power-up) |
| `handMaxRun` | TIME | T#0s | Hand: stop after running this long (a remote user hand-starts and forgets). `T#0s` = no limit; negative = no limit and a warning |

The reversing, star-delta, two-speed and VSD blocks keep their own settings, commands
and status in a second record of their own (`Rev`, `Sd`, `Spd`, `Vsd`), so a plain
motor carries none of them. See [REV](UT_MOTOR_REV.md), [SD](UT_MOTOR_SD.md),
[2SPD](UT_MOTOR_2SPD.md) and [VSD](UT_MOTOR_VSD.md).

### Protections (each a [`UT_PROTECTION`](../conventions.md#protections--every-fault-works-the-same-way) or `UT_LEVEL`; set each one's response and reset independently)
| Field | Bit | Default response · delay · reset | Raised when |
| --- | --- | --- | --- |
| `overload` | 0 | TRIP · 100 ms · **AUTO** | Overload relay tripped. Resetting the relay in the panel puts the motor back in service |
| `thermistor` | 1 | TRIP · 0 · AUTO (recover 5 min) | Motor too hot. Restarts after cooling |
| `noFeedback` | 2 | TRIP · 3 s · RETRY (3, recover 30 s) | `Run` without feedback (failed to start). The delay is the start time |
| `feedbackLost` | 3 | TRIP · 500 ms · RETRY (3, recover 30 s) | Feedback dropped while running |
| `stuck` | 4 | TRIP · 2 s · MANUAL | Feedback with no `Run`: welded contactor |
| `currentHigh` | 5 | OFF · 5 s · RETRY (3, recover 5 min) · sp 115 % FLC | Overcurrent / jam (`UT_LEVEL`) |
| `currentLow` | 6 | OFF · 5 s · RETRY (3, recover 5 min) · sp 40 % FLC | Underload: dry pump, broken belt or coupling (`UT_LEVEL`) |
| `drive` | 7 | TRIP · 0 · AUTO | `DriveFault` input |
| *(speed deviation)* | 8 | VSD only | `Vsd.speedDev` ([UT_MOTOR_VSD](UT_MOTOR_VSD.md)) |
| *(changeover)* | 9 | REV / SD / 2SPD only | The variant's `changeover` ([REV](UT_MOTOR_REV.md), [SD](UT_MOTOR_SD.md), [2SPD](UT_MOTOR_2SPD.md)) |
| *(drive not ready)* | 10 | VSD only | `Vsd.driveNotReady` ([UT_MOTOR_VSD](UT_MOTOR_VSD.md)) |
| *(current signal bad)* | 11 | Warning | `Current` is NaN or infinite while `fullLoadCurrent` > 0 and `currentHigh` or `currentLow` is not OFF (`wrnCurrentBad`). The motor keeps running; the current levels hold as they were |
| *(invalid setting)* | 12 | Warning, or a fault | A setting is invalid (`wrnConfig`), see [Invalid settings](#invalid-settings) |

`faultCode` has a bit for every protection that is raised, **warnings included**
(a WARN protection sets its bit as a TRIP one does), and `faultId` names the
lowest bit set. Bits 8 to 10 are the variants' protections, which live in the
variant's own record.

### HMI commands
| Field | Type | Meaning |
| --- | --- | --- |
| `cmdMode` | INT | 0 Off · 1 Hand · 2 Auto · 3 OOS (acts when a new value arrives; the block sets it back to −1) |
| `cmdStart` / `cmdStop` | BOOL | Hand start / stop |
| `cmdReset` | BOOL | Reset MANUAL protections |

The reversing and two-speed blocks have their direction and speed commands
(`cmdFwd` / `cmdRev`, `cmdLow` / `cmdHigh`) in their own record.

Every BOOL command acts once, **on its rising edge**, and is cleared by the block. One
held TRUE (a Modbus coil left on, a debugger force) acts once: a held `cmdStart` does
not restart a Hand motor after a stop, and a held `cmdReset` never turns a MANUAL trip
into an automatic one. Stop always wins: no start in a scan in which `cmdStop` or
`LocalStop` reads TRUE, so one held TRUE keeps the motor stopped. A master that
rewrites a command every poll goes through [UT_CMD](UT_CMD.md).

### Status fields
`mode`, `state`, `run`, `running`, `ready`, `fault`, `warning`, `interlocked`,
`notPermitted`, `restartBlocked`, `restartIn : TIME`, `current`, `currentPct`,
`runTime : TIME` (this run), `faultCode : DWORD` and `faultId : UT_FAULT` (both cover
warnings too), `statusCode : UT_STATUS` and `statusText : STRING(30)` (what it is
doing or what holds it back, see [Status](#status)), `wrnCurrentBad` (bit 11),
`wrnConfig` (bit 12).

Group fields. The motor block writes only `isVsd`; a group block
([UT_DUTY](UT_DUTY.md), [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md)) writes the `grp…`
fields; you set `capacity` and `jockey`:
| Field | Type | Meaning |
| --- | --- | --- |
| `grpActive` | BOOL | A group owns this motor (set every scan by the group, cleared by the motor) |
| `grpRun` | BOOL | The group asks it to run |
| `grpRank` | INT | Its place in the group's order |
| `grpSpeed` | REAL | VSD: the speed the group asks for, % (used in Auto while owned) |
| `isVsd` | BOOL | TRUE on a UT_MOTOR_VSD record, FALSE on the others, set every scan, so a group knows which pumps have a speed |
| `capacity` | REAL | Setting, default 0.0. A pump in a [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md): its flow at full speed at the setpoint pressure (0 = not known). Ignored by the motor |
| `jockey` | BOOL | Setting, default FALSE. A pump in a [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md): the small pump that carries the low demand. Ignored by the motor |
| `grpRunTime` | TIME | The run time the group has counted since power-up, for its HOURS rotation (the group sets it back to 0 on its first scan after a power cut, also in a `RETAIN` record) |

Added for time visibility and "why it stopped" (at the end of the record):
| Field | Type | Meaning |
| --- | --- | --- |
| `timeLeft` | TIME | The countdown the status shows: the restart delay, a dead time or star time, a fault's recover / retry wait, the Hand run limit |
| `offTime` | TIME | Time stopped, since the last stop or power-up (0 while running) |
| `maskLeft` | TIME | The current start mask still to run (0 when not masking) |
| `faultClearIn` | TIME | An AUTO / RETRY trip clears (or retries) in this (0 = nothing counting) |
| `stopReason` | UT_STOP | Why the last run ended (below; `UT_STOP_NONE` = none since power-up), kept until the next run ends |
| `lastFaultCode` | DWORD | The `faultCode` bits of the last trip, kept after it clears, until the next trip |
| `lastFault` | UT_FAULT | Its name (the lowest bit), e.g. `UT_F_OVERLOAD`, kept the same way |
| `trips` | UDINT | Trips since power-up (not kept over a power cut) |

**Why the last run ended** (`stopReason`, the common
[stop reasons](../conventions.md#why-it-stopped)):
| `stopReason` | Words ([UT_STOP_TEXT](UT_STOP_TEXT.md)) | When |
| --- | --- | --- |
| `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` | `AutoCmd` dropped |
| `UT_STOP_OPERATOR` | `Stopped: operator` | A Hand stop (`cmdStop`, `LocalStop`), or a local stop in Auto |
| `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` | The mode changed to Off or OOS |
| `UT_STOP_INTERLOCK` | `Stopped: interlock` | `Interlock` dropped |
| `UT_STOP_FAULT` | `Stopped: fault` | A protection tripped (or a setting keeps it off); `lastFault` says which |
| `UT_STOP_MAX_RUN` | `Stopped: max run time` | `handMaxRun` ran out |
| `UT_STOP_GROUP` | `Stopped: group` | A group ([UT_DUTY](UT_DUTY.md), [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md)) stopped it |

## How it works
- **Mode** ([UT_MODE_SELECT](UT_MODE_SELECT.md)): Off → stopped. Hand → `cmdStart`/`LocalStart` (rising edge) latch it on,
  `cmdStop`/`LocalStop` stop it. A start given while the `Permissive` is FALSE is
  dropped: the motor does not start later when the permissive returns; the
  operator presses start again (a start waiting out `restartDelay` is dropped too
  if the permissive goes). Auto → follows `AutoCmd`, or `grpRun` while a group (`UT_DUTY`, `UT_PUMP_CASCADE`) owns it (`grpActive`).
  OOS → stopped, protections suppressed, no fault or warning reported.
- **Run** = requested AND `Interlock` AND (already running OR `Permissive`) AND no trip AND
  not restart-blocked. A running motor keeps running if the permissive goes.
- A trip drops `Run` at once. In Auto, AUTO/RETRY recovery puts it back in service
  by itself if `AutoCmd` is still on. In Hand a trip drops the hand start, like the
  interlock: once the fault has cleared the operator presses start again. After a
  MANUAL reset of a stopped motor the command must cycle (unless `restartAfterReset`):
  in Auto, `AutoCmd` goes off and on; in Hand, the operator presses start again.
- A local stop in Auto stops it; it restarts on the next rising edge of `AutoCmd`.
- **Hand run limit** (`handMaxRun`): a Hand run stops after that long (counted from
  the start, or from the change to Hand of a running motor; status `Running: Hand`
  with `timeLeft` counting down, then `Hand: max run, press start` and `stopReason`
  `UT_STOP_MAX_RUN`). The operator presses start again for another run.
- In Hand, losing the interlock drops the hand start, so the motor does not restart
  by itself when the interlock returns. In Auto it restarts (its request is still on).
- `restartDelay` holds back a start until the motor has been off that long; a
  running motor is never stopped by it, nor by the permissive. It counts from
  power-up too, so motors with different delays come back one after the other.
- **After a power cut** the mode is kept (Off, Hand, Auto, OOS), unless `powerUp` is
  `UT_PU_OFF`: then it comes back Off and stays stopped until the operator selects a
  mode again (a conveyor someone must restart on purpose). Auto restarts by
  itself once `restartDelay` has run. Hand needs a fresh start: a start button held
  through the power cut, or a start command already waiting, is not one. Trips,
  latches and retries are not kept; a fault still there trips again.
- Mode changes are bumpless: Auto → Hand keeps a running motor running.
- `State`: OOS · FAULT · INTERLOCKED · STARTING (run, no feedback yet) · WARNING ·
  ON · STOPPING (feedback still on after the stop) · OFF.

## Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the motor is
doing, or what holds it back, so a technician can see on the HMI why it is not
running without opening the program. A motor asked to run that is not running
always shows a held, fault or configuration status. The most important reason wins:
configuration > fault > held / waiting > warning > running > idle. A warning shows
over "Running" so it is seen. The time that goes with a status is in `timeLeft`.
The text is rebuilt only when the status or the fault changes. The numbers are in
[conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off |
| `UT_ST_IDLE` | `Idle` | Auto with nothing asking it to run |
| `UT_ST_RUN_AUTO` | `Running: Auto` |  |
| `UT_ST_RUN_HAND` | `Running: Hand` | With `handMaxRun`: `timeLeft` is the time left |
| `UT_ST_STARTING` | `Starting` | Run given, run feedback not yet in |
| `UT_ST_STOPPING` | `Stopping` | Stopped, run feedback still on |
| `UT_ST_RUN_GROUP` | `Running: group` | A group ([UT_DUTY](UT_DUTY.md), [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md)) runs it; `grpRank` is its place |
| `UT_ST_RESTART_DELAY` | `Waiting: restart delay` | Asked to run, `restartDelay` not over yet (`timeLeft` counts down) |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE (every mode but OOS) |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | `Permissive` FALSE while stopped, in Hand or Auto |
| `UT_ST_HAND_PRESS_START` | `Hand: press start` | Hand and stopped: no start given, or it was dropped (a stop, a trip, the interlock, not permitted) |
| `UT_ST_WAIT_GROUP` | `Waiting: turn in group` | A group owns it and does not run it now |
| `UT_ST_HAND_MAX_RUN` | `Hand: max run, press start` | `handMaxRun` ended the Hand run |
| `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | After a MANUAL reset, or a local stop in Auto: `AutoCmd` must go off and on |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_WARNING` | `Warning: <fault>` | A protection set to WARN is raised, or `Current` is NaN or infinite while a current level is in use (`UT_F_CURRENT_BAD`, `current signal`) |
| `UT_ST_WARN_SETTING` | `Setting: <setting>` | An invalid setting, a safe value in use (settings below) |
| `UT_ST_FAULT` | `Fault: <fault>` | Tripped, AUTO: clears by itself once the cause has gone for `recover` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RETRY` | `Retrying: <fault>` | Tripped, RETRY: the protection's `retries` of `maxRetries` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RESET` | `Latched: <fault>` | Tripped, MANUAL: a reset (pin, `cmdReset`, Off) once the cause has gone |
| `UT_ST_FAULT_LOCKED` | `Locked: <fault>` | RETRY used up: now as MANUAL |
| `UT_ST_CONFIG` | `Config: <setting>` | An invalid setting keeps the motor off |

`<fault>` is `faultId`, one of: `UT_F_OVERLOAD` (overload) · `UT_F_MOTOR_HOT` (motor
too hot) · `UT_F_NO_FEEDBACK` (no run feedback) · `UT_F_FEEDBACK_LOST` (feedback
lost) · `UT_F_WELDED` (contactor welded) · `UT_F_CURRENT_HIGH` (current high) ·
`UT_F_CURRENT_LOW` (current low) · `UT_F_DRIVE` (drive fault) · `UT_F_SPEED_DEV`
(speed deviation) · `UT_F_CHANGEOVER` (changeover) · `UT_F_DRIVE_NOT_READY` (drive
not ready).
`<setting>` is one of: `UT_F_FLC` (full load current) · `UT_F_CURRENT_NEEDS_FLC`
(current needs FLC) · `UT_F_START_MASK` (start mask) · `UT_F_RESTART_DELAY` (restart
delay) · `UT_F_HAND_MAX_RUN` (hand max run) · a protection's name (its `delay`,
`recover` or `maxRetries`).
The variants add their own statuses and settings, listed in their docs.

## Invalid settings
An invalid or out-of-range setting never runs the motor unsafely. Either it falls
back to a safe value and warns (`Warning`, `wrnConfig`, `faultCode` bit 12 "Invalid
setting"), or the motor is kept off with a fault (`Fault`, `wrnConfig`, bit 12),
until the setting is fixed. Common to every motor block (warning, fallback):

| Setting | Invalid | Fallback |
| --- | --- | --- |
| `fullLoadCurrent` | negative, NaN, infinite | Current monitoring off |
| `currentHigh` / `currentLow` | not OFF while `fullLoadCurrent` is 0 or invalid | They cannot act (no FLC) |
| `currentStartMask`, `restartDelay`, `retryWindow` | negative | 0 (`retryWindow` 0 = no window) |
| `handMaxRun` | negative | No limit |
| Any protection in use | negative `delay` / `recover`; negative `maxRetries` with RETRY | 0: acts at once; latches on the first trip |
| A level in use (`currentHigh`, `currentLow`, a VSD's `speedDev`) | `sp` NaN or infinite; `deadband` negative, NaN or infinite | The value cannot raise it; deadband 0 |

The variants add their own: [REV](UT_MOTOR_REV.md) and [2SPD](UT_MOTOR_2SPD.md)
negative dead times (warning), [SD](UT_MOTOR_SD.md) `starTime` 0 or negative (kept
off), [VSD](UT_MOTOR_VSD.md#invalid-settings) speed limits and raw scaling (kept off)
and its other settings (warning).

## Using it
```iecst
M1(AutoCmd := Pump1.RunCmd, Feedback := P1_Aux, Overload := P1_OL,
   Interlock := Pump1.Healthy, Permissive := P1Starts.StartPermit, Data := Motor1);
P1_Contactor := M1.Run;
```
