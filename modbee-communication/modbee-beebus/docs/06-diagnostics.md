# 06 - Diagnostics

Two methods answer *"is this network healthy?"*, the node's own outputs say
what is wrong with it, and one enumeration answers *"why did that fail?"*

## The node and its segment - `node.Statistics`

```
node.Statistics(nNodesInRing => nNodesInRing, tTokenRotationTime => tTokenRotationTime,
                nChecksumErrorCount => nChecksumErrorCount, nNoiseByteCount => nNoiseByteCount);
```

Nothing on it is a setting. Every number is measured. It returns `Ok` once the
node has started, `NotInitialised` before.

| output | |
| --- | --- |
| `nNodeIdInUse` | the address this node holds |
| `nNodesInRing` | how many nodes are in the ring, including this one |
| `tTokenRotationTime` | how long a turn takes to come round, measured. `T#0s` until it has |
| `nPendingOperations` | operations queued and not yet finished |
| `nChecksumErrorCount` | frames that arrived corrupt |
| `nNoiseByteCount` | bytes discarded while hunting for a frame start |

Whether this node is in a ring is `node.bConnected`, on the block itself.

### What to watch, and what it means

**`nNodesInRing`** is the first number to look at. It should equal the number of
nodes you expect. Less means somebody is not joining; the count on each node
tells you who can see whom.

**`nChecksumErrorCount` and `nNoiseByteCount` are the two that judge a link.** On a quiet bus
they should sit still. Climbing steadily means a physical problem, not a
software one:

- **on RS485** - a missing terminating resistor, a floating bus with no bias, a
  baud rate mismatch, or a run that is too long
- **on UDP** - a saturated network, or a switch dropping multicast

A handful at start-up is normal. A number that keeps rising is a fault to go
and look at with a meter.

**`tTokenRotationTime`** is how fast the network actually is. It grows as nodes are
added and as a link slows. Watch it when you add a node: if it jumps far more
than one node's worth, that node's link is the slow one.

**`nPendingOperations`** sitting high means work is being queued faster than the ring
can carry it. Usually a program raising a request every scan instead of on an
edge.

**`bDebugToConsole`** on the node prints the protocol's own running commentary to the
runtime console. Useful when commissioning, noisy in production; it may be
switched while running. On a ModBee Node the commentary is left out of the
firmware to save flash, so it prints nothing there unless the firmware is built
with `BEEBUS_ENABLE_DEBUG` defined; on a Runtime it always works.

## One peer - `node.PeerStatus`

```
node.PeerStatus(nPeerNodeId := 31, bInRing => bPumpAlive, bEverHeard => bPumpSeen,
                tSinceLastHeard => tPumpSilent, tTokenHopTime => tPumpHop, tTokenHopTimeout => tPumpHopTimeout);
```

| output | |
| --- | --- |
| `bInRing` | that peer is in the ring and being heard from |
| `bEverHeard` | it has been heard from at least once since the program started: `bEverHeard` FALSE is a peer never fitted, or given the wrong id; `bEverHeard` with `bInRing` FALSE is one that has gone |
| `tSinceLastHeard` | how long since it last said anything |
| `tTokenHopTime` | how quick it is to take its turn, measured |
| `tTokenHopTimeout` | how long it is allowed before its turn is presumed lost |

It returns `Ok`, `NotInitialised` before the node started, or `InvalidArgument`
for `nPeerNodeId` 0 or 255.

**`bInRing` is the one to gate logic on.** It answers exactly the same question
as the check every read and write makes, so if `bInRing` is `TRUE` an operation
to that peer will not be refused for want of the peer:

```
IF bPumpAlive THEN
    eRead := node.ModbusRead(anyData := rFlow, nPeerNodeId := 31, nStartAddress := 10, bExecute := bFire);
ELSE
    bPumpCommsAlarm := TRUE;
END_IF;
```

**`tTokenHopTime` against `tTokenHopTimeout`** is how much headroom a peer has. A hop creeping
toward its timeout is a link degrading before it fails - a radio path getting
worse, a cable starting to fail. It is the earliest warning the network gives
you.

`tSinceLastHeard` is the plain number for an alarm: *"node 31 has said nothing for
thirty seconds."*

## The node's own outputs

`node.bError`, `node.eErrorId` and `node.sLastError` say what is wrong, most
fundamental first:

1. **the link** - it did not open (`NotInitialised`, tried again; `tRetryTimeLeft`
   counts down), or a setting is wrong (`InvalidArgument`);
2. **another device on this id** (`DuplicateNodeId`);
3. **a member of an option structure for the other target** (`InvalidArgument`,
   *"stSerialConfig.sDevice is the Runtime's"*) - the node runs on;
4. **the last method call that failed**, by method and record: *"PublishStruct
   STS: name too long (256 > 255): ..."*, *"Write spVal: Refused"*. It stays
   until that same call succeeds.

A call that is merely waiting is not a failure: `Queued`, `NotInitialised`, and
a peer out of the ring while this node is out of it too.

## Every result

Every method returns an `E_BeeBusResult`. It mirrors the protocol's own result
codes member for member, so a value you see is the one the protocol
documentation describes.

| | |
| --- | --- |
| `Ok` | finished, and it worked; for a standing method, its record is valid |
| `Queued` | a request accepted; the outcome arrives on a later turn |
| `NotInitialised` | the node has not started, or its link has not opened yet (it is retried; see `sLastError`) |
| `InvalidArgument` | something the method cannot use - see below |
| `UnknownNode` | that peer is not on the network, or this node is not |
| `DuplicateNodeId` | **this** node stood down; another has its id |
| `NotMapped` | nothing is bound at that address or name |
| `Duplicate` | the identical request is already in flight (taken as accepted: a method never returns it) |
| `QueueFull` | too much outstanding at once, or 256 records on the node |
| `Timeout` | a confirmed operation was never acknowledged, or no decision came back |
| `NodeLost` | the peer left before it was delivered |
| `Superseded` | a newer write to the same place replaced it before it went out |
| `Cancelled` | discarded, usually because the node disconnected |
| `Refused` | the peer rejected it - a read-only topic |
| `TypeMismatch` | a value of another type than the binding at the other end, or a register a member cannot hold |
| `NotSubscribed` | no subscription to act on |
| `BufferFull` | a store-and-forward ring overwrote its oldest sample |
| `WrongTask` | the method was called from another task than the node's; it did nothing |

### The ones you will actually meet

**`UnknownNode`** - nine times out of ten the peer is not powered, not on the
network, or has a different `nNodeId` from the one you gave. A request is
refused with it at once, never queued for later.

**`InvalidArgument`** - something the method cannot make sense of, and
`sLastError` says what. Usually a `WSTRING`, a name longer than 255 characters,
a `REAL` in a coil table, `bRequireAcknowledge` on a broadcast, or a record's topic or
address changed after it bound.

**`DuplicateNodeId`** - two devices on one id. Without this code the node looks
exactly like one that has not finished starting. It clears itself when the
other device goes.

## A health rung worth copying

```
node(nNodeId := 10);
node.Statistics(nNodesInRing => nNodesInRing, nChecksumErrorCount => nChecksumErrorCount);

bHealthy := node.bLinkOpen AND node.bConnected
            AND (nNodesInRing >= 3)              (* however many you expect *)
            AND NOT node.bError;
bCommsFault := NOT bHealthy;
```

Put `nChecksumErrorCount` on a trend and you will see a link going bad weeks before it
strands you.

---

Next: [07 - Block reference](07-block-reference.md) for every parameter, or
[09 - Troubleshooting](09-troubleshooting.md) if something is wrong now.
