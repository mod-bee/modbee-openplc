# FB_MotorVsd — Motor on a variable speed drive

A motor on a variable speed drive over hard-wired IO: run, running and ready relays, a speed reference and feedback, speed limits, ramps, a skip band and a drive-reset pulse.

It extends [FB_Motor](FB_Motor.md): everything of it (pins, record, protections), plus what is below.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bDriveReady` | `BOOL` | `TRUE` | the drive's ready relay: lost while running is a fault; not ready holds a new start |
| in | `fSpeedFeedbackPct` | `REAL` | `-1.0` | the actual speed %; below 0 = not wired |
| in | `refDriveData` | `REFERENCE TO ST_VsdData` |  | the drive record |
| in | `bRunFeedback` | `BOOL` |  | run feedback contact *(from FB_Motor)* |
| in | `bOverloadTripped` | `BOOL` |  | TRUE = the overload relay has tripped *(from FB_Motor)* |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | the block's record *(from FB_Motor)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fSpeedReferencePct` | `REAL` |  | the speed reference, % after clamp, skip band and ramp |
| out | `nSpeedReferenceRaw` | `UINT` |  | the speed reference scaled to fRawAtZeroPct..fRawAtFullPct (a Modbus register, %QW) |
| out | `bDriveResetPulse` | `BOOL` |  | a pulse to the drive's reset input on an operator reset |
| out | `bAtSpeed` | `BOOL` |  | the speed reference has reached its target |
| out | `bRunOutput` | `BOOL` |  | run output *(from FB_Motor)* |
| out | `bHoldOutputOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced *(from FB_Motor)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VsdData` (pin `refDriveData`)

