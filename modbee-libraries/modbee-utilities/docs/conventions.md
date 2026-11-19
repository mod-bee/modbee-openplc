# Conventions — how every block behaves

Every block in modbee-utilities follows the same rules. Each block's page only
lists what is its own; this page has the rest.

## Names

The names follow Beckhoff's TwinCAT 3 style, in plain IEC 61131-3:

| Starts with | What it is | Example |
| --- | --- | --- |
| `FB_` | a function block (it has an instance) | `FB_Pump` |
| `F_` | a function (no instance) | `F_Scale` |
| `ST_` | a structure: a record, a row, constants | `ST_PumpData` |
| `E_` | a list (enumeration) | `E_State` |
| `I_` | an interface: a pin that takes another block's instance | `I_Measurement` |

Pins, record fields and variables start with a small letter for their type, then a
capital: `b` BOOL (`bRun`), `n` a whole number (`nStartCount`), `f` a REAL / LREAL
(`fSpeed`), `t` TIME (`tDelay`), `d` DATE, `dt` DATE_AND_TIME (`dtLocalTime`), `e` a list
(`eMode`), `st` a structure (`stConfig`), `ip` an interface (`ipMotor`), `ref` a
record reference (`refData`), `a` an array (`aZones`), `dw` a DWORD.

Lists are always written with their name: `E_Mode.Auto`, `E_UtError.DryRun`. A bare
`Auto` does not compile. In every list the first value is the safe one (off, none).

## Errors and state

Every block (except the small timers, filters and functions) has the same four outputs:

| Output | Type | Meaning |
| --- | --- | --- |
| `bError` | BOOL | TRUE while a trip, or a setting fault, is active now. Wire it to a fault lamp or an alarm |
| `bWarning` | BOOL | TRUE while a warning is active now (nothing has been stopped) |
| `eErrorId` | `E_UtError` | Which error: the first one since the last reset (first-out); with no error the first warning; `None` when all is well |
| `eState` | `E_State` | What the block is doing now |

`E_State` is one list for every block, so an HMI can colour every device the same way:

| `eState` | Meaning |
| --- | --- |
| `Off` | Switched off, not in use, or not fitted |
| `Idle` | Ready, nothing to do |
| `Waiting` | Wants to act but waits (a delay, a permissive, a clock) |
| `Starting` | Starting (a start delay, a valve opening, a sequence starting) |
| `Running` | Running, open, active |
| `Stopping` | Stopping (a stop sequence, a valve closing) |
| `Held` | Held: paused, interlocked, an alarm standing |
| `Fault` | Tripped, or a setting fault |

There is no status text in the records. The HMI or SCADA shows the words for
`eState` and `eErrorId` from its own table.

### `E_UtError` codes

`E_UtError` is a UINT with fixed numbers, grouped by family. A number never changes;
new codes are added in their group.

