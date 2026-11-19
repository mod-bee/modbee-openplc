# FB_Motor2Speed — Two-speed starter

A two-speed starter (Dahlander or separate windings): low and high contactors never on together, an optional star-bridge contactor and an optional start in low.

It extends [FB_Motor](FB_Motor.md): everything of it (pins, record, protections), plus what is below.

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bAutoHighSpeed` | `BOOL` | `FALSE` | Auto speed when the owner gives none |
| in | `bLowSpeedFeedback` | `BOOL` |  | the low speed contactor's aux |
| in | `bHighSpeedFeedback` | `BOOL` |  | the high speed contactor's aux |
| in | `refTwoSpeedData` | `REFERENCE TO ST_Motor2SpeedData` |  | the two-speed record |
| in | `bRunFeedback` | `BOOL` |  | run feedback contact *(from FB_Motor)* |
| in | `bOverloadTripped` | `BOOL` |  | TRUE = the overload relay has tripped *(from FB_Motor)* |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | the block's record *(from FB_Motor)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bLowSpeedOutput` | `BOOL` |  | the low speed contactor |
| out | `bHighSpeedOutput` | `BOOL` |  | never with bLowSpeedOutput |
| out | `bBridgeOutput` | `BOOL` |  | Dahlander: the star point, with high only |
| out | `bRunningHigh` | `BOOL` |  | running at high speed |
| out | `bRunOutput` | `BOOL` |  | run output *(from FB_Motor)* |
| out | `bHoldOutputOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced *(from FB_Motor)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_Motor2SpeedData` (pin `refTwoSpeedData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdHandLowSpeed` | `BOOL` |  | Hand low (and start); cleared by the block |
| `bCmdHandHighSpeed` | `BOOL` |  | Hand high (and start); cleared by the block |

**Settings `set`** (`ST_Motor2SpeedSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tLowToHighDeadTime` | `TIME` | `T#1s` | dead time low -> high |
| `tHighToLowDeadTime` | `TIME` |  | high -> low (0 = tLowToHighDeadTime) |
| `bStartInLowSpeed` | `BOOL` | `TRUE` | a start to high runs low first for tLowSpeedStartTime |
| `tLowSpeedStartTime` | `TIME` | `T#3s` | how long a start to high runs in low first |
| `bDahlanderWinding` | `BOOL` |  | a Dahlander motor: bBridgeOutput closes the star point with high |
| `fLowSpeedPct` | `REAL` | `50.0` | low speed as % of high |
| `bHandHighSelected` | `BOOL` |  | Hand speed chosen last (kept) |
| `tAuxFeedbackTimeout` | `TIME` | `T#2s` | an aux contact must follow its coil within this time |
| `stAuxFeedbackFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | an aux did not follow its coil (contactor fault); default Manual reset; a protection's settings ([protections](../conventions.md#protections)) |
| `bJogAtHighSpeed` | `BOOL` |  | a jog (FB_MotorJog) runs at high speed (FALSE: low) |

**Status `sts`** (`ST_Motor2SpeedSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRunningHigh` | `BOOL` |  | running at high speed |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stAuxFeedbackFault` | `ST_ProtectionSts` |  | an aux did not follow its coil (contactor fault); default Manual reset; a protection's status ([protections](../conventions.md#protections)) |

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

A two-speed starter, Dahlander or separate windings.

Everything of [`FB_Motor`](FB_Motor.md) (modes, protections, totals, `refData`) plus the speed choice. `bRunOutput` = TRUE while either speed is asked to run; the per-speed auxes confirm running (`bRunFeedback` is not used).

Speed: Hand -> `set.bHandHighSelected` (kept; `bCmdHandLowSpeed` / `bCmdHandHighSpeed`, or [`FB_LocalControl`](FB_LocalControl.md)'s `bLowSpeedButton` / `bHighSpeedButton`, choose it and start in Hand); Auto -> the owner's speed (Request `fSpeedSetpointPct`: <= `set.fLowSpeedPct` = low, above = high; none = `bAutoHighSpeed`). With `set.bStartInLowSpeed` a start to high runs low for `set.tLowSpeedStartTime` first. Low -> high waits `set.tLowToHighDeadTime`, high -> low `set.tHighToLowDeadTime` (0 = the same) ([`FB_Changeover`](FB_Changeover.md)). An aux that does not follow its coil within `set.tAuxFeedbackTimeout` trips `set.stAuxFeedbackFault` (default Manual): `bError` Changeover. A planned gap never counts as feedback lost. `fActSpeedPct`: `fLowSpeedPct` or 100.

Jog: [`FB_MotorJog`](FB_MotorJog.md), at `set.bJogAtHighSpeed`'s speed. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A two-speed fan (Dahlander).

| Pin | Wire |
| --- | --- |
| `bAutoHighSpeed` | `bFanHigh` (the Auto speed when the owner gives none) |
| `bLowSpeedFeedback` | `DI_Low_Aux` |
| `bHighSpeedFeedback` | `DI_High_Aux` |
| `bOverloadTripped` | `DI_Overload` |
| `refData` | `stMotor4` |
| `refTwoSpeedData` | `stTwo4` |
| `bLowSpeedOutput` | `DO_Low` |
| `bHighSpeedOutput` | `DO_High` |
| `bBridgeOutput` | `DO_StarBridge` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- method `Choose(eLocalChoice) : BOOL`: a panel choice (FB_LocalControl bLowSpeedButton / bHighSpeedButton): in Hand, as bCmdHandLowSpeed / bCmdHandHighSpeed
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
