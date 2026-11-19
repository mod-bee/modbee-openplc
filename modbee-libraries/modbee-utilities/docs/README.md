# modbee-utilities

Ready-made IEC 61131-3 function blocks for OpenPLC: motors, pumps, valves, levels,
dosing, irrigation, measurements, totals, alarms and sequences. Each block does one
job the way a good panel builder would wire it, with the protections, modes and fault
handling already in place.

**Hardware:** an ESP32-S3 (such as the ModBee Node UIO) or anything more powerful,
including OpenPLC Runtime v4 on a Raspberry Pi or PC.

## How to use a block

1. **Drop it in.** In Ladder, give every library block its own rung with nothing in
   series in front of it. A block whose rung is false doesn't run, and its outputs
   freeze. See [ladder-rules.md](ladder-rules.md).
2. **Wire the pins.** Signals go on the named pins. Blocks connect to blocks through
   their `ip…` pins: write the other block's instance name on the pin (a pump's
   `ipMotor := fbMotor1`).
3. **Give it its record.** Declare one record variable per block (`stPump1 : ST_PumpData`)
   and wire it to `refData`. The record holds the HMI commands, the settings, the
   status and the totals. Every setting has a working default, so you only change what
   the site needs. Do not make the record RETAIN: the block keeps its settings and
   totals itself.

Each block's page lists its pins first, then its record, how it works and an example.

## How the blocks fit together

- **Equipment has an owner.** Motors, pumps and valves have no Run / Start / Stop
  pins. In Auto they do what their **owner** asks: the pump asks its motor, a level
  control or a group asks the pump, a zone asks its valve. In Hand the HMI or an
  [FB_LocalControl](blocks/FB_LocalControl.md) on the panel door runs them. Out of
  service (motors and valves) takes a machine out of use for maintenance.
- **Process blocks take the wires.** Runs, level controls, doses, sequences and zone
  programs have the `bRun` / `bStart` / `bStop` pins, and drive the equipment.
- **Parts add what is fitted.** A thermistor, a dry-run level, a CT, a soft starter, a
  prime, a starts limit, a booster pump: each is a small block with an `ipOwner` pin, on
  its own rung before its owner.
- **One system block.** [FB_SystemMode](blocks/FB_SystemMode.md) is the plant's Off /
  Manual / Auto, power-on delay and reset; wire it to every block's `ipSystem`.
- **Every block reports the same way:** `bError`, `bWarning`, `eErrorId` (an
  `E_UtError` code) and `eState`. The HMI shows the words.

The rules are in [conventions.md](conventions.md).

---

## Pick a block

### The system and the panel door

- **[FB_SystemMode](blocks/FB_SystemMode.md)**: The plant's own mode: Off / Manual / Auto, the auto type, a manual run, the power-on delay and the plant-wide reset. Every other block can read it through its `ipSystem` pin.
- **[FB_LocalControl](blocks/FB_LocalControl.md)**: The panel-door controls of one motor, pump or valve: an Off / Hand / Auto selector and start / stop push-buttons. It drives the equipment through its `ipEquipment` pin.
- **[FB_Cmd](blocks/FB_Cmd.md)**: Arbitrates commands from two masters, the local panel HMI and a remote SCADA / IoT system: stop bits win, local wins over remote, and remote control can be switched off.

### Motors

