# FB_ValveMotor — Motorised two-position valve

A motorised two-position valve or damper: open and close drives never together, a reversal pause, the drive stopping at the end.

It extends [FB_Valve](FB_Valve.md): everything of it (pins, record, protections), plus what is below.

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `refMotor` | `REFERENCE TO ST_ValveMotorData` |  | its record |
| in | `bTorqueOpen` | `BOOL` |  | the open torque switch tripped |
| in | `bTorqueClose` | `BOOL` |  | the close torque switch tripped |
| in | `bOpenLs` | `BOOL` | `FALSE` | Open end switch (TRUE = made) *(from FB_Valve)* |
| in | `bClosedLs` | `BOOL` |  | end switches, used when set.bUseOpenLs / bUseClosedLs *(from FB_Valve)* |
| in | `refData` | `REFERENCE TO ST_ValveData` |  | Its record (a variable of this type) *(from FB_Valve)* |
| in | `bActRemote` | `BOOL` | `TRUE` | the actuator's Local / Remote switch: FALSE = in Local, not driven *(from FB_Valve)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bOpenOut` | `BOOL` |  | the open coil / drive *(from FB_Valve)* |
| out | `bCloseOut` | `BOOL` |  | the close coil of a double-acting valve, or a normally-open valve's coil *(from FB_Valve)* |
| out | `bIsOpen` | `BOOL` |  | Open: its end switch, or the travel time passed *(from FB_Valve)* |
| out | `bIsClosed` | `BOOL` |  | Closed: its end switch, or the travel time passed *(from FB_Valve)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveMotorData` (pin `refMotor`)

**Settings `set`** (`ST_ValveMotorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tReversal` | `TIME` | `T#500ms` | pause between the two directions |
| `bDriveHold` | `BOOL` |  | keep the drive on at the end |
| `bCloseOnTorque` | `BOOL` |  | the close torque at the end of a close = seated (closed) |
| `stTorque` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Retry, tRecover := T#1m, nMaxRetries := 3)` | default Trip, Retry; a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValveMotorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bDriving` | `BOOL` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `bHalted` | `BOOL` |  | stopped where it is (Halt, or a torque trip) |
| `stTorque` | `ST_ProtectionSts` |  | default Trip, Retry; a protection's status ([protections](../conventions.md#protections)) |

## Record `ST_ValveData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |

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

**Totals `tot`** (`ST_ValveTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStrokes` | `UDINT` |  | Strokes, lifetime (kept hourly) |

## Lists

- `E_SafePos`: `Closed`, `Open` (default `Closed`)
- `E_ValveType`: `SpringNc`, `SpringNo`, `DoubleHeld` (default `SpringNc`)

## How it works

A motorised two-position valve or damper.

Everything of [`FB_Valve`](FB_Valve.md) (modes, the safe position, the owner, end switches or travel time, protections, strokes, actuator in Local, slow stroke, exercise) plus the drive: `bOpenOut` drives open, `bCloseOut` drives closed, never together, `set.tReversal` between them ([`FB_Changeover`](FB_Changeover.md)); the drive stops at the end (its end switch, or the travel time), or stays on with `set.bDriveHold`. `set.eType` is not used.

Torque switches (`bTorqueOpen` / `bTorqueClose`, TRUE = tripped: jammed): `set.stTorque` (default Trip, Retry); a torque trip stops the drive where it is (the actuator has failed: it is not driven to the safe position). With `set.bCloseOnTorque` the close torque at the end of a close is the seat, not a fault: the valve is closed (also without a closed switch) until the next command.

Halt ([`FB_LocalControl`](FB_LocalControl.md)'s `bHalt`, `I_LocalChoice`): in Hand the drive stops where it is, the position not known, until the next open / close command.

## Example

A motorised butterfly valve with open and closed limit switches.

| Pin | Wire |
| --- | --- |
| `bOpenLs` | `DI_V2_Open` |
| `bClosedLs` | `DI_V2_Closed` |
| `refData` | `stValve2` |
| `refMotor` | `stVm2` |
| `bOpenOut` | `DO_V2_DriveOpen` |
| `bCloseOut` | `DO_V2_DriveClose` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Choose(eChoice) : BOOL`: a panel choice (FB_LocalControl bHalt): in Hand, stop where it is
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
