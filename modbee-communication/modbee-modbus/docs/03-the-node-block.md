# 03 - The node block

`MODBUS_NODE` is the link. It is the only block that touches the wire, and
every other block takes it on a `NODE` pin.

**Eleven pins are the whole of an ordinary link.** Everything else a node can be
told lives on three optional blocks, so none of it is in your way until you want
it:

| | |
| --- | --- |
| `MODBUS_CONFIG` | timeouts, retries, failsafe, how many clients to hold |
| `MODBUS_IDENTITY` | the nameplate this node answers function code 43 with |
| `MODBUS_ARDUINO` | which hardware serial, the RS-485 direction pin, WiFi, Ethernet |

Each takes the node on its own `NODE` pin and may sit anywhere in the same
program, above or below. **The node waits one scan before opening** so that
whatever they set has been seen — one millisecond of a fast task, in exchange
for a placement rule nobody would remember.

**Without any of them the defaults are the ones you want**: the timeout is
measured per device, the retry count is the library's own, nothing fails safe,
a server holds eight clients (two on a board), and a board uses its own serial
pins.

## Three pins decide everything

Modbus has more combinations than are worth putting in one list, so the node
asks three orthogonal questions:

```
TRANSPORT   where the bytes go     MODBUS_RUNTIME_SERIAL, MODBUS_RUNTIME_TCP,
                                   MODBUS_ARDUINO_SERIAL, MODBUS_ARDUINO_WIFI,
                                   MODBUS_ARDUINO_ETHERNET
ROLE        which half to be       MODBUS_ROLE_CLIENT, _SERVER, _BOTH
```

How frames are found is worked out from the medium and is not a pin here at
all — see **Framing** below for the two links where it is not obvious.

One twelve-value enumeration would make the wrong combinations silently legal.
Three pins are smaller *and* say what is going on.

## TRANSPORT — where the bytes go

A `MODBUS_RUNTIME_*` transport runs on the OpenPLC Runtime, a
`MODBUS_ARDUINO_*` transport on a board. Choosing one the target does not have
is **reported on the pins, not built** — `STATUS` reads
`MODBUS_INVALID_ARGUMENT` and `LAST_ERROR` says *"that transport needs a board,
not the Runtime"*.

Which pins matter depends on the transport, and the rest are ignored:

| | |
| --- | --- |
| `MODBUS_RUNTIME_SERIAL` | `SERIAL_DEVICE`, `SERIAL_BAUD`, `SERIAL_PARITY` |
| `MODBUS_RUNTIME_TCP` | `TCP_HOST`, `TCP_PORT` |
| `MODBUS_ARDUINO_SERIAL` | `BAUD`, `PARITY`, and `MODBUS_ARDUINO` for the pins |
| `MODBUS_ARDUINO_WIFI` | `TCP_HOST`, `TCP_PORT`, and `MODBUS_ARDUINO` for the network |
| `MODBUS_ARDUINO_ETHERNET` | `TCP_HOST`, `TCP_PORT`, and `MODBUS_ARDUINO` for the network |

**`DE_PIN` lives on `MODBUS_ARDUINO`, and it is the RS-485 driver enable.** A half-duplex transceiver has to be
switched to transmit and back again: released too early, the last character is
cut in half and the far end reports a checksum error that points nowhere near
the transceiver; released too late, it talks over the reply. **On an ESP32 the
UART does it**: its RS-485 mode drives DE for exactly as long as bits leave and
drops it after the last stop bit, and nothing in the scan waits for the frame -
before, a 256-byte frame at 9600 baud held the node's scan for about 290 ms.
`DE_HOLD` is the pause before release on a core that cannot; leave it at 0 for
two character times.

## Framing — and the converter case

How a receiver knows where one message ends and the next begins is worked out
from the medium: **RTU on a serial line, MBAP on a socket**. That is right for
every link that has nothing unusual in the middle of it, which is why there is
no pin for it on the node.

Two links are not ordinary, and both are set on `MODBUS_CONFIG`'s `FRAMING`
pin.

### RTU over TCP — a terminal server

A serial-to-Ethernet converter takes raw RS-485 frames and puts them straight
inside a TCP stream, with no MBAP header — and listens on port 502, the same as
the real thing. Point a normal TCP client at one and you get silence with no
explanation.

```
node( TRANSPORT := MODBUS_RUNTIME_TCP,
      ROLE      := MODBUS_ROLE_CLIENT,
      TCP_HOST  := '192.168.1.50',
      TCP_PORT  := 4001 );

cfg ( NODE := node, TIMEOUT := T#0s, FRAMING := MODBUS_FRAMING_RTU );
```

Terminal servers usually put each serial port on its own TCP port — 4001, 4002
and so on — rather than on 502. Check the box's own web page.

**If you are not sure which sort you have**, leave it at `AUTO`. If nothing
comes back, try `MODBUS_FRAMING_RTU`. Then read
`MODBUS_STATUS.FRAMING_REASON`, which says which rule is in force in a sentence.

### ASCII — a link that cannot hold RTU's timing

A radio, a modem, a leased line. ASCII spends twice the bytes and allows a full
second between characters, so timing no longer matters:

```
node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE := '/dev/ttyUSB0', SERIAL_BAUD := 9600 );

cfg ( NODE := node, TIMEOUT := T#0s, FRAMING := MODBUS_FRAMING_ASCII );
```

