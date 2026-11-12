# Scan rate, and the client's own task

Everything in this library is quick. What decides how quick your MQTT *feels*
is not the library at all - it is how often OpenPLC runs the task the client
block sits in.

## The one rule

> **Put `FB_MqttClient`, its methods and every block given it - Sparkplug,
> firmware updates - in one task of their own, at a lower priority
> than the task that runs the machine. The machine's program trades values
> with them through globals.**

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine |
| `NET_TASK` | `T#50ms` on a board, `T#1ms` on the Runtime | `20` | `FB_MqttClient`, its methods and every block given it |

IEC priority 0 is the highest, so the network task's bigger number means it
never holds the machine back.

**On a board, not faster than `T#50ms`.** OpenPLC stops the PLC when a task is
still in one scan after 10 of its intervals. On a board the client's scans are
long while its link comes up: on a Node UIO over WiFi they reached 52 ms, and
a `T#1ms` network task stopped the PLC in its first scans. `T#50ms` gives a
scan 500 ms. Check each task's longest scan with `openplc-cli debug stats` on
your own link before going faster.

**The connect itself never holds a scan on an ESP32.** Opening the socket - up
to three seconds over Wi-Fi when the broker cannot be reached, longer over a
modem - and the TLS handshake run on a short task of their own, below every
PLC task, and `eConnectionState` says `E_MqttState.Connecting` meanwhile. A board without
threads opens the socket inside the scan, for as long as the medium takes.

**The rule is enforced.** OpenPLC runs every task on a thread of its own - on
the Runtime, and on a board in RTOS mode - and the client is single-threaded by
design. A method called from another task would be inside the client at the
same time as the client's own scan. So every method checks it is in its
block's task, and every Sparkplug block that it is in its client's; in any
other it does nothing and returns (or shows on `eErrorId`)
`E_MqttResult.WrongTask`. It never races and it never waits: a lock that waited was tried, and
on a Node UIO the machine's 20 ms task sat 199 ms behind the network task's
scan until OpenPLC stopped the PLC.

The rest of this page explains why, and what to expect once you have done it.

## Why, exactly

**`FB_MqttClient` is the only block that touches the network, and it does one
poll's worth of work per call.** It reads what the socket has, decodes whole
packets, dispatches them, services the keepalive, drains the send queue, and
returns. Once, then returns.

So **the client's task interval is the floor on how fast anything happens.**

A PLC does not listen continuously. It runs a scan, and between scans it is
not looking at the socket at all. A message does not arrive at your program -
it waits at the door until the client's next call notices it.

- Called every **1 ms**, a message is noticed about a millisecond after it
  lands, and an acknowledgement goes back on the same call.
- Called every **20 ms**, it is noticed up to 20 ms late, and anything that
  needs a round trip pays that twice.

At QoS 2 a publish is a four-packet handshake - PUBLISH, PUBREC, PUBREL,
PUBCOMP. That is **four scans minimum**, whatever the network does. On a 20 ms
task that is 80 ms before `Ok`; on a 1 ms task it is the network's own time
plus about four milliseconds.

**The network is not slow. The scan is.**

## What each call actually does

| | |
| --- | --- |
| `mqtt(...)` | **services the protocol** - receive, decode, acknowledge, transmit, keep-alive, reconnect |
| a method | hands the client a job, or reads a result |

`mqtt.Publish` does not talk to the network. It puts an operation on the
client's queue and returns. The client sends it on its next call, and
`Publish` picks up the outcome whenever it is next called. **Whether that
is one scan later or fifty makes no difference to the answer - it only changes
how soon you see it.**

## The cost when there is nothing to do

Almost nothing. The client checks the transport, finds no bytes, and returns. A
1 ms task holding one client is cheap.

What it is *not* free of is the poll itself, so do not put anything else on
that task. Anything you add there runs a thousand times a second for no
benefit.

## Trading values with the machine

