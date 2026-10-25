# 09 - Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## The node will not start

**`READY` is `FALSE` and `ERROR` is `TRUE`.**

Read `LAST_ERROR` first. It says what failed, in the operating system's own
words, which say far more than a code can. While `STATUS` reads
`BEEBUS_NOT_INITIALISED` the node keeps trying — `RETRY_IN` counts down to the
next attempt — so fixing the cause is enough; there is nothing to restart.

| `LAST_ERROR` | |
| --- | --- |
| *"could not bind group port: Address already in use"* | another program has the port. Often a second copy of this one still running |
| *"could not open serial device: No such file or directory"* | the serial `DEVICE` path is wrong, or the adapter is not plugged in yet |
| *"could not open serial device: Permission denied"* | the runtime user cannot open the serial port |
| *"could not join multicast group: No such device"* | `IFACE` names an address this machine does not have, or the network is not up yet |
| *"no serial device named"* | `DEVICE` was left empty with `BEEBUS_NODE_RUNTIME_SERIAL` (a setting: not retried) |
| *"NODE_ID must be 1..254"* | a setting: not retried |
| *"out of memory for the node"*, *"... for the buffers and queues"*, *"... for the link"* | the board has no room left for the node: the rest of the program has the memory. Retried with the back-off |
| *"joining the network"* | WiFi is still associating. Not a fault — it clears on its own |
| *"Ethernet cable unplugged"* | no link on the PHY |
| *"no address from DHCP yet"* | cable is live, no lease yet. A fixed `IP` avoids the wait |
| *"no Ethernet controller found on SPI"* | no W5100/W5500 answered. Check the wiring and CS pin |
| *"set BEEBUS_ENABLE_ETHERNET to use Ethernet"* | Ethernet is opt-in. Add the flag in Build Settings, and install the Arduino Ethernet library |
| *"this board has no WiFi"* | the board has no `WiFi.h` |

`STATUS = BEEBUS_INVALID_ARGUMENT` with *"that link needs a board, not the
Runtime"* — or *"that link needs the Runtime, not a board"* — means `TRANSPORT`
names a link the target cannot carry. Give it a `BEEBUS_NODE_RUNTIME_*` value on
the Runtime, a `BEEBUS_NODE_ARDUINO_*` value on a board.

## The node started but never joins

**`READY` is `TRUE`, `CONNECTED` stays `FALSE`, `MEMBERS` stays 1.**

Work down this list.

**1. Check `STATUS` for `BEEBUS_DUPLICATE_NODE_ID`.** Two devices on one
`NODE_ID`. The second stands down entirely — no turn, no address, every read and
write refused. It looks exactly like a node that has not finished starting,
which is why the code exists. Find the other device and change one of them; the
node rejoins by itself.

This is the most common fault on a new network, and it is worth checking for a
device you had forgotten was still powered.

**2. Are they on the same network at all?** For UDP, both nodes need the same
`GROUP` and `UDP_PORT`. Leave both at their defaults on both nodes and they
will match. If you set them to separate two networks, check you set them the
same within each.

**3. `TTL`.** If the nodes are on different subnets, `TTL := 1` keeps every
frame local and they will never hear each other. Raise it, or put them on one
subnet.

**4. Multicast on the network.** Some switches drop multicast between ports by
default. Two containers on one host always work; two PCs through a managed
switch may need IGMP snooping configured or turned off.

**5. On serial:** both ends at the same `BAUD`, A to A and B to B, and a 120 Ω
terminating resistor at **each end** of the run. Check `NOISE_BYTES` on
`BEEBUS_NODE_STATUS` — climbing means the line is being read but not understood, which
is usually a baud mismatch or missing termination.

## Values are not arriving

**`QUALITY` stays `BEEBUS_TP_UNKNOWN` and `AGE` is `-1`** — nothing has ever
arrived.

**Check the peer is there first.** `BEEBUS_NODE_PEER_STATUS` with that `PEER`. If
`ALIVE` is `FALSE`, this is a ring problem, not a topic problem — go back to the
section above.

**Check `NAME` and `TOPIC_ID` match exactly.** Both must be what the owning node
bound. A mismatched ID is the usual cause and nothing reports it as an error,
because from the protocol's side you have simply subscribed to a topic that node
does not have.

**Check `STATUS` on the subscribe block.** `BEEBUS_INVALID_ARGUMENT` means the
block could not bind its own side — a `VALUE` of a type the wire cannot carry,
or a `NAME` over 253 characters. `BEEBUS_TP_SUBSCRIBE` binds locally as well as asking
the peer, so this is about your declaration, not the peer's.

**Both ends must declare the same type.** If the owner bound a `REAL` and you
bound an `INT`, values are **discarded on arrival** — your `QUALITY` stays
`BEEBUS_TP_UNKNOWN` and nothing on the subscribe block says why. The refusal goes back
to the publisher instead. So when a subscription looks correct and still
receives nothing, compare the two declarations before anything else.

## Values arrive, then stop

**`QUALITY` goes `BEEBUS_TP_UNCERTAIN` then `BEEBUS_TP_BAD`, `AGE` climbs.**

This is the mechanism working, not failing. Something upstream stopped.

`VALUE` deliberately holds its last reading rather than going to zero — zero
would be a lie. Use `QUALITY` to decide whether to trust it, and never raise a
process alarm from a value whose quality is not `BEEBUS_TP_GOOD`.

Check `BEEBUS_NODE_PEER_STATUS.ALIVE` for the publisher. If it is alive and values
still stopped, the topic binding on its side has gone — look at its `BOUND` pin.

