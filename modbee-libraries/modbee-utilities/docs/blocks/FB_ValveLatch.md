# FB_ValveLatch — Latching valve

A latching (pulsed) DC solenoid valve: a pulse on the open or close coil when the position changes; the last position is kept over a power cut.

It extends [FB_Valve](FB_Valve.md): everything of it (pins, record, protections), plus what is below.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `refLatch` | `REFERENCE TO ST_ValveLatchData` |  | its record |
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

## Record `ST_ValveLatchData` (pin `refLatch`)

**Settings `set`** (`ST_ValveLatchSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPulse` | `TIME` | `T#500ms` | coil pulse length |

**Status `sts`** (`ST_ValveLatchSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPulsing` | `BOOL` |  |  |
| `nLastPos` | `USINT` |  | the kept position: 0 unknown, 1 closed, 2 open |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Record `ST_ValveData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
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

A latching valve: a DC latching solenoid (3-wire, or 2-wire through an H-bridge) moved by a pulse on its open or close coil.

Everything of [`FB_Valve`](FB_Valve.md) (modes, the safe position, the owner, end switches or travel time, protections, strokes, actuator in Local, slow stroke, exercise) plus the pulses: `bOpenOut` / `bCloseOut` pulse for `set.tPulse` when the position commanded changes. The last commanded position is kept over a power cut (written only on a move), so nothing is sent at power-up when the wanted position is the kept one; a valve whose kept position is unknown gets its pulse. `set.eType` is not used. With the actuator in Local no pulse is sent; a change of position is sent once it is back in Remote.

## Example

A DC latching valve on two outputs.

| Pin | Wire |
| --- | --- |
| `refData` | `stValve1` |
| `refLatch` | `stLatch1` |
| `bOpenOut` | `DO_V1_Open` |
| `bCloseOut` | `DO_V1_Close` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

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
