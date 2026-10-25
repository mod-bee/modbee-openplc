# UT_MOTOR_VSD — Variable speed drive

Runs a VSD/VFD over hard-wired I/O (run, running, ready and fault relays, speed
reference and feedback). It adds speed limits, ramps, a skip band, a hand speed,
speed-deviation supervision and a drive-reset pulse. Modes, interlocks and the
common protections are as [UT_MOTOR](UT_MOTOR.md) (it is
[UT_MOTOR_CORE](UT_MOTOR_CORE.md) and a speed reference).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoCmd` | BOOL | FALSE | Run request (Auto) |
| in | `AutoSpeed` | REAL | 100.0 | Speed request in Auto, % (e.g. from `PID`) |
| in | `Feedback` | BOOL | FALSE | Drive "running" relay |
| in | `DriveReady` | BOOL | TRUE | Drive "ready" relay: FALSE blocks a start; lost while running, see `driveNotReady`. Unwired = not used |
| in | `DriveFault` | BOOL | FALSE | Drive fault relay |
| in | `SpeedFb` | REAL | -1.0 | Actual speed % (−1 = not wired: deviation check off) |
| in | `Thermistor`, `Current`, `Interlock`, `Permissive`, `SwHand`, `SwAuto`, `LocalStart`, `LocalStop`, `Reset` | | | As UT_MOTOR (TRUE = active; a NC contact through NOT at the pin) |
| out | `Run` | BOOL | | Drive run command |
| out | `SpeedRef` | REAL | | Speed reference %, after the clamp, skip band and ramp (0 when stopped) |
| out | `SpeedRefRaw` | UINT | | `SpeedRef` scaled to `rawMin..rawMax`, for `%QW` |
| out | `DriveReset` | BOOL | | Pulse to the drive's reset input |
| out | `Running`, `Fault`, `Warning`, `Auto`, `State` | | | As UT_MOTOR |
| out | `Ready` | BOOL | | As UT_MOTOR, and the drive is ready |
| out | `AtSpeed` | BOOL | | Running at the reference (see below) |
| inout | `Data` | UT_MOTOR_DATA | | Shared motor record ([UT_MOTOR](UT_MOTOR.md#record-ut_motor_data-shared-by-every-ut_motor-block)) |
| inout | `Vsd` | UT_MOTOR_VSD_DATA | | The drive's settings, protections and status (below) |

## Record `UT_MOTOR_VSD_DATA` (pin `Vsd`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `minSpeed` / `maxSpeed` | REAL | 0.0 / 100.0 | Clamp, in %. Pumps usually need a minimum (e.g. 30). Held to 0..100 (see [Invalid settings](#invalid-settings)) |
| `accelRate` / `decelRate` | REAL | 0.0 / 0.0 | Ramp on the reference, in % per `rateUnit` (0 = no ramp here, let the drive ramp) |
| `rateUnit` | UT_RATE_UNIT | UT_PER_SEC | Time unit of `accelRate` / `decelRate`: `UT_PER_SEC` (0, % per second) or `UT_PER_MIN` (% per minute); `UT_PER_HOUR` and `UT_PER_DAY` work too |
| `skipLow` / `skipHigh` | REAL | 0.0 / 0.0 | Resonance skip band (off while `skipHigh` ≤ `skipLow`) |
| `handSpeed` | REAL | 50.0 | Speed used in Hand (HMI-adjustable) |
| `rawMin` / `rawMax` | REAL | 0.0 / 65535.0 | `SpeedRefRaw` at 0 % and 100 % (either way round, e.g. 0 / 27648; each in 0..65535, not equal) |
| `resetPulse` | TIME | T#500ms | Length of the `DriveReset` pulse (0 = one scan) |
| `ratedHz` / `ratedRpm` | REAL | 0.0 / 0.0 | The motor's frequency and speed at 100 % (nameplate, e.g. 50 Hz, 1460 rpm), for `speedHz` / `speedRpm`. 0 = not worked out; negative, NaN or infinite: a warning (`rated Hz / rpm`), not worked out |
| `speedHz` / `speedRpm` (status) | REAL | | The speed in Hz / rpm: from `SpeedFb` when wired, else the reference (0 when not set up) |
| `speedRef` / `speedFb` (status) | REAL | | The reference and the feedback |

The deviation limit and time are the `speedDev` protection's own `sp` and `delay`.

### Also used in the motor record `Data`
| Field | Type | Meaning |
| --- | --- | --- |
| `isVsd` (status) | BOOL | TRUE, set every scan: a group knows this pump has a speed |
| `grpSpeed` (group) | REAL | Written by a [UT_PUMP_CASCADE](UT_PUMP_CASCADE.md): the Auto speed while the group owns the record |

### Protections (bits as UT_MOTOR)
`drive` is in `Data`; `speedDev` and `driveNotReady` are in `Vsd`:
| Field | Bit | Default response · delay · reset | Raised when |
| --- | --- | --- | --- |
| `drive` | 7 | TRIP · 0 · AUTO | `DriveFault` is on. A drive that resets itself returns to service |
| `speedDev` | 8 | WARN · 10 s · AUTO · sp 10 % (`UT_LEVEL`) | Feedback more than `sp` % off the reference for `delay`, while running and with `SpeedFb` wired |
| `driveNotReady` | 10 | WARN · 0 · AUTO | `DriveReady` went FALSE while running. OFF ignores it; WARN warns and keeps running; TRIP stops the drive. It stays raised while `DriveReady` stays FALSE (also after the drive has stopped), and clears `recover` after it is back |

The overload is inside the drive, so there's no `Overload` pin. The other
protections are UT_MOTOR's.

## How it works
- **The reference.** Hand → `handSpeed`, Auto → `AutoSpeed`, or `grpSpeed` while a
  group ([UT_PUMP_CASCADE](UT_PUMP_CASCADE.md)) owns the record (`grpActive`, set by the
  group every scan); a drive no group owns never looks at `grpSpeed`. Clamped to
  `minSpeed..maxSpeed`, then kept out of the skip band, then ramped. A start begins
  from `minSpeed`; when the drive is stopped (Off, interlock, fault…) the reference is 0.
  A request that is not a number (NaN, infinity) keeps the last good one.
- **Skip band.** The reference is never inside `skipLow..skipHigh` (the edges
  themselves are allowed). A request inside the band holds at the edge on the side
  the reference is coming from; a ramp crossing the band jumps over it. If
  `minSpeed` is inside the band, the drive starts at `skipHigh`.
- **Ramps** use real elapsed time, so they take the same time at any scan rate.
  A lowered `maxSpeed` takes effect at once. The rate is in % of full speed per
  second, or per minute with `rateUnit := UT_PER_MIN`: `accelRate := 10.0` is
  0 → 100 % in 10 s per second, or in 10 min per minute. To copy a drive's
  "0 to full speed in 20 s" ramp, use 5 %/s (`accelRate := 5.0`) or
  300 %/min (`accelRate := 300.0, rateUnit := UT_PER_MIN`).
- **`SpeedRefRaw`** = `rawMin + SpeedRef / 100 × (rawMax − rawMin)`, rounded, held to 0..65535.
- **`DriveReady`** FALSE blocks a start (`Ready` is FALSE). Lost while running, it
  raises `driveNotReady`, which by default warns and keeps the drive running; set
  it to TRIP to stop the drive.
- **In simulation** (`simulate`) the drive fault and `driveNotReady` still act; the
  speed feedback is taken as the reference, so `speedDev` does not act.
- **`DriveReset`** pulses for `resetPulse` when a fault is reset (pin, `cmdReset`,
  or switching to Off), and also when a reset is asked for while `DriveFault` is
  still on: most drives hold their fault relay until they get the pulse. One reset
  request gives one pulse: a `cmdReset` held TRUE (or a `Reset` pin held on) gives
  one pulse and resets once.
- **`AtSpeed`**: with `SpeedFb` wired, running and within `speedDev.sp` of the
  reference; without it, running and the ramp has reached its target.

## Wiring the drive's relays
| The drive has | Wire | Settings |
| --- | --- | --- |
| A "ready" relay and a fault relay | `DriveReady` and `DriveFault` | Defaults: a fault trips; ready lost while running warns (`driveNotReady` WARN). Set `Vsd.driveNotReady.response := UT_RESP_TRIP` to stop on it |
| Only a fault relay (one "healthy/fault" output) | It to `DriveFault` (TRUE = fault; a contact that opens on a fault through NOT). Leave `DriveReady` unwired | None: `DriveReady` defaults to TRUE and is not used |
| Only a "ready" relay | It to `DriveReady`; leave `DriveFault` unwired | Set `Vsd.driveNotReady.response := UT_RESP_TRIP`, so losing it while running stops the drive |

## Invalid settings
A setting that would run the drive unsafely keeps it off with a fault: `Fault`,
`wrnConfig` and `faultCode` bit 12 "Invalid setting". That is `minSpeed` above
`maxSpeed`, `minSpeed` above 100, `maxSpeed` below 0, either one not a number, and
`rawMin` / `rawMax` not numbers, outside 0..65535 or equal. Fix the setting and the
drive is back in service (in Auto at once; in Hand press start again).

Other invalid settings fall back and warn (`Warning`, `wrnConfig`, bit 12), and
the drive runs: `minSpeed` below 0 (0 is used), `maxSpeed` above 100 (100),
`accelRate` / `decelRate` negative or not a number, or an unknown `rateUnit` (no
ramp here: the drive's own ramp), a skip band not a number or with `skipLow` above `skipHigh` (off),
`handSpeed` not a number (the last good request), a negative `resetPulse` (one
scan), `ratedHz` / `ratedRpm` negative, NaN or infinite (`speedHz` / `speedRpm` 0). The common settings are checked as in [UT_MOTOR](UT_MOTOR.md#invalid-settings).

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
| `UT_ST_SKIP_EDGE` | `Running: at skip band edge` | *(this block)* The speed asked for is inside the skip band: the reference holds at its edge |
| `UT_ST_RESTART_DELAY` | `Waiting: restart delay` | Asked to run, `restartDelay` not over yet (`timeLeft` counts down) |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE (every mode but OOS) |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | `Permissive` FALSE while stopped, in Hand or Auto |
| `UT_ST_HAND_PRESS_START` | `Hand: press start` | Hand and stopped: no start given, or it was dropped (a stop, a trip, the interlock, not permitted) |
| `UT_ST_WAIT_GROUP` | `Waiting: turn in group` | A group owns it and does not run it now |
| `UT_ST_HAND_MAX_RUN` | `Hand: max run, press start` | `handMaxRun` ended the Hand run |
| `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | After a MANUAL reset, or a local stop in Auto: `AutoCmd` must go off and on |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_DRIVE_NOT_READY` | `Blocked: drive not ready` | *(this block)* `DriveReady` FALSE while stopped, in Hand or Auto (asked to run or not). Lost while running it is the `driveNotReady` protection: `Warning: drive not ready` (WARN) or a fault (TRIP) |
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
This block adds the settings `UT_F_MIN_MAX_SPEED` (min / max speed) · `UT_F_RAW_MIN_MAX` (raw min / max) (`UT_ST_CONFIG` when they keep it off) · `UT_F_ACCEL_RATE` (accel / decel rate) · `UT_F_SKIP_BAND` (skip band) · `UT_F_HAND_SPEED` (hand speed) · `UT_F_RESET_PULSE` (reset pulse) · `UT_F_RATE_UNIT` (rate unit) · `UT_F_RATED_HZ_RPM` (rated Hz / rpm), and uses `UT_F_SPEED_DEV` and `UT_F_DRIVE_NOT_READY` for its own protections.
The rows marked *(this block)* come from its own sequence and show from the scan after it changes.

## Using it
```iecst
P1(AutoCmd := Station.Run1, AutoSpeed := PressurePID.XOUT, Feedback := P1_Running,
   DriveReady := P1_Ready, DriveFault := P1_Fault, SpeedFb := P1_SpeedPct, Data := Pump1Drive,
   Vsd := Pump1Vsd);
P1_RunRelay := P1.Run;
P1_SpeedAO := P1.SpeedRefRaw;
P1_ResetRelay := P1.DriveReset;
```
