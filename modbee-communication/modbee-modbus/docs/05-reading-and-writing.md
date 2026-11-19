# 05 - Reading and writing

One method per Modbus function, named as the specification names it, and
`Watch`, which keeps a value fresh on its own and says how much to believe it.

| method | function code |
| --- | --- |
| `ReadCoils` | 1 |
| `ReadDiscreteInputs` | 2 |
| `ReadHoldingRegisters` | 3 |
| `ReadInputRegisters` | 4 |
| `WriteSingleCoil` | 5 |
| `WriteSingleRegister` | 6 |
| `WriteMultipleCoils` | 15 |
| `WriteMultipleRegisters` | 16 |
| `MaskWriteRegister` | 22 |
| `ReadWriteMultipleRegisters` | 23 |
| `ReadDeviceIdentification` | 43 - see [06 - Diagnostics](06-diagnostics.md) |

A data sheet that says "supports FC03 and FC16" is `ReadHoldingRegisters` and
`WriteMultipleRegisters`, without a lookup.

## A request

Every one of them is a **request**: it starts on a rising edge of `bExecute`,
takes its inputs at that edge, and returns an `E_ModbusResult`:

```
eRead := node.ReadHoldingRegisters(anyData := aRegs, nUnitId := 2,
                                   nStartAddress := 40, bExecute := bRead);
```

| it returns | when |
| --- | --- |
| `Ok` | before its first edge, and once the answer arrived |
| `Queued` | while the request is out |
| `Timeout`, `Refused`, `NotMapped`, ... | why it failed - see [06 - Diagnostics](06-diagnostics.md) |
| `LinkDown` | at an edge with the link not open or the device not connected: refused at once, never queued for later |
| `InvalidArgument` | the inputs cannot work - refused before anything reaches the wire |

**The outcome is held until the next rising edge**, so you can act on it on
any scan, not only the one it arrived on:

```
IF eRead = E_ModbusResult.Ok THEN
    nMotorSpeed := aRegs[0];
    nFaultWord  := aRegs[1];
ELSIF eRead <> E_ModbusResult.Queued THEN
    bCommsFault := TRUE;
END_IF;
```

**Holding `bExecute` high is safe.** It reads once on the rising edge, not
once a scan, and changing `nStartAddress` or the variable while it is high does
nothing until the next edge. A failing request is also named on the node's
`bError` and `sLastError` until it succeeds.

**One variable is one request per method.** Each call is found again every
scan by its variable's declared name: two calls of `ReadHoldingRegisters` with
the same variable are the same request, and their `bExecute` edges fight. Give
each its own variable. A function block of your own that calls the node's
methods on its locals is fine: the same local in two instances of it is two
records. Calls with no variable - `WriteSingleCoil`,
`WriteSingleRegister`, `MaskWriteRegister` - are found by unit and address.

## Reading

One method for a single value or a whole range, and for values wider than a
register. What you pass decides which:

```
node.ReadCoils(anyData := aCoils, nUnitId := 2, nStartAddress := 0, bExecute := bRead);
node.ReadInputRegisters(anyData := fFlowRate, nUnitId := 2, nStartAddress := 30,
                        eWordOrder := E_ModbusOrder.CDAB, bExecute := bRead);
```

The coil and discrete-input reads take a `BOOL` or an array of `BOOL`; the
register reads take a number. Crossing them is refused rather than
reinterpreted.

**A range is one request, not one per address.** A hundred registers is one
frame and one round trip. Reading them one at a time is a hundred round trips,
which on a 19200 baud bus is the difference between a scan and a second.

## The variable says how many

**Leave `nQuantity` at 0 and the count comes from the variable itself.**
`ARRAY [0..99] OF WORD` reads a hundred registers without you typing 100
anywhere, and it cannot drift when somebody resizes the array a year later.

Getting a length wrong is the commonest mistake anyone makes on a Modbus system
and the one that reads past the end of a buffer, so the method does not ask
for a number it can work out.

`nQuantity` is an override for one case only - a deliberate partial transfer,
some of a bigger buffer. Everything else is refused with `InvalidArgument`,
**before anything reaches the wire**:

- **larger than the variable** - refused, not read off the end;
- **past what one request may carry** - 2000 bits or 125 registers for a read,
  1968 or 123 for a write - refused here rather than found out from an
  exception, or from a device that does not bother to raise one.

A second read of the same place while the first is still out - from another
variable - is refused as `Duplicate` rather than queued twice.

