# Migrating from 0.1

modbee-utilities 0.2.0 replaces the `UT_…` blocks of 0.1.x. The work is the same; the
shape changes. Names follow Beckhoff's TwinCAT 3 conventions: `FB_` blocks, `ST_`
structures, `E_` lists used with their name, pins with a type prefix (`bRun`,
`fSpeed`, `tDelay`). Big blocks are split into a core block and small **parts** placed
only where they are fitted.

**You do not have to move.** A project built on 0.1.x stays on 0.1.x and runs
unchanged. Keep it on the ModBee OpenPLC Editor **4.3.4-modbee.2** with the library
collection **v0.2.1**, which carries modbee-utilities 0.1.x, and it keeps building
against the version it was written for. Move when you choose: a new project, or a
rework of an old one.

## What changed everywhere

**Records.** A 0.1 block had its record on an in-out pin (`Data`). A 0.2 block has a
`refData` pin: wire the record variable to it. Records are in groups: commands at the
top (`bCmdStart`, `bCmdReset`), then `set`, `sts`, `det`, `tot`. See
[conventions.md](conventions.md#records-via-refdata).

**No RETAIN on records.** In 0.1 you declared a record `RETAIN` to keep its settings.
In 0.2 each block keeps a retained copy of its last good settings and its totals
itself; declare the records as ordinary variables. A bad write is put back from the
kept copy (`sts.bRefused`, warning `SettingRefused`).

**No status text.** `statusCode`, `faultId`, `statusText`, `stopText` and the text
functions (`UT_STATUS_TEXT`, `UT_STOP_TEXT`, `UT_RESET_TEXT`) are gone. Every block has
`bError`, `bWarning`, `eErrorId : E_UtError` (a code with a fixed number) and
`eState : E_State`; equipment adds `sts.eStopReason : E_StopReason`. The HMI or SCADA
shows the words. See [conventions.md](conventions.md#errors-and-state).

**Equipment has an owner.** A 0.1 motor had `AutoCmd`, `SwHand` / `SwAuto` and `LocalStart` / `LocalStop` pins. A 0.2
motor, pump or valve has none: in Auto its **owner** drives it through the `ip…` pin
you wire the instance to (a pump's `ipMotor`, a level control's `ipTarget`, a group's
`ipMember1`). Hand is the record's `bCmdStart` / `bCmdStop` or an
[FB_LocalControl](blocks/FB_LocalControl.md) on the panel door. Off / Hand / Auto is
the record's `set.eMode`, kept over a power cut.

**Parts.** What a 0.1 block carried built in for every case (a thermistor, a pump's
pressure, flow and suction levels, a prime, a starts limit) is a small part block in
0.2, with an `ipOwner` pin, on its own rung before its owner. Place only the ones
fitted.

**Tables instead of element blocks.** 0.1 lists (alarm table rows, interlock
conditions, sequencer steps, schedule windows, report items, settings) were element
block instances. In 0.2 they are rows: arrays of a row structure the project declares,
on the block's in-out pins.

**Lists are qualified.** `E_Mode.Auto`, not `UT_MODE_AUTO`. Every list is
`{attribute 'qualified_only'}`, so a bare `Auto` does not compile.

**Rates are per hour.** Meters give their rate per hour (`I_Meter`); the dosing
blocks' pump capacity is per hour.

**No day totals.** As in 0.1.x (the boards have no clock), the blocks give running
totals; SCADA makes the days.

## Blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `UT_MOTOR` | [`FB_Motor`](blocks/FB_Motor.md); thermistor, drive fault, external fault: [`FB_Protection`](blocks/FB_Protection.md); Hand buttons and HOA: [`FB_LocalControl`](blocks/FB_LocalControl.md); the motor current (`Current`): [`FB_MotorCurrent`](blocks/FB_MotorCurrent.md) (a part); jog: [`FB_MotorJog`](blocks/FB_MotorJog.md); a soft starter's top of ramp: [`FB_StarterSoft`](blocks/FB_StarterSoft.md) (a part); simulate: [`FB_MotorSimulate`](blocks/FB_MotorSimulate.md); the Hand run limit: `set.tHandMax`; restart after reset: `set.bRestartAfterReset`; the not-in-Auto warning: `set.bWarnNotAuto` |
| `UT_MOTOR_CORE` | inside the equipment base (`FB_Equipment`): no block of its own |
| `UT_MOTOR_VSD` | [`FB_MotorVsd`](blocks/FB_MotorVsd.md); the speed in Hz and rpm from `set.fRatedHz` / `set.fRatedRpm`; the drive's ramp: `set.tDriveRamp` |
| `UT_MOTOR_REV` | [`FB_MotorRev`](blocks/FB_MotorRev.md); the panel's reverse button: [`FB_LocalControl`](blocks/FB_LocalControl.md) `bRev` |
| `UT_MOTOR_SD` | [`FB_MotorStarDelta`](blocks/FB_MotorStarDelta.md); to delta early on a falling star current: `set.fStarCurrentPct` with [`FB_MotorCurrent`](blocks/FB_MotorCurrent.md) |
| `UT_MOTOR_2SPD` | [`FB_Motor2Speed`](blocks/FB_Motor2Speed.md); the panel's low / high buttons: [`FB_LocalControl`](blocks/FB_LocalControl.md) `bLow` / `bHigh` |
| `UT_HOA`, `UT_MODE_SELECT` | [`FB_LocalControl`](blocks/FB_LocalControl.md); the mode source (HMI, selector, REMOTE): `set.eModeSource`; out of service: `E_Mode.OutOfService` on the motor or valve |
| `UT_DUTY` | [`FB_Group`](blocks/FB_Group.md): rotation (also by run hours), maximum running, Hand runs counted, swap while running, a staged stop, a jockey; a part on the group (e.g. a burst main by [`FB_LevelCheck`](blocks/FB_LevelCheck.md) on the header flow) |
| `UT_STARTS` | [`FB_Starts`](blocks/FB_Starts.md) (a part); the wait after a failed start: `set.tFailWait` |
| `UT_PUMP` | [`FB_Pump`](blocks/FB_Pump.md) (its role and capacity: `set.eRole`, `set.fCapacity`); its levels: [`FB_LevelCheck`](blocks/FB_LevelCheck.md); seal leak, maximum run: [`FB_Protection`](blocks/FB_Protection.md); prime: [`FB_PumpPrime`](blocks/FB_PumpPrime.md); exercise: [`FB_Exercise`](blocks/FB_Exercise.md) on its level control; diagnosis: [`FB_PumpDiag`](blocks/FB_PumpDiag.md); its timed and level modes: [`FB_LevelControl`](blocks/FB_LevelControl.md), [`FB_Run`](blocks/FB_Run.md) |
| `UT_PUMP_STATION` | [`FB_LevelControl`](blocks/FB_LevelControl.md) + [`FB_Group`](blocks/FB_Group.md). EMPTY / FILL / TIMED: `set.eMode`; pump down (`cmdPumpDown`): `bCmdDemand`; level variation: `set.fStartVariation`; level run-on: `set.eLevelFail` RunOn with `set.tRunOnMax`; demand restart: `set.fDemandRestart`. Floats: [`FB_LevelFloats`](blocks/FB_LevelFloats.md); stages and demand pumps: [`FB_Stages`](blocks/FB_Stages.md); cleaning: [`FB_SumpClean`](blocks/FB_SumpClean.md); booster pump: [`FB_Booster`](blocks/FB_Booster.md) (a part) with the duty pumps' `set.tStopDelay`; no flow: [`FB_LevelCheck`](blocks/FB_LevelCheck.md) on the pump's flow. TRANSFER: [`FB_Run`](blocks/FB_Run.md) + [`FB_RunVolume`](blocks/FB_RunVolume.md) + two [`FB_LevelCheck`](blocks/FB_LevelCheck.md) parts (source low, destination full with `set.bDoneWhenReached`) |
| `UT_SPEED_CTRL` | [`FB_SpeedLoop`](blocks/FB_SpeedLoop.md): setpoint sources and presets, flow control, fixed speeds, sleep and wake, derivative, start speed, rate limit, at-setpoint band, pipe fill, flow limit, the high / not reaching / low-at-maximum / hunting protections, an external speed, `bMoreAvailable` |
| `UT_PUMP_CASCADE` | [`FB_SpeedLoop`](blocks/FB_SpeedLoop.md) + [`FB_Group`](blocks/FB_Group.md) + [`FB_Cascade`](blocks/FB_Cascade.md): staging by pressure, by flow or by flow per pump, pressure bands with no VSD; the jockey pump: an FB_Group member with `set.eRole := Jockey`; the staged stop: FB_Group; high flow (burst main): [`FB_LevelCheck`](blocks/FB_LevelCheck.md) on the header flow, a part of the group |
| `UT_DOSE` | [`FB_DoseBatch`](blocks/FB_DoseBatch.md), [`FB_DoseFlow`](blocks/FB_DoseFlow.md), [`FB_DoseTimed`](blocks/FB_DoseTimed.md), one per mode. Hand (`handRate`, `handNeedsCarrier`): the dose block's own `set.eMode` Hand with `set.fHandRate`, `set.bHandNeedsCarrier`, `set.tHandMax`, or an [`FB_LocalControl`](blocks/FB_LocalControl.md) on the dose block; `cmdMode`: `nCmdMode` |
| `UT_MIXER` | [`FB_Mixer`](blocks/FB_Mixer.md) |
| `UT_LIMIT`, `UT_LEVEL_CHECK`, `UT_MEAS_CHECK` | [`FB_LevelCheck`](blocks/FB_LevelCheck.md) (a part); the high / low switch: `bSwitch` |
| `UT_PROTECT` | [`F_Protect`](blocks/F_Protect.md) (in ST), or [`FB_Protection`](blocks/FB_Protection.md) as a part |
| `UT_RUN_LIMIT` | [`FB_Run`](blocks/FB_Run.md); volume target, low flow (`minFlow`) and the default safety cap (`defaultCap`): [`FB_RunVolume`](blocks/FB_RunVolume.md); pause: [`FB_RunPause`](blocks/FB_RunPause.md); permissive wait: [`FB_RunGate`](blocks/FB_RunGate.md); run styles: [`FB_RunStyle`](blocks/FB_RunStyle.md); the last run: [`FB_RunLog`](blocks/FB_RunLog.md) |
| `UT_ZONE_SEQ` | [`FB_ZoneSeq`](blocks/FB_ZoneSeq.md) + one [`FB_Zone`](blocks/FB_Zone.md) per zone: master valve with its close delay, flush, run one zone (`nRunZone`), pump wait and skips, the dose request, repeats, rain action (`bRainHold`), per-zone pressure (`fZoneSp`), resume after a power cut; the zone's flow check and soak: FB_Zone |
| `UT_SCHEDULE` | [`FB_Schedule`](blocks/FB_Schedule.md); its windows are rows (`ST_SchedWindow`) |
| `UT_IRR_DEFER` | [`FB_IrrDefer`](blocks/FB_IrrDefer.md) |
| `UT_VALVE` | [`FB_Valve`](blocks/FB_Valve.md) (spring and double-held); pulsed: [`FB_ValveLatch`](blocks/FB_ValveLatch.md); motorised: [`FB_ValveMotor`](blocks/FB_ValveMotor.md) (torque switches, the actuator in Local: `bActRemote`); panel buttons: [`FB_LocalControl`](blocks/FB_LocalControl.md); exercise of an idle valve: [`FB_Exercise`](blocks/FB_Exercise.md) |
| `UT_VALVE_CORE` | inside the equipment base: no block of its own |
| `UT_VALVE_3POS` | [`FB_Valve3Pos`](blocks/FB_Valve3Pos.md); panel position buttons: [`FB_LocalControl`](blocks/FB_LocalControl.md) `bPos1`..`bPos3` |
| `UT_VALVE_MOD` | [`FB_ValveMod`](blocks/FB_ValveMod.md) |
| `UT_VALVE_FLOAT` | [`FB_ValveFloat`](blocks/FB_ValveFloat.md) |
| `UT_ANALOG_IN` | [`FB_AnalogIn`](blocks/FB_AnalogIn.md) (the alternative value: `set.fAltFactor` / `fAltOffset` → `fValueAlt`); filter, low cut-off, clamp: [`FB_MeasFilter`](blocks/FB_MeasFilter.md); simulate, substitute: [`FB_MeasOverride`](blocks/FB_MeasOverride.md); frozen check: [`FB_MeasFrozen`](blocks/FB_MeasFrozen.md) |
| `UT_ANALOG_OUT` | [`FB_AnalogOut`](blocks/FB_AnalogOut.md) |
| `UT_DIGITAL_IN` | [`FB_DigitalIn`](blocks/FB_DigitalIn.md); level switches as one measurement: [`FB_SwitchSet`](blocks/FB_SwitchSet.md) |
| `UT_VESSEL` | [`FB_Vessel`](blocks/FB_Vessel.md); a strapping table: [`FB_Linearise`](blocks/FB_Linearise.md) in front of it |
| `UT_SIGNAL_SELECT` | [`FB_SignalSelect`](blocks/FB_SignalSelect.md) |
| `UT_TOTALISER` | by method: [`FB_PulseMeter`](blocks/FB_PulseMeter.md) (PULSE, COUNT), [`FB_FlowTotal`](blocks/FB_FlowTotal.md) (RATE, RUNTIME, SAMPLE), [`FB_RegisterMeter`](blocks/FB_RegisterMeter.md) (REGISTER), [`FB_LevelMeter`](blocks/FB_LevelMeter.md) (CHANGE); the batch target: `set.fBatchTarget` → `bBatchDone`; in / out units on FB_PulseMeter, FB_FlowTotal and FB_RegisterMeter: `set.eInUnit` / `set.eOutUnit` ([`F_UnitFactor`](blocks/F_UnitFactor.md)) |
| `UT_RUN_HOURS` | [`FB_RunHours`](blocks/FB_RunHours.md) |
| `UT_RATE` | [`FB_Rate`](blocks/FB_Rate.md) |
| `UT_STATS` | [`FB_Stats`](blocks/FB_Stats.md) |
| `UT_SEQUENCER` | [`FB_Sequencer`](blocks/FB_Sequencer.md); its steps are rows |
| `UT_STEP_SEQ` | [`FB_StepSeq`](blocks/FB_StepSeq.md); its steps are rows |
| `UT_PULSE_SEQ` | [`FB_PulseSeq`](blocks/FB_PulseSeq.md) |
| `UT_ALARM_TABLE` | [`FB_AlarmTable`](blocks/FB_AlarmTable.md); its alarms are rows |
| `UT_ALARM` | [`FB_Alarm`](blocks/FB_Alarm.md) |
| `UT_ANNUNCIATOR` | [`FB_Annunciator`](blocks/FB_Annunciator.md) |
| `UT_ALARM_BEACON` | [`FB_AlarmBeacon`](blocks/FB_AlarmBeacon.md) |
| `UT_INTERLOCK` | [`FB_Interlock`](blocks/FB_Interlock.md); its conditions are rows |
| `UT_MSG_QUEUE` | [`FB_MsgQueue`](blocks/FB_MsgQueue.md): messages are the source's `eState` and `eErrorId` |
| `UT_EVENT_LOG` | [`FB_EventLog`](blocks/FB_EventLog.md): events are `E_StopReason` / `E_UtError` codes |
| `UT_SETTING_CHECK` | [`FB_SettingCheck`](blocks/FB_SettingCheck.md); a list: [`FB_SettingArray`](blocks/FB_SettingArray.md) |
| `UT_REPORT` | [`FB_Report`](blocks/FB_Report.md) |
| `UT_REPORT_ARRAY` | [`FB_ReportArray`](blocks/FB_ReportArray.md) |
| `UT_CMD` | [`FB_Cmd`](blocks/FB_Cmd.md) |
| `UT_SYSTEM_MODE` | [`FB_SystemMode`](blocks/FB_SystemMode.md); the selector: `set.eModeSource` with `bSwManual` / `bSwAuto`; ForceOff: `bForceOff` |
| `UT_WATCHDOG` | [`FB_Watchdog`](blocks/FB_Watchdog.md) |
| `UT_LINK_SUPERVISOR` | [`FB_LinkSupervisor`](blocks/FB_LinkSupervisor.md) |
| `UT_IO_MAP_IN` | [`FB_IoMapIn`](blocks/FB_IoMapIn.md) |
| `UT_IO_MAP_OUT` | [`FB_IoMapOut`](blocks/FB_IoMapOut.md) |
| `UT_IO_FORCE_RUN` | inside the IO maps (their `aForce` table; [`F_IoForceSlot`](blocks/F_IoForceSlot.md)) |
| `UT_TONR` | [`FB_Tonr`](blocks/FB_Tonr.md) |
| `UT_DEBOUNCE` | [`FB_Debounce`](blocks/FB_Debounce.md) |
| `UT_TOGGLE` | [`FB_Toggle`](blocks/FB_Toggle.md) |
| `UT_FLASHER` | [`FB_Flasher`](blocks/FB_Flasher.md) |
| `UT_FILTER` | [`FB_Filter`](blocks/FB_Filter.md); on a measurement: [`FB_MeasFilter`](blocks/FB_MeasFilter.md) |
| `UT_RAMP` | [`FB_Ramp`](blocks/FB_Ramp.md) |
| `UT_TWO_POINT` | [`FB_TwoPoint`](blocks/FB_TwoPoint.md) |
| `UT_LINEARISE` | [`FB_Linearise`](blocks/FB_Linearise.md) |
| `UT_SCALE` | [`F_Scale`](blocks/F_Scale.md) |
| `UT_COUNTDOWN` | [`F_Countdown`](blocks/F_Countdown.md) |
| `UT_TIME_SPLIT` | [`FB_TimeSplit`](blocks/FB_TimeSplit.md) |
| `UT_TIME_BUILD` | [`F_TimeBuild`](blocks/F_TimeBuild.md) |
| `UT_TIME_TEXT` | [`F_TimeText`](blocks/F_TimeText.md) |
| `UT_LOCAL_TIME` | [`F_LocalTime`](blocks/F_LocalTime.md) (with [`F_DstActive`](blocks/F_DstActive.md), [`F_DateDays`](blocks/F_DateDays.md)) |
| `UT_UNIT_CONV` | [`F_UnitConv`](blocks/F_UnitConv.md), [`F_UnitOk`](blocks/F_UnitOk.md); a volume unit factor: [`F_UnitFactor`](blocks/F_UnitFactor.md) |
| `UT_STATUS_TEXT`, `UT_STOP_TEXT`, `UT_RESET_TEXT` | gone: the HMI shows the words for the codes |
| `UT_ROTATION` | [`FB_Rotation`](blocks/FB_Rotation.md): a part of its motor (a stall trips it), or on its own with `bHealthy` |

## Behaviour that changed

**Hand on a dosing block.** A dosing block has its own Off / Hand / Auto
(`set.eMode`): Hand runs the dosing pump at `set.fHandRate` % until a stop or
`set.tHandMax`, and with `set.bHandNeedsCarrier` only while the carrier is proven. An
FB_LocalControl can be wired to the dose block (`ipOwner`) for a panel selector and
buttons.

**Exercise belongs to the process.** A pump in 0.2 always has an owner, so the idle
exercise is a part of the level control ([FB_Exercise](blocks/FB_Exercise.md)), and
the group's rotation exercises each pump in turn. An idle valve's exercise is an FB_Exercise with the valve as its owner.

**Restart after a reset.** By default a 0.2 motor, pump or valve runs again at once
when a reset clears its trip and its owner still asks. For the 0.1 behaviour (the
request must drop and come back first) set `set.bRestartAfterReset := FALSE`.

**Pumps have no out of service.** `E_Mode.OutOfService` is for motors and valves; a
pump refuses it (take its motor out of service instead).

**A bad setting never good stops safely.** A record whose settings were bad from the
declaration gives `bError` `BadSetting`; a 0.1 block often carried on with what it
had. The block's page says what it does then (a mixer never holds its pump, a
three-position valve turns every output off).

**Timed dosing needs the carrier only.** `FB_DoseTimed` doses while `bCarrierRunning`
has been proven for `set.tCarrierProven`; in 0.1 the timed mode also needed a flow
meter. Its rate is `set.fRate`.

**A low mixer level is a protection.** `FB_Mixer`'s low level is an
`ST_ProtectionSet` (default a warning); set it to Trip for `bError`.

**Vessel dimensions are in metres.** `FB_Vessel` takes its dimensions in metres; the
level unit converts only the level, the offset and the % limits. An old configuration
in mm enters its dimensions in metres.

## Moving a project

1. Keep a copy of the project on 0.1.x that builds (editor 4.3.4-modbee.2, library
   collection v0.2.1).
2. Change the library to 0.2.0.
3. For each `UT_…` instance, put in its 0.2 block (the table above) and wire the pins
   by their new names. Wire each block's record to `refData`, and take `RETAIN` off
   the records.
4. Equipment: delete the `AutoCmd` / mode wiring, and wire the owner's `ip…` pin to
   the equipment's instance instead. Add an FB_LocalControl where the panel has a
   selector or buttons.
5. Add the parts the site has (protections, level checks, prime, starts limit), each
   on its own rung before its owner.
6. Turn element block lists into tables (arrays of rows).
7. Point the HMI at the new fields: `eState`, `eErrorId`, `sts`, `det`, `tot`, and the
   `bCmd…` commands. Enter the settings again, or set them in the declarations.

**Back to** [the index](README.md).
