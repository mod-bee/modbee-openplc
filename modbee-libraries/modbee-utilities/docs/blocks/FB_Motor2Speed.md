# FB_Motor2Speed — Two-speed starter

A two-speed starter (Dahlander or separate windings): low and high contactors never on together, an optional star-bridge contactor and an optional start in low.

It extends [FB_Motor](FB_Motor.md): everything of it (pins, record, protections), plus what is below.

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bAutoHigh` | `BOOL` | `FALSE` | Auto speed when the owner gives none |
| in | `bFeedbackLow` | `BOOL` |  | The low speed contactor's aux |
| in | `bFeedbackHigh` | `BOOL` |  | the auxes |
| in | `refTwo` | `REFERENCE TO ST_Motor2SpeedData` |  | its record |
| in | `bFeedback` | `BOOL` |  | run feedback contact *(from FB_Motor)* |
| in | `bOverload` | `BOOL` |  | TRUE = the overload relay has tripped *(from FB_Motor)* |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | Its record (a variable of this type) *(from FB_Motor)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bQLow` | `BOOL` |  | The low speed contactor |
| out | `bQHigh` | `BOOL` |  | never with bQLow |
| out | `bQBridge` | `BOOL` |  | Dahlander: the star point, with high only |
| out | `bHighSpeed` | `BOOL` |  | running at high |
| out | `bQ` | `BOOL` |  | run output *(from FB_Motor)* |
| out | `bHoldOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced *(from FB_Motor)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_Motor2SpeedData` (pin `refTwo`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdLow` | `BOOL` |  | Hand low (and start); cleared by the block |
| `bCmdHigh` | `BOOL` |  | Hand high (and start); cleared by the block |

**Settings `set`** (`ST_Motor2SpeedSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tSpeedChange` | `TIME` | `T#1s` | dead time low -> high |
| `tDownChange` | `TIME` |  | high -> low (0 = tSpeedChange) |
| `bStartInLow` | `BOOL` | `TRUE` |  |
| `tLowStart` | `TIME` | `T#3s` |  |
| `bDahlander` | `BOOL` |  |  |
| `fLowSpeedPct` | `REAL` | `50.0` | low speed as % of high |
| `bHandHigh` | `BOOL` |  | Hand speed chosen last (kept) |
| `tChangeover` | `TIME` | `T#2s` | An aux must follow its coil within this time |
| `stChangeover` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Manual, tRecover := T#0s, nMaxRetries := 0)` | default Manual; a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_Motor2SpeedSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bHighSpeed` | `BOOL` |  | running at high |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `stChangeover` | `ST_ProtectionSts` |  | default Manual; a protection's status ([protections](../conventions.md#protections)) |

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

A two-speed starter, Dahlander or separate windings.

Everything of [`FB_Motor`](FB_Motor.md) (modes, protections, totals, `refData`) plus the speed choice. `bQ` = TRUE while either speed is asked to run; the per-speed auxes confirm running (`bFeedback` is not used).

Speed: Hand -> `set.bHandHigh` (kept; `bCmdLow` / `bCmdHigh`, or [`FB_LocalControl`](FB_LocalControl.md)'s `bLow` / `bHigh`, choose it and start in Hand); Auto -> the owner's speed (Request `fSpeed`: <= `set.fLowSpeedPct` = low, above = high; none = `bAutoHigh`). With `set.bStartInLow` a start to high runs low for `set.tLowStart` first. Low -> high waits `set.tSpeedChange`, high -> low `set.tDownChange` (0 = the same) ([`FB_Changeover`](FB_Changeover.md)). An aux that does not follow its coil within `set.tChangeover` trips `set.stChangeover` (default Manual): `bError` Changeover. A planned gap never counts as feedback lost. `fActSpeed`: `fLowSpeedPct` or 100.

Jog: [`FB_MotorJog`](FB_MotorJog.md). Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A two-speed fan (Dahlander).

| Pin | Wire |
| --- | --- |
| `bAutoHigh` | `bFanHigh` (the Auto speed when the owner gives none) |
| `bFeedbackLow` | `DI_Low_Aux` |
| `bFeedbackHigh` | `DI_High_Aux` |
| `bOverload` | `DI_Overload` |
| `refData` | `stMotor4` |
| `refTwo` | `stTwo4` |
| `bQLow` | `DO_Low` |
| `bQHigh` | `DO_High` |
| `bQBridge` | `DO_StarBridge` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Choose(eChoice) : BOOL`: a panel choice (FB_LocalControl bLow / bHigh): in Hand, as bCmdLow / bCmdHigh
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