| Group | Codes |
| --- | --- |
| none | `None` 0 |
| 1-99 configuration | `BadSetting` 1, `SettingRefused` 2, `NoRecord` 3, `NoMotor` 4, `PartLost` 5, `ValueBad` 6, `LimitsBad` 7, `BelowMin` 8, `AboveMax` 9, `NotAbove` 10, `NotBelow` 11, `NoChannels` 12, `RecipeBad` 13, `NoClock` 14 |
| 100-199 motor / actuator | `Overload` 100, `NoFeedback` 101, `FeedbackLost` 102, `Stuck` 103, `Thermistor` 104, `DriveFault` 105, `ExternalFault` 106, `SpeedDeviation` 107, `TravelTimeout` 108, `BothLimits` 109, `PositionLost` 110, `Changeover` 111, `PositionDeviation` 112, `Stall` 113, `Underspeed` 114, `Overspeed` 115, `CurrentHigh` 116, `CurrentLow` 117, `StartTooLong` 118, `CurrentBad` 119, `ActuatorLocal` 120, `TorqueSwitch` 121, `SlowStroke` 122 |
| 200-299 pump | `SealLeak` 200, `PrimeTimeout` 201, `MaxRun` 202, `StartFail` 203, `Dropped` 204, `PressureLow` 205, `PressureHigh` 206, `NoFlow` 207, `DryRun` 208, `NoneAvailable` 209, `CleanFailed` 210, `ServiceDue` 211, `PumpDiagnosis` 212, `NoPreRun` 213, `NotReaching` 220, `Hunting` 221, `FillTimeout` 222, `LowAtMax` 223, `NoExtSpeed` 224, `PvStaging` 225, `BoosterLost` 240 |
| 300-399 measurement | `SignalLow` 300, `SignalHigh` 301, `SensorBad` 302, `Frozen` 303, `NoMeasurement` 304, `SwitchDisagree` 305, `RateHigh` 306, `RateLow` 307, `StateAlarm` 308, `Chatter` 309, `SensorsDisagree` 310, `SensorDeviates` 311, `OneSensorLeft` 312, `Simulated` 313, `PulsesWhileStopped` 314, `PulsesTooFast` 315 |
| 400-499 level / process | `LevelHighHigh` 400, `LevelHigh` 401, `LevelLow` 402, `LevelLowLow` 403, `SourceLow` 404, `TransducerFault` 405, `FloatsDisagree` 406 |
| 500-599 runs | `RunAborted` 500, `RunMaxTime` 501, `MeterFailed` 502, `GateTimeout` 503, `StepTimeout` 504, `StockLow` 505, `OverCapacity` 506, `OutOfTolerance` 507, `MaxQuantity` 508, `ZoneFlow` 510, `MasterValve` 511, `PumpWait` 512, `RunCapped` 513 |
| 600-699 system / links | `LinkLost` 600, `Bypassed` 601, `ConditionOut` 602, `RouteLost` 603, `RouteBlocked` 604, `NoStorage` 605, `NotAuto` 606, `SelectorFault` 607, `Protection` 699 |
| 700-799 IO map | `IoArraySize` 700, `IoAddress` 701, `IoNotFitted` 702, `IoShared` 703, `IoForced` 704, `IoMissing` 705, `IoBad` 706 |

Three of them appear on almost every block:
- `NoRecord`: the block's `refData` pin is not wired. The block does nothing else.
- `BadSetting`: a setting is not usable and there is no good copy to put back (below).
- `SettingRefused`: a bad write was refused and the good copy put back (a warning, until a reset).

### Why it stopped: `E_StopReason`

