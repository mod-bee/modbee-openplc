# FB_Valve — Two-position valve

A two-position valve, cylinder or damper: spring return (normally closed or open) or double-acting, with end switches or travel times, a safe position and stroke counts.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bOpenLimitSwitch` | `BOOL` | `FALSE` | open end switch (TRUE = made) |
| in | `bClosedLimitSwitch` | `BOOL` |  | closed end switch (TRUE = made) |
| in | `bActuatorRemote` | `BOOL` | `TRUE` | the actuator's Local / Remote switch: FALSE = in Local, not driven |
| in | `refData` | `REFERENCE TO ST_ValveData` |  | the block's record |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bOpenOutput` | `BOOL` |  | the open coil / drive |
| out | `bCloseOutput` | `BOOL` |  | the close coil of a double-acting valve, or a normally-open valve's coil |
| out | `bIsOpen` | `BOOL` |  | open: its end switch, or the travel time passed |
| out | `bIsClosed` | `BOOL` |  | closed: its end switch, or the travel time passed |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdEquipmentMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `bSimulate` | `BOOL` |  | the end switches follow the command (travel times); not kept |
| `bCmdPresetStrokes` | `BOOL` |  | set tot.nStrokeCount to nPresetStrokeCount (cleared by the block) |
| `nPresetStrokeCount` | `UDINT` |  | the stroke count bCmdPresetStrokes writes |

