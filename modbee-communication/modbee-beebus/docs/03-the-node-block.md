# 03 - The node block

One block starts the node. Everything else in the library needs it.

`BEEBUS_NODE` is that block, and there is one of it. The `TRANSPORT` pin picks the
family:

| `TRANSPORT` starts with | for |
| --- | --- |
| `BEEBUS_NODE_RUNTIME_*` | the OpenPLC Runtime — a PC, a Pi, a container |
| `BEEBUS_NODE_ARDUINO_*` | an Arduino-family board — ESP32, ESP8266, and so on |

Pins the chosen family does not use are ignored, so you leave them. A transport
that does not belong to the target you build for compiles into a stub that
raises `ERROR` and says so, rather than failing to build.

## Call it first

```
node( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
```

Put this above every other BeeBus block in the program.

A block placed above it works from what the node left at the end of the previous
scan. That costs a scan and corrects itself — nothing is lost and no restart is
needed — but there is no reason to have it happen.

## The instance

`node` is the node itself, not a handle to it. Every other block takes it on a
`NODE` in-out pin:

```
node    ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
status  ( NODE := node );
mapLevel( NODE := node, ... );
```

**The pin must be assigned at every call.** Leaving it out is a compile error,
not a block that quietly finds nothing at run time.

An in-out is an alias for your variable rather than a copy, so a block drives
the node you declared. Two things follow from that:

- **Read the node's own outputs from the instance** — `node.CONNECTED`, not
  `status.NODE.CONNECTED`. Reaching into another block's in-out pin from
  outside that block is refused.
- **One instance can be given to as many blocks as you like** - in the node's
  own task. A block given the node from another task says `BEEBUS_WRONG_TASK`
  and does nothing; your logic runs at its own rate on another task and trades
  values with the node's program through globals — see
  [10 - Scan rate](10-scan-rate.md).

## Choosing the link

### On the Runtime

| `TRANSPORT` | pins that matter |
| --- | --- |
| `BEEBUS_NODE_RUNTIME_UDP` | `GROUP`, `UDP_PORT`, `TTL`, `IFACE` |
| `BEEBUS_NODE_RUNTIME_SERIAL` | `DEVICE`, `BAUD` |

Everything else is ignored, so you can leave it.

**UDP is the easy one.** Leave every pin at its default and the node uses the
protocol's own multicast group and port. Two containers on one host, or two PCs
on one subnet, find each other with no configuration.

Set `GROUP` and `UDP_PORT` only to run **two separate BeeBus networks on one
wire** — different group or port and they cannot hear each other.

`TTL` is how many routers a frame may cross. `1` keeps it on this subnet, which
is usually what you want on a plant. `IFACE` picks which network card to send
from, on a machine with several.

**Serial** is `DEVICE := '/dev/ttyUSB0'` and `BAUD := 115200`. `BAUD := 0` uses
the transport's default.

### On an Arduino board

The settings only a board has — which serial port and pins, the WiFi network,
the Ethernet address — are on a second block, `BEEBUS_ARDUINO`, rather than on
the node, so a Runtime user never scrolls past them. Put it in the same program
as the node, above or below: the node waits a scan before opening, so whatever
this block sets has been seen by the time the link is built.

```
board( NODE := node, PORT := 1, RX_PIN := 18, TX_PIN := 17 );
node ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_ARDUINO_SERIAL, BAUD := 115200 );
```

| `TRANSPORT` | on `BEEBUS_NODE` | on `BEEBUS_ARDUINO` |
| --- | --- | --- |
| `BEEBUS_NODE_ARDUINO_SERIAL` | `BAUD` | `PORT`, `RX_PIN`, `TX_PIN` |
| `BEEBUS_NODE_ARDUINO_WIFI` | `GROUP`, `UDP_PORT` | `WIFI_SSID`, `PASSWORD` |
| `BEEBUS_NODE_ARDUINO_ETHERNET` | `GROUP`, `UDP_PORT` | `MAC`, `IP` |

`PORT` is the hardware serial port: 0 for the first, 1 for `Serial1`. `RX_PIN`
and `TX_PIN` are taken only by cores that can remap them (in practice ESP32);
-1 leaves the board's own.

On ESP32 the port is opened with buffers that cover a scan: about 4 KB in and
2 KB out (four and two of the longest frames), from internal RAM. With the
core's own defaults (256 bytes in, none out) a send waits inside the scan until
the frame is nearly on the wire, and a slow scan loses what arrives after the
first 256 bytes: the other node is heard, but the ring never forms.

Ethernet is opt-in. Add `BEEBUS_ENABLE_ETHERNET` to the project's build flags
and install the Arduino Ethernet library — the standard one for W5100/W5500
over SPI. It cannot be detected the way WiFi is: WiFi ships inside the core, so
its header is always on the include path, while a user library is only found
when a plain `#include` fails and sends arduino-cli looking for it.

`IP` empty means DHCP, bounded to a second per attempt rather than the
library's default minute. Give it a fixed address where you can.

`LINK` is an extra output here: the WiFi or Ethernet link is up. It says nothing
about BeeBus — a node can have a link and no ring, which is exactly what you
want to be able to tell apart.

## Reading the outputs

| | |
| --- | --- |
| `READY` | the node started |
| `CONNECTED` | in the ring, with at least one other node |
| `ERROR` | the node did not start, or has stood down |
| `STATUS` | why, as a `BEEBUS_RESULT` |
| `LAST_ERROR` | what failed, in the operating system's own words, or which setting is wrong |
| `LINK` | the WiFi or Ethernet link is up (Arduino transports only) |
| `ATTEMPTS` | how many times the link has been opened, or tried |
| `RETRY_IN` | while a failed open waits, how long until the next try |

