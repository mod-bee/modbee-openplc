# Patterns

Worked shapes, and the habits that make them work.

## The two-task split

The one thing worth doing on every project.

```
NET_TASK  T#50ms  prio 20   PROGRAM netrun  ->  mqtt( ... ); its methods; every block given mqtt
APP_TASK  T#20ms  prio 0    PROGRAM main    ->  the machine, no communication blocks
```

The two trade values through globals, each written by one task. Page 10 has the
numbers; the short version is that the client only notices things when it is
called, so its interval is the floor on how quickly anything happens - and a
method called from the machine's task returns `E_MqttResult.WrongTask`. On the
Runtime the network task can run at `T#1ms`; on a board, not faster than
`T#50ms`.

## A device that reports itself

The shape most PLCs want. One block and a call per value.

```st
VAR
  mqtt : FB_MqttClient;
  will : ST_MqttWillConfig := (sTopic := 'plant/intake/status', tDelay := T#30s);
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'plc-intake', stWillConfig := will);

mqtt.Report(anyValue := PLANT.rLevel, sTopic := 'plant/intake/level',
            fDeadband := 0.05, tPeriod := T#1m, bRetain := TRUE);
mqtt.Report(anyValue := PLANT.rFlow, sTopic := 'plant/intake/flow',
            fDeadband := 0.5, tPeriod := T#1m, bRetain := TRUE);
```

Each `Report` call keeps its own last value and its own deadband, found by its
variable.

## Commanding, and refusing to act on stale data

The commanding end owns the topic and publishes it. The commanded end
subscribes - and checks the quality before doing anything.

```st
(* on scada *)
mqtt.Publish(anyValue := rOperatorSetpoint,
             sTopic   := 'plant/intake/cmd/level-setpoint',
             eQos     := E_MqttQos.ExactlyOnceDelivery,
             bRetain  := TRUE,
             bExecute := bSendSetpoint);
```

```st
(* on plc-intake *)
mqtt.Subscribe(anyValue := rSetpoint, sTopic := 'plant/intake/cmd/level-setpoint',
               eQos := E_MqttQos.ExactlyOnceDelivery, eQuality => eSpQuality);

IF eSpQuality >= E_MqttQuality.Uncertain THEN
  rWorkingSetpoint := rSetpoint;
ELSE
  rWorkingSetpoint := rSafeDefault;
END_IF;
```

`bRetain := TRUE` on the command is what lets the intake PLC pick up the
current setpoint immediately after a restart, rather than running on a default
until the operator happens to change something.

QoS 2 because a setpoint applied twice is usually harmless but a setpoint lost
is not, and the cost is four packets on a value that changes rarely.

## An alarm that is not a retained ghost

```st
mqtt.Publish(anyValue := iAlarmCode, sTopic := 'plant/intake/alarm',
             eQos := E_MqttQos.ExactlyOnceDelivery, bRetain := FALSE,
             bExecute := bAlarmRising);
mqtt.Report(anyValue := bAlarmActive, sTopic := 'plant/intake/alarm-active',
            tPeriod := T#1m, bRetain := TRUE);
```

`bRetain := FALSE` on the event. A retained alarm keeps announcing itself to
everything that connects, for ever, long after the cause is gone.

The dashboard's *current* alarm state is the second call: a separate retained
topic holding the state as a `BOOL`, with the event topic kept for events.

## A site that survives its uplink

The PLC is the broker; a bridge carries a subset upstream.

```st
broker(bEnable := TRUE, nPort := 1883, nMaxClients := 32);

bridge(bEnable := TRUE,
       sLocalHost := '127.0.0.1',
       sRemoteHost := 'mqtt.example.com',
       eRemoteSecurity := E_MqttSecurity.TlsVerify,
       sRemoteUserName := 'site7', sRemoteUserPassword := sPassword,
       sBridgeName := 'site7',
       sTopic := 'plant/#', eDirection := E_MqttDirection.Out,
       eQos := E_MqttQos.AtLeastOnceDelivery,
       sRemotePrefix := 'sites/site7/');

bridge(bEnable := TRUE, sTopic := 'cmd/#', eDirection := E_MqttDirection.In,
       eQos := E_MqttQos.ExactlyOnceDelivery, sRemotePrefix := 'sites/site7/');
```

Twenty sensors connect to the PLC, not to head office. The site keeps working
when the uplink does not, and catches up when it returns. One `bridge`
instance, called twice, is two rules on one pair of connections.

## Drawing these blocks in ladder

Everything on these pages is written in ST because it is shorter to read, and
the methods are ST calls. A ladder program keeps its rungs for the machine and
leaves the MQTT calls to an ST program in the network task, trading values
through globals.

A block itself can sit on a rung. `FB_MqttBroker` takes rung power on
`bEnable` and hands it on from `bListening`, because its first input and its
first output are both `BOOL` - the way the editor draws a `TON`. The others
take power on `EN` and hand it back on `ENO`.

**Name every pin you mean to set.** A block call writes only the pins it
names - one left out keeps the value it last had, its default if nothing set
it - so a QoS you meant to set to 1 stays 0 and nothing says so. A method's
input left out takes its declared default on every call.

## Habits worth keeping

**Give every device its own `sClientId`.** Two sharing one will knock each
other off for ever, each looking healthy on its own.
`E_MqttResult.SessionTakenOver` is what that looks like from the inside.

**Decide a topic scheme before the second device.** Nothing enforces one, and
retrofitting is a site visit. `site/area/device/measurement` works.

**Always set `tPeriod` on a `Report`.** Without it a value that never changes
is indistinguishable from a device that has died.

**Retain state, never events.**

**Check `eQuality` before acting on a subscribed number**, and decide what
happens when it is not good. "Hold the last value" and "fail to a safe
default" are both reasonable; "act on it anyway" is not.

**One variable per call.** A method finds its record by the variable; the same
variable in two `Report` calls is one record pulled two ways.

**Put the client in its own task.**

**Set `stSessionConfig.tMaxSilence` on cellular**, and consider
`bAutoReconnect := FALSE` with your own reconnect logic where you can afford
the stall.

## What bites people

**A retained value that is older than the device.** A broker will serve a
retained message from something that died last Tuesday and nothing marks it as
old. Pair every publisher with presence (`stWillConfig`) and subscribe to the
status topic, or you are trusting a ghost.

**`fDeadband` without `tPeriod`.** Covered above, and the most common one.

**Publishing every scan.** MQTT has no rate limit and a broker will accept
everything you send it until it falls over. Use `Report`, not `Publish` on a
timer.

**Wildcards in a publish topic.** `+` and `#` are for subscribing. A publish
refuses them with `E_MqttResult.InvalidTopic`.

**Expecting `Publish` to wait for the link.** Not connected at the edge is
`NotConnected` at once. The program decides whether to ask again.

**Expecting request-and-response.** MQTT is a noticeboard. `Request` exists
and works at 5.0, but if most of your traffic is questions and answers you
have picked the wrong protocol - use Modbus.

**Assuming QoS 2 means fast.** It means exactly once. It is four packets and
two round trips, and on a cellular link that is noticeable.

**Next:** [09 Troubleshooting](09-troubleshooting.md)
