# 09 - Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## The node will not start

**`bLinkOpen` is `FALSE` and `bError` is `TRUE`.**

Read `sLastError` first. It says what failed, in the operating system's own
words, which say far more than a code can. While `eErrorId` reads
`NotInitialised` the node keeps trying - `tRetryTimeLeft` counts down to the next
attempt - so fixing the cause is enough; there is nothing to restart.

| `sLastError` | |
| --- | --- |
| *"could not bind group port: Address already in use"* | another program has the port. Often a second copy of this one still running |
| *"could not open serial device: No such file or directory"* | `stSerialConfig.sDevice` is wrong, or the adapter is not plugged in yet |
| *"could not open serial device: Permission denied"* | the runtime user cannot open the serial port |
| *"could not join multicast group: No such device"* | `sInterfaceAddress` names an address this machine does not have, or the network is not up yet |
| *"no serial device named: stSerialConfig.sDevice"* | `sDevice` left empty with `RuntimeSerial` (a setting: not retried) |
| *"nNodeId must be 1..254"* | a setting: not retried |
| *"stSerialConfig.nUart is not a hardware serial on this board"* | a setting: not retried |
| *"out of memory for the node"*, *"... for the link"* | the board has no room left for the node: the rest of the program has the memory. Retried with the back-off |
| *"joining the network"* | Wi-Fi is still associating. Not a fault - `bError` stays `FALSE` and it clears on its own |
| *"Ethernet cable unplugged"* | no link on the PHY |
| *"no address from DHCP yet"* | cable is live, no lease yet. A fixed `sIpAddress` avoids the wait |
| *"no Ethernet controller found on SPI"* | no W5100/W5500 answered. Check the wiring and CS pin |
| *"Ethernet needs BEEBUS_ENABLE_ETHERNET in the board's build flags"* | Ethernet is opt-in. Add the flag in the board's build flags, and install the Arduino Ethernet library |
| *"this board has no WiFi"* | the board has no `WiFi.h` |

`eErrorId = InvalidArgument` with *"that eTransport needs a board, not the
Runtime"* - or *"that eTransport needs the Runtime, not a board"* - means
`eTransport` names a link the target cannot carry. `RuntimeUdp` or
`RuntimeSerial` on the Runtime, an `Arduino...` value on a board.

## `bError` with the node running

**`bLinkOpen` and `bConnected` are `TRUE`, and `bError` is `TRUE` too.**

`sLastError` names it:

- *"stNetworkConfig: Wi-Fi and Ethernet are a board's ..."*, *"stSerialConfig.sDevice
  is the Runtime's"* - an option structure member for the other target. The node
  runs on; clear the member.
- *"Method record: reason"* - the last method call that failed, by method and
  the variable it is about: *"Serve SET: topic 300 (limit) is already bound"*,
  *"ModbusRead iRemote: Timeout"*. It clears when that same call succeeds. Fix
  the call; the method's own result says the same thing as an `E_BeeBusResult`.

## The node started but never joins

**`bLinkOpen` is `TRUE`, `bConnected` stays `FALSE`, `nNodesInRing` stays 1.**

Work down this list.

**1. Check `eErrorId` for `DuplicateNodeId`.** Two devices on one `nNodeId`.
The second stands down entirely - no turn, no address, every read and write
refused. It looks exactly like a node that has not finished starting, which is
why the code exists. Find the other device and change one of them; the node
rejoins by itself.

**2. Are they on the same network at all?** For UDP, both nodes need the same
`sMulticastAddress` and `nUdpPort`. Leave both at their defaults on both nodes and
they match.

**3. `nMulticastHops`.** If the nodes are on different subnets, the default of 1 keeps
every frame local and they never hear each other. Raise it, or put them on one
subnet.

**4. Multicast on the network.** Some switches drop multicast between ports by
default. Two containers on one host always work; two PCs through a managed
switch may need IGMP snooping configured or turned off.

**5. On serial:** both ends at the same `nBaudRate`, A to A and B to B, and a 120 Ω
terminating resistor at **each end** of the run. Check `nNoiseByteCount` from
`node.Statistics` - climbing means the line is being read but not understood,
which is usually a baud mismatch or missing termination.

## Values are not arriving

**`eQuality` stays `Unknown` and `bValueEverReceived` stays `FALSE`** - nothing has ever
arrived.

**Check the peer is there first.** `node.PeerStatus` with that `nPeerNodeId`. If
`bInRing` is `FALSE`, this is a ring problem, not a topic problem - go back to
the section above.

**Check `sTopic` and `nTopicId` match exactly.** Both must be what the owning
node bound. A mismatched id is the usual cause and nothing reports it as an
error, because from the protocol's side you have simply subscribed to a topic
that node does not have.

**Check the method's result.** `InvalidArgument` means the call could not bind
its own side - a type the wire cannot carry, or a name over 253 characters -
and `sLastError` says which.

**Both ends must declare the same type.** If the owner bound a `REAL` and you
bound an `INT`, values are **discarded on arrival** - `eQuality` stays `Unknown`
and nothing on the subscriber says why. The refusal goes back to the publisher
instead. So when a subscription looks right and still receives nothing, compare
the two declarations before anything else.

## Values arrive, then stop

**`eQuality` goes `Uncertain` then `Bad`, `tValueAge` climbs.**

This is the mechanism working, not failing. Something upstream stopped.

The variable deliberately holds its last reading rather than going to zero -
zero would be a lie. Use `eQuality` to decide whether to trust it, and never
raise a process alarm from a value whose quality is not `Good`.

Check `bInRing` from `node.PeerStatus` for the publisher. If it is alive and
values still stopped, the publisher's own call of `Topic` or `PublishStruct`
stopped returning `Ok` - look at its result and its node's `sLastError`.

