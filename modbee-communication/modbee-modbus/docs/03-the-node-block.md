# 03 - The node block

`FB_ModbusNode` is the link. It is the only block that touches the wire, and
everything you do on the link is one of its methods: `node.ReadCoils`,
`node.Watch`, `node.Map` and the rest.

**Five pins and four option structures are the whole of it.** The pins say
what the link is; the structures hold everything you might tune, each with a
default that is right for most links, so none of it is in your way until you
want it:

| | |
| --- | --- |
| `eTransport`, `eRole`, `sHost`, `nPort`, `bConnect` | what the link is, and whether it is open |
| `stSerialConfig : ST_ModbusSerialConfig` | a serial line: device or UART, baud, parity, this node's unit id, the RS-485 pins |
| `stTimingConfig : ST_ModbusTimingConfig` | timeout, retries, reconnect, framing, failsafe, idle connections, queue and client limits |
| `stIdentityConfig : ST_ModbusIdentityConfig` | the nameplate a server answers function code 43 with |
| `stNetworkConfig : ST_ModbusNetworkConfig` | a board's Wi-Fi or Ethernet |

Set a structure in its declaration or from an HMI. The compiler checks every
member, which a text field could not.

```
VAR
    node   : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);
    timing : ST_ModbusTimingConfig := (nRetries := 3, tFailsafe := T#5s);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, eRole := E_ModbusRole.Both,
     stSerialConfig := serial, stTimingConfig := timing);
```

**Without any of them the defaults are the ones you want**: the timeout is
measured per device, the retry count is the library's own, a dropped link
comes back on its own, nothing fails safe, a server holds eight clients (two
on a board), and a board uses its own serial pins.

## Two pins decide everything

Modbus has more combinations than are worth putting in one list, so the node
asks two orthogonal questions:

```
eTransport  where the bytes go   E_ModbusTransport.RuntimeSerial, RuntimeTcp,
                                 ArduinoSerial, ArduinoWiFi, ArduinoEthernet
eRole       which half to be     E_ModbusRole.Client, Server, Both
```

How frames are found is worked out from the medium - see **Framing** below
for the two links where it is not obvious.

One twelve-value enumeration would make the wrong combinations silently legal.
Two pins are smaller *and* say what is going on.

## eTransport - where the bytes go

A `Runtime...` transport runs on the OpenPLC Runtime, an `Arduino...`
transport on a board. Choosing one the target does not have is **reported, not
built** - `eErrorId` reads `InvalidArgument` and `sLastError` says *"that
eTransport needs a board, not the Runtime"*.

What matters depends on the transport, and the rest is ignored:

| | |
| --- | --- |
| `RuntimeSerial` | `stSerialConfig.sDevice`, `nBaudRate`, `eParity` |
| `RuntimeTcp` | `sHost`, `nPort` |
| `ArduinoSerial` | `stSerialConfig.nUart`, `nRxPin`, `nTxPin`, `nDePin`, `tDeHold`, `nBaudRate`, `eParity` |
| `ArduinoWiFi` | `sHost`, `nPort`, and `stNetworkConfig` |
| `ArduinoEthernet` | `sHost`, `nPort`, and `stNetworkConfig` |

**Every input is used, or you are told.** On the Runtime, a board's members -
anything in `stNetworkConfig`, or `stSerialConfig.nUart` and the pins - set
`bError` with *"stNetworkConfig is for a board; the Runtime uses its machine's
network"*. On a board, `stSerialConfig.sDevice` is reported the same way. The
link still runs; the message is there so a setting that does nothing is never
mistaken for one that does.

**`nDePin` is the RS-485 driver enable.** A half-duplex transceiver has to be
switched to transmit and back again: released too early, the last character is
cut in half and the far end reports a checksum error that points nowhere near
the transceiver; released too late, it talks over the reply. **On an ESP32 the
UART does it**: its RS-485 mode drives DE for exactly as long as bits leave and
drops it after the last stop bit, and nothing in the scan waits for the frame -
before, a 256-byte frame at 9600 baud held the node's scan for about 290 ms.
`tDeHold` is the pause before release on a core that cannot; leave it at 0 for
two character times.