## Writing

```
node.WriteSingleRegister(nValue := nSetpoint, nUnitId := 2, nAddress := 40, bExecute := bSend);
node.WriteSingleCoil(bValue := bRun, nUnitId := 2, nAddress := 7, bExecute := bSend);
node.WriteMultipleRegisters(anyData := aRecipe, nUnitId := 2, nStartAddress := 100, bExecute := bSend);
node.WriteMultipleCoils(anyData := aLamps, nUnitId := 2, nStartAddress := 0, bExecute := bSend);
```

The values are **copied at the edge**: change the variable while the write is
out and the device gets what it held at the edge.

**The single and the multiple forms are different function codes**, and a
device's manual says which it takes - an older meter that implements FC 06 and
not FC 16, a drive whose manual insists on FC 16 even for one register.
`WriteMultipleRegisters` with a single `WORD` sends FC 16 with one register;
`WriteSingleRegister` sends FC 06.

### A repeated write sends only the value you settled on

A second write to the same address while the first is still out - from
another variable - replaces it before it goes out. The first is concluded as
`Superseded`, so nothing is left waiting. An operator dragging a setpoint
slider puts **one** value on the bus, not forty.

### Setting one bit of a shared register

`MaskWriteRegister` is the only atomic read-modify-write Modbus has, and it is
the one to reach for on a shared status or command word:

```
node.MaskWriteRegister(nAndMask := 16#FFF7, nOrMask := 16#0008,
                       nUnitId := 2, nAddress := 10, bExecute := bSet);
```

The device keeps `(current AND nAndMask) OR (nOrMask AND NOT nAndMask)`. Above
sets bit 3 and leaves the rest alone.

Without it, two clients setting different bits of one register corrupt each
other: each reads, modifies and writes back, and whichever writes second erases
the first's bit. That fault is intermittent, load-dependent and very hard to
find.

### A command and its result together

`ReadWriteMultipleRegisters` writes and then reads in **one** transaction, and
the specification says the write goes first - so a client sending a command
and reading back the result gets the result of the command it just sent:

```
node.ReadWriteMultipleRegisters(anyReadData := aStatus, anyWriteData := aCommand,
                                nUnitId := 2, nReadStartAddress := 200,
                                nWriteStartAddress := 100, bExecute := bSend);
```

`WORD`, `INT` or `UINT` only, up to 125 read and 121 written.

### Broadcast

`nUnitId := 0` means every device on the segment performs the write and **none
of them answers**. So `Ok` means "it was transmitted", not "they did it".
Useful for a synchronised command, and worth knowing that it can never be
confirmed. A read cannot be broadcast.

## Values wider than a register

A flow rate, a kilowatt-hour total, a position - none fit in sixteen bits. Pass
a `REAL`, `DINT`, `UDINT`, `DWORD`, `LREAL`, `LINT`, `ULINT` or `LWORD` to the
register reads or to `WriteMultipleRegisters`, and the method reads or writes
the two or four registers and converts them:

```
node.ReadInputRegisters(anyData := fFlowRate, nUnitId := 2, nStartAddress := 30,
                        eWordOrder := E_ModbusOrder.CDAB, bExecute := bRead);
```

An array works too, and is still one request: eight `REAL` setpoints are one
frame, and **a set of values that only mean anything together cannot
half-arrive**.

## Word order - the thing everyone hits

**Nothing on the Modbus wire says which way round a device puts a 32-bit
value.** There is no convention, no negotiation, and plenty of manuals do not
say either. So it is an explicit parameter, `eWordOrder`, named the way vendor
manuals name it:

| | |
| --- | --- |
| `E_ModbusOrder.ABCD` | big-endian throughout, high word first. What the specification implies and what most devices do. The default |
| `E_ModbusOrder.CDAB` | low word first, big-endian within each word. **Extremely common** - Schneider, many drives, most of the "swapped words" settings in SCADA packages |
| `E_ModbusOrder.BADC` | high word first, byte-swapped within each word. Rare |
| `E_ModbusOrder.DCBA` | fully reversed. What a device does when it copies a float straight out of a little-endian CPU |

**How to recognise it.** A wrong order does not give you a slightly wrong
number - it gives you an obviously absurd one. A flow rate that should read
1234.5 reads `4.6e-41`, or `1.7e38`, or a large negative integer. The address
is right; the layout is not.

