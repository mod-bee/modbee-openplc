# 01 - What it is

Modbus is the oldest industrial protocol still in daily use, and it is
everywhere: drives, meters, temperature controllers, weigh cells, protection
relays, SCADA packages. If a piece of industrial kit talks to anything, it
probably talks Modbus.

It is also very simple, and most of what makes it awkward comes from that
simplicity rather than from complexity. This page explains the four things you
have to know before the blocks make sense.

## One asks, the other answers

Modbus has exactly two roles, and a device is one, the other, or both.

**A client asks.** It sends a request and waits for a reply. Your PLC is a
client when it reads a drive's speed.

**A server answers.** It never speaks unless spoken to. A drive is a server. So
is your PLC, when a SCADA package reads it.

Older documents say *master* and *slave* for the same two things. The words
changed; nothing else did.

**Your PLC can be both at once**, and on RS-485 that is ordinary: it reads six
field devices as a client and answers a SCADA package as a server, on the same
wire. `ROLE := MODBUS_ROLE_BOTH`.

**A server cannot start a conversation.** If you want a device to tell you
something the moment it happens, Modbus is the wrong protocol — nobody can be
told anything, only asked. This is why everything in Modbus is a poll, and why
[10 - Scan rate](10-scan-rate.md) matters more than it would elsewhere.

## Four lists, and they are separate

A Modbus device holds four numbered lists. That is its entire data model.

| | holds | writable by a client | function codes |
| --- | --- | --- | --- |
| **Coils** | one bit | yes | 1, 5, 15 |
| **Discrete inputs** | one bit | no | 2 |
| **Holding registers** | 16 bits | yes | 3, 6, 16, 22 |
| **Input registers** | 16 bits | no | 4 |

**They are four separate lists, not four views of one.** Address 40 in the
holding registers and address 40 in the input registers are different storage
holding different things. Reading the wrong list gives you a plausible number
from somewhere else entirely, and that is a common and very annoying mistake.

**A register is sixteen anonymous bits.** Not an integer, not a float — sixteen
bits. What they mean is in the device's manual and nowhere else. This is why
anything bigger than 65535 spans two registers or four, and why
[word order](05-reading-and-writing.md) is a thing you have to know about.

**Read-only is the list, not a permission.** Put a value in the input registers
and no client can write it, because there is no function code that writes that
list. It is not a setting somebody can change later.

## Function codes are how you say which list

Every request carries a function code — a number, 1 to 255, saying what to do.
You will meet six of them:

| | |
| --- | --- |
| **FC 01** read coils | |
| **FC 02** read discrete inputs | |
| **FC 03** read holding registers | by far the most used |
| **FC 04** read input registers | |
| **FC 05 / 06** write one coil / one register | |
| **FC 15 / 16** write several coils / several registers | |

The blocks name them exactly as your device's manual does —
`MODBUS_FC03_READ_HOLDING_REGISTERS` — so a data sheet that says "supports FC03
and FC16" translates without thought.

## Serial or network, and the framing problem

Modbus runs over two quite different things.

**RS-485 (serial).** One pair of wires, one conversation at a time, up to 32
devices sharing it. Each device has a **unit id**, 1 to 247, and that is how
you address it.

**TCP (a network).** You address a device by IP, and the unit id mostly does
not matter. Several clients can talk at once.

The difference that bites is **framing** — how a receiver knows where one
message ends and the next begins.

- **On a network**, every message carries a header that says how long it is.
  There is nothing to work out.
- **On RS-485 there is no length anywhere.** A frame ends when the line has
  been quiet for three and a half character times. That is it. So anything that
  disturbs the timing of the bytes — a USB adapter, a virtual serial port, a
  busy PLC scan — can split one frame into two or glue two into one.

The node block measures the line and decides how to find frames, and it will
tell you which rule it chose and why on one pin. See
[06 - Diagnostics](06-diagnostics.md).

**And there is a third thing, which is not in any standard.** A serial-to-
Ethernet converter takes raw RS-485 frames and puts them inside a TCP stream
without adding the network header. That is **RTU over TCP**, it is extremely
common, and it shares the same port number as the real thing — so pointing a
normal TCP client at one gets silence and no explanation. Here it is one pin.
See [03 - The node block](03-the-node-block.md).

## What this library does about all that

Four things, and they are the reason it exists rather than being a wrapper
around a socket:

**Nothing blocks.** A read is queued and the answer arrives in your variable on
a later scan. Your PLC never waits for a device. On a 9600 baud bus a single
read takes tens of milliseconds, which is thousands of scans.

**The variable says how many.** You pass an array; the block counts it. You
never type a length that can be wrong, and a length that cannot fit is refused
before anything reaches the wire rather than read off the end of a buffer.

**Every request reaches exactly one conclusion.** Success, failure, refusal,
timeout — one of them, always. A request that is accepted and then silently
forgotten does not look like a bug; it looks like a control loop that quietly
stops working after a few hours.

**A stale value is distinguishable from a live one.** A register holding 1234
tells you nothing about whether 1234 is still true. `MODBUS_WATCH` carries a
quality alongside the value, and on a bus where one device has quietly died
that is the difference between an alarm and an accident.

**Next:** [02 - Getting started](02-getting-started.md)