**Two combinations are refused**, with `MODBUS_INVALID_ARGUMENT` and a sentence
on `LAST_ERROR`: ASCII inside a TCP stream, and MBAP framing on a serial line.
Neither is a real thing, and accepting them would turn a typing mistake into a
silence nobody can explain.

## A board's network needs a fixed address

On the Runtime the operating system owns the address and none of this applies.
On a board there is no sketch and no `setup()` of its own, so `MODBUS_NODE`
brings the hardware up itself from `MODBUS_ARDUINO`'s pins — and **`IP` is
required**, on WiFi and on Ethernet alike:

```
wifi( NODE := node, SSID := 'plant', PASSWORD := 'secret',
      IP := '192.168.1.60', GATEWAY := '192.168.1.1' );
```

Two separate reasons, and it is worth knowing which is which:

| | |
| --- | --- |
| **Ethernet** | DHCP **blocks** — up to sixty seconds in the Arduino library, which on a 1 ms task is a stopped PLC, not a delay. The node bounds it to one second an attempt and retries on its own timer, so it works and it costs a stall |
| **WiFi** | DHCP does not block, but **a node that answers Modbus has to be findable**. A SCADA package cannot poll an address that moved when the lease expired |

Write `IP := 'dhcp'` to ask for a server-assigned address anyway. That reads
like the decision it is. `GATEWAY` empty derives from `IP` ending `.1`, and
`SUBNET` empty is `255.255.255.0`.

**Ethernet is opt-in at build time.** Add `MODBUS_ENABLE_ETHERNET` to the
project's build flags — installing the library is not enough, because the
Arduino builder only puts a user library on the include path when it sees a
plain `#include` for it. It drives a W5100/W5500 controller on SPI; an ESP32's
built-in RMII PHY is a different library and is not supported.

## ROLE — which half to be

| | |
| --- | --- |
| `MODBUS_ROLE_CLIENT` | it asks. `MODBUS_READ` and `MODBUS_WRITE` work |
| `MODBUS_ROLE_SERVER` | it answers. `MODBUS_MAP` puts your variables on the bus |
| `MODBUS_ROLE_BOTH` | both, which is ordinary on RS-485 |

**A serial server needs `SERIAL_UNIT_ID`**, 1 to 247 — the address other devices call
it by. It is refused without one, because a server with no address answers
nothing and looks exactly like a broken cable.

**A TCP server does not need `SERIAL_UNIT_ID`.** A client reaching it over TCP has
already addressed it by IP, so it answers whatever unit id is asked for.

**A TCP node is a client when `TCP_HOST` is set and a server when it is empty.**
Saying it that way rather than with another pin keeps the two impossible states
— a client with nowhere to connect, a server pointed at somebody — out of
reach.

## The settings you will usually leave alone

All of these are on `MODBUS_CONFIG`, and the reason they are not on the node is
that most nodes never touch them.

**`TIMEOUT := T#0s`** measures the timeout per device, which is what you want: a
slow drive and a fast I/O block on one bus each get the timeout they deserve.
Set a number only to pin one figure for everything.

**`RETRIES := 0`** takes the default. Raising it on a noisy bus helps; raising
it to hide a wiring fault turns a fast, obvious failure into a slow, confusing
one.

**`MAX_CLIENTS` and `IDLE`** are for a TCP server. The default holds eight
clients on the Runtime and two on a board. There is no ceiling beyond what the
board's memory holds; a figure it cannot hold stops the node with
*"out of memory for MAX_CLIENTS connections"* rather than quietly serving fewer.
The default closes a connection nobody has used for sixty seconds, because a
client that goes away without closing leaves a socket that never reports an
error. `IDLE := -1` never closes one.

**`QUEUE` and `QUEUE_BYTES`** size the request queue: how many requests may
wait at once (16 on a board, 64 on the Runtime) and the bytes their values share
(1 KB on a board). Raise them when `MODBUS_QUEUE_FULL` shows up on requests that
should be accepted. Both are taken when the node opens, and a figure the board
cannot hold stops it with *"out of memory for the request queue"*.

**`FAILSAFE`** is the silence that counts as losing the client. It is what
makes `MODBUS_MAP`'s `ON_LOSS` do anything at all.

The nameplate is on `MODBUS_IDENTITY`:

```
name( NODE := node, VENDOR := 'Example Co', PRODUCT := 'Intake RTU',
      REVISION := '1.0' );
```

## CONNECT — being on the bus, or not

`CONNECT` is `TRUE` unless you say otherwise, which is what almost every node
wants: leave it unwired and the link opens and stays.

Drop it to `FALSE` and the link closes — the port is released and the socket
dropped, so something else may use the converter. Raise it and it opens again.

**Bindings survive the gap.** Everything `MODBUS_MAP` bound is still bound, so
nothing is registered twice and a client reading you after the gap sees what it
saw before.

## Reopening

If the link cannot open — the device is not there, the port is in use — the
node tries again every two seconds rather than every scan. A missing serial
device fails an open in microseconds, and a 1 ms task retrying that is a
thousand identical failures a second in the log.

`READY` stays `FALSE` and `LAST_ERROR` keeps saying why, for as long as it
takes.

## What cannot change once it has started

`TRANSPORT` and `FRAMING` are read when the link is first opened. Changing them
while the program runs is refused, with *"TRANSPORT and FRAMING cannot change
once started"* — because rebuilding the link would silently drop every binding
`MODBUS_MAP` made, and a program that quietly stops answering is worse than one
that says no.

Everything else can change at any time.

**Next:** [04 - Being a device](04-being-a-device.md)
