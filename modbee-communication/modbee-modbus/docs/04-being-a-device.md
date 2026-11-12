# 04 - Being a device

`node.Map` makes your PLC a Modbus device. A SCADA package, an HMI, a
datalogger or another PLC can then read it - and write it, where you let them.

## The whole idea

Set the node's role, then say what lives where:

```
VAR
    node   : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200, nUnitId := 7);
    aTrend : ARRAY [0..9] OF WORD;
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, eRole := E_ModbusRole.Both,
     stSerialConfig := serial);
node.Map(anyData := aTrend, eTable := E_ModbusTable.InputRegister, nAddress := 100);
```

`aTrend` now **is** input registers 100 to 109.

**There is no `bExecute`, and nothing is copied.** A client reading address
103 gets whatever `aTrend[3]` holds at that instant. A client writing a holding
register changes your variable directly. There is nothing to schedule and
nothing to keep in step. Call `Map` every scan, as every standing method: it
returns `E_ModbusResult.Ok` while the range is bound, and `LinkDown` until the
link is open.

**The array's lower bound maps to `nAddress`, whatever that bound is.**
`ARRAY [0..9]` at `nAddress := 100` is 100 to 109; so is `ARRAY [1..10]`.

**A server needs at least one `Map`.** It hands the node its server half, and
without one the node refuses to open as a server.

## Choose the table on purpose

```
E_ModbusTable.Coil             on/off,  a client may write it   FC 1, 5, 15
E_ModbusTable.DiscreteInput    on/off,  read only               FC 2
E_ModbusTable.HoldingRegister  16 bits, a client may write it   FC 3, 6, 16, 22, 23
E_ModbusTable.InputRegister    16 bits, read only               FC 4
```

**Put anything a client must not change in a read-only table.** This is worth
being deliberate about. It is not a permission setting that somebody can alter
later - the table itself has no write function code, so a client that tries is
answered with an exception. A measured value, a status word, a running hours
counter: input registers. A setpoint somebody is meant to adjust: holding
registers.

The four tables are separate, so you can use address 0 in all four without
collision, and most devices do.

## A BOOL goes in a bit table, a number in a register table

Crossing them is refused with `InvalidArgument` rather than reinterpreted. A
coil holds one bit and a register holds sixteen, so binding one to the other
would leave half a register pointing at whatever happens to sit beside your
variable in memory.

**Use `WORD` for registers, not `INT`.** A register is sixteen raw bits, and
`WORD` is what a program can mask, shift and take a bit of - `nStatus.6` for
bit 6 - while `AND`, `OR` and `SHL` are all typed `ANY_BIT`, which `INT` is
not. Use `WORD_TO_INT` where you want a signed number. `INT` and `UINT` map
too.

**An array must have fixed bounds.** `anyData` takes a variable, and
`ARRAY [*]` is not one - it is a view.

## A mapped number is sixteen bits

`INT`, `UINT` and `WORD` map. **`REAL`, `DINT` and the 64-bit types do not** -
they are refused with `InvalidArgument`. This is the one place `Map` asks more
of you than `ReadHoldingRegisters`, which takes all of them, so it is worth
saying why.

Nothing is copied here. The register a client reads **is** your variable, at
that address in memory, this instant. A `REAL` is not a pair of registers; it
is four bytes in a layout that a word order would have to rearrange, and
rearranging means copying, and copying means a client can read half of an old
value and half of a new one with nothing on the wire to say so. A torn reading
is worse than a refused binding, so the method refuses.

Publish a scaled integer instead, which is what a real device does:

```
(* 4.7 mA becomes 470 - 0.01 mA of resolution, and the client divides *)
nScaled := REAL_TO_INT(fMilliamps * 100.0);
node.Map(anyData := nScaled, eTable := E_ModbusTable.InputRegister, nAddress := 0);
```

