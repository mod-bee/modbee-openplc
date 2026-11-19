# FB_Motor — Direct-on-line motor

Runs and protects one motor on a contactor or a run relay: overload, no feedback, feedback lost and stuck, with run hours and starts. It has its own Off / Hand / Auto; in Auto its owner (a pump, a group, a sequence) drives it.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_Motor`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunFeedback` | `BOOL` |  | run feedback contact |
| in | `bOverloadTripped` | `BOOL` |  | TRUE = the overload relay has tripped |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | the block's record |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bRunOutput` | `BOOL` |  | run output |
| out | `bHoldOutputOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

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

A direct-on-line motor or a run relay.

Built in: overload, no feedback (never came after a start), feedback lost (went while running), stuck (stays after a stop); run hours and starts. Everything else is a part placed beside it ([`FB_Protection`](FB_Protection.md) for a thermistor / drive fault / external fault, [`FB_LocalControl`](FB_LocalControl.md) for Hand buttons and HOA, ...).

Detail (det): `tMinOffTimeLeft`, `tThisRunTime` (this run), `tIdleTime` (since the last stop, 0 while running), `tHandTimeLeft` (a Hand run's time left under `set.tMaxHandRunTime`, 0 = none counting).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump motor on a contactor, with an overload relay and a contactor aux.

| Pin | Wire |
| --- | --- |
| `bRunFeedback` | `DI_M1_Aux` |
| `bOverloadTripped` | `DI_M1_Overload` (TRUE = tripped) |
| `bInterlock` | `fbInterlock1.bPermissive` |
| `ipSystem` | `fbSystem` |
| `refData` | `stMotor1` |
| `bRunOutput` | the contactor coil `DO_M1_Run` |

The motor's owner (an FB_Pump with `ipMotor := fbMotor1`) starts and stops it in Auto. In Hand, the HMI's `stMotor1.bCmdStart` / `bCmdStop` or an FB_LocalControl run it.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

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

## See also

[FB_MotorVsd](FB_MotorVsd.md), [FB_MotorRev](FB_MotorRev.md), [FB_MotorStarDelta](FB_MotorStarDelta.md), [FB_Motor2Speed](FB_Motor2Speed.md), [FB_Protection](FB_Protection.md), [FB_MotorCurrent](FB_MotorCurrent.md), [FB_StarterSoft](FB_StarterSoft.md), [FB_MotorJog](FB_MotorJog.md), [FB_MotorSimulate](FB_MotorSimulate.md), [FB_Rotation](FB_Rotation.md), [FB_LocalControl](FB_LocalControl.md), [FB_Pump](FB_Pump.md)

**Back to** [the index](../README.md).
