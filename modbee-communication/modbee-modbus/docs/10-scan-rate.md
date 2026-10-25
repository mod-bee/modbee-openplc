# 10 - Scan rate

Almost every "Modbus is slow" complaint is the task interval rather than the
bus, and there is one change that fixes it.

## The one rule

**`MODBUS_NODE` is the only block that touches the wire, and it does one
poll's worth of work per call.** It transmits, it receives, it retries, it times
out — once, then returns.

So **the node's task interval is the floor on how fast anything happens.** A
node called every 20 ms cannot start a request more often than every 20 ms,
however fast the bus is and however little there is to carry.

Put it, and every block given it, in a fast task of their own; your
application stays where it is and trades values with them through globals:

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine - no Modbus block at all |
| `NET_TASK` | `T#1ms` on the Runtime | `20` | `MODBUS_NODE` and every block given it |

**Declare the node in the network program, never in a global list.** OpenPLC
locks every access to a shared global, and a block instance is one: a machine
task that so much as names a global `MODBUS_NODE` waits for the network task to finish
with it - before the block's own task check has run. Measured on a Node UIO with
the client global and one block of it in the 20 ms task: the broker went away,
the network task's scans stretched while it reconnected, the machine task sat
199 ms behind it and OpenPLC stopped the PLC. `MODBUS_WRONG_TASK` stops a race; only
keeping the instance out of the global list stops the wait. Plain values in the
list are fine - each access is a copy.

**Every block given the node runs in the node's task.** OpenPLC runs each task
on a thread of its own, and the library underneath is single-threaded: a
`MODBUS_READ` in another task would be inside the node while the node's own
scan is - one thread adding to its queue while the other walks it. So each
block checks, and in any other task does nothing and says `MODBUS_WRONG_TASK`.
It never races and never waits: a lock that waited would hold your application
back by the node's scan.

```
VAR_GLOBAL  (* PLANT: each written by one task only *)
  rFlow     : REAL;   (* written by net - what was read *)
  rSpeedSp  : REAL;   (* written by main - what to write *)
END_VAR

PROGRAM net                                  (* NET_TASK *)
  VAR
    node : MODBUS_NODE;
    flow : MODBUS_READ;
    sp   : MODBUS_WRITE;
  END_VAR
  node( TRANSPORT := MODBUS_RUNTIME_SERIAL, SERIAL_DEVICE := '/dev/ttyUSB0',
        SERIAL_BAUD := 38400, ROLE := MODBUS_ROLE_CLIENT );
  flow( NODE := node, REQ := TRUE, UNIT := 2,
        FC := MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 100,
        VALUE := PLANT.rFlow );
  sp  ( NODE := node, REQ := TRUE, UNIT := 2, FC := MODBUS_FC_AUTO,
        ADDRESS := 200, VALUE := PLANT.rSpeedSp );
END_PROGRAM
```

That is the whole of it. Everything below explains why it matters and what to
expect once you have done it.

## What the bus itself costs

Modbus RTU sends 11 bits per character — a start bit, eight data bits, a parity
bit and a stop bit. Everything else follows from that.

One read, request and response, including the silence that frames it:

| baud | 1 register | 10 registers | 100 registers | 100 read one at a time |
| --- | --- | --- | --- | --- |
| 9600 | 25 ms | 46 ms | 252 ms | **2.5 s** |
| 19200 | 13 ms | 23 ms | 126 ms | **1.3 s** |
| 38400 | 6 ms | 12 ms | 63 ms | **0.6 s** |
| 115200 | 2 ms | 4 ms | 21 ms | **0.2 s** |

Add the device's own turnaround, which for a small drive or meter is commonly
another 5 to 20 ms and is not something you can change.

**Two things fall straight out of that table.**

**Read ranges, not addresses.** A hundred registers as one request costs 126 ms
at 19200. The same hundred read one at a time costs 1.3 seconds — ten times
worse, for exactly the same data. This is the single biggest lever you have.

**The bus is slower than your scan, by a lot.** At 19200 a single read takes
about 13 ms, which is thirteen scans of a 1 ms task. Your program is never
waiting on your program; it is waiting on the wire. That is exactly why nothing
here blocks.

## Why a 1 ms task, when a read takes 13 ms

Because the node does not spend 13 ms working. It spends 13 ms *waiting*, and
it checks for progress each time it is called.

- Called every **1 ms**, it notices the response about 1 ms after it lands, and
  starts the next request straight away.
