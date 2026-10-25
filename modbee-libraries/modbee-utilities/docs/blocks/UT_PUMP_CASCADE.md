# UT_PUMP_CASCADE — Multi-pump booster and manifold

Runs several pumps (any number) on one header to hold a pressure (or a flow):
irrigation manifolds, booster sets, town and stock-water supply. Pumps come on one
at a time as the demand rises and drop off one at a time as it falls, the work is
shared by run hours, a pump that fails hands over to the next, and a small jockey
pump can carry the low demand on its own.

Each pump keeps its own motor block, mixed freely: [UT_MOTOR](UT_MOTOR.md) for a
contactor or soft starter (fixed speed), [UT_MOTOR_VSD](UT_MOTOR_VSD.md) for a drive.
The cascade takes the **array of the pumps' motor records**, like
[UT_DUTY](UT_DUTY.md); the array size is the number of pumps. Every VSD the group runs
gets **the same speed**; fixed-speed pumps run flat out. The control loop inside is a
[UT_SPEED_CTRL](UT_SPEED_CTRL.md) (its record is `Data.ctrl`), so the pipe fill,
sleep / wake, overpressure, burst-pipe, hunting and failed-sensor handling are the same
as on a single pump.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | FALSE | Pumping wanted (a schedule, a switch, `UT_ZONE_SEQ.PumpDemand`) |
| in | `Pv` | REAL | 0.0 | The value held: the header pressure (or a flow), e.g. `UT_ANALOG_IN.Value` |
| in | `PvGood` | BOOL | TRUE | Its transmitter is healthy (`UT_ANALOG_IN.Good`) |
| in | `Flow` | REAL | 0.0 | Header flow: flow staging, high flow, low-flow sleep, flow limit (optional) |
| in | `FlowGood` | BOOL | TRUE | The flow meter is healthy |
| in | `Sp` | REAL | 0.0 | Setpoint when `ctrl.spSource := UT_SP_PIN` |
| in | `Rotate` | BOOL | FALSE | Rising edge: hand the longest-running pump over now |
| in | `Reset` | BOOL | FALSE | Rising edge: reset MANUAL protections (the loop's too) |
| out | `RunningCount` | INT | | Pumps running (any mode) |
| out | `Speed` | REAL | | The shared VSD speed, % (0 when stopped) |
| out | `Phase` | UT_SC_PHASE | | The loop's phase: IDLE, FILLING, CONTROL, BOOST, SLEEP, FALLBACK |
| out | `AtSetpoint` | BOOL | | Pv within `ctrl.atSpBand` |
| out | `Shortfall` | BOOL | | More pumps wanted than can run (none left, or `maxRunning` reached) |
| out | `Fault` | BOOL | | A trip has stopped the pumps, or the loop's settings run nothing |
| out | `Warning` | BOOL | | A warning (see the fault code) |
| inout | `Units` | ARRAY[*] OF UT_MOTOR_DATA | | The pumps' motor records (any size, any lower bound) |
| inout | `Data` | UT_PUMP_CASCADE_DATA | | Group record |

## Record `UT_PUMP_CASCADE_DATA`

### Staging
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stageBy` | UT_PC_STAGE | UT_PC_STAGE_PV | What adds and drops pumps: `UT_PC_STAGE_PV` (0, the pressure), `UT_PC_STAGE_FLOW`, `UT_PC_STAGE_PER_PUMP` (see [How it works](#staging-criteria)) |
| `stageDelay` | TIME | T#10s | Add: the need has lasted this long, **and** this long since the last start or stop command |
| `destageDelay` | TIME | T#20s | Drop: the same, for dropping |
| `addBand` | REAL | 0.3 | No VSD running: add when Pv is this far below sp |
| `dropBand` | REAL | 0.3 | No VSD running: drop when Pv is this far above sp |
| `dropSpeed` | REAL | 0.0 | PV with a VSD running: drop one when the shared speed is below this % (0 = only at the minimum speed) |
| `addPct` | REAL | 90.0 | FLOW and the jockey: add above this % of the running pumps' capacity |
| `dropPct` | REAL | 75.0 | FLOW and the jockey: drop below this % of the capacity left after the drop |
| `bepMin` / `bepMax` | REAL | 0.0 / 0.0 | PER_PUMP: keep the flow per running pump between these (the pumps' best-efficiency range) |
| `maxRunning` | INT | 0 | Most pumps running at once, Hand ones included (0 = all) |
| `failoverDelay` | TIME | T#10s | A called pump not running this long after its run command is skipped and the next one called |

### Rotation
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `rotation` | UT_ROTATE_MODE | UT_ROT_HOURS | `UT_ROT_FIXED` · `UT_ROT_EACH_START` · `UT_ROT_HOURS` · `UT_ROT_INTERVAL` |
| `fixedLead` | INT | 1 | FIXED: array index of the first pump |
| `hoursDiff` | TIME | T#1h | HOURS: a running pump with this much more run time than an idle one hands over to it (0 = no swap while running) |
| `rotateInterval` | TIME | T#24h | INTERVAL: the pump running longest hands over this often (0 = never) |

### Protection and the loop
| Field | Bit | Type | Default | Meaning |
| --- | --- | --- | --- | --- |
| `highFlow` | 8 | UT_LEVEL | TRIP · 10 s · RETRY (3, recover 5 min) · sp 0 | A burst main: `Flow` above `sp` while pumps run. **TRIP** stops every pump. sp 0 = off |
| `ctrl` | 0–7 | UT_SPEED_CTRL_DATA | | The loop: setpoint, PID, speed limits, pipe fill, sleep, overpressure (`highPv`), burst at full speed (`lowPvAtMax`), hunting, failed sensor (`pvFail`), manual speed. Every field as [UT_SPEED_CTRL](UT_SPEED_CTRL.md). **`ctrl.sp` must be set**. `ctrl.stageDelay` and the `MoreNeeded` / `LessNeeded` outputs are not used here |

`ctrl.control` chooses what the shared speed follows, as on
[UT_SPEED_CTRL](UT_SPEED_CTRL.md#control-pv-flow-or-fixed-and-the-presets): the PID on
the header pressure `Pv` (`UT_SC_CTRL_PV`, the default), the PID on the `Flow` pin
(`UT_SC_CTRL_FLOW`, setpoints `ctrl.flowSp` / `flowSpLow` / `flowSpHigh`), or a fixed
speed (`UT_SC_CTRL_FIXED`, `ctrl.fixedSpeed` / `fixedSpeedLow` / `fixedSpeedHigh`).
`ctrl.preset` picks NORMAL, LOW or HIGH: for example `ctrl.spLow` for a travelling
irrigator working near the station. `ctrl.highPv` always watches `Pv`. The value
under control is `ctrl.pv`.

### Stopping
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stopMode` | UT_PC_STOP | UT_PC_STOP_ALL_AT_ONCE | How the group stops on `Enable` FALSE or sleep: `UT_PC_STOP_ALL_AT_ONCE` (0) every pump at once; `UT_PC_STOP_STAGED` one pump at a time, less water hammer (see [Stops](#every-arrangement)). A trip always stops every pump at once |
| `stopStep` | TIME | T#3s | STAGED: the time between pump stops |

### HMI commands (act once, cleared by the block)
| Field | Meaning |
| --- | --- |
| `cmdRotate` | Hand the longest-running pump over now |
| `cmdReset` | Reset MANUAL protections, the loop's too |
| `ctrl.cmdManual` / `ctrl.cmdAuto` | The loop's manual speed (`ctrl.manualSpeed`): the called pumps run at it, the loop's protections still act, no pump is added or dropped; `cmdAuto` hands back to the loop (see [UT_SPEED_CTRL](UT_SPEED_CTRL.md#hmi)) |

### Status fields
| Field | Type | Meaning |
| --- | --- | --- |
| `stage` | INT | Duty pumps wanted (0 with `jockeyOn`: the jockey alone) |
| `jockeyOn` | BOOL | The jockey is the running stage |
| `runningCount` / `calledCount` / `availableCount` | INT | Pumps running (any mode) / called by the group / in Auto and ready |
| `capacity` | REAL | Capacity of the group's pumps running |
| `flowPerPump` | REAL | `Flow` / group pumps running |
| `speed` | REAL | The shared speed, % |
| `stageByUsed` | UT_PC_STAGE | The criterion in use (PV after a fallback) |
| `shortfall` | BOOL | As the pin |
| `configBad` | BOOL | The loop's settings are invalid: nothing runs (bit 0) |
| `wrnConfig` | BOOL | A group setting is invalid: a safe value is used (bit 10) |
| `flowBad` | BOOL | The flow signal is bad while it is used (bit 9) |
| `pvStaging` | BOOL | FLOW / PER_PUMP left the pressure short: staging on Pv until the group next starts (bit 11) |
| `fault`, `warning`, `faultCode : DWORD` | | Bits 0–7 are the loop's ([UT_SPEED_CTRL](UT_SPEED_CTRL.md#limits-and-overrides-independent-of-the-loop)): 0 settings, 1 sensor failed, 2 overpressure, 3 low at max (burst), 4 fill timeout, 5 not reaching, 6 hunting, 7 a loop setting warning. Then 8 high flow, 9 flow signal bad, 10 group setting, 11 flow staging fell back to Pv. Warnings set their bits too |
| `faultId` | UT_FAULT | The most important fault or warning by name: `UT_F_HIGH_FLOW`, `UT_F_FLOW_BAD`, `UT_F_FLOW_SHORT`, `UT_F_GROUP_SETTING`, else the loop's `faultId` (`UT_F_NO_UNITS` with an empty array) |
| `statusCode` | UT_STATUS | What the group is doing, or what holds it back (see [Status](#status)) |
| `statusText` | STRING(30) | The status in words, for a person looking at the PLC |
| `statusUnit` | DINT | The pump (array index) the status is about; one below the array's first index when none |
| `stopping` | BOOL | A STAGED stop is under way |
| `timeLeft` | TIME | The countdown that goes with the status: the add or drop delay, the failover, the next staged stop, or (where the loop's status is shown) the loop's `timeLeft`. 0 = none |
| `phaseTime` | TIME | Time in the loop's phase (`ctrl.phaseTime`) |
| `stopReason` | UT_STOP | Why the group last stopped: `UT_STOP_FAULT` for a high-flow trip, otherwise the loop's (`UT_STOP_DEMAND_ENDED` for `Enable` off, `UT_STOP_FAULT` a loop trip, `UT_STOP_SETTING` a setting, `UT_STOP_ASLEEP` asleep) |
| `lastFaultCode` / `lastFault` | DWORD / UT_FAULT | The last trip (the loop's bits and name, or bit 8 and `UT_F_HIGH_FLOW`), kept after it clears |
| `trips` | UDINT | Trips since power-up, the loop's and high flow |

### Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the group is
doing, or what holds it back. The most important reason wins: configuration > fault >
held / waiting > warning > running > idle. Where the loop's own status is the main
thing (its settings, its trips, sleep, `Enable` cycling, its warnings, pipe fill,
boost, flow limit, fallback) the loop's status and its fault (`ctrl.statusCode`, see
[UT_SPEED_CTRL](UT_SPEED_CTRL.md#status)) are shown, with the loop's `timeLeft`.
Enabled with no pump running or starting (a called pump's run command out), it always
shows a held, fault or configuration status; `UT_ST_STARTING` shows over a warning.
The pump a status is about is `statusUnit` (an array index); the counts are
`runningCount`, `calledCount` and `availableCount`, the speed `speed`, and the time
left `timeLeft`. The text is rebuilt only when the status or the fault changes. The
numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE_NOT_ENABLED` | `Idle: not enabled` | `Enable` FALSE |
| `UT_ST_IDLE_NO_DEMAND` | `Idle: no demand` | Nothing running |
| `UT_ST_STARTING` | `Starting` | Pump `statusUnit` called, not running yet; skipped if not running within `timeLeft` (the failover delay) |
| `UT_ST_RUNNING` | `Running` | Pumps running (any mode): `runningCount`, at `speed` with a VSD running |
| `UT_ST_ADDING` | `Adding a pump` | The add rule holds; the next pump after `stageDelay` (`timeLeft`) |
| `UT_ST_DROPPING` | `Dropping a pump` | The drop rule holds; the next drop (or hand-back to the jockey) after `destageDelay` (`timeLeft`) |
| `UT_ST_JOCKEY` | `Jockey running` | The jockey is the running stage |
| `UT_ST_SWAPPING` | `Swapping pumps (rotation)` | A rotation swap: the new pump (`statusUnit`) starts, then the old one stops |
| `UT_ST_STOPPING` | `Stopping` | A STAGED stop: the next pump stops in `timeLeft` |
| `UT_ST_ENABLE_CYCLE` | `Waiting: Enable must cycle` | After a MANUAL high-flow reset (unless `ctrl.restartAfterReset`) |
| `UT_ST_MAX_RUNNING` | `Waiting: max running reached` | Another pump wanted, `maxRunning` pumps on (Hand ones count) |
| `UT_ST_SHORTFALL` | `Shortfall: too few available` | More pumps wanted than can run |
| `UT_ST_WARNING` | `Warning: flow signal bad` | `UT_F_FLOW_BAD`: the flow signal is bad while it is used (FLOW / PER_PUMP staging falls back to Pv; high flow, the flow limit or low-flow sleep) |
| `UT_ST_WARNING` | `Warning: flow staging short` | `UT_F_FLOW_SHORT`: `pvStaging` (bit 11): flow staging left the pressure short, staging is on Pv |
| `UT_ST_WARNING` | `Warning: high flow` | `UT_F_HIGH_FLOW`: `highFlow` set to WARN |
| `UT_ST_WARN_SETTING` | `Setting: group setting` | `UT_F_GROUP_SETTING`: a group setting is invalid (bit 10) |
| `UT_ST_FAULT` · `UT_ST_FAULT_RETRY` · `UT_ST_FAULT_RESET` · `UT_ST_FAULT_LOCKED` | `Fault: high flow` · `Retrying: high flow` · `Latched: high flow` · `Locked: high flow` | The high-flow trip, by its reset mode (`timeLeft` while the recover time counts) |
| `UT_ST_CONFIG` | `Config: no units in array` | `UT_F_NO_UNITS`: an empty array |
| (the loop's) | e.g. `Config: setpoint`, `Fault: overpressure`, `Sleeping`, `Pipe fill`, `Running: fallback speed` | The loop's status and fault |

## Fields in each pump's motor record (`UT_MOTOR_DATA`)
| Field | Type | Written by | Meaning |
| --- | --- | --- | --- |
| `capacity` | REAL | you | The pump's flow at full speed **at the setpoint pressure** (its duty point), in the units of `Flow`. 0 = not known. Used by FLOW staging and the jockey |
| `jockey` | BOOL | you | A small pump that carries the low demand on its own |
| `isVsd` | BOOL | the motor block | TRUE on a UT_MOTOR_VSD record (set every scan), FALSE on the others |
| `grpActive`, `grpRun` | BOOL | the cascade | The group owns the pump and calls it (as UT_DUTY) |
| `grpSpeed` | REAL | the cascade | The shared speed, %. A UT_MOTOR_VSD uses it as its Auto speed **only while a group owns the record**; otherwise `AutoSpeed` as always |
| `grpRunTime` | TIME | the cascade | The pump's run time counted by the group since power-up, for HOURS rotation (every pump counts) |

`capacity` and `jockey` sit in the motor record so they travel with the pump: any
number of pumps, any array bounds, nothing to keep in step in a second array. They
cost a REAL and a BOOL per motor, and a motor that is not in a cascade ignores them.

## How it works

### Every arrangement
- `Enable` starts the loop; its `Run` starts the group with **one pump**. A pump is
  available when it is in Auto and `ready` (healthy, interlock and permissive made, not
  in its restart delay). Hand, Off, OOS and faulted pumps are skipped.
- **One start at a time.** Nothing is called while a called pump is not yet running.
  Stage delays count from the last start or stop command, so a pump that waited for
  its turn never starts in the same breath as the next one.
- **Failover.** A pump that trips or leaves Auto is released at once and the next one
  is called. A called pump not running `failoverDelay` after its run command is
  skipped (until it leaves Auto or faults and comes back, or the group next starts
  from none; skip memory for the first 32 pumps) and the next one is called. A pump
  in its restart delay is not ready, so it is never taken for a failed start.
- **maxRunning** counts pumps running in Hand. A pump put in Hand while the group is at
  the limit makes the group release one of its own.
- **Stops.** Any trip (overpressure TRIP, burst, high flow, a failed sensor with
  STOP, fill timeout) or a loop setting that runs nothing stops every pump at once: a
  fault never leaves a pump running against a closed system. `Enable` FALSE or sleep
  stops every pump at once too with `stopMode` ALL_AT_ONCE (the default). With
  `UT_PC_STOP_STAGED` the called VSDs go to `ctrl.minSpeed` and the pumps stop one at
  a time: the first at once, then one every `stopStep`, fixed-speed pumps first, then
  the jockey (`stopping`, status `UT_ST_STOPPING`). A trip during a staged stop stops the rest at
  once. `Enable` back during a staged stop keeps the pumps still running and carries
  on from them.
- **Overpressure WARN** holds the speed at the minimum and drops a pump each
  `destageDelay` while it lasts (never the last one; TRIP is the hard limit).
- **Failed sensor.** STOP: everything stops (fault). FALLBACK: one pump (a VSD if one is
  running) at `ctrl.fallbackSpeed`, the others stop. HOLD: the pumps and the speed stay
  as they are. A hunting trip keeps the pumps and runs at the fallback speed.
- **Burst.** `ctrl.lowPvAtMax` (at full speed and Pv still below half the setpoint)
  waits while another pump can still be added: the next pump is the answer first. With
  every pump in and the pressure still low, it trips. `highFlow` trips on the flow.
- **Pipe fill** (`ctrl.pipeFill`) runs with one duty pump (a VSD if available), never
  the jockey; staging starts when the fill is done.
- **Sleep.** The loop's sleep (low speed or low flow, then boost, then sleep) stops every
  pump; a pressure drop wakes the group with one pump (the jockey first).
- **Power cut.** Only the rotation's next pump in turn is kept (saved at once when it
  changes, that is when a pump is started; not for FIXED), so after frequent power cuts
  the first pump does not always lead. The run hours for HOURS (each pump's
  `grpRunTime`) start at 0, also when the motor records are `RETAIN` (equal hours go
  by the kept turn), every `grpRun` starts cleared, nothing is called on the first
  scan, and the pumps start again one at a time. The motors keep their own modes and
  restart delays.
- **Manual speed.** `ctrl.cmdManual` runs the called pumps at `ctrl.manualSpeed`, with
  the loop's protections still acting (overpressure, burst at the top speed); no pump
  is added or dropped until `ctrl.cmdAuto`.
- **Each pump's own protection.** The cascade sees only what a pump's motor record
  says: a pump whose motor trips (overload, no feedback, a drive fault) is no longer
  `ready`, so the group releases it and calls the next. A pump's hydraulic checks
  (dry run, prime, seal leak, a pump's own pressure or flow switches) live in its
  [UT_PUMP](UT_PUMP.md), which has no group link to the cascade: wire
  `UT_PUMP.Healthy` to the motor block's `Interlock`, so a pump that fails a hydraulic
  check holds its motor off, reads not ready and is replaced. Without that wire a pump
  running dry stays called.

### 1. All pumps on VSDs
Every running pump gets the same speed from the loop. A pump is added when the speed
is at its maximum and Pv is still short of sp by more than `ctrl.atSpBand` for
`stageDelay`. One is dropped at the minimum speed, or, with `dropSpeed` set, when the
speed stays below `dropSpeed` for `destageDelay`. Set `dropSpeed` a few % below the
speed the pumps settle at just after one is added (that gap is the hysteresis). With a
lot of static head that speed differs from stage to stage: use FLOW or PER_PUMP
staging there.

### 2. One VSD plus fixed-speed pumps
The VSD starts first (the first pump is always a VSD when one is available) and trims.
A fixed pump is added when the VSD is at full speed and still short, and dropped first
when the VSD is at its minimum (or below `dropSpeed`): the VSD is the last to go. If the
VSD is lost, the fixed pumps carry on on the pressure bands (arrangement 3).

### 3. All fixed-speed
No speed: pumps are added when Pv stays `addBand` below sp for `stageDelay` and dropped
when it stays `dropBand` above sp for `destageDelay`. Make the bands wider than the
pressure step one pump makes, or the set will cycle (the delays only slow it).

### 4. Mixed sizes and a jockey
Give each pump its `capacity`. With FLOW staging the running capacity is the sum of the
pumps running, so a small and a large pump count for what they are. Mark the small
pump `jockey := TRUE`: it starts first and runs alone. When it cannot keep up (`Flow`
above `addPct` % of its capacity, or the pressure short on the PV rule) a duty pump
starts, and the jockey stops once the duty pump runs. When one duty pump is left and
the demand falls (`Flow` below `dropPct` % of the jockey's capacity, or the PV drop rule
when its capacity is 0), the jockey starts again and the duty pump stops once it
runs. A jockey that has to hand over on pressure while its flow is below its capacity
is not doing its job (air-locked, worn): it is skipped until the group next starts.
Several pumps may be jockeys: they rotate among themselves, one at a time.

### Staging criteria
| `stageBy` | Add when | Drop when |
| --- | --- | --- |
| `UT_PC_STAGE_PV` | With a VSD running: at full speed and still short. Without: Pv `addBand` below sp | With a VSD running: at the minimum speed or below `dropSpeed`. Without: Pv `dropBand` above sp |
| `UT_PC_STAGE_FLOW` | `Flow` > `addPct` % of the running capacity | `Flow` < `dropPct` % of the capacity left after the drop |
| `UT_PC_STAGE_PER_PUMP` | `Flow` per running pump > `bepMax` (and would stay above `bepMin` with one more) | `Flow` per pump < `bepMin` (and would stay below `bepMax` with one fewer) |

FLOW and PER_PUMP also add a pump on the PV rule: the pressure is never left short
while a pump is free. If that happens, the flow settings are wrong (a capacity too
high, `bepMax` too high), so the group warns (`pvStaging`, bit 11) and stages on the
pressure until it next starts from none. They fall back to PV with a warning while the
flow meter is bad (`flowBad`, bit 9), or while their settings are not usable (a duty
pump with no `capacity`, `bepMax` not above `bepMin`: `wrnConfig`).

### Rotation (even wear)
| `rotation` | Starts | Stops first | While running |
| --- | --- | --- | --- |
| `UT_ROT_FIXED` | From `fixedLead`, in array order (a lead in its restart delay is waited for, not passed over) | The last one started | — |
| `UT_ROT_EACH_START` | The next pump in turn after the last one started | The one running longest | — |
| `UT_ROT_HOURS` (default) | The fewest run hours | The most run hours | A running pump `hoursDiff` ahead of an idle one hands over |
| `UT_ROT_INTERVAL` | As EACH_START | As EACH_START | Every `rotateInterval` the one running longest hands over |

Equal run hours is the answer to "start at random so one pump doesn't do all the
work": the pump with the fewest hours always starts next. Run hours are counted inside
the block (first 32 pumps) and start again at 0 after a power cut (equal hours: the
next in turn, which is kept). A swap (HOURS,
INTERVAL, `Rotate`, `cmdRotate`) is between pumps of the same kind (VSD for VSD, fixed
for fixed, jockey for jockey), waits while a pump is to be added or dropped, starts the
new pump first and stops the old one once it runs; at `maxRunning` the old one stops
first. In arrangement 2 the VSD runs whenever the group runs (it is the trim pump).

## Wiring
The cascade before the motors, each in its own unconditional rung. `AutoCmd` must be
wired (the editor checks it) but is not used while the group owns the motor.

### All on VSDs (arrangement 1)
```iecst
VAR Pumps : ARRAY[1..6] OF UT_MOTOR_DATA; Booster : UT_PUMP_CASCADE; Cfg : UT_PUMP_CASCADE_DATA;
    P : ARRAY[1..6] OF UT_MOTOR_VSD; PV : ARRAY[1..6] OF UT_MOTOR_VSD_DATA; END_VAR
Cfg.ctrl.sp := 5.0;                       (* bar *)
Cfg.ctrl.minSpeed := 45.0;
Cfg.dropSpeed := 70.0;
Booster(Enable := SystemOn, Pv := Header.Value, PvGood := Header.Good, Units := Pumps, Data := Cfg);
P[1](AutoCmd := FALSE, Feedback := P1_Running, DriveReady := P1_Ready, DriveFault := P1_Fault,
     Data := Pumps[1], Vsd := PV[1]);
P1_RunRelay := P[1].Run;
P1_SpeedAO := P[1].SpeedRefRaw;           (* every drive gets the same reference *)
(* ... P[2] to P[6] the same ... *)
```

### One VSD plus contactors and soft starters (arrangement 2)
```iecst
P1(AutoCmd := FALSE, Feedback := VSD1_Running, DriveFault := VSD1_Fault, Data := Pumps[1],
   Vsd := P1Vsd);                                                                           (* UT_MOTOR_VSD *)
P2(AutoCmd := FALSE, Feedback := K2_Aux, Overload := NOT P2_OL_NC, Data := Pumps[2]);       (* UT_MOTOR, contactor *)
P3(AutoCmd := FALSE, Feedback := SS3_TopOfRamp, DriveFault := SS3_Fault, Data := Pumps[3]); (* UT_MOTOR, soft starter *)
K2_Coil := P2.Run;
SS3_Run := P3.Run;
```
Nothing to set for the trim pump: the block knows `Pumps[1]` is a VSD (`isVsd`) and
starts it first.

### All fixed-speed (arrangement 3)
```iecst
Cfg.addBand := 1.0;                       (* add below 4.0 bar *)
Cfg.dropBand := 1.5;                      (* drop above 6.5 bar *)
Cfg.ctrl.sleep.enable := TRUE;
Cfg.ctrl.sleep.flow := 5.0;               (* sleep below 5 m3/h *)
Booster(Enable := SystemOn, Pv := Header.Value, Flow := FlowMeter.Value, FlowGood := FlowMeter.Good,
        Units := Pumps, Data := Cfg);
```

### Mixed sizes with a jockey (arrangement 4)
```iecst
Pumps[1].jockey := TRUE;                  (* the small pump *)
Pumps[1].capacity := 12.0;                (* m3/h at the setpoint pressure *)
FOR k := 2 TO 6 DO Pumps[k].capacity := 80.0; END_FOR;
Cfg.stageBy := UT_PC_STAGE_FLOW;
Booster(Enable := SystemOn, Pv := Header.Value, Flow := FlowMeter.Value, FlowGood := FlowMeter.Good,
        Units := Pumps, Data := Cfg);
```

## Invalid settings
- **Runs nothing** (`Fault`, `configBad`, bit 0): the loop's own (`ctrl.sp` 0, not a
  number or infinite, `ctrl.minSpeed` above `ctrl.maxSpeed` and the rest listed in
  [UT_SPEED_CTRL](UT_SPEED_CTRL.md#invalid-settings)).
- **Warning, safe value used** (`wrnConfig`, bit 10, `Warning`): `stageDelay`,
  `destageDelay` or `failoverDelay` negative → T#10s / T#20s / T#10s; `addBand` or
  `dropBand` negative, not a number or infinite → 0.3; `dropSpeed` outside 0..100 or not a
  number → 0 (the minimum speed only); `addPct` / `dropPct` not in 0 < dropPct < addPct ≤
  100 → 90 / 75; `maxRunning` negative → 1 (the safe side); an unknown `rotation` → HOURS,
  an unknown `stageBy` → PV; FIXED with `fixedLead` not a pump → the first; `hoursDiff` or
  `rotateInterval` negative → 0 (no swap); `stopStep` negative → T#3s; an unknown
  `stopMode` → all at once; PER_PUMP with `bepMax` not above `bepMin` →
  PV staging; FLOW with a duty pump's `capacity` 0 → PV staging; a `capacity` negative, not
  a number or infinite → 0; every pump a jockey (the jockey runs alone); `highFlow` with a
  bad setpoint, deadband or time. The loop's own warnings are its bit 7.
- **Signals:** Pv not a number or infinite (or `PvGood` FALSE) is a failed sensor (the
  loop's `pvFail`). Flow not a number or infinite (or `FlowGood` FALSE) while it is used
  gives `flowBad` (bit 9) and PV staging; `highFlow`, low-flow sleep and the flow limit
  then ignore it.
