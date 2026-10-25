# 05 - Topics

A topic is a **named, typed value** that a node owns. Peers subscribe to it and
the value arrives on its own — nothing polls.

Six blocks:

| | |
| --- | --- |
| `BEEBUS_TP_TOPIC` | own a topic; the node publishes it by itself |
| `BEEBUS_TP_SUBSCRIBE` | bind a peer's topic and ask for a stream of it |
| `BEEBUS_TP_STRUCT` | own a whole `STRUCT`, one topic per member |
| `BEEBUS_TP_STRUCT_SUBSCRIBE` | a peer's whole `STRUCT`, into one of yours |
| `BEEBUS_TP_PUBLISH` | own a topic and send it when **you** say so |
| `BEEBUS_TP_BUFFER` | hold samples while there is nowhere to send them |

A panel or SCADA that changes settings in a PLC does not need to put these
together: `BEEBUS_TP_SERVE` and `BEEBUS_TP_BIND` do it in one block each side
([11 - Settings both ways](11-bidirectional-binding.md)). The blocks here are
what they are built from, and are there for anything else.

## Owning one — `BEEBUS_TP_TOPIC`

```
tpLevel( NODE := node, NAME := 'tank_level', TOPIC_ID := 1,
         VALUE := rLevel );
```

That is the whole thing. There is no request pin: once bound, the node
publishes `rLevel` to every subscriber, on the deadband and interval each of
them asked for. Move the variable and it goes out.

**`NAME`** is the identity — up to 253 characters (`NAME` is a `STRING(254)`,
the longest the editor declares, and a full one may have been cut to fit).
Longer is refused rather than truncated, because two long names cut alike
become one topic across the whole network, silently. A node with an older
BeeBus (before names grew past 31 characters) refuses a longer name it is sent
and does not learn that topic: keep names to 31 characters while such a node is
on the network.

**`TOPIC_ID`** is 1 to 32767 and unique on this node. It is what travels on the
wire; the name is for people. Under 128 costs one byte instead of two.

**`VALUE`** is the variable, and its declared type is the type on the wire:
`BOOL`, `SINT`, `USINT`, `BYTE`, `INT`, `UINT`, `WORD`, `DINT`, `UDINT`,
`DWORD`, `LINT`, `ULINT`, `LWORD`, `REAL`, `LREAL`, `LTIME` or `STRING`.
`LTIME` travels as an `LINT` of nanoseconds, which is what IEC 61131-3 defines it
to be. `WSTRING` is refused with `BEEBUS_INVALID_ARGUMENT`. (`BEEBUS_TP_STRUCT`
also carries `TIME`, `TOD`, `DT` and `DATE` members; see below.)

**Peers may read this topic; they may not write it.** To take a command from
elsewhere, subscribe to a topic that node owns — see *Commanding* below.

**One instance is one topic.** `NAME`, `TOPIC_ID` and `VALUE` are taken on the
first scan the node is there, and changing them later — or calling the same
instance again with others — does nothing. A second topic is a second instance.
For many values at once, put them in a `STRUCT` and use `BEEBUS_TP_STRUCT`.

## A whole STRUCT — `BEEBUS_TP_STRUCT`

Everything an HMI shows, in one `STRUCT`, published by one block:

```
TYPE PLANT_STS : STRUCT
  systemMode  : INT;          (* topic 100 *)
  levelPct    : REAL;         (* topic 101 *)
  pumpRunning : BOOL;         (* topic 102 *)
  banner      : STRING(64);   (* topic 103 *)
  hmi         : PANEL;        (* hmi.page 104, hmi.alarmCount 105 *)
  spare       : ARRAY[1..2] OF REAL;   (* spare[1] 106, spare[2] 107 *)
END_STRUCT END_TYPE

sts( NODE := node, VALUE := STS, TOPIC_ID := 100 );
```

- **Each member is a topic.** Its name is the member's name as declared; a
  nested `STRUCT` adds a dot (`hmi.page`), an array element its position in
  brackets counting from 1 (`spare[1]`). Names are 255 characters at most,
  `PREFIX` included: a longer one refuses the whole `STRUCT`, and `LAST_ERROR`
  names it. `PREFIX`
  goes in front of every name when two `STRUCT`s on one node share member
  names.
- **`VALUE` may be an `ARRAY`** of `STRUCT`s or of simple values: one block for
  a list of alike things. Each element is named from its position on, after
  `PREFIX` — `PREFIX := 'alarms'` gives `alarms[1].active`,
  `alarms[3].set.prot.delay` — without the variable's own name, so the
  subscriber's `ARRAY` may be called anything. `WRITABLE` works as for a
  `STRUCT`, and the whole `ARRAY` is one writable `STRUCT` (a node holds 8).
- **Its id is `TOPIC_ID` plus its position**, counting from 0 in declaration
  order, every array element and nested member one position. Add members at
  the **end**: one added in the middle moves every id after it.