- Called every **20 ms**, it notices up to 20 ms late, and then the next request
  waits for the following call. A 13 ms transaction becomes a 40 ms one.

**That is a threefold loss on an idle bus**, and it gets worse as you add
devices, because every transaction pays it.

The node costs almost nothing when there is nothing to do: it checks the
transport, finds no bytes and returns. A 1 ms task holding one node block is
cheap.

## Budgeting a bus

Add up what you are asking for and compare it with what the wire can carry.

A segment at 19200 with six devices, each watched every 500 ms for 20 registers:

```
one read of 20 registers   ≈  33 ms wire + ~10 ms device  ≈  43 ms
six of them                ≈ 258 ms
required every 500 ms      →  about half the bus
```

That leaves room for control writes and for retries. Halve the interval and
there is none, and every `MODBUS_WRITE` starts queueing behind a watch.

**Signs you have overbooked the bus:**

- `MODBUS_WATCH.QUALITY` sitting at `MODBUS_QUALITY_UNCERTAIN` — values
  arriving, but late;
- `MODBUS_STATUS.PENDING` climbing instead of hovering near zero;
- `MODBUS_QUEUE_FULL` on requests that used to work;
- a write that takes noticeably longer than it used to.

**What to do about it, in order of how much it buys you:**

1. **Read wider ranges.** Ten registers cost barely more than one.
2. **Watch less often.** A tank level does not need 200 ms.
3. **Turn off watches you are not using**, with `ENABLE`.
4. **Raise the baud rate.** 38400 halves everything in the table, and most
   modern devices manage it over a properly terminated segment.
5. **Split the bus.** Two segments on two ports carry two conversations at
   once; one segment never will.

## A watch cannot flood the bus

This is worth stating plainly, because it is what makes `MODBUS_WATCH` safe to
use freely.

A watch asks for a read every `EVERY`. If the previous read is **still
outstanding** when the next falls due, the new one is refused as a duplicate
rather than stacked behind it. So the worst a watch can do is have one request
outstanding at a time, however short its interval.

**A device that stops answering is backed off**, progressively, to as little as
one attempt in sixteen. One dead unit on a segment of twenty therefore costs
that segment almost nothing, instead of consuming it with timeouts. It picks
itself up when the device returns.

## Where the time actually goes

When a value seems slow, it is one of four things, and they are easy to tell
apart:

| | how to tell |
| --- | --- |
| **the node's task interval** | it is slower than it needs to be. Check first, fix first |
| **the bus is full** | `PENDING` climbing, `QUALITY` `UNCERTAIN` |
| **the device is slow** | `MODBUS_DEVICE.ROUND_TRIP` is high for that unit and normal for the others |
| **the bus is slow** | `ROUND_TRIP` is high for every unit |

`ROUND_TRIP` is measured, not configured, and it settles the "is it the
device or the bus" argument in about ten seconds.

## Two nodes, two buses

Two `MODBUS_NODE` instances are two independent links, and they poll
independently. Put both in the same fast task:

```
PROGRAM net
VAR
    fieldBus : MODBUS_NODE;
    scada    : MODBUS_NODE;
END_VAR

fieldBus( TRANSPORT := MODBUS_RUNTIME_SERIAL,
          SERIAL_DEVICE := '/dev/ttyUSB0', SERIAL_BAUD := 38400,
          ROLE := MODBUS_ROLE_CLIENT );

scada   ( TRANSPORT := MODBUS_RUNTIME_TCP,
          ROLE := MODBUS_ROLE_SERVER );
END_PROGRAM
```

The serial segment reads field devices; the TCP server answers SCADA. Neither
waits for the other, and a slow drive on the field bus cannot delay a SCADA
poll.

## On a board

The same rule, with less room.

**Measure before going fast.** OpenPLC stops the PLC when a task is still in one
scan after 10 of its intervals, so a `T#1ms` task needs every scan of the node
under 10 ms. Bringing Wi-Fi or Ethernet up is not that - DHCP alone waits up to
a second - so a node on a network link starts at `T#50ms`. Check the task's
longest scan with `openplc-cli debug stats` on your own link before going
faster.

**An RS-485 frame never holds the scan.** On an ESP32 the node gives the port
a transmit buffer that holds any frame, and lets the UART drive the
transceiver's `DE` pin itself (page 03): the frame leaves in the background,
and the driver is released after the last stop bit.

And memory: each link costs roughly two kilobytes before any of your data, so
two links and a large register map is a real figure on a device with a few
hundred kilobytes.

**Back to** [README](README.md)
