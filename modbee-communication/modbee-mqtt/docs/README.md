# modbee-mqtt

Function blocks that put an MQTT client inside an OpenPLC program. One node
block starts the client and hands itself to the others, so a program can talk
to two brokers at once, be the site broker itself, or bridge between them.

These pages are for the person writing the ST or drawing the ladder. They
assume you know a PLC. They do not assume you have ever used MQTT — page 01
starts there.

## Where to start

**Never used MQTT** — [01 What it is](01-what-it-is.md). Broker, client,
publish, subscribe and topics, in about ten minutes.

**Want something working** — [02 Getting started](02-getting-started.md). Six
steps to a PLC publishing a value and acting on one.

**It connects and then stops** — [09 Troubleshooting](09-troubleshooting.md),
arranged by what you are seeing rather than by what is wrong.

**It works but feels slow** — [10 Scan rate](10-scan-rate.md). One change
fixes almost every complaint, and it is not in this library.

**Looking for a pin** — [07 Block reference](07-block-reference.md).

**Building a site, not a device** — [11 Broker](11-broker.md) and
[12 Bridge](12-bridge.md).

**Many PLCs on a modbee broker** — [13 Provisioning](13-provisioning.md): each
gets its own login by itself, with nothing typed in.

**Reporting to a SCADA system** — [14 Sparkplug](14-sparkplug.md): a site's
values, writes and timestamps over Wi-Fi, Ethernet or cellular.

## The whole set

| | |
| --- | --- |
| [01 What it is](01-what-it-is.md) | brokers, clients, topics, QoS, retained messages and wills |
| [02 Getting started](02-getting-started.md) | six steps to a working device |
| [03 The node block](03-the-node-block.md) | transports, security, versions, the optional helpers |
| [04 Publishing](04-publishing.md) | on demand, on change with a deadband, and a whole STRUCT at once |
| [05 Subscribing](05-subscribing.md) | values with a quality, raw messages, and a whole STRUCT at once |
| [06 Diagnostics](06-diagnostics.md) | the counters, and the full result table |
| [07 Block reference](07-block-reference.md) | every block, every pin |
| [08 Patterns](08-patterns.md) | worked examples, habits, and what bites people |
| [09 Troubleshooting](09-troubleshooting.md) | by symptom |
| [10 Scan rate](10-scan-rate.md) | the node's own task, and why it matters |
| [11 Broker](11-broker.md) | the PLC as the site broker |
| [12 Bridge](12-bridge.md) | carrying topics between two brokers |
| [13 Provisioning](13-provisioning.md) | a PLC that gets its own login from a modbee broker, by itself |
| [14 Sparkplug](14-sparkplug.md) | SCADA over Sparkplug B: transports, metric limits, deadbands, writes, time, settings changes, outage history (`SPARKPLUG_HISTORY`) and daily totals (`SPARKPLUG_DAY_TOTALS`) |

## Client, broker, bridge

Three roles, three blocks, MQTT's own words:

| | |
| --- | --- |
| `MQTT_CLIENT` | this PLC talks to a broker. **The one almost every program wants**. Runtime and board |
| `MQTT_BROKER` | this PLC *is* the broker other devices connect to. Runtime and board — serving plain needs nothing installed, serving TLS needs wolfSSL |
| `MQTT_BRIDGE` | this PLC carries topics between two brokers. **Runtime only**: two simultaneous connections is most of a board's heap |

**Every block that publishes or subscribes takes a `CLIENT` pin.**
`MQTT_BROKER` and `MQTT_BRIDGE` do not have one, because neither is a client:
a broker *routes* what clients send, and a bridge *forwards* between two
brokers. Neither has topics of its own.

So a PLC that runs the broker **and** wants to publish runs both blocks — one
to be the broker, one to be a client of it. See [11 Broker](11-broker.md).

## The protocol underneath

This library is a thin layer over `modbee-mqtt`, a clean-room MQTT 3.1.1 and
5.0 implementation written from the OASIS standards. It holds no protocol
logic of its own: the blocks translate pins into calls and calls into pins.

Nothing in it blocks. `connect()` does not wait for the broker — it starts the
attempt and a later scan says whether it arrived. That is what makes MQTT safe
inside a scan cycle, and it is why the library was written rather than
borrowed.

**Next:** [01 What it is](01-what-it-is.md)
