# Getting started

Six steps. At the end a PLC publishes a level, acts on a setpoint, and says so
when it goes offline.

You need a broker. [Mosquitto](https://mosquitto.org) on a plant server is the
usual answer; this PLC can be one itself (page 11).

## 1. Start a client

```st
VAR
  mqtt : FB_MqttClient;
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp,
     sHostName      := '10.0.0.20',
     sClientId  := 'plc-intake');
```

`mqtt` is the connection. Call it **once every scan**: that call keeps the
connection, the queues and the timers going. Everything else on this page is
a method of it - `mqtt.Report(...)`, `mqtt.Subscribe(...)` - called after it.

`sClientId` is what the broker calls this device. **Every device on a broker
needs its own.** Two sharing one identifier knock each other off for ever,
each reconnecting, each looking healthy on its own.

## 2. Give it a task of its own

This is the step people skip, and then wonder why everything feels slow.

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine |
| `NET_TASK` | `T#50ms` on a board, `T#1ms` on the Runtime | `20` | `mqtt`, its methods, and every block given it |

The client does one poll's worth of work per call - it services the socket,
decodes what arrived, sends what is queued, and returns. It is cheap when
there is nothing to do. But **it only notices things when it is called**, so
its task interval is the floor on how quickly anything happens. Page 10 has
the measured numbers.

**Its methods run in its task.** OpenPLC runs each task on a thread of its
own, and a method called from another task returns `E_MqttResult.WrongTask`
and does nothing rather than race the client. The machine's program trades
values with the network task through globals - page 10 shows how.

## 3. Check it connected

```st
IF NOT mqtt.bConnected THEN
  sWhy := mqtt.sLastError;   (* the operating system's or the broker's own words *)
END_IF;
```

`bConnected` means the broker acknowledged us, not merely that a socket
opened. It is the pin to interlock on.

If it never connects, `sLastError` carries the real reason - "Connection
refused" is a broker that is not running or not on that port; "Name or service
not known" is DNS.

## 4. Publish a value

Not every scan. When it moves:

```st
mqtt.Report(anyValue  := rTankLevel,
            sTopic    := 'plant/intake/level',
            fDeadband := 0.05,
            tSendInterval   := T#1m,
            bRetain   := TRUE);
```

`anyValue : ANY` takes the variable itself, and its declared type is what
travels: a `REAL` goes as `23.5`, an `INT` as `42`, a `BOOL` as `true`.

`fDeadband` stops a jittering transmitter filling the broker. `tSendInterval` sends
it anyway once a minute, so a value that never changes still proves the device
is alive - which is what lets the other end run a quality on it. **Setting the
first without the second is the common mistake.**

`Report` is a **standing** method: call it every scan, and it decides when a
message is worth sending. There is no edge to arrange.

**Every duration is a `TIME`**, so `T#1m` here reads exactly as `T#1m` on a
`TON` in the next rung. `T#0s` always means "the sensible default", which each
parameter names. Where the protocol itself is coarser - MQTT carries
keep-alive in whole seconds - the block rounds up.

## 5. Act on a setpoint

```st
mqtt.Subscribe(anyValue := rSetpoint,
               sTopic   := 'plant/intake/cmd/level-setpoint',
               eQos     := E_MqttQos.AtLeastOnceDelivery,
               eQuality => eSpQuality);

IF eSpQuality = E_MqttQuality.Good THEN
  rWorkingSetpoint := rSetpoint;   (* worth acting on *)
END_IF;
```

The value lands in `rSetpoint` directly - there is no copy to keep in step.

`eQuality` is what makes it safe. `E_MqttQuality.Unknown` means nothing has
ever arrived, which is a commissioning fault. `E_MqttQuality.Bad` means the
link is down or the value is long overdue, which is a running fault. They send
you to opposite ends of the site, which is why they are different values.

## 6. Say when you are here, and when you are not

```st
VAR
  will : ST_MqttWillConfig := (sTopic := 'plant/intake/status', tWillDelayInterval := T#30s);
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHostName := '10.0.0.20',
     sClientId := 'plc-intake', stWill := will);
```

No extra block: presence is a structure on the client. It publishes `online`
every time the connection comes up, retained, and registers `offline` with the
broker to be published if this device ever vanishes without saying goodbye.

`tWillDelayInterval := T#30s` stops a marginal radio crying wolf: the broker waits half a
minute before announcing the loss, and a reconnect inside that window cancels
the announcement entirely.

## The whole thing

```st
VAR
  mqtt : FB_MqttClient;
  will : ST_MqttWillConfig := (sTopic := 'plant/intake/status', tWillDelayInterval := T#30s);
  eSpQuality : E_MqttQuality;
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHostName := '10.0.0.20',
     sClientId := 'plc-intake', stWill := will);
mqtt.Report(anyValue := PLANT.rTankLevel, sTopic := 'plant/intake/level',
            fDeadband := 0.05, tSendInterval := T#1m, bRetain := TRUE);
mqtt.Subscribe(anyValue := PLANT.rSetpoint, sTopic := 'plant/intake/cmd/level-setpoint',
               eQos := E_MqttQos.AtLeastOnceDelivery, eQuality => eSpQuality);
PLANT.bSetpointGood := eSpQuality = E_MqttQuality.Good;
```

One block and two method calls, all in the network task; `PLANT` is a global
list the machine's task writes `rTankLevel` into and reads `rSetpoint` from.

Watch it from a desk:

```bash
mosquitto_sub -h 10.0.0.20 -t 'plant/#' -v
```

**Next:** [03 The client block](03-the-node-block.md)