**`READY` and `CONNECTED` are different questions.** `READY` says the node
started and holds its socket or port. `CONNECTED` says it is in a ring with
somebody. A node alone on a network is `READY` and not `CONNECTED`, which is
correct and not an error.

**`LAST_ERROR` is worth wiring to something you can see.** A code cannot say
which of forty things went wrong at a socket; *"could not open serial device:
No such file or directory"* can.

### A link that will not open is tried again

A USB adapter plugged in after boot, an interface that comes up after the PLC,
a port another program holds for a while: the node does not give up. `STATUS`
reads `BEEBUS_NOT_INITIALISED`, `LAST_ERROR` says why, and the open is tried
again after 1 s, then 2, 4, 8, 16, and every 30 s from then on. `RETRY_IN`
counts down to the next try. The moment it opens `ERROR` clears and `READY` is
set — nothing in your program has to do it.

A **wrong setting** is not retried, because trying again cannot fix it: a
`TRANSPORT` the target does not have, `NODE_ID` 0 or 255, a serial link
with no `DEVICE`, a `PORT` the board has not got. `STATUS` reads
`BEEBUS_INVALID_ARGUMENT` and `LAST_ERROR` names the setting. Correct it and
the link opens - no restart needed.

## Changing settings while it runs

`NODE_ID`, `TRANSPORT`, `DEVICE`, `BAUD`, `GROUP`, `UDP_PORT`, `TTL`, `IFACE`,
`FAILSAFE`, and everything `BEEBUS_ARDUINO` sets (`PORT`, the pins, the Wi-Fi
login, `MAC`, `IP`), are read every scan. An HMI that moves this node to
another ID or baud rate takes effect at once:

1. the node leaves the ring (it announces its departure, given up to a second);
2. the link is opened again with the new settings, on the **same node** - every
   register map, topic and subscription the other blocks bound stays bound,
   and nothing binds again;
3. it joins the ring under its new ID. Peers that subscribed to its topics
   subscribe again when it arrives, as for any node that comes back; its own
   subscriptions are asked for again as each peer joins.

`CONNECTED` drops for the moment it takes. A peer that addressed the old
`NODE_ID` must of course be told the new one.

## The status you should know

`STATUS` carries `BEEBUS_DUPLICATE_NODE_ID` when another device on the segment
is transmitting under your `NODE_ID`.

That node then stands down completely: it takes no turn, claims no address, and
refuses every read and write. Without the code it looks exactly like a node
that has not finished starting.

**It clears itself.** Unplug the other device and the node rejoins on its own
after the address has been quiet a while — no restart. A rising edge on
`CONNECT` re-claims it immediately if you would rather not wait.

Two nodes commissioned on one ID is the most common mistake on a new network.
This is what it looks like.

## Nodes that sleep

`CONNECT` is `TRUE` unless you say otherwise, and almost every node wants it
left alone — the node joins and stays.

Drop it to `FALSE` and the node **leaves the ring properly**: it stops taking a
turn and its peers are told, rather than being left to time it out. Raise it and
it rejoins.

That is what a battery node wants — wake, report, sleep:

```
VAR
    node       : BEEBUS_NODE;
    bAwake     : BOOL;
    cycleTicks : DINT;
END_VAR

(* awake ten seconds in every twenty *)
cycleTicks := cycleTicks + 1;
IF cycleTicks >= 1000 THEN cycleTicks := 0; END_IF;
bAwake := (cycleTicks < 500);

node( NODE_ID := 88, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, CONNECT := bAwake );
```

**Bindings survive the gap.** Topics and registers stay bound while
disconnected, so nothing is registered again on waking and a subscriber's stream
picks up where it left off. Add `BEEBUS_TP_BUFFER` and the samples taken while it slept
go out too — see [05 - Topics](05-topics.md).

Wait for the node to be back in the ring before it reports. Rejoining takes a
few turns, and a value published into a ring you have not joined yet has nowhere
to go — it is refused with `BEEBUS_UNKNOWN_NODE`.

Wait on `CONNECTED` rather than on a timer. How long a rejoin takes is not fixed
— measured on a live ring it varied between 140 ms and 800 ms on the same node —
so any delay you pick is either too long every cycle or too short occasionally,
and the cycle it is too short on loses its reading:

```
IF bAwake AND node.CONNECTED AND NOT bReported THEN
  report( REQ := TRUE, ... );
  bReported := TRUE;
END_IF;
```

## How often it is called decides how fast the ring is

This block is the only one that services the protocol. Every other block hands
the node a job and reads a result; this one receives the token, takes the node's
turn and passes it on.

That has a consequence worth knowing early: **a PLC only looks at the network
once per scan**, so each hop of the token costs a scan, and a rotation costs
roughly `4.5 x nodes x scan period`. Six nodes on a 20 ms task is about half a
second for a value to get round, and every read and write waits for its turn.

The fix is to put this block, and the blocks given it, in their own fast task,
and leave the rest of the program where it is. Measured on six runtimes, that
took a rotation from 485 ms to 80 ms with no change to the application logic.

[10 - Scan rate](10-scan-rate.md) has the pattern and the numbers.

## Failsafe

`FAILSAFE := TRUE` turns on safe states for this node. It does nothing on its
own — what each address does is set per address on `BEEBUS_MB_MAP`, in
[04 - Registers](04-registers.md).

Leave it `FALSE` and a value written by a peer simply stays where it was when
that peer went quiet.

## More than one node in a program

A program may run several. Each needs its own block, its own `NODE_ID` and its
own transport, and each of the other blocks is given the instance it belongs to
— which the `NODE` pin makes explicit, since it has to be assigned either way.

The usual reason is a gateway: one node on a serial segment, one on UDP, and a
program moving values between them.

---

Next: [04 - Registers](04-registers.md) or [05 - Topics](05-topics.md).
