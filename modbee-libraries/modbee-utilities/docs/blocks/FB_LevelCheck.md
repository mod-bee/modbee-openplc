# FB_LevelCheck — One alarm level on a measurement (a part)

One alarm level on any measurement, added to its owner: low or high pressure, no flow, dry run, a high tank level. One block for each level fitted.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bBackupSwitch` | `BOOL` | `FALSE` | optional switch, TRUE = past the level (a backup, or the only signal) |
| in | `ipMeasurement` | `I_Measurement` |  | optional: none wired = the switch alone. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipOwner` | `I_PartOwner` |  | required. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `bSuppress` | `BOOL` |  | TRUE: the check is suppressed (no cause; an active one clears per its reset) |
| in | `refData` | `REFERENCE TO ST_LevelCheckData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelCheckData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |

**Settings `set`** (`ST_LevelCheckSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActionOnFault` | `E_Response` | `E_Response.Trip` | what it does when the condition lasts: Off, Warn, Trip or Signal |
| `tTripDelay` | `TIME` | `T#1s` | the condition must last this long before it acts |
| `eResetMode` | `E_ResetMode` | `E_ResetMode.Retry` | how it clears: Auto, Manual (held until a reset) or Retry (locks out after too many) |
| `tAutoRecoverAfter` | `TIME` | `T#10s` | the condition must be gone this long before it clears |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | Retry: trips within the retry window before it locks out |
| `eCheckAboveOrBelow` | `E_LevelDir` |  | High: acts above the setpoint; Low: acts below it |
| `fSetpoint` | `REAL` |  | the level it acts at, in the measurement's unit |
| `fDeadband` | `REAL` |  | hysteresis: it clears this far back, in the measurement's unit |
| `eSwitchBand` | `E_Band` |  | a switch band that also signals it (None: the value only) |
| `bUseMeasuredValue` | `BOOL` | `TRUE` | FALSE: the band only |
| `bCheckOnlyWhenRunning` | `BOOL` |  | checked only while the owner runs |
| `bUseStartMask` | `BOOL` |  | ignored during the owner's start mask |
| `tRideThroughBadValue` | `TIME` | `T#5s` | a bad measurement holds the last state this long |
| `eErrorRaised` | `E_UtError` | `E_UtError.Protection` | the error the owner shows when this trips or warns |
| `bEndsRunWhenReached` | `BOOL` |  | with eActionOnFault Signal: reaching the level ENDS the owner's run (Done) instead of pausing it (a full destination ends a latched / timed transfer) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_LevelCheckSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eFaultState` | `E_ProtState` |  | Clear, Pending, Warning, Tripped, Locked, Recovering or Signal |
| `nRetriesUsed` | `INT` |  | trips counted in the current retry window |
| `nTripCount` | `UDINT` |  | trips since the counter was cleared |
| `tTimeLeft` | `TIME` |  | delay before it acts, or recover wait before it clears |
| `bPastLevel` | `BOOL` |  | the value is past the level (with its deadband) |
| `bHeldOnBadValue` | `BOOL` |  | the measurement is bad, its state held |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by its reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_LevelDir`: `High`, `Low` (default `High`)

## How it works

One alarm level on any measurement, as a part of its owner: low pressure, high pressure, no flow, dry run, a high tank level ... one block for each level fitted.

A bad measurement is ridden through for `set.tRideThroughBadValue` (the state is held), then the value part lets go: the sensor raises its own fault, and a switch band still acts. A measurement that is not fitted is no check.

It acts per its protection settings (off / warn / trip / signal, delay, reset). A signal is a stop without an alarm (the owner stops and restarts with it); with `set.bEndsRunWhenReached` a signal ends the owner's run instead (Done: a full destination ends a latched transfer run; for a held run keep the pause).  `bSuppress` TRUE suppresses the check (no cause): an active one clears per its reset settings.

A bad settings write is put back (`sts.bSettingRefused` / `sts.eSettingRefusedErrorId`) and warns its owner (SettingRefused) until its reset (`bCmdResetFaults`) or the owner's.

## Example

Dry-run protection for pump 1 on the sump level.

| Pin | Wire |
| --- | --- |
| `ipMeasurement` | `fbSumpLevel` |
| `ipOwner` | `fbPump1` |
| `refData` | `stDryRun1` |

In `stDryRun1.set`: the direction Low and the setpoint (the dry-run level).

**Back to** [the index](../README.md).
