# Publishing

Three methods of the client. `Report` for a value that changes, `Publish` for
an event that happens, `PublishStruct` for a whole STRUCT.

## A value that changes

```st
mqtt.Report(anyValue  := rTankLevel,
            sTopic    := 'plant/intake/level',
            fDeadband := 0.05,
            tSendInterval   := T#1m,
            bRetain   := TRUE,
            nMessageSentCount     => nLevelSent);
```

Standing - no `bExecute`, no edge to arrange. Call it every scan; it watches
the variable and publishes when it is worth publishing.

**The two timing parameters are the point of it, and they work together.**

`fDeadband` is how far the value must move from the value **last sent** before
that is worth a message, so a slow drift still adds up and goes. A level
transmitter that jitters by 0.02 m is not telling you anything, and publishing
that four times a second for a year is thirty million messages nobody reads.
Set it to the smallest change an operator would act on.

`tSendInterval` sends it anyway after that long, unchanged. **Leaving it at `T#0s` is
the mistake worth avoiding.** A value that never moves publishes nothing, and a
consumer cannot tell that from a device that has died - it just sees silence.
Set it to a minute or two and the silence becomes meaningful, which is exactly
what lets the subscribing end run a quality on it (page 05).

Deadband is measured on the number, so it has no meaning for a `STRING`: there
the text is compared, any change at all is a change, and `tSendInterval` still
applies. A `BOOL` counts as 1.0 or 0.0, so a deadband of 1.0 or more would
freeze one - leave it 0 for anything that is not an analogue. An empty
`STRING` has nothing to send: the call returns `InvalidArgument` until it has
text.

`eTrigger` chooses when:

| | |
| --- | --- |
| `E_MqttTrigger.OnChange` (default) | when it moves by `fDeadband`, and every `tSendInterval` anyway |
| `E_MqttTrigger.OnInterval` | every `tSendInterval`, changed or not. `tSendInterval := T#0s` is refused with `InvalidArgument`, never turned into "every scan" |
| `E_MqttTrigger.OnRequest` | on a rising edge of `bExecute`, and nothing else - no first value, no heartbeat |

`bEnable := FALSE` stops it without losing the record; an edge of `bExecute`
raised meanwhile does not fire on enabling. `nMessageSentCount` counts messages; `tSinceLastSent` is
the time since the last one, `T#0s` before the first, which `nMessageSentCount = 0` tells
apart.

## An event that happens

```st
eAlarmResult := mqtt.Publish(anyValue := iAlarmCode,
                             sTopic   := 'plant/intake/alarm',
                             eQos     := E_MqttQos.ExactlyOnceDelivery,
                             bExecute := bHighLevelAlarm);
```

A request: it acts on the **rising edge** of `bExecute`, and takes its inputs
at that edge. Holding `bExecute` TRUE does not send again.

| it returns | |
| --- | --- |
| `E_MqttResult.Queued` | out and not yet concluded |
| `E_MqttResult.Ok` | the broker has it. Held until the next edge |
| anything else | why not. Held until the next edge |

`Ok` means different things at different QoS, and that difference is the
whole point. At QoS 0 it means the bytes left this device. At QoS 1 the broker
acknowledged them. At QoS 2 the broker acknowledged them exactly once and the
four-packet handshake completed. Interlock on `Ok` at QoS 1 or 2 and you have
a delivery receipt; at QoS 0 you have a despatch note.

**Not connected at the edge is `NotConnected` at once**, and nothing is queued
for later: a command that goes out when the link returns an hour later is
worse than one that never went. A link lost while it was out also ends it with
`NotConnected`. Ask again with a new edge.

```st
IF eAlarmResult = E_MqttResult.Ok THEN
  bAlarmDelivered := TRUE;    (* held until the next rising edge *)
END_IF;
```

## One value parameter, of your own type

There is no type selector and no per-type pin. `anyValue : ANY` takes the
variable itself, or a literal, and its declared type is what travels:

| ST type | on the wire |
| --- | --- |
| `BOOL` | `true` / `false` |
| `INT`, `DINT`, `SINT`, `LINT` | `42` |
| `UINT`, `WORD`, `BYTE`, `DWORD` | `42` |
| `REAL` | `23.5` - seven significant figures, which is what a float carries |
| `LREAL` | `23.5` - fifteen |
| `STRING` | its text |

**Text, not raw bytes**, and deliberately. A dashboard, a Node-RED flow, a
Python script and `mosquitto_sub` all read `23.5`; none of them agree on what
four raw bytes mean and half would get the byte order wrong.

**The text of a STRING is published, never its IEC representation** - not the
header bytes every IEC string carries, not a trailing NUL.

