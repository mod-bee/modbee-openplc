# FB_SumpClean — Sump cleaning (a part)

Sump cleaning: every so many pump cycles it pumps the sump down below its normal stop level and runs on there for a while to clear settled solids.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the EMPTY level control. The owner's instance |
| in | `ipLevel` | `I_Measurement` |  | required: the sump level. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `bClean` | `BOOL R_EDGE` |  | clean now Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_SumpCleanData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bCleaning` | `BOOL` |  | A clean is running |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SumpCleanData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClean` | `BOOL` |  | clean now (cleared by the block) |
| `bCmdReset` | `BOOL` |  | clear bFailed (cleared by the block) |
| `bCleaning` | `BOOL` |  | status |
| `bFailed` | `BOOL` |  |  |
| `nCycles` | `INT` |  | since the last clean |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_SumpCleanSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nEvery` | `INT` |  | pump cycles between cleans (0 = only on command) |
| `fCleanLevel` | `REAL` | `5.0` |  |
| `tCleanTime` | `TIME` | `T#20s` | run on at the clean level |
| `tMaxClean` | `TIME` | `T#5m` | give up after this (0 = no limit) |

## How it works

Sump cleaning: every `set.nEvery` pump cycles (or `bClean` / `bCmdClean`) the sump is pumped down past its normal stop to `set.fCleanLevel` and the pump runs on `set.tCleanTime` there, to clear the settled solids. A part of an EMPTY [`FB_LevelControl`](FB_LevelControl.md): it asks for a normal run (`E_PartAction.Request`; the low-low cut-out and start limits still apply). Not reaching `fCleanLevel` within `set.tMaxClean` gives up: a warning (CleanFailed) until the next good clean or a reset. A cycle is one start of the owner's run. A bad level stops a clean.

## Example

Clean the sump every 20 pump cycles.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbLevelCtl` |
| `ipLevel` | `fbSumpLevel` |
| `refData` | `stClean` |

Set `stClean.set.nEvery := 20`, `fCleanLevel` and `tCleanTime`.

**Back to** [the index](../README.md).