- **[FB_Motor](blocks/FB_Motor.md)**: Runs and protects one motor on a contactor or a run relay: overload, no feedback, feedback lost and stuck, with run hours and starts. It has its own Off / Hand / Auto; in Auto its owner (a pump, a group, a sequence) drives it.
- **[FB_MotorVsd](blocks/FB_MotorVsd.md)**: A motor on a variable speed drive over hard-wired IO: run, running and ready relays, a speed reference and feedback, speed limits, ramps, a skip band and a drive-reset pulse.
- **[FB_MotorRev](blocks/FB_MotorRev.md)**: A reversing starter: forward and reverse contactors that are never on together, a dead time between directions and end-of-travel limits.
- **[FB_MotorStarDelta](blocks/FB_MotorStarDelta.md)**: A star-delta starter: main, star and delta contactors, the timed star stage and the open transition, star and delta never on together.
- **[FB_Motor2Speed](blocks/FB_Motor2Speed.md)**: A two-speed starter (Dahlander or separate windings): low and high contactors never on together, an optional star-bridge contactor and an optional start in low.
- **[FB_Changeover](blocks/FB_Changeover.md)**: Two contactors that must never be on together, with the dead time between them and an aux check. The reversing, two-speed and star-delta motors use it; it also works on its own.
- **[FB_MotorJog](blocks/FB_MotorJog.md)**: A held jog (inch) button for a motor in Hand: the motor runs while the button is held, and stops when it is let go.
- **[FB_MotorSimulate](blocks/FB_MotorSimulate.md)**: Tests a motor or valve without the plant: while simulating, the feedback follows the block's own output, with a warning so it is never mistaken for the real thing.

### Pumps, groups and speed control

- **[FB_Pump](blocks/FB_Pump.md)**: One pump: its run decision (start / stop delays, minimum run and off times), start fail and dropped checks, and the motor it drives (`ipMotor`). Its owner (a level control, a group, a run) drives it.
- **[FB_Group](blocks/FB_Group.md)**: Duty / standby / assist over up to four pumps or motors: rotation (also by run hours), staging, failover, swap while running, a staged stop, idle exercise and a jockey pump. A level control or a run drives the group as it would drive one pump.
- **[FB_SpeedLoop](blocks/FB_SpeedLoop.md)**: Holds a pressure, flow or level by changing a pump's speed (PID), or runs it at a fixed speed: presets, pipe fill, sleep and wake, a flow limit, and protections for high pressure, a burst main, not reaching the setpoint, hunting and a failed sensor.
- **[FB_Cascade](blocks/FB_Cascade.md)**: Decides how many pumps of a group run on one header: staging by speed and pressure, by flow or by flow per pump, with or without VSDs, and a jockey pump for low demand.
- **[FB_PumpDiag](blocks/FB_PumpDiag.md)**: Names the likely cause of a pump's hydraulic trouble from its pressure, flow and suction: blocked, burst, suction low or no lift. It only tells; it stops nothing.

### Parts: protections and add-ons

- **[FB_Protection](blocks/FB_Protection.md)**: One protection on any condition, added to a motor, pump or valve: a thermistor, a drive fault, an external fault, a seal leak, a phase failure, a maximum run time.
- **[FB_LevelCheck](blocks/FB_LevelCheck.md)**: One alarm level on any measurement, added to its owner: low or high pressure, no flow, dry run, a high tank level. One block for each level fitted.
- **[FB_MotorCurrent](blocks/FB_MotorCurrent.md)**: A motor's current from a CT, added to its motor as a part: % of full load, a run proven by current, high and low current, a start that takes too long, a bad CT.
- **[FB_StarterSoft](blocks/FB_StarterSoft.md)**: A soft starter's top-of-ramp check, added to its motor as a part: a start that never reaches full speed trips the motor.
- **[FB_Rotation](blocks/FB_Rotation.md)**: Watches a proximity sensor on a driven shaft, pulley or target wheel: the speed (rpm, rev/s, m/min, m/s), a stall, underspeed (belt slip), overspeed and pulses while stopped. Added to its motor as a part, a stall trips the motor.
- **[FB_PumpPrime](blocks/FB_PumpPrime.md)**: Primes a pump at its start: masks the low pressure / no flow checks until the pipe is full (by pressure, flow, a contact or a run time), with a prime timeout.
- **[FB_Starts](blocks/FB_Starts.md)**: Anti-cycling for a motor or pump: a maximum number of starts per window and a minimum time between starts. A start that would break a limit waits; a running motor is never stopped.
- **[FB_Exercise](blocks/FB_Exercise.md)**: Keeps idle equipment from seizing: after a set idle time it asks its owner for a short run.
- **[FB_LevelFloats](blocks/FB_LevelFloats.md)**: The floats of a sump or wet well, added to its level control: an overflow backup run, a check of the level transmitter against the high float, and float / timer control when the transmitter is lost.
- **[FB_Stages](blocks/FB_Stages.md)**: The extra level stages 2 to 4 of a pump station: tells an FB_Group how many more pumps to call.
- **[FB_SumpClean](blocks/FB_SumpClean.md)**: Sump cleaning: every so many pump cycles it pumps the sump down below its normal stop level and runs on there for a while to clear settled solids.
- **[FB_Booster](blocks/FB_Booster.md)**: A series booster pump that runs with a station's duty pumps, added to the station's level control: started after a delay or on low pressure; a booster that will not run can stop the station.

