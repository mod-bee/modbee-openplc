# Modbus for OpenPLC

Function blocks that put Modbus inside an OpenPLC program - reading other
devices, answering other devices, or both at once, over RS-485 or a network.

These pages are for the person writing the ST. They assume you know ladder or
structured text and, helpfully but not necessarily, a little Modbus. They do
not assume you have read the protocol source.

**Coming from 0.1?** [Migrating from 0.1](migrating-from-0.1.md) maps every
0.1 block and pin to its 0.2 method or member. A project on 0.1.x can stay on
it: pin the version and nothing changes.

## Where to start

**Never used Modbus.** Read [01 - What it is](01-what-it-is.md), then work
through [02 - Getting started](02-getting-started.md). Half an hour and you
will have a PLC reading a real device.

**You know Modbus and want to read a device.**
[05 - Reading and writing](05-reading-and-writing.md).

**You want your PLC to BE a Modbus device**, so a SCADA package or an HMI can
read it. [04 - Being a device](04-being-a-device.md).

**You have a serial-to-Ethernet converter** - a terminal server, a "Modbus
gateway", one of the cheap boxes. [03 - The node block](03-the-node-block.md),
the section on framing. It is one member, `stTimingConfig.eFraming`.

**A float reads as 4.6e-41 instead of 1234.5.**
[05 - Reading and writing](05-reading-and-writing.md), the section on word
order. Nothing on the wire says which way round a device puts a 32-bit value,
and this is the single most common Modbus surprise.

**Something is not working.** [09 - Troubleshooting](09-troubleshooting.md) is
arranged by what you are seeing, not by what is wrong.

**You want the parameter list and nothing else.**
[07 - Block reference](07-block-reference.md).

**A sensor or output whose address, type and scaling come from settings** -
a site set up from an HMI, a meter swapped for another model, a device behind
the LoRa mesh. [11 - Points from settings](11-points-from-settings.md).

**Reads are taking too long.** [10 - Scan rate](10-scan-rate.md). Almost always
the task interval rather than the bus, and there is one change that fixes it.

## The whole set

| | |
| --- | --- |
| [01 - What it is](01-what-it-is.md) | Clients, servers, the four tables, and why Modbus is the way it is |
| [02 - Getting started](02-getting-started.md) | A PLC reading a device, one step at a time |
| [03 - The node block](03-the-node-block.md) | Transport, framing, role, the option structures, RTU over TCP |
| [04 - Being a device](04-being-a-device.md) | `Map` - your variables at Modbus addresses |
| [05 - Reading and writing](05-reading-and-writing.md) | The request methods, `Watch`, word order, data quality |
| [06 - Diagnostics](06-diagnostics.md) | `Statistics`, `Device`, the node's error pins, and every result |
| [07 - Block reference](07-block-reference.md) | Every block, method, parameter, structure and enumeration |
| [08 - Patterns](08-patterns.md) | Worked examples, and the habits worth keeping |
| [09 - Troubleshooting](09-troubleshooting.md) | Symptom, cause, fix |
| [10 - Scan rate](10-scan-rate.md) | Why the task interval prices the bus, and the node's own task |
| [11 - Points from settings](11-points-from-settings.md) | `Point`, `Points`: points defined by settings, quality, radio devices |
| [Migrating from 0.1](migrating-from-0.1.md) | Every 0.1 block and pin, and where it went |

## Two blocks

`FB_ModbusNode` is one link: a serial line or a TCP connection, as a client,
a server or both. Everything per request, value, device or mapped range is a
**method** of it. `FB_ModbusBridge` stands alone.

| | |
| --- | --- |
| `FB_ModbusNode` | the link: transport and role on its pins, everything else in four option structures. The only block that touches the wire |
| `ReadCoils`, `ReadDiscreteInputs`, `ReadHoldingRegisters`, `ReadInputRegisters` | read a device - FC 1, 2, 3, 4 |
| `WriteSingleCoil`, `WriteSingleRegister`, `WriteMultipleCoils`, `WriteMultipleRegisters` | write a device - FC 5, 6, 15, 16 |
| `MaskWriteRegister`, `ReadWriteMultipleRegisters` | FC 22 and FC 23 |
| `ReadDeviceIdentification` | a device's nameplate - FC 43 |
| `Watch` | a repeating read, with a quality that says how much to believe it |
| `Point`, `Points` | values defined by settings - read or write, scaled, with a quality |
| `Device` | one device: answering, round trip |
| `Map` | your variables at Modbus addresses, for others to read |
| `Statistics` | link counters, and how frames are being found |
| `FB_ModbusBridge` | TCP clients in front, a serial segment behind |

## The protocol underneath

This library is a thin layer. It binds your variables to the protocol and
translates its results into method results - it holds no logic of its own.
Where these pages say a thing happens, it happens in the protocol underneath,
whose own documentation explains it in far more depth.

You do not need any of it to use these blocks.

**Next:** [01 - What it is](01-what-it-is.md)
