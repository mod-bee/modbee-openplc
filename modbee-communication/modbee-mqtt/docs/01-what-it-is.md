# What it is

MQTT is how a device tells the rest of the plant what it knows, without either
end having to be told about the other.

## The broker in the middle

Modbus is a conversation: a client asks a device a question and the device
answers. Both ends must know the other exists, and the client must know what
to ask for and when.

MQTT is a noticeboard. A device **publishes** what it knows to a **broker**,
and anything that cares **subscribes** to it. Neither end knows the other
exists. Add a second SCADA screen and no PLC changes. Replace a sensor with a
different make and nothing downstream notices.

```
   plc-intake  ──publish──►  ┌────────┐  ──►  scada screen
   plc-dosing  ──publish──►  │ BROKER │  ──►  historian
   a flow meter ─publish──►  └────────┘  ──►  an alarm dialler
```

The broker is a piece of software — Mosquitto on a plant server, a cloud
service, or this PLC itself (page 11). Everything else is a **client**, and
that includes SCADA: there is no master here, only publishers and subscribers.

## Topics

A topic is a label, written like a file path:

```
plant/line3/tank-01/level
```

Nothing enforces the shape — the broker has no list of valid topics and you
invent them. That freedom is the trap, so decide a naming scheme early and
write it down; the hierarchy is what makes wildcards useful later.

A subscriber may use **wildcards**:

| | |
| --- | --- |
| `plant/line3/+/level` | one level: every tank on line 3 |
| `plant/line3/#` | the rest: everything under line 3 |

`+` and `#` are for subscribing only. A topic you publish to is always exact.

## Quality of service

How hard the broker and client work to deliver one message.

| | |
| --- | --- |
| **QoS 0** | sent once, never retried. Might not arrive |
| **QoS 1** | arrives, and may arrive twice |
| **QoS 2** | arrives exactly once, at the cost of four packets |

Pick by what a lost or repeated message would cost. A level reading published
every second is QoS 0 — the next one is along shortly. A command to start a
pump is QoS 2, because "twice" and "not at all" are both wrong. A totaliser
reading is QoS 1: you would rather have it twice than lose it.

## Retained messages

An ordinary message reaches whoever is subscribed **at that moment**. Anybody
subscribing a second later hears nothing until the next one.

Publish with **retain** and the broker keeps the last one, handing it to every
new subscriber immediately. A SCADA screen that opens at three in the morning
shows the current tank level instead of a blank field.

Retain the things that describe a state. Do not retain events — a retained
"pump started" is a message that keeps announcing an event that happened last
Tuesday.

## Wills, and how silence is read

Here is the problem MQTT has that Modbus does not. You subscribe to a topic
and hear nothing. Is the device dead, or has it simply nothing new to say?

The **Will** answers it. When a client connects it hands the broker a message
to publish *on its behalf* if the connection ever dies without a proper
goodbye — a power cut, a pulled cable, a modem that lost coverage. Pair it
with a message published on connecting and a subscriber always knows:

```
plant/tank-01/status  =  "online"    published by the device
plant/tank-01/status  =  "offline"   published by the broker, when it vanishes
```

`MQTT_PRESENCE` is that pair, and it is one block.

## What this library adds

The protocol carries bytes. A PLC needs a little more:

- **Data quality.** A number that arrived four seconds ago and a number that
  arrived four hours ago look identical on a wire. `MQTT_SUBSCRIBE` puts an
  age and a quality beside every value.
- **Report by exception.** `MQTT_REPORT` publishes a variable when it moves
  by more than a deadband, and at worst every so often — so a noisy analogue
  input does not fill the broker, and a value that never moves still proves
  the device is alive.
- **Nothing blocks.** Not connecting, not publishing, not reconnecting. A
  scan cycle never waits on a network.

## When not to use it

**Deterministic control between two PLCs.** MQTT has a broker in the middle
and no timing guarantee at all. Use Modbus or BeeBus for an interlock.

**Request and response.** MQTT 5.0 can do it and `MQTT_REQUEST` is there, but
if most of your traffic is questions and answers you want Modbus.

MQTT is for telling the plant what you know. It is very good at that, and it
is the wrong tool for making something happen in the next ten milliseconds.

**Next:** [02 Getting started](02-getting-started.md)
