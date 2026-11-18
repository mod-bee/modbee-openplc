# FB_Exercise — Idle exercise (a part)

Keeps idle equipment from seizing: after a set idle time it asks its owner for a short run.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the level control, or the valve. The owner's instance |
| in | `bExercise` | `BOOL R_EDGE` |  | run one now Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_ExerciseData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bExercising` | `BOOL` |  | An exercise run is asked now |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ExerciseData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdExercise` | `BOOL` |  | run one now (cleared by the block) |
| `bExercising` | `BOOL` |  | status |
| `tNextIn` | `TIME` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Settings `set`** (`ST_ExerciseSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tInterval` | `TIME` | `T#7d` | 0 = off |
| `tRun` | `TIME` | `T#30s` |  |

## How it works

Keeps idle equipment from seizing: after `set.tInterval` with its owner not running, it asks the owner for a run of `set.tRun`. Its owner (`ipOwner`) is a block that honours a part's Request:

```
  FB_LevelControl  the run goes through its pump or group, so the group's rotation exercises each member in turn
                   (a pump always has an owner, so a pump's exercise is its level control's)
  a valve          FB_Valve, FB_ValveLatch, FB_ValveMotor, FB_Valve3Pos (to set.nAutoPos), FB_ValveMod,
                   FB_ValveFloat (fully open): opened in Auto for tRun, then back to where its owner wants it;
                   the interlock, trips and the permissive still apply, and an owner's own request wins
```

`bExercise` (a rising edge) or `bCmdExercise` runs one now. Any run by the owner restarts the interval; `set.tInterval` 0 = off. The interval counts power-on time only (no clock).

## Example

Exercise the pumps of a station once a week.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbLevelCtl` (the FB_LevelControl) |
| `refData` | `stExercise` |

Set `stExercise.set.tInterval := T#7d` and `tRun`.

**Back to** [the index](../README.md).
