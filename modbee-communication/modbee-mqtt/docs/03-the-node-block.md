# The node block

`MQTT_CLIENT` owns the connection. It is the only block that touches the
network; everything else queues work and reads pins.

## Call it first

Blocks below it act on the same scan. A block placed above it acts one scan
later, which costs a scan and corrects itself — not fatal, but there is no
reason to let it happen.

## The instance

`net` is the client, not a handle to it:

```
net    ( TRANSPORT := MQTT_RUNTIME_TCP, HOST := '10.0.0.20' );
status ( CLIENT := net );
level  ( CLIENT := net, ... );
```

**The pin must be assigned at every call.** Leaving it out is a compile error,
not a block that silently finds nothing at run time.

An in-out is an alias for your variable rather than a copy, so two things
follow:

- **Read the node's own outputs from the instance** — `net.CONNECTED`, not
  `status.CLIENT.CONNECTED`. Reaching into another block's in-out pin from
  outside is refused.
- **One instance can serve as many blocks as you like** - in the same task as
  the node. A block given the node from another task says `MQTT_WRONG_TASK`
  and does nothing (page 10).

## Two pins decide the link

```
TRANSPORT   where the bytes go
SECURITY    whether they are encrypted
```

They are separate because they are separate questions. One combined list would
make the combinations that do not exist look legal — a Runtime-only transport
with a board-only option, say — and the wrong one would be a silence nobody
could explain.

| `MQTT_LINK` | runs on | pins that matter |
| --- | --- | --- |
| `MQTT_RUNTIME_TCP` | the Runtime | `HOST`, `PORT` |
| `MQTT_ARDUINO_WIFI` | a board | `HOST`, `PORT`, and `MQTT_ARDUINO` |
| `MQTT_ARDUINO_ETHERNET` | a board | `HOST`, `PORT`, and `MQTT_ARDUINO` |
| `MQTT_CELLULAR` | a board | `HOST`, `PORT`, and a `GSM_MODEM` from the `modbee-gsm` library |
| `MQTT_LINK_EXTERNAL` | either | `LINK`, and nothing else |

| `MQTT_SECURITY` | |
| --- | --- |
| `MQTT_PLAIN` | no encryption. Port 1883 |
| `MQTT_TLS_VERIFY` | encrypted, and a **certificate authority** vouches for the broker. Port 8883. What a cloud broker needs |
| `MQTT_TLS_PINNED` | encrypted, and **one key** is trusted. What a plant broker needs, because nobody signed for it |
| `MQTT_TLS_INSECURE` | encrypted, and it is **not** checked |

Choosing a transport the target does not have is reported on `ERROR`,
`STATUS` and `LAST_ERROR` — never built, and never a build failure. *"that
transport needs a board, not the Runtime"* is a sentence you can act on.

`PORT := 0` means the standard one for the security chosen: 1883 or 8883.

### Which `SECURITY` for a board

**A board talking to its own broker** - a site Mosquitto, or a ModBee PLC
broker - uses `MQTT_TLS_PINNED` with `TRUST_NEW`, and a login (`USER` and
`PASSWORD` on `MQTT_CONFIG`). Nothing to install and nothing to define: the
broker's key is learned on the first connection and enforced from then on
(see *About `MQTT_TLS_PINNED`* below). This is the simple default for a site.

`MQTT_TLS_VERIFY` is for a broker somebody signed for - a cloud platform - and
needs that authority's certificate in the board package (see *Defines*).

### TLS on a board

On an ESP32 — the ModBee Node and every other ESP32 board — **every
`SECURITY` works on every `TRANSPORT`**, and works the same way. Wi-Fi,
Ethernet and cellular each open a plain connection, and the TLS runs on the
controller with the mbedTLS the board already carries for its Wi-Fi. So:

- `MQTT_TLS_VERIFY` checks the chain and the host name against the CA in
  `MQTT_CA_CERT_PEM`, a define the board package supplies (see *Defines*).
  Dates are not judged: a controller has no clock to judge them with until
  something sets it.
- `MQTT_TLS_PINNED` and `TRUST_NEW` work exactly as on the Runtime, below.
- `BROKER_KEY` shows the broker's key on every medium.
- Mutual TLS takes the board's own certificate and key from the
  `MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM` defines, also from the
  board package — see `MQTT_TLS`.
- Opening the socket and the handshake run on a short task of their own,
  below the PLC's tasks: the block's task never waits for them, and `STATE`
  says `MQTT_CONNECTING` meanwhile. A plain connection's socket opens the same
  way.

A TLS session holds about 40 kB of memory while it is up and none while it is
down. On a board with PSRAM, the Node included, it is placed there.