- **Types:** as for `BEEBUS_TP_TOPIC`, plus `TIME` and `TOD` as `DINT`
  milliseconds, `DT` and `DATE` as `UDINT` seconds since 1970, and an
  enumeration as its integer. A `WSTRING` member refuses the `STRUCT`.
- **Members travel one by one.** Five members changed on one scan go as five
  values, a few to each turn of the token, so the far end may see them over two
  or three scans. Don't use one member as a "the rest has arrived" flag.

The other side is one block too, with a `STRUCT` of the same type:

```
sts( NODE := node, VALUE := STS, PEER := 1, TOPIC_ID := 100 );   (* BEEBUS_TP_STRUCT_SUBSCRIBE *)
```

It subscribes every member, and reports for the lot: `QUALITY` (the worst
member), `SEEN` (every member has arrived), `NEW_VALUE`, `NEW_COUNT`,
`NEW_NAME` and `NEW_INDEX` (what arrived this scan), and `MISSED`.

**Use the same TYPE on both sides.** Topics travel by id, and the ids come from
the member order. Keep the `STRUCT` in one place both projects take it from.

**The table is generated, not typed.** A table generator reads the
`.st` file and prints every member's name, topic id, type and register address
as Markdown and as JSON — the single reference an HMI's firmware is written
from.


## Subscribing — `BEEBUS_TP_SUBSCRIBE`

```
subLevel( NODE := node, PEER := 10,
          NAME := 'tank_level', TOPIC_ID := 1,
          DEADBAND := 0.5, PERIOD := T#2s,
          VALUE := rLevelFromTank );
```

`PEER` owns it; `NAME` and `TOPIC_ID` must match what that node bound.

### The terms

**`DEADBAND`** — how far the value must move to be worth sending. `0.0` means
every change. On a temperature, `0.5` keeps the noise off the network and still
tells you about anything real.

**`PERIOD`** — the longest you will go without hearing anything, even
if nothing changed. This is what proves the link is alive rather than the value
being flat.

Together: *"tell me when it moves this much, and at least this often."*

**`RELIABLE`** — `FALSE` (the default, LIVE): best effort, newest wins, the
right thing for a level or a flow updated every scan. `TRUE` for a setpoint, a
setting or configuration: every change arrives, and one a lost frame took is
sent again, as the current value, within a rotation or two — a setting is never
left blank or old. `DEADBAND` does not apply. Costs about two bytes a rotation
while values move.

Each subscriber sets its own terms. A SCADA can ask for every change while a
controller asks only for big ones, and the publisher serves both.

### Knowing whether to trust it

| output | |
| --- | --- |
| `QUALITY` | `BEEBUS_TP_GOOD` / `BEEBUS_TP_UNCERTAIN` / `BEEBUS_TP_BAD` / `BEEBUS_TP_UNKNOWN` |
| `AGE` | milliseconds since the last one, `-1` if none ever arrived |
| `NEW_VALUE` | one scan, when one arrived |
| `MISSED` | running total of updates that went astray |

**This is the reason to use topics.** When the publisher stops, `VALUE` holds
its last reading — it does not go to zero, because zero would be a lie — but
`QUALITY` decays through `BEEBUS_TP_UNCERTAIN` to `BEEBUS_TP_BAD` and `AGE` climbs.

A stale Modbus register looks exactly like a healthy one. A stale topic does
not.

```
IF subLevel.QUALITY = BEEBUS_TP_BAD THEN
    bLevelAlarm := TRUE;
    (* use the last good value, or a default, but do not trust this one *)
END_IF;
```

**`MISSED` is a running total**, not a per-scan count, so a gap three minutes
ago is still visible to somebody watching.

**Subscribe once, at the top of the program, unconditionally.** It is a
standing intent: the protocol holds it until the peer is on the network, and
re-establishes it by itself if the peer restarts. You do not need to watch for
the peer or retry — subscribing to a node that is not there yet is normal and
returns `BEEBUS_QUEUED`.

## Publishing on demand — `BEEBUS_TP_PUBLISH`

`BEEBUS_TP_TOPIC` publishes when a subscriber's terms say so. `BEEBUS_TP_PUBLISH` publishes
when **you** say so, on a rising edge of `REQ`. That is what an event wants: a
value that must go the moment something happened, not when it has drifted far
enough.

The block is complete on its own — it binds `VALUE` and it sends it.

```
report( REQ := bJustWoke, NODE := node,
        NAME := 'soil_temp', TOPIC_ID := 1,
        MODE := BEEBUS_TP_PUBLISH_ALL, VALUE := rSoilTemp );
```

### The two modes

`MODE` is named for the protocol call it makes.

**`BEEBUS_TP_PUBLISH_ALL`** — one frame to the whole ring. Every node holding that
topic takes it, subscribed or not. **One send however many are listening**,
which is the point: the bus is shared, so every node's receiver already has the
bytes whatever the frame is addressed to. A copy per listener would cost a copy
and buy no delivery.

Nothing acknowledges a broadcast, so `CONFIRMED` is refused with
`BEEBUS_INVALID_ARGUMENT` — and nothing counts one either, so a broadcast that
goes missing is not reported.

