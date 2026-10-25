# modbee-utilities

Ready-made IEC 61131-3 function blocks for OpenPLC: motors, pumps, valves,
signals, alarms, totals and sequences. Each block does one job the way a good
panel builder would wire it, with the protections, modes and fault handling already
in place. They work from Ladder, FBD and Structured Text (ST).

**Hardware:** an ESP32-S3 (such as the ModBee Node) or anything more powerful,
including OpenPLC Runtime v4 on a Raspberry Pi or PC. The blocks are too big for
small boards such as the Arduino Uno and Mega.

## How to use a block

1. **Drop it in.** In Ladder or FBD, give every library block its own rung with
   nothing in series in front of it. A block whose rung is false doesn't run, and
   its outputs freeze. See [ladder-rules.md](ladder-rules.md).
2. **Wire the pins.** The first input is the main signal; the first output is the
   main result. Unwired pins have safe defaults.
3. **Set the record.** Each block has a record (`Data`) holding its settings, HMI
   commands and status. Every setting has a working default, so you only change
   what the site needs, either from the HMI or in code.

Each block's page lists its pins first, then the record, how it works and an example.

---

## Pick a block

### Motors

**[UT_MOTOR](blocks/UT_MOTOR.md)**: runs and protects one motor on a contactor
or soft starter, with Hand/Off/Auto, overload, thermistor, current and feedback checks.
- *Use it when:* a pump, fan, conveyor or heater bank is started direct on line, or
  by a soft starter, and you have a run relay and a run feedback.
- *Not for:* a VSD (use UT_MOTOR_VSD), a reversing, star-delta or two-speed starter
  (use the blocks below).

**[UT_MOTOR_VSD](blocks/UT_MOTOR_VSD.md)**: runs a variable speed drive over
hard-wired I/O (run, running, ready and fault relays, speed reference and feedback),
with speed limits, ramps, a skip band, a hand speed and a drive-reset pulse.
- *Use it when:* the motor is on a VSD and you set the speed from the PLC.
- *Not for:* deciding the speed. To hold a pressure, flow or level, put
  [UT_SPEED_CTRL](blocks/UT_SPEED_CTRL.md) in front of it.

**[UT_MOTOR_REV](blocks/UT_MOTOR_REV.md)**: forward and reverse contactors that are
never on together, with a dead time so the motor stops before it changes direction.
- *Use it when:* a gate, screw conveyor, roller door or mixer needs to run both ways.

**[UT_MOTOR_SD](blocks/UT_MOTOR_SD.md)**: main, star and delta contactors, with a
timed (or current-confirmed) star stage, and star and delta never on together.
- *Use it when:* a larger motor is started star-delta to cut the starting current.

**[UT_MOTOR_2SPD](blocks/UT_MOTOR_2SPD.md)**: low and high speed contactors that are
never on together, with an optional star-bridge contactor (Dahlander) and an
optional "start in low first".
- *Use it when:* a two-speed fan or pump (Dahlander or separate windings).

**[UT_DUTY](blocks/UT_DUTY.md)**: shares "I need N running" across a group of motors,
with rotation, failover to a standby, staggered starts and exercise runs for idle units.
- *Use it when:* duty/assist/standby fans, compressors, blowers, heater banks or
  cooling towers.
- *Not for:* a pump station on level or pressure (use UT_PUMP_STATION, which adds
  the level logic and floats), or a VSD booster set (UT_PUMP_CASCADE).

**[UT_STARTS](blocks/UT_STARTS.md)**: counts starts and stops a motor starting too
often: a maximum per hour, a minimum time between starts, and a longer wait after a
failed start. Its `StartPermit` goes to the motor's `Permissive`.
- *Use it when:* a motor or pump could short-cycle (a float near its switch point,
  an undersized tank) and the motor maker gives a start limit.

**[UT_ROTATION](blocks/UT_ROTATION.md)**: watches a proximity sensor on a shaft, pulley
or target wheel for a stall, underspeed (belt slip) and overspeed, and measures the speed
in rpm, rev/s, or as a belt / chain line speed in m/min or m/s.
- *Use it when:* a conveyor, elevator or crusher needs belt-slip or stall protection.
  Wire `Healthy` to the motor's `Interlock`.

