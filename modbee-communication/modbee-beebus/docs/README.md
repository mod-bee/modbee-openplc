# BeeBus for OpenPLC

One function block, `FB_BeeBusNode`, that puts a BeeBus node inside an OpenPLC
program, so PLCs share data with no master, no polling, and no gateway between
them. Everything the node shares, serves, subscribes, binds, reads or writes is
a **method** of that block: `node.Serve(...)`, `node.Subscribe(...)`,
`node.ModbusRead(...)`.

These pages are for the person writing the ST. They assume you know ladder or
structured text and, helpfully but not necessarily, a little Modbus. They do
not assume you have read the protocol source.

## Where to start

**Never used BeeBus.** Read [01 - What it is](01-what-it-is.md), then work
through [02 - Getting started](02-getting-started.md). Half an hour and you
will have two runtimes exchanging a live value.

**You know Modbus and want your registers shared.** [01 - What it is](01-what-it-is.md)
for the one paragraph that differs, then [04 - Registers](04-registers.md).

**A panel or SCADA changes settings in a PLC.** Start with
[11 - Settings both ways](11-bidirectional-binding.md): `node.Serve` on the
PLC, `node.Bind` on the panel, and nothing else in either program.

**You want values to arrive on their own, not be polled.**
[05 - Topics](05-topics.md).

**You are connecting an HMI.** Put what it shows in one `STRUCT` and what it
sets in another: `node.PublishStruct` publishes the first, one topic per member
([05 - Topics](05-topics.md)), and `node.ModbusMap` maps the second as holding
registers the HMI writes, with `sWrittenName` saying which setting it changed
([04 - Registers](04-registers.md)). One call each, whatever the size.

**Something is not working.** [09 - Troubleshooting](09-troubleshooting.md)
is arranged by what you are seeing, not by what is wrong.

**You want the pin and parameter lists and nothing else.**
[07 - Block reference](07-block-reference.md).

**Values are taking too long to arrive.** [10 - Scan rate](10-scan-rate.md).
Almost always the task interval rather than the network, and there is one
change that fixes it.

## The whole set

| | |
| --- | --- |
| [01 - What it is](01-what-it-is.md) | Nodes, the ring, and the two ways to share a value |
| [02 - Getting started](02-getting-started.md) | Two runtimes talking, one step at a time |
| [03 - The node block](03-the-node-block.md) | `FB_BeeBusNode`: links, settings, records, nodes that sleep |
| [04 - Registers](04-registers.md) | `ModbusMap`, `ModbusRead`, `ModbusWrite` - Modbus addresses, single values to whole `STRUCT`s |
| [05 - Topics](05-topics.md) | `Topic`, `Subscribe`, `PublishStruct`, `SubscribeStruct`, `Publish`, `Write`, `Buffer` - named values, writable settings |
| [06 - Diagnostics](06-diagnostics.md) | `Statistics`, `PeerStatus`, and every `E_BeeBusResult` |
| [07 - Block reference](07-block-reference.md) | The block, every pin, every method and its parameters (generated) |
| [08 - Patterns](08-patterns.md) | Worked examples, and the habits worth keeping |
| [09 - Troubleshooting](09-troubleshooting.md) | Symptom, cause, fix |
| [10 - Scan rate](10-scan-rate.md) | Why the task interval prices the ring, and the node's own task |
| [11 - Settings both ways](11-bidirectional-binding.md) | `Serve`, `Bind` - a panel changes, the PLC decides, both end the same |

## The protocol underneath

This library is a thin layer. It binds your variables to the protocol and
turns its results into `E_BeeBusResult` - it holds no logic of its own. Where
these pages say a thing happens, it happens in the protocol, and the protocol's
own documentation explains why in far more depth:

- **How the ring works**, token passing, joining and healing
- **Every byte on the wire**, if you are implementing BeeBus somewhere else
- **The C++ API**, if you are writing a gateway or an Arduino sketch by hand

You do not need any of it to use the block.
