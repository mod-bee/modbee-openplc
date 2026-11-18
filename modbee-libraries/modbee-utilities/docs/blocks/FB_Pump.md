# FB_Pump — Pump

One pump: its run decision (start / stop delays, minimum run and off times), start fail and dropped checks, and the motor it drives (`ipMotor`). Its owner (a level control, a group, a run) drives it.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_Pump`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMotor` | `I_Motor` |  | the motor it drives (required). A motor block's instance (FB_Motor or a variant) |
| in | `refData` | `REFERENCE TO ST_PumpData` |  | Its record (a variable of this type) |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PumpData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |

**Settings `set`** (`ST_PumpSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `tRetryWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bResetByOff` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tHandMax` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `bWarnNotAuto` | `BOOL` |  | the owner's request must drop and come back first warn NotAuto while not in Auto and the plant is in Auto |
| `tMinOff` | `TIME` |  | after a stop, before the next start (a power-up counts as a stop) |
| `tStartDelay` | `TIME` |  | the request must last this long to start |
| `tStopDelay` | `TIME` |  | the request must be gone this long to stop |
| `tMinRun` | `TIME` |  | anti-short-cycle (a trip stops at once) |
| `tStartMask` | `TIME` | `T#10s` | after a start, parts that mask at start ignore their cause |
| `stStartFail` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#10s, eReset := E_ResetMode.Retry, tRecover := T#1m, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stDropped` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#0s, eReset := E_ResetMode.Manual, tRecover := T#0s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `eRole` | `E_PumpRole` |  | its role in a station |
| `fCapacity` | `REAL` |  | flow at full speed, in the station's flow unit (0 = not known) |

**Status `sts`** (`ST_PumpSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | first-out: the first error since the last reset |
| `eStopReason` | `E_StopReason` |  | Why it last stopped |
| `bRunning` | `BOOL` |  | It runs (status) |
| `bReady` | `BOOL` |  | could start now if asked |
| `bAvailable` | `BOOL` |  | in Auto, not tripped, not interlocked |
| `bLinked` | `BOOL` |  | an owner is driving it |
| `bInterlocked` | `BOOL` |  | The interlock is holding it off |
| `bRefused` | `BOOL` |  | a setting write was refused and put back |
| `bJogging` | `BOOL` |  | jogging (FB_MotorJog, Hand only) |
| `bMustCycle` | `BOOL` |  | a reset cleared a trip: waiting for the request to drop (bRestartAfterReset) |
| `bMotorInHand` | `BOOL` |  |  |
| `bMotorFaulted` | `BOOL` |  |  |
| `bMasked` | `BOOL` |  | the start mask is on |
| `stStartFail` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stDropped` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_PumpDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRunTime` | `TIME` |  | this run |
| `tTimeLeft` | `TIME` |  | of the start delay, minimum run or stop delay now counting |

## Lists

- `E_PumpRole`: `Duty`, `Jockey`, `Booster` (default `Duty`)

## How it works

One pump: its owner link, its run decision and the motor it drives.

The pump has its own Off / Hand / Auto; the motor has its own too and follows the pump only while the motor is in Auto: a motor in Hand bypasses the pump ("motor in Hand": not available to the owner). `set.bWarnNotAuto` warns NotAuto while the pump or its motor is not in Auto (and the plant is).

Auto: the owner's request after `set.tStartDelay` (it must last that long), kept for `set.tMinRun` and until it has been gone `set.tStopDelay`; after a stop, `set.tMinOff` (a power-up counts as a stop).

Built in: start fail (asked, motor ready, not running) and dropped (stopped by itself while asked: a warning kept until reset, never holding the pump). The start mask (`set.tStartMask` after each start) is offered to parts that mask at start (low pressure, no flow ...). A faulted motor is a warning on the pump.

## Example

Pump 1 drives motor 1; a level control drives the pump.

| Pin | Wire |
| --- | --- |
| `ipMotor` | `fbMotor1` (its FB_Motor) |
| `ipSystem` | `fbSystem` |
| `refData` | `stPump1` |

Then `ipTarget := fbPump1` on the FB_LevelControl (or `ipMember1 := fbPump1` on an FB_Group). Put its parts (FB_LevelCheck for dry run, FB_Protection for a seal leak) on their own rungs with `ipOwner := fbPump1`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `eActRole : E_PumpRole`: Auto: start delay, minimum run, stop delay
- property `fActCapacity : REAL`
- property `fActSpeed : REAL`
- method `Request(bRun, bHold, fSpeed, bUrgent) : E_UtError`
- method `Command(eCmd)`
- property `eActMode : E_Mode`
- property `bIsRunning : BOOL`
- property `bIsReady : BOOL`
- property `bIsAvailable : BOOL`
- property `bIsAuto : BOOL`
- property `bIsFaulted : BOOL`
- property `eActError : E_UtError`
- property `eActStopReason : E_StopReason`
- property `fActRunHours : REAL`

## See also

[FB_Motor](FB_Motor.md), [FB_LevelCheck](FB_LevelCheck.md), [FB_Protection](FB_Protection.md), [FB_PumpPrime](FB_PumpPrime.md), [FB_Starts](FB_Starts.md), [FB_Group](FB_Group.md), [FB_LevelControl](FB_LevelControl.md)

**Back to** [the index](../README.md).
