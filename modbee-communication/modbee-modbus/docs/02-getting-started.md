# 02 - Getting started

A PLC reading a real device, then answering one. Every step says what it does
and why, because the why is what lets you change it afterwards.

## What you need

**An OpenPLC Runtime and something to talk to.** A drive, a meter, a
temperature controller — anything with an RS-485 port and a manual. Or, with no
hardware at all, any Modbus simulator on your own machine over TCP.

Or **a board** — ESP32 or similar — with an RS-485 transceiver. The only
difference is which transport you name.

You also need the library installed in the editor: **Libraries → Install**, and
pick `modbee-modbus.stlib`.

## Step 1 — start a node

Make a project. Add a program called `net`, and in it declare a node and call
it:

```
PROGRAM net
VAR
    node : MODBUS_NODE;
END_VAR

node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE    := '/dev/ttyUSB0',
      SERIAL_BAUD      := 19200 );

END_PROGRAM
```

That is a complete Modbus client. It will open the port and is ready to ask
anybody anything.

**`BAUD` and the wiring are the only things you must get right.** Parity
defaults to even, which is the Modbus default and what most devices ship with.
If your device's manual says 8N1, say so — `SERIAL_PARITY := MODBUS_PARITY_NONE_8N1` —
and note that `MODBUS_PARITY_NONE` on its own means 8N2, which is what the
specification actually requires when parity is off.

For TCP instead:

```
node( TRANSPORT := MODBUS_RUNTIME_TCP,
      TCP_HOST      := '192.168.1.50' );
```

## Step 2 — give it a task of its own

This is the one piece of setup that is not obvious and matters more than
anything else on this page.

**`MODBUS_NODE` is the only block that touches the wire.** It transmits,
receives, retries and times out — once per call. So how often it is called is
the floor on how fast anything happens.

Put it, **with every block given it**, in a fast task of their own, and leave
the rest of your program in a normal one:

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine - no Modbus block at all |
| `NET_TASK` | `T#1ms` on the Runtime, `T#50ms` on a board to start | `20` | `MODBUS_NODE` and every block given it |

The two trade values through globals, each written by one task. A Modbus block
in any other task than its node's says `MODBUS_WRONG_TASK` and does nothing.

A node called every 20 ms spends most of the bus waiting for a task to come
round. [10 - Scan rate](10-scan-rate.md) has the numbers.

## Step 3 — check it opened

Add a status block so you can see what is happening:

```
VAR
    node   : MODBUS_NODE;
    health : MODBUS_STATUS;
END_VAR

node  ( TRANSPORT := MODBUS_RUNTIME_SERIAL,
        SERIAL_DEVICE    := '/dev/ttyUSB0', SERIAL_BAUD := 19200 );
health( NODE := node );
```

`node.READY` is `TRUE` once the port opened. If it is `FALSE`, `node.STATUS`
says why in a code and **`node.LAST_ERROR` says it in the operating system's own
words** — *"No such file or directory"* for a wrong path, *"Permission denied"*
for a user who is not in the `dialout` group. Read that one first; it says far
more than a code can.

**Note how `node` is passed to `health` on its `NODE` pin.** That is how every
block gets at the link, and it must be assigned at every call — leaving it out
is a compile error. That is deliberate: a block with no node is a block that
silently does nothing.

## Step 4 — read something

Now ask a device for some registers. Put this in your `app` program, in the
slower task:

```
PROGRAM app
VAR
    node : MODBUS_NODE;     (* the same instance, passed in *)
    rd   : MODBUS_READ;
    regs : ARRAY [0..3] OF WORD;
    go   : BOOL;
END_VAR

rd( NODE := node, REQ := go, UNIT := 1,
    FC := MODBUS_FC03_READ_HOLDING_REGISTERS,
    ADDRESS := 40, VALUE := regs );
```

A rising edge on `go` reads holding registers 40 to 43 from unit 1.

**You did not type a length.** `regs` is four elements, so four registers are
read. Resize the array later and the read follows it. Getting a length wrong is
the commonest mistake anyone makes on a Modbus system and the one that reads
past the end of a buffer, so the block does not ask for a number it can work
out. There is a `LENGTH` pin if you genuinely want a partial transfer, and
anything larger than the array is refused rather than obeyed.

**The answer does not arrive on this scan.** `rd.BUSY` goes `TRUE`, and some
scans later `rd.DONE` pulses for exactly one scan with the values in `regs`:

```
IF rd.DONE THEN
    motorSpeed := regs[0];
END_IF;
```

If it failed, `rd.ERROR` pulses instead and `rd.STATUS` says why.
`MODBUS_TIMEOUT` means nothing answered. `MODBUS_REFUSED` means the device
answered and said no — which is progress, because it proves the wiring works.

**Holding `go` high is safe.** It reads once on the edge, not once a scan.

## Step 5 — a value that keeps itself up to date

Most of what a PLC reads, it wants to keep reading. That is `MODBUS_WATCH`:

```
VAR
    level     : MODBUS_WATCH;
    tankLevel : ARRAY [0..1] OF WORD;
END_VAR

level( NODE := node, UNIT := 1,
       FC := MODBUS_FC04_READ_INPUT_REGISTERS,
       ADDRESS := 30, EVERY := T#2s,
       VALUE := tankLevel );
```

No request pin. Every two seconds it decides a read is due, hands it to the
same queue everything else uses, and the answer lands in `tankLevel`.

**And it tells you how much to believe it.** This is the part worth
understanding:

```
IF level.QUALITY = MODBUS_QUALITY_GOOD AND tankLevel[0] > 900 THEN
    closeInletValve := TRUE;
END_IF;
```

Without that check, a device that quietly failed leaves `tankLevel[0]` holding
the last number it ever sent — plausible, steady, and wrong. `QUALITY` is what
separates a live reading from a fossil. See
[05 - Reading and writing](05-reading-and-writing.md).

## Step 6 — be a device yourself

Turn it round: let a SCADA package or an HMI read your PLC. Tell the node to
answer as well as ask, and say what lives where:

```
VAR
    node    : MODBUS_NODE;
    pub     : MODBUS_MAP;
    trend   : ARRAY [0..9] OF WORD;
END_VAR

node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE    := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
      ROLE      := MODBUS_ROLE_BOTH,
      SERIAL_UNIT_ID   := 7 );

pub( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
     ADDRESS := 100, VALUE := trend );
```

`SERIAL_UNIT_ID := 7` is the address other devices call your PLC by. `trend` now *is*
input registers 100 to 109 — a client reading them gets whatever the array
holds at that instant. Nothing is copied and there is no request pin, because
once bound the variable **is** the register.

`MODBUS_INPUT_REGISTERS` is read-only, so nobody can write it. Use
`MODBUS_HOLDING_REGISTERS` for something you want a client to be able to
change. See [04 - Being a device](04-being-a-device.md).

## What you have

A PLC that reads a device on demand, keeps one value permanently fresh with a
quality you can interlock on, and answers a SCADA package on the same wire.

**Next:** [03 - The node block](03-the-node-block.md)
