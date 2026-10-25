# 05 - Reading and writing

Three blocks. `MODBUS_READ` and `MODBUS_WRITE` act on a rising edge;
`MODBUS_WATCH` keeps a value fresh on its own and says how much to believe it.

## Reading

```
rd( NODE := node, REQ := go, UNIT := 2,
    FC := MODBUS_FC03_READ_HOLDING_REGISTERS,
    ADDRESS := 40, VALUE := regs );
```

One block for a single value or a whole range, for bits or registers, and for
values wider than a register. What you passed decides which.

`FC` says which of the four lists to read, named the way your device's manual
names it:

| | |
| --- | --- |
| `MODBUS_FC01_READ_COILS` | on/off, a client may also write them |
| `MODBUS_FC02_READ_DISCRETE_INPUTS` | on/off, read only |
| `MODBUS_FC03_READ_HOLDING_REGISTERS` | 16 bits, a client may also write them |
| `MODBUS_FC04_READ_INPUT_REGISTERS` | 16 bits, read only |

**A range is one request, not one per address.** A hundred registers is one
frame and one round trip. Reading them one at a time is a hundred round trips,
which on a 19200 baud bus is the difference between a scan and a second.

## The variable says how many

**Leave `LENGTH` at 0 and the count comes from the variable itself.**
`ARRAY [0..99] OF WORD` reads a hundred registers without you typing 100
anywhere, and it cannot drift when somebody resizes the array a year later.

Getting a length wrong is the commonest mistake anyone makes on a Modbus system
and the one that reads past the end of a buffer, so the block does not ask for
a number it can work out.

`LENGTH` is an override for one case only — a deliberate partial transfer, some
of a bigger buffer. Everything else is refused with
`MODBUS_INVALID_ARGUMENT`, **before anything reaches the wire**:

- **larger than the variable** — refused, not read off the end;
- **past what one request may carry** — 2000 bits or 125 registers for a read,
  1968 or 123 for a write — refused here rather than found out from an
  exception, or from a device that does not bother to raise one.

**`COUNT` says how many addresses actually moved.** It is the pin that makes a
length mistake visible at a glance in the debugger, instead of being inferred
from values that look wrong.

## Handling the answer

`DONE` and `ERROR` are **one-scan pulses**, set on the scan the operation
finished and cleared on the next. That is what lets a program count operations
by counting edges — but it also means you have to act on them in the same scan:

```
IF rd.DONE THEN
    motorSpeed := regs[0];
    faultWord  := regs[1];
END_IF;

IF rd.ERROR THEN
    commsFault := TRUE;
    lastCode   := rd.STATUS;
END_IF;
```

`BUSY` is a **level**, not a pulse: it is `TRUE` for as long as the request is
outstanding.

**Holding `REQ` high is safe.** It reads once on the rising edge, not once a
scan. And a second read of the same address while the first is still
outstanding is refused as `MODBUS_DUPLICATE` rather than queued twice, so a
mistake there costs you nothing on the bus.

## Writing

```
wr( NODE := node, REQ := go, UNIT := 2, ADDRESS := 40, VALUE := setpoint );
```

`FC` defaults to `MODBUS_FC_AUTO`, which reads what you passed and sends the
function code that matches it:

| you passed | it sends |
| --- | --- |
| a single `BOOL` | FC 05, write single coil |
| an array of `BOOL` | FC 15, write multiple coils |
| a single number | FC 06, write single register |
| several numbers | FC 16, write multiple registers |

That is the choice a person would make, and the one most devices expect.

**Name a function code yourself for the devices that disagree** — an older
meter that implements FC 06 and not FC 16, a drive whose manual insists on FC
16 even for one register. The manual will name it the same way this pin does.
A named code that does not match what you passed is refused rather than sent as
something else.

### A repeated write sends only the value you settled on

Raise `REQ` again while the first write is still outstanding and the newer value
replaces it before it goes out. The first is concluded as `MODBUS_SUPERSEDED`,
so nothing is left waiting.

An operator dragging a setpoint slider therefore puts **one** value on the bus,
not forty. That is worth knowing before you write a rate limiter you do not
need.

### Setting one bit of a shared register

`MODBUS_FC22_MASK_WRITE_REGISTER` is the only atomic read-modify-write Modbus
has, and it is the one to reach for on a shared status or command word:

```
wr( NODE := node, REQ := go, UNIT := 2,
    FC := MODBUS_FC22_MASK_WRITE_REGISTER, ADDRESS := 10,
    AND_MASK := 16#FFF7, OR_MASK := 16#0008 );
```

The device keeps `(current AND AND_MASK) OR (OR_MASK AND NOT AND_MASK)`. Above
sets bit 3 and leaves the rest alone.

Without it, two clients setting different bits of one register corrupt each
other: each reads, modifies and writes back, and whichever writes second erases
the first's bit. That fault is intermittent, load-dependent and very hard to
find.

### Broadcast

`UNIT := 0` means every device on the segment performs the write and **none of
them answers**. So `DONE` means "it was transmitted", not "they did it". Useful
for a synchronised command, and worth knowing that it can never be confirmed.

## Values wider than a register

