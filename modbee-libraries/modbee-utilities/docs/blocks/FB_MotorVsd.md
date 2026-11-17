# FB_MotorVsd — Motor on a variable speed drive

A motor on a variable speed drive over hard-wired IO: run, running and ready relays, a speed reference and feedback, speed limits, ramps, a skip band and a drive-reset pulse.

It extends [FB_Motor](FB_Motor.md): everything of it (pins, record, protections), plus what is below.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bDriveReady` | `BOOL` | `TRUE` | the drive's ready relay: lost while running is a protection; not ready holds a new start |
| in | `fSpeedFb` | `REAL` | `-1.0` | actual speed %, < 0 = not wired |
| in | `refVsd` | `REFERENCE TO ST_VsdData` |  | its record |
| in | `bFeedback` | `BOOL` |  | run feedback contact *(from FB_Motor)* |
| in | `bOverload` | `BOOL` |  | TRUE = the overload relay has tripped *(from FB_Motor)* |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | Its record (a variable of this type) *(from FB_Motor)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fSpeedRef` | `REAL` |  | % after clamp, skip band, ramp |
| out | `nSpeedRefRaw` | `UINT` |  | scaled to set.fRawMin..fRawMax, a Modbus register |
| out | `bDriveReset` | `BOOL` |  | a pulse on an operator reset |
| out | `bAtSpeed` | `BOOL` |  | The speed reference has reached its target |
| out | `bQ` | `BOOL` |  | run output *(from FB_Motor)* |
| out | `bHoldOff` | `BOOL` |  | TRUE: the block wants the output off *(from FB_Motor)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VsdData` (pin `refVsd`)

**Settings `set`** (`ST_VsdSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinSpeed` | `REAL` |  |  |
| `fMaxSpeed` | `REAL` | `100.0` |  |
| `fAccelRate` | `REAL` |  | % per second (0 = the drive ramps) |
| `fDecelRate` | `REAL` |  | % per second, 0 = the drive ramps |
| `fSkipLow` | `REAL` |  | resonance band (equal = off) |
| `fSkipHigh` | `REAL` |  |  |
| `fHandSpeed` | `REAL` | `50.0` |  |
| `fAutoSpeed` | `REAL` | `100.0` |  |
| `fRawMin` | `REAL` |  |  |
| `fRawMax` | `REAL` | `65535.0` |  |
| `tResetPulse` | `TIME` | `T#500ms` |  |
| `fDevBand` | `REAL` | `10.0` | speed deviation, % |
| `stDriveNotReady` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#1s, eReset := E_ResetMode.Retry, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stSpeedDev` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#10s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `tDriveRamp` | `TIME` |  | the drive's own 0 -> 100 % time: bAtSpeed / speedDev wait for it |
| `fRatedHz` | `REAL` |  | the motor's frequency at 100 % (display; 0 = none) |
| `fRatedRpm` | `REAL` |  | its speed at 100 % (display; 0 = none) |

**Status `sts`** (`ST_VsdSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fSpeedRef` | `REAL` |  | % after clamp, skip band, ramp |
| `fSpeedFb` | `REAL` |  | actual speed %, < 0 = not wired |
| `bAtSpeed` | `BOOL` |  |  |
| `bDriveReady` | `BOOL` |  | the drive's ready relay: lost while running is a protection; not ready holds a new start |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `stDriveNotReady` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stSpeedDev` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `fSpeedHz` | `REAL` |  | the speed in Hz (set.fRatedHz) |
| `fSpeedRpm` | `REAL` |  | the speed in rpm (set.fRatedRpm) |

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

**Totals `tot`** (`ST_MotorTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRunHours` | `LREAL` |  | Run hours, lifetime (kept) |
| `nStarts` | `UDINT` |  | Starts, lifetime (kept) |

## How it works

A variable speed drive over hard-wired IO.

Everything of [`FB_Motor`](FB_Motor.md) (modes, protections, the plug, totals, `refData`) plus the speed. `bQ` = the drive's run command; `bFeedback` = the drive's running relay.

Speed asked for: Auto -> the owner's speed (Request `fSpeed`, < 0 = `set.fAutoSpeed`); Hand -> `set.fHandSpeed`.

Clamped to `fMinSpeed`..fMaxSpeed; a target inside the skip band holds at its near edge; ramped by `fAccelRate` / `fDecelRate` (% per second, 0 = the drive ramps); a start begins from `fMinSpeed`.

Drive protections: driveNotReady (the ready relay lost while running), speedDev (\|reference - `fSpeedFb`\| past `set.fDevBand` while running with the ramp done and `set.tDriveRamp` passed since the reference stopped changing, `fSpeedFb` wired). `bAtSpeed`: the ramp done, and by `fSpeedFb` within `fDevBand`, or without `fSpeedFb` once `set.tDriveRamp` (the drive's own 0 -> 100 % ramp time, 0 = none) has passed since the reference stopped changing.

The speed in Hz and rpm (`sts.fSpeedHz`, `sts.fSpeedRpm`, for display): the feedback while running when wired, else the reference, x `set.fRatedHz` / `fRatedRpm` at 100 % (0 = not shown).

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump on a VSD with run, running and ready relays and a 0-10 V speed reference.

| Pin | Wire |
| --- | --- |
| `bFeedback` | `DI_VSD1_Running` |
| `bDriveReady` | `DI_VSD1_Ready` |
| `bOverload` | `DI_VSD1_Fault` |
| `refData` | `stMotor1` |
| `refVsd` | `stVsd1` |
| `bQ` | `DO_VSD1_Run` |
| `nSpeedRefRaw` | the analog output `AO_VSD1_Speed` |
| `bDriveReset` | `DO_VSD1_Reset` |

Its owner (an FB_Pump, an FB_SpeedLoop, an FB_Group) asks for the speed.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

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

**Back to** [the index](../README.md).
