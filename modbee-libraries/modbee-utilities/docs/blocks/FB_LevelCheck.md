# FB_LevelCheck — One alarm level on a measurement (a part)

One alarm level on any measurement, added to its owner: low or high pressure, no flow, dry run, a high tank level. One block for each level fitted.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSwitch` | `BOOL` | `FALSE` | optional switch, TRUE = past the level (a backup, or the only signal) |
| in | `ipMeas` | `I_Measurement` |  | optional: none wired = the switch alone. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipOwner` | `I_PartOwner` |  | required. The owner's instance |
| in | `refData` | `REFERENCE TO ST_LevelCheckData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelCheckData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_LevelCheckSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eResponse` | `E_Response` | `E_Response.Trip` | `Off`, `Warn`, `Trip` or `Signal` (see conventions) |
| `tDelay` | `TIME` | `T#1s` | The condition must last this long |
| `eReset` | `E_ResetMode` | `E_ResetMode.Retry` | `Auto`, `Manual` or `Retry` (see conventions) |
| `tRecover` | `TIME` | `T#10s` | The cause must be gone this long before it clears |
| `nMaxRetries` | `INT` | `3` | Retry: trips in the window before it locks out |
| `eDirection` | `E_LevelDir` |  |  |
| `fSetpoint` | `REAL` |  |  |
| `fDeadband` | `REAL` |  | Hysteresis / deadband, in the value's unit |
| `eBand` | `E_Band` |  | a switch band that also signals it (None: the value only) |
| `bUseValue` | `BOOL` | `TRUE` | FALSE: the band only |
| `bOnlyWhenRunning` | `BOOL` |  |  |
| `bMaskAtStart` | `BOOL` |  |  |
| `tBadRide` | `TIME` | `T#5s` | the state is held |
| `eErrorId` | `E_UtError` | `E_UtError.Protection` | The first error since the last reset (first-out) |
| `bDoneWhenReached` | `BOOL` |  | with eResponse Signal: reaching the level ENDS the owner's run (Done) instead |

**Status `sts`** (`ST_LevelCheckSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_ProtState` |  | What it is doing now (status) |
| `nRetries` | `INT` |  | Trips counted in the retry window |
| `nCount` | `UDINT` |  | trips since the counter was cleared |
| `tTimeLeft` | `TIME` |  | delay before it acts, or recover wait before it clears |
| `bBeyond` | `BOOL` |  | the value is past the level (with its deadband) |
| `bBadHeld` | `BOOL` |  | the measurement is bad, its state held |

## Lists

- `E_LevelDir`: `High`, `Low` (default `High`)

## How it works

One alarm level on any measurement, as a part of its owner: low pressure, high pressure, no flow, dry run, a high tank level ... one block for each level fitted.

A bad measurement is ridden through for `set.tBadRide` (the state is held), then the value part lets go: the sensor raises its own fault, and a switch band still acts. A measurement that is not fitted is no check.

It acts per its protection settings (off / warn / trip / signal, delay, reset). A signal is a stop without an alarm (the owner stops and restarts with it); with `set.bDoneWhenReached` a signal ends the owner's run instead (Done: a full destination ends a latched transfer run; for a held run keep the pause).

## Example

Dry-run protection for pump 1 on the sump level.

| Pin | Wire |
| --- | --- |
| `ipMeas` | `fbSumpLevel` |
| `ipOwner` | `fbPump1` |
| `refData` | `stDryRun1` |

In `stDryRun1.set`: the direction Low and the setpoint (the dry-run level).

**Back to** [the index](../README.md).
