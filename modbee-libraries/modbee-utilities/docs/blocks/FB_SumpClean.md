# FB_SumpClean — Sump cleaning (a part)

Sump cleaning: every so many pump cycles it pumps the sump down below its normal stop level and runs on there for a while to clear settled solids.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the EMPTY level control. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `ipLevel` | `I_Measurement` |  | required: the sump level. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bCleanNow` | `BOOL R_EDGE` |  | clean now |
| in | `refData` | `REFERENCE TO ST_SumpCleanData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bCleaning` | `BOOL` |  | a clean is running |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SumpCleanData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdCleanNow` | `BOOL` |  | clean now (cleared by the block) |
| `bCmdClearCleanFailed` | `BOOL` |  | clear bCleanFailed (cleared by the block) |

**Settings `set`** (`ST_SumpCleanSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nPumpCyclesBetweenCleans` | `INT` |  | pump cycles between cleans (0 = only on command) |
| `fCleanLevel` | `REAL` | `5.0` | a clean pumps past the normal stop to this level |
| `tRunOnAtCleanLevel` | `TIME` | `T#20s` | run on at the clean level |
| `tCleanTimeout` | `TIME` | `T#5m` | give up after this (0 = no limit) |

**Status `sts`** (`ST_SumpCleanSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCleaning` | `BOOL` |  | a clean is running |
| `bCleanFailed` | `BOOL` |  | the last clean did not reach the clean level in time (warning CleanFailed) |
| `nPumpCycleCount` | `INT` |  | since the last clean |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `tElapsedTime` | `TIME` |  | the clean under way (0 when none) |

## How it works

Sump cleaning: every `set.nPumpCyclesBetweenCleans` pump cycles (or `bCleanNow` / `bCmdCleanNow`) the sump is pumped down past its normal stop to `set.fCleanLevel` and the pump runs on `set.tRunOnAtCleanLevel` there, to clear the settled solids. A part of an EMPTY [`FB_LevelControl`](FB_LevelControl.md): it asks for a normal run (`E_PartAction.Request`; the low-low cut-out and start limits still apply). Not reaching `fCleanLevel` within `set.tCleanTimeout` gives up: a warning (CleanFailed) until the next good clean or a reset. A cycle is one start of the owner's run. A bad level stops a clean. The record shows the clean under way's time (`sts.tElapsedTime`).

## Example

Clean the sump every 20 pump cycles.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbLevelCtl` |
| `ipLevel` | `fbSumpLevel` |
| `refData` | `stClean` |

Set `stClean.set.nPumpCyclesBetweenCleans := 20`, `fCleanLevel` and `tRunOnAtCleanLevel`.

**Back to** [the index](../README.md).
