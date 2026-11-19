# 11 - Settings both ways: serve and bind

A panel shows a setting and lets the operator change it. The PLC decides
whether the new value is allowed. Whatever it decides, the panel must end up
showing what the PLC holds - never a value the PLC refused, never a value a
lost frame left behind.

That is two methods, and nothing else in either program:

| | |
| --- | --- |
| `node.Serve` | on the PLC: serves a `STRUCT`, one topic per member, and decides every change asked of it |
| `node.Bind` | on the panel (or SCADA, or another PLC): keeps a `STRUCT` of the same type equal to the PLC's, and asks for its changes |

No subscribe-and-write pair, no copy-back, no command flags cleared by the
program, no timers or retries. The protocol carries every change, waits for the
decision, and puts the owner's value back in the member.

New projects start here. The methods of [05 - Topics](05-topics.md) are still
there underneath, for anything that needs them on their own.

## An example

The types, the same on both nodes:

```
TYPE
  PUMP_SET : STRUCT
    runTime  : TIME := T#10m;
    level    : REAL := 60.0;
    enabled  : BOOL := TRUE;
    name     : STRING(20) := 'Bore 1';
  END_STRUCT;

  PUMP_CMD : STRUCT
    start    : BOOL;
    stop     : BOOL;
    resetHrs : BOOL;
  END_STRUCT;
END_TYPE
```

The PLC, node 1:

```
node.Serve(anyData := SET, nFirstTopicId := 300, bPeersMayChange := TRUE);
node.Serve(anyData := CMD, nFirstTopicId := 400, bPeersMayChange := TRUE, bMembersAreCommands := TRUE,
           tPulseLength := T#500ms);

pump(RUN_TIME := SET.runTime, START := CMD.start, STOP := CMD.stop, ...);
```

The panel, node 2:

```
node.Bind(anyData := SET, nPeerNodeId := 1, nFirstTopicId := 300, bDeliverEveryChange := TRUE,
          eBindState => eSetState, bInSync => bSetInSync);
node.Bind(anyData := CMD, nPeerNodeId := 1, nFirstTopicId := 400, bDeliverEveryChange := TRUE);
```

The operator types 15 minutes into the panel's `SET.runTime`. The panel's bind
goes `Pending`, the change reaches the PLC, `SET.runTime` there becomes
`T#15m`, the pump block runs with it, and the panel's bind goes back to
`InSync`. Nothing in either program did any of that.

## How the PLC decides

A change is put into the member when `Serve` is called. The program then runs -
every block that reads the member sees the new value - and after that scan (and
`tAnswerDelay`, if the block that judges it needs longer) the member is read back:

- still holding what was asked: **Accepted**;
- holding something else: **Changed**, and the panel is told the value kept.

So the rule that a setting must stay in range lives where it already does, in
the block that uses it. A block that refuses a value and puts its own back
needs no extra rung to tell the panel; one that clamps it is reported the same
way. `nRefusedChangeCount` on `Serve` counts them, and `bChangedByPeer`, `nMembersChanged`,
`sFirstChangedMember` and `nChangedByNodeId` say what was taken by this call.

`nOfflineBufferDepth` holds each member in a ring of that many while the network is away,
as `node.Buffer` does for one topic.

## Commands

`bMembersAreCommands := TRUE` makes every member a command: each change is one event for
the program, taken exactly once - not twice when an acknowledgement is lost and
the change is sent again, and not lost when the network drops a frame. A `BOOL`
command goes back to `FALSE` after `tPulseLength`, so the panel sees it go back too.

On the panel, setting `CMD.start := TRUE` is the whole button. The bind takes it
to the PLC, the PLC takes it once, and `start` comes back `FALSE` when the pulse
ends.

## bDeliverEveryChange, and when not

`bDeliverEveryChange := TRUE` on the bind is for setpoints, settings and configuration:
every change arrives, and one a lost frame took is sent again, as the current
value, within a rotation or two. It costs about two bytes a rotation while
values move, nothing while they do not. After a long spell of loss the bind
settles back on the PLC's value by itself once the link is clean: within seconds
on a fast ring, up to a minute on a slow one (a scan of 100 ms or more), where a
change whose answer was lost waits for its retry.

Live values - levels, flows, speeds updated every scan - do not need it, and it
is off by default. Bind or subscribe them Live: best effort, newest wins, an
`fDeadband` allowed.

## What the panel shows

`eBindState` is the worst member. In a Ladder rung use the `BOOL`s, since a rung
cannot compare an enumeration:

| output | show |
| --- | --- |
| `bInSync` | the values are the PLC's |
| `bChangePending` | "sending..." - a change is with the PLC |
| `bSettingRefused` | "refused: kept *value*" - the member already holds the kept value; `sFirstRefusedMember` says which member |
| `bNoDecisionReceived` | "not answered" - the member holds the PLC's last value |
| `eBindState = E_BeeBusBindState.Offline` | the PLC is not on the network |
| `eBindState = E_BeeBusBindState.Syncing` | waiting for the PLC's values (at start, and after it restarted) |

`bSettingRefused` and `bNoDecisionReceived` clear by themselves on the member's next change or the
PLC's next value. `tOldestMemberAge` is how long since the oldest member last had a value
from the PLC, and `bValueReceived` says one arrived since the last call.

## Restarts

A panel or a PLC that restarts - even one back before the other noticed it go -
is told apart from the instance before it, and the binds start again on their
own: `Syncing`, then `InSync` with the PLC's values. Nothing in the program.

## One write, with its answer

For a single write that is not a bind - a value a sequence sets once -
`node.Write` with `bAskOwnerDecision := TRUE` waits for the owner's decision: the
result is `Queued`, then `Ok` with `eOwnerDecision` (`E_BeeBusOutcome.Accepted`,
`Changed` ...), `bOwnerAccepted`, `bOwnerKeptOtherValue` and `fOwnerKeptValue`, held until the next
edge.

## What not to write any more

- A subscription of the PLC's settings plus a separate write for changes.
- Copying a settings `STRUCT` into the blocks' `set` and back every scan to
  "bounce" a refused value.
- Command flags the program clears after acting (`TRUE` then `FALSE`, or `-1`
  for "no command").
- Timers on the panel that guess "refused" from what arrives.
- Subscribing a few topics at a time, and re-subscribing when the PLC comes
  back.

All of it is in the protocol now.