**What to do.** Try `E_ModbusOrder.CDAB` first; it is the common alternative
to the default. If neither works, read the two registers as plain `WORD`s and
look at them in the debugger - the bytes are all there, and one of the four
arrangements will be a plausible number.

`eWordOrder` is ignored for `BOOL` and the 16-bit types, which have nothing to
reorder.

## Keeping a value fresh, and knowing whether to trust it

```
eLevel := node.Watch(anyData := aTankLevel, nUnitId := 1,
                     eTable := E_ModbusTable.InputRegister, nStartAddress := 30,
                     tReadInterval := T#2s, eQuality => eLevelQ, bValueEverReceived => bLevelSeen,
                     tValueAge => tLevelAge, nConsecutiveFailureCount => nLevelFailures);
```

No `bExecute`: call it every scan. Every `tReadInterval` it decides a read is due
and hands it to the **same queue everything else uses**. The node transmits it
on its next call. `eTable` says which table to read; the variable says how
many, as for the requests.

**The method never touches the wire**, which means it inherits the whole
contract rather than being a special case:

- a read still outstanding when the next falls due is not stacked, so a watch
  **cannot flood the bus** however short its period;
- a device that stops answering is backed off to as little as one attempt in
  sixteen, so one dead unit does not consume the segment;
- every read reaches exactly one conclusion, which is what `nConsecutiveFailureCount` counts.

It returns the last read's result: `Ok`, or why the last read failed.

### Why quality matters more on Modbus than anywhere

A register holding 1234 tells you nothing about whether 1234 is still true.

On a bus where one device has quietly failed, **a stale reading looks exactly
like a steady process**. The number is plausible. It does not flicker. Every
alarm stays clear. A trend of it is a flat line, which is what a well-controlled
process also looks like.

`eQuality` is the only thing that separates them:

| | |
| --- | --- |
| `E_ModbusQuality.Good` | read within the period you asked for. Act on it |
| `E_ModbusQuality.Uncertain` | late, but not by much. One missed read on a busy bus looks like this and is usually nothing |
| `E_ModbusQuality.Bad` | stale past any reasonable allowance, or the last read failed. Do not act on it |
| `E_ModbusQuality.Unknown` | never read at all |

**Interlock on quality, not on the value:**

```
IF eLevelQ = E_ModbusQuality.Good AND aTankLevel[0] > 900 THEN
    bCloseInletValve := TRUE;
END_IF;
```

### Unknown and Bad are different faults

They are worth separate alarms, because they send an engineer to opposite ends
of the site:

- **`Unknown`** - this value has never arrived. An address typed wrong, a unit
  id that is not on the bus, a device never fitted. A **commissioning fault**,
  found at the desk with a wiring drawing.
- **`Bad`** - it did arrive and has since stopped. A cable, a power supply, a
  device that died. A **running fault**, found in the plant.

An alarm list that shows both as "no comms" throws that distinction away, and
it is the most useful thing on the method.

`bValueEverReceived` says the same as a `BOOL` a rung can read: `FALSE` means nothing has
ever arrived. `tValueAge` is the time since the value last arrived - `T#0s` until it
ever has, which `bValueEverReceived` tells apart from a fresh one.

### Choosing tReadInterval

`tReadInterval` is what you asked for, and it is also **what `eQuality` is judged
against**. Ask for 100 ms on a bus that cannot manage it and the value will
read `Uncertain` for being exactly as late as you should have expected.

Ask for what the process needs:

| | |
| --- | --- |
| a nameplate, a serial number | read it once, with a request |
| a tank level, a temperature | seconds |
| a totaliser | seconds |
| a torque or position feedback | a hundred milliseconds, if the bus can carry it |

Every extra read is bus time a control word cannot have.
[10 - Scan rate](10-scan-rate.md) has the arithmetic.

**`bEnable` stops and starts a watch in place**, so a value watched only in
one machine state costs nothing the rest of the time. Starting it reads at once
rather than waiting out a period.

**`nUnitId`, `eTable`, `nStartAddress` and `eWordOrder` may change while it runs** -
from settings, say - and the watch follows: the same record is re-aimed,
`eQuality` goes back to `Unknown` and the next read goes to the new place.
`nQuantity` and the variable are fixed at the first call. For a value whose
type and scaling come from settings too, use `Point` -
[11 - Points from settings](11-points-from-settings.md).

`nDeadband` is how far a register must move to count as a change for the
library's change tracking; 0 counts any change.

**Next:** [06 - Diagnostics](06-diagnostics.md)
