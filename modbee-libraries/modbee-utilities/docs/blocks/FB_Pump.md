# FB_Pump — Pump

One pump: its run decision (start / stop delays, minimum run and off times), start fail and dropped checks, and the motor it drives (`ipMotor`). Its owner (a level control, a group, a run) drives it.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_Pump`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMotor` | `I_Motor` |  | the motor it drives (required). An instance of a block that offers I_Motor (FB_Motor, FB_Motor2Speed, FB_MotorRev, FB_MotorStarDelta, FB_MotorVsd, ...) |
| in | `refData` | `REFERENCE TO ST_PumpData` |  | the block's record |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PumpData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdEquipmentMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |

**Settings `set`** (`ST_PumpSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `eModeAtPowerUp` | `E_PowerUp` |  | which mode it starts in after a power cut |
| `tRetryCountWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bOffResetsFaults` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tMaxHandRunTime` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | after a reset clears a trip, run again at once; FALSE: the owner's request must drop and come back first |
| `bWarnWhenNotAuto` | `BOOL` |  | warn NotAuto while not in Auto and the plant is in Auto |
| `tMinOffTime` | `TIME` |  | after a stop, before the next start (a power-up counts as a stop) |
| `tStartDelay` | `TIME` |  | the request must last this long to start |
| `tStopDelay` | `TIME` |  | the request must be gone this long to stop |
| `tMinRunTime` | `TIME` |  | anti-short-cycle (a trip stops at once) |
| `tMaskAfterStart` | `TIME` | `T#10s` | after a start, parts that mask at start ignore their cause |
| `stStartFailFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#10s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#1m, nMaxRetriesBeforeLockout := 3)` | asked to run, motor ready, but it is not running; a protection's settings ([protections](../conventions.md#protections)) |
| `stDroppedOutFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#0s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | the motor stopped by itself while asked to run; a protection's settings ([protections](../conventions.md#protections)) |
| `ePumpRole` | `E_PumpRole` |  | its role in a station |
| `fFlowAtFullSpeed` | `REAL` |  | flow at full speed, in the station's flow unit (0 = not known) |

**Status `sts`** (`ST_PumpSts`)

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
| `bMotorInHand` | `BOOL` |  | its motor is in Hand |
| `bMotorFaulted` | `BOOL` |  | its motor has a trip |
| `bStartMaskOn` | `BOOL` |  | the start mask is on |
| `stStartFailFault` | `ST_ProtectionSts` |  | asked to run, motor ready, but it is not running; a protection's status ([protections](../conventions.md#protections)) |
| `stDroppedOutFault` | `ST_ProtectionSts` |  | the motor stopped by itself while asked to run; a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_PumpDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tThisRunTime` | `TIME` |  | this run |
| `tTimeLeft` | `TIME` |  | of the start delay, minimum run or stop delay now counting |
| `tIdleTime` | `TIME` |  | since the last stop (0 while running) |
| `tHandTimeLeft` | `TIME` |  | a Hand run's time left under set.tMaxHandRunTime (0 = none counting) |

## Lists

- `E_PumpRole`: `Duty`, `Jockey`, `Booster` (default `Duty`)

## How it works

One pump: its owner link, its run decision and the motor it drives.

The pump has its own Off / Hand / Auto; the motor has its own too and follows the pump only while the motor is in Auto: a motor in Hand bypasses the pump ("motor in Hand": not available to the owner). `set.bWarnWhenNotAuto` warns NotAuto while the pump or its motor is not in Auto (and the plant is).

Auto: the owner's request after `set.tStartDelay` (it must last that long), kept for `set.tMinRunTime` and until it has been gone `set.tStopDelay`; after a stop, `set.tMinOffTime` (a power-up counts as a stop).

Built in: start fail (asked, motor ready, not running) and dropped (stopped by itself while asked: a warning kept until reset, never holding the pump). The start mask (`set.tMaskAfterStart` after each start) is offered to parts that mask at start (low pressure, no flow ...). A faulted motor is a warning on the pump.

Detail (det): `tThisRunTime` (this run), `tIdleTime` (since the last stop, 0 while running: with `tThisRunTime`, the time in the present phase), `tTimeLeft` (of the start delay, minimum run or stop delay now counting), `tHandTimeLeft` (a Hand run's time left under `set.tMaxHandRunTime`, 0 = none counting). `set.ePumpRole` (duty, jockey, booster) and `set.fFlowAtFullSpeed` (flow at full speed) are read by stations and cascades through `I_Pump`.

## Example

Pump 1 drives motor 1; a level control drives the pump.

| Pin | Wire |
| --- | --- |
| `ipMotor` | `fbMotor1` (its FB_Motor) |
| `ipSystem` | `fbSystem` |
| `refData` | `stPump1` |

Then `ipEquipment := fbPump1` on the FB_LevelControl (or `ipMember1 := fbPump1` on an FB_Group). Put its parts (FB_LevelCheck for dry run, FB_Protection for a seal leak) on their own rungs with `ipOwner := fbPump1`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `eActRole : E_PumpRole`: Auto: start delay, minimum run, stop delay
- property `fActCapacity : REAL`: flow at full speed (0 = not known)
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

[FB_Motor](FB_Motor.md), [FB_LevelCheck](FB_LevelCheck.md), [FB_Protection](FB_Protection.md), [FB_PumpPrime](FB_PumpPrime.md), [FB_Starts](FB_Starts.md), [FB_Group](FB_Group.md), [FB_LevelControl](FB_LevelControl.md)

**Back to** [the index](../README.md).
