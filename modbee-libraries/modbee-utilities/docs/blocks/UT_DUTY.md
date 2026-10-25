# UT_DUTY — Duty / assist / standby for any group of motors

Shares a demand ("I need N units running") across a group of motor-driven units:
fans, compressors, blowers, heater banks, cooling towers, or pumps when you
don't need [UT_PUMP_STATION](UT_PUMP_STATION.md)'s level logic. It handles rotation,
failover, staggered starts and exercise of idle units.

The group is an **array of the units' motor records**. Each `UT_MOTOR*` block uses
one element as its `Data`, and its Auto command comes from the group automatically
(`grpActive` / `grpRun`). A unit is available when it is in Auto and ready (healthy,
interlock and permissive made).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Required` | INT | 1 | How many units should run (0 or negative = none) |
| in | `Rotate` | BOOL | FALSE | Rising edge: change the lead now |
| out | `RunningCount` | INT | | Units running (any mode) |
| out | `Shortfall` | BOOL | | Fewer available than `Required` |
| out | `Lead` | INT | | Array index of the lead unit |
| inout | `Units` | ARRAY[*] OF UT_MOTOR_DATA | | The motor records of the group (any size, any lower bound) |
| inout | `Data` | UT_DUTY_DATA | | Group record |

## Record `UT_DUTY_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `rotation` | UT_ROTATE_MODE | UT_ROT_EACH_START | FIXED · EACH_START (the lead moves on when the group goes to none) · HOURS (fewest run hours leads, decided when the group starts from none) · INTERVAL |
| `rotateInterval` | TIME | T#24h | INTERVAL (0 = never) |
| `fixedLead` | INT | 1 | FIXED: array index of the lead (out of range = the first) |
| `stageDelay` / `destageDelay` | TIME | T#5s / T#2s | Minimum gap between starts / stops |
| `failoverDelay` | TIME | T#10s | A called unit not running in this time is skipped, the next is called. A unit still in its own `restartDelay` hands over to another, and is called again when no other is left |
| `swapWhileRunning` | BOOL | FALSE | Rotate without stopping: start the new lead, then stop the old one. FALSE: the old one stops first |
| `countHandUnits` | BOOL | TRUE | A unit running in Hand counts toward `Required` |
| `exerciseInterval` / `exerciseTime` | TIME | T#0s / T#30s | Run idle units briefly (0 = off) |
| `cmdRotate` | BOOL | | HMI command: move the lead on now (acts once, cleared) |
| `lead`, `runningCount`, `calledCount`, `availableCount`, `shortfall`, `exercising` | | | Status |
| `statusCode` | UT_STATUS | | What the group is doing, or what holds it back (see [Status](#status)) |
| `faultId` | UT_FAULT | | The setting a configuration status is about (`UT_F_NO_UNITS`); else `UT_F_NONE` |
| `statusText` | STRING(30) | | The status in words, for a person looking at the PLC |
| `statusUnit` | DINT | | The unit (array index) the status is about; one below the array's first index when none |
| `rotateIn` | TIME | | *status*: INTERVAL: time to the next rotation (0 for the other rotations, or `rotateInterval` 0) |
| `nextExerciseIn` | TIME | | *status*: time until the next idle unit is exercised: the one idle longest (0 with exercise off, or while one is exercised) |
| `timeLeft` | TIME | | *status*: the countdown that goes with the status: stage, failover, destage or restart delay, or the exercise run still to go (0 = none) |

Each unit's rank is in `Units[i].grpRank` (1 = lead). Run time per unit for
`UT_ROT_HOURS` is counted by the group in `Units[i].grpRunTime`, for every unit.

### Status
`statusCode` and `statusText` say the **one main thing** the group is doing, or what
holds it back. The group has no faults of its own: each unit's motor status says why
it tripped. The most important reason wins: held / waiting > running > idle. With
`Required` above 0 and no unit running or starting (its run command out), the status
is always a held one. The unit a status is about is `statusUnit` (an array index),
the time left is in `timeLeft`, and the counts are `runningCount`, `calledCount` and
`availableCount`. The text is rebuilt only when the status changes. The numbers are
in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE_NO_DEMAND` | `Idle: no demand` | `Required` 0 (or less), nothing running |
| `UT_ST_RUN_HAND` | `Running: Hand` | Nothing wanted; units run in Hand |
| `UT_ST_STARTING` | `Starting` | Unit `statusUnit` called, not running yet; skipped if not running within `timeLeft` (the failover delay) |
| `UT_ST_STOPPING` | `Stopping` | More called than wanted: the next release after `destageDelay` (`timeLeft`); or a released unit running down |
| `UT_ST_RUNNING` | `Running` | Units running (any mode); `runningCount` of `Required` |
| `UT_ST_EXERCISING` | `Exercising` | Unit `statusUnit` is on an exercise run (`timeLeft`) |
| `UT_ST_RESTART_DELAY` | `Waiting: restart delay` | Unit `statusUnit` waits out its motor's `restartDelay` (`timeLeft`), or the group is short only because a unit is in its restart delay |
| `UT_ST_FAILOVER` | `Waiting: start failed, next` | A unit did not run (failover, or its motor tripped while starting); unit `statusUnit` is called instead |
| `UT_ST_STAGE_DELAY` | `Waiting: stage delay` | More units wanted, the next start after `stageDelay` (`timeLeft`) |
| `UT_ST_SHORTFALL` | `Shortfall: too few available` | Fewer units available (in Auto and ready, not skipped) or running in Hand than `Required`; `availableCount` says how many are |
| `UT_ST_CONFIG` | `Config: no units in array` | `faultId` `UT_F_NO_UNITS`: an empty array |

## How it works
- Units are called one at a time, best rank first, at least `stageDelay` apart and
  only once the last one called is running. Extra units are released one at a time,
  worst rank first, at least `destageDelay` apart.
- A unit that trips or leaves Auto (Hand, Off, OOS) is released at once and replaced.
  A called unit that does not run within `failoverDelay` is skipped until it has been
  unavailable or the group next starts from none (skip memory: first 32 units). A
  unit coming back is not swapped in while another is doing the job. A unit that is
  only waiting out its own `restartDelay` (just stopped, or after a power cut) has not
  failed: it hands over to another unit if there is one, and is called again once no
  other is left, so a lone compressor restarts when its delay ends.
- Exercise: one idle, available unit at a time (any unit in the array) whose motor has
  been stopped for `exerciseInterval` (its `offTime`) runs `exerciseTime`. It does not count toward `Required`, only
  touches units in Auto, and counts as a start for `stageDelay`. `nextExerciseIn`
  shows when the next one is due.
- `rotateIn` counts down to the next INTERVAL rotation and starts again at each
  rotation (also one by `Rotate` / `cmdRotate`).
- **Power cut**: only the lead is kept (saved at once when it changes, which is
  rare), so the rotation carries on instead of the first unit always leading after
  frequent power cuts. Run times for HOURS (`grpRunTime`) start again at 0, also when the
  motor records are `RETAIN` (equal times go in turn from the kept lead), and so does
  the exercise timing (the motors' `offTime` counts from power-up). Every `grpRun` starts cleared
  and units start one at a time again. The motors keep their own modes. A motor ignores `grpRun` on its first scan,
  so a retained record never starts it, and it clears `grpActive` each scan: if UT_DUTY stops being called,
  its motors go back to their own `AutoCmd` on the next scan. Call order does not
  matter (after the motors, they follow one scan later).

## Using it
```iecst
VAR Fans : ARRAY[1..3] OF UT_MOTOR_DATA; END_VAR
Duty(Required := FansNeeded, Units := Fans, Data := DutyCfg);
F1(AutoCmd := FALSE, Feedback := F1_Aux, Overload := F1_OL, Data := Fans[1]);
(* … F2, F3 … *)
```
`AutoCmd` must be wired (the editor checks it) but is not used while the group owns
the motor.
