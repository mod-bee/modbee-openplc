# FB_Mixer — Stirrer / agitator

Runs a stirrer or agitator before the pump starts (holding the pump), with the pump, after it, and on a timed cycle. A stirrer that cannot run never holds the pump.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | FALSE: no run, the pump never held |
| in | `bCycleAllowed` | `BOOL` | `TRUE` | the periodic cycle may run |
| in | `bPumpCalled` | `BOOL` |  | the pump is called: pre-run first |
| in | `bPumpRunning` | `BOOL` |  | the pump is running (with bRunWithPump) |
| in | `bStartNow` | `BOOL` |  | run now, no pre-run, never hold the pump |
| in | `bLevelAboveMinimum` | `BOOL` | `TRUE` | level at / above the minimum (AND-ed with ipLevel) |
| in | `ipLevel` | `I_Measurement` |  | optional: the tank level. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipStirrerMotor` | `I_Equipment` |  | optional: the stirrer motor (else the wires below) |
| in | `bStirrerReady` | `BOOL` | `TRUE` | only without ipStirrerMotor |
| in | `bStirrerRunning` | `BOOL` |  | only without ipStirrerMotor |
| in | `refData` | `REFERENCE TO ST_MixerData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bStirrerRunCommand` | `BOOL` |  | run the stirrer (also sent to ipStirrerMotor) |
| out | `bHoldPumpStart` | `BOOL` |  | the pump must wait: pre-run |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MixerData` (pin `refData`)

**Settings `set`** (`ST_MixerSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCycleOn` | `BOOL` | `TRUE` | run the periodic on / off cycle |
| `tOnTime` | `TIME` | `T#5m` | cycle on time |
| `tOffTime` | `TIME` | `T#1h` | cycle off time |
| `bPreRunOn` | `BOOL` | `TRUE` | mix before the pump starts |
| `tPreRunTime` | `TIME` | `T#2m` | pre-run time (time already run counts) |
| `bPostRunOn` | `BOOL` | `TRUE` | mix on after the pump stops |
| `tPostRunTime` | `TIME` | `T#30s` | post-run time |
| `bRunWithPump` | `BOOL` | `TRUE` | mix while the pump runs |
| `fMinLevelToMix` | `REAL` | `0.3` | in the level's unit |
| `fMinLevelDeadband` | `REAL` | `0.05` | the level must rise this far above fMinLevelToMix before mixing again |
| `stLowLevelFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5m, eResetMode := E_ResetMode.Auto)` | the level is below fMinLevelToMix (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_MixerSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActivity` | `E_MixerActivity` |  | what it is doing: Off, Idle, Rest, Timed, PreRun, WithPump, StartNow, PostRun, LevelLow, NotReady |
| `bStirrerRunCommand` | `BOOL` |  | the stirrer is asked to run now |
| `bLevelAboveMinimum` | `BOOL` |  | the level is at or above the minimum |
| `stLowLevelFault` | `ST_ProtectionSts` |  | the level is below fMinLevelToMix (default a warning); a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_MixerDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTimeLeft` | `TIME` |  | of the pre-run, post-run, on or off time |

## Lists

- `E_MixerActivity`: `Off`, `Idle`, `Rest`, `Timed`, `PreRun`, `WithPump`, `StartNow`, `PostRun`, `LevelLow`, `NotReady` (default `Off`)

## How it works

A stirrer / agitator: when it runs, and the pump's hold for the pre-run.

The stirrer is `ipStirrerMotor` (`I_Equipment`: Request(`bStirrerRunCommand`), `bIsReady`, `bIsAvailable`, `bIsRunning`) or, without one, the `bStirrerReady` / `bStirrerRunning` wires and the `bStirrerRunCommand` output. `bStirrerRunCommand` is on (while the level is OK) for any of:

```
  pre-run    bPumpCalled came on: bStirrerRunCommand on, bHoldPumpStart holds the pump until the stirrer has run set.tPreRunTime (time
             already run counts); bPumpCalled going before the pump starts ends it.
  with pump  while bPumpRunning (set.bRunWithPump).
  post-run   set.tPostRunTime after the pump stops, counted only while the level is OK (held while it is low, like the
             cycle; it ends when the pump runs again).
  start now  while bStartNow.
  cycle      off for set.tOffTime, on for set.tOnTime, over and over (off first); any other run restarts the off time.
```

The pump is never held for a stirrer that cannot run: `bHoldPumpStart` drops at once with `bStartNow`, a low level or a stirrer not available (not in Auto, tripped, held off; one in its restart wait can run, the pre-run waits for it), and after `set.tPreRunTime` + 1 min if it still has not run (warning NoPreRun until `bPumpCalled` ends).

Level OK = `bLevelAboveMinimum` AND `ipLevel`: its value at / above `set.fMinLevelToMix` (back on at `fMinLevelToMix` + `fMinLevelDeadband`), or not in its Low band; a bad level counts as low (never stir blind). Wanted but held by the level for `stLowLevelFault`'s delay: its protection (warning LevelLow by default).

## Example

A stirrer in an effluent tank, mixing before the pump starts.

| Pin | Wire |
| --- | --- |
| `bEnable` | `fbSystem.bNotOff` |
| `bPumpCalled` | `fbLevelCtl.bLevelCalls` |
| `bPumpRunning` | `DI_P1_Running` (the pump motor's run feedback) |
| `ipLevel` | `fbTankLevel` |
| `ipStirrerMotor` | `fbStirrerMotor` |
| `refData` | `stMixer` |

Wire `NOT fbMixer.bHoldPumpStart` to the pump's `bPermissive`, so the pump waits for the pre-run.

**Back to** [the index](../README.md).