**`nUart`** picks the board's hardware serial, 0 for the first. A number the
board does not have is refused - never quietly opened on UART0, which on the
ModBee Node is the HAT port. On an ESP32-S3 with USB CDC on boot, `Serial` is
the USB device, so 0 is `Serial0`; for a real RS-485 port use 1 or 2 with
`nRxPin` and `nTxPin`.

## Framing - and the converter case

How a receiver knows where one message ends and the next begins is worked out
from the medium: **RTU on a serial line, MBAP on a socket**
(`stTimingConfig.eFraming := E_ModbusFraming.Auto`, the default). That is right
for every link that has nothing unusual in the middle of it.

Two links are not ordinary.

### RTU over TCP - a terminal server

A serial-to-Ethernet converter takes raw RS-485 frames and puts them straight
inside a TCP stream, with no MBAP header - and listens on port 502, the same as
the real thing. Point a normal TCP client at one and you get silence with no
explanation.

```
VAR
    timing : ST_ModbusTimingConfig := (eFraming := E_ModbusFraming.Rtu);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeTcp, sHost := '192.168.1.50',
     nPort := 4001, stTimingConfig := timing);
```

Terminal servers usually put each serial port on its own TCP port - 4001, 4002
and so on - rather than on 502. Check the box's own web page.

**If you are not sure which sort you have**, leave it at `Auto`. If nothing
comes back, try `E_ModbusFraming.Rtu`. Then read `sFramingReason` from
`node.Statistics`, which says which rule is in force in a sentence.

### ASCII - a link that cannot hold RTU's timing

A radio, a modem, a leased line. ASCII spends twice the bytes and allows a full
second between characters, so timing no longer matters:

```
VAR
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 9600);
    timing : ST_ModbusTimingConfig := (eFraming := E_ModbusFraming.Ascii);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial,
     stSerialConfig := serial, stTimingConfig := timing);
```

**Two combinations are refused**, with `InvalidArgument` and a sentence on
`sLastError`: `Ascii` inside a TCP stream, and `Tcp` (MBAP) framing on a serial
line. Neither is a real thing, and accepting them would turn a typing mistake
into a silence nobody can explain.

## A board's network needs a fixed address

On the Runtime the operating system owns the address and none of this applies.
On a board there is no sketch and no `setup()` of its own, so the node brings
the hardware up itself from `stNetworkConfig` - and **`sIp` is required**, on
Wi-Fi and on Ethernet alike:

```
VAR
    net : ST_ModbusNetworkConfig := (sSsid := 'plant', sWiFiPassword := 'secret',
                                     sIp := '192.168.1.60', sGateway := '192.168.1.1');
END_VAR

node(eTransport := E_ModbusTransport.ArduinoWiFi, eRole := E_ModbusRole.Server,
     stNetworkConfig := net);
```

Two separate reasons, and it is worth knowing which is which:

| | |
| --- | --- |
| **Ethernet** | DHCP **blocks** - up to sixty seconds in the Arduino library, which on a 1 ms task is a stopped PLC, not a delay. The node bounds it to one second an attempt and retries on its own timer, so it works and it costs a stall |
| **Wi-Fi** | DHCP does not block, but **a node that answers Modbus has to be findable**. A SCADA package cannot poll an address that moved when the lease expired |

Write `sIp := 'dhcp'` to ask for a server-assigned address anyway. That reads
like the decision it is. `sGateway` empty derives from `sIp` ending `.1`, and
`sSubnet` empty is `255.255.255.0`. Joining Wi-Fi takes seconds and does not
block: the node reports `LinkDown` with *"joining the network"* meanwhile.

**Ethernet is opt-in at build time.** Add `MODBUS_ENABLE_ETHERNET` to the
project's build flags - installing the library is not enough, because the
Arduino builder only puts a user library on the include path when it sees a
plain `#include` for it. It drives a W5100/W5500 controller on SPI; an ESP32's
built-in RMII PHY is a different library and is not supported. Without the
flag the node says *"define MODBUS_ENABLE_ETHERNET to build Ethernet in"*.

## eRole - which half to be

| | |
| --- | --- |
| `E_ModbusRole.Client` | it asks: the `Read...` and `Write...` methods, `Watch`, `Point`, `Points`, `Device` |
| `E_ModbusRole.Server` | it answers: `Map` puts your variables on the bus |
| `E_ModbusRole.Both` | both, which is ordinary on RS-485 |