### Pumps and pump stations

The pump blocks sit **on top of** a motor block. The motor block keeps Hand/Off/Auto
and the electrical protection; the pump block decides when to run and protects the pump.

**[UT_PUMP](blocks/UT_PUMP.md)**: decides when one pump runs (on demand, empty on
level, fill on level, or timed on/off) and protects it with whatever is fitted:
pressure, flow and suction, each a switch, a transmitter, both or nothing. It also
names the likely cause (blocked, burst, no lift, suction low).
- *Use it when:* any pump: a single sump pump on a float, a bore pump filling a tank,
  a stock-water pump with dry-run protection, or each pump in a station.
- *Not for:* sharing work between pumps (add UT_PUMP_STATION) or holding a pressure
  with a VSD (add UT_SPEED_CTRL).

**[UT_PUMP_STATION](blocks/UT_PUMP_STATION.md)**: runs any number of pumps from one
level or pressure signal: staged start and stop points, duty rotation, failover,
backup floats, a check that the transmitter agrees with the high float, sump
cleaning and inflow figures.
- *Use it when:* a sump or wet well with 2–6 pumps and a level transmitter plus
  backup floats, or a reservoir or fixed-speed booster that fills on a level or
  pressure.
- *Not for:* fans and compressors with no level (UT_DUTY), or pumps on VSDs holding a
  pressure (UT_SPEED_CTRL, UT_PUMP_CASCADE).

**[UT_SPEED_CTRL](blocks/UT_SPEED_CTRL.md)**: holds a pressure, flow, level or
temperature by changing a drive's speed. It fills the pipe gently first, sleeps when
demand stops, wakes on a pressure drop, and guards against a badly tuned loop, a
burst pipe, overpressure and a failed sensor.
- *Use it when:* an irrigation or stock-water pump on a VSD, a constant-pressure
  supply, a borehole pump, or a duct-pressure or cooling-tower fan.
- *Not for:* starting extra pumps by itself. It gives `MoreNeeded` / `LessNeeded`
  signals; a multi-pump set needs a group block (UT_PUMP_CASCADE).

**[UT_PUMP_CASCADE](blocks/UT_PUMP_CASCADE.md)**: a multi-pump manifold or booster set.
The pumps are an array of motor records, any mix of VSD, soft starter and contactor;
every VSD gets the same speed. It stages pumps in and out one at a time on pressure,
flow or flow per pump, shares the work by run hours, hands over from a failed pump, and
lets a small jockey pump carry the low demand. The pipe fill, sleep, overpressure,
burst and failed-sensor handling are UT_SPEED_CTRL's.
- *Use it when:* a booster set or irrigation manifold with several pumps sharing one
  header, on VSDs, contactors, soft starters or a mix, with or without a jockey pump.
- *Not for:* a sump or wet well on level (UT_PUMP_STATION), or fans and compressors
  (UT_DUTY).

**[UT_DOSE](blocks/UT_DOSE.md)**: doses chemical, fertiliser or product: a batch to a
target (with a learned early stop), in proportion to the water flow (speed or stroke
pulses to the dosing pump), or timed on/off.
- *Use it when:* fertigation, chlorination, stock-water additives, tank filling to a
  quantity or irrigation shots.

**[UT_MIXER](blocks/UT_MIXER.md)**: runs a stirrer, agitator or mixer before the pump
starts (holding the pump through its `StartHold`), with the pump, for a while after
it, and on a timed on/off cycle. A mixer that can't run never holds the pump.
- *Use it when:* an effluent sump or tank must be mixed before and while it is pumped.

### Valves

**[UT_VALVE](blocks/UT_VALVE.md)**: opens and closes a two-position valve, cylinder or
damper and checks its limit switches. It covers spring return (one coil), double
solenoid held, bistable (pulsed) and motorised open/close.
- *Use it when:* an on/off valve or cylinder: an irrigation solenoid, a tank inlet,
  an actuated butterfly valve, a pneumatic gate.
