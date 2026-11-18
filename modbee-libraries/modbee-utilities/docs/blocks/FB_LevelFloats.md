# FB_LevelFloats — Sump floats: backup and transmitter check (a part)

The floats of a sump or wet well, added to its level control: an overflow backup run, a check of the level transmitter against the high float, and float / timer control when the transmitter is lost.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipFloats` | `I_Measurement` |  | required. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipLevel` | `I_Measurement` |  | the transducer (optional). A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipOwner` | `I_LevelControl` |  | required: the level control. The FB_LevelControl instance |
| in | `refData` | `REFERENCE TO ST_LevelFloatsData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bTransducerFault` | `BOOL` |  | The transmitter disagrees with the high float (latched until a reset) |
| out | `bFloatControl` | `BOOL` |  | Running on the floats and timers |
| out | `bRunAll` | `BOOL` |  | the overflow backup asks every pump (set.bRunAll) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelFloatsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | clear the transducer fault (cleared by the block) |
| `bCmdResetStats` | `BOOL` |  | zero tot (cleared by the block) |

**Settings `set`** (`ST_LevelFloatsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tHighHold` | `TIME` | `T#2m` | the overflow keeps running this long after the high float clears |
| `tFloatRunTime` | `TIME` | `T#5m` | float control: runs on this long after the high float clears |
| `tLockout` | `TIME` | `T#1m` | float control: then this long before the high float starts it again |
| `tCheckDelay` | `TIME` | `T#10s` | transducer check |
| `fCheckLevel` | `REAL` |  | the high float made with the level below this = transducer fault (0: the owner's high-high) |
| `bRunAll` | `BOOL` |  | the overflow backup runs every pump (bRunAll -> FB_Stages.bRunAll) |

**Status `sts`** (`ST_LevelFloatsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRun` | `BOOL` |  | asks the level control to run |
| `bStop` | `BOOL` |  | the low float stops it (float control) |
| `bFloatControl` | `BOOL` |  |  |
| `bTransducerFault` | `BOOL` |  |  |
| `bDisagree` | `BOOL` |  | high and low made together |
| `bLocked` | `BOOL` |  | float control lockout |
| `tTimeLeft` | `TIME` |  | of the high hold, the run-on or the lockout now counting |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Totals `tot`** (`ST_LevelFloatsTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nHighEvents` | `UDINT` |  | high float made (each time) |
| `tHighTime` | `TIME` |  | the high float's made time, summed (each event at its end) |

## How it works

The floats of a sump or wet well, as a part of its [`FB_LevelControl`](FB_LevelControl.md) (EMPTY duty).

- Overflow backup: the high float made asks the level control to run (`E_PartAction.Run`); it keeps asking for `set.tHighHold` after the float clears.
- Transducer check: the high float made while the level reads below the check level for `set.tCheckDelay` is a transducer fault, latched until a reset (the owner's or the record's) or a power cycle: `bTransducerFault`, a warning on the owner. The check level: `set.fCheckLevel`; 0 (the default) = the level control's high-high (`ipOwner.fActHighHigh`); no check while that is not used either (3.4E38).
- Float / timer control, with the transducer fault or with no level value (unwired, not fitted, no value or not good): run while the high float is made and `set.tFloatRunTime` after it clears, then `set.tLockout` before the high float can start it again (the high-high float starts it at any time). The low float stops at once (`E_PartAction.Stop`, also the level control's own request).
- Both floats made: high wins, and "floats disagree" (a warning).
- `set.bRunAll`: while the overflow backup asks, `bRunAll` is TRUE (wire it to `FB_Stages.bRunAll`: every pump runs).
- Totals: `tot.nHighEvents` (high float made) and `tot.tHighTime` (its made time, added when it clears), kept over a power cut; the record's `bCmdResetStats` zeroes them.

One action per Evaluate: Run > Stop > Warn. The warnings also show on the part's own `bWarning` / `eErrorId`.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A sump with a transmitter and high / low floats as backup.

| Pin | Wire |
| --- | --- |
| `ipFloats` | `fbFloats` (an FB_SwitchSet) |
| `ipLevel` | `fbSumpLevel` |
| `ipOwner` | `fbLevelCtl` |
| `refData` | `stFloats` |

**Back to** [the index](../README.md).
