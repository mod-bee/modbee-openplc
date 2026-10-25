# modbee-gsm

Function blocks that put a cellular modem inside an OpenPLC program: the
ModBee GSM HAT on a ModBee Node UIO, or a USB modem on the Runtime. One block
brings the modem up and keeps it up; the others send and receive text
messages, open a connection to a server, read the signal, the network time and
a GPS position, and send any AT command. `MQTT_CLIENT` from `modbee-mqtt` uses
the same modem with `TRANSPORT := MQTT_CELLULAR`.

These pages are for the person writing the ST or drawing the ladder. They
assume you know a PLC, not a modem.

## Where to start

**Want something working** — [01 Getting started](01-getting-started.md):
the HAT, the SIM, and a program that comes online.

**Sending to a broker** — [03 MQTT over cellular](03-mqtt-over-cellular.md).

**Looking for a pin** — [02 Block reference](02-block-reference.md).

**It will not connect** — [04 Troubleshooting](04-troubleshooting.md), by what
you are seeing.

## The blocks

| Block | |
| --- | --- |
| `GSM_MODEM` | the modem: power, SIM, network, data. Call it first; a PLC has one |
| `GSM_ARDUINO` | which UART and which pins, on a board. Optional: the defaults are the Node UIO's |
| `GSM_RADIO` | which technology, bands and network to search. Optional |
| `GSM_STATUS` | signal, network, addresses, serial numbers and counters, for a screen |
| `GSM_SOCKET` | a TCP connection to a server, plain or TLS |
| `GSM_SMS_SEND` | sends a text message |
| `GSM_SMS_RECEIVE` | text messages arriving |
| `GSM_GNSS` | the module's satellite position, where it has a receiver |
| `GSM_TIME` | the time, from the network |
| `GSM_AT` | any AT command, and its reply |
| `GSM_POWER` | powers the module off, on, or restarts it |

## Three things worth knowing first

**Nothing waits.** No block holds up a scan waiting for the modem: every
operation starts, and a pin says when it has finished. The one exception is
outside this library - `MQTT_CLIENT` opening its connection - and
[page 03](03-mqtt-over-cellular.md) says how to keep it out of your machine's
way.

**It recovers by itself.** A lost network, a lost data connection or a module
that stops answering is recovered without the program doing anything, and
`GSM_STATUS` counts each time it happened.

**Every setting is a pin.** The APN, its user and password, and the SIM PIN
are ordinary inputs, so they can come from `RETAIN` variables and change
without a new download.