- *Not for:* a third position (UT_VALVE_3POS) or a valve set to a percentage
  (UT_VALVE_MOD or UT_VALVE_FLOAT).

**[UT_VALVE_3POS](blocks/UT_VALVE_3POS.md)**: three positions: a diverter A / closed / B,
a spring-centred double solenoid, three coils, or a motorised valve with a mid position.
- *Use it when:* a 3-way diverter (to tank A or tank B), or a cylinder with a centre stop.

**[UT_VALVE_MOD](blocks/UT_VALVE_MOD.md)**: drives a valve or damper that has a
positioner (4–20 mA or 0–10 V demand), with optional position feedback.
- *Use it when:* the actuator takes an analog signal, usually after a `PID`.
- *Not for:* an actuator with only open and close contacts (UT_VALVE_FLOAT).

**[UT_VALVE_FLOAT](blocks/UT_VALVE_FLOAT.md)**: positions an actuator that has only
raise and lower contacts, estimating where it is from the run time (feedback and end
switches are used if fitted).
- *Use it when:* an HVAC mixing valve, an irrigation valve or a damper with a
  3-wire floating actuator and no positioner.

### Signals and measurements

| Block | What it does | Use it when |
| --- | --- | --- |
| [UT_ANALOG_IN](blocks/UT_ANALOG_IN.md) | Scales a raw analog reading to engineering units, spots a failed transmitter or broken wire (NAMUR NE43 for 4–20 mA), filters it and reports quality | Any 4–20 mA or 0–10 V transmitter: level, pressure, flow, temperature |
| [UT_SCALE](blocks/UT_SCALE.md) | Plain linear scaling, no record | A quick conversion where you don't need fault handling |
| [UT_DIGITAL_IN](blocks/UT_DIGITAL_IN.md) | Debounces a switch or float, alarms on it, spots chatter, and can simulate it | A float, pressure switch or alarm contact you want to watch properly |
| [UT_DEBOUNCE](blocks/UT_DEBOUNCE.md) | On and off delay filter | Just cleaning up a bouncing contact; use UT_DIGITAL_IN if you also want the alarm and chatter check |
| [UT_ANALOG_OUT](blocks/UT_ANALOG_OUT.md) | Turns a % or engineering value into the raw output, with limits, a rate limit, a hand value and a set value on interlock | A speed reference or valve demand on an analog output card |
| [UT_FILTER](blocks/UT_FILTER.md) | Smooths a noisy value (low-pass, moving average or block average) | A level with waves, a pulsing flow, per-minute averages for logging |
| [UT_RAMP](blocks/UT_RAMP.md) | Moves an output toward a target at a set rate | Soft speed changes, gentle valve moves, heating setpoint ramps |
| [UT_LINEARISE](blocks/UT_LINEARISE.md) | Converts through a table of points with straight lines between | Odd-shaped tank strapping tables, V-notch weirs and flumes, pump curves |
| [UT_VESSEL](blocks/UT_VESSEL.md) | Level to volume, percent and mass for standard shapes (vertical, cone-bottom silo, horizontal, rectangular, sphere) | Showing tank or silo contents; for odd shapes use UT_LINEARISE |
| [UT_SIGNAL_SELECT](blocks/UT_SIGNAL_SELECT.md) | Combines two or three transmitters into one trusted value, drops bad ones, alarms when they disagree | Duplicate level or pressure transmitters on a critical measurement |
| [UT_LIMIT](blocks/UT_LIMIT.md) | Checks a value against HH, H, L and LL, each with its own delay, response and reset | High and low alarms or trips on any analog value |
| [UT_RATE](blocks/UT_RATE.md) | Measures how fast a value changes and alarms if it rises or falls too fast | Wet-well level rise, a temperature climb, pressure decay in a leak test |
| [UT_UNIT_CONV](blocks/UT_UNIT_CONV.md) | Converts pressure, flow, volume, temperature and length units (bar ↔ psi ↔ kPa, L/s ↔ m³/h, °C ↔ °F); a function, with UT_UNIT_OK to check a pair | Showing a value in the units a client or a spec sheet uses |
| [UT_IO_MAP_IN](blocks/UT_IO_MAP_IN.md) | Connects input terminals (board, I2C module, field bus or remote value) to named functions from settings, with NC, debounce, a fail-safe value when a module or channel is lost, and timed commissioning forces | Re-wiring a site, or moving an input to an I2C or remote module, should be a setting, not a program change |
| [UT_IO_MAP_OUT](blocks/UT_IO_MAP_OUT.md) | Connects named output functions to output terminals from settings, turns spare outputs off, says whether each output reached the field, and allows timed forces only while the system is Off | The same for relays and analog outputs; a hard trip on `block` keeps an output off even when forced |