Equipment, runs and doses say why they last stopped: `None`, `Off`, `Interlock`,
`OwnerLost` (its owner stopped calling it), `Fault`, `Request` (the request ended),
`Part` (a part stopped it), `PowerCut`, `Hand`, `MaxRun`, `Manual` (a stop command),
`Done` (the target was reached), `PauseMax`, `Abort`, `MaxQuantity`, `TimeCap` (a
part's safety time cap), `LevelEnd`, `IrrigatorStop`, `PumpFault` and `Rain` (an
irrigation program's ends).

## Records via `refData`

Each block with settings has a **record**: one structure `ST_<Name>Data` that holds its
HMI commands, its settings and its status. Declare one variable of that type per block
instance and wire it to the block's `refData` pin. Variants add a second record pin
for their own part (`FB_MotorVsd`: `refData` and `refDriveData`).

The record is in groups, the same in every block:

| Group | What | Who writes it |
| --- | --- | --- |
| `bRunCommand…`, `nCommandBits…` (top level) | HMI commands | the HMI / SCADA writes; the block acts and sets it back |
| `set` | settings | the HMI / SCADA, or the declaration |
| `sts` | status: what it is doing, what is wrong | the block |
| `det` | details: times left, times so far | the block |
| `tot` | totals: hours, starts, volumes, counts | the block (kept over a power cut) |

**Commands.** A command acts when it is written TRUE (or a number for an `nCommandBits…`), and
the block sets it back to FALSE (or -1). A block page says when a command acts only
once per write even if the master keeps writing TRUE.

**Constants.** Some blocks take a second structure on a `stConfig` pin: engineering
constants (a signal type and raw span, a tank shape, which switches are fitted). Set
them once, in the variable's declaration. They are not settings: an HMI does not
change them.

An unwired `refData` gives `bError` with `NoRecord`, and the block does nothing.

## Kept settings and put-back

Declare the records as ordinary variables, **not RETAIN**: each block keeps what must
be kept itself.

- **A kept copy.** Each block keeps a retained copy of its last good `set`, with a
  layout number. At power-up (and after a download) the copy goes back into the
  record's `set`. A new library version whose settings layout changed starts again
  from the declaration.
- **A bad write is put back.** Every scan the block checks `set`. A good `set` becomes
  the kept copy. A bad one (a NaN, a negative time, a value out of range, a list value
  that does not exist) is replaced by the kept copy, **the whole set at once**, and
  `sts.bSettingRefused` comes on: a warning `SettingRefused` until a reset.
- **No good copy.** A `set` that is bad and was never good (a bad declaration) is
  `bError` `BadSetting`. What the block does then is safe for it and is on its page:
  most do nothing, a valve goes to its safe position with every output off, a stirrer
  never holds its pump.
- **Rows** (tables, below) are kept the same way, one row at a time, for the first 16
  or 32 rows (the block's page says how many). A row that was never good is left out
  and reported.
- **Totals** (`tot`) are kept too: hourly, and at the events the block's page lists
  (a stop, a dose end, a reset).

The kept copy is the block's own variable, so you never declare anything RETAIN for a
library block.

## Equipment with an owner

Motors, pumps and valves are **equipment** (they extend the base `FB_Equipment`).
Equipment always has an owner and has **no Run / Start / Stop pins**:

- **Off / Hand / Auto / Out of service** is the record's `set.eMode`, kept over a power cut
  (`set.eModeAtPowerUp := E_PowerUp.Off` forces Off at every power-up).
  - **Off**: nothing runs. Switching to Off resets the trips whose cause has gone
    (`set.bOffResetsFaults`).
  - **Hand**: the record's `bCmdStart` / `bCmdStop`, or an
    [FB_LocalControl](blocks/FB_LocalControl.md) on the panel door. A start waits out
    the restart delay. Hand never resumes by itself after a power cut. No owner
    reaches it. `set.tMaxHandRunTime` (0 = none) ends a Hand run after that long (stop
    reason `MaxRun`).
  - **Jog** (Hand only): a held jog button
    ([FB_MotorJog](blocks/FB_MotorJog.md)) runs the motor while it is held, past its
    trips, restart delay and permissive; only Off and `bInterlock` stop it. A jog is a
    panel button only, never an HMI one.
  - **Auto**: it follows its **owner**. The owner is the block whose `ip…` pin you wire
    this instance to: a pump's `ipMotor`, a level control's `ipEquipment`, a group's
    `ipMember1`, a zone's `ipValve`, a route's `ipValve1`. The owner asks every scan;
    an owner that stops asking (its rung false, the block deleted) is `OwnerLost`
    and the equipment stops. A start waits for the permissive, the restart delay, the
    system's power-up hold and no part holding it. `bCmdStop` in Auto stops it until
    the owner's request drops.
  - **Out of service** (motors and valves; not pumps): taken out for maintenance.
    Nothing runs, and no protection trips or warns; it is not ready and not available,
    so a group or a station uses the others.
- **`bInterlock`** FALSE stops it in every mode, Hand too. It is not a fault.
- **`bPermissive`** FALSE blocks a start; a running device keeps running.
- **Trips** (its own protections and its parts') stop it in every mode. The first one
  is `eErrorId`.
- **After a reset** clears a trip, it runs again at once while its owner still asks
  (`set.bRestartAfterReset`, default TRUE). FALSE: the owner's request must drop and
  come back first, for machines that must not restart unexpectedly (`sts.bWaitRequestDrop`
  shows it is waiting).
- **`set.bWarnWhenNotAuto`**: a warning (`NotAuto`) while it is not in Auto and the plant is
  (the `ipSystem` block in Auto; unwired: always expected in Auto).

Unwired, `bInterlock` and `bPermissive` are TRUE (OK).

The owner's request reaches the equipment on its next scan (one scan later).

**Run / Start / Stop / Reset pins** stay on blocks driven by a wire: a run
([FB_Run](blocks/FB_Run.md)), a level control, a dose, a sequence, a zone program. These
are the blocks that own the equipment.

**Hand and HOA.** A panel's Off / Hand / Auto selector and start / stop buttons are an
[FB_LocalControl](blocks/FB_LocalControl.md) wired to the equipment (`ipEquipment`). Where
the mode comes from is its `set.eModeSource` (an `E_ModeSource`):
- `Hmi`: the selector is not used; the mode is the equipment's own (its record, the HMI).
- `Switch` (the default on FB_LocalControl): the selector sets the mode (Hand, Auto,
  neither = Off); the HMI cannot change it.
- `Remote`: the selector's Off and Hand act on the panel; its Auto hands the mode to the
  operator's choice on the HMI.

Both selector contacts made is Off and a warning (`SelectorFault`).
[FB_SystemMode](blocks/FB_SystemMode.md) uses the same `set.eModeSource` for the plant's
Off / Manual / Auto selector.

The panel buttons beyond start and stop (low / high speed, reverse, a valve's halt or
positions) reach the equipment through `I_LocalChoice`, which FB_Motor2Speed,
FB_MotorRev, FB_ValveMotor and FB_Valve3Pos offer. A choice acts in Hand only; an
owner without that choice ignores the button.

**What owners read.** Every equipment block offers `I_Equipment`, which includes
`fActRunHours` (its run hours; 0 where not counted), so a group can rotate by run hours.
A pump also offers `I_Pump`: its role (`eActRole`: `Duty`, `Jockey` or `Booster`,
from `set.ePumpRole`) and its capacity (`fActCapacity`, from `set.fFlowAtFullSpeed`), read by
FB_Group and FB_Cascade.

**The system.** Wire the [FB_SystemMode](blocks/FB_SystemMode.md) instance to every
block's `ipSystem` pin: those blocks then follow the plant's Auto, wait out its
power-on delay (`bPowerUpHold`), and reset on its reset button. Unwired: no system.

## Parts and observers

A **part** is a small block that adds one ability to its owner. Parts are placed only
where they are fitted:

| Part | Owner | What it adds |
| --- | --- | --- |
| [FB_Protection](blocks/FB_Protection.md) | any equipment, a level control | a trip or warning on a signal (thermistor, seal leak, external fault, maximum run) |
| [FB_LevelCheck](blocks/FB_LevelCheck.md) | any equipment, a level control, a run, a group | a high or low check on a measurement (dry run, low pressure, no flow, source low, tank full) |
| [FB_MotorCurrent](blocks/FB_MotorCurrent.md) | a motor | current from a CT: high, low, a start too long, a bad CT |
| [FB_StarterSoft](blocks/FB_StarterSoft.md) | a motor | a soft starter's top of ramp |
| [FB_Rotation](blocks/FB_Rotation.md) | a motor | shaft speed: stall, belt slip, overspeed |
| [FB_PumpPrime](blocks/FB_PumpPrime.md) | a pump | a prime before the start |
| [FB_Starts](blocks/FB_Starts.md) | a motor or a pump | a starts-per-hour limit |
| [FB_Exercise](blocks/FB_Exercise.md) | a level control, a valve | a short run after a long idle time |
| [FB_LevelFloats](blocks/FB_LevelFloats.md) | a level control | float backup and a check of the transmitter |
| [FB_SumpClean](blocks/FB_SumpClean.md) | a level control | a pump-down cleaning run |
| [FB_Booster](blocks/FB_Booster.md) | a level control | a series booster pump |
| [FB_RunVolume](blocks/FB_RunVolume.md), [FB_RunPause](blocks/FB_RunPause.md), [FB_RunGate](blocks/FB_RunGate.md) | a run | a volume target with a safety cap, a pause, a permissive wait |


- Wire the owner's instance to the part's `ipOwner` (or `ipRun`) pin. On its first call
  the part adds itself to its owner.
- The **owner** evaluates its parts inside its own scan. A part only stops, holds,
  masks, pauses or warns; only the owner starts anything.
- Give each part its own rung and call it every scan. **Put the parts' rungs before
  their owner's rung.** A part whose rung stops being called while it acts (a trip, a
  hold) raises `PartLost` on its owner until a reset: a deleted rung never leaves a
  protection silently off.

An **observer** ([FB_RunLog](blocks/FB_RunLog.md), [FB_PumpDiag](blocks/FB_PumpDiag.md))
only watches a block and changes nothing. A missing observer rung stops nothing.

Two motor add-ons are neither: [FB_MotorJog](blocks/FB_MotorJog.md) works the motor's
jog command, and [FB_MotorSimulate](blocks/FB_MotorSimulate.md) sits between the field
feedback and the motor's `bRunFeedback` pin.

## Rows (tables)

Blocks that handle a list of items take **tables**: arrays the project declares, with
one row per item, on in-out pins. Typically one table of settings and one of live rows:
[FB_AlarmTable](blocks/FB_AlarmTable.md) takes `aAlarmSettings : ARRAY[1..8] OF ST_AlarmSet`
and `aAlarms : ARRAY[1..8] OF ST_Alarm`.

- Declare the arrays any size (up to the block's limit) and with any lower bound. Row 1
  is always the first element: the row number is the item's number for the HMI.
- Tables that belong together are declared the same size. Most blocks give `bError` when they are not;
  FB_Sequencer and FB_StepSeq use the rows both tables have.
- The project writes its part of a live row on the item's own rung (a coil on
  `aAlarms[3].bConditionPresent`); the block writes the rest.

## Retained data

What a block keeps over a power cut:

- **Settings**: the kept copy of `set` and of its rows.
- **Totals**: run hours, starts, strokes, volumes, dose totals, counts, the last run's
  figures; written hourly and at events, never every scan.
- **States written only on an event**, so a power cut does not lose them: a group's
  lead pump, a latching valve's last position, a run's and a zone's progress (for a
  resume), an event log's kept copy, a link supervisor's reboot count.

Never kept: trips (a fault still there trips again), alarms, timers, live values and
sequences in progress. Sequences come back idle with every output off.

Two live values are kept, as **approved safety exceptions**:
- [FB_IrrDefer](blocks/FB_IrrDefer.md)'s weather defer (written on a change only), so a
  power cut during rain does not start irrigating;
- [FB_LinkSupervisor](blocks/FB_LinkSupervisor.md)'s count window without a clock
  (written every 1/24 of the window), so a dead link can never make the controller
  reboot in a loop.

There are no day totals anywhere: the boards have no real-time clock. Blocks give
running totals; SCADA makes the days.

## Protections

Every protection in every block works the same way. Its settings are an
`ST_ProtectionSet` in the block's `set`, its status an `ST_ProtectionSts` in `sts`.

| `ST_ProtectionSet` | Meaning |
| --- | --- |
| `eActionOnFault` | `Off` (ignored), `Warn` (a warning), `Trip` (stops: `bError`), `Signal` (the owner reacts, for example a pause, with no alarm) |
| `tTripDelay` | The condition must last this long |
| `eResetMode` | How it clears: `Auto`, `Retry` or `Manual` (below) |
| `tAutoRecoverAfter` | The cause must have been gone this long before it clears |
| `nMaxRetriesBeforeLockout` | `Retry`: trips in the window before it locks out |

| `ST_ProtectionSts` | Meaning |
| --- | --- |
| `eFaultState` | `Clear`, `Pending` (the delay runs), `Warning`, `Tripped`, `Locked`, `Recovering`, `Signal` |
| `nRetriesUsed` | Trips counted in the retry window |
| `nTripCount` | Trips since the counter was cleared |
| `tTimeLeft` | The delay before it acts, or the recover wait before it clears |

Reset modes:
- **Auto**: clears once the cause has been gone for `tAutoRecoverAfter`, and the equipment
  carries on.
- **Retry**: as Auto, but after `nMaxRetriesBeforeLockout` trips within the block's
  `set.tRetryCountWindow` it locks out and needs a reset.
- **Manual**: stays until a reset, taken only while the cause is gone.

A reset is the record's `bCmdResetFaults`, a `bResetFaults` pin where the block has one, the
system's reset button (`ipSystem`), or switching the equipment to Off. A reset clears
trips only, never totals or counts: those have their own commands.

A bad protection setting never removes the protection: an unknown response acts as
Trip, an unknown reset as Retry, a negative delay as 0 (a warning `BadSetting`).

## Inputs are TRUE = active

A fault input is TRUE when tripped, a float TRUE when it is made, a stop button TRUE
when pressed. There is no "NC" setting: wire a normally-closed contact through `NOT`
at the pin. A broken wire then reads as tripped, which is the safe side.

## Measurements and meters

Measurement blocks ([FB_AnalogIn](blocks/FB_AnalogIn.md),
[FB_SwitchSet](blocks/FB_SwitchSet.md), [FB_Vessel](blocks/FB_Vessel.md),
[FB_SignalSelect](blocks/FB_SignalSelect.md) and the decorators) offer
`I_Measurement`: wire the instance to another block's `ipLevel`, `ipMeasurement`, `ipProcessValue`,
`ipPressure`, `ipFlow` pin. The consumer reads its value, its health, whether it is
fitted on this site, its unit and its switch bands. A bad measurement is never used as
if it were good.

Meters ([FB_PulseMeter](blocks/FB_PulseMeter.md), [FB_FlowTotal](blocks/FB_FlowTotal.md),
[FB_RegisterMeter](blocks/FB_RegisterMeter.md), [FB_LevelMeter](blocks/FB_LevelMeter.md))
offer `I_Meter`: the total, the rate per hour, and its health.

Decorators ([FB_MeasFilter](blocks/FB_MeasFilter.md),
[FB_MeasFrozen](blocks/FB_MeasFrozen.md), [FB_MeasOverride](blocks/FB_MeasOverride.md))
sit between a measurement and its consumers: wire the measurement to the decorator's
`ipMeasurement`, and the decorator to the consumers.

## Shared lists

| List | Values |
| --- | --- |
| `E_Mode` | `Off`, `Hand`, `Auto`, `OutOfService` (motors and valves) |
| `E_ModeSource` | `Hmi`, `Switch`, `Remote` (where the mode comes from: FB_LocalControl, FB_SystemMode) |
| `E_PumpRole` | `Duty`, `Jockey`, `Booster` (a pump's `set.ePumpRole`) |
| `E_LocalChoice` | `None`, `Low`, `High`, `Forward`, `Reverse`, `Pos1`, `Pos2`, `Pos3`, `Halt` (panel choices) |
| `E_PowerUp` | `Last` (back in the mode it had), `Off` |
| `E_SysMode` | `Off`, `Manual`, `Auto` (the plant, FB_SystemMode) |
| `E_Response` | `Off`, `Warn`, `Trip`, `Signal` |
| `E_ResetMode` | `Manual`, `Retry`, `Auto` |
| `E_ProtState` | `Clear`, `Pending`, `Warning`, `Tripped`, `Locked`, `Recovering`, `Signal` |
| `E_Cause` | `Always`, `Running`, `Stopped` (when a protection counts) |
| `E_RateUnit` | `PerSec`, `PerMin`, `PerHour`, `PerDay` |
| `E_RunResume` | `Resume`, `Restart`, `None` (a run after a power cut) |
| `E_Band` | `None`, `LowLow`, `Low`, `High`, `HighHigh` (switch bands) |
| `E_OnBadValue` | `Pass`, `Hold`, `Substitute`, `Stop` (what a bad value leads to: `set.eWhenValueBad` on FB_MeasOverride and FB_SpeedLoop) |
| `E_Unit` | `None`, `Bar`, `KPa`, `Psi`, `MetreH2O`, `LitrePerSec`, `LitrePerMin`, `M3PerHour`, `GalPerMin`, `Litre`, `M3`, `MegaLitre`, `Gallon`, `DegC`, `DegF`, `Kelvin`, `Mm`, `Cm`, `Metre`, `Inch`, `Foot`, `Percent`, `Amp`, `Hertz`, `KW`, `M3PerDay`, `MegaLitrePerDay`, `Kg`, `Tonne` |
| `E_UnitKind` | `None`, `Pressure`, `Flow`, `Volume`, `Temperature`, `Length`, `Percent`, `Current`, `Frequency`, `Power`, `Mass` |
| `E_IoSrc`, `E_IoKind`, `E_IoQ` | the IO map's sources, kinds and channel qualities ([FB_IoMapIn](blocks/FB_IoMapIn.md)) |

## Time

Blocks measure time from `TIME()` differences, carrying the part of a millisecond left
over, so a delay or a total is the same at any task interval. Times left are always
visible in `det` (or `sts`) beside the status, never inside a text.

## Ladder rules

The full rules are in [ladder-rules.md](ladder-rules.md). In short:

- **One block per rung**, with nothing in series in front of it. A block on a false
  rung is not called: its timers stop and its outputs hold.
- **Ladder uses pins.** Some blocks also have methods and properties (listed on their
  pages under "Read from ST"). Those are for ST code and for the blocks you wire them
  to; Ladder never needs them.
- Read and write record fields and table rows with contacts and coils.
- **Rung order**: the IO map in first, parts before their owners, zones before their
  program, the IO map out last.

**Back to** [the index](README.md).