**Settings `set`** (`ST_ValveSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `eModeAtPowerUp` | `E_PowerUp` |  | which mode it starts in after a power cut |
| `tRetryCountWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bOffResetsFaults` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tMaxHandRunTime` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | after a reset clears a trip, run again at once; FALSE: the owner's request must drop and come back first |
| `bWarnWhenNotAuto` | `BOOL` |  | warn NotAuto while not in Auto and the plant is in Auto |
| `eValveType` | `E_ValveType` |  | the valve kind: SpringNc, SpringNo or DoubleHeld |
| `eSafePosition` | `E_SafePos` |  | where it goes on Off, the interlock or a trip: Closed or Open |
| `tOpenStrokeTime` | `TIME` | `T#5s` | travel time (also the end switch timeout base) |
| `tCloseStrokeTime` | `TIME` | `T#5s` | travel time to close (also the end switch timeout base) |
| `bOpenLimitSwitchFitted` | `BOOL` |  | the open end switch (bOpenLimitSwitch) is fitted and used |
| `bClosedLimitSwitchFitted` | `BOOL` |  | the closed end switch (bClosedLimitSwitch) is fitted and used |
| `stStrokeTimeoutFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | the end switch did not arrive within the travel time; a protection's settings ([protections](../conventions.md#protections)) |
| `stBothLimitsFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#1s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | both end switches made at once; a protection's settings ([protections](../conventions.md#protections)) |
| `stPositionLostFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#2s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#2s, nMaxRetriesBeforeLockout := 0)` | an end switch lost while the valve is at rest; a protection's settings ([protections](../conventions.md#protections)) |
| `tSlowStrokeAbove` | `TIME` |  | a stroke slower than this warns (0 = off; needs the end switch) |
| `stSlowStrokeFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#0s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 3)` | a stroke slower than tSlowStrokeAbove (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `stActuatorInLocalFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#2s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#2s, nMaxRetriesBeforeLockout := 3)` | the actuator is switched to Local (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `stNoMovementFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#2s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#1m, nMaxRetriesBeforeLockout := 3)` | no movement: commanded away, the switch of the position it left still made (protection; off by default); a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValveSts`)

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
| `bIsOpen` | `BOOL` |  | open now |
| `bIsClosed` | `BOOL` |  | closed now |
| `bTravelling` | `BOOL` |  | travelling now |
| `stStrokeTimeoutFault` | `ST_ProtectionSts` |  | the end switch did not arrive within the travel time; a protection's status ([protections](../conventions.md#protections)) |
| `stBothLimitsFault` | `ST_ProtectionSts` |  | both end switches made at once; a protection's status ([protections](../conventions.md#protections)) |
| `stPositionLostFault` | `ST_ProtectionSts` |  | an end switch lost while the valve is at rest; a protection's status ([protections](../conventions.md#protections)) |
| `tLastStrokeTime` | `TIME` |  | the last stroke confirmed by its end switch |
| `bActuatorInLocal` | `BOOL` |  | the actuator is in Local (bActuatorRemote FALSE) |
| `stSlowStrokeFault` | `ST_ProtectionSts` |  | a stroke slower than tSlowStrokeAbove (default a warning); a protection's status ([protections](../conventions.md#protections)) |
| `stActuatorInLocalFault` | `ST_ProtectionSts` |  | the actuator is switched to Local (default a warning); a protection's status ([protections](../conventions.md#protections)) |
| `stNoMovementFault` | `ST_ProtectionSts` |  | no movement: commanded away, the switch of the position it left still made (protection; off by default); a protection's status ([protections](../conventions.md#protections)) |
| `tLastOpenStrokeTime` | `TIME` |  | the last open stroke confirmed by its end switch |
| `tLastCloseStrokeTime` | `TIME` |  | the last close stroke confirmed by its end switch |

**Totals `tot`** (`ST_ValveTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStrokeCount` | `UDINT` |  | strokes, lifetime (kept hourly) |

## Lists

- `E_SafePos`: `Closed`, `Open` (default `Closed`)
- `E_ValveType`: `SpringNc`, `SpringNo`, `DoubleHeld` (default `SpringNc`)

## How it works

A two-position valve, cylinder or damper.

On `FB_Equipment`: "running" is open. An owner (a zone, a route, a level control) drives it through `I_Equipment.Request` (`bRun` = open); Hand opens / closes it from the record's `bCmdStart` / `bCmdStop` (or [`FB_LocalControl`](FB_LocalControl.md)). Off, the interlock or a trip put it in its safe position (`set.eSafePosition`), not merely closed.

Kinds (`set.eValveType`): SpringNc (coil = open), SpringNo (coil = closed), DoubleHeld (open and close coils held).

Open / closed: by its end switch when used, else after `set.tOpenStrokeTime` / `tCloseStrokeTime` from the command.

Protections: open / close timeout (the end switch not made in its travel time + 50 %), both end switches made, position lost (an end switch lost at rest), slow stroke (`set.tSlowStrokeAbove` > 0: a stroke confirmed by its end switch that took longer, a sign of wear; `set.stSlowStrokeFault`, default a warning, until a stroke within the time), actuator in Local (`bActuatorRemote` FALSE: the actuator's own Local / Remote switch; every output off, not available to its owner, the travel checks wait; `set.stActuatorInLocalFault`, default a warning after 2 s), no movement (`set.stNoMovementFault`, off by default: commanded away and the end switch of the position it left still made). Strokes counted (`tot.nStrokeCount`; the record's `bCmdPresetStrokes` sets it to `nPresetStrokeCount`); the last stroke's time per direction (`sts.tLastOpenStrokeTime` / `tLastCloseStrokeTime`, with `sts.tLastStrokeTime` the latest). Simulation (the record's `bSimulate`, not kept, cleared by a system reset): the end switches are ignored and the travel times decide, with a warning (Simulated).

Exercise: an [`FB_Exercise`](FB_Exercise.md) part on the valve (`ipOwner` := the valve) opens an idle valve in Auto for its run time (a part's Request, honoured in Auto like the owner's own: interlock, trips and the permissive still apply).

Variants (EXTENDS `FB_Valve`): [`FB_ValveLatch`](FB_ValveLatch.md) (latching pulses), [`FB_ValveMotor`](FB_ValveMotor.md) (motorised: torque switches, Halt).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

Variants: [`FB_ValveLatch`](FB_ValveLatch.md) (latching pulse valve), [`FB_ValveMotor`](FB_ValveMotor.md) (motorised). Positioning valves: [`FB_ValveMod`](FB_ValveMod.md), [`FB_ValveFloat`](FB_ValveFloat.md).

## Example

An irrigation solenoid valve (spring return, normally closed) with an open end switch.

| Pin | Wire |
| --- | --- |
| `bOpenLimitSwitch` | `DI_V1_Open` |
| `refData` | `stValve1` |
| `bOpenOutput` | `DO_V1_Coil` |

Its owner (a zone, a route) opens it in Auto.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

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
