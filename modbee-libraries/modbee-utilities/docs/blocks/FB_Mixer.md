# FB_Mixer — Stirrer / agitator

Runs a stirrer or agitator before the pump starts (holding the pump), with the pump, after it, and on a timed cycle. A stirrer that cannot run never holds the pump.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | FALSE: no run, the pump never held |
| in | `bCycle` | `BOOL` | `TRUE` | the periodic cycle may run |
| in | `bPumpCall` | `BOOL` |  | the pump is called: pre-run first |
| in | `bPumpRunning` | `BOOL` |  | set.bWithPump |
| in | `bStartNow` | `BOOL` |  | run now, no pre-run, never hold the pump |
| in | `bLevelOk` | `BOOL` | `TRUE` | level at / above the minimum (AND-ed with ipLevel) |
| in | `ipLevel` | `I_Measurement` |  | optional: the tank level. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipMixer` | `I_Equipment` |  | optional: the stirrer motor (else the wires below). The instance it drives (a motor, pump, valve or FB_Group) |
| in | `bMixerReady` | `BOOL` | `TRUE` | only without ipMixer |
| in | `bMixerRunning` | `BOOL` |  | only without ipMixer |
| in | `refData` | `REFERENCE TO ST_MixerData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRun` | `BOOL` |  | run the stirrer (also sent to ipMixer) |
| out | `bStartHold` | `BOOL` |  | the pump must wait: pre-run |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MixerData` (pin `refData`)

**Settings `set`** (`ST_MixerSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCycle` | `BOOL` | `TRUE` |  |
| `tOnTime` | `TIME` | `T#5m` | On time |
| `tOffTime` | `TIME` | `T#1h` | Off time |
| `bPreRun` | `BOOL` | `TRUE` |  |
| `tPreRun` | `TIME` | `T#2m` | time already run counts |
| `bPostRun` | `BOOL` | `TRUE` |  |
| `tPostRun` | `TIME` | `T#30s` |  |
| `bWithPump` | `BOOL` | `TRUE` |  |
| `fMinLevel` | `REAL` | `0.3` | in the level's unit |
| `fMinDeadband` | `REAL` | `0.05` |  |
| `stLowLevel` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5m, eReset := E_ResetMode.Auto)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_MixerSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActivity` | `E_MixerActivity` |  |  |
| `bWanted` | `BOOL` |  |  |
| `bLevelOk` | `BOOL` |  |  |
| `stLowLevel` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Details `det`** (`ST_MixerDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTimeLeft` | `TIME` |  | of the pre-run, post-run, on or off time |

## Lists

- `E_MixerActivity`: `Off`, `Idle`, `Rest`, `Timed`, `PreRun`, `WithPump`, `StartNow`, `PostRun`, `LevelLow`, `NotReady` (default `Off`)

## How it works

A stirrer / agitator: when it runs, and the pump's hold for the pre-run.

The stirrer is `ipMixer` (`I_Equipment`: Request(`bRun`), `bIsReady`, `bIsAvailable`, `bIsRunning`) or, without one, the `bMixerReady` / `bMixerRunning` wires and the `bRun` output. `bRun` is on (while the level is OK) for any of:

```
  pre-run    bPumpCall came on: bRun on, bStartHold holds the pump until the stirrer has run set.tPreRun (time
             already run counts); bPumpCall going before the pump starts ends it.
  with pump  while bPumpRunning (set.bWithPump).
  post-run   set.tPostRun after the pump stops, counted only while the level is OK (held while it is low, like the
             cycle; it ends when the pump runs again).
  start now  while bStartNow.
  cycle      off for set.tOffTime, on for set.tOnTime, over and over (off first); any other run restarts the off time.
```

The pump is never held for a stirrer that cannot run: `bStartHold` drops at once with `bStartNow`, a low level or a stirrer not available (not in Auto, tripped, held off; one in its restart wait can run, the pre-run waits for it), and after `set.tPreRun` + 1 min if it still has not run (warning NoPreRun until `bPumpCall` ends).

Level OK = `bLevelOk` AND `ipLevel`: its value at / above `set.fMinLevel` (back on at `fMinLevel` + `fMinDeadband`), or not in its Low band; a bad level counts as low (never stir blind). Wanted but held by the level for `stLowLevel`'s delay: its protection (warning LevelLow by default).

## Example

A stirrer in an effluent tank, mixing before the pump starts.

| Pin | Wire |
| --- | --- |
| `bEnable` | `fbSystem.bNotOff` |
| `bPumpCall` | `fbLevelCtl.bCall` |
| `bPumpRunning` | `DI_P1_Running` (the pump motor's run feedback) |
| `ipLevel` | `fbTankLevel` |
| `ipMixer` | `fbStirrerMotor` |
| `refData` | `stMixer` |

Wire `NOT fbMixer.bStartHold` to the pump's `bPermissive`, so the pump waits for the pre-run.

**Back to** [the index](../README.md).
