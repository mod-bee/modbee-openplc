# FB_MotorStarDelta — Star-delta starter

A star-delta starter: main, star and delta contactors, the timed star stage and the open transition, star and delta never on together.

It extends [FB_Motor](FB_Motor.md): everything of it (pins, record, protections), plus what is below.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bFeedbackStar` | `BOOL` | `FALSE` | star contactor aux (optional) |
| in | `bFeedbackDelta` | `BOOL` |  | delta contactor aux |
| in | `refSd` | `REFERENCE TO ST_StarDeltaData` |  | its record |
| in | `fCurrentPct` | `REAL` | `-1.0` | the motor current, % of full load (FB_MotorCurrent.fPercent; < 0 = not wired) |
| in | `bFeedback` | `BOOL` |  | run feedback contact *(from FB_Motor)* |
| in | `bOverload` | `BOOL` |  | TRUE = the overload relay has tripped *(from FB_Motor)* |
| in | `refData` | `REFERENCE TO ST_MotorData` |  | Its record (a variable of this type) *(from FB_Motor)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bQStar` | `BOOL` |  | never with bQDelta |
| out | `bQDelta` | `BOOL` |  | never on together |
| out | `bQ` | `BOOL` |  | run output *(from FB_Motor)* |
| out | `bHoldOff` | `BOOL` |  | TRUE: the overload or the thermistor is tripped: hold the output off, even forced *(from FB_Motor)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StarDeltaData` (pin `refSd`)

**Settings `set`** (`ST_StarDeltaSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tStarTime` | `TIME` | `T#6s` | or, with set.fStarCurrentPct > 0, until the star current has risen to and fallen back below that % of full load, whichever comes first |
| `tTransition` | `TIME` | `T#60ms` | open-transition gap |
| `bUseStarDeltaFb` | `BOOL` |  |  |
| `tChangeover` | `TIME` | `T#2s` | contactors must open / close within this |
| `stChangeover` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Manual, tRecover := T#0s, nMaxRetries := 0)` | default Manual; a protection's settings ([protections](../conventions.md#protections)) |
| `fStarCurrentPct` | `REAL` |  | > 0: to delta early once the star current falls below this % of full load |

**Status `sts`** (`ST_StarDeltaSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bInStar` | `BOOL` |  |  |
| `bInDelta` | `BOOL` |  |  |
| `tStarLeft` | `TIME` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stChangeover` | `ST_ProtectionSts` |  | default Manual; a protection's status ([protections](../conventions.md#protections)) |
| `bCurrentRisen` | `BOOL` |  | the star current has risen to fStarCurrentPct in this start |

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

A star-delta starter.

Everything of [`FB_Motor`](FB_Motor.md) (modes, protections, totals, `refData`) plus the star -> delta sequence. `bQ` = the main contactor; `bFeedback` = the main contactor's aux.

Sequence: main and star together; star for `set.tStarTime` (or, with `set.fStarCurrentPct` > 0, until the star current has risen to and fallen back below that % of full load, whichever comes first) and the main confirmed; star off; the open transition (`set.tTransition`, and with `bUseStarDeltaFb` the star aux open); delta on ([`FB_Changeover`](FB_Changeover.md)). An aux that does not follow its coil within `set.tChangeover` trips `set.stChangeover` (default Manual): `bError` Changeover. `fStarCurrentPct` > 0 with `fCurrentPct` not wired: a warning (BadSetting), the star time alone.

Jog: [`FB_MotorJog`](FB_MotorJog.md).

Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A large pump motor started star-delta.

| Pin | Wire |
| --- | --- |
| `bFeedback` | `DI_Main_Aux` |
| `bFeedbackStar` | `DI_Star_Aux` |
| `bFeedbackDelta` | `DI_Delta_Aux` |
| `bOverload` | `DI_Overload` |
| `refData` | `stMotor2` |
| `refSd` | `stSd2` |
| `bQ` | `DO_Main` |
| `bQStar` | `DO_Star` |
| `bQDelta` | `DO_Delta` |

Set `stSd2.set.bUseStarDeltaFb := TRUE` when the star and delta auxes are wired.

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

**Back to** [the index](../README.md).