**Settings `set`** (`ST_VsdSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinSpeedPct` | `REAL` |  | lowest speed while running, % |
| `fMaxSpeedPct` | `REAL` | `100.0` | highest speed, % |
| `fAccelPctPerSec` | `REAL` |  | % per second (0 = the drive ramps) |
| `fDecelPctPerSec` | `REAL` |  | speed fall, % per second (0 = the drive ramps) |
| `fSkipBandLow` | `REAL` |  | resonance band (equal = off) |
| `fSkipBandHigh` | `REAL` |  | top of the speed band to skip |
| `fHandSpeedPct` | `REAL` | `50.0` | speed in Hand, % |
| `fAutoSpeedPct` | `REAL` | `100.0` | speed in Auto when the owner gives none, % |
| `fRawAtZeroPct` | `REAL` |  | raw speed reference at 0 % (a register or card value) |
| `fRawAtFullPct` | `REAL` | `65535.0` | raw speed reference at 100 % |
| `tDriveResetPulse` | `TIME` | `T#500ms` | length of the bDriveReset pulse on an operator reset |
| `fSpeedDeviationPct` | `REAL` | `10.0` | speed deviation, % |
| `stDriveNotReadyFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#1s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | the drive's ready relay lost while running; a protection's settings ([protections](../conventions.md#protections)) |
| `stSpeedDeviationFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#10s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the speed feedback is off the reference by more than fSpeedDeviationPct; a protection's settings ([protections](../conventions.md#protections)) |
| `tDriveOwnRampTime` | `TIME` |  | the drive's own 0 -> 100 % time: bAtSpeed / speedDev wait for it |
| `fRatedFrequency` | `REAL` |  | the motor's frequency at 100 % (display; 0 = none) |
| `fRatedRpm` | `REAL` |  | its speed at 100 % (display; 0 = none) |
| `fJogSpeedPct` | `REAL` |  | the speed while jogging (FB_MotorJog), % (0 = fHandSpeedPct) |
| `eRateUnit` | `E_RateUnit` |  | fAccelPctPerSec / fDecelPctPerSec: % per second (default), minute, hour or day |

**Status `sts`** (`ST_VsdSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSpeedReferencePct` | `REAL` |  | the speed reference sent, % after clamp, skip band and ramp |
| `fSpeedFeedbackPct` | `REAL` |  | the actual speed %; below 0 = not wired |
| `bAtSpeed` | `BOOL` |  | the speed reference has reached its target |
| `bDriveReady` | `BOOL` |  | the drive's ready relay |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stDriveNotReadyFault` | `ST_ProtectionSts` |  | the drive's ready relay lost while running; a protection's status ([protections](../conventions.md#protections)) |
| `stSpeedDeviationFault` | `ST_ProtectionSts` |  | the speed feedback is off the reference by more than fSpeedDeviationPct; a protection's status ([protections](../conventions.md#protections)) |
| `fSpeedHz` | `REAL` |  | the speed in Hz (set.fRatedFrequency) |
| `fSpeedRpm` | `REAL` |  | the speed in rpm (set.fRatedRpm) |

## Record `ST_MotorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdEquipmentMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `bCmdPresetTotals` | `BOOL` |  | set the totals to the preset values (rising edge, cleared) |
| `fPresetRunHours` | `LREAL` |  | the run hours bCmdPresetTotals writes (a replacement motor) |
| `nPresetStartCount` | `UDINT` |  | the starts bCmdPresetTotals writes |

**Settings `set`** (`ST_MotorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `eModeAtPowerUp` | `E_PowerUp` |  | which mode it starts in after a power cut |
| `tRetryCountWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bOffResetsFaults` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tMaxHandRunTime` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | after a reset clears a trip, run again at once; FALSE: the owner's request must drop and come back first |
| `bWarnWhenNotAuto` | `BOOL` |  | warn NotAuto while not in Auto and the plant is in Auto |
| `tMinOffTime` | `TIME` | `T#5s` | after a stop, before the next start |
| `bRunFeedbackFitted` | `BOOL` | `TRUE` | use the run feedback (bFeedback); FALSE: no feedback checks |
| `stOverloadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#100ms, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | overload relay tripped; a protection's settings ([protections](../conventions.md#protections)) |
| `stNoRunFeedbackFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#3s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#30s, nMaxRetriesBeforeLockout := 3)` | the run feedback never came after a start; a protection's settings ([protections](../conventions.md#protections)) |
| `stRunFeedbackLostFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#500ms, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#30s, nMaxRetriesBeforeLockout := 3)` | the run feedback went while running; a protection's settings ([protections](../conventions.md#protections)) |
| `stStuckOnFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#3s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | the run feedback stays after a stop (contactor stuck); a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_MotorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault |
| `eErrorId` | `E_UtError` |  | first-out: the first error since the last reset |
| `eStopReason` | `E_StopReason` |  | why it last stopped |
| `bRunning` | `BOOL` |  | running now |
| `bReady` | `BOOL` |  | could start now if asked |
| `bAvailable` | `BOOL` |  | in Auto, not tripped, not interlocked |
| `bOwnerDriving` | `BOOL` |  | an owner is driving it |
| `bInterlocked` | `BOOL` |  | the interlock is off: it cannot run |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and put back |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `bJogging` | `BOOL` |  | jogging (FB_MotorJog, Hand only) |
| `bWaitRequestDrop` | `BOOL` |  | a reset cleared a trip: waiting for the request to drop (bRestartAfterReset) |
| `bFaulted` | `BOOL` |  | tripped now (as the bIsFaulted property) |
| `eModeInUse` | `E_Mode` |  | the mode it is in now (as the eActMode property) |
| `stOverloadFault` | `ST_ProtectionSts` |  | overload relay tripped; a protection's status ([protections](../conventions.md#protections)) |
| `stNoRunFeedbackFault` | `ST_ProtectionSts` |  | the run feedback never came after a start; a protection's status ([protections](../conventions.md#protections)) |
| `stRunFeedbackLostFault` | `ST_ProtectionSts` |  | the run feedback went while running; a protection's status ([protections](../conventions.md#protections)) |
| `stStuckOnFault` | `ST_ProtectionSts` |  | the run feedback stays after a stop (contactor stuck); a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_MotorDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tMinOffTimeLeft` | `TIME` |  | time left before a start is allowed (restart delay) |
| `tThisRunTime` | `TIME` |  | this run |
| `tIdleTime` | `TIME` |  | since the last stop (0 while running) |
| `tHandTimeLeft` | `TIME` |  | a Hand run's time left under set.tMaxHandRunTime (0 = none counting) |

**Totals `tot`** (`ST_MotorTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRunHours` | `LREAL` |  | run hours, lifetime (kept) |
| `nStartCount` | `UDINT` |  | starts, lifetime (kept) |

## How it works

A variable speed drive over hard-wired IO.

Everything of [`FB_Motor`](FB_Motor.md) (modes, protections, the plug, totals, `refData`) plus the speed. `bRunOutput` = the drive's run command; `bRunFeedback` = the drive's running relay.

Speed asked for: Auto -> the owner's speed (Request `fSpeedSetpointPct`, < 0 = `set.fAutoSpeedPct`); Hand -> `set.fHandSpeedPct`.

Clamped to `fMinSpeedPct`..fMaxSpeedPct; a target inside the skip band holds at its near edge; ramped by `fAccelPctPerSec` / `fDecelPctPerSec` (% per `set.eRateUnit`: second by default, minute, hour or day; 0 = the drive ramps); a start begins from `fMinSpeedPct`. A jog ([`FB_MotorJog`](FB_MotorJog.md)) runs at `set.fJogSpeedPct` (0 = `fHandSpeedPct`).

Drive protections: driveNotReady (the ready relay lost while running), speedDev (\|reference - `fSpeedFeedbackPct`\| past `set.fSpeedDeviationPct` while running with the ramp done and `set.tDriveOwnRampTime` passed since the reference stopped changing, `fSpeedFeedbackPct` wired). `bAtSpeed`: the ramp done, and by `fSpeedFeedbackPct` within `fSpeedDeviationPct`, or without `fSpeedFeedbackPct` once `set.tDriveOwnRampTime` (the drive's own 0 -> 100 % ramp time, 0 = none) has passed since the reference stopped changing.

The speed in Hz and rpm (`sts.fSpeedHz`, `sts.fSpeedRpm`, for display): the feedback while running when wired, else the reference, x `set.fRatedFrequency` / `fRatedRpm` at 100 % (0 = not shown).

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump on a VSD with run, running and ready relays and a 0-10 V speed reference.

| Pin | Wire |
| --- | --- |
| `bRunFeedback` | `DI_VSD1_Running` |
| `bDriveReady` | `DI_VSD1_Ready` |
| `bOverloadTripped` | `DI_VSD1_Fault` |
| `refData` | `stMotor1` |
| `refDriveData` | `stVsd1` |
| `bRunOutput` | `DO_VSD1_Run` |
| `nSpeedReferenceRaw` | the analog output `AO_VSD1_Speed` |
| `bDriveResetPulse` | `DO_VSD1_Reset` |

Its owner (an FB_Pump, an FB_SpeedLoop, an FB_Group) asks for the speed.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActSpeedPct : REAL`: the speed now, % (0 when stopped)
- method `Request(bRun, bHoldOff, fSpeedSetpointPct, bOverflowUrgent) : E_UtError`
- method `Command(eCommand)`
- property `eActMode : E_Mode`: the mode it is in now
- property `bIsRunning : BOOL`: running now
- property `bIsReady : BOOL`: could start now if asked
- property `tActIdleTime : TIME`: time since the last stop (0 while running)
- property `tActHandTimeLeft : TIME`: a Hand run's time left under set.tMaxHandRunTime (0 = none counting)
- property `bIsAvailable : BOOL`: in Auto, not tripped, not interlocked
- property `bIsAuto : BOOL`: in Auto now
- property `bIsFaulted : BOOL`: a trip or setting fault is active
- property `eActError : E_UtError`: the error shown now
- property `eActStopReason : E_StopReason`: why it last stopped
- property `fActRunHours : REAL`: run hours (0 where not counted): rotation by hours