## `MISSED` keeps climbing

Updates are being lost on the way. `MISSED` is a running total, so a steady
climb means it is happening now; a fixed number means it happened once.

- **`CRC_ERRORS` climbing too** — a physical problem. Termination, bias, cable
  length, or a noisy environment.
- **`NOISE_BYTES` climbing** — a floating bus or a baud mismatch.
- **Both quiet, `MISSED` still climbing** — the network is saturated. Check
  `PENDING_OPS` and `ROTATION`; a rotation that has grown a lot means the
  ring is busy. Widen the deadbands, lengthen the intervals, or move fast values
  to `BEEBUS_TP_PUBLISH_ALL` so one frame serves every listener.

## Everything works, but it is slow

Values do arrive and nothing reports an error — they just take longer than you
expected. Read `ROTATION` on `BEEBUS_NODE_STATUS` and divide by your node count.

- **About four times your task interval per node** — normal, and it is the task
  interval you are paying for, not the network. A PLC only looks at the bus once
  per scan, so every hop of the token costs a scan.
  [10 - Scan rate](10-scan-rate.md) explains it and gives the fix: the node
  block and its blocks in their own fast task, the rest of the program left
  alone.
- **Much larger than that** — the ring is busy rather than slow. Check
  `PENDING_OPS`, and see `MISSED` above.

## Reads and writes fail

**`ERROR` on `BEEBUS_MB_READ` or `BEEBUS_MB_WRITE`.** Read `STATUS`:

| | |
| --- | --- |
| `BEEBUS_UNKNOWN_NODE` | that peer is not on the network — or the block ran above the node block |
| `BEEBUS_DUPLICATE_NODE_ID` | **this** node stood down; another has its ID |
| `BEEBUS_NOT_MAPPED` | the peer has nothing bound at that address |
| `BEEBUS_TIMEOUT` | a confirmed write went unacknowledged after every retry |
| `BEEBUS_NODE_LOST` | the peer left before it was delivered |
| `BEEBUS_QUEUE_FULL` | too much outstanding — almost always `REQ` held high |
| `BEEBUS_INVALID_ARGUMENT` | wrong table for the type, or a count Modbus disallows |

**`BEEBUS_QUEUE_FULL` is nearly always `REQ`.** It is edge-triggered. Holding it
`TRUE` fires once, but a program that sets it every scan from a level rather
than an edge fills the queue. Use a step counter — see
[08 - Patterns](08-patterns.md).

**`BEEBUS_NOT_MAPPED` on a range** — the peer has *some* of the addresses but
not all. `BEEBUS_MB_MAP` on that node takes `COUNT` addresses from `ADDRESS`; check the
whole span you are asking for is inside it.

## `BUSY` never clears

`BUSY` stuck `TRUE` with no `DONE` and no `ERROR` means the block is waiting for
something that is not coming.

Check the peer is `ALIVE`. A confirmed write to a node that vanished mid-flight
reports `BEEBUS_NODE_LOST` once the ring notices, which can take a few turns —
give it `ROTATION` × a few before concluding it is stuck.

If it never clears at all, note the `PEER` and `ADDRESS` and raise it: a block
that waits forever is a defect, not a configuration.

## The safe state never applies

**`SAFE_APPLIED` never pulses.**

- **`FAILSAFE := TRUE` on the node block?** Without it, `ON_LOSS` does nothing.
  This is the usual answer.
- **`ON_LOSS := BEEBUS_MB_RESET_TO_VALUE`?** `BEEBUS_MB_HOLD_LAST_VALUE` is the default and
  is a no-op by design.
- **Is it a single value on a writable table?** A range has no one safe value
  and a string has no numeric one, so those ignore `ON_LOSS`.
- **Has a peer actually written it?** The safe state applies when the peer that
  was driving an address goes quiet. An address nobody ever wrote has no driver
  to lose.

## Everything worked, then one node was replaced

**A new node with the same ID as the old one.** Check for
`BEEBUS_DUPLICATE_NODE_ID` first — if the old device is still powered somewhere
on the segment, the new one stands down.

**Subscriptions re-establish themselves.** When a peer rejoins, subscriptions to
it are re-issued automatically. You do not need to restart the subscribers.

**Buffered topics deliver their history.** If the replaced node owned a buffered
topic, its subscribers receive what accumulated, oldest first, each carrying the
age it was taken at. `MISSED` may jump if the buffer overflowed while it was
away — that is the loss being reported honestly rather than hidden.

## Nothing above fits

Turn on `DEBUG_ENABLE` on `BEEBUS_NODE_STATUS` and read the runtime console. It prints
the protocol's own running commentary — joins, token passes, refusals and why.
It is read once at start-up, so set it and download rather than toggling it
live. On a ModBee Node it prints only in a firmware built with
`BEEBUS_ENABLE_DEBUG` defined.

Then check these three numbers together on every node, at the same moment:

| | what a disagreement means |
| --- | --- |
| `MEMBERS` | nodes disagreeing about the count means a one-way link — one can hear the other but not the reverse |
| `ROTATION` | wildly different figures mean the nodes are not in the same ring |
| `CRC_ERRORS` | rising on one node only points at that node's wiring |

## STATUS says BEEBUS_WRONG_TASK

The block is in a different task from its node. It does nothing until it is
moved: OpenPLC runs each task on a thread of its own, and a block in another
task would be inside the node while the node's own scan is. Move it into the
node's program, and hand your application the value through a global — see
[10 - Scan rate](10-scan-rate.md#the-pattern).

