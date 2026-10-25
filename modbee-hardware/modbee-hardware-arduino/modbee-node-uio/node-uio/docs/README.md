# ModBee Node UIO for OpenPLC

The blocks that put a Node UIO's I/O into an OpenPLC program: eight digital
inputs and eight digital outputs, four analog inputs and two analog outputs,
the HAT power rail, the network, sleep and a controlled restart, pulse counting,
I2C expansion modules and the controller's own health. Variables that
survive a power cut need no block: OpenPLC's built-in ESP32 store keeps them.

This is a hardware library. It knows nothing about ModBee, Modbus or anything
else that talks to other machines — those are their own libraries, and they run
alongside this one on the same board.

It assumes you know your way around the OpenPLC Editor and can write a program.
It does not assume you know the board.

## Where to start

**New to the board** — [01 Getting started](01-getting-started.md) puts an
input on an output and proves the wiring.

**Looking up a pin** — [02 Block reference](02-block-reference.md) lists every
block and every pin.

**Reading a sensor or driving a valve** — [03 Analog](03-analog.md) covers
ranges, scaling and calibration, and the solder bridge that decides which.

**Running on a battery** — [04 Sleep and power](04-sleep.md), including the
radio, the button that brings it back, and the four outputs that cannot be
held.

**Values that must survive a power cut** — [05 Retained variables](05-retained-variables.md).

**A flow meter, or how the controller itself is doing** — [07 Pulses and diagnostics](07-pulses-and-diagnostics.md).

**More inputs and outputs on I2C** — [08 I2C expansion](08-expansion.md).

**Something is not doing what you expect** — [06 Troubleshooting](06-troubleshooting.md).

## The whole set

| Page | What it covers |
| --- | --- |
| [01 Getting started](01-getting-started.md) | A first program, and where the blocks go |
| [02 Block reference](02-block-reference.md) | Every block, every pin |
| [03 Analog](03-analog.md) | Ranges, scaling, raw counts, calibration |
| [04 Sleep and power](04-sleep.md) | Sleep, wake sources, what holds, and running on a battery |
| [05 Retained variables](05-retained-variables.md) | RETAIN, where it is kept, and what it costs |
| [06 Troubleshooting](06-troubleshooting.md) | Symptoms, and what causes them |
| [07 Pulses and diagnostics](07-pulses-and-diagnostics.md) | `PULSE_COUNT` for flow meters, `SYS_INFO` for on-site diagnosis |
| [08 I2C expansion](08-expansion.md) | `UIO_EXPANSION`, `UIO_I2C_SCAN`, the module table, and adding a chip driver |

## The board underneath

The electrical side — pinouts, terminals, solder bridges, power — belongs to
the board's own documentation rather than here. What matters in a program is
that a channel's voltage-or-current choice is a solder bridge, not a setting,
and that the two are easy to get out of step.
