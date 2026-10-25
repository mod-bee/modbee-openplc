# 02 - Getting started

Two nodes, one sending a value and the other receiving it. Every step says what
it does and why, because the why is what lets you change it afterwards.

## What you need

**Two OpenPLC Runtimes.** Two Docker containers on one machine is a real BeeBus
network in every way that matters, and needs no hardware at all. Start there.

Or **two boards** — ESP32 or similar — over RS485 or WiFi. The only difference
is which node block you use.

You also need the library installed in the editor: **Libraries → Install**, and
pick `modbee-beebus.stlib`.

## Step 1 — start a node

Make a project. In `main`, declare a node block and call it:

```
PROGRAM main
VAR
    node : BEEBUS_NODE;
END_VAR

node( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );

END_PROGRAM
```

That is a complete BeeBus node. It will find any other node on the network,
join the ring, and stay there.

**`NODE_ID` is 1 to 254 and must be unique.** It is the only thing you must
decide. Nothing else on the block needs setting: `BEEBUS_NODE_RUNTIME_UDP` uses the
protocol's own multicast group and port, which is what you want unless you are
running two separate networks on one wire.

**Call the node block first**, before any block that uses it. A block placed
above it sees no node on that scan and reports `BEEBUS_UNKNOWN_NODE`. It
corrects itself on the next scan — it is not fatal — but there is no reason to
have it happen.

Build it and download it to the first runtime.

## Step 2 — check it started

Add a status block so you can see what is happening:

```
VAR
    node   : BEEBUS_NODE;
    status : BEEBUS_NODE_STATUS;
END_VAR

node  ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
status( NODE := node );
```

`status.MEMBERS` is how many nodes are in the ring, including this one. On its
own it will read **1**. When the second node joins it becomes **2**.

`node.READY` is `TRUE` once the node started. If it is `FALSE`, `node.STATUS`
says why in a code and `node.LAST_ERROR` says it in the operating system's own
words — *"Address already in use"* and the like.

## Step 3 — share a value

Give the node something to share. A **topic** — a named value:

```
VAR
    node      : BEEBUS_NODE;
    status    : BEEBUS_NODE_STATUS;
    tankLevel : BEEBUS_TP_TOPIC;
    rLevel    : REAL;
END_VAR

node  ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
status( NODE := node );

tankLevel( NODE := node, NAME := 'tank_level', TOPIC_ID := 1,
           VALUE := rLevel );

(* something to watch *)
rLevel := rLevel + 0.1;
IF rLevel > 100.0 THEN rLevel := 0.0; END_IF;
```

Three things to notice:

**There is no request pin.** Once bound, the node publishes `rLevel` on its
own. Move the variable and it goes out. You never call anything to send it.

**`NAME` is the identity.** Peers ask for `'tank_level'`. Up to 253 characters.

**`TOPIC_ID` is stated once, here.** 1 to 32767, unique on this node. It is what
travels on the wire — the name is for you. IDs under 128 cost one byte instead
of two, so start at 1 and count up.

**`VALUE` is the variable itself**, and its declared type is the type on the
wire. Declare it `REAL` and subscribers get a `REAL`. `BOOL`, the integer types
(64-bit `LINT`, `ULINT`, `LWORD` included), `REAL`, `LREAL`, `LTIME` and
`STRING` all work. A type the wire cannot carry (`WSTRING`) gets
`BEEBUS_INVALID_ARGUMENT` rather than a surprise.

Download it.

## Step 4 — receive it on the second node

New project, second runtime. **Different `NODE_ID`:**

```
PROGRAM main
VAR
    node   : BEEBUS_NODE;
    status : BEEBUS_NODE_STATUS;
    subLevel : BEEBUS_TP_SUBSCRIBE;
    rLevelFromTank : REAL;
END_VAR

node  ( NODE_ID := 20, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
status( NODE := node );

subLevel( NODE := node, PEER := 10,
          NAME := 'tank_level', TOPIC_ID := 1,
          DEADBAND := 0.0, PERIOD := T#5s,
          VALUE := rLevelFromTank );

END_PROGRAM
```