### Levels, mixing and dosing

- **[FB_LevelControl](blocks/FB_LevelControl.md)**: Keeps a level by driving a pump or a group: EMPTY (a sump, a wet well), FILL (a tank) or TIMED (on / off with no level), with high-high and low-low levels, a demand run, a moving start level and an action for a bad level.
- **[FB_Mixer](blocks/FB_Mixer.md)**: Runs a stirrer or agitator before the pump starts (holding the pump), with the pump, after it, and on a timed cycle. A stirrer that cannot run never holds the pump.
- **[FB_DoseBatch](blocks/FB_DoseBatch.md)**: Doses a batch to a target quantity: fast then slow feed, an early stop for what is still in flight (learned), a settle time and a tolerance check; Hand runs the dosing pump at a set rate.
- **[FB_DoseFlow](blocks/FB_DoseFlow.md)**: Doses in proportion to the carrier flow (fertigation, chlorination): the dosing pump's speed follows the flow, or stroke pulses go to a pulse pump; Hand runs it at a set rate.
- **[FB_DoseTimed](blocks/FB_DoseTimed.md)**: Timed dosing: the dosing pump on for a set time, off for a set time, over and over, while the carrier runs; Hand runs it at a set rate.
- **[FB_Dose](blocks/FB_Dose.md)**: The engine every dosing block shares (FB_DoseBatch, FB_DoseFlow, FB_DoseTimed): written once. bRun / bStart / bStop / bResetFaults and the record's commands (bCmdStart, bCmdStop, bCmdPause, bCmdResetFaults: once per write); bInterlock FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held); bPermissive FALSE holds back a dose start; bPause and bCmdPause (until the next start) pause; bStop, bCmdStop, bAbortWhileHeld, the record's bCmdAbort (stop reason Abort), set.bDosingEnabled FALSE end a dose (a held bRun must drop before it doses again); bStockLowSwitch -> set.stStockLowFault; set.stMaxDoseTimeFault and set.fMaxQuantityPerDose cap a dose. ipDosingPump (optional): Request(bRun := bPumpRunCommand, bPause := NOT bInterlock, fSpeedSetpointPct := fPumpSpeedPct); dosing counts only while it runs.

### Runs

