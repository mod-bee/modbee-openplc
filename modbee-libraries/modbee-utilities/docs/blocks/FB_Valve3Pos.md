# FB_Valve3Pos — Three-position valve

A three-position valve: a 3-way diverter, a spring-centred double solenoid, a three-coil valve or a motorised valve with a mid position.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bPosition1Switch` | `BOOL` | `FALSE` | position 1 switch (with bPosition1SwitchFitted) |
| in | `bPosition2Switch` | `BOOL` |  | position 2 switch (with bPosition2SwitchFitted) |
| in | `bPosition3Switch` | `BOOL` |  | position 3 switch (with bPosition3SwitchFitted) |
| in | `refData` | `REFERENCE TO ST_Valve3PosData` |  | the block's record |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bPosition1Output` | `BOOL` |  | coil 1 / drive toward 1 |
| out | `bPosition2Output` | `BOOL` |  | coil 2 (ThreeCoil only) |
| out | `bPosition3Output` | `BOOL` |  | coil 3 / drive toward 3 |
| out | `nPosition` | `INT` |  | 1..3 reached, -1 moving / not known |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_Valve3PosData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdEquipmentMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `nCmdHandPosition` | `INT` | `-1` | Hand position 1..3 (set back to -1) |
| `bSimulate` | `BOOL` |  | the switches are ignored, the travel times decide; not kept |
| `bCmdPresetStrokes` | `BOOL` |  | set tot.nStrokeCount to nPresetStrokeCount (cleared by the block) |
| `nPresetStrokeCount` | `UDINT` |  | the stroke count bCmdPresetStrokes writes |

