# UT_PUMP_STATION — Multi-pump station (wet well, sump, tank, booster)

Runs a station of any number of pumps from one level or pressure signal. It
handles staged start/stop points, duty rotation (alternation), failover to the
next pump, staggered starts, backup floats, random start-level variation (stops
fat rings forming), sump cleaning, a pump-down on request (`Demand`), an inhibit that
keeps the overflow backup, and inflow, outflow and overflow statistics.

There's no per-pump wiring. Give the station the array of pump records, and each
[UT_PUMP](UT_PUMP.md) uses one element as its `Data`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Level` | REAL | 0.0 | Level (or pressure) signal, e.g. `UT_ANALOG_IN.Value` |
| in | `Enable` | BOOL | TRUE | FALSE = everything off: no pump is called, the high float included (pumps stop unless in Hand) |
| in | `LevelBad` | BOOL | FALSE | Transmitter failed (e.g. `NOT LevelAI.Good`). Switches to float/timer control. A level that is not a number does the same |
| in | `HighFloat` | BOOL | FALSE | Backup high-level float, TRUE = made. Also checks the transmitter (see `transducer`). A float that opens at high level: `NOT` at the pin |
| in | `LowFloat` | BOOL | FALSE | Low-level cut-out float, TRUE = level low (stops all pumps). A float that is made with water (fail-safe on a broken wire): `NOT` at the pin |
| in | `Rotate` | BOOL | FALSE | Rising edge: change the lead pump now |
| in | `Reset` | BOOL | FALSE | Rising edge: clear latched faults (a MANUAL transducer fault, `cleanFailed`), as `cmdReset`. The statistics are kept (`cmdResetStats`) |
| in | `Demand` | BOOL | FALSE | Pump down now (FILL: fill up): `demandPumps` pumps until `demandStop`. A remote run request (SCADA, a timer); see [Demand](#demand-and-inhibit) |
| in | `Inhibit` | BOOL | FALSE | No level, demand or cleaning start (a running level cycle is released), while **the high float still runs the pumps** (the overflow backup). `Enable` FALSE is everything off |
| out | `RunningCount` | INT | | Pumps running |
| out | `HighLevel` | BOOL | | Level above `highLevelAlarm`, or the high float |
| out | `Shortfall` | BOOL | | Fewer pumps available than the level asks for |
| out | `Lead` | INT | | Array index of the lead pump |
| out | `Inflow` | REAL | | Estimated inflow per hour, in the vessel's volume unit: the rise of the `Level` vessel's volume (a `UT_VESSEL` on `Level`), plus the `Flow` meter's rate. 0 without a vessel |
| out | `TransducerFault` | BOOL | | The level can't be trusted: it disagreed with the high float (until it reads again, see `transducer`), or `LevelBad` / a level that is not a number. `floatControl` says whether the station runs on the floats and timers |
| out | `ConfigFault` | BOOL | | A setting makes level control meaningless. An unknown `stationMode`: **no pump is called**. Stage 1 the wrong way round or not a number: no level control; in EMPTY the high float still runs the pumps (float/timer control, the overflow backup never depends on settings), in FILL no pump is called. Until it is fixed |
| out | `Warning` | BOOL | | An invalid setting (a safe value is used), a cleaning timeout (`cleanFailed`), a transducer WARN, or `ConfigFault` |
| out | `Fault` | BOOL | | A configuration fault, the transducer check tripped, a bad level in FILL, or no pump available while one is wanted (`faultCode` says which) |
| inout | `Pumps` | ARRAY[*] OF UT_PUMP_DATA | | All the station's pump records (any size, any lower bound) |
| inout | `Data` | UT_STATION_DATA | | Station record |

## Record `UT_STATION_DATA`

### Settings
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stationMode` | UT_STATION_MODE | UT_SM_EMPTY | `UT_SM_EMPTY` (wet well, sump) or `UT_SM_FILL` (reservoir, booster on pressure) |
| `stage` | ARRAY[1..4] OF UT_STAGE | see below | `start`/`stop` point per stage (stage n = n pumps running) |
| `maxRunning` | INT | 0 | Limit on pumps running together (0 = no limit). No pump is called while this many run (Hand pumps count) |
| `rotation` | UT_ROTATE_MODE | UT_ROT_EACH_START | Fixed / each cycle / equal hours / every interval |
| `rotateInterval` | TIME | T#24h | For `UT_ROT_INTERVAL` (0 = never) |
| `fixedLead` | INT | 1 | For `UT_ROT_FIXED`: the array index of the lead (out of range = the first) |
| `stageDelay` | TIME | T#5s | Minimum gap between pump starts (inrush, water hammer), counted from the last pump's run command |
| `destageDelay` | TIME | T#2s | Minimum gap between pump stops |
| `failoverDelay` | TIME | T#10s | Called pump not running this long after its run command → skipped, the next is called. Set it longer than the motor's `restartDelay` |
| `levelVariation` | REAL | 0.0 | Random ± offset on stage 1 start, new each cycle (fat-ring prevention). 0 = off |
| `cleanEvery` | INT | 0 | Every N cycles, pump down to `cleanLevel` (sump clean). 0 = off |
| `cleanLevel` | REAL | 5.0 | |
| `cleanTime` | TIME | T#20s | Extra run ("snore") once the clean level is reached |
| `maxCleanTime` | TIME | T#5m | Cleaning not finished in this time (from its start): it ends with `cleanFailed` and the pumps running only for it stop at once (the well isn't coming down: blocked intake, air lock, `cleanLevel` below the pump), then normal control. Set it longer than a pump-down plus `cleanTime`. 0 = no limit |
| `highFloatRunAll` | BOOL | TRUE | High float runs every available pump (FALSE: the lead only). Each high-float event also gives every pump skipped for a failed start one more try |
| `highFloatHold` | TIME | T#2m | Keep running after the high float clears (level trusted) |
| `floatRunTime` | TIME | T#5m | Float/timer control: keep running this long after the high float clears |
| `floatLockout` | TIME | T#1m | Float/timer control: after the pumps stop, the high float can't start them again for this long (anti-cycling) |
| `floatCheckDelay` | TIME | T#10s | High float made while the level reads below `highLevelAlarm` for this long → the transducer is suspect. A float tipping right at the alarm level for less than this is not a fault |
| `transducer` | UT_PROTECTION | TRIP · AUTO · recover 10 s | What a suspect transducer does. `response`: OFF = no check · **TRIP** = float/timer control while it lasts · WARN = an alarm only, the level is still used (less safe: a stuck-low reading then never starts the pumps, only the high float does). `reset`: **AUTO** = it clears once the transducer reads properly again (a valid reading at or above `highLevelAlarm`) and `recover` has passed · MANUAL = it also needs `Reset` / `cmdReset` · RETRY = AUTO up to `maxRetries` in an hour, then MANUAL. `delay` is not used (`floatCheckDelay` is the check's delay). Status: `active`, `tripped`, `retries`, `count` |
| `highLevelAlarm` | REAL | 90.0 | High-level alarm, and the transducer check. Set it at or below the level the high float makes at |
| `wellArea` | REAL | 0.0 | Plan area of the well (m²) for the inflow estimate. 0 = off |
| `pumpsUsed` | INT | 0 | Pumps fitted: the station uses the first `pumpsUsed` records of `Pumps` (0 = all). The others are left alone: never called, rotated in or counted, so a record can serve a pump that is not fitted yet, or one run on its own (e.g. a booster). Negative or more than the array: every pump, and the warning `Setting: pumps used` |
| `floatsOnly` | BOOL | FALSE | EMPTY, no level transmitter: float-only control as the normal control (see How it works). `Level` is not used and is no fault. With FILL it is a configuration fault (`UT_F_STATION_MODE`) |

`UT_STAGE` (`start`, `stop` : REAL) defaults: stage 1 = 60 / 20, stage 2 = 75 / 25,
stage 3 = 85 / 30, stage 4 = 90 / 35 (same units as `Level`). Stations with more than 4
pumps: stage 4 calls every remaining pump. In FILL mode, set start below stop. Stage 1
must be usable: the wrong way round for the mode (or not a number) is a configuration
fault and no pump runs. Stages 2–4 whose points are the wrong way round are not used, so
in FILL mode the EMPTY defaults of the stages you don't set never call a pump (not a
number there: not used, and a warning).