Over cellular this replaces the modem's own TLS, which encrypted and checked
nothing. A board **without** that engine keeps what its medium offers:
`WiFiClientSecure` (no `MQTT_TLS_PINNED`), no TLS over Ethernet, and the
modem's TLS (`MQTT_TLS_INSECURE` only).

### About `MQTT_TLS_INSECURE`

It encrypts the traffic and does not check who is at the other end, which
means an encrypted conversation with whoever answered. It is named at length
so nobody selects it by accident, and it is on the node rather than tucked
inside `MQTT_TLS` so the decision is visible in the block that makes the
connection.

Use it to get a link working on a bench. Take it off before the plant runs.

### About `MQTT_TLS_PINNED`

A certificate authority answers *"is this certificate vouched for"*. On a plant
broker nobody vouched for anything — a ModBee PLC serving its own certificate,
or a site Mosquitto somebody generated one for on a Tuesday — so there is no
authority to ask. Pinning trusts **one key** instead, and there is nothing to
type:

```
net( TRANSPORT := MQTT_RUNTIME_TCP,
     SECURITY  := MQTT_TLS_PINNED,
     HOST      := '10.0.0.10',
     PORT      := 8883,
     TRUST_NEW := commissioning );   (* TRUE once, FALSE for ever after *)
```

`TRUST_NEW` TRUE, on a link that has never connected, brings it up unverified
exactly once so the broker's key can be learned. The block keeps it in **its
own retained variable** — no pin to wire, nothing to name, nothing to mistype,
and nothing a user can accidentally un-retain: IEC 61131-3 §6.5.6.2 says a
`RETAIN` declared in a function block type overrides the instance's qualifier.

Turn `TRUST_NEW` off and that key is the pin. A broker showing a different one
is refused - on the Runtime `LAST_ERROR` names both fingerprints, on a board it
reads *TLS: not the pinned key* and `BROKER_KEY` shows the key that was
presented - because the useful question is always which one moved: a broker
that was reinstalled, or an address that is wrong.

`MQTT_BROKER` publishes its own key on `BROKER_KEY`, and the node publishes
what it was shown on `BROKER_KEY` too. Read one, compare with the other.

> **Turn on persistent storage.** The pin is a retained variable, and a project
> without storage configured starts every retained variable at its initial
> value — so the pump relearns the key on every restart, which is not pinning.
> The runtime says so in its log at start.

**Do not pin a cloud broker.** AWS IoT, HiveMQ and the rest rotate every ninety
days, and the key usually rotates with the certificate. Use `MQTT_TLS_VERIFY`
there; it needs no configuration at all.

## Defines come from the board package

