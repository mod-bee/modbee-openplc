# Diagnostics

One block, no inputs, safe to drop on any page. It reports and changes
nothing.

```
status( CLIENT := net );
```

## The numbers worth a screen

**`CONNECTS` and `RECONNECTS`.** A link that works but reconnects nightly is a
completely different problem from one that has never worked, and nothing else
on the list tells them apart. A `RECONNECTS` that climbs at the same time each
day is a lease expiring or a scheduled job on the broker. One that climbs with
the weather is a radio.

**`PUBLISH_FAILURES` against `PUBLISHED`.** A handful during a reconnect is
ordinary. A steady ratio means something is *refusing* messages rather than
losing them — read `STATUS` on the block that sends them, which names the
reason.

**`VERSION`.** 5 or 4, whichever is actually in force. Ask for
`E_MqttProtocol.V5ThenV311` and you may be speaking either; a 5.0-only feature quietly
unavailable makes much more sense when this pin says 4.

**`QUEUED`.** Operations accepted and not yet concluded. A number that climbs
and does not come down is a broker that has stopped acknowledging, or a link
that is saturated.

**`PROTOCOL_ERRORS`.** The broker said something the standard does not allow.
Not zero means one of the two ends has a bug.

**`REASON_CODE`.** The broker's own last reason code. Zero at 3.1.1 always —
that version has no way to say why.

## The full result table

Every block returns `STATUS`, and the values mirror the protocol library's own
result codes member for member, so a program compares names rather than text.

### Accepted — not faults

| | |
| --- | --- |
| `E_MqttResult.Ok` | finished, and it worked |
| `E_MqttResult.Queued` | accepted; the outcome arrives on a later scan |
| `E_MqttResult.Duplicate` | the identical operation is already in flight. **This is what stops a held REQ flooding the broker** |

### Refused before anything reached the wire

These are your program's mistakes, and being told immediately is the point:
you can fix a bad request, and you cannot tell a bad request from an absent
broker once it has timed out.

| | |
| --- | --- |
| `E_MqttResult.NotInitialised` | the node block has not run |
| `E_MqttResult.InvalidArgument` | a pin the block cannot use — a type the wire cannot carry, a transport this target does not have |
| `E_MqttResult.InvalidTopic` | the topic failed validation: a wildcard where one is not allowed, an empty level, a `#` that is not last |
| `E_MqttResult.NotConnected` | no link, and no session to queue into either |
| `E_MqttResult.QueueFull` | too much outstanding at once. Never a silent drop |
| `E_MqttResult.Superseded` | a newer write to the same topic replaced it before it went out |
| `E_MqttResult.Cancelled` | discarded, usually because the node disconnected |
| `E_MqttResult.NotSupportedByProtocol` | 3.1.1 cannot express this at all |
| `E_MqttResult.NotSupportedByPeer` | 5.0 can, and **this broker said no** |
| `E_MqttResult.PacketTooLarge` | over the broker's stated maximum packet size |
| `E_MqttResult.QuotaExceeded` | our own send quota is exhausted |
| `E_MqttResult.NoPacketIdentifier` | every identifier is in flight |

**`E_MqttResult.NotSupportedByProtocol` and `E_MqttResult.NotSupportedByPeer` are
different on purpose**, because they send you to different places. The first
means upgrade the connection. The second means change the broker's
configuration, or stop asking.

### Concluded on the wire

| | |
| --- | --- |
| `E_MqttResult.Refused` | a failure with no more specific name |
| `E_MqttResult.NoMatchingSubscribers` | delivered nowhere, **which may be fine** |
| `E_MqttResult.TopicNameInvalid` | the broker would not accept that topic |
| `E_MqttResult.NotAuthorized` | credentials, or an access rule. On a CONNECT it means the broker refused the user name or password, `LAST_ERROR` carries the broker's own words, and the node does **not** retry — page 09 |
| `E_MqttResult.PayloadFormatInvalid` | we said it was UTF-8 text and it was not |
| `E_MqttResult.QuotaExceededByPeer` | the broker's own limit, not ours |
| `E_MqttResult.PacketIdentifierInUse` | the two ends disagree about what is in flight |

### Link faults

| | |
| --- | --- |
| `E_MqttResult.ConnectionLost` | dropped while this was outstanding |
| `E_MqttResult.SessionLost` | dropped, and the session did not survive it |
| `E_MqttResult.ConnectionRefused` | the broker's CONNACK said no |
| `E_MqttResult.ProtocolError` | the broker said something the standard does not allow |
| `E_MqttResult.MalformedPacket` | the broker's bytes did not parse |
| `E_MqttResult.KeepAliveTimeout` | no answer inside the interval. Also what a `MQTT_REQUEST` timeout looks like |
| `E_MqttResult.SessionTakenOver` | **another connection claimed our client identifier** |

**`E_MqttResult.SessionTakenOver` is the one people meet first on a new site.** MQTT
says a second connection using an existing identifier displaces the first, so
two devices flashed with the same `CLIENT_ID` will knock each other off for
ever — each reconnecting, each looking perfectly healthy on its own. Give
every device its own.

**`E_MqttResult.NoMatchingSubscribers` is the most encouraging failure on this
list.** It means the connection works, the broker understood the topic and
accepted the message, and nobody happened to be listening. Everything below
the application layer is fine.

## A health rung

```
status( CLIENT := net );

bMqttHealthy := status.CONNECTED AND
                (status.PROTOCOL_ERRORS = 0);

(* and somewhere an operator can see *)
iMqttReconnects := status.RECONNECTS;
```

**Next:** [07 Block reference](07-block-reference.md)
