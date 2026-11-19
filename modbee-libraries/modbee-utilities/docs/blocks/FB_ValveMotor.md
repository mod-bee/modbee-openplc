# FB_ValveMotor — Motorised two-position valve

A motorised two-position valve or damper: open and close drives never together, a reversal pause, the drive stopping at the end.

It extends [FB_Valve](FB_Valve.md): everything of it (pins, record, protections), plus what is below.

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bOpenTorqueTripped` | `BOOL` |  | the open torque switch tripped |
| in | `bCloseTorqueTripped` | `BOOL` |  | the close torque switch tripped |
| in | `refMotorisedData` | `REFERENCE TO ST_ValveMotorData` |  | the motorised valve record |
| in | `bOpenLimitSwitch` | `BOOL` | `FALSE` | open end switch (TRUE = made) *(from FB_Valve)* |
| in | `bClosedLimitSwitch` | `BOOL` |  | closed end switch (TRUE = made) *(from FB_Valve)* |
| in | `bActuatorRemote` | `BOOL` | `TRUE` | the actuator's Local / Remote switch: FALSE = in Local, not driven *(from FB_Valve)* |
| in | `refData` | `REFERENCE TO ST_ValveData` |  | the block's record *(from FB_Valve)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bOpenOutput` | `BOOL` |  | the open coil / drive *(from FB_Valve)* |
| out | `bCloseOutput` | `BOOL` |  | the close coil of a double-acting valve, or a normally-open valve's coil *(from FB_Valve)* |
| out | `bIsOpen` | `BOOL` |  | open: its end switch, or the travel time passed *(from FB_Valve)* |
| out | `bIsClosed` | `BOOL` |  | closed: its end switch, or the travel time passed *(from FB_Valve)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveMotorData` (pin `refMotorisedData`)

**Settings `set`** (`ST_ValveMotorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tReversingDeadTime` | `TIME` | `T#500ms` | pause between the two directions |
| `bKeepDriveAtEnd` | `BOOL` |  | keep the drive on at the end |
| `bSeatedOnCloseTorque` | `BOOL` |  | the close torque at the end of a close = seated (closed) |
| `stTorqueFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#1m, nMaxRetriesBeforeLockout := 3)` | a torque switch tripped mid-travel (default Trip, Retry); a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValveMotorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bDriving` | `BOOL` |  | the motor is driving |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `bHalted` | `BOOL` |  | stopped where it is (Halt, or a torque trip) |
| `stTorqueFault` | `ST_ProtectionSts` |  | a torque switch tripped mid-travel (default Trip, Retry); a protection's status ([protections](../conventions.md#protections)) |

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

A motorised two-position valve or damper.

Everything of [`FB_Valve`](FB_Valve.md) (modes, the safe position, the owner, end switches or travel time, protections, strokes, actuator in Local, slow stroke, exercise) plus the drive: `bOpenOutput` drives open, `bCloseOutput` drives closed, never together, `set.tReversingDeadTime` between them ([`FB_Changeover`](FB_Changeover.md)); the drive stops at the end (its end switch, or the travel time), or stays on with `set.bKeepDriveAtEnd`. `set.eValveType` is not used.

Torque switches (`bOpenTorqueTripped` / `bCloseTorqueTripped`, TRUE = tripped: jammed): `set.stTorqueFault` (default Trip, Retry); a torque trip stops the drive where it is (the actuator has failed: it is not driven to the safe position). With `set.bSeatedOnCloseTorque` the close torque at the end of a close is the seat, not a fault: the valve is closed (also without a closed switch) until the next command.

Halt ([`FB_LocalControl`](FB_LocalControl.md)'s `bHaltButton`, `I_LocalChoice`): in Hand the drive stops where it is, the position not known, until the next open / close command.

## Example

A motorised butterfly valve with open and closed limit switches.

| Pin | Wire |
| --- | --- |
| `bOpenLimitSwitch` | `DI_V2_Open` |
| `bClosedLimitSwitch` | `DI_V2_Closed` |
| `refData` | `stValve2` |
| `refMotorisedData` | `stVm2` |
| `bOpenOutput` | `DO_V2_DriveOpen` |
| `bCloseOutput` | `DO_V2_DriveClose` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- method `Choose(eLocalChoice) : BOOL`: a panel choice (FB_LocalControl bHaltButton): in Hand, stop where it is
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
