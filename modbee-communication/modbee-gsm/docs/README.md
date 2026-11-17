# modbee-gsm

Function blocks that put a cellular modem inside an OpenPLC program: the
ModBee GSM HAT on a ModBee Node UIO, or a USB modem on the Runtime. One block
per modem module brings the modem up and keeps it up; everything else is a
method of that block: text messages out and in, text-message commands, a
connection to a server, the signal, the network time, a satellite position,
any AT command, and the module's power. `FB_MqttClient` from `modbee-mqtt`
uses the same modem with `eTransport := E_MqttTransport.Cellular`.

These pages are for the person writing the ST or drawing the ladder. They
assume you know a PLC, not a modem.

## Where to start

**Want something working** - [01 Getting started](01-getting-started.md):
the HAT, the SIM, and a program that comes online.

**Looking for a pin or a method** - [02 Block reference](02-block-reference.md).

**Sending to a broker** - [03 MQTT over cellular](03-mqtt-over-cellular.md).

**It will not connect** - [04 Troubleshooting](04-troubleshooting.md), by what
you are seeing.

## The blocks

| Block | Module | |
| --- | --- | --- |
| `FB_GsmModemA7670` | SIMCom A7670, A7672, A7678, A7608 (LTE Cat-1) - the ModBee GSM HAT |
| `FB_GsmModemSim7070` | SIMCom SIM7070, SIM7080, SIM7090 (LTE-M, NB-IoT) |

Pick the block for the module on the board: only its driver goes into the
firmware (about 4 kB less flash than both), and a module of the other family
is refused by name rather than driven wrongly.

Their settings are option structures: `stApnConfig` (APN, user, password),
`stSerialConfig` (the serial device, or a board's UART and pins),
`stPowerConfig` (the power key and supply pins), `stRadioConfig` (radio mode,
operator, bands), `stCapacityConfig` (sockets, buffers, command queue) and
`stSmsConfig` (`SendSms`'s queue, hourly limit and retries).

## The methods

| Method | |
| --- | --- |
| `SendSms` | queues a text message to a list of numbers; the block sends them, with an hourly limit and retries |
| `SendSmsRequest` | one text message on a rising edge, followed until the network has it |
| `Format` | a message from a template, `{member}` placeholders filled from a STRUCT |
| `Inbox` | text messages arriving, one a call |
| `SmsCommand` | text-message commands from allowed numbers, with PINs, replies and a rate limit |
| `AtCommand` | any AT command, and its reply |
| `Power` | switches the module off, on, or restarts it |
| `Socket` | a TCP connection to a server, plain or TLS |
| `Status` | signal, network, addresses, serial numbers and counters |
| `NetworkTime` | the time, from the network |
| `Gnss` | the module's satellite position, where it has a receiver |

## Three things worth knowing first

**Nothing waits.** No block or method holds up a scan waiting for the modem:
a request starts on an edge and returns `E_GsmResult.Queued` until it is done.
The one exception is outside this library - `FB_MqttClient` opening its
connection - and [page 03](03-mqtt-over-cellular.md) says how it stays out of
your machine's way.

**It recovers by itself.** A lost network, a lost data connection or a module
that stops answering is recovered without the program doing anything, and
`Status` counts each time it happened.

**Every setting is an input.** The APN, its user and password, and the SIM PIN
are ordinary inputs, so they can come from `RETAIN` variables and change
without a new download.
