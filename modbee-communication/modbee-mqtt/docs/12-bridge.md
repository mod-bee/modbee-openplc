# The bridge

`FB_MqttBridge` carries topics between two brokers. Standalone - it owns both
connections and takes no client. The OpenPLC Runtime only.

```st
bridge(bEnable := TRUE,
       sLocalHost := '127.0.0.1',
       sRemoteHost := 'mqtt.example.com',
       eRemoteSecurity := E_MqttSecurity.TlsVerify,
       sRemoteUserName := 'site7', sRemoteUserPassword := sPassword,
       sBridgeName := 'site7',
       sTopic := 'plant/#', eDirection := E_MqttDirection.Out,
       eQos := E_MqttQos.AtLeastOnceDelivery,
       sRemotePrefix := 'sites/site7/');
```

## It is not a client either

Like `FB_MqttBroker`, `FB_MqttBridge` takes no client - but for a different
reason. It **owns two clients of its own**, one per side, and its identifiers
come from `sBridgeName`. What it carries is decided by its rules, not by
publish calls.

A PLC that bridges and also publishes runs an `FB_MqttClient` of its own beside
it, pointed at whichever broker it wants to talk to.

## What it is for

One connection out of a site instead of twenty. The local broker holds the
site; the bridge carries an agreed subset upstream and brings commands back.

The two sides are configured separately because they are genuinely different.
A site broker on the same switch needs no TLS. The link out of the building
always does. Two security pins rather than one: `eLocalSecurity` and
`eRemoteSecurity`.

## Prefixes

`sTopic` is the topic filter **without either prefix**. The prefixes are what
each side actually sees.

With `sTopic := 'plant/#'`, an empty `sLocalPrefix` and
`sRemotePrefix := 'sites/site7/'`:

```
local   plant/intake/level
remote  sites/site7/plant/intake/level
```

That is how ten sites share one upstream broker without colliding, and how the
upstream end can subscribe to `sites/+/plant/+/level` and get every site's
intake level in one go.

## Direction

| `E_MqttDirection` | |
| --- | --- |
| `Out` | local to remote. Readings going upstream |
| `In` | remote to local. Commands and setpoints coming down |
| `Both` | both |

Prefer an `Out` and an `In` rule over one `Both` unless you mean it. A topic
tree carried both ways is the shape that loops.

## One instance, many rules

Call the same instance several times in a scan, each with a different
`sTopic`, and each call adds a rule. The connection pins are read when it
starts:

```st
bridge(bEnable := TRUE, sLocalHost := '127.0.0.1', sRemoteHost := 'mqtt.example.com',
       sBridgeName := 'site7',
       sTopic := 'plant/#', eDirection := E_MqttDirection.Out,
       eQos := E_MqttQos.AtLeastOnceDelivery, sRemotePrefix := 'sites/site7/');
bridge(bEnable := TRUE, sTopic := 'cmd/#', eDirection := E_MqttDirection.In,
       eQos := E_MqttQos.ExactlyOnceDelivery, sRemotePrefix := 'sites/site7/');
```

The rules are collected on the first scan and the connections built on the
second, which is why a rule called later in the program still arrives before
either end connects. A rule repeated in a scan is one rule. **Once started the
rules are fixed**: a changed `sTopic` takes effect when `bEnable` goes FALSE
and TRUE.

## A mapping that would loop is refused

Two rules that carry this bridge's own output back into it are a message storm
that takes a broker down. At 5.0 the **No Local** subscription option prevents
it outright - the bridge does not receive its own publishes. Where the version
cannot express that, the configuration is **rejected at start** with
`E_MqttResult.InvalidArgument` rather than accepted and regretted.

## Retain across a bridge

`bForwardRetained` is **FALSE by default** and that is usually right. A
retained message that crosses a bridge outlives the link that carried it, and a
stale reading sitting on a head-office dashboard is worse than no reading at
all - nobody can tell it is three days old.

Turn it on for values where the upstream end genuinely needs the last known
state on connecting, and pair it with presence (`stWillConfig` on the
publishing client) so the age is knowable.

## Reading it

| | |
| --- | --- |
| `eBridgeState` | `Idle`, `Connecting`, `Up` or `Degraded` |
| `bLocalUp` / `bRemoteUp` | each end |
| `nForwardedOut` / `nForwardedIn` | running totals carried |
| `nRefusedOut` / `nRefusedIn` | the far side would not take it |

**`E_MqttBridgeState.Degraded` is the state worth alarming on.** One end is
connected and the other is not, so half the traffic flows and the other half
piles up - which from the site looks like everything working and from head
office looks like the site has died. Neither end sees it; this pin does.

## Client identifiers

`sBridgeName` (empty for `'bridge'`) becomes part of both client identifiers,
and they **must differ**. `[V5:MQTT-3.1.4-3]` means a bridge using one
identifier for both ends would take over its own session the moment both
brokers turned out to be the same box - which happens on a bench more often
than you would think.

## What it refuses, and why

Three things are refused at start rather than half-applied. Each sets `bError`
with `eErrorId := E_MqttResult.InvalidArgument`.

**No rules.** A bridge with no `sTopic` is two connections and a session on
each broker, carrying nothing, and looking healthy on every pin. Call the block
at least once with a topic.

**`E_MqttSecurity.TlsPinned` on either side.** Pinning needs a key, and this
block has nowhere to keep one - `FB_MqttClient` has `bTrustNew` and its own
retained key for that. Refused rather than quietly falling back to
`TlsVerify`, which would mean trusting every public CA when the engineer asked
for exactly one broker.

**A mapping that would loop**, above.

## Runtime only

A bridge is two simultaneous connections - two sessions, two send queues, and
usually TLS on one of them to a cloud broker. On an ESP32 that is most of the
heap before the program gets any, so this is a Runtime block; on a board it
sets `bError` with `InvalidArgument` rather than half-building.

**The shape that works on a board** is `FB_MqttBroker` on the panel serving the
line, and the bridge upstream running on a Runtime. A board can be the broker
- see [11 Broker](11-broker.md) - and it is the Runtime that carries the site
out of the building.

---

**Next:** [13 Provisioning](13-provisioning.md)
