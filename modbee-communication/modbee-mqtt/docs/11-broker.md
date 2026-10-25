# The PLC as broker

`MQTT_BROKER` makes this PLC the broker other devices connect to. It is
standalone — it owns its own listener and takes no `CLIENT`.

```
broker( ENABLE := TRUE, PORT := 1883, MAX_CLIENTS := 32 );
```

## Why put a broker in a PLC

A site with twenty sensors and an intermittent uplink does not want twenty
devices each retrying a connection to head office. Point them at the PLC, let
it hold the retained values and the sessions, and carry one connection
upstream with `MQTT_BRIDGE` (page 12).

What that buys:

- **The site keeps working when the link does not.** Sensors publish, the
  local SCADA screen updates, interlocks run. Nothing notices the uplink is
  down except the bridge.
- **One connection out instead of twenty.** On cellular that is the difference
  between a viable site and an unaffordable one.
- **The retained values are local.** A screen that opens during an outage
  shows the plant, not blank fields.

## On the Runtime and on a board

Both, now. This page used to say "Runtime only, for now": the broker itself was
always platform-neutral — the routing, the retained store, the subscription
registry, session takeover and shared-subscription groups compile anywhere —
and what was missing was an Arduino **listener**, because the two that shipped
used BSD sockets. Two more exist, so an ESP32 running this block is a real
broker and not a stub reporting an error on its pins.

**Serving plain needs nothing installed.** No engine, no certificate, nothing
to configure. WiFi comes with the ESP32 core; Ethernet is opt-in — define
`MQTT_ENABLE_ETHERNET` in the board package's compiler flags, for the same
reason the node block needs it (page 03).

**Five things behave differently on a board**, and none of them silently:

| | |
| --- | --- |
| `LISTEN_ON` | ignored. An Arduino server listens on whatever interface the core brought up; there is no second one to choose between |
| `CERT_FILE`, `KEY_FILE` | **refused**, not ignored. They are paths on a file system, and a board has none this block may assume. Naming one sets `ERROR` rather than quietly serving a different certificate than the pins asked for |
| `BROKER_KEY` | the fingerprint of a certificate made on **this run**. See below |
| the defaults | sized for a panel: four connections, eight sessions, 1 kB buffers, 32 retained. The Runtime's defaults would be tens of kilobytes |
| TLS | needs wolfSSL on the include path. Without it, `SECURITY` other than `MQTT_PLAIN` sets `ERROR`; plain still works |

**The fingerprint moves on every restart on a board.** There is nowhere for
this block to keep a key — no file system it may assume, and a PEM does not fit
in a retained variable — so the certificate is minted fresh each start. Either
re-pin after a reflash, or do the ordinary thing: serve **plain** on an
isolated line, where there is nothing to overhear it, and let a Runtime carry
the site upstream over TLS with [MQTT_BRIDGE](12-bridge.md) — which is a
Runtime block, and is the connection that actually needs encrypting. On the
Runtime the identity is written beside the program and the fingerprint holds.

## Serving TLS

Set `SECURITY` and the broker serves encrypted connections instead of clear
text. With nothing else set it **makes its own certificate on the first start**,
keeps it beside the program, and presents the same one every start after:

```
srv( ENABLE   := always,
     PORT     := 8883,
     SECURITY := MQTT_TLS_VERIFY,
     BROKER_KEY => brokerKey );
```

`BROKER_KEY` is 64 hexadecimal characters — the SHA-256 of the broker's public
key. That is the number every client pins against. Read it once at
commissioning and write it on the panel: it is a fingerprint of the **key**, so
it stays true when the certificate is reissued.

### Where the certificate comes from

| | how | clients use |
| --- | --- | --- |
| nothing on the pins | made here, on the first start | `MQTT_TLS_PINNED` and `BROKER_KEY` |
| `CERT_FILE` + `KEY_FILE` | files on the Runtime, from the site's own CA | `MQTT_TLS_VERIFY`, the ordinary way |

**Self-signed is the zero-configuration default, not a ceiling.** The obstacle
was never the engine — it was that a certificate does not fit on an IEC
`STRING`, and a path does. A public certificate is worth having and painful to
keep: Let's Encrypt renews every ninety days and a PLC is a poor host for a
renewal agent. A long-lived certificate from the site's own CA, or the
self-signed default, are the two shapes that actually work in a plant.

One without the other is refused rather than half applied.

---

## A broker does not publish. Ever.

This catches people out, so it is worth being blunt: **in MQTT a broker has no
topics of its own.** It accepts what clients publish and delivers it to
clients that subscribed. It is a router, not a participant.

That is why `MQTT_BROKER` has no `CLIENT` pin, and why no publish or subscribe
block hangs off it. There is nothing to hang.

**If this PLC should also publish** — its own health, a reading, anything — it
connects to itself as a client, like everything else does:

```
srv ( ENABLE := TRUE, PORT := 1883 );          (* be the broker *)

mqtt( TRANSPORT := MQTT_RUNTIME_TCP,           (* and a client of it *)
      HOST := '127.0.0.1', CLIENT_ID := 'plc-broker' );

pres( CLIENT := mqtt, TOPIC := 'plant/broker/status', RETAINED := TRUE );
rep ( CLIENT := mqtt, TOPIC := 'plant/broker/clients', VALUE := clients,
      PERIOD := T#5s );
```

