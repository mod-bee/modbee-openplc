# 05 - Topics

A topic is a **named, typed value** that a node owns. Peers subscribe to it and
the value arrives on its own - nothing polls.

The methods:

| | |
| --- | --- |
| `node.Topic` | own a topic; the node publishes it by itself |
| `node.Subscribe` | bind a peer's topic and ask for a stream of it |
| `node.PublishStruct` | own a whole `STRUCT`, one topic per member |
| `node.SubscribeStruct` | a peer's whole `STRUCT`, into one of yours |
| `node.Publish` | own a topic and send it when **you** say so |
| `node.Write` | write one value into a peer's writable topic |
| `node.Buffer` | hold samples while there is nowhere to send them |

A panel or SCADA that changes settings in a PLC does not need to put these
together: `node.Serve` and `node.Bind` do it in one call each side
([11 - Settings both ways](11-bidirectional-binding.md)).

## Owning one - `node.Topic`

```
node.Topic(anyValue := rLevel, sTopic := 'tank_level', nTopicId := 1);
```

That is the whole thing. There is no send: once bound, the node publishes
`rLevel` to every subscriber, on the deadband and interval each of them asked
for. Move the variable and it goes out. It returns `Ok` while bound.

**`sTopic`** is the identity - up to 253 characters (a `STRING(254)`, the
longest the editor declares, and a full one may have been cut to fit). Longer is
refused rather than truncated, because two long names cut alike become one
topic across the whole network, silently. A node with an older BeeBus (before
names grew past 31 characters) refuses a longer name it is sent and does not
learn that topic: keep names to 31 characters while such a node is on the
network.

**`nTopicId`** is 1 to 32767 and unique on this node. It is what travels on the
wire; the name is for people. Under 128 costs one byte instead of two.

**`anyValue`** is the variable, and its declared type is the type on the wire:
`BOOL`, `SINT`, `USINT`, `BYTE`, `INT`, `UINT`, `WORD`, `DINT`, `UDINT`,
`DWORD`, `LINT`, `ULINT`, `LWORD`, `REAL`, `LREAL`, `LTIME` or `STRING`.
`LTIME` travels as an `LINT` of nanoseconds, which is what IEC 61131-3 defines
it to be. `WSTRING`, a `STRUCT` or an array is refused with `InvalidArgument`
(`PublishStruct` carries those, and `TIME`, `TOD`, `DT` and `DATE`; see below).

**Peers may read this topic; they may not write it.** To take a command from
elsewhere, subscribe to a topic that node owns - see *Commanding* below - or
make it a writable member of a `PublishStruct` or `Serve`.

**One variable, one topic.** `sTopic` and `nTopicId` are taken on the first call
that binds; a later call that changes them returns `InvalidArgument` and the
topic stays as bound. For many values at once, put them in a `STRUCT` and use
`PublishStruct`.

## A whole STRUCT - `node.PublishStruct`

Everything an HMI shows, in one `STRUCT`, published by one call:

```
TYPE PLANT_STS : STRUCT
  systemMode  : INT;          (* topic 100 *)
  levelPct    : REAL;         (* topic 101 *)
  pumpRunning : BOOL;         (* topic 102 *)
  banner      : STRING(64);   (* topic 103 *)
  hmi         : PANEL;        (* hmi.page 104, hmi.alarmCount 105 *)
  spare       : ARRAY[1..2] OF REAL;   (* spare[1] 106, spare[2] 107 *)
END_STRUCT END_TYPE

node.PublishStruct(anyData := STS, nFirstTopicId := 100, nMembers => nStsMembers);
```

- **Each member is a topic.** Its name is the member's name as declared; a
  nested `STRUCT` adds a dot (`hmi.page`), an array element its position in
  brackets counting from 1 (`spare[1]`). Names are 255 characters at most,
  `sTopicPrefix` included: a longer one refuses the whole `STRUCT`, and the node's
  `sLastError` names it. `sTopicPrefix` goes in front of every name when two
  `STRUCT`s on one node share member names.
