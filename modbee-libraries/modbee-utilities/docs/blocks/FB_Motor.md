# FB_Motor — Direct-on-line motor

Runs and protects one motor on a contactor or a run relay: overload, no feedback, feedback lost and stuck, with run hours and starts. It has its own Off / Hand / Auto; in Auto its owner (a pump, a group, a sequence) drives it.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_Motor`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bFeedback` | `BOOL` |  | run feedback contact |
| in | `bOverload` | `BOOL` |  | TRUE = the overload relay has tripped |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | Its record (a variable of this type) |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bQ` | `BOOL` |  | run output |
| out | `bHoldOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `bCmdPreset` | `BOOL` |  | set the totals to the preset values (rising edge, cleared) |
| `fPresetHours` | `LREAL` |  | The run hours `bCmdPreset` writes (a replacement motor) |
| `nPresetStarts` | `UDINT` |  | The starts `bCmdPreset` writes |

**Settings `set`** (`ST_MotorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `tRetryWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bResetByOff` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tHandMax` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `bWarnNotAuto` | `BOOL` |  | the owner's request must drop and come back first warn NotAuto while not in Auto and the plant is in Auto |
| `tRestartDelay` | `TIME` | `T#5s` | after a stop, before the next start |
| `bUseFeedback` | `BOOL` | `TRUE` | Use the run feedback (`bFeedback`); FALSE: no feedback checks |
| `stOverload` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#100ms, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stNoFeedback` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#3s, eReset := E_ResetMode.Retry, tRecover := T#30s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stFeedbackLost` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#500ms, eReset := E_ResetMode.Retry, tRecover := T#30s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stStuck` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#3s, eReset := E_ResetMode.Manual, tRecover := T#0s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_MotorSts`)

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
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `bJogging` | `BOOL` |  | jogging (FB_MotorJog, Hand only) |
| `bMustCycle` | `BOOL` |  | a reset cleared a trip: waiting for the request to drop (bRestartAfterReset) |
| `stOverload` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stNoFeedback` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stFeedbackLost` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stStuck` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_MotorDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRestartIn` | `TIME` |  | Time left before a start is allowed (restart delay) |
| `tRunTime` | `TIME` |  | this run |
| `tIdleTime` | `TIME` |  | since the last stop (0 while running) |
| `tHandLeft` | `TIME` |  | a Hand run's time left under set.tHandMax (0 = none counting) |

**Totals `tot`** (`ST_MotorTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRunHours` | `LREAL` |  | Run hours, lifetime (kept) |
| `nStarts` | `UDINT` |  | Starts, lifetime (kept) |

## How it works

A direct-on-line motor or a run relay.

Built in: overload, no feedback (never came after a start), feedback lost (went while running), stuck (stays after a stop); run hours and starts. Everything else is a part placed beside it ([`FB_Protection`](FB_Protection.md) for a thermistor / drive fault / external fault, [`FB_LocalControl`](FB_LocalControl.md) for Hand buttons and HOA, ...).

Detail (det): `tRestartIn`, `tRunTime` (this run), `tIdleTime` (since the last stop, 0 while running), `tHandLeft` (a Hand run's time left under `set.tHandMax`, 0 = none counting).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump motor on a contactor, with an overload relay and a contactor aux.

| Pin | Wire |
| --- | --- |
| `bFeedback` | `DI_M1_Aux` |
| `bOverload` | `DI_M1_Overload` (TRUE = tripped) |
| `bInterlock` | `fbInterlock1.bOk` |
| `ipSystem` | `fbSystem` |
| `refData` | `stMotor1` |
| `bQ` | the contactor coil `DO_M1_Run` |

The motor's owner (an FB_Pump with `ipMotor := fbMotor1`) starts and stops it in Auto. In Hand, the HMI's `stMotor1.bCmdStart` / `bCmdStop` or an FB_LocalControl run it.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActSpeed : REAL`
- method `Request(bRun, bHold, fSpeed, bUrgent) : E_UtError`
- method `Command(eCmd)`
- property `eActMode : E_Mode`
- property `bIsRunning : BOOL`
- property `bIsReady : BOOL`
- property `tActIdleTime : TIME`
- property `tActHandLeft : TIME`
- property `bIsAvailable : BOOL`
- property `bIsAuto : BOOL`
- property `bIsFaulted : BOOL`
- property `eActError : E_UtError`
- property `eActStopReason : E_StopReason`
- property `fActRunHours : REAL`

## See also

[FB_MotorVsd](FB_MotorVsd.md), [FB_MotorRev](FB_MotorRev.md), [FB_MotorStarDelta](FB_MotorStarDelta.md), [FB_Motor2Speed](FB_Motor2Speed.md), [FB_Protection](FB_Protection.md), [FB_MotorCurrent](FB_MotorCurrent.md), [FB_StarterSoft](FB_StarterSoft.md), [FB_MotorJog](FB_MotorJog.md), [FB_MotorSimulate](FB_MotorSimulate.md), [FB_Rotation](FB_Rotation.md), [FB_LocalControl](FB_LocalControl.md), [FB_Pump](FB_Pump.md)

**Back to** [the index](../README.md).