**`BEEBUS_TP_PUBLISH_TO`** — one named peer, subscribed or not. This is the only mode
that can be `CONFIRMED`, because only a named node can answer for itself.

### Both blocks on one topic

You may put `BEEBUS_TP_TOPIC` beside `BEEBUS_TP_PUBLISH` with the same `NAME` and `TOPIC_ID`,
when a topic should **also** go out on the subscribers' own terms.

They are separate pipelines and do not disturb each other: a subscription is a
counted stream, so a lost sample shows up as `MISSED`, while a broadcast takes
no part in that counting and is simply applied on arrival.

## Store and forward — `BEEBUS_TP_BUFFER`

```
buffer( NODE := node, NAME := 'soil_temp', DEPTH := 8 );
```

Turns buffering on for one topic this node owns. `DEPTH` is how many samples to
hold; `0` turns it off again.

While there is nowhere to send — the node is off the network, or every
subscriber is away — samples are **held** rather than lost. When the listener
comes back it gets the **history**, oldest first, each carrying the age it was
taken at.

That is what makes it different from simply publishing again: the shape of what
happened while the link was down survives.

It works both ways round:

- **the publisher goes off the network** — it keeps recording, and sends the lot
  when it rejoins
- **the subscriber goes away** — the publisher holds the samples rather than
  spending them on a node that is not there, and delivers them on its return

If more samples arrive than `DEPTH` holds, the oldest are overwritten and the
loss is reported to the subscriber as a gap, so nobody is quietly misled about
what they have.

`HELD` is how many are waiting.

**Buffer the topics where the history matters** — a meter reading, a fault code,
an event count. A temperature that is sampled every second rarely needs it: the
current value is what you want, and the next one is along shortly.

## Settings a peer may write — `WRITABLE`

The owner keeps its settings, and a panel HMI or a SCADA node changes them: bind
the settings `STRUCT` with `WRITABLE := TRUE`. A peer's write never lands behind
the program's back. The node queues it and `BEEBUS_TP_STRUCT` takes it in its
own scan, one write per member a scan, oldest first, so a command written 1 and
then 0 between two scans is seen as both (a member written more than four
times between two scans keeps the newest four; `LOST` counts the rest).

```
setTopics( NODE := node, VALUE := SET, TOPIC_ID := 600, WRITABLE := TRUE, PULSE := T#500ms );
IF setTopics.WRITTEN THEN
    IF SET.sp > 100.0 THEN SET.sp := spInUse; END_IF;   (* refused: put back *)
END_IF;
spInUse := SET.sp;
```

A refused write is put back in the same scan; the value every subscriber sees
never changes, so the writer sees its write bounce. A writer that asks for the
result (`BEEBUS_TP_WRITE` `WANT_RESULT`, or a bind) is told so directly: the
member is read back after the scan (plus `SETTLE`), and a value put back is
answered `CHANGED` with the value kept. `PULSE` turns a `BOOL` member written
TRUE back to FALSE after that time: a momentary command, applied exactly once
however often the network had to send it. Keep
settings and commands in their own `WRITABLE` STRUCT and status in a read-only
one. A peer writes with `BEEBUS_TP_WRITE` (or `writeTopic` in C++).

## Commanding a peer

A topic is owned by one node and read by others, so a command runs the
ownership the other way round: **the commander owns the topic and the device
subscribes to it.** For a whole set of commands, the commander (an HMI) owns a
`STRUCT` with `BEEBUS_TP_STRUCT` and the PLC takes it with
`BEEBUS_TP_STRUCT_SUBSCRIBE`; `NEW_NAME` says which command moved.

On the commander:

```
cmdSpeed( REQ := bSendCmd, NODE := node,
          NAME := 'pump_speed_cmd', TOPIC_ID := 20,
          MODE := BEEBUS_TP_PUBLISH_TO, PEER := 31, CONFIRMED := TRUE,
          VALUE := rDemand );
```

On the pump:

```
subCmd( NODE := node, PEER := 200,
        NAME := 'pump_speed_cmd', TOPIC_ID := 20,
        DEADBAND := 0.0, PERIOD := T#5s,
        VALUE := rSpeedSetpoint );
```

`CONFIRMED := TRUE` and `BEEBUS_TP_PUBLISH_TO` together mean `DONE` is *the pump has
it*, not *it was sent*. For a command, that is the difference that matters.

The pump also gets `QUALITY` on its setpoint for free — if the commander stops,
the pump knows its setpoint is stale rather than running on an old number
forever.

## Strings

A `STRING` topic works like any other. It carries its own length, so a short
message costs short bytes:

```
tpFault( NODE := node, NAME := 'fault_text', TOPIC_ID := 9,
         VALUE := sFaultText );
```

A subscriber binds its own `STRING` and gets the text. The protocol reads and
writes the `STRING` variable itself, with no copy of its own, so a text longer
than the subscriber's `STRING` is cut to fit: size it for the longest message.

---

Next: [06 - Diagnostics](06-diagnostics.md), or [08 - Patterns](08-patterns.md).