- **`anyData` may be an `ARRAY`** of `STRUCT`s or of simple values: one call for
  a list of alike things. Each element is named from its position on, after
  `sTopicPrefix` - `sTopicPrefix := 'alarms'` gives `alarms[1].active`,
  `alarms[3].set.prot.delay` - without the variable's own name, so the
  subscriber's `ARRAY` may be called anything.
- **Its id is `nFirstTopicId` plus its position**, counting from 0 in declaration
  order, every array element and nested member one position. Add members at the
  **end**: one added in the middle moves every id after it.
- **Types:** as for `Topic`, plus `TIME` and `TOD` as `DINT` milliseconds, `DT`
  and `DATE` as `UDINT` seconds since 1970, and an enumeration as its integer. A
  `WSTRING` member refuses the `STRUCT`.
- **Members travel one by one.** Five members changed on one scan go as five
  values, a few to each turn of the token, so the far end may see them over two
  or three scans. Don't use one member as a "the rest has arrived" flag.

The other side is one call too, with a `STRUCT` of the same type:

```
node.SubscribeStruct(anyData := STS, nPeerNodeId := 1, nFirstTopicId := 100,
                     eQuality => eStsQuality, bAllMembersEverReceived => bStsSeen);
```

It subscribes every member, and reports for the lot: `eQuality` (the worst
member), `bAllMembersEverReceived` (every member has arrived), `tOldestMemberAge` (the oldest member's
age), `nMembersReceived`, `sFirstReceivedMember` and `nFirstReceivedIndex` (what arrived since the last
call), and `nMissedUpdateCount`.

**Use the same TYPE on both sides.** Topics travel by id, and the ids come from
the member order. Keep the `STRUCT` in one place both projects take it from.

**The table is generated, not typed.** A table generator reads the `.st` file
and prints every member's name, topic id, type and register address as Markdown
and as JSON - the single reference an HMI's firmware is written from.

## Subscribing - `node.Subscribe`

```
node.Subscribe(anyValue := rLevelFromTank, nPeerNodeId := 10, sTopic := 'tank_level',
               nTopicId := 1, fDeadband := 0.5, tMaxSendInterval := T#2s);
```

`nPeerNodeId` owns it; `sTopic` and `nTopicId` must match what that node bound.

### The terms

**`fDeadband`** - how far the value must move to be worth sending. `0.0` means
every change. On a temperature, `0.5` keeps the noise off the network and still
tells you about anything real.

**`tMaxSendInterval`** - the longest you will go without hearing anything, even if
nothing changed. This is what proves the link is alive rather than the value
being flat.

Together: *"tell me when it moves this much, and at least this often."*

**`bDeliverEveryChange`** - `FALSE` (the default, Live): best effort, newest wins, the
right thing for a level or a flow. `TRUE` for a setpoint, a setting or
configuration: every change arrives, and one a lost frame took is sent again,
as the current value, within a rotation or two - a setting is never left blank
or old. `fDeadband` does not apply. Costs about two bytes a rotation while
values move.

Each subscriber sets its own terms, and they may change while it runs: the
subscription is asked again. A SCADA can ask for every change while a
controller asks only for big ones, and the publisher serves both.

### Knowing whether to trust it

| output | |
| --- | --- |
| `eQuality` | `Good` / `Uncertain` / `Bad` / `Unknown` (`E_BeeBusQuality`) |
| `bValueEverReceived` | a value has arrived at least once - what a ladder rung uses, since it cannot compare an enumeration |
| `tValueAge` | since the last one; `T#0s` before the first |
| `bValueReceived` | one arrived since the last call |
| `nMissedUpdateCount` | running total of updates that went astray |

**This is the reason to use topics.** When the publisher stops, `anyValue`
holds its last reading - it does not go to zero, because zero would be a lie -
but `eQuality` decays through `Uncertain` to `Bad` and `tValueAge` climbs.

