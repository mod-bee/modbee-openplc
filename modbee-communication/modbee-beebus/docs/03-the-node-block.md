# 03 - The node block

One block, `FB_BeeBusNode`, is this PLC's place on one segment. It starts the
node, keeps it in the ring, and every method in this library is one of its
methods.

`eTransport` picks the link:

| `eTransport` | for |
| --- | --- |
| `E_BeeBusTransport.RuntimeUdp` (default), `RuntimeSerial` | the OpenPLC Runtime - a PC, a Pi, a container |
| `E_BeeBusTransport.ArduinoSerial`, `ArduinoWiFi`, `ArduinoEthernet` | a board - ESP32 and similar |

A transport the target does not have is reported on `bError` (`eErrorId`
`InvalidArgument`, `sLastError` *"that eTransport needs a board, not the
Runtime"*), never built.

## Call it first, then its methods

```
node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
node.Serve(anyData := SET, nTopicId := 300, bWritable := TRUE);
node.Subscribe(anyValue := rFlow, nPeer := 31, sName := 'flow', nTopicId := 3);
```

The block itself runs the protocol: it receives, takes the node's turn and
passes the token, once a scan. A method hands the node a job or reads a result.
A method called above the block works from what the node left at the end of the
previous scan; that costs a scan and corrects itself.

**The link is opened on the block's second scan**, so every method has been
called once first, wherever it sits in the program.

## Methods and their records

Each method call is found again every scan by **what it is about**: its
`anyValue` (`anyData`) - the variable's declared name and type - and the
method. The node keeps what the call needs between scans (the topics it bound,
a request's progress, what arrived) in a record of its own. So:

- **One variable is one record per method.** `node.Topic(anyValue := rLevel ...)`
  and `node.Subscribe(anyValue := rLevel ...)` are two records; two `Topic`
  calls on `rLevel` are one. To serve one variable twice, give each call its
  own variable.
- **A literal has no name** and is found by its topic or address instead.
- **In a `FOR` loop over an array**, `arr[i]` names one element spelling for
  every pass, so every pass is the same record. Write each call with a constant
  index, or pass the whole array to one call.
- **A node holds up to 256 records.** Past that a method returns
  `E_BeeBusResult.QueueFull`.
- **What a record is** - its topic ids, prefix, peer, table and address - is
  taken on the first call that binds it. A later call that changes them returns
  `InvalidArgument` (`sLastError` *"... changed after the first call"*), and the
  record goes on as bound. A record that was refused is tried again once what
  it is changes.

A method's outputs are read with `=>`:

```
eQ := node.Subscribe(anyValue := rFlow, nPeer := 31, sName := 'flow', nTopicId := 3,
                     eQuality => eFlowQuality, bSeen => bFlowSeen);
```

Every method returns an `E_BeeBusResult`. A **request** (`Publish`, `Write`,
`ModbusRead`, `ModbusWrite`) starts on a rising edge of `bExecute`, takes its
inputs at that edge, returns `Queued` while it runs and then holds its outcome
until the next edge. A **standing** method (`Topic`, `Subscribe`,
`PublishStruct`, `SubscribeStruct`, `Serve`, `Bind`, `Buffer`, `ModbusMap`) is
called every scan while it is wanted and returns `Ok` while its record is
valid; its terms (deadband, period, reliability, pulse, settle, depth) may
change while it runs.

## Choosing the link

### On the Runtime

| `eTransport` | what matters |
| --- | --- |
| `RuntimeUdp` | `stNetworkConfig`: `sGroupAddr`, `nUdpPort`, `nTtl`, `sInterfaceAddr` |
| `RuntimeSerial` | `stSerialConfig`: `sDevice`, `nBaud` |

**UDP is the easy one.** Leave `stNetworkConfig` at its defaults and the node
uses the protocol's own multicast group and port. Two containers on one host,
or two PCs on one subnet, find each other with no configuration.

Set `sGroupAddr` and `nUdpPort` only to run **two separate BeeBus networks on
one wire** - different group or port and they cannot hear each other.

`nTtl` is how many routers a frame may cross; 0 is 1, this subnet, which is
usually what you want on a plant. `sInterfaceAddr` picks which network card to
send from, on a machine with several.

**Serial** is `stSerialConfig.sDevice := '/dev/ttyUSB0'`, and `nBaud` (0 for
the default, 115200).

```
VAR
    node   : FB_BeeBusNode;
    serial : ST_BeeBusSerialConfig;
END_VAR
serial.sDevice := '/dev/ttyUSB0';
serial.nBaud := 115200;
node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeSerial, stSerialConfig := serial);
```

### On a board

The settings only a board has - which serial port and pins, the Wi-Fi network,
the Ethernet address - are members of the same two option structures. A
member for the other target (`sDevice` on a board, `sSsid` on the Runtime) is
reported on `bError`, never ignored; the node runs on regardless.

| `eTransport` | `stSerialConfig` | `stNetworkConfig` |
| --- | --- | --- |
| `ArduinoSerial` | `nPort`, `nBaud`, `nRxPin`, `nTxPin` | |
| `ArduinoWiFi` | | `sSsid`, `sWiFiPassword`, `sGroupAddr`, `nUdpPort` |
| `ArduinoEthernet` | | `sMac`, `sIp`, `sGroupAddr`, `nUdpPort` |

```
serial.nPort := 1;
serial.nRxPin := 18;
serial.nTxPin := 17;
node(nNodeId := 10, eTransport := E_BeeBusTransport.ArduinoSerial, stSerialConfig := serial);
```

`nPort` is the hardware serial port: 0 for the first, 1 for `Serial1`. A port
the board has not got is refused (`InvalidArgument`), never quietly opened on
UART0 - on the ModBee Node UART0 is the HAT port, where a modem sits. `nRxPin`
and `nTxPin` are taken only by cores that can remap them (in practice ESP32);
-1, the default, leaves the board's own.

On ESP32 the port is opened with buffers that cover a scan: about 4 KB in and
2 KB out (four and two of the longest frames). With the core's own defaults (256
bytes in, none out) a send waits inside the scan until the frame is nearly on
the wire, and a slow scan loses what arrives after the first 256 bytes: the
other node is heard, but the ring never forms.

Ethernet is opt-in. Add `BEEBUS_ENABLE_ETHERNET` to the board's build flags and
install the Arduino Ethernet library - the standard one for W5100/W5500 over
SPI. It cannot be detected the way Wi-Fi is: Wi-Fi ships inside the core, so its
header is always on the include path, while a user library is only found when a
plain `#include` fails and sends arduino-cli looking for it.

`sIp` empty means DHCP, bounded to a second per attempt rather than the
library's default minute. Give it a fixed address where you can. `sMac` empty
takes a built-in default: fine for one device on a network, a collision the
moment there are two.

## Reading the outputs

| | |
| --- | --- |
| `bReady` | the node started: its link is open |
| `bLinkUp` | the network under it is up: Wi-Fi joined, Ethernet cable in and an address held. The same as `bReady` on the Runtime and on a serial line |
| `bConnected` | in the ring, holding a place in the rotation. The one to interlock on |
| `bError` | something failed: the link, a setting, or a method call |
| `eErrorId` | why, as an `E_BeeBusResult`; `Ok` when fine |
| `sLastError` | what failed, in words |
| `nAttempts` | how many times the link has been opened, or tried |
| `tRetryIn` | while a failed open waits, how long until the next try |

**`bReady` and `bConnected` are different questions.** `bReady` says the node
started and holds its socket or port. `bConnected` says it is in a ring with
somebody. A node alone on a network is `bReady` and not `bConnected`, which is
correct and not an error. `bLinkUp` without `bConnected` is a board on its
network with no ring - exactly what you want to be able to tell apart.

**`sLastError` is worth wiring to something you can see.** A code cannot say
which of forty things went wrong at a socket; *"could not open serial device: No
such file or directory"* can. It says, most fundamental first: the link's own
fault, another device on this id, a setting for the other target, then **the
last method call that failed, by method and record** - *"Serve STS: topic 300
(limit) is already bound"*, *"ModbusRead stsRegs: Timeout"* - until that same
call succeeds. On a board, while nothing is wrong, it also says what the
network is doing: *"joining the network"*, *"no address from DHCP yet"*.

### A link that will not open is tried again

A USB adapter plugged in after boot, an interface that comes up after the PLC,
a port another program holds for a while: the node does not give up.
`eErrorId` reads `NotInitialised`, `sLastError` says why, and the open is tried
again after 1 s, then 2, 4, 8, 16, and every 30 s from then on. `tRetryIn`
counts down to the next try. The moment it opens `bError` clears and `bReady` is
set - nothing in your program has to do it. Until then every method returns
`NotInitialised` and keeps its record.

A **wrong setting** is not retried, because trying again cannot fix it: an
`eTransport` the target does not have, `nNodeId` 0 or 255, a serial link with no
`sDevice`, an `nPort` the board has not got. `eErrorId` reads `InvalidArgument`
and `sLastError` names the setting. Correct it and the link opens - no restart.

## Changing settings while it runs

`nNodeId`, `eTransport`, `bFailsafe`, `nMaxPending` and every member of
`stSerialConfig` and `stNetworkConfig` are read every scan. An HMI that moves
this node to another id or baud rate takes effect at once:

1. the node leaves the ring (it announces its departure, given up to a second);
2. the link is opened again with the new settings, on the **same node** - every
   record its methods bound stays bound, and nothing binds again;
3. it joins the ring under its new id. Peers that subscribed to its topics
   subscribe again when it arrives, as for any node that comes back; its own
   subscriptions are asked for again as each peer joins.

`bConnected` drops for the moment it takes, and `nAttempts` counts the opening.
A peer that addressed the old `nNodeId` must of course be told the new one.

## A duplicate id

`eErrorId` reads `DuplicateNodeId` when another device on the segment is
transmitting under your `nNodeId`.

That node then stands down completely: it takes no turn, claims no address, and
refuses every read and write. Without the code it looks exactly like a node
that has not finished starting.

**It clears itself.** Unplug the other device and the node rejoins on its own
after the address has been quiet a while - no restart. A rising edge on
`bConnect` re-claims it immediately if you would rather not wait.

## Nodes that sleep

`bConnect` is `TRUE` unless you say otherwise, and almost every node wants it
left alone - the node joins and stays.

Drop it to `FALSE` and the node **leaves the ring properly**: it stops taking a
turn and its peers are told, rather than being left to time it out. Raise it and
it rejoins.

```
(* awake ten seconds in every twenty *)
cycleTicks := cycleTicks + 1;
IF cycleTicks >= 1000 THEN cycleTicks := 0; END_IF;
bAwake := cycleTicks < 500;

node(nNodeId := 88, bConnect := bAwake);
```

**Every record survives the gap.** Topics and registers stay bound while
disconnected, so nothing is registered again on waking and a subscriber's
stream picks up where it left off. Add `node.Buffer` and the samples taken while
it slept go out too - see [05 - Topics](05-topics.md).

Wait for `bConnected` before reporting, not on a timer. A value published into
a ring you have not joined yet has nowhere to go and is refused with
`UnknownNode`; how long a rejoin takes is not fixed - measured on a live ring it
varied between 140 ms and 800 ms on the same node:

```
eReport := node.Publish(anyValue := rSoilTemp, sName := 'soil_temp', nTopicId := 1,
                        bExecute := bAwake AND node.bConnected);
```

## How often it is called decides how fast the ring is

This block is the only thing that services the protocol. That has a
consequence worth knowing early: **a PLC only looks at the network once per
scan**, so each hop of the token costs a scan, and a rotation costs roughly
`4.5 x nodes x scan period`. Six nodes on a 20 ms task is about half a second
for a value to get round, and every read and write waits for its turn.

The fix is to put the node and its method calls in a program on a fast task of
its own, and leave the rest of the program where it is. Measured on six
runtimes, that took a rotation from 485 ms to 80 ms with no change to the
application logic. [10 - Scan rate](10-scan-rate.md) has the pattern.

**One task.** The node and every call of its methods run in one task. A method
called from another task returns `E_BeeBusResult.WrongTask` and does nothing,
rather than race the node from another thread. Declare the node in the network
task's program, never in a global list.

## Failsafe

`bFailsafe := TRUE` turns on safe states for this node. It does nothing on its
own - what each address does is set per call of `node.ModbusMap`
(`eOnLoss`, `nSafeValue`), in [04 - Registers](04-registers.md).

Leave it `FALSE` and a value written by a peer simply stays where it was when
that peer went quiet.

## nMaxPending

How many requests (reads, writes, subscriptions) and how many answers can wait
for the token at once, 1 to 255. 0, the default, is 16 on a board and 50 on the
Runtime. Past it a request is refused with `QueueFull` and asked again by its
method on a later scan. Raise it for a node that keeps many requests in flight,
and on the node that answers them. Each place costs about 300 bytes of RAM,
taken when the node starts.

## bDebug

`bDebug := TRUE` prints the protocol's own running commentary - joins, token
passes, refusals and why - to the console. It may be switched while running.
On a ModBee Node the commentary is left out of the firmware to save flash, so it
prints nothing there unless the firmware is built with `BEEBUS_ENABLE_DEBUG`.

## More than one node in a program

A program may run several, one per segment. Each is its own instance with its
own `nNodeId` and link, and each method call names the node it belongs to. The
usual reason is a gateway: one node on a serial segment, one on UDP, and a
program moving values between them ([08 - Patterns](08-patterns.md#a-gateway)).

---

Next: [04 - Registers](04-registers.md) or [05 - Topics](05-topics.md).