Two blocks, two roles, and nothing special about it: **everything that
publishes is a client, including the machine hosting the broker.** Put both on
the same fast task.

The example above does exactly this, which is how `plant/broker/clients`
gets onto the bus at all.

## What it enforces

The broker advertises its limits in CONNACK and then holds to them, which is
the part that matters: a client told it may publish 8 kB and then refused at
4 kB has no way to understand what happened.

| | default | |
| --- | --- | --- |
| `MAX_CLIENTS` | 32 | connections served at once |
| sessions | 2× clients | held, including those of clients currently away |
| `MAX_RETAINED` | 256 | retained messages |
| `MAX_SUBSCRIPTIONS` | 32 | subscriptions each client session holds |
| `MAX_QUEUED` | 64 | messages held for a client that is away or slow |
| `MAX_MESSAGE` | 8 kB | maximum packet size, and each connection's buffers |
| `MAX_SESSION_EXPIRY` | 1 h | how long a session outlives its client: a 3.1.1 persistent session, and the most a 5.0 client may ask for |
| receive maximum | 32 | QoS > 0 messages in flight per client |
| maximum QoS | 2 | |

The defaults are the Runtime's. On a board they are sized for a panel: four
connections, eight sessions, 32 retained, 8 subscriptions and 16 queued
messages per session, 1 kB messages. Every one is a pin, so a site that needs
more raises it - within the board's memory: each connection holds two
`MAX_MESSAGE` buffers. Accounts (`MQTT_BROKER_USER`) have no fixed number on a
board; the table grows with the blocks.

**Sessions outnumber connections on purpose.** A plant at three in the morning
is mostly offline sessions — devices asleep, a radio out of coverage — and
holding only as many sessions as there are sockets would expire them the
moment a device slept.

## Reading it

| | |
| --- | --- |
| `LISTENING` | the port is open |
| `CLIENTS` | attached right now |
| `SESSIONS` | held, including absent clients |
| `ACCEPTED` | connections accepted at the socket |
| `CONNECTED` | of those, how many earned a successful CONNACK |
| `REFUSED` | and how many were turned away |
| `PUBLISHED` | messages accepted from clients |
| `DELIVERED` | messages sent to clients |
| `DROPPED` | deliveries a full client queue could not take |
| `TAKEOVERS` | a client identifier claimed by a second connection with the same login |

**`ACCEPTED` climbing while `CONNECTED` does not** means something is opening
sockets and failing the handshake — a port scanner, or a client with bad
credentials retrying. `REFUSED` says how many got as far as a CONNACK - a
client that uses another login with an existing client identifier among them.

**`DROPPED` is not silent.** When a client's queue fills, the drop is counted
here *and* at QoS above 0 the publisher is told with reason `0x97` rather than
being allowed to believe it arrived.

**`TAKEOVERS` is the pin to watch on a new site.** MQTT says a second
connection using an existing client identifier displaces the first, so two
devices flashed with the same identifier knock each other off for ever — each
reconnecting, each looking healthy on its own. This counter is the only place
that is visible from the middle.

**A session belongs to the login that made it.** A client that connects with
another login and an existing client identifier is refused - CONNACK `0x85`
(`0x02` at 3.1.1) - and counts on `REFUSED`, not `TAKEOVERS`: one device cannot
take another's session just by copying its identifier. The same login and the
same identifier take over as before. Without logins every client is the same
nobody, so takeovers work as they always did.

**Sessions expire.** A persistent session (clean session off) of a 3.1.1
client is kept for `MAX_SESSION_EXPIRY` after the client goes - an hour unless
set - then dropped; before, it was kept until the broker restarted. A 5.0
client sets its own expiry, up to the same limit. Raise it for devices that
sleep longer than an hour, and keep in mind that every session held keeps its
queue.

**Refused as the standard says.** A Will topic with wildcards (`0x90`), a Will
declared UTF-8 that is not (`0x99`), a client `PUBLISH` carrying a Subscription
Identifier, two Subscription Identifiers in one `SUBSCRIBE`, No Local on a
`$share` subscription, and a 3.1.1 `CONNECT` with a password but no user name
are refused or disconnected. A 3.1.1 QoS 2 message when the client's inbound
table is full closes the connection, rather than being acknowledged and lost.
Retained messages for a wildcard subscription are sent over several scans, not
all in one.

## Scan cost

Unlike every other block here, this one's cost scales with `CLIENTS`: it
services each connection once per call. Thirty-two clients is thirty-two
socket checks per scan. Still bounded, still non-blocking, not free.

Put it on the fast task with the node. Page 10.

## What it does not do

**No authentication beyond what the library provides.** If the site needs
users and passwords enforced, put Mosquitto on a server and use this PLC as a
client.

**No authentication for TLS client certificates.** The broker can *serve* TLS,
and can require a client certificate on the Runtime, but there is no pin here
for mapping a certificate to a user or a permission. That is the authorisation
hook in the C++ library, not a function block.

**No persistence across a power cut.** Sessions and retained messages are in
RAM. A PLC that loses power loses them, which is legal MQTT and worth knowing.

**Next:** [12 Bridge](12-bridge.md)