A stale Modbus register looks exactly like a healthy one. A stale topic does
not.

```
IF eLevelQuality = E_BeeBusQuality.Bad THEN
    bLevelAlarm := TRUE;
    (* use the last good value, or a default, but do not trust this one *)
END_IF;
```

**Subscribe every scan, unconditionally.** It is a standing intent: the
protocol holds it until the peer is on the network, and re-establishes it by
itself if the peer restarts. You do not need to watch for the peer or retry -
subscribing to a node that is not there yet is normal, and returns `Ok`.

## Publishing on demand - `node.Publish`

`Topic` publishes when a subscriber's terms say so. `Publish` publishes when
**you** say so, on a rising edge of `bExecute`. That is what an event wants: a
value that must go the moment something happened, not when it has drifted far
enough.

It is complete on its own - it binds `anyValue` and it sends it.

```
eReport := node.Publish(anyValue := rSoilTemp, sTopic := 'soil_temp', nTopicId := 1,
                        bExecute := bJustWoke);
```

### The two modes

**`E_BeeBusPublishMode.All`** (the default) - one frame to the whole ring.
Every node holding that topic takes it, subscribed or not. **One send however
many are listening**, which is the point: the bus is shared, so every node's
receiver already has the bytes whatever the frame is addressed to.

Nothing acknowledges a broadcast, so `bRequireAcknowledge` is refused with
`InvalidArgument` - and nothing counts one either, so a broadcast that goes
missing is not reported. The result is `Ok` at the edge.

**`E_BeeBusPublishMode.ToPeer`** - one named peer, `nPeerNodeId`, subscribed or not.
This is the only mode that can be `bRequireAcknowledge`, because only a named node can
answer for itself: `Queued` until it acknowledges, then `Ok`.

### Both on one topic

`Topic` and `Publish` on the same variable, `sTopic` and `nTopicId`, when a topic
should **also** go out on the subscribers' own terms. They are separate
pipelines and do not disturb each other: a subscription is a counted stream, so
a lost sample shows up as `nMissedUpdateCount`, while a broadcast takes no part in that
counting and is simply applied on arrival.

## Store and forward - `node.Buffer`

```
node.Buffer(sTopic := 'soil_temp', nOfflineBufferDepth := 8, nSamplesWaiting => nSoilHeld);
```

Turns buffering on for one topic this node owns (bound by `Topic` or
`Publish`). `nOfflineBufferDepth` is how many samples to hold; `0` turns it off again. It may
change while it runs. A name that is not one of this node's topics returns
`NotMapped`.

While there is nowhere to send - the node is off the network, or every
subscriber is away - samples are **held** rather than lost. When the listener
comes back it gets the **history**, oldest first, each carrying the age it was
taken at.

That is what makes it different from simply publishing again: the shape of what
happened while the link was down survives.

It works both ways round:

- **the publisher goes off the network** - it keeps recording, and sends the lot
  when it rejoins
- **the subscriber goes away** - the publisher holds the samples rather than
  spending them on a node that is not there, and delivers them on its return

If more samples arrive than `nOfflineBufferDepth` holds, the oldest are overwritten and the
loss is reported to the subscriber as a gap, so nobody is quietly misled about
what they have. `nSamplesWaiting` is how many are waiting.

**A buffered topic goes out from its ring, change by change** - one path,
network up or down, so a live value never jumps ahead of the history behind it.
So a subscriber's `tMaxSendInterval` does not apply to it, and a subscriber that arrives
while the value stands still gets nothing until it next changes: `eQuality`
stays `Unknown` meanwhile.

**Buffer the topics where the history matters** - a meter reading, a fault code,
an event count. A temperature sampled every second rarely needs it, and a
setting a panel must see at once should not be buffered.

For a whole `STRUCT`, `node.Serve` has the same ring for every member
(`nOfflineBufferDepth`).

## Settings a peer may write - `bPeersMayWrite`