- **[FB_Run](blocks/FB_Run.md)**: One run of any equipment: a held request or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a part or a power cut. Its `bRunCommand` drives the equipment.
- **[FB_RunVolume](blocks/FB_RunVolume.md)**: A volume target for a run, added to it: the run ends when the target has been delivered; a meter that stops counting trips the run.
- **[FB_RunPause](blocks/FB_RunPause.md)**: An operator pause and resume for a run, added to it. The pause ends with the run.
- **[FB_RunGate](blocks/FB_RunGate.md)**: A run waits for a permissive (a tank, a valve's open confirmation, a pressure), with a maximum wait.
- **[FB_RunStyle](blocks/FB_RunStyle.md)**: The way a run takes its signal: held, toggle (push-on / push-off), keep-alive pulses or a single pulse. Put it in front of FB_Run.
- **[FB_RunLog](blocks/FB_RunLog.md)**: Logs each run's time, volume and end reason, and counts the runs by how they ended. It only watches its run.

### Irrigation and routing

- **[FB_ZoneSeq](blocks/FB_ZoneSeq.md)**: An irrigation or wash-down program: the zones watered in turn, by time or by volume, in a safe valve and pump order, with a master valve, repeats, rain action, cycles and soak, a pump wait, a dosing hook and a resume after a power cut.
- **[FB_Zone](blocks/FB_Zone.md)**: One zone of an irrigation or wash-down program: its valve, its water time or volume, cycles and soak, a flow check and its pressure setpoint. Used by FB_ZoneSeq.
- **[FB_Schedule](blocks/FB_Schedule.md)**: A weekly time-of-day schedule (a local fallback; the platform holds the real calendar): time windows by day, overrides, hour and day pulses.
- **[FB_IrrDefer](blocks/FB_IrrDefer.md)**: The wet-weather inhibit: says when not to irrigate (rain, wet soil, a lost sensor, a manual or remote defer), why, and to send the effluent to storage instead.
- **[FB_Route](blocks/FB_Route.md)**: The outlet selector for up to four outlet valves: which outlet the pumps deliver to, valve first, the wet-weather divert to storage, a blocked irrigator.

### Valves

- **[FB_Valve](blocks/FB_Valve.md)**: A two-position valve, cylinder or damper: spring return (normally closed or open) or double-acting, with end switches or travel times, a safe position and stroke counts.
- **[FB_ValveLatch](blocks/FB_ValveLatch.md)**: A latching (pulsed) DC solenoid valve: a pulse on the open or close coil when the position changes; the last position is kept over a power cut.
- **[FB_ValveMotor](blocks/FB_ValveMotor.md)**: A motorised two-position valve or damper: open and close drives never together, a reversal pause, the drive stopping at the end.
- **[FB_Valve3Pos](blocks/FB_Valve3Pos.md)**: A three-position valve: a 3-way diverter, a spring-centred double solenoid, a three-coil valve or a motorised valve with a mid position.
- **[FB_ValveMod](blocks/FB_ValveMod.md)**: A modulating valve or damper with a positioner (4-20 mA / 0-10 V): the position from its owner, shaped, clamped and ramped.
- **[FB_ValveFloat](blocks/FB_ValveFloat.md)**: A floating (three-point) valve or damper with raise / lower contacts only: positioned by drive time, re-synced at the ends, homed at power-up.
- **[FB_ValvePos](blocks/FB_ValvePos.md)**: ABSTRACT base of the positioning valves (FB_ValveMod, FB_ValveFloat).

### Measurements

- **[FB_AnalogIn](blocks/FB_AnalogIn.md)**: An analog reading to an engineering value with its health: 4-20 mA (NE43 fail bands), 0-20 mA, 0-10 V, custom or a value already in units, with a fault ride-through.
- **[FB_SwitchSet](blocks/FB_SwitchSet.md)**: Up to four level switches (LL, L, H, HH) and one plain contact as one measurement, each debounced, with a quality per switch and a check that the switches agree.
- **[FB_DigitalIn](blocks/FB_DigitalIn.md)**: A switch, float or contact cleaned up: debounce, an alarm on a state, chatter detection, and running totals of changes and on-time.
- **[FB_Vessel](blocks/FB_Vessel.md)**: A tank, sump, silo or pond: its volume, % full, free space, mass and surface area from a level measurement, for six shapes and several joined tanks.
- **[FB_SignalSelect](blocks/FB_SignalSelect.md)**: Two or three sensors measuring the same thing, voted into one trusted measurement.
- **[FB_MeasFilter](blocks/FB_MeasFilter.md)**: Placed after a measurement: smooths it, cuts off creep below a low limit and clamps it.
- **[FB_MeasFrozen](blocks/FB_MeasFrozen.md)**: Placed after a measurement: warns (or trips) when a value that should move has not moved.
- **[FB_MeasOverride](blocks/FB_MeasOverride.md)**: Placed after a measurement: simulation, and what a bad value shows (pass, hold or a substitute).
- **[FB_Linearise](blocks/FB_Linearise.md)**: A lookup table / curve: tank strapping tables, non-linear sensors, weirs and flumes, pump curves.
- **[FB_Rate](blocks/FB_Rate.md)**: The rate of change of a value (a least-squares trend), with rising-fast and falling-fast warnings.
- **[FB_Stats](blocks/FB_Stats.md)**: Minimum, maximum and time-weighted average of a value, for the current period and the previous one.
- **[FB_AnalogOut](blocks/FB_AnalogOut.md)**: An engineering demand to an analog output card: clamp, ramp, a fail value on the interlock, Manual / Auto, the raw value for the card.

### Meters and totals

- **[FB_PulseMeter](blocks/FB_PulseMeter.md)**: A pulse flow meter or a hardware pulse counter, as a total and a rate, with unit conversion and a batch target.
- **[FB_FlowTotal](blocks/FB_FlowTotal.md)**: A total from a flow rate, from running time at a nominal rate, or from samples of a slow reading, with unit conversion and a batch target.
- **[FB_RegisterMeter](blocks/FB_RegisterMeter.md)**: A total from a device's own total register (a Modbus energy or flow meter, a BeeBus counter): increases counted, resets, wraps and glitches handled, with unit conversion and a batch target.
- **[FB_LevelMeter](blocks/FB_LevelMeter.md)**: The volume a pump moves, worked out from the tank's level (with a high-water mark, so waves are never counted twice).
- **[FB_RunHours](blocks/FB_RunHours.md)**: A run-hour and start meter with a service interval, for anything that runs.

### Sequences

- **[FB_Sequencer](blocks/FB_Sequencer.md)**: A start / stop chain (conveyors, crushers, process trains): one step per machine, started in order with proven feedback, stopped in reverse, with fault cascades and an auto restart.
- **[FB_StepSeq](blocks/FB_StepSeq.md)**: A timed or conditional step sequence (backwash, CIP, fill-mix-drain): each step switches its outputs and lasts its time or until its condition, with jumps, loops and stop steps.
- **[FB_PulseSeq](blocks/FB_PulseSeq.md)**: Sequential pulsing (jet-pulse filter cleaning, flush valves): one output at a time, in order, with gaps and pauses, on demand or continuously.

### Alarms, interlocks and the HMI

- **[FB_AlarmTable](blocks/FB_AlarmTable.md)**: All of a panel's alarms in one block, one row each, with the fault and warning lamps, the beacon, the siren and the healthy relay.
- **[FB_Alarm](blocks/FB_Alarm.md)**: One alarm as its own block, the ISA-18.2 way: shelving, suppression, out of service, priority and time stamps. Use FB_Annunciator for the group's horn and lamp.
- **[FB_Annunciator](blocks/FB_Annunciator.md)**: The horn, alarm lamp and first-out for a group of FB_Alarm blocks.
- **[FB_AlarmBeacon](blocks/FB_AlarmBeacon.md)**: Flashes alarm numbers on a single lamp, for sites with one fault lamp and no HMI.
- **[FB_Interlock](blocks/FB_Interlock.md)**: All the conditions that must be healthy before a device may run, as one `bPermissive`, with first-out and maintenance bypasses.
- **[FB_MsgQueue](blocks/FB_MsgQueue.md)**: A message ticker and site-status board for an HMI: each source's state and error code, queued or as a list of what is wrong now.
- **[FB_EventLog](blocks/FB_EventLog.md)**: The last events (trips, stops, end reasons) with their time, newest first, optionally kept over a power cut: "what happened overnight".

### Settings and reporting

- **[FB_SettingCheck](blocks/FB_SettingCheck.md)**: A write gate for one project value that belongs to no block: a new value from the HMI is checked against its limits before it is used.
- **[FB_SettingArray](blocks/FB_SettingArray.md)**: FB_SettingCheck for a list of project values, one row each; the values are kept over a power cut.
- **[FB_Report](blocks/FB_Report.md)**: Report by exception: decides when one value is worth sending (a change past a deadband, a heartbeat, a force), for a value sent by other means than modbee-mqtt.
- **[FB_ReportArray](blocks/FB_ReportArray.md)**: FB_Report for a list of values, one row each.

### Remote sites

- **[FB_Watchdog](blocks/FB_Watchdog.md)**: Watches a heartbeat or counter from the other end of a link, and makes one for it to watch.
- **[FB_LinkSupervisor](blocks/FB_LinkSupervisor.md)**: Escalating recovery of a remote site's comms link: restart the modem, power cycle it, and at most a few controlled reboots a day.

### The IO map

- **[FB_IoMapIn](blocks/FB_IoMapIn.md)**: The input side of the IO map: terminals to functions, from a table, with fail-safe values, debounce and commissioning forces. Call it first in the scan.
- **[FB_IoMapOut](blocks/FB_IoMapOut.md)**: The output side of the IO map: functions to terminals, from a table, with commissioning forces and a hold-off per output. Call it last in the scan.
- **[F_IoAddrOk](blocks/F_IoAddrOk.md)**: TRUE when an IO address can be kept by the IO maps (a known source, a module of at most 127).
- **[F_IoAddrPack](blocks/F_IoAddrPack.md)**: Packs an IO channel address into one DWORD (the IO maps' kept copies).
- **[F_IoAddrUnpack](blocks/F_IoAddrUnpack.md)**: Unpacks the address F_IoAddrPack packed.
- **[F_IoFind](blocks/F_IoFind.md)**: Finds a channel through the IO module table (used by the IO maps).
- **[F_IoForceSlot](blocks/F_IoForceSlot.md)**: One commissioning force slot (used by the IO maps).

### Timers, logic and signal helpers

- **[FB_Tonr](blocks/FB_Tonr.md)**: A retentive (accumulating) on-delay timer: the time adds up over several on periods.
- **[FB_Debounce](blocks/FB_Debounce.md)**: An on / off delay filter: ignores anything shorter than its delays.
- **[FB_Toggle](blocks/FB_Toggle.md)**: Push-on / push-off: each press flips the output.
- **[FB_Flasher](blocks/FB_Flasher.md)**: An on / off pulse generator that never drifts: a flasher, or an "every X, pulse" timer.
- **[FB_Filter](blocks/FB_Filter.md)**: A smoothing filter: low-pass, moving average or block average.
- **[FB_Ramp](blocks/FB_Ramp.md)**: A rate-limited setpoint: the output moves toward the input at a set rate.
- **[FB_TwoPoint](blocks/FB_TwoPoint.md)**: An on / off (hysteresis) controller, thermostat style, with delays and anti-short-cycle times.
- **[FB_TimeSplit](blocks/FB_TimeSplit.md)**: Splits a TIME into days, hours, minutes, seconds and milliseconds, with texts for an HMI.
- **[F_Countdown](blocks/F_Countdown.md)**: Time remaining on any timer: preset minus elapsed, never negative.
- **[F_Scale](blocks/F_Scale.md)**: Linear scaling from one range onto another.
- **[F_TimeBuild](blocks/F_TimeBuild.md)**: Days, hours, minutes, seconds and milliseconds to a TIME (an HMI enters a delay as numbers).
- **[F_TimeText](blocks/F_TimeText.md)**: A duration as a short text for a simple display ('42 m 10 s').
- **[F_Blink](blocks/F_Blink.md)**: A flashing lamp from the PLC clock: every lamp using it flashes in step.

### Time and units

- **[F_LocalTime](blocks/F_LocalTime.md)**: Local time from a UTC clock: the offset plus daylight saving.
- **[F_DateDays](blocks/F_DateDays.md)**: Days from 1970-01-01 to a date.
- **[F_DstActive](blocks/F_DstActive.md)**: TRUE while daylight saving is in force under a rule (NZ, AU south-east, EU, US).
- **[F_ClockOk](blocks/F_ClockOk.md)**: TRUE when the site clock has been set (a date from 2020 up to 2100).
- **[F_UnitConv](blocks/F_UnitConv.md)**: Converts a value from one engineering unit to another (bar to psi, L/s to m3/h ...).
- **[F_UnitOk](blocks/F_UnitOk.md)**: TRUE when F_UnitConv can convert between two units.
- **[F_UnitKind](blocks/F_UnitKind.md)**: The unit table behind F_UnitConv: a unit's kind and how to reach its base unit.
- **[F_UnitFactor](blocks/F_UnitFactor.md)**: The factor from one volume unit to another (litre, m3, megalitre, gallon), used by the meters' input and output units.

### Building your own (ST)

- **[F_Protect](blocks/F_Protect.md)**: The protection engine every block is built from: delay, response, reset mode and retries for one condition. Use it in your own ST code to protect something the library does not cover.
- **[F_CheckReal](blocks/F_CheckReal.md)**: The settings-check rule for a REAL: why a value is refused, or `None`.
- **[F_CheckLreal](blocks/F_CheckLreal.md)**: The settings-check rule for an LREAL: why a value is refused, or `None`.
- **[F_CheckTime](blocks/F_CheckTime.md)**: The settings-check rule for a TIME: why a value is refused, or `None`.
- **[F_CheckInt](blocks/F_CheckInt.md)**: The settings-check rule for an INT: why a value is refused, or `None`.
- **[F_BitPut](blocks/F_BitPut.md)**: Sets one bit of a DWORD.
- **[F_HoursAdd](blocks/F_HoursAdd.md)**: Whole milliseconds of running to add this scan, exact over years (for your own run-hour counts).
- **[FB_Equipment](blocks/FB_Equipment.md)**: The engine every equipment block shares (motor, pump, valve): written once.
- **[FB_Object](blocks/FB_Object.md)**: The base of every block: the error outputs and the system link. bError: a trip is active now. bWarning: a warning is active now. eErrorId: the first error since the last reset (first-out), else the first warning; None when nothing is active. eState: what the block is doing.

---

## Putting a site together

**Sump with two pumps.** A level transmitter goes into an
[FB_AnalogIn](blocks/FB_AnalogIn.md) (`fbSumpLevel`); high and low floats into an
[FB_SwitchSet](blocks/FB_SwitchSet.md) (`fbFloats`). Each pump is an
[FB_Motor](blocks/FB_Motor.md) with an [FB_Pump](blocks/FB_Pump.md) on top
(`ipMotor := fbMotor1`) and an [FB_LevelCheck](blocks/FB_LevelCheck.md) for dry run
(`ipOwner := fbPump1`). An [FB_Group](blocks/FB_Group.md) shares the duty
(`ipMember1 := fbPump1`, `ipMember2 := fbPump2`), and an
[FB_LevelControl](blocks/FB_LevelControl.md) in EMPTY mode drives the group
(`ipTransducer := fbSumpLevel`, `ipEquipment := fbGroup`). [FB_LevelFloats](blocks/FB_LevelFloats.md)
(`ipFloats := fbFloats`, `ipOwner := fbLevelCtl`) runs the pumps on the floats if the
transmitter fails, and checks it against the high float.
[FB_AlarmTable](blocks/FB_AlarmTable.md) drives the panel's lamps and siren.

**Station with a booster pump.** When the duty pumps push through a series booster,
make the booster its own FB_Pump (not a group member) and add an
[FB_Booster](blocks/FB_Booster.md) (`ipBoosterPump := fbBoosterPump`,
`ipOwner := fbLevelCtl`). It starts the booster a delay after the duty pumps, or on low
pressure (`ipPressure`). The booster stops at once at the end of a cycle, so give each
duty FB_Pump a `set.tStopDelay` to stop that much later.

**Pumping on a timer.** With no level to keep (a circulation pump, a timed transfer),
set the FB_LevelControl's `set.eControlMode := Timed`: it runs the pump `set.tOnTime`, rests
`set.tOffTime`, over and over while `bEnable` is on. `ipLevel` may stay unwired.

**Tank to tank transfer.** An [FB_Run](blocks/FB_Run.md) is one transfer: started from
the HMI or a schedule, its `bRunCommand` goes to an FB_LevelControl's `bDemand` (with
`set.bRunOnDemandOnly`), and the level control's `bEquipmentRunning` back to the run's
`bEquipmentRunning`. [FB_RunVolume](blocks/FB_RunVolume.md) (`ipRun := fbTransfer`,
`ipMeter := fbFlowMeter`) ends it at a volume, with a safety time cap. Two
[FB_LevelCheck](blocks/FB_LevelCheck.md) parts on the run: the source tank low
(Signal: the transfer pauses until the level is back) and the destination full (Signal
with `set.bEndsRunWhenReached`: the transfer ends normally).

**Pressure set.** A pressure transmitter (FB_AnalogIn) feeds an
[FB_SpeedLoop](blocks/FB_SpeedLoop.md) (`ipProcessValue`), which drives an FB_Pump on an
[FB_MotorVsd](blocks/FB_MotorVsd.md). For several pumps on one header the loop drives
an FB_Group, and [FB_Cascade](blocks/FB_Cascade.md) sets how many pumps run
(`nExtraPumps` to the group's `nExtraMembers`).

**Pressure set with a jockey pump.** Add a small pump to the same FB_Group with its
FB_Pump `set.ePumpRole := Jockey`. The group never makes it the lead; wire the group's
`fJockeyCapacity` and `bJockeyReady` to the FB_Cascade, and the header flow to its
`ipHeaderFlow`. At low demand the cascade asks for the jockey alone (`nExtraPumps` -1); when the
jockey falls short a duty pump takes over, and the jockey stays on until it runs.

**Irrigation zones.** [FB_Schedule](blocks/FB_Schedule.md) starts an
[FB_ZoneSeq](blocks/FB_ZoneSeq.md). Each zone is an [FB_Zone](blocks/FB_Zone.md) with
its own [FB_Valve](blocks/FB_Valve.md). The program opens each valve, asks for the pump
(`ipPump`: a pump, a group or a level control) and waters by time or by volume
([FB_PulseMeter](blocks/FB_PulseMeter.md) on the flow meter), with cycles and soak per
zone and `set.repeats` passes of the whole program. A master valve goes on
`ipMasterValve`: it opens with the first zone and closes `set.tMasterCloseDelay` after
the last. For rain, wire [FB_IrrDefer](blocks/FB_IrrDefer.md)'s `bDeferIrrigation` to the
program's `bDeferIrrigation` and pick `set.eActionOnDefer` (Pause, Skip, Cancel or Ignore).
[FB_DoseFlow](blocks/FB_DoseFlow.md) can add fertiliser in proportion to the flow.

**Conveyor chain.** Each machine is an FB_Motor (or
[FB_MotorStarDelta](blocks/FB_MotorStarDelta.md)). [FB_Sequencer](blocks/FB_Sequencer.md)
has one row per machine in start order; pull cords and guards go through
[FB_Interlock](blocks/FB_Interlock.md) to each motor's `bInterlock`. Wire the e-stop
healthy signal, inverted, to the sequencer's `bAbortWhileHeld`.

**A motor with more fitted.** Parts go on their own rungs before the motor, each with
`ipOwner := fbMotor1`: [FB_Protection](blocks/FB_Protection.md) for a thermistor or an
overload contact, [FB_MotorCurrent](blocks/FB_MotorCurrent.md) for a CT,
[FB_StarterSoft](blocks/FB_StarterSoft.md) for a soft starter's top-of-ramp relay.
[FB_MotorJog](blocks/FB_MotorJog.md) adds a held jog button in Hand.
[FB_MotorSimulate](blocks/FB_MotorSimulate.md) sits between the field feedback and the
motor's `bRunFeedback`, for testing without the plant.

**Remote site.** [FB_Watchdog](blocks/FB_Watchdog.md) watches the SCADA heartbeat;
[FB_LinkSupervisor](blocks/FB_LinkSupervisor.md) restarts or power cycles the modem when
the link stays down.

---

## More reading

- [conventions.md](conventions.md): errors and state, the `E_UtError` codes, records,
  kept settings, equipment and owners, parts, tables, retained data, protections.
- [ladder-rules.md](ladder-rules.md): using library blocks in Ladder.