A few settings are compile-time defines: `MQTT_CA_CERT_PEM`,
`MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM`, and `MQTT_ENABLE_ETHERNET`.
No limit is one: the tables (topics, subscriptions, Sparkplug metrics and
devices, a Sparkplug host's nodes, broker accounts) grow with the program until
memory runs out, on a board and the Runtime alike, and the sizes that are
settings are pins - `MAX_PENDING` on `MQTT_CONFIG` among them, which nothing
caps but memory. The OpenPLC editor has no per-project
build flags, so a define comes from the **board package** (the VPP): its
compiler flags, as com.modbee.node sets them for the ModBee Node. To change
one, change the board package. Nothing else in this library needs a define.

## Ethernet has to be asked for

Define `MQTT_ENABLE_ETHERNET` in the board package's compiler flags.

This is not fussiness. The Arduino Ethernet library is a *user* library, and
arduino-cli puts one on the include path only when its dependency scanner sees
a plain `#include` for it. A header hidden behind `__has_include` is invisible
to that scanner — so the library can be installed, the guard still reports it
missing, and the block says "install the Arduino Ethernet library" for ever.
WiFi needs no flag because it ships inside the ESP32 core.

## Which version you get

```
PROTOCOL := MQTT_V5_THEN_V311      (* the default *)
```

| | |
| --- | --- |
| `MQTT_V5` | 5.0 only. Refuse anything older |
| `MQTT_V311` | 3.1.1 only |
| `MQTT_V5_THEN_V311` | try 5.0, drop to 3.1.1 if the broker is older |

**Fallback happens only on evidence that the VERSION is the problem** — a 5.0
reason code `0x84`, or a 3.1.1 return code `0x01`. Never on an authentication
failure, never on a network error. Treating those as a version problem would
hide them, and you would spend an afternoon on the wrong thing.

`MQTT_STATUS.VERSION` reports what is actually in force: 5 or 4. Worth putting
on a screen, because a 5.0-only feature quietly unavailable makes much more
sense when that pin says 4.

## The four optional helpers

Eight pins are the whole of an ordinary connection. Everything else lives on
blocks that cost nothing until you place them:

| | |
| --- | --- |
| `MQTT_CONFIG` | keepalive, session, credentials, buffers, reconnect backoff |
| `MQTT_TLS` | the certificate authority, and mutual TLS. A board's CA, and its own certificate, are defines from the board package (`MQTT_CA_CERT_PEM`, `MQTT_CLIENT_CERT_PEM`, `MQTT_CLIENT_KEY_PEM`), because an IEC `STRING` stops at 254 characters and the shortest real PEM is about eight times that |
| `MQTT_ARDUINO` | SSID, MAC, IP — the things only a board has |
| `MQTT_PRESENCE` | the online message and the Will that answers for it |
| `MQTT_PROVISION` | on a modbee broker: the PLC gets its own login, by itself - [13 Provisioning](13-provisioning.md) |

**Place them anywhere in the rung**, above the node or below it. The node
waits one scan before opening its link precisely so that every helper has run
at least once first — which is a rule nobody would remember and the compiler
could not check, so the node takes the scan instead. Opening a socket costs
more than that on its own.

## Credentials

On a modbee broker, the PLC can get its own login instead, and nobody types a
password at all: [13 Provisioning](13-provisioning.md). Otherwise they live on
`MQTT_CONFIG`, and the order matters:

```
tls ( CLIENT := net, CA_FILE := '/etc/ssl/certs/ca-certificates.crt' );
cfg ( CLIENT := net, USERNAME := 'plant-operator', PASSWORD := sPassword );
net ( TRANSPORT := MQTT_RUNTIME_TCP, SECURITY := MQTT_TLS_VERIFY,
      HOST := 'mqtt.example.com', PORT := 8883 );
```

**A user name and password travel in the clear unless `SECURITY` is a TLS
one.** MQTT has no challenge and no hashing: the password is bytes in the
first packet the PLC sends. On a plant segment nobody else is on that may be
fine; on anything that leaves the building it is a password published to
whoever is on the path. Nothing warns you, so pairing them is a habit rather
than a rule the blocks enforce.

**Put the password in a variable, not a literal in the rung.** A literal ends
up in the project file, in every backup of it, and on the screen of whoever
opens the program next.

**A rejected credential stops, and says why.** `ERROR` goes true, `STATUS`
carries `MQTT_NOT_AUTHORIZED`, and `LAST_ERROR` reads *"the broker refused the
connection: Not authorized"* — the broker's own reason rather than a blank
field, which is what it used to be. The node does **not** repeat it at its
usual backoff — a PLC sending a rejected password every second is how a site
gets itself banned — but it does not give up either: it tries again every five
minutes, so a remote site whose broker is fixed at the other end comes back by
itself. `ERROR` stays true while the credential is being refused.

Where the credential really is expected to become valid on its own — a broker
whose access list loads after it starts listening —
`RETRY_REJECTED_CREDENTIAL := TRUE` on `MQTT_CONFIG` turns retrying back on.

## Standing down

`CONNECT := FALSE` disconnects properly — the broker sees a goodbye rather
than a Will — and the object stays. Subscriptions, topic handles and bindings
survive the gap, because the pins that describe them have not changed.

`CONNECT := TRUE` again and it reconnects.

## Changing settings while it runs

Every pin of `MQTT_CLIENT`, and everything `MQTT_CONFIG`, `MQTT_TLS`,
`MQTT_ARDUINO` and `MQTT_PRESENCE` set, is read every scan. A broker address, a
port, the security mode, the login or the client ID changed on an HMI settings
page takes effect at once, without a restart:

1. the client says goodbye on the old settings (a DISCONNECT, so the broker
   does not publish the Will), giving it up to a second to leave;
2. it comes back on the new ones - on a rebuilt connection when `TRANSPORT`,
   `SECURITY`, `HOST`, `PORT`, the TLS files or the board's network settings
   changed, on the same connection when only the CONNECT changed (login,
   `CLIENT_ID`, `PROTOCOL`, keepalive, session, Will).

It is the **same client** either way, so every subscription and every handle
the other blocks hold carries on. `CONNECTED` drops for the moment it takes.

A Wi-Fi login on `MQTT_ARDUINO` that changes makes the client leave the
network and join again with the new one (a radio `NETWORK` brought up is
`NETWORK`'s to rejoin).

**A pinned key stays pinned.** With `MQTT_TLS_PINNED`, a new `HOST` is a new
broker with a different key, and it is refused until `TRUST_NEW` is switched
off and on - exactly as for a broker replaced on purpose. An address typed on a
panel is not a way round the pin.

**Next:** [04 Publishing](04-publishing.md)
