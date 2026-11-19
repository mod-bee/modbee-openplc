# FB_Exercise — Idle exercise (a part)

Keeps idle equipment from seizing: after a set idle time it asks its owner for a short run.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the level control, or the valve. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `bExerciseNow` | `BOOL R_EDGE` |  | run one now |
| in | `refData` | `REFERENCE TO ST_ExerciseData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bExercising` | `BOOL` |  | an exercise run is asked now |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ExerciseData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdExerciseNow` | `BOOL` |  | run one now (cleared by the block) |

**Settings `set`** (`ST_ExerciseSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tExerciseAfterIdle` | `TIME` | `T#7d` | 0 = off |
| `tExerciseRunTime` | `TIME` | `T#30s` | how long each exercise run lasts |

**Status `sts`** (`ST_ExerciseSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bExercising` | `BOOL` |  | an exercise run is asked now |
| `tNextExerciseTimeLeft` | `TIME` |  | time until the next exercise run |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

Keeps idle equipment from seizing: after `set.tExerciseAfterIdle` with its owner not running, it asks the owner for a run of `set.tExerciseRunTime`. Its owner (`ipOwner`) is a block that honours a part's Request:

```
  FB_LevelControl  the run goes through its pump or group, so the group's rotation exercises each member in turn
                   (a pump always has an owner, so a pump's exercise is its level control's)
  a valve          FB_Valve, FB_ValveLatch, FB_ValveMotor, FB_Valve3Pos (to set.nAutoPosition), FB_ValveMod,
                   FB_ValveFloat (fully open): opened in Auto for tExerciseRunTime, then back to where its owner wants it;
                   the interlock, trips and the permissive still apply, and an owner's own request wins
```

`bExerciseNow` (a rising edge) or `bCmdExerciseNow` runs one now. Any run by the owner restarts the interval; `set.tExerciseAfterIdle` 0 = off. The interval counts power-on time only (no clock).

## Example

Exercise the pumps of a station once a week.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbLevelCtl` (the FB_LevelControl) |
| `refData` | `stExercise` |

Set `stExercise.set.tExerciseAfterIdle := T#7d` and `tExerciseRunTime`.

**Back to** [the index](../README.md).
