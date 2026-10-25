# UT_ZONE_SEQ — Irrigation / wash-down zone sequencer

Runs a list of zones (irrigation blocks, pivots, wash-down stations, effluent
spreading) one after another, each by time or by volume. It opens the right valve,
runs the pump, sets each zone's pressure for the speed controller, and overlaps
valves so the pump never deadheads. It also handles cycle-and-soak, rain hold,
flow checks per zone (blocked dripper line, burst lateral), pause, skip and
manual zone runs.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Start` | BOOL | FALSE | Rising edge: run the program (e.g. `UT_SCHEDULE.Active` edge). Also resumes an HMI pause. With `startIsLevel`: held = run, dropping it stops the program (a remote schedule that holds a run signal) |
| in | `Stop` | BOOL | FALSE | Rising edge: end the program (closes safely) |
| in | `Pause` | BOOL | FALSE | Hold where it is (pump off, valves closed, time kept) |
| in | `RainHold` | BOOL | FALSE | Rain sensor / soil moisture satisfied (action set by `rainAction`) |
| in | `PumpRunning` | BOOL | FALSE | Pump running. **Zone time only counts while TRUE** — wire it |
| in | `PumpFault` | BOOL | FALSE | Pump tripped: zone time stops, carries on when the pump recovers |
| in | `Flow` | REAL | 0.0 | Flow meter (volume zones, per-zone flow checks). Optional. NaN, infinite or negative counts as 0 |
| in | `Clock` | DT | DT#1970-01-01-00:00:00 | Real-time clock, for each zone's `lastRun`. Optional |
| in | `Permit` | BOOL | TRUE | FALSE holds back the start of the program and of each next zone (`Not permitted`): nothing opens, the pump stays off. A zone already watering carries on to its end. TRUE again: it carries on. E.g. tank level OK, an off-peak window |
| in | `Abort` | BOOL | FALSE | Ends the program safely (pump off, then the valves) and refuses a start while on (`Blocked: abort`). E.g. a low-low level or a site trip |
| in | `AbortCode` | UT_STOP | UT_STOP_NONE | The `endReason` an `Abort` gives, e.g. `UT_STOP_LOW_LEVEL`. `UT_STOP_NONE` gives `UT_STOP_ABORTED` |
| out | `PumpDemand` | BOOL | | → `UT_SPEED_CTRL.Enable` / `UT_PUMP.Demand` |
| out | `ZoneSp` | REAL | | Active zone's pressure (its `sp`, or `defaultSp`) → `UT_SPEED_CTRL.Sp` |
| out | `ActiveZone` | INT | | Position of the zone whose valve is open (0 = none) |
| out | `Busy` | BOOL | | Running, or closing up |
| out | `Done` | BOOL | | One scan at the end of the program (not after a stop or a rain cancel) |
| out | `Warning` | BOOL | | A zone had a flow problem or hit `maxZoneTime` in this run (stays until the next start) |
| inout | `Zones` | ARRAY[*] OF UT_ZONE | | One element per zone, in run order |
| inout | `Data` | UT_ZONE_SEQ_DATA | | |

Positions (`ActiveZone`, `cmdRunZone`) count from 1 = the first
element, whatever the array's lower bound.

## Zone slot `UT_ZONE`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `enable` | BOOL | TRUE | Include in the program |
| `runTime` | TIME | T#10m | Watering time (when `volume` = 0) |
| `volume` | REAL | 0.0 | Water to apply, in the flow meter's volume unit (needs `Flow`). 0 = time-based |
| `sp` | REAL | 0.0 | Pressure for this zone (0 = `defaultSp`) |
| `cycles` | INT | 1 | Split the zone into this many cycles… |
| `soakTime` | TIME | T#0s | …with this soak between them (less runoff on heavy soils) |
| `minFlow` / `maxFlow` | REAL | 0.0 / 0.0 | Expected flow band (0 = not checked): low = blocked, high = burst |
| `flowCheck` | UT_PROTECTION | WARN · 60 s · AUTO | What to do on a flow-band breach. TRIP = end this zone and move on |
| `valve` | BOOL | | **Output**: this zone's valve should be open. With the default NC drive, wire this or `openCmd` to the valve's output |
| `active` | BOOL | | Status: this zone is the one being watered |
| `done` | BOOL | | Status: finished in this run (watered, skipped or capped) |
| `skipped` | BOOL | | Status: skipped (rain, `cmdSkip`, flow trip) |
| `capped` | BOOL | | Status: ended by `maxZoneTime` |
| `flowAlarm` | BOOL | | Status: flow out of band in this run |
| `delivered` | REAL | | Status: volume this run |
| `watered` | TIME | | Status: water time this run |
| `remaining` | TIME | | Status: water time left (volume zones: `maxZoneTime` left) |
| `cycle` | INT | | Status: cycles finished |
| `soakLeft` | TIME | | Status: soak time left |
| `lastRun` | DT | | Status: `Clock` when it last finished watering |
| `endBy` | UT_ZONE_END | UT_ZE_AUTO | How the zone ends: `UT_ZE_AUTO` (0: `volume` if it has one, else `runTime`) · `UT_ZE_TIME` (`runTime`, the volume only counted) · `UT_ZE_VOLUME` (`volume`, `runTime` ignored) · `UT_ZE_FIRST` (whichever comes first) · `UT_ZE_UNTIL_STOP` (it waters until `Stop` / `cmdStop`, a held `Start` dropping, `cmdSkip`, `Abort` or a protection; `runTime`, `volume` and `cycles` are not used; `maxZoneTime` still caps it). A zone with nothing to give for its `endBy` (VOLUME with no volume, TIME with no `runTime`) is passed over |
| `useProven` | BOOL | FALSE | The valve must be proven open (`proven`) before the pump starts or the previous valve closes (see [Valve proven open](#valve-proven-open)) |
| `proven` | BOOL | FALSE | **Input**: the valve is proven open, e.g. its open limit switch. Write it from your input every scan |
| `openCmd` | BOOL | | **Output**: NC drive: on = open (the same as `valve`). LATCH: the open pulse. MOTOR: the open run |
| `closeCmd` | BOOL | | **Output**: NO drive: on = closed. LATCH: the close pulse. MOTOR: the close run |
| `driveLeft` | TIME | | Status: LATCH / MOTOR: the pulse or travel time left |

## Record `UT_ZONE_SEQ_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `valveOverlap` | TIME | T#5s | Next valve opens this long before the previous one closes (no deadhead) |
| `pumpStartDelay` | TIME | T#3s | First valve opens this long before the pump starts |
| `valveCloseDelay` | TIME | T#5s | Valves close this long after the pump is told to stop, and only once `PumpRunning` has gone (no water hammer) |
| `rainAction` | UT_RAIN_ACTION | UT_RAIN_PAUSE | `UT_RAIN_PAUSE` (0, resume when cleared) · `UT_RAIN_SKIP` (each zone is skipped as it comes up while it rains; the one running ends now) · `UT_RAIN_CANCEL` (end the program) · `UT_RAIN_IGNORE` |
| `repeats` | INT | 1 | Run the whole program this many times |
| `maxZoneTime` | TIME | T#0s | Safety cap on any zone's water time (volume zones with a dead meter). 0 = off |
| `defaultSp` | REAL | 0.0 | `ZoneSp` when the zone's `sp` is 0, and when idle |
| `flowPer` | UT_RATE_UNIT | UT_PER_HOUR | `Flow` is volume units per second / minute / hour / day |
| `cmdStart` | BOOL | | HMI: start, or resume an HMI pause |
| `cmdStop` | BOOL | | HMI: stop |
| `cmdPause` | BOOL | | HMI: pause until a start |
| `cmdSkip` | BOOL | | HMI: skip the zone running now |
| `cmdRunZone` | INT | -1 | HMI: run only this zone (position, enabled or not); -1 = none |
| `phase` | UT_ZONE_PHASE | | Status: `UT_ZS_IDLE`, `_OPENING`, `_WATERING`, `_OVERLAP`, `_SOAKING`, `_PAUSED`, `_RAIN`, `_PUMP_FAULT`, `_CLOSING`, `_HELD` (`Permit` off, a zone waiting to start) |
| `activeZone` | INT | | Status: same as `ActiveZone` |
| `pass` | INT | | Status: which pass of the program (1..`repeats`, 0 idle) |
| `programRemaining` | TIME | | Status: water time left (time zones; soaks not included) |
| `runs` | UDINT | | Status: programs completed since the PLC started (manual zone runs not counted) |
| `paused` | BOOL | | Status |
| `warning` | BOOL | | Status: same as `Warning` (also on a bad setting) |
| `configBad` | BOOL | | Status: a setting is invalid (see Bad settings) |
| `statusCode` | UT_STATUS | | Status: what it is doing, or what holds it back (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | Status: the warning or setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Running: zone`. The zone is in `activeZone`, its time left in `timeLeft` |
| `maxPumpWait` | TIME | T#0s | While a zone waters, the pump faulted or not running this long ends the program (`Stopped: pump fault`, valves closed safely). 0 = wait for ever |
| `pumpWaitSkips` | BOOL | FALSE | `maxPumpWait`, and a valve not proven in `provenTime`, skip that zone instead, and the next one runs |
| `startIsLevel` | BOOL | FALSE | `Start` held = run, dropping it stops the program (`Stopped: remote off`) |
| `timeLeft` | TIME | | Status: the countdown the status shows (the zone's water time left, the pump start delay, the soak) |
| `phaseTime` | TIME | | Status: time in the current phase |
| `programDelivered` | REAL | | Status: volume through the meter in this program (all zones), kept after it ends |
| `endReason` | UT_STOP | | Status: why the last program ended: `UT_STOP_OPERATOR` (`Stop`, `cmdStop`), `UT_STOP_DONE` (also a `cmdRunZone` run), `UT_STOP_RAIN` (CANCEL), `UT_STOP_PUMP_FAULT` (`maxPumpWait`), `UT_STOP_REMOTE_OFF` (`startIsLevel`, or found off at power-up), `UT_STOP_SETTING` (a setting made invalid), `UT_STOP_POWER_CUT` (a program cut off that does not carry on: RESTART, NONE), `AbortCode` (`Abort`; `UT_STOP_ABORTED` when it is NONE), `UT_STOP_FAULT` (a valve not proven in `provenTime`). `UT_STOP_NONE` = none since power-up |
| `endZone` | INT | | Status: the zone watering (or watered last) when it ended: the `cmdRunZone` zone, the zone of a power cut (0 = none) |
| `lastFaultCode` / `lastFault` | DWORD / UT_FAULT | | Status: the last fault, kept after it clears: bit 0 `UT_F_ZONE_FLOW` (a flow TRIP), bit 1 `UT_F_PUMP_FAULT` (`maxPumpWait`), bit 2 `UT_F_NOT_PROVEN` (a valve not proven). The zone's `flowAlarm` / `skipped` show which, until the next start |
| `trips` | UDINT | | Status: flow trips, pump waits and valves not proven since power-up |
| `powerUp` | UT_RUN_POWERUP | UT_RPU_RESUME | What a program does after a power cut: `UT_RPU_RESUME` (0, the default: it carries on where it was) · `UT_RPU_RESTART` (a held program starts again from zone 1) · `UT_RPU_NONE` (nothing starts). See [After a power cut](#after-a-power-cut). An unknown value acts as NONE. The enum is declared with [UT_RUN_LIMIT](UT_RUN_LIMIT.md) |
| `progressSave` | TIME | T#1m | RESUME: while a program runs, the zone's water time and volume are saved at most this often (and at once when the zone, pass or cycle changes). At most this much water is given again after a power cut. 0 = saved only on those changes (the zone starts its count again) |
| `provenTime` | TIME | T#30s | `useProven`: a valve not proven this long after it is told to open is a fault (`UT_F_NOT_PROVEN`): the program ends (`UT_STOP_FAULT`), or with `pumpWaitSkips` the zone is skipped. Include the MOTOR travel. 0 = wait for ever |
| `valveDrive` | UT_ZV_DRIVE | UT_ZV_NC | How the zone valves are driven, for every zone (see [Valve drives](#valve-drives)): `UT_ZV_NC` (0, output on = open) · `UT_ZV_NO` (output on = closed) · `UT_ZV_LATCH` (open / close pulses) · `UT_ZV_MOTOR` (open / close runs) |
| `driveTime` | TIME | T#0s | LATCH: the pulse time. MOTOR: the travel time, open or close. Needed (above 0) for LATCH and MOTOR |

## How it works
- **Order, so the pump never deadheads and never hammers**: start = the valve opens,
  `pumpStartDelay` later `PumpDemand` comes on. Zone change = the next valve opens,
  `valveOverlap` later the previous one closes. End, pause or soak = `PumpDemand` goes
  off; the valves close once `valveCloseDelay` has passed and the pump has stopped.
- **Zone time** counts only while `PumpRunning` and not `PumpFault`. A pump trip keeps
  the valve open and the pump asked for, and the zone carries on when it recovers.
- **How a zone ends** (`endBy`): AUTO (the volume if it has one, else the time), TIME,
  VOLUME, or FIRST (whichever comes first, e.g. "50 m³ or 2 h"). Volume counts `Flow`
  integrated, units per `flowPer`. `maxZoneTime` caps any zone; a capped zone gives
  `Warning` and the program moves on.
- **A pump that does not run**: the zone waits (no water time). With `maxPumpWait`, a
  pump faulted or not running that long ends the program safely (`endReason` `UT_STOP_PUMP_FAULT`), or
  with `pumpWaitSkips` skips the zone; either is counted in `trips` with
  `lastFault`.
- **Run while held** (`startIsLevel`): `Start` held runs the program, dropping it stops
  it (`endReason` `UT_STOP_REMOTE_OFF`). A program that ends while `Start` is still held does not start
  again until `Start` cycles. After a power cut, see `powerUp`.
- **Cycle and soak**: each cycle is `runTime / cycles` (or `volume / cycles`). While a
  zone soaks, the next zones run; the program comes back to it after its soak. With
  nothing else to run the pump stops and the valves close until a soak is over.
- **Flow check**: a flow outside `minFlow`..`maxFlow` while one valve is open (not
  during an overlap) is the zone's `flowCheck` protection: after its delay, WARN keeps
  watering, TRIP ends the zone. Either sets `flowAlarm` and `Warning`.
- **Pause** keeps the zone's time. Disabled zones, and zones with no time and no
  volume, are passed over.
- **Permit**: `Permit` off holds back each start: the program's first zone, the next
  zone, and a zone coming back after a pause or a soak. A zone already watering
  carries on to its end; then the pump stops and the valves close as at the end, and
  the program waits (`Not permitted`, phase `UT_ZS_HELD`, `Busy` on). `Permit` on
  again carries on. To stop a zone that is watering, use `Pause` or `Abort`.
- **Abort**: ends the program as `Stop` does (pump off, then the valves), with
  `endReason` = `AbortCode`. While it is on a start is refused, and is not kept for
  later (`Blocked: abort`).
- **Until stopped**: a zone with `endBy` `UT_ZE_UNTIL_STOP` waters until it is stopped,
  the held `Start` drops (`startIsLevel`, a remote that holds the run), or `cmdSkip`
  moves on (status `Running: until stopped`, `timeLeft` 0). The zones after it run only
  after a `cmdSkip`. It is not counted in `programRemaining`.
- **Power cut**: every valve starts closed and the pump off (even if you declared the
  zones RETAIN); LATCH and MOTOR valves are driven closed (one close pulse / run);
  then `powerUp` decides, below.
- Start and Stop in the same scan: no start. Commands held on act once.
- A pump that never reports running holds the program (no water time), and a pump
  that never stops holds the valves open: both are what you want hydraulically, and
  the pump block reports the fault.

## Valve drives
`valveDrive` sets how every zone valve is driven. `valve` is always "this zone should
be open"; wire the outputs for your valve:

| `valveDrive` | Wire | Opening | Closing |
| --- | --- | --- | --- |
| `UT_ZV_NC` (default) | `openCmd` (or `valve`) → the solenoid | `openCmd` on, held | `openCmd` off |
| `UT_ZV_NO` | `closeCmd` → the solenoid | `closeCmd` off | `closeCmd` on, held (also when idle) |
| `UT_ZV_LATCH` | `openCmd` → open coil, `closeCmd` → close coil (or the polarity relays) | one `openCmd` pulse of `driveTime` | one `closeCmd` pulse of `driveTime` |
| `UT_ZV_MOTOR` | `openCmd` → open contactor, `closeCmd` → close contactor | `openCmd` on for the `driveTime` travel | `closeCmd` on for the `driveTime` travel |

- `openCmd` and `closeCmd` are never on together. A valve told the other way while it
  moves reverses at once and gets the full `driveTime`.
- A LATCH or MOTOR valve counts as open once its `driveTime` is over: the pump starts
  (after `pumpStartDelay` too) and the previous zone's valve closes only then. The
  status shows `Starting` with the time left.
- At power-up every LATCH or MOTOR valve gets a close pulse / run (its position is not
  known: it may have been open at the cut). The close pulse or run can still be on
  for `driveTime` after `Busy` goes off.
- LATCH or MOTOR with no `driveTime`, or an unknown `valveDrive`: `Config: valve
  drive`, nothing runs, both outputs stay off.
- On NO valves the valve opens when the output is off: also when the PLC is stopped
  or loses power.

## Valve proven open
With a zone's `useProven` on, its valve must prove it has opened before water is
counted for it:
- The valve opens; the pump starts once `pumpStartDelay` has passed **and** `proven` is
  on. At a zone change, the previous valve stays open (the pump keeps running through
  it) until the new valve is proven and `valveOverlap` has passed. The new zone's time
  counts once it is proven. Status `Waiting: valve proven`, `timeLeft` = `provenTime` left.
- Use a signal that is valid with the pump off, e.g. the valve's open limit switch (a
  pressure switch behind the valve only proves once the pump runs: it works at a zone
  change, not at the first zone).
- Proven is checked while the valve opens; once seen it is not checked again while the
  zone waters (a flow or pressure check covers a valve that shuts while watering).
- Not proven within `provenTime`: `lastFault` `UT_F_NOT_PROVEN`, `trips` + 1, and the
  program ends (`UT_STOP_FAULT`) with the pump off, or with `pumpWaitSkips` the zone is
  skipped and the next one opens (at a zone change, while the previous valve still
  carries the flow, so the pump never deadheads).

## After a power cut
Irrigation of sports fields and properties often runs with no operator: when the
power comes back (or the PLC is stopped and started) the program should carry on, as
a commercial irrigation controller does. `powerUp` chooses:

| `powerUp` | A program running at the cut | `Start` held (`startIsLevel`) at power-up, no program running |
| --- | --- | --- |
| `UT_RPU_RESUME` (default) | **Carries on**: the zone that was watering with the time / volume it had left (status `Running: resumed`), then the zones after it, and the passes left. A program started by a held `Start` that is off now ends: `UT_STOP_REMOTE_OFF`. One started by a pulse, `cmdStart` or `cmdRunZone` just carries on | Starts the program |
| `UT_RPU_RESTART` | Nothing is kept. A program started by a held `Start` that is still on starts again from zone 1 (status `Running: restarted`); `endReason` says `UT_STOP_POWER_CUT`, `endZone` the zone it was in. One started by a pulse, `cmdStart` or `cmdRunZone` ends (`UT_STOP_POWER_CUT`, `endZone`) | Starts the program |
| `UT_RPU_NONE` | Ends (`UT_STOP_POWER_CUT`, `endZone`) | Nothing starts: `Waiting: start again` until `Start` goes off and on again |

- The valves open again in the normal order: valve first, the pump `pumpStartDelay`
  later.
- **Resume** carries on with the zone that was watering: the zones before it count as
  done for this pass, the zone gets its water time, volume and cycles back, and the
  zones after it run in full. A zone that was soaking at the cut soaks again in full.
  `programDelivered` and an HMI pause (`cmdPause`) carry on too; a `cmdRunZone` run
  carries on with that zone only.
- With **cycle and soak**, a zone that was soaking while a later zone watered (other
  than the one cut off) is not tracked: if it is before the interrupted zone in the
  list its cycles left are not given; if after, it runs all its cycles again.
- Water time spent before the cut is not counted again, and a zone never gets more
  than its `runTime` / `volume`.
- The zone carries on from its **last save**: the progress is saved when the program
  starts and ends, when the zone, pass or cycle changes, on `Start` and HMI pause
  changes, and every `progressSave` (default 1 min) while it runs, never every scan
  (flash wear: a few hundred saves on a day of irrigation, none when idle). So up to
  `progressSave` of a zone's water can be given again after a cut.
- A held `Start` that was **already on at the cut and had been dealt with** (its
  program done, or stopped) does not start the program again after the power cut, in
  any mode: as without a power cut, it must go off and on again. Only a `Start` that
  came on while the power was off counts as a new request.
- `Pause`, `RainHold`, `PumpFault` and the settings act from the first scan, as they
  would without a power cut.
- **Kept over a power cut** (inside the block, for this only): whether a program is
  running, how it was started, whether `Start` is on, the HMI pause, the zone
  watering (position, cycles done, soaking, water time, volume), the pass, a
  `cmdRunZone` run, and `programDelivered`. `runs` counts from when the PLC started.

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes. The one main
thing, in the order config, held, warning, normal, idle. The zone is in `activeZone`
(a position in the array), the countdown in `timeLeft`, a volume zone's progress in its
`delivered` of `volume`. Name the zones on the HMI, by position.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_IDLE` | | `Idle` | Not running |
| `UT_ST_STARTING` | | `Starting` | The valve is open, `pumpStartDelay` before the pump (`timeLeft`) |
| `UT_ST_STOPPING` | | `Stopping` | The end (or a pause or soak) closing safely: pump off, then the valves |
| `UT_ST_RUN_ZONE` | | `Running: zone` | Watering: `timeLeft` the zone's water time left (all its cycles); 0 for a volume zone |
| `UT_ST_RESUMED` | | `Running: resumed` | The same, for the first zone watered after a power cut (RESUME), until the zone changes |
| `UT_ST_RESTARTED` | | `Running: restarted` | The same, after a power cut with RESTART |
| `UT_ST_WAIT_POWERUP` | | `Waiting: start again` | NONE: a held `Start` that would have run is on at power-up; it must go off and on again |
| `UT_ST_PAUSED_RAIN` | | `Paused: rain` | `RainHold` with `rainAction` PAUSE |
| `UT_ST_PAUSED_INPUT` | | `Paused: Pause input` | `Pause` |
| `UT_ST_PAUSED_START` | | `Paused: press Start` | `cmdPause` |
| `UT_ST_PUMP_FAULT_HOLD` | | `Blocked: pump fault` | `PumpFault` while watering: the zone time stops |
| `UT_ST_WAIT_PUMP` | | `Waiting: pump not running` | Watering but `PumpRunning` is off (the time does not count) |
| `UT_ST_SOAK` | | `Waiting: soak` | Every zone left is soaking (`timeLeft`: the shortest soak left) |
| `UT_ST_RUN_UNTIL_STOP` | | `Running: until stopped` | Watering a `UT_ZE_UNTIL_STOP` zone |
| `UT_ST_NOT_PERMITTED` | | `Not permitted` | `Permit` off: the next zone (or the first) waits; the valves close after the pump |
| `UT_ST_WAIT_PROVEN` | | `Waiting: valve proven` | The zone's valve is open, waiting for `proven` (`timeLeft`: `provenTime` left) |
| `UT_ST_ABORT` | | `Blocked: abort` | `Abort` on: not running, a start is refused |
| `UT_ST_WARN_SETTING` | `UT_F_SETTING` | `Setting: a setting` | A setting with a safe value (see Bad settings) |
| `UT_ST_WARNING` | `UT_F_ZONE_FLOW` | `Warning: zone flow` | The zone's flow check (WARN) is raised now |
| `UT_ST_CONFIG` | `UT_F_VALVE_PUMP_TIME` | `Config: valve / pump time` | A negative valve or pump time: nothing runs |
| `UT_ST_CONFIG` | `UT_F_DEFAULT_SP` | `Config: default setpoint` | `defaultSp` negative or not a number: nothing runs |
| `UT_ST_CONFIG` | `UT_F_VALVE_DRIVE` | `Config: valve drive` | LATCH / MOTOR with no `driveTime`, or an unknown `valveDrive`: nothing runs |

## Bad settings
- **Nothing runs** (`configBad`, `Warning`; a program running ends safely: pump off, then the
  valves once it has stopped; `ZoneSp` 0): a negative `valveOverlap`, `pumpStartDelay` or
  `valveCloseDelay`, `defaultSp` negative or not a number, an unknown `valveDrive`, or
  LATCH / MOTOR with `driveTime` 0 or negative.
- **Warning, safe values:** an unknown `rainAction` (PAUSE), an unknown `flowPer` (per
  hour), `repeats` below 1 (1), a negative `maxZoneTime` (none), a negative
  `provenTime` (wait for ever); a zone with a negative
  `runTime` / `soakTime`, `volume`, `sp`, `minFlow` or `maxFlow` negative or not a number,
  or `cycles` below 1 (it runs on the safe value or is passed over).