Download it, and watch `rLevelFromTank` climb.

`status.MEMBERS` reads **2** on both nodes now.

### What the subscribe pins mean

**`PEER` is who owns the topic** — node 10. **`NAME` and `TOPIC_ID` must match
what that node bound.**

**`DEADBAND`** is how much the value has to move before it is worth sending.
`0.0` means every change. `0.5` on a temperature means you get told when it
moves half a degree, and the small wobbles stay off the network.

**`PERIOD`** is the longest you will go without hearing anything, even
if nothing changed. It is what tells you the link is alive rather than the value
being flat. 5000 means "at least every five seconds".

The two together are the whole subscription: *"tell me when it moves this much,
and at least this often."*

## Step 5 — is the value any good?

This is where topics earn their place. Add to the second node:

```
VAR
    bLevelGood : BOOL;
    diLevelAge : DINT;
END_VAR

bLevelGood := (subLevel.QUALITY = BEEBUS_TP_GOOD);
diLevelAge := subLevel.AGE;
```

**`QUALITY`** answers *"can I trust this number?"*

| | |
| --- | --- |
| `BEEBUS_TP_GOOD` | arriving as agreed |
| `BEEBUS_TP_UNCERTAIN` | late — past the interval that was asked for |
| `BEEBUS_TP_BAD` | long overdue, or the peer has gone |
| `BEEBUS_TP_UNKNOWN` | nothing has arrived yet |

**`AGE`** is how long since the last one, or `-1` if none ever arrived.

Now stop the first runtime and watch. `rLevelFromTank` **stops at the last
value it had** — it does not go to zero, because zero would be a lie. But
`QUALITY` goes `BEEBUS_TP_UNCERTAIN` and then `BEEBUS_TP_BAD`, and `AGE` climbs.

That is the failure a polled register hides: the number looks perfectly healthy
and is quietly hours old. Start the runtime again and it recovers on its own.

**`MISSED`** counts updates that went astray — a running total, so a gap three
minutes ago is still visible.

## Step 6 — share a register too

Same node, alongside the topic. This is the Modbus side:

```
VAR
    mapLevel : BEEBUS_MB_MAP;
    iLevel   : INT;
END_VAR

iLevel := REAL_TO_INT(rLevel);

mapLevel( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
          VALUE := iLevel );
```

`iLevel` **is** holding register 40 now. Any peer reading address 40 gets what
it holds this instant. Nothing is copied and there is no request pin.

On the second node, read it:

```
VAR
    readLevel : BEEBUS_MB_READ;
    bRead     : BOOL;
    iRemote   : INT;
END_VAR

readLevel( REQ := bRead, NODE := node, PEER := 10,
           TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
           VALUE := iRemote );
```

Set `bRead` for one scan and the read goes out. `readLevel.BUSY` is `TRUE`
while it is outstanding; `readLevel.DONE` pulses for one scan when the answer
lands in `iRemote`.

Two things that always apply to reads and writes:

**They are edge-triggered.** `REQ` fires on the rising edge. Hold it `TRUE` and
you get one read, not a stream.

**`VALUE` takes the variable itself.** One value or a whole array, on the same
pin — `VALUE := iLevel` or `VALUE := aTrend`. `TABLE` is what says whether the
addresses are bits or registers, so the variable does not have to. An array
must be declared with fixed bounds.

## What you have

A network with no master, where one node's value reaches another on its own,
carries its own freshness, and survives either end being switched off.

Both nodes here run everything on one task, which is the simplest thing that
works. When the ring grows, the node moves to a task of its own and your logic
stays where it is — [10 - Scan rate](10-scan-rate.md) has the pattern and what
it measures.

## Next

- [03 - The node block](03-the-node-block.md) — transports, and nodes that sleep
- [10 - Scan rate](10-scan-rate.md) — the node's own task, and why it matters
- [04 - Registers](04-registers.md) — ranges, writing, and failsafe
- [05 - Topics](05-topics.md) — buffering, publishing on demand, strings
- [08 - Patterns](08-patterns.md) — how these fit together in a real plant