**A server needs at least one `Map` call.** Without one it refuses to open,
with *"a server needs a Map call"* - a server with nothing to serve answers
every request with an exception for a reason nobody could see. A program that
only asks never calls `Map`, and so links none of the server code.

**A serial server needs `stSerialConfig.nUnitId`**, 1 to 247 - the address
other devices call it by. It is refused without one, because a server with no
address answers nothing and looks exactly like a broken cable.

**A TCP server does not need a unit id.** A client reaching it over TCP has
already addressed it by IP, so it answers whatever unit id is asked for.

**A TCP node is a client when `sHost` is set and a server when it is empty.**
Saying it that way rather than with another pin keeps the two impossible states
- a client with nowhere to connect, a server pointed at somebody - out of
reach.

## stTimingConfig - the settings you will usually leave alone

**`tTimeout := T#0s`** measures the timeout per device, which is what you want:
a slow drive and a fast I/O block on one bus each get the timeout they
deserve. Set a figure only to pin one for everything.

**`nRetries := 0`** takes the default. Raising it on a noisy bus helps; raising
it to hide a wiring fault turns a fast, obvious failure into a slow, confusing
one.

**`tReconnect` and `bAutoReconnect`.** A dropped link is retried every two
seconds (`tReconnect := T#0s`) until it returns, and every watched value is
made due the moment it does: the far end of a Modbus link is a device that gets
rebooted. `bAutoReconnect := FALSE` leaves it down until `bConnect` is cycled,
for a link where the application would rather decide.

**`nMaxClients` and `tIdle`** are for a TCP server. The default holds eight
clients on the Runtime and two on a board. There is no ceiling beyond what the
board's memory holds; a figure it cannot hold stops the node with *"out of
memory for nMaxClients connections"* rather than quietly serving fewer.
`tIdle := T#0s` closes a connection nobody has used for sixty seconds, because
a client that goes away without closing leaves a socket that never reports an
error.

**`nMaxPending` and `nMaxPendingBytes`** size the request queue: how many
requests may wait at once (16 on a board, 64 on the Runtime) and the bytes
their values share (1 KB on a board). Raise them when `QueueFull` shows up on
requests that should be accepted. Both are taken when the node opens, and a
figure the board cannot hold stops it with *"out of memory for the request
queue"*.

**`tFailsafe`** is the silence that counts as losing the client. It is what
makes `Map`'s `eOnLoss` do anything at all.

The nameplate is `stIdentityConfig`:

```
VAR
    ident : ST_ModbusIdentityConfig := (sVendor := 'Example Co',
                                        sProduct := 'Intake RTU', sRevision := '1.0');
END_VAR
```

## bConnect - being on the bus, or not

`bConnect` is `TRUE` unless you say otherwise, which is what almost every node
wants: leave it unwired and the link opens and stays.

Drop it to `FALSE` and the link closes - the port is released and the socket
dropped, so something else may use the converter. A request still out is
concluded `Cancelled`. Raise it and it opens again.

**Records survive the gap.** Everything `Map` bound is still bound and every
`Watch` still watches, so nothing is registered twice and a client reading you
after the gap sees what it saw before.

## Reopening

If the link cannot open - the device is not there, the port is in use - the
node tries again every two seconds rather than every scan. A missing serial
device fails an open in microseconds, and a 1 ms task retrying that is a
thousand identical failures a second in the log.

`bLinkUp` stays `FALSE` and `sLastError` keeps saying why, for as long as it
takes. A TCP client whose device refuses the connection is open but not
connected: `bConnected` is `FALSE`, `eErrorId` is `LinkDown`, and `sLastError`
says *"not connected"* while it retries.

## What changes when

`tTimeout`, `nRetries` and `stIdentityConfig` take effect at once. The rest
is read when the link opens - cycle `bConnect` to apply a change.
`eTransport` and `eFraming` cannot change once the link has been built: that
is refused, with *"eTransport and eFraming cannot change once started"* -
because rebuilding the link would silently drop every binding `Map` made, and
a program that quietly stops answering is worse than one that says no.

**Next:** [04 - Being a device](04-being-a-device.md)
