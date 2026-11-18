# FB_Valve — Two-position valve

A two-position valve, cylinder or damper: spring return (normally closed or open) or double-acting, with end switches or travel times, a safe position and stroke counts.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bOpenLs` | `BOOL` | `FALSE` | Open end switch (TRUE = made) |
| in | `bClosedLs` | `BOOL` |  | end switches, used when set.bUseOpenLs / bUseClosedLs |
| in | `refData` | `REFERENCE TO ST_ValveData` |  | Its record (a variable of this type) |
| in | `bActRemote` | `BOOL` | `TRUE` | the actuator's Local / Remote switch: FALSE = in Local, not driven |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bOpenOut` | `BOOL` |  | the open coil / drive |
| out | `bCloseOut` | `BOOL` |  | the close coil of a double-acting valve, or a normally-open valve's coil |
| out | `bIsOpen` | `BOOL` |  | Open: its end switch, or the travel time passed |
| out | `bIsClosed` | `BOOL` |  | Closed: its end switch, or the travel time passed |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `bSimulate` | `BOOL` |  | the end switches follow the command (travel times); not kept |
| `bCmdPreset` | `BOOL` |  | set tot.nStrokes to nPresetStrokes (cleared by the block) |
| `nPresetStrokes` | `UDINT` |  |  |

**Settings `set`** (`ST_ValveSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `tRetryWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bResetByOff` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tHandMax` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `bWarnNotAuto` | `BOOL` |  | the owner's request must drop and come back first warn NotAuto while not in Auto and the plant is in Auto |
| `eType` | `E_ValveType` |  | The valve kind |
| `eSafe` | `E_SafePos` |  | Where it goes on Off, the interlock or a trip: `Closed` or `Open` |
| `tOpenTime` | `TIME` | `T#5s` | travel time (also the end switch timeout base) |
| `tCloseTime` | `TIME` | `T#5s` | Travel time to close (also the arrival time without an end switch) |
| `bUseOpenLs` | `BOOL` |  | The open end switch (`bOpenLs`) is fitted and used |
| `bUseClosedLs` | `BOOL` |  | The closed end switch (`bClosedLs`) is fitted and used |
| `stTravel` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Retry, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stBothLimits` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#1s, eReset := E_ResetMode.Manual, tRecover := T#0s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stPositionLost` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#2s, eReset := E_ResetMode.Auto, tRecover := T#2s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `tStrokeWarn` | `TIME` |  | a stroke slower than this warns (0 = off; needs the end switch) |
| `stSlowStroke` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#0s, eReset := E_ResetMode.Auto, tRecover := T#0s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stActLocal` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#2s, eReset := E_ResetMode.Auto, tRecover := T#2s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stNoMovement` | `ST_ProtectionSet` | `(eResponse := E_Response.Off, tDelay := T#2s, eReset := E_ResetMode.Retry, tRecover := T#1m, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValveSts`)

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
| `bOpen` | `BOOL` |  | Open (status) |
| `bClosed` | `BOOL` |  | Closed (status) |
| `bMoving` | `BOOL` |  | Travelling (status) |
| `stTravel` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stBothLimits` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stPositionLost` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `tLastStroke` | `TIME` |  | the last stroke confirmed by its end switch |
| `bActLocal` | `BOOL` |  | the actuator is in Local (bActRemote FALSE) |
| `stSlowStroke` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stActLocal` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stNoMovement` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `tLastOpenStroke` | `TIME` |  | the last open stroke confirmed by its end switch |
| `tLastCloseStroke` | `TIME` |  | the last close stroke confirmed by its end switch |

**Totals `tot`** (`ST_ValveTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStrokes` | `UDINT` |  | Strokes, lifetime (kept hourly) |

## Lists

- `E_SafePos`: `Closed`, `Open` (default `Closed`)
- `E_ValveType`: `SpringNc`, `SpringNo`, `DoubleHeld` (default `SpringNc`)

## How it works

A two-position valve, cylinder or damper.

On `FB_Equipment`: "running" is open. An owner (a zone, a route, a level control) drives it through `I_Equipment.Request` (`bRun` = open); Hand opens / closes it from the record's `bCmdStart` / `bCmdStop` (or [`FB_LocalControl`](FB_LocalControl.md)). Off, the interlock or a trip put it in its safe position (`set.eSafe`), not merely closed.

Kinds (`set.eType`): SpringNc (coil = open), SpringNo (coil = closed), DoubleHeld (open and close coils held).

Open / closed: by its end switch when used, else after `set.tOpenTime` / `tCloseTime` from the command.

Protections: open / close timeout (the end switch not made in its travel time + 50 %), both end switches made, position lost (an end switch lost at rest), slow stroke (`set.tStrokeWarn` > 0: a stroke confirmed by its end switch that took longer, a sign of wear; `set.stSlowStroke`, default a warning, until a stroke within the time), actuator in Local (`bActRemote` FALSE: the actuator's own Local / Remote switch; every output off, not available to its owner, the travel checks wait; `set.stActLocal`, default a warning after 2 s), no movement (`set.stNoMovement`, off by default: commanded away and the end switch of the position it left still made). Strokes counted (`tot.nStrokes`; the record's `bCmdPreset` sets it to `nPresetStrokes`); the last stroke's time per direction (`sts.tLastOpenStroke` / `tLastCloseStroke`, with `sts.tLastStroke` the latest). Simulation (the record's `bSimulate`, not kept, cleared by a system reset): the end switches are ignored and the travel times decide, with a warning (Simulated).

Exercise: an [`FB_Exercise`](FB_Exercise.md) part on the valve (`ipOwner` := the valve) opens an idle valve in Auto for its run time (a part's Request, honoured in Auto like the owner's own: interlock, trips and the permissive still apply).

Variants (EXTENDS `FB_Valve`): [`FB_ValveLatch`](FB_ValveLatch.md) (latching pulses), [`FB_ValveMotor`](FB_ValveMotor.md) (motorised: torque switches, Halt).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

Variants: [`FB_ValveLatch`](FB_ValveLatch.md) (latching pulse valve), [`FB_ValveMotor`](FB_ValveMotor.md) (motorised). Positioning valves: [`FB_ValveMod`](FB_ValveMod.md), [`FB_ValveFloat`](FB_ValveFloat.md).

## Example

An irrigation solenoid valve (spring return, normally closed) with an open end switch.

| Pin | Wire |
| --- | --- |
| `bOpenLs` | `DI_V1_Open` |
| `refData` | `stValve1` |
| `bOpenOut` | `DO_V1_Coil` |

Its owner (a zone, a route) opens it in Auto.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

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
