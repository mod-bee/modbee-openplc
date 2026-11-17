# 02 - Getting started

Two nodes, one sending a value and the other receiving it. Every step says what
it does and why, because the why is what lets you change it afterwards.

## What you need

**Two OpenPLC Runtimes.** Two Docker containers on one machine is a real BeeBus
network in every way that matters, and needs no hardware at all. Start there.

Or **two boards** - ESP32 or similar - over RS485 or Wi-Fi. The only difference
is `eTransport` and an option structure.

You also need the library installed in the editor: **Libraries -> Install**, and
pick `modbee-beebus.stlib` (0.2.0).

## Step 1 - start a node

Make a project. In `main`, declare the node and call it:

```
PROGRAM main
VAR
    node : FB_BeeBusNode;
END_VAR

node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
END_PROGRAM
```

That is a complete BeeBus node. It finds any other node on the network, joins
the ring, and stays there.

**`nNodeId` is 1 to 254 and must be unique.** It is the only thing you must
decide. `E_BeeBusTransport.RuntimeUdp` is the default and uses the protocol's
own multicast group and port, which is what you want unless you are running two
separate networks on one wire.

**Call the node first**, and its methods after it. A method called above it
works from what the node left at the end of the previous scan: it costs a scan
and corrects itself.

Build it and download it to the first runtime.

## Step 2 - check it started

Read what the node says about itself, and ask it for its statistics:

```
VAR
    node     : FB_BeeBusNode;
    nMembers : BYTE;
END_VAR

node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
node.Statistics(nMembers => nMembers);
```

`nMembers` is how many nodes are in the ring, including this one. On its own it
reads **1**. When the second node joins it becomes **2**.

`node.bReady` is `TRUE` once the node started. If it is `FALSE`,
`node.eErrorId` says why as an `E_BeeBusResult` and `node.sLastError` says it in
the operating system's own words - *"Address already in use"* and the like.
`node.bConnected` is `TRUE` once it is in a ring with somebody.

## Step 3 - share a value

Give the node something to share. A **topic** - a named value:

```
VAR
    node   : FB_BeeBusNode;
    rLevel : REAL;
END_VAR

node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
node.Topic(anyValue := rLevel, sName := 'tank_level', nTopicId := 1);

(* something to watch *)
rLevel := rLevel + 0.1;
IF rLevel > 100.0 THEN rLevel := 0.0; END_IF;
```

Four things to notice:

**There is no send.** Once bound, the node publishes `rLevel` on its own. Move
the variable and it goes out. `Topic` returns `E_BeeBusResult.Ok` while the
topic is bound.

**`sName` is the identity.** Peers ask for `'tank_level'`. Up to 253 characters.

**`nTopicId` is stated once, here.** 1 to 32767, unique on this node. It is
what travels on the wire - the name is for you. Ids under 128 cost one byte
instead of two, so start at 1 and count up.

**`anyValue` is the variable itself**, and its declared type is the type on the
wire. Declare it `REAL` and subscribers get a `REAL`. `BOOL`, the integer types
(64-bit `LINT`, `ULINT`, `LWORD` included), `REAL`, `LREAL`, `LTIME` and
`STRING` all work. A type the wire cannot carry (`WSTRING`) returns
`E_BeeBusResult.InvalidArgument` rather than a surprise, and the node's
`sLastError` says which call and why.

Download it.

## Step 4 - receive it on the second node

New project, second runtime. **Different `nNodeId`:**

```
PROGRAM main
VAR
    node           : FB_BeeBusNode;
    rLevelFromTank : REAL;
END_VAR

node(nNodeId := 20, eTransport := E_BeeBusTransport.RuntimeUdp);
node.Subscribe(anyValue := rLevelFromTank, nPeer := 10, sName := 'tank_level',
               nTopicId := 1, fDeadband := 0.0, tPeriod := T#5s);
END_PROGRAM
```

Download it, and watch `rLevelFromTank` climb. `nMembers` reads **2** on both
nodes now.

### What the subscribe parameters mean

**`nPeer` is who owns the topic** - node 10. **`sName` and `nTopicId` must match
what that node bound.**