## `nMissedUpdateCount` keeps climbing

Updates are being lost on the way. `nMissedUpdateCount` is a running total, so a steady
climb means it is happening now; a fixed number means it happened once.

- **`nChecksumErrorCount` climbing too** - a physical problem. Termination, bias, cable
  length, or a noisy environment.
- **`nNoiseByteCount` climbing** - a floating bus or a baud mismatch.
- **Both quiet, `nMissedUpdateCount` still climbing** - the network is saturated. Check
  `nPendingOperations` and `tTokenRotationTime`; a rotation that has grown a lot means the ring
  is busy. Widen the deadbands, lengthen the periods, or publish fast values to
  `All` so one frame serves every listener.

## Everything works, but it is slow

Values arrive and nothing reports an error - they just take longer than you
expected. Read `tTokenRotationTime` from `node.Statistics` and divide by your node count.

- **About four times your task interval per node** - normal, and it is the task
  interval you are paying for, not the network. A PLC only looks at the bus once
  per scan, so every hop of the token costs a scan. [10 - Scan rate](10-scan-rate.md)
  explains it and gives the fix: the node and its method calls in their own
  fast task, the rest of the program left alone.
- **Much larger than that** - the ring is busy rather than slow. Check
  `nPendingOperations`, and see `nMissedUpdateCount` above.

## Reads and writes fail

**A request ends with something other than `Ok`.**

| result | |
| --- | --- |
| `UnknownNode` | that peer is not on the network - refused at the edge, nothing sent |
| `DuplicateNodeId` | **this** node stood down; another has its id |
| `NotMapped` | nothing is mapped at that address |
| `Timeout` | a confirmed write went unacknowledged after every retry, or no decision came back |
| `NodeLost` | the peer left before it was delivered |
| `QueueFull` | more outstanding than `nMaxPendingOperations` - almost always requests raised every scan |
| `InvalidArgument` | wrong table for the type, a count Modbus disallows, `nQuantity` past the variable |
| `Refused` | the peer rejected it: a read-only topic |
| `TypeMismatch` | a value the other end cannot take as its type |

**`QueueFull` is nearly always the program.** Use a step counter - see
[08 - Patterns](08-patterns.md) - or raise `nMaxPendingOperations` on both ends.

**`NotMapped` on a range** - the peer has *some* of the addresses but not all.
`ModbusMap` there takes `nAddressesUsed` addresses from `nStartAddress`; check the whole
span you are asking for is inside it.

## A request stays `Queued`

`Queued` with no end means the request is waiting for something that is not
coming. Check the peer is `bInRing`. A confirmed write to a node that vanished
mid-flight ends `NodeLost` once the ring notices, which can take a few turns -
give it `tTokenRotationTime` x a few before concluding it is stuck.

If it never ends at all, note the `nPeerNodeId` and address and raise it: a request
that waits forever is a defect, not a configuration.

## A request never starts again

`bExecute` held `TRUE` is one request. Lower it for at least one call, and
raise it again.

## The safe state never applies

**`bSafeValueApplied` never comes.**

- **`bApplySafeValueOnWriterLoss := TRUE` on the node?** Without it, `eActionOnWriterLoss` does nothing. This
  is the usual answer.
- **`eActionOnWriterLoss := ResetToValue`?** `HoldLastValue` is the default and does
  nothing by design.
- **Is it a single number on a writable table?** A range has no one safe value
  and a string has no numeric one, so those ignore `eActionOnWriterLoss`.
- **Has a peer actually written it?** The safe state applies when the peer that
  was driving an address goes quiet. An address nobody ever wrote has no driver
  to lose.

## Everything worked, then one node was replaced

**A new node with the same id as the old one.** Check for `DuplicateNodeId`
first - if the old device is still powered somewhere on the segment, the new
one stands down.

**Subscriptions re-establish themselves.** When a peer rejoins, subscriptions to
it are re-issued automatically. You do not need to restart the subscribers.

**Buffered topics deliver their history.** If the replaced node owned a buffered
topic, its subscribers receive what accumulated, oldest first, each carrying the
age it was taken at. `nMissedUpdateCount` may jump if the buffer overflowed while it was
away - that is the loss being reported honestly rather than hidden.

## A method returns `WrongTask`

It is called from another task than its node's. It does nothing until it is
moved: OpenPLC runs each task on a thread of its own, and a call from another
task would be inside the node while the node's own scan is. Move the call into
the node's program, and hand your application the value through a global - see
[10 - Scan rate](10-scan-rate.md#the-pattern).

## A method returns `InvalidArgument` after it worked

What a record is - its topic ids, prefix, peer, table and address - is taken on
the first call that binds it. A call that later passes another `nTopicId`,
`sTopicPrefix`, `nPeerNodeId`, `eTable` or `nStartAddress` for the same variable returns
`InvalidArgument` (*"... changed after the first call"*), and the record goes
on as bound. Put it back, or give the other topic its own variable.

## Nothing above fits

Set `bDebugToConsole := TRUE` on the node and read the runtime console. It prints the
protocol's own running commentary - joins, token passes, refusals and why. On a
ModBee Node it prints only in a firmware built with `BEEBUS_ENABLE_DEBUG`.

Then check these three numbers together on every node, at the same moment:

| | what a disagreement means |
| --- | --- |
| `nNodesInRing` | nodes disagreeing about the count means a one-way link - one can hear the other but not the reverse |
| `tTokenRotationTime` | wildly different figures mean the nodes are not in the same ring |
| `nChecksumErrorCount` | rising on one node only points at that node's wiring |