A type the wire cannot carry - a structure, an array, a `TIME` - is refused
with `E_MqttResult.InvalidArgument` rather than guessed at. A wrong number on a
SCADA screen is worse than no number.

## Each call is found by its variable

A method call has no instance of its own. The client keeps one record per
call, found again each scan by **the variable it is about** - `anyValue`'s
declared name and type - and the method. So:

```st
mqtt.Report(anyValue := rLevel,    sTopic := 'plant/intake/level',    tSendInterval := T#1m);
mqtt.Report(anyValue := rFlow,     sTopic := 'plant/intake/flow',     tSendInterval := T#1m);
mqtt.Report(anyValue := rPressure, sTopic := 'plant/intake/pressure', tSendInterval := T#1m);
```

is three reports, each with its own last value and its own deadband. A literal
or an expression has no name, and is found by its topic instead.

**One variable is one record per method.** Reporting the same variable on two
topics is two calls fighting over one record; give each its own variable. A
client holds up to 256 records; past that a method returns `QueueFull`.

## Retain, and when not to

`bRetain := TRUE` keeps the message on the broker, so anything subscribing
later is told immediately instead of waiting for the next change.

**Retain what describes a state.** A level, a setpoint, a mode, an
online/offline flag. A SCADA screen opened at three in the morning shows the
plant instead of blank fields.

**Do not retain an event.** A retained "pump started" keeps announcing
something that happened last Tuesday to everything that connects, for ever.
Alarms, commands and counters are events.

To withdraw a retained value, publish an empty message to the same topic with
retain on - MQTT's delete. An empty `STRING` is that message:

```
sClear := '';
mqtt.Publish(anyValue := sClear, sTopic := 'plant/intake/level', bRetain := TRUE,
             bExecute := bWithdraw);
```

## Choosing a QoS

| `E_MqttQos` | when |
| --- | --- |
| `AtMostOnceDelivery` (0, default) | a reading published often. The next one is along shortly |
| `AtLeastOnceDelivery` (1) | something you would rather have twice than lose - a totaliser |
| `ExactlyOnceDelivery` (2) | something where twice and never are both wrong - a command |

QoS costs round trips, and QoS 2 costs four packets per message. On a cellular
link that is real money. Publish readings at 0 and commands at 2.

## A whole STRUCT, one call

```st
mqtt.PublishStruct(anyData  := stIntake,
                   sBaseTopic    := 'plant/intake',
                   eTrigger := E_MqttTrigger.OnChange,
                   tSendInterval  := T#1m,
                   bRetain  := TRUE,
                   nMembersRefused => nIntakeSkipped);
```

Every member of `stIntake` becomes its own topic under `sBaseTopic`, published only
when it moves:

```
TYPE S_INTAKE : STRUCT        plant/intake/LEVEL
  LEVEL   : REAL;             plant/intake/FLOW
  FLOW    : REAL;             plant/intake/RUNNING
  RUNNING : BOOL;             plant/intake/TAG
  TAG     : STRING(16);
END_STRUCT END_TYPE
```

**Fifty setpoints become one call.** In ST you could loop; this is shorter, and
the record is found by the STRUCT's name like any other.

**The member name IS the topic**, so the STRUCT declaration is the topic
scheme. Rename a member and you rename a topic - worth knowing before the
third device is commissioned.

**A member the wire cannot carry is refused, not skipped quietly.** An array, a
nested STRUCT, a `TIME`: counted on `nMembersRefused`, and the call returns
`InvalidArgument` while the other members still go. A member silently missing
from a payload is the kind of fault that survives commissioning and turns up
months later in an argument about whose data is wrong.

**There is no deadband here, deliberately.** One number covering fifty
members of mixed types is a trap: a `BOOL` counts as 1.0, so a deadband above
that would freeze every bit in the struct - including a `FAULT` - until the
interval rescued it. Where a member needs a deadband it gets a `Report` of its
own. The two coexist happily on one client.

**`eTrigger` is the parameter that matters here**, and it is worth matching to
the data:

| | |
| --- | --- |
| `OnChange` | setpoints, commands, states - things that move when somebody moves them. `tSendInterval` is then the heartbeat that keeps the far end's quality good while nothing happens |
| `OnInterval` | analogues that never stop moving. A wet well level changes every scan, so on-change would publish at the task rate - send the set on a clock instead |
| `OnRequest` | a recipe download. `bExecute` sends the **whole** set, changed or not, so the receiving end gets something complete to act on rather than the three values that happened to differ |

`nMembers` counts the members published, `nMessageSentCount` the messages, and `nMessagesSentThisScan`
those sent by this call.

**Next:** [05 Subscribing](05-subscribing.md)
