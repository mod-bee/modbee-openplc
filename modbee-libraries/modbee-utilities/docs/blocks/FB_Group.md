# FB_Group — Duty / standby / assist group

Duty / standby / assist over up to four pumps or motors: rotation (also by run hours), staging, failover, swap while running, a staged stop, idle exercise and a jockey pump. A level control or a run drives the group as it would drive one pump.

Offers `I_Equipment`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipMember1` | `I_Equipment` |  | member 1 (a pump, motor or valve; unwired = none) |
| in | `ipMember2` | `I_Equipment` |  | member 2 (unwired = none) |
| in | `ipMember3` | `I_Equipment` |  | member 3 (unwired = none) |
| in | `ipMember4` | `I_Equipment` |  | member 4 (unwired = none) |
| in | `nExtraMembers` | `INT` |  | members wanted beyond the first while it is asked to run; -1 = the jockey alone |
| in | `bRotate` | `BOOL R_EDGE` |  | rising edge: the lead moves on now |
| in | `refData` | `REFERENCE TO ST_GroupData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bAnyMemberRunning` | `BOOL` |  | a member runs |
| out | `nDutyMembers` | `INT` |  | duty members fitted (the jockey not counted): -> FB_Cascade.nDutyPumps |
| out | `nDutyMembersRunning` | `INT` |  | duty members running: -> FB_Cascade.nDutyPumpsRunning |
| out | `fRunningCapacity` | `REAL` |  | the running duty members' capacity (I_Pump.fActCapacity; 0 = not known) |
| out | `fJockeyCapacity` | `REAL` |  | the jockey's capacity (0 = none, or not known) |
| out | `bJockeyReady` | `BOOL` |  | a jockey is fitted and available |
| out | `nMembersRunning` | `INT` |  | members running now |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_GroupData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdRotateNow` | `BOOL` |  | HMI: the lead moves on now (acts once, cleared by the block) |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |

**Settings `set`** (`ST_GroupSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eRotateBy` | `E_Rotate` |  | how the lead moves on: EachStart, Periodic, Fixed or Hours |
| `tRotateInterval` | `TIME` | `T#24h` | Periodic: the lead moves on this often |
| `nFixedLeadMember` | `INT` | `1` | Fixed: the member that always leads (1..4) |
| `tAddMemberAfter` | `TIME` | `T#5s` | while more are wanted: the next member is added this long after the last add or drop |
| `tDropMemberAfter` | `TIME` | `T#5s` | while still asked, for fewer: the next member is dropped (the most recent first) this long after the last add or drop |
| `tFailoverAfter` | `TIME` | `T#10s` | a called member not running after this is skipped and the next one called |
| `nMaxMembersRunning` | `INT` |  | most members running at once, Hand included (0 = no limit) |
| `bHandRunCounts` | `BOOL` | `TRUE` | a member running in Hand counts toward the members wanted |
| `bSwapWhileRunning` | `BOOL` |  | a rotation while running: start the next member, then stop the old one |
| `eStopOrder` | `E_GroupStop` |  | nothing asked any more: stop AllAtOnce, or Staged (one per tStagedStopInterval) |
| `tStagedStopInterval` | `TIME` | `T#3s` | eStopOrder Staged, nothing asked any more: the first member stops at once, each next one this long after the last |
| `fEqualHoursBand` | `REAL` | `1.0` | Hours: members this close in run hours (h) count as equal (rotation order) |
| `tExerciseAfterIdle` | `TIME` |  | run a member idle this long while nothing is asked (0 = off) |
| `tExerciseRunTime` | `TIME` | `T#30s` | for this long |

**Status `sts`** (`ST_GroupSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | what it is doing now |
| `eErrorId` | `E_UtError` |  | the first error since the last reset (first-out) |
| `nLeadMember` | `INT` |  | the member that leads now (1..4) |
| `nMembersRequired` | `INT` |  | members wanted now |
| `nMembersRunning` | `INT` |  | members running now |
| `nMembersCalled` | `INT` |  | members called to run now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `nMembersExercising` | `INT` |  | members on an exercise run |
| `tNextExerciseTimeLeft` | `TIME` |  | until the next exercise run (0: off, or one running) |
| `nMembersAvailable` | `INT` |  | duty members available (not skipped) |
| `bMembersShort` | `BOOL` |  | asked for more members than can run (none left, or nMaxMembersRunning) |
| `tRotateTimeLeft` | `TIME` |  | Periodic: until the next rotation (0 otherwise) |
| `bStopping` | `BOOL` |  | a staged stop is under way |

## Lists

- `E_GroupStop`: `AllAtOnce`, `Staged` (default `AllAtOnce`)
- `E_Rotate`: `EachStart`, `Periodic`, `Fixed`, `Hours` (default `EachStart`)

## How it works

Duty / standby / assist over up to four pumps or motors. It offers `I_Equipment` itself, so a level control or a run drives a group as it drives one pump.

A member whose `I_Pump` role is Booster is left out ([`FB_Booster`](FB_Booster.md) runs it).

Jockey: the first member that is an `I_Pump` with role Jockey is not a duty member (never the lead, never staged, swapped or counted in `nDutyMembers`). With `nExtraMembers` -1 ([`FB_Cascade`](FB_Cascade.md)'s low demand), or no duty member available, the group runs the jockey alone; with `nExtraMembers` 0 or more it calls the duty members and keeps the jockey on until one of them runs (the hand-over). A staged stop releases it last.

Parts: a part added to the group (e.g. [`FB_LevelCheck`](FB_LevelCheck.md) High on the header flow meter for a burst main) is evaluated every scan: a trip or a stop releases every member at once (`bError` and the part's `eErrorId` on a trip, stop reason Part), a hold lets none start, a warning shows.

Asked to run: the lead first, then the next available members in rotation order up to 1 + `nExtraMembers`, one per `set.tAddMemberAfter`; released one per `set.tDropMemberAfter`, the most recent first. Failover: a called member that is not running after `set.tFailoverAfter` is skipped and the next one is called at once (until a reset or nothing is asked); a member that became unavailable is skipped until it is available again. Rotation (`set.eRotateBy`): EachStart (the lead moves on at each group start), Periodic (every `set.tRotateInterval`), Fixed (`set.nFixedLeadMember`). The lead is kept over a power cut. Nobody available while asked: a warning (NoneAvailable).

Hours rotation (`set.eRotateBy` = Hours): each call takes the available member with the fewest run hours (each member's `fActRunHours`, e.g. [`FB_Pump`](FB_Pump.md) / [`FB_Motor`](FB_Motor.md)'s `tot.fRunHours`); members within `set.fEqualHoursBand` hours of each other count as equal and go in rotation order, and the lead moves on at each group start, so equal members take turns.

A member in Hand is never called (it is not available); while it runs it counts toward the members wanted (`set.bHandRunCounts`, default on) and always toward `set.nMaxMembersRunning`, the most members running at once (0 = no limit).

Swap while running (`set.bSwapWhileRunning`): a rotation while the group runs (`bRotate`, `bCmdRotateNow`, Periodic) calls the next member first and releases the longest-running one (not the new lead) once the new one runs; nobody available, or no room under `nMaxMembersRunning`: no swap.

Stop (`set.eStopOrder`): when nothing is asked any more, AllAtOnce releases every member; Staged releases the most recent first: the first at once, then one per `set.tStagedStopInterval` (a shutdown gap, not the `set.tDropMemberAfter` of a smaller request, which counts from the last add or drop). A new request during a staged stop keeps those still running.

Exercise (`set.tExerciseAfterIdle`, 0 = off): while nothing is asked, a member that has not run for `tExerciseAfterIdle` (an available one, not skipped) runs for `set.tExerciseRunTime`; a request, the member going unavailable or the setting off ends it; `sts.nMembersExercising`, `sts.tNextExerciseTimeLeft` (until the next one). Idle time counts power-on time only (no clock). A member that exercises itself, or an owner exercise ([`FB_Exercise`](FB_Exercise.md) on the level control: it asks the group, so the lead runs), leaves this off.

Status: `sts.nMembersAvailable` (duty members available), `sts.bMembersShort` (asked for more members than can run: none left to call, or `nMaxMembersRunning` reached), `sts.tRotateTimeLeft` (Periodic: until the next rotation), `sts.bStopping` (a staged stop).

An invalid setting is refused and put back (`sts.bSettingRefused` / `eSettingRefusedErrorId`, a warning until a reset).

## Example

Two pumps sharing duty, called by a level control.

| Pin | Wire |
| --- | --- |
| `ipMember1` | `fbPump1` |
| `ipMember2` | `fbPump2` |
| `nExtraMembers` | `fbStages.nExtraPumps` (or 0) |
| `refData` | `stGroup` |
| `nMembersRunning` | a display |

Then `ipEquipment := fbGroup` on the FB_LevelControl.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- method `Request(bRun, bHoldOff, fSpeedSetpointPct, bOverflowUrgent) : E_UtError`
- method `Command(eCommand)`
- property `eActMode : E_Mode`: the mode it is in now
- property `bIsRunning : BOOL`: a member is running
- property `bIsReady : BOOL`: could start now if asked
- property `bIsAvailable : BOOL`: in Auto, not tripped, not interlocked
- property `bIsAuto : BOOL`: in Auto now
- property `bIsFaulted : BOOL`: a trip or setting fault is active
- property `eActError : E_UtError`: the error shown now
- property `eActStopReason : E_StopReason`: why it last stopped
- property `fActRunHours : REAL`: a group counts no hours of its own