### Timers and logic

| Block | What it does | Use it when |
| --- | --- | --- |
| [UT_TOGGLE](blocks/UT_TOGGLE.md) | One press on, the next press off | A single pushbutton for lights or a manual run |
| [UT_FLASHER](blocks/UT_FLASHER.md) | On/off pulse generator | A flashing lamp, a pulsing horn, an "every 10 minutes" trigger |
| [UT_TONR](blocks/UT_TONR.md) | A `TON` that keeps its time when the input drops, then carries on (cleared at a power cut) | Totting up how long a condition has lasted over several goes |
| [UT_COUNTDOWN](blocks/UT_COUNTDOWN.md) | Time left on any timer (a function) | Showing "time remaining" on an HMI |
| [UT_TIME_SPLIT](blocks/UT_TIME_SPLIT.md) | A duration as days, hours, minutes, seconds, or as text | Showing run time or time left on an HMI |
| [UT_TIME_TEXT](blocks/UT_TIME_TEXT.md) | A duration as short text: `1 h 20 m`, `42 m`, `35 s` (a function) | Showing a block's `timeLeft` on a simple display, or in your own texts |
| [UT_TIME_BUILD](blocks/UT_TIME_BUILD.md) | Days, hours, minutes and seconds into a TIME (a function) | Letting an operator enter "2 h 30 min" as separate numbers |
| [UT_LOCAL_TIME](blocks/UT_LOCAL_TIME.md) | UTC to local time with daylight saving (NZ, AU, EU, US rules; a function) | Showing site time on an HMI, local-time schedules and reports |
| [UT_SCHEDULE](blocks/UT_SCHEDULE.md) | Weekly time windows on chosen days, with an operator override | Irrigation start times, lighting, off-peak pumping |
| [UT_TWO_POINT](blocks/UT_TWO_POINT.md) | On/off control with a gap between on and off points (like a thermostat) | Filling or emptying a tank, heating or cooling, without chatter |
| [UT_HOA](blocks/UT_HOA.md) | Hand/Off/Auto (from the HMI or a selector switch) for an output with no block of its own | Lights, heaters, solenoids, a whole system |
| [UT_INTERLOCK](blocks/UT_INTERLOCK.md) | Gathers every "must be healthy" condition into one OK signal, records which one dropped first, and allows keyed bypasses | Pull cords, guards and upstream-running checks feeding a motor's `Interlock` or `Permissive` |

### Plant mode, commands and settings

| Block | What it does | Use it when |
| --- | --- | --- |
| [UT_SYSTEM_MODE](blocks/UT_SYSTEM_MODE.md) | The plant's Off / Manual / Auto with a choice of auto programs, local / remote, and a manual run while a run request is held | Any site with a plant-wide mode on top of its devices: an effluent system, an irrigation scheme, a water treatment plant |
| [UT_CMD](blocks/UT_CMD.md) | Takes commands from two masters (the panel HMI and SCADA), each writing its own variables, with local / remote, stop wins, and refusals counted | A device commanded from both an HMI and SCADA, or by a SCADA that rewrites its values every poll |
| [UT_SETTING_CHECK](blocks/UT_SETTING_CHECK.md) | Takes a setting written by an HMI or SCADA only if it is sensible (min, max, above or below a related setting), else keeps the old one and says why; UT_SETTING_ARRAY for a list | Setpoints and levels operators can change: start / stop levels, pressures, times |

