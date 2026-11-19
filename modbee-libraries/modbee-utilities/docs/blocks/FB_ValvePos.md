# FB_ValvePos — ABSTRACT base of the positioning valves

ABSTRACT base of the positioning valves (FB_ValveMod, FB_ValveFloat). On FB_Equipment: "running" is open (not closed). An owner (a PID loop such as FB_SpeedLoop, a zone, a route) drives it through I_Equipment.Request: bRun = open, fSpeed = the position % (none: 100 %).

Pins: ipPositionFeedback (I_Measurement, the position feedback in %; NULL = the variant's travel estimate), bOpenLimitSwitch / bClosedLimitSwitch (end switches, with set.bOpenLimitSwitchFitted / bClosedLimitSwitchFitted), refData -> fPositionPct (the position in use: the feedback when good, else the estimate; never the demand alone), bIsOpen, bIsClosed, plus FB_Equipment's bInterlock, bPermissive, ipSystem and FB_Object's outputs. Where it goes (fPositionSetpointPct, for the variant): open (bRun) Hand: set.fHandPositionPct (kept; on entering Hand it takes the position now: bumpless); Auto: the owner's fSpeed (none: 100 %) not open set.fRestPositionPct Off / interlock / a trip set.fSafePositionPct (< 0: stays; set.bHoldWhenTripped: a trip holds) Protections: position feedback (outside -5..105 % or not good; set.stPositionFeedbackFault, default Trip after 500 ms: the estimate takes over) and deviation (|demand - feedback| above set.fDeviationAbovePct while settled; set.stDeviationFault, default Warn after 10 s). bIsOpen / bIsClosed: an end switch, or the position past set.fOpenAtOrAbovePct / fClosedAtOrBelowPct. Exercise: an FB_Exercise part on the valve (ipOwner := the valve) opens an idle valve in Auto fully (100 %) for its run time. The variant moves the valve (fDemandPct, fEstimatedPct, bSettled) after SUPER^(). Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

An abstract base: not placed on its own; the blocks that extend it are.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipPositionFeedback` | `I_Measurement` |  | position feedback, %; NULL = the travel estimate. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bOpenLimitSwitch` | `BOOL` |  | open end switch (TRUE = made) |
| in | `bClosedLimitSwitch` | `BOOL` |  | closed end switch (TRUE = made) |
| in | `refData` | `REFERENCE TO ST_ValvePosData` |  | the block's record |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fPositionPct` | `REAL` |  | the position in use, % (-1: not known yet) |
| out | `bIsOpen` | `BOOL` |  | open: its end switch, or the travel time passed |
| out | `bIsClosed` | `BOOL` |  | closed: its end switch, or the travel time passed |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

## Record `ST_ValvePosData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdEquipmentMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |

**Settings `set`** (`ST_ValvePosSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `eModeAtPowerUp` | `E_PowerUp` |  | which mode it starts in after a power cut |
| `tRetryCountWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bOffResetsFaults` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tMaxHandRunTime` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | after a reset clears a trip, run again at once; FALSE: the owner's request must drop and come back first |
| `bWarnWhenNotAuto` | `BOOL` |  | warn NotAuto while not in Auto and the plant is in Auto |
| `fSafePositionPct` | `REAL` |  | % on Off / interlock / a trip (< 0 = stays) |
| `bHoldWhenTripped` | `BOOL` |  | a trip holds where it is |
| `fRestPositionPct` | `REAL` |  | % while the owner's open is off |
| `fHandPositionPct` | `REAL` |  | Hand position (kept) |
| `fOpenAtOrAbovePct` | `REAL` | `98.0` | bIsOpen at or above, % |
| `fClosedAtOrBelowPct` | `REAL` | `2.0` | bIsClosed at or below, % |
| `fPositionDeadbandPct` | `REAL` | `1.0` | % error ignored |
| `fDeviationAbovePct` | `REAL` | `5.0` | deviation above this, % |
| `bOpenLimitSwitchFitted` | `BOOL` |  | the open end switch (bOpenLimitSwitch) is fitted and used |
| `bClosedLimitSwitchFitted` | `BOOL` |  | the closed end switch (bClosedLimitSwitch) is fitted and used |
| `stDeviationFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#10s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 3)` | position off its aim by more than fDeviationAbovePct; a protection's settings ([protections](../conventions.md#protections)) |
| `stPositionFeedbackFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#500ms, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#2s, nMaxRetriesBeforeLockout := 3)` | the position feedback is bad; a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValvePosSts`)

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
| `fPositionSetpointPct` | `REAL` |  | where it is going, % |
| `fDemandPct` | `REAL` |  | the demand now (after shaping and ramp), % |
| `fPositionPct` | `REAL` |  | the position in use, % |
| `fFeedbackPct` | `REAL` |  | the feedback (-1: none) |
| `fEstimatedPct` | `REAL` |  | the travel estimate, % (-1 = not known until homed) |
| `bFeedbackGood` | `BOOL` |  | the position feedback can be trusted |
| `bIsOpen` | `BOOL` |  | open now |
| `bIsClosed` | `BOOL` |  | closed now |
| `bTravelling` | `BOOL` |  | travelling now |
| `stDeviationFault` | `ST_ProtectionSts` |  | position off its aim by more than fDeviationAbovePct; a protection's status ([protections](../conventions.md#protections)) |
| `stPositionFeedbackFault` | `ST_ProtectionSts` |  | the position feedback is bad; a protection's status ([protections](../conventions.md#protections)) |

## Read from ST (methods and properties)

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

**Back to** [the index](../README.md).
