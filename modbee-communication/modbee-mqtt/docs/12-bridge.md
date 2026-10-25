# The bridge

`MQTT_BRIDGE` carries topics between two brokers. Standalone — it owns both
connections and takes no `CLIENT`.

```
bridge( ENABLE := TRUE,
        LOCAL_HOST := '127.0.0.1',
        REMOTE_HOST := 'mqtt.example.com',
        REMOTE_SECURITY := MQTT_TLS_VERIFY,
        REMOTE_USER := 'site7', REMOTE_PASSWORD := sPassword,
        BRIDGE_NAME := 'site7',
        TOPIC := 'plant/#', DIRECTION := MQTT_OUT, QOS := 1,
        REMOTE_PREFIX := 'sites/site7/' );
```

## It is not a client either

Like `MQTT_BROKER`, `MQTT_BRIDGE` has no `CLIENT` pin — but for a different
reason. It **owns two clients of its own**, one per side, and its identifiers
come from `BRIDGE_NAME`. What it carries is decided by its rules, not by
publish blocks.

A PLC that bridges and also publishes runs an `MQTT_CLIENT` of its own beside
it, pointed at whichever broker it wants to talk to.

## What it is for

One connection out of a site instead of twenty. The local broker holds the
site; the bridge carries an agreed subset upstream and brings commands back.

The two sides are configured separately because they are genuinely different.
A site broker on the same switch needs no TLS. The link out of the building
always does. Two `SECURITY` pins rather than one.

## Prefixes

`TOPIC` is the topic filter **without either prefix**. The prefixes are what
each side actually sees.

With `TOPIC := 'plant/#'`, an empty `LOCAL_PREFIX` and
`REMOTE_PREFIX := 'sites/site7/'`:

```
local   plant/intake/level
remote  sites/site7/plant/intake/level
```

That is how ten sites share one upstream broker without colliding, and how the
upstream end can subscribe to `sites/+/plant/+/level` and get every site's
intake level in one go.

## Direction

| | |
| --- | --- |
| `MQTT_OUT` | local to remote. Readings going upstream |
| `MQTT_IN` | remote to local. Commands and setpoints coming down |
| `MQTT_BOTH` | both |

Prefer two `MQTT_OUT` and `MQTT_IN` rules over one `MQTT_BOTH` unless you mean
it. A topic tree carried both ways is the shape that loops.

## One instance, many rules

Call the same instance several times before it starts, each with a different
`TOPIC`, and each call adds a rule. The connection pins are read from the
first call:

```
bridge( ENABLE := TRUE, LOCAL_HOST := ..., REMOTE_HOST := ..., BRIDGE_NAME := 'site7',
        TOPIC := 'plant/#', DIRECTION := MQTT_OUT, QOS := 1,
        REMOTE_PREFIX := 'sites/site7/' );
bridge( ENABLE := TRUE, TOPIC := 'cmd/#', DIRECTION := MQTT_IN, QOS := 2,
        REMOTE_PREFIX := 'sites/site7/' );
```

The rules are collected on the first scan and the connections built on the
second, which is why a rule added later in the program still arrives before
either end connects.

## A mapping that would loop is refused

Two rules that carry this bridge's own output back into it are a message storm
that takes a broker down. At 5.0 the **No Local** subscription option prevents
it outright — the bridge does not receive its own publishes. Where the version
cannot express that, the configuration is **rejected at start** with
`MQTT_INVALID_ARGUMENT` rather than accepted and regretted.

That is a real answer rather than a formality: the library names the two
filters that would feed each other.

## Retain across a bridge

`FORWARD_RETAIN` is **off by default** and that is usually right. A retained
message that crosses a bridge outlives the link that carried it, and a stale
reading sitting on a head-office dashboard is worse than no reading at all —
nobody can tell it is three days old.

Turn it on for values where the upstream end genuinely needs the last known
state on connecting, and pair it with `MQTT_PRESENCE` so the age is knowable.

## Reading it

| | |
| --- | --- |
| `STATE` | idle, connecting, up, or degraded |
| `LOCAL_UP` / `REMOTE_UP` | each end |
| `FORWARDED_OUT` / `FORWARDED_IN` | running totals carried |
| `REFUSED_OUT` / `REFUSED_IN` | the far side would not take it |

**`MQTT_BRIDGE_DEGRADED` is the state worth alarming on.** One end is
connected and the other is not, so half the traffic flows and the other half
piles up — which from the site looks like everything working and from head
office looks like the site has died. Neither end sees it; this pin does.

## Client identifiers

`NAME` becomes part of both client identifiers, and they **must differ**.
`[V5:MQTT-3.1.4-3]` means a bridge using one identifier for both ends would
take over its own session the moment both brokers turned out to be the same
box — which happens on a bench more often than you would think.

## What it refuses, and why

Three things are refused at start rather than half-applied. Each sets `ERROR`
with `STATUS := MQTT_INVALID_ARGUMENT`.

**No rules.** A bridge with no `TOPIC` is two connections and a session on each
broker, carrying nothing, and looking healthy on every pin. Call the block at
least once with a topic.

**`MQTT_TLS_PINNED` on either side.** Pinning needs a key, and this block has
no pin to put one on — `MQTT_CLIENT` has `PINNED_KEY` and `TRUST_NEW` for that.
Refused rather than quietly falling back to `MQTT_TLS_VERIFY`, which would mean
trusting every public CA when the engineer asked for exactly one broker.

**A mapping that would loop.** Two rules that would carry this bridge's own
output back into it are a message storm that takes a broker down. At 5.0 the
No Local subscription option prevents it outright; where the version cannot
express that, the configuration is rejected at start rather than accepted and
regretted.

## Runtime only

A bridge is two simultaneous connections — two sessions, two send queues, and
usually TLS on one of them to a cloud broker. On an ESP32 that is most of the
heap before the ladder logic gets any, so this is a Runtime block and says so
on its pins rather than half-building.

**The shape that works on a board** is `MQTT_BROKER` on the panel serving the
line, and the bridge upstream running on a Runtime. A board can be the broker
now — see [11 Broker](11-broker.md) — and it is the Runtime that carries the
site out of the building.

---

**Back to** [the index](README.md).
