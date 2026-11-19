# FB_Stages — Extra pump station stages

The extra level stages 2 to 4 of a pump station: tells an FB_Group how many more pumps to call.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipLevel` | `I_Measurement` |  | required. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `eControlMode` | `E_LevelMode` |  | Empty (sump) or Fill (tank): the level control's |
| in | `bLevelControlRunning` | `BOOL` |  | the stages may act (the level control is running) |
| in | `nPumps` | `INT` | `2` | pumps in the station |
| in | `bRunAllPumps` | `BOOL` |  | every pump (FB_LevelFloats.bRunAllPumps: the overflow backup) |
| in | `bDemandActive` | `BOOL` |  | a demand runs (FB_LevelControl.bDemandActive) |
| in | `refData` | `REFERENCE TO ST_StagesData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `nExtraPumps` | `INT` |  | -> FB_Group.nExtraMembers |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StagesData` (pin `refData`)

**Settings `set`** (`ST_StagesSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `aExtraPumpLevels` | `ARRAY[2..4] OF ST_Stage` |  | 0 / 0 = not used; fields below |
| `nDemandPumps` | `INT` | `1` | pumps on a demand (at least) |

**`aExtraPumpLevels`** (`ST_Stage`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fStartLevel` | `REAL` |  | this pump starts at this level |
| `fStopLevel` | `REAL` |  | this pump stops at this level |

**Status `sts`** (`ST_StagesSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nExtraPumps` | `INT` |  | pumps wanted beyond the first now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_LevelMode`: `Empty`, `Fill`, `Timed` (default `Empty`)

## How it works

The extra level stages of a pump station. Stage 1 is [`FB_LevelControl`](FB_LevelControl.md)'s own start / stop; this block adds stages 2..4 and tells an [`FB_Group`](FB_Group.md) how many more pumps to call (`nExtraPumps` -> `FB_Group.nExtraMembers`). Stage n is on from its start point until its stop point: Empty starts above and stops below (`fStartLevel` > `fStopLevel`), Fill starts below and stops above (`fStartLevel` < `fStopLevel`); a stage the wrong way round, not a number, or both 0 is not used. Stages 2 and 3 call one pump each; stage 4 calls every remaining pump of a station of more than 3 (`nPumps`). `bLevelControlRunning` FALSE (the level control not running: off, level not trusted, inhibited) drops every stage. A bad level drops them too. `bDemandActive` (`FB_LevelControl.bDemandActive`): while a demand runs, at least `set.nDemandPumps` pumps run.

## Example

A three-pump station: stages 2 and 3 call more pumps.

| Pin | Wire |
| --- | --- |
| `ipLevel` | `fbSumpLevel` |
| `eControlMode` | `E_LevelMode.Empty` |
| `bLevelControlRunning` | `fbLevelCtl.bRunning` |
| `nPumps` | 3 |
| `refData` | `stStages` |
| `nExtraPumps` | `fbGroup.nExtraMembers` |

**Back to** [the index](../README.md).