### Demand settings (at the end of the record)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `demandPumps` | INT | 1 | `Demand` / `cmdPumpDown`: pumps to run (1 or more; staged a `stageDelay` apart, within `maxRunning`) |
| `demandStop` | REAL | 0.0 | `Demand` / `cmdPumpDown`: run until the level reaches this (EMPTY: falls to it; FILL: rises to it). 0 = stage 1's stop point |

### HMI commands
`cmdRotate` (move the lead on now), `cmdClean` (clean now), `cmdReset` (clear latched
faults, as the `Reset` pin), `cmdResetStats` (`cycles`, `highFloatEvents` and
`highFloatTime` to 0; nothing else), `cmdPumpDown` (pump down now, as a new `Demand`).
Each acts once, on its rising edge, and is cleared.

### Status fields
`lead`, `runningCount`, `calledCount`, `availableCount`, `shortfall`, `highLevel`,
`floatControl` (float/timer control active), `transducerFault` (as the pin),
`configFault` (as the pin), `configBad` (any invalid setting, `configFault` included),
`cleaning`, `cleanFailed` (cleaning timed out; until a reset or a clean that finishes),
`warning` (as the pin), `cycles : UDINT`,
`highFloatEvents : UDINT`, `highFloatTime : TIME` (overflow-risk duration),
`inflow : REAL`, `startPointNow` (stage 1 start including the variation),
`statusCode : UT_STATUS`, `statusText : STRING(30)` and `statusUnit : DINT` (what the
station is doing or what holds it back, and the pump it is about, see
[Status](#status)), and at the end of the record:

| Field | Type | Meaning |
| --- | --- | --- |
| `demand` | BOOL | `Demand` / `cmdPumpDown` is running pumps |
| `inhibited` | BOOL | `Inhibit` holds the level control off |
| `timeLeft` | TIME | The countdown that goes with the status: stage or destage delay, the high-float hold or `floatRunTime`, the float lockout, the clean (`cleanTime` once at the clean level, else `maxCleanTime`). 0 = none |
| `phaseTime` | TIME | Time in this cycle (pumps wanted), or idle since the last one |
| `cleanElapsed` | TIME | Time cleaning so far (0 when not cleaning) |
| `rotateIn` | TIME | INTERVAL: time to the next rotation (0 for the other rotations) |
| `outflow` | REAL | Estimated pumped flow per hour while pumps run: `wellArea` × the level fall per hour + `inflow` (FILL: the rise − use). Needs `wellArea`; 0 while idle |
| `cycleVolume` | REAL | Net volume drawn (EMPTY) or added (FILL) this cycle: `wellArea` × the level change since the cycle began; kept after it ends (not counted on while the level is not trusted) |
| `fault`, `faultCode : DWORD` | | As `Fault`: bit 0 config fault, 1 transducer fault (float check), 2 level signal bad (FILL), 3 no pump available |
| `faultId` | UT_FAULT | The lowest `faultCode` bit by name: the setting (`UT_F_STATION_MODE`, `UT_F_STAGE1`), `UT_F_TRANSDUCER`, `UT_F_LEVEL_BAD`, `UT_F_NO_PUMP`; `UT_F_NONE` when there is no fault |
| `stopReason` | UT_STOP | Why the last cycle ended (all pumps released), below |
| `lastFaultCode`, `lastFault` | DWORD, UT_FAULT | The last fault's bits and name, kept after it clears |
| `trips` | UDINT | Faults since power-up |

Each pump's record shows its part: `grpRank` (1 = lead), `grpRun` (called),
`grpSkipped` (called but did not run; skipped until it has been unavailable or the next
cycle starts) and `grpRunTime` (its run time counted by the station since power-up,
for HOURS rotation).

**Why the last cycle ended** (`stopReason`):
| `stopReason` | Words ([UT_STOP_TEXT](UT_STOP_TEXT.md)) | When |
| --- | --- | --- |
| `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` | The level reached the stop point |
| `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` | `Enable` off |
| `UT_STOP_INHIBITED` | `Stopped: inhibited` | `Inhibit` |
| `UT_STOP_LOW_LEVEL` | `Stopped: low level` | The low float |
| `UT_STOP_FULL` | `Stopped: full` | FILL: the high float |
| `UT_STOP_CLEAN_TIMEOUT` | `Stopped: cleaning too long` | Cleaning timed out |
| `UT_STOP_LEVEL_BAD` | `Stopped: level signal bad` | FILL: the level is not trusted |
| `UT_STOP_SETTING` | `Stopped: setting invalid` | A configuration fault |
| `UT_STOP_DONE` | `Done` | `Demand` / `cmdPumpDown` reached the demand level |

### Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the station is
doing, or what holds it back. The most important reason wins: configuration > fault >
held / waiting > warning > running > idle. A station asked to run (the level or the
high float wants a pump) with no pump running or starting always shows a held, fault
or configuration status. `UT_ST_STARTING` (a called pump's run command is out, its
feedback not yet in) shows over a warning. `statusUnit` is the pump (its array index)
the status is about, for `UT_ST_STARTING` and `UT_ST_PUMP_DELAY`; one below the
array's first index when none. Each pump's own status says more (e.g. `Waiting: min
off time`). The words hold no numbers: the level is the `Level` output, the counts are
`runningCount`, `calledCount` and `availableCount`, and the time left is in
`timeLeft`. The text is rebuilt only when the status or the fault changes. The
numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE_NO_DEMAND` | `Idle: no demand` | No pump wanted |
| `UT_ST_STARTING` | `Starting` | Pump `statusUnit` is called, its run command is out, not running yet |
| `UT_ST_STOPPING` | `Stopping` | More pumps called than wanted: the next release after `destageDelay` (`timeLeft`) |
| `UT_ST_RUNNING` | `Running` | Pumps running (any mode); `runningCount` says how many |
| `UT_ST_RUN_DEMAND` | `Running: demand` | `Demand` / `cmdPumpDown` is running pumps |
| `UT_ST_IDLE_LEVEL_REACHED` | `Idle: demand level reached` | `Demand` still held, the level at `demandStop`: it waits for the start point or a new `Demand` (never "no demand" while `Demand` is TRUE) |
| `UT_ST_CLEANING` | `Cleaning` | Pumping down to `cleanLevel` (`timeLeft` is the time left of `maxCleanTime`), then `cleanTime` |
| `UT_ST_HIGH_FLOAT` | `Running: high float` | EMPTY, level trusted: the high float runs the pumps (made, then `highFloatHold`, counting in `timeLeft`) |
| `UT_ST_FLOAT_RUN` | `Running: on floats` | `floatsOnly`: the high float started the lead; it runs to the low float (or `floatRunTime`, counting in `timeLeft`, after the high float clears) |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | `Enable` FALSE |
| `UT_ST_INHIBITED` | `Blocked: inhibit` | `Inhibit`, no pump running (the high float still acts) |
| `UT_ST_LOW_FLOAT` | `Blocked: low float (dry)` | `LowFloat` made: every pump stopped (not with `floatsOnly`: there it is the stop float, made whenever the well is down) |
| `UT_ST_FULL` | `Blocked: high float (full)` | FILL: `HighFloat` made |
| `UT_ST_STAGE_DELAY` | `Waiting: stage delay` | More pumps wanted, the next start after `stageDelay` (`timeLeft`) |
| `UT_ST_PUMP_DELAY` | `Waiting: pump own delay` | Pump `statusUnit` is called but waits out its own `startDelay` / `minOffTime` or its `StartHold` (the pump's status says which) |
| `UT_ST_MAX_RUNNING` | `Waiting: max running reached` | More pumps wanted, `maxRunning` already running (e.g. one running down) |
| `UT_ST_SHORTFALL` | `Shortfall: too few available` | More pumps wanted than are available (tripped, not in Auto, skipped); `availableCount` says how many are |
| `UT_ST_WARNING` | `Warning: level vs high float` | `UT_F_FLOAT_DISAGREE`: the transducer check set to WARN |
| `UT_ST_WARNING` | `Warning: cleaning too long` | `UT_F_CLEAN_TIME`: `cleanFailed` |
| `UT_ST_WARN_SETTING` | `Setting: a setting` | `UT_F_SETTING`: `configBad` without a configuration fault |
| `UT_ST_WARN_SETTING` | `Setting: pumps used` | `UT_F_PUMPS_USED`: `pumpsUsed` negative or more than the array (every pump is used) |
| `UT_ST_FLOAT_CONTROL` | `Float control` | EMPTY: float/timer control, with `faultId` `UT_F_TRANSDUCER` (the transducer check tripped) or `UT_F_LEVEL_BAD` (`LevelBad` or a NaN / infinite level); `runningCount` pumps running |
| `UT_ST_FLOAT_LOCKOUT` | `Float lockout` | Float/timer control: the high float can't start the pumps again for `floatLockout` (`timeLeft`) |
| `UT_ST_FAULT` | `Fault: level signal bad` | FILL: a bad level stops every pump |
| `UT_ST_FAULT` | `Fault: no pump ready` | Pumps wanted, none available (all tripped, not in Auto or skipped) and none running |
| `UT_ST_CONFIG` | `Config: <setting>` | No level control until fixed: `UT_F_STATION_MODE` (station mode: unknown), `UT_F_STAGE1` (stage 1 start / stop: the wrong way round, equal, or not a number), `UT_F_NO_UNITS` (no units in array: an empty pump array) |

## How it works
1. **Ranking.** Pumps are ranked by the rotation rule (`grpRank`). A pump is a
   candidate when it is available (healthy, motor ready, motor in Auto) and not
   skipped. Pumps running in Hand (or exercising) count toward the demand; a pump
   running down after a stop or a trip does not.
2. **Staging.** As the level rises past stage n's start, n pumps are wanted. Pumps are
   called one at a time, best rank first, at least `stageDelay` apart and only once
   the last one called is running. Each stage drops out at its own stop point, and
   pumps are released one at a time (worst rank first), at least `destageDelay` apart.
3. **Failover.** A called pump that isn't running within `failoverDelay` of its run
   command is skipped and the next is called (it rejoins next cycle: no retry storm). A
   pump still waiting out its own `startDelay` / `minOffTime` (after a power cut, or
   just stopped) hasn't failed: after `failoverDelay` it hands over if another pump can
   be called, and is called again once no other is left. A pump that trips, loses its
   motor or leaves Auto is released at once and replaced. It rejoins once it's
   available again (no needless swap of a pump already running). A pump whose
   `StartHold` is on (`startHold`, e.g. a stirrer pre-run) has not failed either: it
   stays called, with no failover, and starts when the hold ends.
4. **Rotation.** FIXED: `fixedLead`. EACH_START: the lead moves on when a cycle ends
   (all pumps released). HOURS: at each cycle start the pump with the least run time
   leads (each pump's `grpRunTime`, counted by the station; every pump counts). INTERVAL: every
   `rotateInterval`. `Rotate`/`cmdRotate` move the lead on now. A rotation while
   running starts the new lead before stopping the old one, never dropping below the
   demand; at `maxRunning` the old one stops first, so the limit is never passed.
5. **Backup floats (EMPTY).** `HighFloat` runs every available pump (or the lead)
   whatever the transmitter says, and keeps them running `highFloatHold` after it
   clears. `LowFloat` and `Enable` off release every pump at once.
   **Transducer check.** If the high float is made while the transmitter reads below
   `highLevelAlarm` for longer than `floatCheckDelay`, the transmitter is suspect
   (stuck, drifted, fouled): `TransducerFault`, and with the default TRIP, float/timer
   control. It does not latch for ever: build-up round a sensor clears. A healthy
   transmitter shows the high level as the well refills, before or as the float
   makes; once it reads a valid value at or above `highLevelAlarm`, the fault clears
   after `transducer.recover` (AUTO). A transmitter still stuck never shows it, so the
   float catches it again. With MANUAL it also needs `Reset` / `cmdReset`. A reset
   clears it at any time (refused while the float is made and the reading is still
   low); so does a power cut.
   **Float/timer control** (a transducer fault, `LevelBad`, or a level that is not a
   number): the level is ignored. When the high float makes, the pumps run while it
   stays made (never stopped during a real flood) and `floatRunTime` after it clears.
   After they stop, the high float can't start them again for `floatLockout`. The
   low float stops them at once and ends the run (the lockout follows).
   **FILL mode:** `HighFloat` (tank full) and a bad level release every pump;
   `LowFloat` still cuts out.
   **Float-only control** (`floatsOnly`, EMPTY, no transmitter): the normal control,
   not a fault. `HighFloat` (the start float) calls the lead pump; it runs until
   `LowFloat` (the stop float) makes, or `floatRunTime` after the high float clears
   (0 = the low float only). No lockout, no transducer check, `HighLevel` is not
   set by the start float (wire a high-level float to its own alarm), and level
   stages, `Demand`, cleaning and the inflow estimate are not used. Failover and
   rotation work as usual; a second pump is called only by failover. `Inhibit` stops
   it (it is the level control).
6. **Cleaning and variation.** These reduce grease build-up in sewage wells. A clean
   cycle runs a pump down to `cleanLevel`, then `cleanTime` more. A pump that trips
   during the clean (its own dry-run protection) ends it. A clean not finished within
   `maxCleanTime` ends with `cleanFailed` (a warning) and the pumps running only for
   it stop at once; if the level still wants a pump, it runs on as normal.
   `levelVariation` must be less than the gap between stage 1's start and stop.
7. **Inflow.** While no pump runs, the level rise × `wellArea`, averaged since the
   pumps stopped (published after 2 s, a fresh window every minute). Held while
   pumps run.
8. **Invalid settings.** A **configuration fault** (`ConfigFault`, until fixed): an
   unknown `stationMode` (no pump at all); stage 1 the wrong way round for the mode or
   not a number (no level control: an EMPTY station drops to float/timer control so
   the high float still protects the well; a FILL station calls no pump, and must set
   stage 1). A
   **warning** (`configBad`, `Warning`) with a safe value: `maxRunning` negative (as
   0, no limit); `failoverDelay` 0 or negative (10 s: 0 would skip every pump before
   it could start); `levelVariation` negative, not a number or not below the stage 1
   gap (no variation); `cleanEvery` negative, `cleanLevel` not a number, a negative
   `cleanTime` or `maxCleanTime` (no cleaning); an unknown `rotation`; `fixedLead` out
   of range with FIXED (the first pump); `pumpsUsed` negative or more than the array
   (every pump); stages 2–4 not a number (not used); a negative
   time (as 0); `highLevelAlarm` not a number; `wellArea` negative or not a number
   (inflow off); `transducer` with an unknown response (as TRIP) or reset (as AUTO),
   or a bad time.
9. **Resets.** `Reset` (rising edge) and `cmdReset` clear latched faults (a MANUAL or
   used-up RETRY transducer fault, `cleanFailed`); `cmdResetStats` clears the
   statistics. Neither does the other's job.

### Demand and inhibit
- **`Demand`** (or `cmdPumpDown`, once) pumps down now, e.g. a SCADA "empty the
  sump before the rain" or a timed draw-off: `demandPumps` pumps run until the level
  reaches `demandStop` (0 = stage 1's stop point), status `UT_ST_RUN_DEMAND`. Every station protection
  still acts: the low float, the transducer check (no demand while the level is not
  trusted), `maxRunning`, failover and staging. At `demandStop` the pumps stop
  (`stopReason` `UT_STOP_DONE`); a `Demand` still held waits (`UT_ST_IDLE_LEVEL_REACHED`) and runs again once the
  level is back at the stage 1 start point, or on a new rising edge. Refused on the low
  float, a level that is not trusted, `Enable` off or `Inhibit`. In FILL mode it fills
  up to `demandStop` instead.
- **`Inhibit`** holds the level control off (no level, demand or cleaning start; a
  pump running for the level is released, `stopReason` `UT_STOP_INHIBITED`) while the **high float still
  runs the pumps**: the overflow backup stays. `Enable` FALSE is everything off, the
  high float included (`stopReason` `UT_STOP_SWITCHED_OFF`).

**Power cut**: only the lead is kept (saved at once when it changes, so after
frequent power cuts the first pump does not always lead). With HOURS a tie in run
time goes to the kept lead,
`cycles`, `highFloatEvents`, `highFloatTime` and the pumps' `grpRunTime` at 0 (also when the pump records are `RETAIN`), and a transducer
fault and `cleanFailed` are cleared. Every
`grpRun` starts cleared and the pumps are called one at a time again, even if your
pump records are `RETAIN`.

## Using it
```iecst
VAR Pumps : ARRAY[1..3] OF UT_PUMP_DATA; END_VAR
Station(Level := WetWell.Value, LevelBad := NOT WetWell.Good,
        HighFloat := HiFloat, LowFloat := LoFloat, Pumps := Pumps, Data := StationCfg);
P1(Demand := HiFloat, Running := M1.Running, MotorReady := M1.Ready, MotorAuto := M1.Auto,
   DryRun := LoFloat, Data := Pumps[1]);
(* … P2, P3 … *)
```
Each pump's `Demand` is only its fallback: while the station runs, the station decides.
If the station block stops being called, each pump is back on its own control (here:
run on the high float) from the next scan.
