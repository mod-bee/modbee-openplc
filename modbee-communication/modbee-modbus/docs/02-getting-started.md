# 02 - Getting started

A PLC reading a real device, then answering one. Every step says what it does
and why, because the why is what lets you change it afterwards.

## What you need

**An OpenPLC Runtime and something to talk to.** A drive, a meter, a
temperature controller - anything with an RS-485 port and a manual. Or, with no
hardware at all, any Modbus simulator on your own machine over TCP.

Or **a board** - ESP32 or similar - with an RS-485 transceiver. The only
difference is which transport you name.

You also need the library installed in the editor: **Libraries -> Install**, and
pick `modbee-modbus.stlib`.

## Step 1 - start a node

Make a project. Add a program called `net`, and in it declare a node and call
it:

```
PROGRAM net
VAR
    node   : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, stSerialConfig := serial);

END_PROGRAM
```

That is a complete Modbus client. It will open the port and is ready to ask
anybody anything.

**The baud rate and the wiring are the only things you must get right.**
`eParity` defaults to `E_ModbusParity.Even`, which is the Modbus default and
what most devices ship with. If your device's manual says 8N1, say so -
`eParity := E_ModbusParity.None8N1` - and note that `E_ModbusParity.None` on
its own means 8N2, which is what the specification actually requires when
parity is off.

Everything about the serial line lives in one structure, `stSerialConfig`:
give it initial values in the declaration as above, or set its members in the
program (`serial.nBaudRate := 9600;`) or from an HMI. The node reads it when
the link opens.

For TCP instead:

```
node(eTransport := E_ModbusTransport.RuntimeTcp, sHostName := '192.168.1.50');
```

## Step 2 - give it a task of its own

This is the one piece of setup that is not obvious and matters more than
anything else on this page.

**`FB_ModbusNode` is the only block that touches the wire.** It transmits,
receives, retries and times out - once per call. So how often it is called is
the floor on how fast anything happens.

Put it, **with every call of its methods**, in a fast task of its own, and
leave the rest of your program in a normal one:

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine - no Modbus at all |
| `NET_TASK` | `T#1ms` on the Runtime, `T#50ms` on a board to start | `20` | `FB_ModbusNode` and its method calls |

The two trade values through globals, each written by one task. A method
called from any other task than its node's returns
`E_ModbusResult.WrongTask` and does nothing.

A node called every 20 ms spends most of the bus waiting for a task to come
round. [10 - Scan rate](10-scan-rate.md) has the numbers.

## Step 3 - check it opened

`node.bLinkOpen` is `TRUE` once the port opened. If it is `FALSE`,
`node.eErrorId` says why in a code and **`node.sLastError` says it in the
operating system's own words** - *"No such file or directory"* for a wrong
path, *"Permission denied"* for a user who is not in the `dialout` group. Read
that one first; it says far more than a code can.

For a TCP client, `node.bConnected` says whether the device at `sHostName` is
actually there. When it is not, `eErrorId` is `LinkDown`, `sLastError` says
*"not connected"*, and the node keeps trying.

## Step 4 - read something

Now ask a device for some registers, in the same program, after the node:

```
VAR
    node    : FB_ModbusNode;
    serial  : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);
    aRegs   : ARRAY [0..3] OF WORD;
    bRead   : BOOL;
    eLastResult : E_ModbusResult;
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, stSerialConfig := serial);
eLastResult := node.ReadHoldingRegisters(anyData := aRegs, nUnitId := 1,
                                     nStartAddress := 40, bExecute := bRead);
```

A rising edge on `bRead` reads holding registers 40 to 43 from unit 1.

**You did not type a length.** `aRegs` is four elements, so four registers are
read. Resize the array later and the read follows it. Getting a length wrong is
the commonest mistake anyone makes on a Modbus system and the one that reads
past the end of a buffer, so the method does not ask for a number it can work
out. `nQuantity` is there if you genuinely want a partial transfer, and
anything larger than the array is refused rather than obeyed.

**The answer does not arrive on this scan.** The method returns
`E_ModbusResult.Queued` while the request is out, and on a later scan `Ok`,
with the values in `aRegs`. It keeps returning that outcome until the next
rising edge of `bRead`, so you can act on it whenever you look:

```
IF eLastResult = E_ModbusResult.Ok THEN
    nMotorSpeed := aRegs[0];
END_IF;
```

If it failed, the result says why. `Timeout` means nothing answered.
`Refused` means the device answered and said no - which is progress, because
it proves the wiring works. The node also names the failing call on
`bError` and `sLastError` - *"ReadHoldingRegisters aRegs: Timeout"* - until it
succeeds.

**Holding `bRead` high is safe.** It reads once on the edge, not once a scan,
and changing `nStartAddress` while it is high does nothing until the next edge.

## Step 5 - a value that keeps itself up to date

Most of what a PLC reads, it wants to keep reading. That is `Watch`:

```
VAR
    aTankLevel : ARRAY [0..1] OF WORD;
    eLevelQ    : E_ModbusQuality;
END_VAR

node.Watch(anyData := aTankLevel, nUnitId := 1,
           eTable := E_ModbusTable.InputRegister, nStartAddress := 30,
           tReadInterval := T#2s, eQuality => eLevelQ);
```

No `bExecute`. Call it every scan; every two seconds it decides a read is due,
hands it to the same queue everything else uses, and the answer lands in
`aTankLevel`.

**And it tells you how much to believe it.** This is the part worth
understanding:

```
IF eLevelQ = E_ModbusQuality.Good AND aTankLevel[0] > 900 THEN
    bCloseInletValve := TRUE;
END_IF;
```

Without that check, a device that quietly failed leaves `aTankLevel[0]`
holding the last number it ever sent - plausible, steady, and wrong.
`eQuality` is what separates a live reading from a fossil. See
[05 - Reading and writing](05-reading-and-writing.md).

## Step 6 - be a device yourself

Turn it round: let a SCADA package or an HMI read your PLC. Tell the node to
answer as well as ask, and say what lives where:

```
VAR
    node   : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200, nServerUnitId := 7);
    aTrend : ARRAY [0..9] OF WORD;
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, eRole := E_ModbusRole.Both,
     stSerialConfig := serial);
node.Map(anyData := aTrend, eTable := E_ModbusTable.InputRegister, nStartAddress := 100);
```

`nServerUnitId := 7` is the address other devices call your PLC by. `aTrend` now
*is* input registers 100 to 109 - a client reading them gets whatever the
array holds at that instant. Nothing is copied and there is no `bExecute`,
because once mapped the variable **is** the register.

`E_ModbusTable.InputRegister` is read-only, so nobody can write it. Use
`E_ModbusTable.HoldingRegister` for something you want a client to be able to
change. See [04 - Being a device](04-being-a-device.md).

## What you have

A PLC that reads a device on demand, keeps one value permanently fresh with a
quality you can interlock on, and answers a SCADA package on the same wire -
one block and three method calls.

**Next:** [03 - The node block](03-the-node-block.md)