**Settings `set`** (`ST_Valve3PosSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `eModeAtPowerUp` | `E_PowerUp` |  | which mode it starts in after a power cut |
| `tRetryCountWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bOffResetsFaults` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tMaxHandRunTime` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | after a reset clears a trip, run again at once; FALSE: the owner's request must drop and come back first |
| `bWarnWhenNotAuto` | `BOOL` |  | warn NotAuto while not in Auto and the plant is in Auto |
| `eValveKind` | `E_Valve3Kind` |  | SpringCentre, ThreeCoil or Motor |
| `bPosition1SwitchFitted` | `BOOL` |  | the position 1 switch is fitted and used |
| `bPosition2SwitchFitted` | `BOOL` |  | the position 2 switch is fitted and used |
| `bPosition3SwitchFitted` | `BOOL` |  | the position 3 switch is fitted and used |
| `tStrokeTime` | `TIME` | `T#10s` | per move: arrival without a switch; the timeout base with one |
| `tEndToMiddleTime` | `TIME` |  | motor without bPosition2Switch: end -> mid (0 = half tStrokeTime) |
| `tReversingDeadTime` | `TIME` | `T#500ms` | motor: pause between the two directions |
| `nSafePosition` | `INT` | `2` | position on Off, the interlock or a trip (1..3) |
| `nRestPosition` | `INT` | `2` | when nothing is asked |
| `nHandPosition` | `INT` | `2` | Hand position (kept) |
| `stStrokeTimeoutFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | the end switch did not arrive within the travel time; a protection's settings ([protections](../conventions.md#protections)) |
| `nAutoPosition` | `INT` | `3` | the position asked with no number |
| `bKeepLastPosition` | `BOOL` |  | the last position asked stays when the request ends |
| `stBothLimitsFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#1s, eResetMode := E_ResetMode.Manual, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | two position switches made at once (protection); a protection's settings ([protections](../conventions.md#protections)) |
| `stPositionLostFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#2s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#2s, nMaxRetriesBeforeLockout := 0)` | position lost: its position switch lost at rest (protection); a protection's settings ([protections](../conventions.md#protections)) |
| `stNoMovementFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#2s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#1m, nMaxRetriesBeforeLockout := 3)` | no movement: commanded away, the switch of the position it left still made (protection; off by default); a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_Valve3PosSts`)

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
| `nPositionSetpoint` | `INT` |  | going to (0 = hold) |
| `nPosition` | `INT` |  | reached (-1 not known) |
| `stStrokeTimeoutFault` | `ST_ProtectionSts` |  | the end switch did not arrive within the travel time; a protection's status ([protections](../conventions.md#protections)) |
| `stBothLimitsFault` | `ST_ProtectionSts` |  | two position switches made at once (protection); a protection's status ([protections](../conventions.md#protections)) |
| `stPositionLostFault` | `ST_ProtectionSts` |  | position lost: its position switch lost at rest (protection); a protection's status ([protections](../conventions.md#protections)) |
| `stNoMovementFault` | `ST_ProtectionSts` |  | no movement: commanded away, the switch of the position it left still made (protection; off by default); a protection's status ([protections](../conventions.md#protections)) |
| `tLastStrokeTime` | `TIME` |  | the last move's time (start to arrival) |

**Totals `tot`** (`ST_ValveTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStrokeCount` | `UDINT` |  | strokes, lifetime (kept hourly) |

## Lists

- `E_Valve3Kind`: `SpringCentre`, `ThreeCoil`, `Motor` (default `SpringCentre`)

## How it works

A three-position valve: a 3-way diverter (A / closed / B), a spring-centred double solenoid, a three-coil valve, or a motorised valve with a mid position. Positions 1, 2, 3.

On `FB_Equipment`: an owner (a route, a zone) drives it through `I_Equipment.Request`: `bRun` = go, `fSpeedSetpointPct` = the position 1..3 (none: `set.nAutoPosition`, default 3); its request off = `set.nRestPosition`, or with `set.bKeepLastPosition` the last position asked (it stays there until another is asked). Hand: `set.nHandPosition` (kept; `nCmdHandPosition` 1..3, or [`FB_LocalControl`](FB_LocalControl.md)'s `bPosition1Button`..bPosition3Button, writes it and starts in Hand); a motorised valve: [`FB_LocalControl`](FB_LocalControl.md)'s `bHaltButton` stops it where it is until the next position or command. Off, the interlock or a trip: `set.nSafePosition`. "Running" is away from the rest position. An [`FB_Exercise`](FB_Exercise.md) part on it moves an idle valve (in Auto) to `nAutoPosition` for its run time.

Kinds (`set.eValveKind`): SpringCentre (`bPosition1Output` / `bPosition3Output` held, none for 2: the springs centre it), ThreeCoil (`bPosition1Output`..3 held), Motor (`bPosition1Output` drives toward 1, `bPosition3Output` toward 3, `set.tReversingDeadTime` between; the mid by `bPosition2Switch`, or timed `set.tEndToMiddleTime` from a known end (0 = half `tStrokeTime`); a position not known goes to 1 first). Arrival: the position's switch when used, else `set.tStrokeTime` after the move started. A switch that does not come within `tStrokeTime` + 50 % of a move: the travel protection (TravelTimeout); a switch lost after arrival is `set.stPositionLostFault`'s. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a bad setting with no good copy is a trip (BadSetting) with every output off (a spring-centred valve centres). Moves counted (`tot.nStrokeCount`: each new target 1..3), kept hourly; the record's `bCmdPresetStrokes` sets it to `nPresetStrokeCount`; `sts.tLastStrokeTime` is the last move's time. With the switches: `set.stBothLimitsFault` (two made at once), `set.stPositionLostFault` (the reached position's switch lost), `set.stNoMovementFault` (off by default: moving, and the switch of the position it left still made). Simulation (the record's `bSimulate`, not kept, cleared by a system reset): the switches are ignored and the travel times decide, with a warning (Simulated).

## Example

A spring-centred 3-way diverter with end switches.

| Pin | Wire |
| --- | --- |
| `bPosition1Switch` | `DI_Pos1` |
| `bPosition3Switch` | `DI_Pos3` |
| `refData` | `stDiverter` |
| `bPosition1Output` | `DO_CoilA` |
| `bPosition3Output` | `DO_CoilB` |

Its owner asks for a position through `Request` (`fSpeedSetpointPct` = 1, 2 or 3).

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- method `Choose(eLocalChoice) : BOOL`: a panel choice (FB_LocalControl bPosition1Button..bPosition3Button, bHaltButton): in Hand
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
