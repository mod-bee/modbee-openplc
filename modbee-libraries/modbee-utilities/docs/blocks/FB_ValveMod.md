# FB_ValveMod — Modulating valve

A modulating valve or damper with a positioner (4-20 mA / 0-10 V): the position from its owner, shaped, clamped and ramped.

It is one of the `FB_ValvePos` family: the common part is described under *How it works*.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `refMod` | `REFERENCE TO ST_ValveModData` |  | its record |
| in | `stConfig` | `ST_ValveModConfig` |  | the signal's raw span (set at the declaration) |
| in | `ipPosFb` | `I_Measurement` |  | position feedback, %; NULL = the travel estimate. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) *(from FB_ValvePos)* |
| in | `bOpenLs` | `BOOL` |  | Open end switch (TRUE = made) *(from FB_ValvePos)* |
| in | `bClosedLs` | `BOOL` |  | end switches, with set.bUseOpenLs / bUseClosedLs *(from FB_ValvePos)* |
| in | `refData` | `REFERENCE TO ST_ValvePosData` |  | Its record (a variable of this type) *(from FB_ValvePos)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fOut` | `REAL` |  | demand % (reverse acting: 100 - demand) |
| out | `nOutRaw` | `UINT` |  | for %QW |
| out | `fPosition` | `REAL` |  | the position in use, % (-1: not known yet) *(from FB_ValvePos)* |
| out | `bIsOpen` | `BOOL` |  | Open: its end switch, or the travel time passed *(from FB_ValvePos)* |
| out | `bIsClosed` | `BOOL` |  | Closed: its end switch, or the travel time passed *(from FB_ValvePos)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ValveModData` (pin `refMod`)

**Settings `set`** (`ST_ValveModSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOutMin` | `REAL` |  | demand clamp, % |
| `fOutMax` | `REAL` | `100.0` |  |
| `fRampRate` | `REAL` |  | % per eRateUnit (0 = off) |
| `eRateUnit` | `E_RateUnit` |  |  |
| `fTightShutoff` | `REAL` |  | demand below this -> 0 % (0 = off) |
| `fFullOpenAbove` | `REAL` | `100.0` | demand above this -> 100 % (100 = off) |
| `bReverseActing` | `BOOL` |  | air to close: fOut = 100 - demand |
| `tStroke` | `TIME` | `T#60s` | travel estimate without feedback (0 = at once) |

**Status `sts`** (`ST_ValveModSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOut` | `REAL` |  | the demand %, 100 - demand when set.bReverseActing |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Record `ST_ValvePosData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |

**Settings `set`** (`ST_ValvePosSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `tRetryWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bResetByOff` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tHandMax` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `bWarnNotAuto` | `BOOL` |  | the owner's request must drop and come back first warn NotAuto while not in Auto and the plant is in Auto |
| `fSafePos` | `REAL` |  | % on Off / interlock / a trip (< 0 = stays) |
| `bHoldOnFault` | `BOOL` |  | a trip holds where it is |
| `fRestPos` | `REAL` |  | % while the owner's open is off |
| `fHandPos` | `REAL` |  | Hand position (kept) |
| `fOpenThreshold` | `REAL` | `98.0` | bIsOpen at or above, % |
| `fClosedThreshold` | `REAL` | `2.0` | bIsClosed at or below, % |
| `fDeadband` | `REAL` | `1.0` | % error ignored |
| `fDevLimit` | `REAL` | `5.0` | deviation above this, % |
| `bUseOpenLs` | `BOOL` |  | The open end switch (`bOpenLs`) is fitted and used |
| `bUseClosedLs` | `BOOL` |  | The closed end switch (`bClosedLs`) is fitted and used |
| `stDeviation` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#10s, eReset := E_ResetMode.Auto, tRecover := T#0s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stPosFb` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#500ms, eReset := E_ResetMode.Auto, tRecover := T#2s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_ValvePosSts`)

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
| `fAim` | `REAL` |  | where it is going, % |
| `fDemand` | `REAL` |  | the demand now (after shaping and ramp), % |
| `fPosition` | `REAL` |  | the position in use, % |
| `fFeedback` | `REAL` |  | the feedback (-1: none) |
| `fEstimate` | `REAL` |  |  |
| `bFbOk` | `BOOL` |  |  |
| `bOpen` | `BOOL` |  | Open (status) |
| `bClosed` | `BOOL` |  | Closed (status) |
| `bMoving` | `BOOL` |  | Travelling (status) |
| `stDeviation` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stPosFb` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

## Constants `ST_ValveModConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_ValveModConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawMin` | `REAL` |  | nOutRaw at 0 % |
| `fRawMax` | `REAL` | `65535.0` | nOutRaw at 100 % |

## How it works

A modulating valve or damper with a positioner (4-20 `mA` / 0-10 V). Everything of `FB_ValvePos` (where it goes, the feedback, the protections, Hand) plus the signal.

The aim is shaped: `set.fTightShutoff` (below it: 0 %) and `fFullOpenAbove` (above it: 100 %) win over the clamp `fOutMin`..fOutMax; a safe position is not shaped. `set.fRampRate` limits the demand (per `eRateUnit`; 0 = off; a safe position or a hold jumps). Without feedback the position is a travel estimate: the demand followed at a full stroke per `set.tStroke` (0 = at once). Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

### Common to the FB_ValvePos family

On `FB_Equipment`: "running" is open (not closed). An owner (a PID loop such as [`FB_SpeedLoop`](FB_SpeedLoop.md), a zone, a route) drives it through `I_Equipment.Request`: `bRun` = open, `fSpeed` = the position % (none: 100 %).

Where it goes (`fAim`, for the variant):

```
  open (bRun)                Hand: set.fHandPos (kept; on entering Hand it takes the position now: bumpless);
                             Auto: the owner's fSpeed (none: 100 %)
  not open                   set.fRestPos
  Off / interlock / a trip   set.fSafePos (< 0: stays; set.bHoldOnFault: a trip holds)
```

Protections: position feedback (outside -5..105 % or not good; `set.stPosFb`, default Trip after 500 ms: the estimate takes over) and deviation (\|demand - feedback\| above `set.fDevLimit` while settled; `set.stDeviation`, default Warn after 10 s). `bIsOpen` / `bIsClosed`: an end switch, or the position past `set.fOpenThreshold` / `fClosedThreshold`. Exercise: an [`FB_Exercise`](FB_Exercise.md) part on the valve (`ipOwner` := the valve) opens an idle valve in Auto fully (100 %) for its run time.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A control valve with a 4-20 mA positioner and a position feedback.

| Pin | Wire |
| --- | --- |
| `ipPosFb` | `fbValvePos` (an FB_AnalogIn in %) |
| `refData` | `stValve3` |
| `refMod` | `stMod3` |
| `nOutRaw` | `AO_Valve3` |

Its owner (an FB_SpeedLoop) asks for the position.

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