**UT_HOA or UT_MODE_SELECT?** UT_HOA gives you a mode **and** switches the output.
UT_MODE_SELECT only works out the mode (including Out of service); use it when you
are writing your own device logic. Motors and valves already have it built in, so
they need neither.

### Counting and totals

| Block | What it does | Use it when |
| --- | --- | --- |
| [UT_TOTALISER](blocks/UT_TOTALISER.md) | Totals from pulses, a fast counter, a 4–20 mA flow, a meter's own register, or run time × rated flow. Hour, day and user totals, a batch total, a rate, and 15-minute interval records for the IoT platform | Water take, effluent volume, energy, production counts, compliance metering |
| [UT_RUN_HOURS](blocks/UT_RUN_HOURS.md) | Run hours (total, today, yesterday) kept over a power cut, with a service-due flag | Pump, motor or filter servicing by hours |
| [UT_STATS](blocks/UT_STATS.md) | Minimum, maximum and average per period, for this period and the last | Daily figures for reports, dashboards and IoT uploads |

UT_STARTS (start counts) is under [Motors](#motors).

### Alarms and reporting

| Block | What it does | Use it when |
| --- | --- | --- |
| [UT_ALARM](blocks/UT_ALARM.md) | One managed alarm: on and off delays, acknowledge, latching, shelving, suppression, priority and counts | Any condition an operator should see and acknowledge |
| [UT_ANNUNCIATOR](blocks/UT_ANNUNCIATOR.md) | Horn and lamp for a group of alarms: fast flash and horn for new, steady when acknowledged, slow flash when cleared but not acknowledged; first-out; silence and lamp test | A panel with a horn and alarm beacon |
| [UT_ALARM_BEACON](blocks/UT_ALARM_BEACON.md) | Flashes the number of each active alarm in turn on one lamp | A site with one fault lamp and no HMI |
| [UT_ALARM_TABLE](blocks/UT_ALARM_TABLE.md) | Every alarm of a site in one array, one row each: on and off delays, warn or trip, clears by itself, latched or retry-then-lockout, acknowledge, siren with silence and re-arm, beacon, and one status line naming the first alarm | A site that wants all its alarms, the horn and the beacon from one block, with the alarm words kept in the HMI |
| [UT_MSG_QUEUE](blocks/UT_MSG_QUEUE.md) | One HMI text line for the whole site: a ticker of new status messages (QUEUE), or each device's current problem in turn (ACTIVE). It keeps the status codes and gives the words of the one on display; you size its buffer | Showing every device's status on one screen line |
| [UT_EVENT_LOG](blocks/UT_EVENT_LOG.md) | The last N trips, stops and end reasons (as codes) with their time, newest first; optionally kept over a power cut | "What happened overnight" on a remote site, also while comms were down |
| [UT_REPORT](blocks/UT_REPORT.md) | Decides when a value is worth sending: changed by a deadband, quality changed, or a heartbeat time has passed, with a minimum gap | Publishing over a cellular link without flooding it |
| [UT_REPORT_ARRAY](blocks/UT_REPORT_ARRAY.md) | UT_REPORT for a whole list of values in one block, each with its own settings | A site sending dozens of metrics to SCADA or the IoT platform |
| [UT_WATCHDOG](blocks/UT_WATCHDOG.md) | Raises `CommsFail` when a heartbeat or counter stops changing, and makes a heartbeat for the other end | Checking a remote PLC, Modbus device or MQTT link is still alive |
| [UT_LINK_SUPERVISOR](blocks/UT_LINK_SUPERVISOR.md) | Gets a dead link back by itself: modem restart, modem power cycle, one controlled reboot, then retries further apart; reboots limited per day and never in a loop | A remote site on a cellular modem that must come back online unattended |

### Sequencing

**[UT_SEQUENCER](blocks/UT_SEQUENCER.md)**: starts a chain of machines in order, each
waiting for the one before to prove it's running, and stops them in reverse. If one
drops out, everything feeding it stops at once (cascade stop). It can restart
automatically after a fault, with a pre-start siren.
- *Use it when:* conveyors, crushers and screens that must start downstream-first.
- *Not for:* timed recipes (UT_STEP_SEQ).

**[UT_STEP_SEQ](blocks/UT_STEP_SEQ.md)**: runs a recipe of steps, each switching a set
of outputs for a time and/or until a condition is met. Steps can jump and loop, and a
stop goes through a safe end step (for example, drain).
- *Use it when:* filter backwash, dairy vat or CIP wash, tank fill-mix-drain.
- *Not for:* a chain of machines with run feedbacks (UT_SEQUENCER).

**[UT_ZONE_SEQ](blocks/UT_ZONE_SEQ.md)**: runs irrigation or wash-down zones one after
another, by time or by volume. It opens the right valve, calls the pump, sets each
zone's pressure, and overlaps valves so the pump never deadheads. It also does cycle
and soak, rain hold and a flow check per zone.
- *Use it when:* irrigation blocks, pivots, wash-down stations or effluent spreading.

**[UT_RUN_LIMIT](blocks/UT_RUN_LIMIT.md)**: one run by time, by volume (whichever
first), or for as long as a remote signal is held, with pauses while the pump is not
running, and why it ended (`Done`, `Stopped: low level`), with the time and volume
it ran.
- *Use it when:* an effluent or irrigation run, filling a trough, flushing a line,
  running a generator for a set time, a SCADA schedule that holds a run signal.
- *Not for:* several zones in turn (UT_ZONE_SEQ) or chemical batches (UT_DOSE).

**[UT_IRR_DEFER](blocks/UT_IRR_DEFER.md)**: says when not to irrigate and why: rain,
wet soil, a lost rain or soil sensor, or a manual or remote defer, with an on delay
and a clear delay while the soil drains. `ToStorage` sends the effluent to storage
meanwhile.
- *Use it when:* effluent or irrigation runs must stop in wet weather: `Defer` to
  UT_ZONE_SEQ's `RainHold`, or through `NOT` to UT_RUN_LIMIT's `Permit`.

**[UT_PULSE_SEQ](blocks/UT_PULSE_SEQ.md)**: pulses a row of outputs one at a time,
never two together, continuously or on demand.
- *Use it when:* dust-collector jet-pulse cleaning on high differential pressure,
  irrigation flush valves, staged heaters.

### Building blocks

The bigger blocks are built from these. You'll rarely need them directly, but each
one works on its own.

| Block | What it does | Use it directly when |
| --- | --- | --- |
| [UT_PROTECT](blocks/UT_PROTECT.md) | One protection: delay, response (off, warn, trip) and reset mode (also as the function UT_PROT_RUN) | You have your own condition that should warn or stop something |
| [UT_LEVEL_CHECK](blocks/UT_LEVEL_CHECK.md) | One alarm level with a setpoint and deadband | A single high or low check; UT_LIMIT is four of these |
| [UT_MEAS_CHECK](blocks/UT_MEAS_CHECK.md) | HH, H, L and LL for a measurement that may be a switch, a transmitter, both or nothing | Your own equipment block that must cope with whatever is fitted on site |
| [UT_MODE_SELECT](blocks/UT_MODE_SELECT.md) | Off / Hand / Auto / Out of service from the HMI or a selector, with what happens after a power cut and a forced Off | Your own device logic that needs a mode (see UT_HOA above) |
| [UT_STATUS_TEXT](blocks/UT_STATUS_TEXT.md) | A status and its fault in words: `Latched: overload` (a function), and UT_STATUS_KIND, its kind (normal, held, warning, fault, configuration) | Your own block's status line, or an HMI colour from a status code |
| [UT_STOP_TEXT](blocks/UT_STOP_TEXT.md) | Why a run ended, in words: `Stopped: interlock` (a function) | Showing a `stopReason` on a simple display |
| [UT_RESET_TEXT](blocks/UT_RESET_TEXT.md) | How a trip will clear, as the end of a fault text: `, auto reset in 25 s` (a function) | A fault line of your own on a simple display |
| [UT_MOTOR_CORE](blocks/UT_MOTOR_CORE.md) | Everything the motor blocks share (two functions) | Building a new kind of motor starter |
| [UT_VALVE_CORE](blocks/UT_VALVE_CORE.md) | Everything the valve blocks share (two functions) | Building a new kind of valve block |
| [UT_IO_FORCE_RUN](blocks/UT_IO_FORCE_RUN.md) | One commissioning force slot of the IO maps: start, time-out, release (a function) | Never: UT_IO_MAP_IN and UT_IO_MAP_OUT call it |

---

## Common patterns

**Sump pump station.** A level transmitter goes through
[UT_ANALOG_IN](blocks/UT_ANALOG_IN.md) into [UT_PUMP_STATION](blocks/UT_PUMP_STATION.md),
with the high and low floats on its `HighFloat` and `LowFloat` pins. Each pump has a
[UT_PUMP](blocks/UT_PUMP.md) (one element of the station's pump array) driving a
[UT_MOTOR](blocks/UT_MOTOR.md): pump `RunCmd` to motor `AutoCmd`, pump `Healthy` to
motor `Interlock`. If the transmitter fails or disagrees with the high float, the
station runs on the floats and timers. Give each pump's `Demand` the high float, so
the pumps still run on it if the station block ever stops. Add
[UT_RUN_HOURS](blocks/UT_RUN_HOURS.md) and [UT_STARTS](blocks/UT_STARTS.md) per motor,
and [UT_ANNUNCIATOR](blocks/UT_ANNUNCIATOR.md) for the panel horn and beacon.

**Pressure booster.** A pressure transmitter feeds
[UT_SPEED_CTRL](blocks/UT_SPEED_CTRL.md). Its `Run` goes to the pump's `Demand`
([UT_PUMP](blocks/UT_PUMP.md)), the pump's `RunCmd` to the drive's `AutoCmd`
([UT_MOTOR_VSD](blocks/UT_MOTOR_VSD.md)), and `Speed` to the drive's `AutoSpeed`. It
fills the main gently, holds the pressure, and sleeps at no demand. For several pumps
on one header, [UT_PUMP_CASCADE](blocks/UT_PUMP_CASCADE.md) stages them in and out. A fixed-speed set
on pressure switch points can use [UT_PUMP_STATION](blocks/UT_PUMP_STATION.md) in FILL mode.

**Irrigation zones.** [UT_SCHEDULE](blocks/UT_SCHEDULE.md) starts
[UT_ZONE_SEQ](blocks/UT_ZONE_SEQ.md) at the set times. The zone sequencer opens each
zone valve, sends `PumpDemand` and the zone's pressure (`ZoneSp`) to UT_SPEED_CTRL
(above), and holds for rain. A flow meter on `Flow` lets zones run by volume and
catches a blocked dripper line or a burst lateral. A
[UT_TOTALISER](blocks/UT_TOTALISER.md) on the same meter gives daily and per-run
totals, and [UT_DOSE](blocks/UT_DOSE.md) in flow-paced mode can add fertiliser.

**Compliance water metering.** Put the meter into
[UT_TOTALISER](blocks/UT_TOTALISER.md) with the right method: `REGISTER` if the meter
keeps its own total (nothing is lost while the PLC is off), `PULSE` or `COUNT` if the
PLC counts pulses (then set a short `saveEvery`, for example 1 minute). Wire the
real-time clock to `Clock`. Every 15 minutes the block writes an interval record
(volume, end time, total and a sequence number that shows a missed record) and pulses
`IntervalDone`: publish the record on that pulse. The IoT platform stores the
history. NZ rules need 15-minute records, sent daily, for takes of 5 L/s or more.
[UT_WATCHDOG](blocks/UT_WATCHDOG.md) can watch the link.

**Conveyor or crusher chain.** Each machine is a [UT_MOTOR](blocks/UT_MOTOR.md) (or
[UT_MOTOR_SD](blocks/UT_MOTOR_SD.md) for the big ones). [UT_SEQUENCER](blocks/UT_SEQUENCER.md)
has one step per machine in start order (the last conveyor first, the feeder last):
each step's `cmd` goes to the motor's `AutoCmd`, and the motor's `Running` and
`Ready` come back to the step. If a conveyor stops, everything feeding it stops at
once. Pull cords and guards go through [UT_INTERLOCK](blocks/UT_INTERLOCK.md) to each
motor's `Interlock`, and [UT_ROTATION](blocks/UT_ROTATION.md) catches belt slip. Wire
the e-stop healthy signal, inverted, to `Abort`, and `Restarting` to a pre-start siren.

---

## How every block behaves

The full rules are in [conventions.md](conventions.md). The short version:

- **Modes: Off, Hand, Auto** (and Out of service on motors and valves). Everything
  starts in **Off**, so a freshly loaded program does nothing until someone chooses.
  By default the mode is kept over a power cut; a device's `powerUp` setting can
  bring it back Off instead. A motor in Auto restarts by itself once its
  restart delay has run (5 s by default, counted from power-up, so motors come back
  one after another). A motor in Hand needs a fresh start press, and a UT_HOA output
  left in Hand comes back off.
- **Inputs are TRUE = active.** A fault input is TRUE when tripped, a float TRUE when
  it signals. There is no "NC" setting: wire a normally-closed contact through `NOT`
  at the pin. A broken wire then reads as tripped, which is the safe side.
- **Interlock vs permissive.** An **interlock** stops a running device and blocks a
  start, in Hand too. A **permissive** only blocks a start; a running device keeps
  running. Unwired, both read as OK. Neither is a fault.
- **Trips recover by themselves where that is safe.** Each protection has a response
  (off, warn or trip) and a reset mode:
  - **AUTO**: clears once the cause has gone for a set time, and the device carries
    on. For example, an overload reset in the panel puts the sump pump straight back
    in service with no HMI needed.
  - **RETRY**: as AUTO, but only so many times in a window, then it latches.
  - **MANUAL**: stays until it is reset and the cause has gone. Reset with the
    `Reset` pin, the HMI `cmdReset`, or by switching the device to Off and back.
- **Reset clears faults only.** On a block with faults, `Reset` and `cmdReset` never
  clear totals, counts or statistics; those have their own commands. After a MANUAL reset, a held run command must drop and come
  back before the device restarts (unless you set it to restart after a reset).
- **Kept over a power cut:** only the modes, run hours, starts, valve strokes, flow
  and dose totals. Counts and totals are saved every 12 hours by default
  (`saveEvery`), so a power cut loses at most that much counting.
  **Not kept:** trips (a fault still there trips again), alarms, leads, statistics,
  retries and any sequence in progress. UT_SEQUENCER, UT_STEP_SEQ, UT_ZONE_SEQ and
  UT_DOSE come back stopped, with their outputs off, and need a new start. To keep your settings, declare the record `RETAIN`.
- **Invalid settings never run anything.** A setting that is not a number, negative
  where it can't be, or out of range either falls back to a safe value with a
  warning, or keeps the device off with a fault until it's fixed. Each block's page
  lists its checks.
- **HMI commands act once.** A `cmd…` field acts when it is written (a BOOL on its
  rising edge), and the block clears it. A command held on (a Modbus coil left on)
  still acts only once, and stop always wins over start. With two masters, or a
  SCADA that rewrites its values every poll, put [UT_CMD](blocks/UT_CMD.md) in front.
- **Every device says what it is doing.** Its record has `statusCode` (what it is
  doing, or what holds it back), `faultId` (which fault or setting) and `statusText`
  (the two in words, such as `Latched: overload`). HMIs and SCADA read the codes; the
  full lists are in [conventions.md](conventions.md#status-every-critical-block-says-what-it-is-doing-and-why).
- **Time left is always visible.** Timed blocks show `timeLeft` (and `phaseTime`
  where useful) in their record, beside the status: a status never holds a number.

---

## More reading

- [conventions.md](conventions.md): modes, states, faults, interlocks, the status codes, defaults and retain in full.
- [ladder-rules.md](ladder-rules.md): using library blocks in Ladder and FBD.