**Declare the client in the network program, never in a global list.** OpenPLC
locks every access to a shared global, and a block instance is one: a machine
task that so much as names a global `FB_MqttClient` waits for the network task to finish
with it - before the method's own task check has run. Measured on a Node UIO with
the client global and one of its calls in the 20 ms task: the broker went away,
the network task's scans stretched while it reconnected, the machine task sat
199 ms behind it and OpenPLC stopped the PLC. `E_MqttResult.WrongTask` stops a race; only
keeping the instance out of the global list stops the wait. Plain values in the
list are fine - each access is a copy.

The client and its calls live in the network task's program; the machine's
program reads and writes **globals**, which OpenPLC already makes safe between
tasks:

```
PLANT, a global variable list:
  rLevel    : REAL;     (* written by main *)
  rSetpoint : REAL;     (* written by netrun *)
```

```st
PROGRAM netrun                       (* NET_TASK *)
  VAR
    mqtt : FB_MqttClient;
  END_VAR
  mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
       sClientId := 'plc-intake');
  mqtt.Report(anyValue := PLANT.rLevel, sTopic := 'plant/intake/level',
              fDeadband := 0.05, tPeriod := T#1m);
  mqtt.Subscribe(anyValue := PLANT.rSetpoint, sTopic := 'plant/intake/setpoint');
END_PROGRAM
```

```st
PROGRAM main                         (* APP_TASK *)
  VAR
    rLevelScaled : REAL;
    rError : REAL;
  END_VAR
  PLANT.rLevel := rLevelScaled;
  rError := PLANT.rSetpoint - PLANT.rLevel;
END_PROGRAM
```

**Each global is written by one task only** - the machine writes what it
measures, the network task writes what arrives. A value that both write is two
owners arguing, whatever the locking.

A Sparkplug block's `fbClient` is an in-out pin carrying the client itself, so
it must be assigned - leaving it out is a compile error rather than a client
that goes missing at run time. Read the client's own outputs from the instance
- `mqtt.bConnected` - in the network task, and hand the machine what it needs
through a global.

## Everything in one task

A program small enough that the machine's logic can run at the network task's
rate needs only one task: the client, its calls and the logic together. It is
the right choice when nothing is timing-critical - a device that publishes
readings and takes the odd command.

The cost is that your logic runs at the client's rate. On the Runtime, with a
`T#1ms` task, put heavy work behind a divider:

```st
divider := divider + 1;
IF divider >= 20 THEN     (* 1 ms task, so this is every 20 ms *)
  divider := 0;
  (* the heavy work *)
END_IF
```

## What the broker and the bridge cost

Every other block in this library costs a constant amount per scan. These two
do not:

- **`FB_MqttBroker`** services each connected client once per call, so its cost
  scales with `nClients`. Thirty-two clients is thirty-two socket checks per
  scan. It is still bounded and still non-blocking, but it is not free, and it
  belongs on the network task rather than anywhere else.
- **`FB_MqttBridge`** polls two clients, so it costs roughly twice a client.

If a PLC is a broker *and* a device, put `FB_MqttBroker` and `FB_MqttClient` in
the same network task. `broker.User` runs in its broker's task the way every
method runs in its block's.

## In a container, check the log before relying on priorities

Setting a real-time priority needs `CAP_SYS_NICE`, which Docker does not grant
by default. The runtime says so and carries on:

```
[task TASK0] SCHED_FIFO(1) failed: Operation not permitted - running default scheduling
```

Add `--cap-add=SYS_NICE` if you want them honoured.

## Rules of thumb

**The network task holds the client and its calls, and nothing of the
machine's.** The machine's task holds no communication block at all.

**Two clients are two independent connections**, each with its own calls.
Both may share the network task.

**A slow task is not a correctness problem.** Nothing is lost, and no
acknowledgement is missed - running totals mean a method cannot miss an outcome
between scans however slowly it is called. It only changes how soon you see
things.

**Next:** [11 Broker](11-broker.md)
