# FB_LevelFloats — Sump floats: backup and transmitter check (a part)

The floats of a sump or wet well, added to its level control: an overflow backup run, a check of the level transmitter against the high float, and float / timer control when the transmitter is lost.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipFloats` | `I_Measurement` |  | required. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipTransducer` | `I_Measurement` |  | the transducer (optional). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipOwner` | `I_LevelControl` |  | required: the level control. An instance of a block that offers I_LevelControl (FB_LevelControl) |
| in | `refData` | `REFERENCE TO ST_LevelFloatsData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bTransducerFault` | `BOOL` |  | the transmitter disagrees with the high float (latched until a reset) |
| out | `bOnFloatControl` | `BOOL` |  | running on the floats and timers |
| out | `bRunAllPumps` | `BOOL` |  | the overflow backup asks every pump (set.bRunAllPumps) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelFloatsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTransducerFault` | `BOOL` |  | clear the transducer fault (cleared by the block) |
| `bCmdResetTotals` | `BOOL` |  | zero tot (cleared by the block) |

**Settings `set`** (`ST_LevelFloatsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tOverflowRunOnTime` | `TIME` | `T#2m` | the overflow keeps running this long after the high float clears |
| `tFloatRunOnTime` | `TIME` | `T#5m` | float control: runs on this long after the high float clears |
| `tFloatRestTime` | `TIME` | `T#1m` | float control: then this long before the high float starts it again |
| `tTransducerCheckDelay` | `TIME` | `T#10s` | transducer check |
| `fTransducerCheckLevel` | `REAL` |  | the high float made with the level below this = transducer fault (0: the owner's high-high) |
| `bRunAllPumps` | `BOOL` |  | the overflow backup runs every pump (bRunAllPumps -> FB_Stages.bRunAllPumps) |

**Status `sts`** (`ST_LevelFloatsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bAsksToRun` | `BOOL` |  | asks the level control to run |
| `bLowFloatStops` | `BOOL` |  | the low float stops it (float control) |
| `bOnFloatControl` | `BOOL` |  | running on the floats and timers |
| `bTransducerFault` | `BOOL` |  | the transmitter disagrees with the high float (latched until a reset) |
| `bFloatsDisagree` | `BOOL` |  | high and low made together |
| `bFloatResting` | `BOOL` |  | float control lockout |
| `tTimeLeft` | `TIME` |  | of the high hold, the run-on or the lockout now counting |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Totals `tot`** (`ST_LevelFloatsTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nHighFloatCount` | `UDINT` |  | high float made (each time) |
| `tHighFloatTime` | `TIME` |  | the high float's made time, summed (each event at its end) |

## How it works

The floats of a sump or wet well, as a part of its [`FB_LevelControl`](FB_LevelControl.md) (EMPTY duty).

- Overflow backup: the high float made asks the level control to run (`E_PartAction.Run`); it keeps asking for `set.tOverflowRunOnTime` after the float clears.
- Transducer check: the high float made while the level reads below the check level for `set.tTransducerCheckDelay` is a transducer fault, latched until a reset (the owner's or the record's) or a power cycle: `bTransducerFault`, a warning on the owner. The check level: `set.fTransducerCheckLevel`; 0 (the default) = the level control's high-high (`ipOwner.fActHighHighLevel`); no check while that is not used either (3.4E38).
- Float / timer control, with the transducer fault or with no level value (unwired, not fitted, no value or not good): run while the high float is made and `set.tFloatRunOnTime` after it clears, then `set.tFloatRestTime` before the high float can start it again (the high-high float starts it at any time). The low float stops at once (`E_PartAction.Stop`, also the level control's own request).
- Both floats made: high wins, and "floats disagree" (a warning).
- `set.bRunAllPumps`: while the overflow backup asks, `bRunAllPumps` is TRUE (wire it to `FB_Stages.bRunAllPumps`: every pump runs).
- Totals: `tot.nHighFloatCount` (high float made) and `tot.tHighFloatTime` (its made time, added when it clears), kept over a power cut; the record's `bCmdResetTotals` zeroes them.

One action per Evaluate: Run > Stop > Warn. The warnings also show on the part's own `bWarning` / `eErrorId`.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A sump with a transmitter and high / low floats as backup.

| Pin | Wire |
| --- | --- |
| `ipFloats` | `fbFloats` (an FB_SwitchSet) |
| `ipTransducer` | `fbSumpLevel` |
| `ipOwner` | `fbLevelCtl` |
| `refData` | `stFloats` |

**Back to** [the index](../README.md).
