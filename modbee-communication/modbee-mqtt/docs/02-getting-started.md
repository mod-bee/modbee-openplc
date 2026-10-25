# Getting started

Six steps. At the end a PLC publishes a level, acts on a setpoint, and says so
when it goes offline.

You need a broker. [Mosquitto](https://mosquitto.org) on a plant server is the
usual answer; this PLC can be one itself (page 11).

## 1. Start a node

```
VAR
  net    : MQTT_CLIENT;
  status : MQTT_STATUS;
END_VAR

net( TRANSPORT := MQTT_RUNTIME_TCP,
     HOST      := '10.0.0.20',
     CLIENT_ID := 'plc-intake' );
```

`net` is the client itself, not a handle to it. Every other block takes it on
a `CLIENT` in-out pin, and **that pin must be assigned at every call** — leaving
it out is a compile error rather than a block that quietly does nothing.

`CLIENT_ID` is what the broker calls this device. **Every device on a broker
needs its own.** Two sharing one identifier will knock each other off for
ever, each reconnecting, each looking healthy on its own.

## 2. Give it a task of its own

This is the step people skip, and then wonder why everything feels slow.

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine |
| `NET_TASK` | `T#50ms` on a board, `T#1ms` on the Runtime | `20` | `net` and every block given it |

The node does one poll's worth of work per call — it services the socket,
decodes what arrived, sends what is queued, and returns. It is cheap when
there is nothing to do. But **it only notices things when it is called**, so
its task interval is the floor on how quickly anything happens. Page 10 has
the measured numbers.

**Every block given `net` runs in `net`'s task.** OpenPLC runs each task on a
thread of its own, and a block in another task says `MQTT_WRONG_TASK` and does
nothing rather than race the client. The machine's program trades values with
the network task through globals - page 10 shows how.

## 3. Check it connected

```
status( CLIENT := net );

IF NOT status.CONNECTED THEN
  (* net.LAST_ERROR says why, in the operating system's own words *)
END_IF
```

`CONNECTED` means the broker acknowledged us, not merely that a socket
opened. It is the pin to interlock on.

If it never connects, `net.LAST_ERROR` carries the real reason — "Connection
refused" is a broker that is not running or not on that port; "Name or service
not known" is DNS.

## 4. Publish a value

Not every scan. When it moves:

```
level( CLIENT := net,
       TOPIC := 'plant/intake/level',
       VALUE := rTankLevel,
       DEADBAND := 0.05,
       PERIOD := T#1m,
       RETAINED := TRUE );
```

`VALUE : ANY` takes the variable itself, and its declared type is what
travels: a `REAL` goes as `23.5`, an `INT` as `42`, a `BOOL` as `true`.

`DEADBAND` stops a jittering transmitter filling the broker.
`PERIOD` sends it anyway once a minute, so a value that never changes
still proves the device is alive — which is what lets the other end run a
quality on it. **Setting the first without the second is the common mistake.**

**Every duration on every block is a `TIME`**, so `T#1m` here reads exactly as
`T#1m` on a `TON` in the next rung. Write `T#500ms`, `T#30s`, `T#2h` — whatever
the value is. `T#0s` always means "the sensible default", which each pin names.
Where the protocol itself is coarser — MQTT carries keepalive in whole seconds
— the block rounds up and the pin says so.

## 5. Act on a setpoint

```
sp( CLIENT := net,
    TOPIC := 'plant/intake/cmd/level-setpoint',
    VALUE := rSetpoint,
    EXPECT := T#0s,
    QOS := 1 );

IF sp.QUALITY = MQTT_QUALITY_GOOD THEN
  (* rSetpoint is worth acting on *)
END_IF
```

The value lands in `rSetpoint` directly — there is no copy to keep in step.

`QUALITY` is the pin that makes it safe. `MQTT_QUALITY_UNKNOWN` means nothing
has ever arrived, which is a commissioning fault. `MQTT_QUALITY_BAD` means the
link is down or the value is long overdue, which is a running fault. They send
you to opposite ends of the site, which is why they are different values.

## 6. Say when you are here, and when you are not

```
presence( CLIENT := net,
          TOPIC := 'plant/intake/status',
          RETAINED := TRUE,
          DELAY := T#30s );
```

One block. It publishes `online` every time the connection comes up, and
registers `offline` with the broker to be published if this device ever
vanishes without saying goodbye.

`DELAY := T#30s` stops a marginal radio crying wolf: the broker waits half a
minute before announcing the loss, and a reconnect inside that window cancels
the announcement entirely.

## The whole thing

```
net     ( TRANSPORT := MQTT_RUNTIME_TCP, HOST := '10.0.0.20',
          CLIENT_ID := 'plc-intake' );
presence( CLIENT := net, TOPIC := 'plant/intake/status',
          RETAINED := TRUE, DELAY := T#30s );
level   ( CLIENT := net, TOPIC := 'plant/intake/level', VALUE := rTankLevel,
          DEADBAND := 0.05, PERIOD := T#1m, RETAINED := TRUE );
sp      ( CLIENT := net, TOPIC := 'plant/intake/cmd/level-setpoint',
          VALUE := rSetpoint, QOS := 1 );
status  ( CLIENT := net );
```

Five blocks, all in the network task; `rTankLevel` and `rSetpoint` are globals
the machine's task writes and reads.

Watch it from a desk:

```bash
mosquitto_sub -h 10.0.0.20 -t 'plant/#' -v
```

**Next:** [03 The node block](03-the-node-block.md)
