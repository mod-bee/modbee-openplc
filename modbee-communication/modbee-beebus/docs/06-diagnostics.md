# 06 - Diagnostics

Two blocks answer *"is this network healthy?"*, and one enumeration answers
*"why did that fail?"*

## The node and its segment — `BEEBUS_NODE_STATUS`

```
status( NODE := node );
```

Nothing on it is a setting. Every number is measured.

| output | |
| --- | --- |
| `CONNECTED` | this node is in a ring |
| `NODE_ID` | its own address |
| `MEMBERS` | how many nodes are in the ring, including this one |
| `ROTATION` | how long a turn takes to come round, measured (`TIME`). `T#0s` until it has |
| `PENDING_OPS` | operations queued and not yet finished |
| `CRC_ERRORS` | frames that arrived corrupt |
| `NOISE_BYTES` | bytes discarded while hunting for a frame start |

### What to watch, and what it means

**`MEMBERS`** is the first number to look at. It should equal the number of
nodes you expect. Less means somebody is not joining; the count on each node
tells you who can see whom.

**`CRC_ERRORS` and `NOISE_BYTES` are the two that judge a link.** On a quiet bus
they should sit still. Climbing steadily means a physical problem, not a
software one:

- **on RS485** — a missing terminating resistor, a floating bus with no bias, a
  baud rate mismatch, or a run that is too long
- **on UDP** — a saturated network, or a switch dropping multicast

A handful at start-up is normal. A number that keeps rising is a fault to go
and look at with a meter.

**`ROTATION`** is how fast the network actually is. It grows as nodes are
added and as a link slows. Watch it when you add a node: if it jumps far more
than one node's worth, that node's link is the slow one.

**`PENDING_OPS`** sitting high means work is being queued faster than the ring
can carry it. Usually a program firing reads every scan instead of on an edge.

**`DEBUG_ENABLE`** prints the protocol's own running commentary to the runtime
console. Useful when commissioning, noisy in production. It is read once at
start-up, so set it before you download rather than toggling it live. On a
ModBee Node the commentary is left out of the firmware to save flash, so
`DEBUG_ENABLE` prints nothing there unless the firmware is built with
`BEEBUS_ENABLE_DEBUG` defined; on a Runtime it always works.

## One peer — `BEEBUS_NODE_PEER_STATUS`

```
peerPump( NODE := node, PEER := 31 );
```

| output | |
| --- | --- |
| `ALIVE` | that peer is in the ring and being heard from |
| `SEEN` | it has been heard from at least once since the program started: `SEEN` FALSE is a peer never fitted, or given the wrong id; `SEEN` with `ALIVE` FALSE is one that has gone |
| `SILENT` | how long since it last said anything (`TIME`) |
| `HOP` | how quick it is to take its turn, measured |
| `HOP_TIMEOUT` | how long it is allowed before its turn is presumed lost |

**`ALIVE` is the one to gate logic on.** It answers exactly the same question as
the check every read and write makes, so if `ALIVE` is `TRUE` an operation to
that peer will not be refused for want of the peer:

```
IF peerPump.ALIVE THEN
    readFlow( REQ := bFire, NODE := node, PEER := 31, ... );
ELSE
    bPumpCommsAlarm := TRUE;
END_IF;
```

**`HOP` against `HOP_TIMEOUT`** is how much headroom a peer has. A hop
creeping toward its timeout is a link degrading before it fails — a radio path
getting worse, a cable starting to fail. It is the earliest warning the network
gives you.

`SILENT` is the plain number for an alarm: *"node 31 has said nothing for
thirty seconds."*

## Every status code

`STATUS` on every block is a `BEEBUS_RESULT`. It mirrors the protocol's own
result codes member for member, so a value you see on a pin is the same one the
protocol documentation describes.

| | |
| --- | --- |
| `BEEBUS_OK` | finished, and it worked |
| `BEEBUS_QUEUED` | accepted; the result arrives on a later turn |
| `BEEBUS_NOT_INITIALISED` | the node block has not run, or its link has not opened yet (it is retried; see `LAST_ERROR`) |
| `BEEBUS_INVALID_ARGUMENT` | a pin the block cannot use — see below |
| `BEEBUS_UNKNOWN_NODE` | that peer is not on the network |
| `BEEBUS_DUPLICATE_NODE_ID` | **this** node stood down; another has its ID |
| `BEEBUS_NOT_MAPPED` | nothing is bound at that address or topic |
| `BEEBUS_DUPLICATE` | the identical request is already in flight |
| `BEEBUS_QUEUE_FULL` | too much outstanding at once |
| `BEEBUS_TIMEOUT` | a confirmed operation was never acknowledged |
| `BEEBUS_NODE_LOST` | the peer left before it was delivered |
| `BEEBUS_SUPERSEDED` | a newer write to the same place replaced it before it went out |
| `BEEBUS_CANCELLED` | discarded, usually because the node disconnected |
| `BEEBUS_REFUSED` | the peer rejected it |
| `BEEBUS_TYPE_MISMATCH` | the topic's type differs from the binding at the other end |
| `BEEBUS_NOT_SUBSCRIBED` | no subscription to act on |
| `BEEBUS_BUFFER_FULL` | a store-and-forward ring overwrote its oldest sample |

### The three you will actually meet

**`BEEBUS_UNKNOWN_NODE`** — nine times out of ten the peer is not powered, not
on the network, or has a different `NODE_ID` from the one you wired. It is also
what every block reports on the first scan if it was called above the node
block.

**`BEEBUS_INVALID_ARGUMENT`** — a pin the block cannot make sense of. Usually a
`WSTRING` on a `VALUE` pin, a name longer than 255 characters, bits sent to a
register table, or `CONFIRMED := TRUE` on `BEEBUS_TP_PUBLISH_ALL`.

**`BEEBUS_DUPLICATE_NODE_ID`** — two devices on one ID. Without this code the
node looks exactly like one that has not finished starting. It clears itself
when the other device goes.

### The ones that are not faults

`BEEBUS_QUEUED` means accepted and on its way. `BEEBUS_SUPERSEDED` means you
wrote the same address twice before the first went out and the newer value won —
reported so it does not vanish silently. `BEEBUS_DUPLICATE` means the same
request is already in flight and will be answered by the same completion.

## A health block worth copying

One rung that says whether this node is happy:

```
VAR
    node    : BEEBUS_NODE;
    status  : BEEBUS_NODE_STATUS;
    bHealthy : BOOL;
    bCommsFault : BOOL;
END_VAR

node  ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
status( NODE := node );

bHealthy := node.READY
            AND status.CONNECTED
            AND (status.MEMBERS >= 3)      (* however many you expect *)
            AND NOT node.ERROR;

bCommsFault := NOT bHealthy;
```

Add `status.CRC_ERRORS` to a trend and you will see a link going bad weeks
before it strands you.

---

Next: [07 - Block reference](07-block-reference.md) for the pin lists, or
[09 - Troubleshooting](09-troubleshooting.md) if something is wrong now.
