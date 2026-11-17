# FB_Stages — Extra pump station stages

The extra level stages 2 to 4 of a pump station: tells an FB_Group how many more pumps to call.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipLevel` | `I_Measurement` |  | required. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `eMode` | `E_LevelMode` |  | Empty (sump) or Fill (tank): the level control's |
| in | `bRun` | `BOOL` |  | the stages may act (the level control is running) |
| in | `nMembers` | `INT` | `2` | pumps in the station |
| in | `bDemand` | `BOOL` |  | a demand runs (FB_LevelControl.bDemandActive) |
| in | `refData` | `REFERENCE TO ST_StagesData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `nExtra` | `INT` |  | -> FB_Group.nExtra |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StagesData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nExtra` | `INT` |  | status |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_StagesSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `aStage` | `ARRAY[2..4] OF ST_Stage` |  | 0 / 0 = not used; fields below |
| `nDemandPumps` | `INT` | `1` | pumps on a demand (at least) |

**`aStage`** (`ST_Stage`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fStart` | `REAL` |  |  |
| `fStop` | `REAL` |  |  |

## Lists

- `E_LevelMode`: `Empty`, `Fill`, `Timed` (default `Empty`)

## How it works

The extra level stages of a pump station. Stage 1 is [`FB_LevelControl`](FB_LevelControl.md)'s own start / stop; this block adds stages 2..4 and tells an [`FB_Group`](FB_Group.md) how many more pumps to call (`nExtra` -> `FB_Group.nExtra`). Stage n is on from its start point until its stop point: Empty starts above and stops below (`fStart` > `fStop`), Fill starts below and stops above (`fStart` < `fStop`); a stage the wrong way round, not a number, or both 0 is not used. Stages 2 and 3 call one pump each; stage 4 calls every remaining pump of a station of more than 3 (`nMembers`). `bRun` FALSE (the level control not running: off, level not trusted, inhibited) drops every stage. A bad level drops them too. `bDemand` (`FB_LevelControl.bDemandActive`): while a demand runs, at least `set.nDemandPumps` pumps run.

## Example

A three-pump station: stages 2 and 3 call more pumps.

| Pin | Wire |
| --- | --- |
| `ipLevel` | `fbSumpLevel` |
| `eMode` | `E_LevelMode.Empty` |
| `bRun` | `fbLevelCtl.bRunning` |
| `nMembers` | 3 |
| `refData` | `stStages` |
| `nExtra` | `fbGroup.nExtra` |

**Back to** [the index](../README.md).
