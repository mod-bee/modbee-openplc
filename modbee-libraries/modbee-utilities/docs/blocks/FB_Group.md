# FB_Group — Duty / standby / assist group

Duty / standby / assist over up to four pumps or motors: rotation (also by run hours), staging, failover, swap while running, a staged stop, idle exercise and a jockey pump. A level control or a run drives the group as it would drive one pump.

Offers `I_Equipment`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMember1` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipMember2` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipMember3` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipMember4` | `I_Equipment` |  | the members, any I_Equipment: pumps, motors; unwired = none. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `nExtra` | `INT` |  | members wanted beyond the first while it is asked to run: assist / staging; -1 = the jockey alone |
| in | `bRotate` | `BOOL R_EDGE` |  | rising edge: the lead moves on now Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_GroupData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bAnyRunning` | `BOOL` |  | A member runs |
| out | `nDuty` | `INT` |  | duty members fitted (the jockey not counted): -> FB_Cascade.nMembers |
| out | `nDutyRunning` | `INT` |  | duty members running: -> FB_Cascade.nRunning |
| out | `fRunCapacity` | `REAL` |  | the running duty members' capacity (I_Pump.fActCapacity; 0 = not known) |
| out | `fJockeyCapacity` | `REAL` |  | the jockey's capacity (0 = none, or not known) |
| out | `bJockeyReady` | `BOOL` |  | a jockey is fitted and available |
| out | `nRunning` | `INT` |  | Members running (wire to FB_Cascade's `nRunning`) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_GroupData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdRotate` | `BOOL` |  |  |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_GroupSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eRotate` | `E_Rotate` |  |  |
| `tRotateInterval` | `TIME` | `T#24h` |  |
| `nFixedLead` | `INT` | `1` |  |
| `tStageDelay` | `TIME` | `T#5s` |  |
| `tDestageDelay` | `TIME` | `T#5s` |  |
| `tFailover` | `TIME` | `T#10s` |  |
| `nMaxRunning` | `INT` |  | most members running at once, Hand included (0 = no limit) |
| `bHandCounts` | `BOOL` | `TRUE` | a member running in Hand counts toward the members wanted |
| `bSwapWhileRunning` | `BOOL` |  | a rotation while running: start the next member, then stop the old one |
| `eStop` | `E_GroupStop` |  | nothing asked any more: stop all at once, or one per tStopStep |
| `tStopStep` | `TIME` | `T#3s` | Staged: between member stops |
| `fHoursBand` | `REAL` | `1.0` | Hours: members this close in run hours (h) count as equal (rotation order) |
| `tExerciseEvery` | `TIME` |  | run a member idle this long while nothing is asked (0 = off) |
| `tExerciseTime` | `TIME` | `T#30s` | for this long |