The owner keeps its settings, and a panel or a SCADA node changes them: publish
the settings `STRUCT` with `bPeersMayWrite := TRUE`. A peer's write never lands
behind the program's back. The node queues it and `PublishStruct` takes it in
its own call, one write per member a scan, oldest first, so a command written 1
and then 0 between two scans is seen as both (a member written more than four
times between two scans keeps the newest four; `nDroppedWriteCount` counts the rest).

```
node.PublishStruct(anyData := SET, nFirstTopicId := 600, bPeersMayWrite := TRUE, tPulseLength := T#500ms,
                   bWrittenByPeer => bSetWritten);
IF bSetWritten THEN
    IF SET.sp > 100.0 THEN SET.sp := spInUse; END_IF;   (* refused: put back *)
END_IF;
spInUse := SET.sp;
```

A refused write is put back in the same scan; the value every subscriber sees
never changes, so the writer sees its write bounce. A writer that asks for the
result (`node.Write` with `bAskOwnerDecision`, or a `Bind`) is told so directly: the
member is read back after the scan (plus `tAnswerDelay`), and a value put back is
answered `Changed` with the value kept. `tPulseLength` turns a `BOOL` member written
TRUE back to FALSE after that time: a momentary command, applied exactly once
however often the network had to send it. Keep settings and commands in their
own writable `STRUCT` and status in a read-only one.

## Writing one value - `node.Write`

```
eWrite := node.Write(anyValue := rNewSp, nPeerNodeId := 1, nTopicId := 600,
                     bRequireAcknowledge := TRUE, bExecute := bSend);
```

One value into a peer's writable topic, on a rising edge of `bExecute`.
`bRequireAcknowledge` retries until the owner acknowledges, and the owner applies it
once however often it was sent. `bAskOwnerDecision` asks the owner what it did with
it (and makes the write confirmed): the result is `Queued` until the decision,
then `Ok` with `eOwnerDecision` `Accepted`, `Changed` (it kept another value,
`fOwnerKeptValue`) or `Refused`; `bOwnerAccepted` and `bOwnerKeptOtherValue` say the same for a
ladder rung. No decision coming back ends it with `Timeout`. A read-only topic
is `Refused`; a value of another type than the owner's member is
`TypeMismatch`, or refused by the owner with `eOwnerDecision` `WrongType`.

## Commanding a peer

A topic is owned by one node and read by others, so a command runs the
ownership the other way round: **the commander owns the topic and the device
subscribes to it.** For a whole set of commands, the commander (an HMI) owns a
`STRUCT` with `PublishStruct` and the PLC takes it with `SubscribeStruct`;
`sFirstReceivedMember` says which command moved.

On the commander:

```
eCmd := node.Publish(anyValue := rDemand, sTopic := 'pump_speed_cmd', nTopicId := 20,
                     ePublishMode := E_BeeBusPublishMode.ToPeer, nPeerNodeId := 31,
                     bRequireAcknowledge := TRUE, bExecute := bSendCmd);
```

On the pump:

```
node.Subscribe(anyValue := rSpeedSetpoint, nPeerNodeId := 200, sTopic := 'pump_speed_cmd',
               nTopicId := 20, tMaxSendInterval := T#5s, eQuality => eCmdQuality);
```

`ToPeer` with `bRequireAcknowledge` means `Ok` is *the pump has it*, not *it was sent*.
For a command, that is the difference that matters. The pump also gets
`eQuality` on its setpoint for free - if the commander stops, the pump knows its
setpoint is stale rather than running on an old number forever.

## Strings

A `STRING` topic works like any other. It carries its own length, so a short
message costs short bytes:

```
node.Topic(anyValue := sFaultText, sTopic := 'fault_text', nTopicId := 9);
```

A subscriber binds its own `STRING` and gets the text. The protocol reads and
writes the `STRING` variable itself, with no copy of its own, so a text longer
than the subscriber's `STRING` is cut to fit: size it for the longest message.

---

Next: [06 - Diagnostics](06-diagnostics.md), or [08 - Patterns](08-patterns.md).
