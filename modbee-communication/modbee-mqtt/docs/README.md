# modbee-mqtt

Function blocks that put MQTT inside an OpenPLC program. Version 0.2.0.

One block per connection. `FB_MqttClient` is one connection to one broker;
everything you publish or subscribe on it is a **method** of that block:
`mqtt.Publish(...)`, `mqtt.Subscribe(...)`. A Sparkplug node is one more block
on the same connection, and a whole STRUCT reports with one call:
`sp.Record(...)`. The PLC can also be the site broker, or bridge two brokers.

These pages are for the person writing the ST. They assume you know a PLC.
They do not assume you have ever used MQTT - page 01 starts there.

> **Coming from 0.1.x?** 0.2.0 replaces 28 blocks with 6. A project built on
> 0.1.x stays on 0.1.x and runs unchanged - pin it with `openplc-cli library
> pin <project> modbee-mqtt@0.1.2` - and moves when its owner chooses. The wire does not
> change: the same configuration sends the same topics, metrics and births.
> [Migrating from 0.1](migrating-from-0.1.md) maps every old block and pin.

## Quick start: a plain MQTT client

```st
VAR
  mqtt     : FB_MqttClient;
  rLevel   : REAL;            (* the machine writes it *)
  rSetpoint: REAL;            (* arrives from the broker *)
  eQuality : E_MqttQuality;
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'plc-intake');

mqtt.Report(anyValue := rLevel, sTopic := 'plant/intake/level',
            fDeadband := 0.05, tPeriod := T#1m, bRetain := TRUE);

mqtt.Subscribe(anyValue := rSetpoint, sTopic := 'plant/intake/cmd/setpoint',
               eQos := E_MqttQos.AtLeastOnceDelivery, eQuality => eQuality);
```

The client is called once a scan, in a task of its own (page 02 step 2). The
level goes out when it moves by 5 cm and once a minute anyway; the setpoint
lands in `rSetpoint` with a quality that says how much to believe it.

## Quick start: a Sparkplug node with Record

```st
VAR
  mqtt : FB_MqttClient;
  sp   : FB_SparkplugNode;
  PUMP : S_PUMP;              (* your STRUCT: sts, tot, cmd, ... *)
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'site1-pumps');
sp(fbClient := mqtt, sGroupId := 'Site1', sEdgeNodeId := 'pumps');

sp.Record(anyData := PUMP, sPrefix := 'pump1/',
          sSettings := 'sts = now; tot = log, db = 0.5, u = h; cmd = cmd, pulse = 500');
```

Every member of `sts` goes at once when it changes, the totals every 15
minutes when they moved by more than 0.5 h, and SCADA may write `cmd` once
`stReportConfig.bRemoteControl` is TRUE. The point list is page 15.

## Where to start

**Never used MQTT** - [01 What it is](01-what-it-is.md). Broker, client,
publish, subscribe and topics, in about ten minutes.

**Want something working** - [02 Getting started](02-getting-started.md). Six
steps to a PLC publishing a value and acting on one.

**It connects and then stops** - [09 Troubleshooting](09-troubleshooting.md),
arranged by what you are seeing rather than by what is wrong.

**It works but feels slow** - [10 Scan rate](10-scan-rate.md). One change
fixes almost every complaint, and it is not in this library.

**Looking for a pin or a method** - [07 Block reference](07-block-reference.md).

**Building a site, not a device** - [11 Broker](11-broker.md) and
[12 Bridge](12-bridge.md).

**Many PLCs on a modbee broker** - [13 Provisioning](13-provisioning.md): each
gets its own login by itself, with nothing typed in.

**Reporting to a SCADA system** - [14 Sparkplug](14-sparkplug.md) and
[15 Record](15-sparkplug-record.md): a site's values, writes and timestamps
over Wi-Fi, Ethernet or cellular.

## The blocks

