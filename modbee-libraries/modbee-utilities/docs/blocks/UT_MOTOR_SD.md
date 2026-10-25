# UT_MOTOR_SD — Star-delta starter

Main, star and delta contactors with a timed (or current-confirmed) star stage and
an open-transition dead time, so star and delta are never on together. Modes,
interlocks, protection, faults and restart rules are as [UT_MOTOR](UT_MOTOR.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoCmd` | BOOL | FALSE | Run request from your logic (Auto) |
| in | `FeedbackMain` | BOOL | FALSE | Main contactor aux (the run feedback) |
| in | `FeedbackStar` | BOOL | FALSE | Star contactor aux (only used with `useStarDeltaFb`) |
| in | `FeedbackDelta` | BOOL | FALSE | Delta contactor aux (only used with `useStarDeltaFb`) |
| in | `Overload` | BOOL | FALSE | Overload relay tripped (TRUE = tripped; a NC aux through NOT at the pin) |
| in | `Thermistor` | BOOL | FALSE | PTC relay / thermal switch tripped (a NC contact through NOT at the pin) |
| in | `Current` | REAL | 0.0 | Motor current in amps (used if `fullLoadCurrent` > 0) |
| in | `Interlock` | BOOL | TRUE | FALSE **stops** the motor in every mode |
| in | `Permissive` | BOOL | TRUE | FALSE **blocks starting** only |
| in | `SwHand` / `SwAuto` | BOOL | FALSE | Selector switch (if `modeSource` uses it) |
| in | `LocalStart` | BOOL | FALSE | Local start pushbutton (Hand) |
| in | `LocalStop` | BOOL | FALSE | Local stop pushbutton (TRUE = pressed; a NC button through NOT at the pin) |
| in | `Reset` | BOOL | FALSE | Reset for MANUAL protections (rising edge) |
| out | `Main` | BOOL | | Main contactor |
| out | `Star` | BOOL | | Star contactor (never on with `Delta`) |
| out | `Delta` | BOOL | | Delta contactor |
| out | `Running` | BOOL | | Run confirmed by the main feedback |
| out | `Fault` | BOOL | | A trip is holding it off |
| out | `Warning` | BOOL | | A protection set to warn is active |
| out | `Ready` | BOOL | | Would start now if asked: healthy, permitted, in Auto or Hand, not waiting out `restartDelay` (stays TRUE while running) |
| out | `Auto` | BOOL | | In Auto mode |
| out | `State` | UT_STATE | | For HMIs |
| inout | `Data` | UT_MOTOR_DATA | | Shared motor record ([UT_MOTOR](UT_MOTOR.md#record-ut_motor_data-shared-by-every-ut_motor-block)) |
| inout | `Sd` | UT_MOTOR_SD_DATA | | The star-delta settings and status (below) |

Always wire the star and delta contactors' NC auxiliaries as a hardware interlock as
well. The block never turns both on, but only the wiring stops a welded contactor.

## Record `UT_MOTOR_SD_DATA` (pin `Sd`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `starTime` | TIME | T#6s | Time in star. Zero or negative is refused (see below) |
| `starCurrentPct` | REAL | 0.0 | If > 0 and `fullLoadCurrent` > 0: change to delta early once the current has risen to this % of FLC and fallen below it again (never later than `starTime`) |
| `transitionTime` | TIME | T#60ms | Open-transition dead time between star and delta (both ways) |
| `useStarDeltaFb` | BOOL | FALSE | Supervise the star / delta aux contacts |
| `changeover` | UT_PROTECTION | TRIP · 0 · MANUAL | Star / delta feedback wrong for the sequence (`faultCode` bit 9, below) |
| `inStar` (status) | BOOL | | The star contactor is on |

Everything else (modes, protections, commands, status) is in the motor record `Data`.

## How it works
- **Sequence:** star and main together → `starTime` (or the early change on
  current) → star off → `transitionTime` → delta. Main stays on throughout, so
  `Running` and the run-feedback protections follow the main contactor.
- **Main confirmed first:** with `useFeedback` the change to delta waits until the
  main contactor's feedback is in: star is held past `starTime`, and delta is held
  off in the transition, while main is not confirmed. If main never confirms,
  `noFeedback` acts; if it drops, `feedbackLost` acts. Delta never comes on with
  main unconfirmed. In `simulate` the simulated feedback confirms it; without
  `useFeedback` there is no wait.
- **Invalid settings:** `starTime` zero or negative would start the motor straight
  in delta, so the motor is kept off with a fault (`wrnConfig`, `faultCode` bit 12
  "Invalid setting"). A negative `transitionTime` (0 is used), and a `starCurrentPct`
  that is negative, not a number, or set without a valid `fullLoadCurrent` (only
  `starTime` is used) warn (`Warning`, `wrnConfig`) and the motor runs.
- **The early change on current** needs the current to have reached
  `starCurrentPct` first, so the zero reading before the contactors make is not taken
  as "up to speed". NaN or no `fullLoadCurrent`: the star time is used.
- **Stopping** at any point (stop, interlock, trip, Off, OOS) turns all three off at
  once. A start again goes into star, with a full star time. Star never comes on
  within `transitionTime` of delta going off, so a quick restart after running in
  delta waits for the dead time (the core is held, so no feedback fault is counted).
- **After a power-up** the first start waits `transitionTime`.
- **With `useStarDeltaFb`** (not in `simulate`): delta waits for the star aux to show
  open, and a start waits for the delta aux to show open. The **changeover
  protection** (`changeover`, bit 9, TRIP · MANUAL by default) trips when star and
  delta both show closed; when delta shows closed in star, or star shows closed in
  delta; when star or delta still shows closed `stuck.delay` after it went off (a
  welded contactor: delta is withheld, main stays on alone until the trip); or when
  the star or delta aux has not confirmed `noFeedback.delay` after its contactor came
  on.
- **Always a gap:** there is always at least one scan with neither star nor delta
  on, even with `transitionTime` at 0.

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
| `UT_ST_STAR` | `Starting: star` | *(this block)* In star; `timeLeft` is the star time left (it may change to delta earlier on current) |
| `UT_ST_RESTART_DELAY` | `Waiting: restart delay` | Asked to run, `restartDelay` not over yet (`timeLeft` counts down) |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE (every mode but OOS) |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | `Permissive` FALSE while stopped, in Hand or Auto |
| `UT_ST_HAND_PRESS_START` | `Hand: press start` | Hand and stopped: no start given, or it was dropped (a stop, a trip, the interlock, not permitted) |
| `UT_ST_WAIT_GROUP` | `Waiting: turn in group` | A group owns it and does not run it now |
| `UT_ST_HAND_MAX_RUN` | `Hand: max run, press start` | `handMaxRun` ended the Hand run |
| `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | After a MANUAL reset, or a local stop in Auto: `AutoCmd` must go off and on |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | *(this block)* The open transition (star off, delta not yet on), or delta's dead time before star; `timeLeft` counts down |
| `UT_ST_WAIT_MAIN_FB` | `Waiting: main contactor` | *(this block)* Star time is over, but the main contactor is not confirmed closed: delta waits (`noFeedback` trips if it never comes) |
| `UT_ST_WAIT_OPEN` | `Waiting: contactor to open` | *(this block)* With `useStarDeltaFb`: the star or delta aux still shows closed |
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
This block adds the settings `UT_F_TRANSITION_TIME` (transition time) · `UT_F_STAR_CURRENT` (star current %) · `UT_F_STAR_NEEDS_FLC` (star % needs FLC) · `UT_F_STAR_TIME` (star time, zero or negative: `UT_ST_CONFIG`, kept off), and uses `UT_F_CHANGEOVER` for its `changeover` protection.
The rows marked *(this block)* come from its own sequence and show from the scan after it changes.

## Using it
```iecst
Crusher(AutoCmd := Seq.Run3, FeedbackMain := KM_Aux, FeedbackStar := KY_Aux, FeedbackDelta := KD_Aux,
        Overload := Crusher_OL, Current := Crusher_Amps, Interlock := PullCord.Healthy, Data := CrusherData,
        Sd := CrusherSd);
KM := Crusher.Main;
KY := Crusher.Star;
KD := Crusher.Delta;
```
