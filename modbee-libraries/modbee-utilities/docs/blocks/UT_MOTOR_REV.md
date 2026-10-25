# UT_MOTOR_REV — Reversing starter

A forward and a reverse contactor that are never on together, with a dead time
(`reversalDelay`) so the motor stops before it changes direction. Everything else
(modes, interlocks, protection, faults, restart rules) is the same as
[UT_MOTOR](UT_MOTOR.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoCmd` | BOOL | FALSE | Run request from your logic (Auto) |
| in | `AutoReverse` | BOOL | FALSE | Direction in Auto: FALSE = forward, TRUE = reverse |
| in | `FeedbackFwd` | BOOL | FALSE | Forward contactor aux |
| in | `FeedbackRev` | BOOL | FALSE | Reverse contactor aux |
| in | `Overload` | BOOL | FALSE | Overload relay tripped (TRUE = tripped; a NC aux through NOT at the pin) |
| in | `Thermistor` | BOOL | FALSE | PTC relay / thermal switch tripped (a NC contact through NOT at the pin) |
| in | `DriveFault` | BOOL | FALSE | Soft-starter fault relay |
| in | `Current` | REAL | 0.0 | Motor current in amps (used if `fullLoadCurrent` > 0) |
| in | `Interlock` | BOOL | TRUE | FALSE **stops** the motor in every mode |
| in | `Permissive` | BOOL | TRUE | FALSE **blocks starting** only |
| in | `SwHand` / `SwAuto` | BOOL | FALSE | Selector switch (if `modeSource` uses it) |
| in | `LocalFwd` | BOOL | FALSE | Local forward pushbutton (Hand): runs it forward |
| in | `LocalRev` | BOOL | FALSE | Local reverse pushbutton (Hand): runs it in reverse |
| in | `LocalStop` | BOOL | FALSE | Local stop pushbutton (TRUE = pressed; a NC button through NOT at the pin) |
| in | `Reset` | BOOL | FALSE | Reset for MANUAL protections (rising edge) |
| out | `RunFwd` | BOOL | | Forward contactor |
| out | `RunRev` | BOOL | | Reverse contactor (never on with `RunFwd`) |
| out | `Running` | BOOL | | Run confirmed by feedback (stays on through a reversal) |
| out | `Fault` | BOOL | | A trip is holding it off |
| out | `Warning` | BOOL | | A protection set to warn is active |
| out | `Ready` | BOOL | | Would start now if asked: healthy, permitted, in Auto or Hand, not waiting out `restartDelay` (stays TRUE while running) |
| out | `Auto` | BOOL | | In Auto mode |
| out | `State` | UT_STATE | | For HMIs |
| out | `Reversed` | BOOL | | Running in reverse |
| inout | `Data` | UT_MOTOR_DATA | | Shared motor record ([UT_MOTOR](UT_MOTOR.md#record-ut_motor_data-shared-by-every-ut_motor-block)) |
| inout | `Rev` | UT_MOTOR_REV_DATA | | The reversing settings, commands and status (below) |

Always wire the contactors' NC auxiliaries as a hardware interlock as well. The
block never turns both on, but only the wiring stops a welded contactor.

## Record `UT_MOTOR_REV_DATA` (pin `Rev`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `reversalDelay` | TIME | T#2s | Dead time between one direction switching off and the other switching on (negative: 0 is used, with a config warning `wrnConfig`) |
| `changeover` | UT_PROTECTION | TRIP · 0 · MANUAL | Contactor feedback wrong for the sequence (`faultCode` bit 9, below) |
| `cmdFwd` / `cmdRev` | BOOL | FALSE | Hand: run forward / run in reverse (each acts once, on its rising edge, then cleared: one held TRUE acts once) |
| `reverse` (status) | BOOL | | The reverse contactor is on |

Everything else (modes, protections, `cmdStart` / `cmdStop`, status) is in the motor
record `Data`.

## How it works
- **Direction.** Auto: `AutoReverse`. Hand: `cmdFwd` / `LocalFwd` run it forward,
  `cmdRev` / `LocalRev` run it in reverse; each starts it as well. `cmdStart` starts
  it in the direction chosen last. Forward and reverse pressed together do nothing.
  The direction commands are ignored (and cleared) in Off and Auto. Switching
  Auto → Hand keeps the direction it was running in.
- **Changing direction while running:** the running contactor goes off at once, the
  dead time runs, then the other contactor comes on. The motor stays requested the
  whole time, so `Running` stays on, a permissive does not stop it, and the restart
  delay does not apply. If the request goes back to the old direction during the dead
  time, that contactor comes straight back on.
- **Starting after a stop:** the same direction starts at once; the other direction
  waits until `reversalDelay` has passed since the last contactor went off (the motor
  may still be turning).
- **After a power-up** either direction waits `reversalDelay` first, because the motor
  may still be turning.
- **With feedback supervised** (`useFeedback`, not in `simulate`), the new direction
  also waits until the other contactor's aux shows open. With `reversalDelay = T#0s`
  there is still at least one scan with both off, and the new direction waits for the
  old contactor to drop out.
- **Changeover protection** (`changeover`, bit 9, TRIP · MANUAL by default) trips when
  both auxes show closed, when the aux of the direction that is off shows closed while
  the other direction is on, or when a contactor switched off for a reversal still
  shows closed after `stuck.delay` (the new direction is never switched on into it).
  A contact that stays closed at standstill is the welded-contactor protection
  (`stuck`), as on UT_MOTOR.
- If the new direction's aux does not confirm after a reversal, `feedbackLost`
  trips; if the motor never had feedback, `noFeedback` does.

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
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | *(this block)* Changing direction (or starting the other way): both contactors off for `reversalDelay`; `timeLeft` counts down |
| `UT_ST_WAIT_OPEN` | `Waiting: contactor to open` | *(this block)* The other direction's contactor aux still shows closed |
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
This block adds the setting `UT_F_REVERSAL_DELAY` (reversal delay, negative) and uses `UT_F_CHANGEOVER` for its `changeover` protection.
The rows marked *(this block)* come from its own sequence and show from the scan after it changes.

## Using it
```iecst
Conv1(AutoCmd := Line.Run, AutoReverse := Line.Back, FeedbackFwd := K1_Aux, FeedbackRev := K2_Aux,
      Overload := Conv1_OL, LocalFwd := PB_Fwd, LocalRev := PB_Rev, LocalStop := PB_Stop, Data := Conv1Data,
      Rev := Conv1Rev);
K1 := Conv1.RunFwd;
K2 := Conv1.RunRev;
```
