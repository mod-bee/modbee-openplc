# Patterns

Worked shapes, and the habits that make them work.

## The two-task split

The one thing worth doing on every project.

```
NET_TASK  T#50ms  prio 20   PROGRAM netrun  ->  net( ... ); and every block given net
APP_TASK  T#20ms  prio 0    PROGRAM main    ->  the machine, no communication blocks
```

The two trade values through globals, each written by one task. Page 10 has the
numbers; the short version is that the node only notices things when it is
called, so its interval is the floor on how quickly anything happens - and a
block given the node from the machine's task refuses with `MQTT_WRONG_TASK`.
On the Runtime the network task can run at `T#1ms`; on a board, not faster than
`T#50ms`.

## A device that reports itself

The shape most PLCs want. Five blocks.

```
net     ( TRANSPORT := MQTT_RUNTIME_TCP, HOST := BROKER,
          CLIENT_ID := 'plc-intake' );
presence( CLIENT := net, TOPIC := 'plant/intake/status',
          RETAINED := TRUE, DELAY := T#30s );

report  ( CLIENT := net, TOPIC := 'plant/intake/level',
          VALUE := rLevel, DEADBAND := 0.05, PERIOD := T#1m,
          RETAINED := TRUE );
report  ( CLIENT := net, TOPIC := 'plant/intake/flow',
          VALUE := rFlow,  DEADBAND := 0.5,  PERIOD := T#1m,
          RETAINED := TRUE );

status  ( CLIENT := net );
```

One `report` instance, called twice. Each call keeps its own last value and
its own deadband.

## Commanding, and refusing to act on stale data

The commanding end owns the topic and publishes it. The commanded end
subscribes — and checks the quality before doing anything.

```
(* on scada *)
cmd( CLIENT := net, REQ := bSendSetpoint,
     TOPIC := 'plant/intake/cmd/level-setpoint',
     VALUE := rOperatorSetpoint, QOS := 2, RETAINED := TRUE );

(* on plc-intake *)
sp( CLIENT := net, TOPIC := 'plant/intake/cmd/level-setpoint',
    VALUE := rSetpoint, QOS := 2 );

IF sp.QUALITY >= MQTT_QUALITY_UNCERTAIN THEN
  rWorkingSetpoint := rSetpoint;
ELSE
  rWorkingSetpoint := rSafeDefault;
END_IF
```

`RETAINED := TRUE` on the command is what lets the intake PLC pick up the
current setpoint immediately after a restart, rather than running on a default
until the operator happens to change something.

QoS 2 because a setpoint applied twice is usually harmless but a setpoint lost
is not, and the cost is four packets on a value that changes rarely.

## An alarm that is not a retained ghost

```
alarm( CLIENT := net, REQ := bAlarmRising,
       TOPIC := 'plant/intake/alarm',
       VALUE := iAlarmCode, QOS := 2, RETAINED := FALSE );
```

`RETAINED := FALSE` on an event. A retained alarm keeps announcing itself to
everything that connects, for ever, long after the cause is gone.

If you want a dashboard to show the *current* alarm state, publish that as a
separate retained topic holding the state — `plant/intake/alarm-active` as a
`BOOL` — and keep the event topic for events.

## A site that survives its uplink

The PLC is the broker; a bridge carries a subset upstream.

```
broker( ENABLE := TRUE, PORT := 1883, MAX_CLIENTS := 32 );

bridge( ENABLE := TRUE,
        LOCAL_HOST := '127.0.0.1',
        REMOTE_HOST := 'mqtt.example.com',
        REMOTE_SECURITY := MQTT_TLS_VERIFY,
        REMOTE_USER := 'site7', REMOTE_PASSWORD := sPassword,
        BRIDGE_NAME := 'site7',
        TOPIC := 'plant/#', DIRECTION := MQTT_OUT, QOS := 1,
        REMOTE_PREFIX := 'sites/site7/' );

bridge( ENABLE := TRUE, TOPIC := 'cmd/#', DIRECTION := MQTT_IN, QOS := 2,
        REMOTE_PREFIX := 'sites/site7/' );
```

Twenty sensors connect to the PLC, not to head office. The site keeps working
when the uplink does not, and catches up when it returns. One instance of
`bridge`, called twice, is two rules on one pair of connections.

## Drawing these blocks in ladder

Everything on these pages is written in ST because it is shorter to read. In
ladder the same call is a contact, the block, and a variable box on every pin —
and one detail decides how the rung is drawn.

**Twelve of the fifteen blocks take rung power on `EN` and hand it back on
`ENO`.** Every pin is then named, including `ENABLE`:

```
sub( EN := always, CLIENT := net, TOPIC := 'plant/pump-01/cmd/SP',
     VALUE := setpoint, ENABLE := always );
```

**Three do not**, because their first input and their first output are both
`BOOL`, which is how the editor draws a `TON`:

| block | power in | power out |
| --- | --- | --- |
| `MQTT_BROKER` | `ENABLE` | `LISTENING` |
| `MQTT_PUBLISH` | `REQ` | `BUSY` |
| `MQTT_REQUEST` | `REQ` | `BUSY` |

For those three the contact **is** the pin, and the pin on the way out carries
on to the next element:

```
srv( ENABLE := always, LISTEN_ON := '', PORT := 1883, MAX_CLIENTS := 16 );
listening := srv.LISTENING;
```

which is the rung `[always]───[MQTT_BROKER]───(listening)`. It reads the way a
start/stop rung reads, and it is the reason `REQ` is the first pin on
`MQTT_PUBLISH`: a publish request belongs on the rung's own power.

**Name every other pin.** A library block writes only the pins the rung names —
one left out is not defaulted, it is never written at all, so a `QOS` you meant
to set to 1 stays 0 and nothing says so.

## Habits worth keeping

**Give every device its own `CLIENT_ID`.** Two sharing one will knock each
other off for ever, each looking healthy on its own. `MQTT_SESSION_TAKEN_OVER`
is what that looks like from the inside.

**Decide a topic scheme before the second device.** Nothing enforces one, and
retrofitting is a site visit. `site/area/device/measurement` works.

**Always set `PERIOD` on a report.** Without it a value that never
changes is indistinguishable from a device that has died.

**Retain state, never events.**

**Check `QUALITY` before acting on a subscribed number**, and decide what
happens when it is not good. "Hold the last value" and "fail to a safe
default" are both reasonable; "act on it anyway" is not.

**Put the node in its own fast task.**

**Turn `AUTO_RECONNECT` off on cellular**, and reconnect from your own logic
where you can afford the stall.

## What bites people

**A retained value that is older than the device.** A broker will serve a
retained message from something that died last Tuesday and nothing marks it as
old. Pair every publisher with `MQTT_PRESENCE` and subscribe to the status
topic, or you are trusting a ghost.

**`DEADBAND` without `PERIOD`.** Covered above, and the most common
one.

**Publishing every scan.** MQTT has no rate limit and a broker will accept
everything you send it until it falls over. Use `MQTT_REPORT`, not
`MQTT_PUBLISH` on a timer.

**Wildcards in a publish topic.** `+` and `#` are for subscribing. The block
refuses them with `MQTT_INVALID_TOPIC`.

**Expecting request-and-response.** MQTT is a noticeboard. `MQTT_REQUEST`
exists and works at 5.0, but if most of your traffic is questions and answers
you have picked the wrong protocol — use Modbus.

**Assuming QoS 2 means fast.** It means exactly once. It is four packets and
two round trips, and on a cellular link that is noticeable.

**Next:** [09 Troubleshooting](09-troubleshooting.md)