A flow rate, a kilowatt-hour total, a position — none fit in sixteen bits. Pass
a `REAL`, `DINT`, `UDINT`, `LREAL`, `LINT` or `ULINT` and the block reads or
writes the two or four registers and converts them:

```
flow( NODE := node, REQ := go, UNIT := 2,
      FC := MODBUS_FC04_READ_INPUT_REGISTERS, ADDRESS := 30,
      ORDER := MODBUS_ORDER_CDAB, VALUE := flowRate );
```

An array works too, and is still one request: eight `REAL` setpoints are one
frame.

## Word order — the thing everyone hits

**Nothing on the Modbus wire says which way round a device puts a 32-bit
value.** There is no convention, no negotiation, and plenty of manuals do not
say either. So it is an explicit pin, named the way vendor manuals name it:

| | |
| --- | --- |
| `MODBUS_ORDER_ABCD` | big-endian throughout, high word first. What the specification implies and what most devices do |
| `MODBUS_ORDER_CDAB` | low word first, big-endian within each word. **Extremely common** — Schneider, many drives, most of the "swapped words" settings in SCADA packages |
| `MODBUS_ORDER_BADC` | high word first, byte-swapped within each word. Rare |
| `MODBUS_ORDER_DCBA` | fully reversed. What a device does when it copies a float straight out of a little-endian CPU |

**How to recognise it.** A wrong order does not give you a slightly wrong
number — it gives you an obviously absurd one. A flow rate that should read
1234.5 reads `4.6e-41`, or `1.7e38`, or a large negative integer. The address
is right; the layout is not.

**What to do.** Try `MODBUS_ORDER_CDAB` first; it is the common alternative to
the default. If neither works, read the two registers as plain `WORD`s and look
at them in the debugger — the bytes are all there, and one of the four
arrangements will be a plausible number.

`ORDER` is ignored for `BOOL` and `WORD`, which have nothing to reorder.

## Keeping a value fresh, and knowing whether to trust it

```
level( NODE := node, UNIT := 1,
       FC := MODBUS_FC04_READ_INPUT_REGISTERS,
       ADDRESS := 30, EVERY := T#2s, VALUE := tankLevel );
```

No request pin. Every two seconds it decides a read is due and hands it to the
**same queue everything else uses**. The node transmits it on its next call.

**This block never touches the wire**, which means it inherits the whole
contract rather than being a special case:

- a read still outstanding when the next falls due is refused as a duplicate
  rather than stacked, so a watch **cannot flood the bus** however short its
  interval;
- a device that stops answering is backed off to as little as one attempt in
  sixteen, so one dead unit does not consume the segment;
- every read reaches exactly one conclusion, which is what `FAILURES` counts.

### Why quality matters more on Modbus than anywhere

A register holding 1234 tells you nothing about whether 1234 is still true.

On a bus where one device has quietly failed, **a stale reading looks exactly
like a steady process**. The number is plausible. It does not flicker. Every
alarm stays clear. A trend of it is a flat line, which is what a well-controlled
process also looks like.

`QUALITY` is the only thing that separates them:

| | |
| --- | --- |
| `MODBUS_QUALITY_GOOD` | read within the interval you asked for. Act on it |
| `MODBUS_QUALITY_UNCERTAIN` | late, but not by much. One missed read on a busy bus looks like this and is usually nothing |
| `MODBUS_QUALITY_BAD` | stale past any reasonable allowance, or the last read failed. Do not act on it |
| `MODBUS_QUALITY_UNKNOWN` | never read at all |

**Interlock on quality, not on the value:**

```
IF level.QUALITY = MODBUS_QUALITY_GOOD AND tankLevel[0] > 900 THEN
    closeInletValve := TRUE;
END_IF;
```

### UNKNOWN and BAD are different faults

They are worth separate alarms, because they send an engineer to opposite ends
of the site:

- **`UNKNOWN`** — this value has never arrived. An address typed wrong, a unit
  id that is not on the bus, a device never fitted. A **commissioning fault**,
  found at the desk with a wiring drawing.
- **`BAD`** — it did arrive and has since stopped. A cable, a power supply, a
  device that died. A **running fault**, found in the plant.

An alarm list that shows both as "no comms" throws that distinction away, and
it is the most useful thing on the pin.

`AGE` is milliseconds since the value last arrived, or **-1 if it never
has** — the same distinction, as a number.

### Choosing EVERY

`EVERY` is what you asked for, and it is also **what `QUALITY` is judged
against**. Ask for 100 ms on a bus that cannot manage it and the value will
read `UNCERTAIN` for being exactly as late as you should have expected.

Ask for what the process needs:

| | |
| --- | --- |
| a nameplate, a serial number | read it once, with `MODBUS_READ` |
| a tank level, a temperature | seconds |
| a totaliser | seconds |
| a torque or position feedback | a hundred milliseconds, if the bus can carry it |

Every extra read is bus time a control word cannot have.
[10 - Scan rate](10-scan-rate.md) has the arithmetic.

`ENABLE` stops and starts a watch in place, without adding a second one, so a
value watched only in one machine state costs nothing the rest of the time.
Starting it reads at once rather than waiting out an interval.

**Next:** [06 - Diagnostics](06-diagnostics.md)
