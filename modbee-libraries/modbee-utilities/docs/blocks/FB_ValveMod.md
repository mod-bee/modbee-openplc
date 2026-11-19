# FB_ValveMod — Modulating valve

A modulating valve or damper with a positioner (4-20 mA / 0-10 V): the position from its owner, shaped, clamped and ramped.

It is one of the `FB_ValvePos` family: the common part is described under *How it works*.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `refModulatingData` | `REFERENCE TO ST_ValveModData` |  | the modulating valve record |
| in | `stConfig` | `ST_ValveModConfig` |  | the signal's raw span (set at the declaration) |
| in | `ipPositionFeedback` | `I_Measurement` |  | position feedback, %; NULL = the travel estimate. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) *(from FB_ValvePos)* |
| in | `bOpenLimitSwitch` | `BOOL` |  | open end switch (TRUE = made) *(from FB_ValvePos)* |
| in | `bClosedLimitSwitch` | `BOOL` |  | closed end switch (TRUE = made) *(from FB_ValvePos)* |
| in | `refData` | `REFERENCE TO ST_ValvePosData` |  | the block's record *(from FB_ValvePos)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fOutputPct` | `REAL` |  | demand % (reverse acting: 100 - demand) |
| out | `nRawOutput` | `UINT` |  | for %QW |
| out | `fPositionPct` | `REAL` |  | the position in use, % (-1: not known yet) *(from FB_ValvePos)* |
| out | `bIsOpen` | `BOOL` |  | open: its end switch, or the travel time passed *(from FB_ValvePos)* |
| out | `bIsClosed` | `BOOL` |  | closed: its end switch, or the travel time passed *(from FB_ValvePos)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveModData` (pin `refModulatingData`)

**Settings `set`** (`ST_ValveModSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinDemandPct` | `REAL` |  | demand clamp, % |
| `fMaxDemandPct` | `REAL` | `100.0` | demand clamp, highest % |
| `fRampRate` | `REAL` |  | % per eRateUnit (0 = off) |
| `eRateUnit` | `E_RateUnit` |  | the time unit of the ramp rate |
| `fTightShutoffBelowPct` | `REAL` |  | demand below this -> 0 % (0 = off) |
| `fFullOpenAbovePct` | `REAL` | `100.0` | demand above this -> 100 % (100 = off) |
| `bReverseActing` | `BOOL` |  | air to close: fOutputPct = 100 - demand |
| `tFullStrokeTime` | `TIME` | `T#60s` | travel estimate without feedback (0 = at once) |

**Status `sts`** (`ST_ValveModSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOutputPct` | `REAL` |  | the output %, 100 - demand when bReverseActing |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

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

## Constants `ST_ValveModConfig` (pin `stConfig`)

**Fields** (`ST_ValveModConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawAtZeroPct` | `REAL` |  | nRawOutput at 0 % |
| `fRawAtFullPct` | `REAL` | `65535.0` | nRawOutput at 100 % |

Set once, at the variable's declaration (engineering constants, not changed while running).

## How it works

A modulating valve or damper with a positioner (4-20 `mA` / 0-10 V). Everything of `FB_ValvePos` (where it goes, the feedback, the protections, Hand) plus the signal.

The aim is shaped: `set.fTightShutoffBelowPct` (below it: 0 %) and `fFullOpenAbovePct` (above it: 100 %) win over the clamp `fMinDemandPct`..fMaxDemandPct; a safe position is not shaped. `set.fRampRate` limits the demand (per `eRateUnit`; 0 = off; a safe position or a hold jumps). Without feedback the position is a travel estimate: the demand followed at a full stroke per `set.tFullStrokeTime` (0 = at once). Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

### Common to the FB_ValvePos family

On `FB_Equipment`: "running" is open (not closed). An owner (a PID loop such as [`FB_SpeedLoop`](FB_SpeedLoop.md), a zone, a route) drives it through `I_Equipment.Request`: `bRun` = open, `fSpeedSetpointPct` = the position % (none: 100 %).

Where it goes (`fAim`, for the variant):

```
  open (bRun)                Hand: set.fHandPositionPct (kept; on entering Hand it takes the position now: bumpless);
                             Auto: the owner's fSpeedSetpointPct (none: 100 %)
  not open                   set.fRestPositionPct
  Off / interlock / a trip   set.fSafePositionPct (< 0: stays; set.bHoldWhenTripped: a trip holds)
```

Protections: position feedback (outside -5..105 % or not good; `set.stPositionFeedbackFault`, default Trip after 500 ms: the estimate takes over) and deviation (\|demand - feedback\| above `set.fDeviationAbovePct` while settled; `set.stDeviationFault`, default Warn after 10 s). `bIsOpen` / `bIsClosed`: an end switch, or the position past `set.fOpenAtOrAbovePct` / `fClosedAtOrBelowPct`. Exercise: an [`FB_Exercise`](FB_Exercise.md) part on the valve (`ipOwner` := the valve) opens an idle valve in Auto fully (100 %) for its run time.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A control valve with a 4-20 mA positioner and a position feedback.

| Pin | Wire |
| --- | --- |
| `ipPositionFeedback` | `fbValvePos` (an FB_AnalogIn in %) |
| `refData` | `stValve3` |
| `refModulatingData` | `stMod3` |
| `nRawOutput` | `AO_Valve3` |

Its owner (an FB_SpeedLoop) asks for the position.

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