**Status `sts`** (`ST_GroupSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | The first error since the last reset (first-out) |
| `nLead` | `INT` |  |  |
| `nRequired` | `INT` |  |  |
| `nRunning` | `INT` |  |  |
| `nCalled` | `INT` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `nExercising` | `INT` |  | members on an exercise run |
| `tExerciseIn` | `TIME` |  | until the next exercise run (0: off, or one running) |
| `nAvailable` | `INT` |  | duty members available (not skipped) |
| `bShortfall` | `BOOL` |  | asked for more members than can run (none left, or nMaxRunning) |
| `tRotateIn` | `TIME` |  | Periodic: until the next rotation (0 otherwise) |
| `bStopping` | `BOOL` |  | a staged stop is under way |

## Lists

- `E_GroupStop`: `AllAtOnce`, `Staged` (default `AllAtOnce`)
- `E_Rotate`: `EachStart`, `Periodic`, `Fixed`, `Hours` (default `EachStart`)

## How it works

Duty / standby / assist over up to four pumps or motors. It offers `I_Equipment` itself, so a level control or a run drives a group as it drives one pump.

A member whose `I_Pump` role is Booster is left out ([`FB_Booster`](FB_Booster.md) runs it).

Jockey: the first member that is an `I_Pump` with role Jockey is not a duty member (never the lead, never staged, swapped or counted in `nDuty`). With `nExtra` -1 ([`FB_Cascade`](FB_Cascade.md)'s low demand), or no duty member available, the group runs the jockey alone; with `nExtra` 0 or more it calls the duty members and keeps the jockey on until one of them runs (the hand-over). A staged stop releases it last.

Parts: a part added to the group (e.g. [`FB_LevelCheck`](FB_LevelCheck.md) High on the header flow meter for a burst main) is evaluated every scan: a trip or a stop releases every member at once (`bError` and the part's `eErrorId` on a trip, stop reason Part), a hold lets none start, a warning shows.

Asked to run: the lead first, then the next available members in rotation order up to 1 + `nExtra`, one per `set.tStageDelay`; released one per `set.tDestageDelay`, the most recent first. Failover: a called member that is not running after `set.tFailover` is skipped and the next one is called at once (until a reset or nothing is asked); a member that became unavailable is skipped until it is available again. Rotation (`set.eRotate`): EachStart (the lead moves on at each group start), Periodic (every `set.tRotateInterval`), Fixed (`set.nFixedLead`). The lead is kept over a power cut. Nobody available while asked: a warning (NoneAvailable).

Hours rotation (`set.eRotate` = Hours): each call takes the available member with the fewest run hours (each member's `fActRunHours`, e.g. [`FB_Pump`](FB_Pump.md) / [`FB_Motor`](FB_Motor.md)'s `tot.fRunHours`); members within `set.fHoursBand` hours of each other count as equal and go in rotation order, and the lead moves on at each group start, so equal members take turns.

A member in Hand is never called (it is not available); while it runs it counts toward the members wanted (`set.bHandCounts`, default on) and always toward `set.nMaxRunning`, the most members running at once (0 = no limit).

Swap while running (`set.bSwapWhileRunning`): a rotation while the group runs (`bRotate`, `bCmdRotate`, Periodic) calls the next member first and releases the longest-running one (not the new lead) once the new one runs; nobody available, or no room under `nMaxRunning`: no swap.

Stop (`set.eStop`): when nothing is asked any more, AllAtOnce releases every member; Staged releases the most recent first, one per `set.tStopStep`. A new request during a staged stop keeps those still running.

Exercise (`set.tExerciseEvery`, 0 = off): while nothing is asked, a member that has not run for `tExerciseEvery` (an available one, not skipped) runs for `set.tExerciseTime`; a request, the member going unavailable or the setting off ends it; `sts.nExercising`, `sts.tExerciseIn` (until the next one). Idle time counts power-on time only (no clock). A member that exercises itself, or an owner exercise ([`FB_Exercise`](FB_Exercise.md) on the level control: it asks the group, so the lead runs), leaves this off.

Status: `sts.nAvailable` (duty members available), `sts.bShortfall` (asked for more members than can run: none left to call, or `nMaxRunning` reached), `sts.tRotateIn` (Periodic: until the next rotation), `sts.bStopping` (a staged stop).

An invalid setting is refused and put back (`sts.bRefused` / `eRefusedWhy`, a warning until a reset).

## Example

Two pumps sharing duty, called by a level control.

| Pin | Wire |
| --- | --- |
| `ipMember1` | `fbPump1` |
| `ipMember2` | `fbPump2` |
| `nExtra` | `fbStages.nExtra` (or 0) |
| `refData` | `stGroup` |
| `nRunning` | a display |

Then `ipTarget := fbGroup` on the FB_LevelControl.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Request(bRun, bHold, fSpeed, bUrgent) : E_UtError`
- method `Command(eCmd)`
- property `eActMode : E_Mode`
- property `bIsRunning : BOOL`
- property `bIsReady : BOOL`
- property `bIsAvailable : BOOL`
- property `bIsAuto : BOOL`
- property `bIsFaulted : BOOL`
- property `eActError : E_UtError`
- property `eActStopReason : E_StopReason`
- property `fActRunHours : REAL`: a group counts no hours of its own

**Back to** [the index](../README.md).
