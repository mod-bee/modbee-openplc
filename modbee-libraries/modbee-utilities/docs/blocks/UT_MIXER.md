# UT_MIXER — Stirrer / agitator / mixer

Decides when a stirrer, agitator or mixer runs: before the pump starts (and holds
the pump until it has mixed), with the pump, for a while after the pump stops, and
on a timed on/off cycle in between. A mixer that can't run never holds the pump: a
broken mixer must never cause an overflow.

It sits on top of a motor block: `Run` → the mixer motor's `AutoCmd`. The motor
block owns Hand/Off/Auto and the electrical protection. `StartHold` goes to the
pump's `StartHold` ([UT_PUMP](UT_PUMP.md)).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | FALSE | The mixer logic works, e.g. the system is not Off. FALSE: `Run` off, the pump is never held |
| in | `Cycle` | BOOL | TRUE | The timed on/off cycle may run, e.g. the system is in Auto. `Data.cycle` switches it too |
| in | `PumpCall` | BOOL | FALSE | The pump is asked to start: the signal into the pump's `Demand`. Its rising edge starts the pre-run |
| in | `PumpRunning` | BOOL | FALSE | The pump runs (the pump motor's `Running`). The mixer runs with it; when it stops, the post-run starts |
| in | `StartNow` | BOOL | FALSE | While TRUE: run now, whatever the timers, and never hold the pump. E.g. a high level, or emptying the tank |
| in | `LevelOk` | BOOL | TRUE | The level is at or above the mixer's minimum (a float made). FALSE stops the mixer, holds the cycle clock and never holds the pump |
| in | `MixerReady` | BOOL | TRUE | The mixer motor can run on request: wire the motor's `Auto AND NOT Fault` |
| in | `MixerRunning` | BOOL | FALSE | The mixer motor runs: wire the motor's `Running`. The pre-run counts from it |
| out | `Run` | BOOL | | Run the mixer → the mixer motor's `AutoCmd` |
| out | `StartHold` | BOOL | | TRUE: the pump must wait, the pre-run is running → the pump's `StartHold` |
| out | `Warning` | BOOL | | The pump was let go without a full pre-run (the mixer is not ready, or did not run). On until `PumpCall` ends |
| inout | `Data` | UT_MIXER_DATA | | Settings and status |

## Using it
```iecst
Mixer(Enable := NOT SystemOff, Cycle := SystemAuto, PumpCall := SumpHigh,
      PumpRunning := M1.Running, StartNow := SumpHighHigh, LevelOk := MixerMinFloat,
      MixerReady := MX.Auto AND NOT MX.Fault, MixerRunning := MX.Running, Data := MixerData);
MX(AutoCmd := Mixer.Run, Feedback := MX_Aux, Overload := MX_OL, Data := MixerMotor);

Pump1(Demand := SumpHigh, Running := M1.Running, MotorReady := M1.Ready, MotorAuto := M1.Auto,
      StartHold := Mixer.StartHold, Data := Pump1Data);
M1(AutoCmd := Pump1.RunCmd, Feedback := M1_Aux, Overload := M1_OL,
   Interlock := Pump1.Healthy, Data := Motor1);
```

## Record `UT_MIXER_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `cycle` | BOOL | TRUE | Use the timed on/off cycle (also needs the `Cycle` pin) |
| `onTime` | TIME | T#5m | Cycle: run this long… |
| `offTime` | TIME | T#1h | …then rest this long. The cycle starts with the rest |
| `preRun` | BOOL | TRUE | Run before the pump starts, holding the pump |
| `preRunTime` | TIME | T#2m | How long the mixer must have run before the pump may start. `T#0s` = no pre-run |
| `postRun` | BOOL | TRUE | Run on after the pump stops |
| `postRunTime` | TIME | T#30s | How long. `T#0s` = no post-run. Counted only while the level is OK: held while it is low, like the cycle |
| `withPump` | BOOL | TRUE | Run whenever the pump runs |
| `statusCode` | UT_STATUS | | Status: what it is doing, or what holds it back (below) |
| `faultId` | UT_FAULT | | Status: the warning or setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | Status: the two in words |
| `timeLeft` | TIME | | Status: the pre-run, post-run or cycle phase still to go (0 = none) |

There are no HMI commands. `timeLeft` shows:
- during the pre-run: `preRunTime` less the time the mixer has run so far (the full
  time until the mixer is seen running);
- during the post-run: the post-run left (0 while `StartNow` is on);
- while the cycle is in use and nothing else runs the mixer: the on or rest time left
  (held while `LevelOk` is FALSE);
- otherwise 0.

## Status
The one main thing, in the order below (top first). The numbers are in
[conventions](../conventions.md#the-numbers).

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OFF` | | `Off` | `Enable` is FALSE |
| `UT_ST_WARNING` | `UT_F_NO_PRE_RUN` | `Warning: no pre-run` | The pump was let go without its pre-run (until `PumpCall` ends) |
| `UT_ST_WARN_SETTING` | `UT_F_TIMED_ON_OFF` | `Setting: timed on / off time` | `cycle` is on, with `onTime` or `offTime` 0 or negative: no cycle |
| `UT_ST_WARN_SETTING` | `UT_F_PRE_POST_RUN` | `Setting: pre/post-run time` | A negative `preRunTime` (with `preRun`) or `postRunTime` (with `postRun`): that run is not used |
| `UT_ST_STOPPED_LOW` | | `Stopped: low level` | It should run, but `LevelOk` is FALSE |
| `UT_ST_MOTOR_NOT_READY` | | `Blocked: motor not ready` | It should run, but `MixerReady` is FALSE (`Run` stays on; the motor's own status says why) |
| `UT_ST_PRE_RUN` | | `Running: pre-run` | Holding the pump for the pre-run (`timeLeft`); or the pre-run is done and `PumpCall` is still on, with nothing below running it (the pump starting) |
| `UT_ST_RUN_WITH_PUMP` | | `Running: with pump` | The pump runs (`withPump`) |
| `UT_ST_RUN_DEMAND` | | `Running: demand` | `StartNow` |
| `UT_ST_POST_RUN` | | `Running: post-run` | After the pump stopped (`timeLeft`) |
| `UT_ST_RUN_TIMED` | | `Running: timed` | The cycle's on time (`timeLeft`) |
| `UT_ST_TIMED_REST` | | `Waiting: timed rest` | The cycle's rest (`timeLeft`) |
| `UT_ST_IDLE` | | `Idle` | Nothing to do (no cycle) |

## How it works
`Run` is on, while `LevelOk` is TRUE and `Enable` is on, for any of these:

1. **Pre-run.** `PumpCall` comes on: `Run` comes on and `StartHold` holds the pump
   until the mixer has run `preRunTime` (default 2 min). The time counts from the
   mixer's `MixerRunning`, so the motor's restart delay and contactor time don't
   count. Time the mixer had already been running (say, in its cycle) counts. If
   `PumpCall` goes before the pump starts, the pre-run stops.
2. **After the pre-run** the mixer keeps running for as long as `PumpCall` stays on,
   also while the pump starts and runs. (So with a pre-run, `withPump` FALSE does
   not stop the mixer while the pump is called.)
3. **With the pump**: while `PumpRunning` (`withPump`, default on).
4. **Post-run**: for `postRunTime` (default 30 s) after the pump stops. A pump that
   starts again ends it.
5. **Start now**: while `StartNow` is on.
6. **Cycle**: rest for `offTime` (default 1 h), then run for `onTime` (default 5 min),
   over and over, starting with the rest. Any other run holds the cycle at the start
   of its rest, so the rest starts again when that run ends: the tank was just
   mixed. `LevelOk` FALSE holds the cycle clock where it is.

`preRun`, `postRun`, `withPump` and `cycle` switch each one on or off.

**The pump is never held for a mixer that can't run.** `StartHold` lets the pump go:
- at once, with no warning, when there is no pre-run (`preRun` off or
  `preRunTime` 0), `StartNow` is on, `LevelOk` is FALSE or the pump already runs;
- at once, **with** `Warning`, when `MixerReady` is FALSE (the mixer motor is not in
  Auto, or has tripped);
- with `Warning`, `preRunTime` + 1 min after `PumpCall` came on, if the mixer still
  has not run its pre-run (it never started, or it stopped). The 1 min is fixed.

Once let go, the pump stays let go until `PumpCall` ends. `Warning` stays on until
then too. Without a full pre-run the mixer does not run on the call itself, only
with the pump.

`MixerReady` only decides whether to hold the pump; it does not switch `Run` off.
The motor block refuses to run a motor that is not ready.

### Invalid settings
- `cycle` on with `onTime` or `offTime` 0 or negative: no cycle,
  `Setting: timed on / off time`.
- A negative `preRunTime` (with `preRun` on) or `postRunTime` (with `postRun` on):
  that run is not used (no pre-run means the pump is not held),
  `Setting: pre/post-run time`.
- A bad setting does not set the `Warning` pin.

### Power cut
Nothing is kept: the cycle starts again with its rest, and a pump call after the
power cut starts a new pre-run.