**`fDeadband`** is how much the value has to move before it is worth sending.
`0.0` means every change. `0.5` on a temperature means you get told when it
moves half a degree, and the small wobbles stay off the network.

**`tPeriod`** is the longest you will go without hearing anything, even if
nothing changed. It is what tells you the link is alive rather than the value
being flat.

The two together are the whole subscription: *"tell me when it moves this
much, and at least this often."*

## Step 5 - is the value any good?

This is where topics earn their place. Read the method's outputs:

```
VAR
    eLevelQuality : E_BeeBusQuality;
    tLevelAge     : TIME;
    bLevelGood    : BOOL;
END_VAR

node.Subscribe(anyValue := rLevelFromTank, nPeer := 10, sName := 'tank_level',
               nTopicId := 1, tPeriod := T#5s,
               eQuality => eLevelQuality, tAge => tLevelAge);
bLevelGood := eLevelQuality = E_BeeBusQuality.Good;
```

**`eQuality`** answers *"can I trust this number?"*

| | |
| --- | --- |
| `E_BeeBusQuality.Good` | arriving as agreed |
| `E_BeeBusQuality.Uncertain` | late - past the interval that was asked for |
| `E_BeeBusQuality.Bad` | long overdue, or the peer has gone |
| `E_BeeBusQuality.Unknown` | nothing has arrived yet |

**`tAge`** is how long since the last one, `T#0s` before the first; `bSeen`
tells that zero apart, and is the one a ladder rung uses.

Now stop the first runtime and watch. `rLevelFromTank` **stops at the last
value it had** - it does not go to zero, because zero would be a lie. But
`eQuality` goes `Uncertain` and then `Bad`, and `tAge` climbs.

That is the failure a polled register hides: the number looks perfectly healthy
and is quietly hours old. Start the runtime again and it recovers on its own.

**`nMissed`** counts updates that went astray - a running total, so a gap three
minutes ago is still visible.

## Step 6 - share a register too

Same node, beside the topic. This is the Modbus side:

```
VAR
    iLevel : INT;
END_VAR

iLevel := REAL_TO_INT(rLevel);
node.ModbusMap(anyData := iLevel, nAddress := 40);   (* HoldingRegister is the default *)
```

`iLevel` **is** holding register 40 now. Any peer reading address 40 gets what
it holds this instant. Nothing is copied and there is no request.

On the second node, read it:

```
VAR
    bRead   : BOOL;
    iRemote : INT;
    eRead   : E_BeeBusResult;
END_VAR

eRead := node.ModbusRead(anyData := iRemote, nPeer := 10, nAddress := 40,
                         bExecute := bRead);
```

Raise `bRead` and the read goes out. `eRead` is `E_BeeBusResult.Queued` while
it is outstanding, then `Ok` once the answer is in `iRemote` - and it stays `Ok`
until the next rising edge of `bRead`.

Two things that always apply to reads and writes:

**They start on an edge.** `bExecute` fires on its rising edge, and the inputs
are taken at that edge. Hold it `TRUE` and you get one read, not a stream.

**`anyData` takes the variable itself.** One value, an array or a whole
`STRUCT`, on the same parameter - `anyData := iLevel` or `anyData := aTrend`.
`eTable` is what says whether the addresses are bits or registers, so the
variable does not have to. An array must be declared with fixed bounds.

## What you have

A network with no master, where one node's value reaches another on its own,
carries its own freshness, and survives either end being switched off.

Both nodes here run everything on one task, which is the simplest thing that
works. When the ring grows, the node's program moves to a task of its own and
your logic stays where it is - [10 - Scan rate](10-scan-rate.md) has the
pattern and what it measures.

## Next

- [03 - The node block](03-the-node-block.md) - links, settings, and nodes that sleep
- [10 - Scan rate](10-scan-rate.md) - the node's own task, and why it matters
- [04 - Registers](04-registers.md) - ranges, writing, and failsafe
- [05 - Topics](05-topics.md) - buffering, publishing on demand, strings
- [08 - Patterns](08-patterns.md) - how these fit together in a real plant