Say the scaling in your address list, the same way every instrument manual
does. If you would rather not scale, read the `REAL` with
`ReadHoldingRegisters` on the other end instead: a read completes as one
operation, so it has no torn value to cause.

## Several ranges

Call `Map` once per range, each with its own variable. That is how
non-consecutive ranges are expressed:

```
node.Map(anyData := aReadings, eTable := E_ModbusTable.InputRegister, nAddress := 0);
node.Map(anyData := aSetpoints, eTable := E_ModbusTable.HoldingRegister, nAddress := 100,
         bWritten => bSetpointsWritten);
node.Map(anyData := aLamps, eTable := E_ModbusTable.Coil, nAddress := 0);
```

Each call is found again by its variable's declared name, so each range is its
own record with its own `bWritten`. A binding is made once: the same variable
moved to another table or address is refused with `InvalidArgument` rather
than served from where nothing looks.

## Knowing when a client wrote

`bWritten` is `TRUE` on the call after a client wrote **any** address in this
range, whether or not the value changed:

```
node.Map(anyData := aSetpoints, eTable := E_ModbusTable.HoldingRegister,
         nAddress := 100, bWritten => bSetpointsWritten);

IF bSetpointsWritten THEN
    (* validate before acting on anything a stranger sent *)
    IF aSetpoints[0] > 1500 THEN aSetpoints[0] := 1500; END_IF;
    bNewSetpoint := TRUE;
END_IF;
```

It is counted per range, so two ranges never take each other's edges.

**Validate what arrives.** A client can write any sixteen-bit value it likes
into a holding register, including one that will hurt. The register is your
variable, so the check belongs in your program and nowhere else.

## Failsafe - what happens when the client stops

A machine being driven over Modbus needs an answer to "what if the master goes
away". Two settings:

```
VAR
    timing : ST_ModbusTimingConfig := (tFailsafe := T#5s);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeTcp, eRole := E_ModbusRole.Server,
     stTimingConfig := timing);
node.Map(anyData := nDemandSpeed, eTable := E_ModbusTable.HoldingRegister, nAddress := 40,
         eOnLoss := E_ModbusFailsafe.ResetToValue, nSafeValue := 0,
         bSafeApplied => bSpeedSafed);
```

`stTimingConfig.tFailsafe` is the silence that counts as loss: no request
from any client for that long - on TCP whether the client is still connected
or has closed its connection. It fires once per loss. `eOnLoss` on
the map says what that address does about it. `bSafeApplied` says when it
happened.

**Both are needed.** Without `tFailsafe` there is no silence to measure, so
`eOnLoss` never fires - which is a quiet way to have no safety at all, and
worth checking on commissioning by pulling the cable and watching
`bSafeApplied`.

`ResetToValue` applies to a **single value only**. A range has no one safe
value, and guessing one would be worse than holding. Map the few addresses
that need a safe state individually.

**`HoldLastValue`, the default, is a real choice and often the right one** - a
temperature setpoint should probably stay where it was. A speed demand
probably should not.

## A nameplate

A server answers function code 43 - what a handheld tool or another PLC's
`ReadDeviceIdentification` reads - with `stIdentityConfig`:

```
VAR
    ident : ST_ModbusIdentityConfig := (sVendor := 'Example Co',
                                        sProduct := 'Intake RTU', sRevision := '1.0');
END_VAR

node(..., stIdentityConfig := ident);
```

Worth setting on anything somebody else will commission. A panel with six
identical-looking nodes on one segment is a panel where the only way to tell
which is which is to ask them. Leave it empty and the node does not answer
function code 43, as most devices.

## Reading your own registers back

Nothing special is needed: the variable is the register, so read the variable.
`Map` does not give you a copy because there is no copy.

## What it costs

Nothing per scan beyond the call. Binding is done once; after that a client's
request is served straight out of your variable by the node, in the node's own
task. Mapping two thousand registers costs the same per scan as mapping two.

**Next:** [05 - Reading and writing](05-reading-and-writing.md)