| Block | Is | Methods |
| --- | --- | --- |
| `FB_MqttClient` | one connection to one broker. **The block almost every program wants.** Runtime and board | `Publish`, `Report`, `Subscribe`, `PublishStruct`, `SubscribeStruct`, `Request`, `Response`, `Message`, `Provision`, `Statistics` |
| `FB_SparkplugNode` | a Sparkplug B edge node on a client's connection | `Record`, `Metric`, `Device`, `Command`, `History`, `DayTotals` |
| `FB_SparkplugHost` | a Sparkplug B host application on a client's connection | `Watch`, `Write` |
| `FB_MqttBroker` | this PLC **is** the broker. Runtime and board | `User` |
| `FB_MqttBridge` | carries topics between two brokers. **Runtime only** | |
| `FB_MqttClock` | sets the controller's clock from the network | |

The client's settings that are not where it connects are grouped in four
option structures on its inputs, checked by the compiler and settable from an
HMI: `stSessionConfig` (keep-alive, session, login, queue, reconnecting),
`stTlsConfig` (certificates), `stNetworkConfig` (a board's Wi-Fi or Ethernet)
and `stWillConfig` (online/offline presence). Leave them out and the defaults
are the ones you want.

**`FB_MqttBroker` and `FB_MqttBridge` take no client**, because neither is
one: a broker *routes* what clients send, and a bridge *forwards* between two
brokers. A PLC that runs the broker **and** publishes runs both blocks - one
to be the broker, one to be a client of it. See [11 Broker](11-broker.md).

## The whole set

| | |
| --- | --- |
| [01 What it is](01-what-it-is.md) | brokers, clients, topics, QoS, retained messages and wills |
| [02 Getting started](02-getting-started.md) | six steps to a working device |
| [03 The client block](03-the-node-block.md) | transports, security, versions, the option structures, logins |
| [04 Publishing](04-publishing.md) | `Publish`, `Report` with a deadband, and a whole STRUCT with `PublishStruct` |
| [05 Subscribing](05-subscribing.md) | `Subscribe` with a quality, `Message`, `SubscribeStruct`, `Request` and `Response` |
| [06 Diagnostics](06-diagnostics.md) | `Statistics`, and the full result table |
| [07 Block reference](07-block-reference.md) | every block, every pin, every method |
| [08 Patterns](08-patterns.md) | worked examples, habits, and what bites people |
| [09 Troubleshooting](09-troubleshooting.md) | by symptom |
| [10 Scan rate](10-scan-rate.md) | the client's own task, and why it matters |
| [11 Broker](11-broker.md) | the PLC as the site broker |
| [12 Bridge](12-bridge.md) | carrying topics between two brokers |
| [13 Provisioning](13-provisioning.md) | a PLC that gets its own login from a modbee broker, by itself |
| [14 Sparkplug](14-sparkplug.md) | SCADA over Sparkplug B: the node, metrics, writes, Live Demand, time, outage history and daily totals |
| [15 Record](15-sparkplug-record.md) | `sp.Record`: a whole STRUCT by point list - classes, options, metric names |
| [Migrating from 0.1](migrating-from-0.1.md) | every 0.1.x block and pin, and where it went |

## How a method behaves

Two kinds, the PLCopen ones:

- **A request** - `Publish`, `Request`, the host's `Write` - starts on a
  rising edge of `bExecute` and takes its inputs at that edge. It returns
  `E_MqttResult.Queued` while it runs, then `Ok` or the reason it failed,
  held until the next edge. Not connected at the edge: `NotConnected` at once,
  never queued for later.
- **A standing method** - everything else - is called every scan while it is
  wanted. `Ok` means its record is valid. Its inputs may change while it runs.
  While there is no connection it returns `NotConnected` and keeps the record.

Every method returns an `E_MqttResult`, and its other answers are outputs read
with `=>`. A call is found again by the variable it is about - its declared
name and type - so it keeps its state from scan to scan with no instance of
its own.

## The protocol underneath

This library is a thin layer over `modbee-mqtt`, a clean-room MQTT 3.1.1 and
5.0 implementation written from the OASIS standards. It holds no protocol
logic of its own: the blocks translate pins into calls and calls into pins.

Nothing in it blocks. `connect()` does not wait for the broker - it starts the
attempt and a later scan says whether it arrived. That is what makes MQTT safe
inside a scan cycle, and it is why the library was written rather than
borrowed.

**Next:** [01 What it is](01-what-it-is.md)
