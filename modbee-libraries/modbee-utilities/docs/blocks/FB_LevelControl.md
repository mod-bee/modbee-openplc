# FB_LevelControl — Level control: empty, fill or timed

Keeps a level by driving a pump or a group: EMPTY (a sump, a wet well), FILL (a tank) or TIMED (on / off with no level), with high-high and low-low levels, a demand run, a moving start level and an action for a bad level.

Offers `I_LevelControl`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | the process may run: e.g. the system not Off |
| in | `bDemand` | `BOOL` |  | pump down / fill now, past the start level, to set.fDemandStop |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: nothing is requested |
| in | `ipLevel` | `I_Measurement` |  | required. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipTarget` | `I_Equipment` |  | required. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_LevelControlData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRunning` | `BOOL` |  | it asks and the pump runs |
| out | `bCall` | `BOOL` |  | the level calls for pumping |
| out | `bAtStop` | `BOOL` |  | at or past the stop level |
| out | `bHighHigh` | `BOOL` |  | The high-high switch / level |
| out | `bLowLow` | `BOOL` |  | The low-low switch / level |
| out | `bDemandActive` | `BOOL` |  | a demand is running (-> FB_Stages bDemand) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LevelControlData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdDemand` | `BOOL` |  | as the bDemand pin, latched until the demand level is reached |
| `bCmdStop` | `BOOL` |  | ends a latched demand |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_LevelControlSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_LevelMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `bDemandOnly` | `BOOL` |  |  |
| `fStart` | `REAL` |  |  |
| `fStop` | `REAL` |  |  |
| `fDemandStop` | `REAL` |  |  |
| `fHighHigh` | `REAL` | `3.4E38` | EMPTY: overflow run; FILL: full, no run (3.4E38 / -3.4E38: not used) |
| `fLowLow` | `REAL` | `-3.4E38` | EMPTY: cut-out; FILL: alarm only |
| `eLevelFail` | `E_LevelFail` |  |  |
| `stLevelBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#10s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `tRunOnMax` | `TIME` | `T#10m` | RunOn: the longest run-on on a failed level |
| `fStartVariation` | `REAL` |  | the start moves at random by up to this each cycle (0 = off) |
| `fDemandRestart` | `REAL` |  | a held demand reruns at this level (0 = the start level) |
| `tOnTime` | `TIME` | `T#5m` | TIMED |
| `tOffTime` | `TIME` | `T#5m` | Off time |

**Status `sts`** (`ST_LevelControlSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | The first error since the last reset (first-out) |
| `bCall` | `BOOL` |  | the level calls for pumping |
| `bDemandActive` | `BOOL` |  | for FB_Stages' demand pumps |
| `bAtStop` | `BOOL` |  | at or past the stop level |
| `bHighHigh` | `BOOL` |  | The high-high switch / level |
| `bLowLow` | `BOOL` |  | The low-low switch / level |
| `bRequest` | `BOOL` |  | what it asks of the pump |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `stLevelBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `fStartNow` | `REAL` |  | the start level in use (with its variation) |
| `bRunOn` | `BOOL` |  | running on a failed level |

## Lists

- `E_LevelFail`: `Stop`, `RunOn` (default `Stop`)
- `E_LevelMode`: `Empty`, `Fill`, `Timed` (default `Empty`)

## How it works

Keeps a level by driving a pump.

EMPTY (sump, wet well): start at or above `fStart`, stop at or below `fStop`; `bDemand` runs it down to `fDemandStop`; at or above `fHighHigh` it always runs (overflow), also with `bDemandOnly`; at or below `fLowLow` it never runs.

FILL (tank): start at or below `fStart`, stop at or above `fStop`; `bDemand` fills to `fDemandStop`; at or above `fHighHigh` it never runs (full); `fLowLow` is an alarm level only.

TIMED: no level needed (`ipLevel` may be unwired): on for `set.tOnTime`, off for `set.tOffTime`, over and over (on first), while `bRun`. `set.fStartVariation`: the start level moves at random by up to this, either way, after each cycle (fat build-up in a sump; used only when smaller than the start-stop gap). A held `bDemand` that reached `set.fDemandStop` runs again when the level is back at `set.fDemandRestart` (0 = the start level). -> `bDemandActive` (for [`FB_Stages`](FB_Stages.md)' demand pumps). `bDemandOnly`: the start / stop levels are not used, it runs on `bDemand` only (the high-high still acts in EMPTY). A bad level is ridden through for its protection delay (the request held), then `set.eLevelFail`: Stop or RunOn (keeps the request as it was, for at most `set.tRunOnMax`, then stops).

Parts ([`FB_LevelCheck`](FB_LevelCheck.md), [`FB_Protection`](FB_Protection.md)): a trip stops the request; a signal pauses it (source low, no flow); its parts: float backup ([`FB_LevelFloats`](FB_LevelFloats.md)), cleaning ([`FB_SumpClean`](FB_SumpClean.md)), exercise ([`FB_Exercise`](FB_Exercise.md)), booster ([`FB_Booster`](FB_Booster.md)), level checks ([`FB_LevelCheck`](FB_LevelCheck.md)); beside it: stages ([`FB_Stages`](FB_Stages.md) -> `FB_Group.nExtra`).

## Example

A sump emptied by a duty / standby group.

| Pin | Wire |
| --- | --- |
| `bRun` | `fbSystem.bIsAuto` |
| `ipLevel` | `fbSumpLevel` |
| `ipTarget` | `fbGroup` |
| `refData` | `stLevelCtl` |
| `bHighHigh` | the high-level alarm |

In `stLevelCtl.set`: the mode `Empty`, the start and stop levels, the high-high and low-low.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActHighHigh : REAL`

## See also

[FB_Pump](FB_Pump.md), [FB_Group](FB_Group.md), [FB_LevelCheck](FB_LevelCheck.md), [FB_LevelFloats](FB_LevelFloats.md), [FB_Stages](FB_Stages.md), [FB_SumpClean](FB_SumpClean.md), [FB_Booster](FB_Booster.md)

**Back to** [the index](../README.md).
