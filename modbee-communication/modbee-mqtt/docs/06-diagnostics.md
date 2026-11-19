# Diagnostics

The client's own pins say whether it is connected and why not:
`mqtt.bConnected`, `mqtt.eConnectionState`, `mqtt.bError`, `mqtt.eErrorId`
and `mqtt.sLastError`. While the link has nothing to report, they also name
the last method call that failed, by method and record -
`Publish DEV.level: InvalidArgument` - while that call keeps failing. It
clears when the same call succeeds, or 10 seconds after its last failure once
the program stops making it (a step that is over, a method switched off), so a
brief failure stays up long enough for a SCADA poll to see it and an old one
does not sit on a link that is working.

The counters are a method, safe to call on any page. It reports and changes
nothing.

```st
mqtt.Statistics(nProtocolVersion => nMqttVersion, nReconnectCount => nMqttReconnects,
                nMessageSentCount => nMqttPublished, nPublishFailureCount => nMqttFailures,
                nProtocolErrorCount => nMqttProtocolErrors, nPendingOperations => nMqttPending);
```

It returns `Ok`, or `NotConnected` while there is no link. The figures are
written either way: they count across outages, and `nReconnectCount` is worth
reading most while the link is down.

## The numbers worth a screen

**`nConnectCount` and `nReconnectCount`.** A link that works but reconnects nightly is
a completely different problem from one that has never worked, and nothing
else on the list tells them apart. An `nReconnectCount` that climbs at the same
time each day is a lease expiring or a scheduled job on the broker. One that
climbs with the weather is a radio.

**`nPublishFailureCount` against `nMessageSentCount`.** A handful during a reconnect is
ordinary. A steady ratio means something is *refusing* messages rather than
losing them - read the result of the method that sends them, which names the
reason.

**`nProtocolVersion`.** 5 or 4, whichever is actually in force. Ask for
`E_MqttProtocol.V5ThenV311` and you may be speaking either; a 5.0-only feature
quietly unavailable makes much more sense when this says 4.

**`nPendingOperations`.** Operations accepted and not yet concluded. A number that climbs
and does not come down is a broker that has stopped acknowledging, or a link
that is saturated.

**`nProtocolErrorCount`.** The broker said something the standard does not allow.
Not zero means one of the two ends has a bug.

**`nLastReasonCode`.** The broker's own last reason code. Zero at 3.1.1 always -
that version has no way to say why.

**`tSinceLastHeard`** on the client. A healthy broker is heard at least once a
keep-alive - it answers our ping - so `bConnected` with `tSinceLastHeard` under three
keep-alives proves the broker is really there, which a modem that only buffers
our bytes cannot fake.

## The full result table

Every method returns an `E_MqttResult`, and every block's `eErrorId` is one.
The values mirror the protocol library's own result codes member for member,
so a program compares names rather than text.

### Accepted - not faults

| | |
| --- | --- |
| `E_MqttResult.Ok` | finished, and it worked |
| `E_MqttResult.Queued` | accepted; the outcome arrives on a later scan |
| `E_MqttResult.Duplicate` | the identical operation is already in flight. **This is what stops a held request flooding the broker** |

### Refused before anything reached the wire

These are your program's mistakes, and being told immediately is the point:
you can fix a bad request, and you cannot tell a bad request from an absent
broker once it has timed out.

| | |
| --- | --- |
| `E_MqttResult.NotInitialised` | the block has not been built yet - a method called before its block's first call, or a Sparkplug metric not yet declared |
| `E_MqttResult.InvalidArgument` | a pin the block cannot use - a type the wire cannot carry, a transport this target does not have |
| `E_MqttResult.InvalidTopic` | the topic failed validation: a wildcard where one is not allowed, an empty level, a `#` that is not last |
| `E_MqttResult.NotConnected` | no link. A request is refused at once, never queued for later; a standing method keeps its record |
| `E_MqttResult.QueueFull` | too much outstanding at once, or a table full - 256 records per client, memory for topics. Never a silent drop |
| `E_MqttResult.Superseded` | a newer write to the same topic replaced it before it went out |
| `E_MqttResult.Cancelled` | discarded: the client disconnected, or a host `Write`'s `bExecute` fell before it could go |
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
| `E_MqttResult.NotAuthorized` | credentials, or an access rule. On a CONNECT it means the broker refused the user name or password, `sLastError` carries the broker's own words, and the client retries only every five minutes - page 09 |
| `E_MqttResult.PayloadFormatInvalid` | we said it was UTF-8 text and it was not |
| `E_MqttResult.QuotaExceededByPeer` | the broker's own limit, not ours |
| `E_MqttResult.PacketIdentifierInUse` | the two ends disagree about what is in flight |
| `E_MqttResult.NoReply` | a `Request` got no answer within `tTimeout` |

### Link faults

| | |
| --- | --- |
| `E_MqttResult.ConnectionLost` | dropped while this was outstanding |
| `E_MqttResult.SessionLost` | dropped, and the session did not survive it |
| `E_MqttResult.ConnectionRefused` | the broker's CONNACK said no |
| `E_MqttResult.ProtocolError` | the broker said something the standard does not allow |
| `E_MqttResult.MalformedPacket` | the broker's bytes did not parse |
| `E_MqttResult.KeepAliveTimeout` | the broker did not answer inside the keep-alive interval |
| `E_MqttResult.SessionTakenOver` | **another connection claimed our client identifier** |

**`E_MqttResult.SessionTakenOver` is the one people meet first on a new site.** MQTT
says a second connection using an existing identifier displaces the first, so
two devices flashed with the same `sClientId` will knock each other off for
ever - each reconnecting, each looking perfectly healthy on its own. Give
every device its own.

**`E_MqttResult.NoMatchingSubscribers` is the most encouraging failure on this
list.** It means the connection works, the broker understood the topic and
accepted the message, and nobody happened to be listening. Everything below
the application layer is fine.

## A health rung

```st
mqtt.Statistics(nProtocolErrorCount => nMqttProtocolErrors, nReconnectCount => nMqttReconnects);
bMqttHealthy := mqtt.bConnected AND (nMqttProtocolErrors = 0)
                AND (mqtt.tSinceLastHeard < T#3m);
```

and somewhere an operator can see `nMqttReconnects`.

**Next:** [07 Block reference](07-block-reference.md)
