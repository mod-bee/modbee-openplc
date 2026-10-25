# Publishing

Two blocks. `MQTT_REPORT` for a value that changes, `MQTT_PUBLISH` for an
event that happens.

## A value that changes

```
level( CLIENT := net,
       TOPIC := 'plant/intake/level',
       VALUE := rTankLevel,
       DEADBAND := 0.05,
       PERIOD := T#1m,
       RETAINED := TRUE );
```

Standing — no `REQ`, no edge to arrange. It watches the variable and publishes
when it is worth publishing.

**The two timing pins are the point of the block, and they work together.**

`DEADBAND` is how far the value must move before that is worth a message. A
level transmitter that jitters by 0.02 m is not telling you anything, and
publishing that four times a second for a year is thirty million messages
nobody reads. Set it to the smallest change an operator would act on.

`PERIOD` sends it anyway after that long, unchanged. **Leaving this
at 0 is the mistake worth avoiding.** A value that never moves publishes
nothing, and a consumer cannot tell that from a device that has died — it just
sees silence. Set it to a minute or two and the silence becomes meaningful,
which is exactly what lets the subscribing end run a quality on it (page 05).

Deadband is measured on the number, so it has no meaning for a `STRING`: there
any change at all is a change, and `PERIOD` still applies.

## An event that happens

```
alarm( CLIENT := net,
       REQ := bHighLevelAlarm,
       TOPIC := 'plant/intake/alarm',
       VALUE := iAlarmCode,
       QOS := 2 );
```

Acted on the **rising edge** of `REQ`. Holding it true does not send
repeatedly.

| | |
| --- | --- |
| `BUSY` | a level: out and not yet concluded |
| `DONE` | **one scan**, when the broker has it |
| `ERROR` | **one scan**, when it did not |

`DONE` means different things at different QoS, and that difference is the
whole point of the pin. At QoS 0 it means the bytes left this device. At QoS 1
the broker acknowledged them. At QoS 2 the broker acknowledged them exactly
once and the four-packet handshake completed. Interlock on `DONE` at QoS 1 or
2 and you have a delivery receipt; at QoS 0 you have a despatch note.

Latch `DONE` if a slower task has to see it.

## One value pin, of your own type

There is no type selector and no per-type pin. `VALUE : ANY` takes the
variable itself and its declared type is what travels:

| ST type | on the wire |
| --- | --- |
| `BOOL` | `true` / `false` |
| `INT`, `DINT`, `SINT`, `LINT` | `42` |
| `UINT`, `WORD`, `BYTE`, `DWORD` | `42` |
| `REAL` | `23.5` — seven significant figures, which is what a float carries |
| `LREAL` | `23.5` — fifteen |
| `STRING` | its text |

**Text, not raw bytes**, and deliberately. A dashboard, a Node-RED flow, a
Python script and `mosquitto_sub` all read `23.5`; none of them agree on what
four raw bytes mean and half would get the byte order wrong.

**The text of a STRING is published, never its IEC representation.** Worth
naming because a competing platform gets this wrong and documents it: passing
a string as a raw payload there sends the four header bytes every IEC 61131
string carries, plus a trailing NUL. Anybody who has debugged that once does
not want to meet it again.

A type the wire cannot carry — a structure, an array, a `TIME` — is refused
with `MQTT_INVALID_ARGUMENT` rather than guessed at. A wrong number on a SCADA
screen is worse than no number.

## Retain, and when not to

`RETAINED := TRUE` keeps the message on the broker, so anything subscribing
later is told immediately instead of waiting for the next change.

The pin is `RETAINED` rather than MQTT's own word `RETAIN` for one reason:
`RETAIN` is a reserved keyword in Structured Text — `VAR RETAIN` is how a
variable survives a power cycle — so a pin of that name cannot be declared.

**Retain what describes a state.** A level, a setpoint, a mode, an
online/offline flag. A SCADA screen opened at three in the morning shows the
plant instead of blank fields.

**Do not retain an event.** A retained "pump started" keeps announcing
something that happened last Tuesday to everything that connects, for ever.
Alarms, commands and counters are events.

To withdraw a retained value, publish an empty message to the same topic with
retain on. That is MQTT's delete.

## Choosing a QoS

| | when |
| --- | --- |
| 0 | a reading published often. The next one is along shortly |
| 1 | something you would rather have twice than lose — a totaliser |
| 2 | something where twice and never are both wrong — a command |

QoS costs round trips, and QoS 2 costs four packets per message. On a cellular
link that is real money. Publish readings at 0 and commands at 2.

## A whole STRUCT, one block

```
pubAll( CLIENT := mqtt, BASE := 'plant/intake', DATA := stIntake,
        MODE := MQTT_ON_CHANGE, PERIOD := T#1m, RETAINED := TRUE );
```

Every member of `stIntake` becomes its own topic under `BASE`, published only
when it moves:

```
TYPE S_INTAKE : STRUCT        plant/intake/LEVEL
  LEVEL   : REAL;             plant/intake/FLOW
  FLOW    : REAL;             plant/intake/RUNNING
  RUNNING : BOOL;             plant/intake/TAG
  TAG     : STRING(16);
END_STRUCT END_TYPE
```

**Fifty setpoints become one block.** In ST you could loop; in ladder there is
no `FOR`, so the alternative is fifty rungs.

**The member name IS the topic**, so the STRUCT declaration is the topic
scheme. Rename a member and you rename a topic — worth knowing before the
third device is commissioned.

**A member the wire cannot carry is refused, not skipped quietly.** An array, a
nested STRUCT, a `TIME`: counted on `SKIPPED` and named on `STATUS`. A member
silently missing from a payload is the kind of fault that survives
commissioning and turns up months later in an argument about whose data is
wrong.

**There is no `DEADBAND` here, deliberately.** One number covering fifty
members of mixed types is a trap: a `BOOL` counts as 1.0, so a deadband above
that would freeze every bit in the struct — including a `FAULT` — until the
interval rescued it, and a counter moving by one would go the same way. Where a
member needs a deadband it gets an `MQTT_REPORT` of its own, which is one point,
one unit and one declared type, all visible on the rung. The two blocks coexist
happily on one client.

**`MODE` is the pin that matters here**, and it is worth matching to the data:

| | |
| --- | --- |
| `MQTT_ON_CHANGE` | setpoints, commands, states — things that move when somebody moves them. `PERIOD` is then the heartbeat that keeps the far end's `QUALITY` good while nothing happens |
| `MQTT_ON_INTERVAL` | analogues that never stop moving. A wet well level changes every scan, so on-change would publish at the task rate — send the set on a clock instead |
| `MQTT_ON_REQUEST` | a recipe download. `REQ` sends the **whole** set, changed or not, so the receiving end gets something complete to act on rather than the three values that happened to differ |

`MQTT_ON_INTERVAL` with `PERIOD := T#0s` is refused with
`MQTT_INVALID_ARGUMENT` rather than turned into "every scan" — fifty topics at
the task rate is how a broker falls over.

## One instance, many topics

A block holds no slot index. Its state is keyed by the topic it was given, so
one instance called several times in a scan is several publishes:

```
report( CLIENT := net, TOPIC := 'plant/intake/level',    VALUE := rLevel );
report( CLIENT := net, TOPIC := 'plant/intake/flow',     VALUE := rFlow );
report( CLIENT := net, TOPIC := 'plant/intake/pressure', VALUE := rPressure );
```

Three reports, each with its own last value and its own deadband, on one
block's memory. Called more than once, the block's outputs describe the last
call.

**Next:** [05 Subscribing](05-subscribing.md)
