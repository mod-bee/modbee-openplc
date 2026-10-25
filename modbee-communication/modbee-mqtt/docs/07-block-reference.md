# Block reference

Every block but `MQTT_CLIENT`, `MQTT_BROKER` and `MQTT_BRIDGE` takes its parent
block on an in-out pin (`CLIENT` for the MQTT blocks, `NODE` for the Sparkplug
blocks) and returns `ERROR` and `STATUS`. **That pin must be
assigned at every call — leaving it out is a compile error.**

`BUSY` is a level. `DONE`, `ERROR` and `NEW_VALUE` are **one scan wide**, so
latch them if a slower task has to see one. `-1` on an age means *never*, which
is not the same as *a long time ago*.

> Generated from each block's own comment; edit the block's comment, not this page.

| Block | What it does |
| --- | --- |
| [`MQTT_ARDUINO`](#mqtt_arduino) | The things only a board has. |
| [`MQTT_BRIDGE`](#mqtt_bridge) | Carries topics between two brokers. |
| [`MQTT_BROKER`](#mqtt_broker) | Makes this PLC the broker other devices connect to. |
| [`MQTT_BROKER_USER`](#mqtt_broker_user) | ONE ACCOUNT ON THIS PLC'S BROKER. |
| [`MQTT_CLIENT`](#mqtt_client) | Starts an MQTT client and hands itself to every other block. |
| [`MQTT_CLOCK`](#mqtt_clock) | SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet, the mobile network's own time over cellular - so Sparkplug timestamps and CURRENT_DT are real time. |
| [`MQTT_CONFIG`](#mqtt_config) | Everything about a connection that is not where it goes. |
| [`MQTT_MESSAGE`](#mqtt_message) | The raw text of whatever arrives, for anything that is not a single number. |
| [`MQTT_PRESENCE`](#mqtt_presence) | Says this device is here, and arranges for the broker to say when it is not. |
| [`MQTT_PROVISION`](#mqtt_provision) | Lets this PLC register itself with a modbee broker, so nobody types a password into it. |
| [`MQTT_PUBLISH`](#mqtt_publish) | Sends one message when you ask. |
| [`MQTT_REPORT`](#mqtt_report) | Publishes a variable. |
| [`MQTT_REQUEST`](#mqtt_request) | Asks a question and waits for the answer. |
| [`MQTT_STATUS`](#mqtt_status) | How this connection is doing. |
| [`MQTT_STRUCT_PUBLISH`](#mqtt_struct_publish) | A whole STRUCT, one block. |
| [`MQTT_STRUCT_SUBSCRIBE`](#mqtt_struct_subscribe) | A whole STRUCT, one block. |
| [`MQTT_SUBSCRIBE`](#mqtt_subscribe) | Keeps a variable up to date from the broker, with a quality that says how much to believe it. |
| [`MQTT_TLS`](#mqtt_tls) | What to trust at the other end. |
| [`SPARKPLUG_COMMAND`](#sparkplug_command) | A SPARKPLUG COMMAND, ARRIVING. |
| [`SPARKPLUG_DAY_TOTALS`](#sparkplug_day_totals) | A small table of daily totals, kept by the project and sent on every birth as historical values, so SCADA fills in the days the link was down. |
| [`SPARKPLUG_DEVICE`](#sparkplug_device) | A DEVICE UNDER A SPARKPLUG NODE. |
| [`SPARKPLUG_HISTORY`](#sparkplug_history) | Keeps events while the link is down and sends them after it comes back, flagged historical, in order, at the time they happened. |
| [`SPARKPLUG_HOST`](#sparkplug_host) | A SPARKPLUG B HOST APPLICATION: the other end of SPARKPLUG_NODE. |
| [`SPARKPLUG_METRIC`](#sparkplug_metric) | ONE SPARKPLUG METRIC, for what a STRUCT member cannot express. |
| [`SPARKPLUG_NODE`](#sparkplug_node) | A SPARKPLUG B EDGE NODE. |
| [`SPARKPLUG_STRUCT`](#sparkplug_struct) | A WHOLE STRUCT AS A SPARKPLUG METRIC SET. |
| [`SPARKPLUG_SUBSCRIBE`](#sparkplug_subscribe) | READ ONE METRIC from a node a SPARKPLUG_HOST is watching. |
| [`SPARKPLUG_WRITE`](#sparkplug_write) | WRITE ONE METRIC on an edge node, from a SPARKPLUG_HOST. |

---

## MQTT_ARDUINO

```
The things only a board has. Optional, and ignored on the Runtime.

CLIENT       which client. Must be wired.
SSID       the WiFi network to join.
WIFI_PASSWORD   its password. Empty for an open network.
MAC        this board's MAC address, for Ethernet. "DE:AD:BE:EF:00:01" -
          colons, hyphens or nothing between the pairs, whichever the label
          uses. EVERY BOARD ON A SEGMENT NEEDS ITS OWN.
IP         a fixed address for Ethernet, or "dhcp" to ask for one.
GATEWAY    the router, when the address is fixed.
SUBNET     the mask, when the address is fixed.

APPLIED    the settings reached the client.
ERROR      they did not - this is the Runtime, which has none of this hardware.
STATUS     why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SSID` | `STRING(48)` |  |
| `WIFI_PASSWORD` | `STRING(64)` |  |
| `MAC` | `STRING(32)` |  |
| `IP` | `STRING(32)` |  |
| `GATEWAY` | `STRING(32)` |  |
| `SUBNET` | `STRING(32)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `APPLIED` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

A FIXED ADDRESS IS WHAT YOU WANT, for two reasons. DHCP blocks - up to sixty
seconds in the Arduino library, which on a 1 ms task is not a delay, it is a
stopped PLC. The client bounds it to one second an attempt and retries on its
own timer, so it works and it costs a stall. And a plant network rarely runs
DHCP at all, so a board that cannot get a lease sits there publishing into
nothing.

Set IP to "dhcp" only when you know there is a server and you can afford the
first attempt.

On the Runtime every pin here describes hardware that is not there, so the
block says so on ERROR rather than quietly doing nothing. A block that
silently ignores what it was told is how an afternoon goes missing.

---

## MQTT_BRIDGE

```
Carries topics between two brokers. Standalone - it owns both connections and
takes no CLIENT.

ENABLE          TRUE connects both ends and starts forwarding.
LOCAL_HOST      the near broker. Usually the site one, often this PLC itself.
LOCAL_PORT      0 for the standard port.
LOCAL_SECURITY  plain or TLS on the near side.
REMOTE_HOST     the far broker. Usually head office or a cloud service.
REMOTE_PORT     0 for the standard port.
REMOTE_SECURITY plain or TLS on the far side. These are separate pins because
                the two sides are genuinely different: a site broker on the
                same switch needs no TLS, and the link out of the building
                always does.
REMOTE_USER     credentials for the far side, which usually wants them.
REMOTE_PASSWORD
BRIDGE_NAME            what to call this bridge. It becomes part of both client
                identifiers, WHICH MUST DIFFER - a bridge using one identifier
                on both ends would take over its own session the moment both
                brokers turned out to be the same box.
TOPIC          one rule: what to carry. Wildcards allowed.
DIRECTION       MQTT_OUT local to remote, MQTT_IN remote to local, MQTT_BOTH.
QOS            the most this rule will carry. Never higher than it arrived.
LOCAL_PREFIX    what the near side sees in front of the topic.
REMOTE_PREFIX   and the far side. "site7/" on the remote turns "plant/a/temp"
                into "site7/plant/a/temp" upstream, so ten sites can share one
                broker without colliding.
FORWARD_RETAINED  whether a retained message stays retained across. OFF by
                default and usually right: a retained value that crosses a
                bridge outlives the link that carried it, and a stale reading
                on a head-office dashboard is worse than no reading.

STATE           where the bridge is up to.
LOCAL_UP        the near end is connected.
REMOTE_UP       the far end is connected.
FORWARDED_OUT   running total carried local to remote.
FORWARDED_IN    and the other way.
REFUSED_OUT     the far side would not take it.
REFUSED_IN
ERROR           something failed.
STATUS          why. MQTT_OK when fine.
```

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ENABLE` | `BOOL` | `TRUE` |
| `LOCAL_HOST` | `STRING(64)` |  |
| `LOCAL_PORT` | `UINT` |  |
| `LOCAL_SECURITY` | `MQTT_SECURITY` |  |
| `REMOTE_HOST` | `STRING(64)` |  |
| `REMOTE_PORT` | `UINT` |  |
| `REMOTE_SECURITY` | `MQTT_SECURITY` |  |
| `REMOTE_USER` | `STRING(64)` |  |
| `REMOTE_PASSWORD` | `STRING(64)` |  |
| `BRIDGE_NAME` | `STRING(48)` |  |
| `TOPIC` | `STRING(128)` |  |
| `DIRECTION` | `MQTT_DIRECTION` |  |
| `QOS` | `BYTE` |  |
| `LOCAL_PREFIX` | `STRING(64)` |  |
| `REMOTE_PREFIX` | `STRING(64)` |  |
| `FORWARD_RETAINED` | `BOOL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `STATE` | `MQTT_BRIDGE_STATE` |  |
| `LOCAL_UP` | `BOOL` |  |
| `REMOTE_UP` | `BOOL` |  |
| `FORWARDED_OUT` | `DINT` |  |
| `FORWARDED_IN` | `DINT` |  |
| `REFUSED_OUT` | `DINT` |  |
| `REFUSED_IN` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

ONE INSTANCE, MANY RULES. Call the same instance several times in a scan, each
with a different TOPIC, and each call adds a rule - the connection pins are
read from the first call and the rest add to the mapping. A site carrying
three topic trees is one block called three times, not three bridges.

The rules are collected on the first scan and the connections built on the
second, which is why a rule added later in the program still arrives before
either end connects.

MQTT_BRIDGE_DEGRADED is the state worth alarming on. It means one end is
connected and the other is not, so half the traffic is flowing and the other
half is piling up - which from the site looks like everything working and from
head office looks like the site has died.

A MAPPING THAT WOULD LOOP IS REFUSED, not carried. Two rules that would carry
this bridge's own output back into it are a message storm that takes a broker
down, and on 5.0 the No Local subscription option prevents it outright. Where
the version cannot express that, the configuration is rejected at start with
MQTT_INVALID_ARGUMENT rather than accepted and regretted.

---

## MQTT_BROKER

```
Makes this PLC the broker other devices connect to. Standalone - it owns its
own listener and takes no CLIENT.

ENABLE       TRUE listens. A falling edge stops and releases the port.
LISTEN_ON      which interface to listen on. Empty for all of them.
PORT         0 for 1883.
MAX_CLIENTS  connections served at once. 0 for 32.
MAX_RETAINED retained messages held. 0 for 256.
MAX_SUBSCRIPTIONS  subscriptions each client session may hold. 0 for 32
             (8 on a board).
MAX_QUEUED   messages held for each client while it is away or slow. 0 for
             64 (16 on a board).
MAX_MESSAGE  the largest message, in bytes, a client may send or be sent;
             also each connection's buffer size. 0 for 8192 (1024 on a
             board).
MAX_SESSION_EXPIRY  how long a session is kept after its client goes: a
             3.1.1 client's persistent session, and the most a 5.0 client
             may ask for. 0 for 1 h. Read when the broker starts.
SECURITY   MQTT_PLAIN serves clear text on 1883, the way this block always
           has. Anything else serves TLS, and then:
             no CERT_FILE      the broker makes its OWN certificate on first
                               start, keeps it beside the program and presents
                               the same one every start after. Zero
                               configuration; clients pin BROKER_KEY.
             CERT_FILE + KEY_FILE
                               a real certificate - from the site's own CA, or
                               a public one. Clients verify it the ordinary
                               way, hostname and all, with nothing pinned.
           Self-signed is the DEFAULT, not a ceiling. The obstacle was never
           the engine; it was that a certificate does not fit on a pin, and a
           path does.
CERT_FILE  a certificate to present, as a path on the Runtime. Empty to make
           one.
KEY_FILE   its private key. One without the other is refused rather than half
           applied.

ACCOUNTS   are not a pin. Draw one MQTT_BROKER_USER rung per device, wired to
           this block. Declaring any account makes accounts REQUIRED for every
           connection - including one whose ENABLE is off, so switching off the
           last account locks the broker rather than quietly opening it. With
           no MQTT_BROKER_USER at all the broker admits anybody, as it always
           has; on a network that is not isolated, declare accounts.

LISTENING    the port is open.
CLIENTS      connections attached right now. THIS PLC COUNTS AS ONE of them if
             it also runs MQTT_CLIENT against itself, which is the ordinary way
             a broker PLC gets onto its own bus - a broker holds no values, so
             anything that publishes or subscribes is a client.
SESSIONS     sessions held, including those of clients currently away whose
             state has not expired.
ACCEPTED     running total of connections accepted at the socket.
ADMITTED     of those, how many earned a successful CONNACK. A socket that
             opens and never becomes a client is a scanner, or bad credentials.
REFUSED      and how many were turned away - a client with a different login
             than the one that made an existing session among them.
FROM_CLIENTS    messages accepted from clients.
TO_CLIENTS    messages sent to clients.
DROPPED      deliveries a full client queue could not take. Not silent: at
             QoS above 0 the publisher is told rather than left believing it
             arrived.
TAKEOVERS    times a client identifier was claimed by a second connection
             with the same login, and the first was disconnected. A number
             that climbs usually means two devices share an identifier.
ERROR        something failed.
STATUS       why. MQTT_OK when fine.
```

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ENABLE` | `BOOL` | `TRUE` |
| `LISTEN_ON` | `STRING(48)` |  |
| `PORT` | `UINT` |  |
| `MAX_CLIENTS` | `INT` |  |
| `MAX_RETAINED` | `INT` |  |
| `SECURITY` | `MQTT_SECURITY` |  |
| `CERT_FILE` | `STRING(128)` |  |
| `KEY_FILE` | `STRING(128)` |  |
| `MAX_SUBSCRIPTIONS` | `INT` |  |
| `MAX_QUEUED` | `INT` |  |
| `MAX_MESSAGE` | `DINT` |  |
| `MAX_SESSION_EXPIRY` | `TIME` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `LISTENING` | `BOOL` |  |
| `CLIENTS` | `INT` |  |
| `SESSIONS` | `INT` |  |
| `ACCEPTED` | `DINT` |  |
| `ADMITTED` | `DINT` |  |
| `REFUSED` | `DINT` |  |
| `FROM_CLIENTS` | `LINT` |  |
| `TO_CLIENTS` | `LINT` |  |
| `DROPPED` | `LINT` |  |
| `TAKEOVERS` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `BROKER_KEY` | `STRING(64)` |  |

WHY PUT A BROKER IN A PLC. A site with twenty sensors and an intermittent
uplink does not want twenty devices each retrying a connection to head office.
Point them at the PLC, let it hold the retained values and the sessions, and
bridge one connection upstream with MQTT_BRIDGE. The site keeps working when
the link does not, and comes back in step when it returns.

RUNS ON A BOARD TOO, and for a while it did not. The broker was always
platform-neutral - the routing, the retained store, the session registry and
takeover compile anywhere - and what was missing was a listener that could
accept a connection without a BSD socket. There are two now, so an ESP32
running this block is a real broker and not a stub.

What differs on a board:

  LISTEN_ON        ignored. An Arduino server listens on whatever interface
                   the core brought up; there is no second one to choose.
  CERT_FILE,
  KEY_FILE         refused rather than ignored. They are paths, and a board
                   has no file system this block may assume.
  BROKER_KEY       the fingerprint of a certificate made on THIS run. There is
                   nowhere on a board to keep a key, so it moves on every
                   restart - either re-pin after a reflash, or serve plain on
                   an isolated line and put the TLS on the MQTT_BRIDGE that
                   leaves it, which is the connection that needs it.
  the defaults     sized for a panel: four connections, eight sessions, 1 kB
                   buffers, 32 retained, 8 subscriptions and 16 queued
                   messages per session. The Runtime's defaults would be tens
                   of kilobytes. Every one is a pin: raise the ones a site
                   needs, within the board's memory - each connection holds
                   two MAX_MESSAGE buffers.

Serving TLS on a board also needs wolfSSL on the include path; serving plain
needs nothing at all. WiFi comes with the ESP32 core, and Ethernet is opt-in:
MQTT_ENABLE_ETHERNET, a define in the board package's compiler flags (an
OpenPLC project has no build flags of its own).

TAKEOVERS is the pin to watch on a new site. MQTT says a second connection
using an existing client identifier displaces the first, so two devices
flashed with the same identifier will knock each other off for ever, each
reconnecting and each looking healthy on its own. This counter is how that
looks from the middle, and it is the only place it is visible. A session
belongs to the login that made it: a client that uses another login with an
existing identifier is refused (CONNACK 0x85; 0x02 at 3.1.1) and counts on
REFUSED, not here. Without logins every client is the same nobody, so
takeovers work as before.

SESSIONS EXPIRE. A persistent session (clean session off) of a 3.1.1 client is
kept for MAX_SESSION_EXPIRY after it goes (an hour unless set), then dropped -
before, it was kept until the broker restarted. A 5.0 client says how long
itself, up to the same limit. Raise it for devices that sleep longer.

REFUSED AS THE STANDARD SAYS. A Will topic with wildcards (0x90), a Will
declared UTF-8 that is not (0x99), a PUBLISH from a client carrying a
Subscription Identifier, two Subscription Identifiers in one SUBSCRIBE, No
Local on a $share subscription, and a 3.1.1 CONNECT with a password but no
user name are refused or disconnected. A 3.1.1 QoS 2 message when the client's
inbound table is full closes the connection rather than being acknowledged
and lost.

---

## MQTT_BROKER_USER

```
ONE ACCOUNT ON THIS PLC'S BROKER. Draw one rung per device that connects.

USERNAME   the name the device logs in with. Compared exactly, case included -
           MQTT user names are case-sensitive.
PASSWORD   its password. Up to 64 characters, which is what a STRING pin
           carries; compared in full, never stopping at the first difference.
ENABLE     FALSE refuses this device without forgetting it. The account still
           counts as declared, so the broker STILL REQUIRES ACCOUNTS: switching
           off the last one locks the broker, it does not open it.

ACTIVE     the account is declared and enabled.
LOGINS     times this device has connected successfully.
REFUSED    times a connection under this name was turned away - a wrong
           password, or the account switched off. A number that climbs on one
           device and not the others is that device's configuration.
ERROR      the account could not be declared; STATUS says why.
STATUS     MQTT_INVALID_ARGUMENT for an empty USERNAME, MQTT_QUOTA_EXCEEDED
           when the broker cannot hold another account: when memory for one
           ran out. The table grows with these blocks, on a board and the
           Runtime alike.

WHY ONE BLOCK PER ACCOUNT rather than a list on MQTT_BROKER: an account is
something an engineer adds, removes and switches off one device at a time, and
a rung per device makes each one visible, commentable and interlockable. A
list on a pin would be an array, typed by hand, with no way to disable one
entry.

WHY EACH DEVICE GETS ITS OWN. A shared password cannot be revoked from one
controller without changing it on all of them, and a broker log that says
"plant-user refused" does not say which panel to go to.

WHAT IS NOT HERE: topic permissions. This decides who may CONNECT.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `BROKER` | `MQTT_BROKER` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `USERNAME` | `STRING(64)` |  |
| `PASSWORD` | `STRING(64)` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ACTIVE` | `BOOL` |  |
| `LOGINS` | `DINT` |  |
| `REFUSED` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

---

## MQTT_CLIENT

```
Starts an MQTT client and hands itself to every other block. Call it first.

TRANSPORT  where the bytes go. A MQTT_RUNTIME_* link runs on the OpenPLC
           Runtime, a MQTT_ARDUINO_* link on a board, and MQTT_CELLULAR over
           the modem a modbee-gsm GSM_MODEM runs, on a board. Choosing one the
           target does not have is reported on the pins, not built.
SECURITY   plain or TLS, and which kind of TLS. Separate from TRANSPORT,
           because they are separate questions: one sixteen-value list would
           make the combinations that do not exist look legal.
             MQTT_TLS_VERIFY   a broker somebody signed for. The ordinary
                               check: chain, dates and hostname (a board
                               checks chain and hostname - it has no clock
                               to judge a date). Use this for anything
                               public - AWS IoT, HiveMQ, a customer's
                               platform - where the key rotates every ninety
                               days and pinning would break in the field.
             MQTT_TLS_PINNED   a broker nobody signed for: a ModBee PLC broker,
                               or a site's own Mosquitto. Trusts ONE key, and
                               skips chain and expiry deliberately - a
                               controller with no clock cannot judge a date.
                               The Runtime and an ESP32; see TRUST_NEW.
HOST       the broker. A name or an address.
PORT       0 for the standard one: 1883 plain, 8883 TLS.
CLIENT_ID  what the broker calls this device. Empty asks the broker to assign
           one, which it reports back on ASSIGNED_ID.
PROTOCOL   which version to speak. MQTT_V5_THEN_V311 tries 5.0 and drops to
           3.1.1 only when the broker says the VERSION is the problem - never
           on an authentication or network failure.
EXTERNAL_LINK  a transport another block made, for
           TRANSPORT := MQTT_LINK_EXTERNAL. Ignore it otherwise - it is the
           escape hatch for a transport somebody else wrote, not something
           to wire by hand.
CONNECT    TRUE connects and stays connected. A falling edge stands the client
           down without destroying it, so subscriptions and bindings survive.
TRUST_NEW  for MQTT_TLS_PINNED and nothing else. TRUE lets the FIRST key a
           broker shows be learned and kept (trust on first use, as SSH does).
           Once learned it is ENFORCED, whether TRUST_NEW stays on or not and
           across restarts: a broker showing a different key is refused
           (LAST_ERROR "TLS: not the pinned key" on a board, both fingerprints
           on the Runtime) and BROKER_KEY shows the key it presented. Wiring
           it TRUE is therefore safe.
           To accept a broker REPLACED ON PURPOSE, switch TRUST_NEW off and on
           again - the rising edge forgets the stored key and the next
           connection learns the new one. FALSE with nothing stored refuses to
           connect at all.

LINK_UP      the client exists and its link is open.
CONNECTED  the broker has acknowledged us. This is the one to interlock on.
SESSION_PRESENT  the broker had our session waiting. FALSE after a clean start,
           and FALSE on a first connection - which is how you tell a resumed
           session from a fresh one.
ASSIGNED_ID  the identifier in force, ours or the broker's.
STATE      where the connection is up to, for a diagnostic page.
ERROR      something failed.
STATUS     why. MQTT_OK when fine.
BROKER_KEY the SHA-256 of the key the broker actually presented, 64 hexadecimal
           characters, whether or not anything is pinned. Write it down at
           commissioning; compare it when something looks wrong. Empty on a
           plain connection.
LAST_ERROR the operating system's own words - "Connection refused", "Name or
           service not known". Text, because no status code can say which of
           forty things went wrong at a socket. TLS on a board says it in a
           short fixed line with the engine's code, "TLS: wrong host name" or
           "TLS: broker refused us -0x7780"; page 09 lists them.
           "out of memory for topics or subscriptions" when a block's topic
           or subscription could not be held: those tables grow with the
           program, on a board and the Runtime alike, and only memory ends
           them. "out of memory for MAX_PENDING" when the queue MQTT_CONFIG
           asked for could not be taken: the client runs on with the queue
           it had, and the rest of the sentence says how many that is.
```

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TRANSPORT` | `MQTT_LINK` |  |
| `SECURITY` | `MQTT_SECURITY` |  |
| `HOST` | `STRING(64)` |  |
| `PORT` | `UINT` |  |
| `CLIENT_ID` | `STRING(48)` |  |
| `PROTOCOL` | `MQTT_PROTOCOL` |  |
| `EXTERNAL_LINK` | `__XWORD` |  |
| `CONNECT` | `BOOL` | `TRUE` |
| `TRUST_NEW` | `BOOL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `LINK_UP` | `BOOL` |  |
| `CONNECTED` | `BOOL` |  |
| `SESSION_PRESENT` | `BOOL` |  |
| `ASSIGNED_ID` | `STRING(48)` |  |
| `STATE` | `MQTT_STATE` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |
| `BROKER_KEY` | `STRING(64)` |  |

THESE EIGHT PINS ARE THE WHOLE OF AN ORDINARY CONNECTION. Everything else a
client can be told lives on optional blocks, so it costs you nothing until you
want it:

  MQTT_CONFIG    keepalive, session, credentials, queue and buffer sizes,
                 reconnect backoff.
  MQTT_TLS       the certificate authority, and mutual TLS.
  MQTT_ARDUINO   the pins and credentials only a board has - SSID, MAC, IP.
  MQTT_PRESENCE  the online/offline pair: a birth message and the Will that
                 says when you are gone.

AND THE PROTOCOLS THAT RIDE ON IT, as layers on this one connection - one
radio, one login, one session for everything the device says:

  SPARKPLUG_NODE / SPARKPLUG_HOST   Sparkplug B. Takes the Will (its death
                 certificate) and a clean session on every CONNECT, so not
                 with MQTT_PRESENCE.
  OTA_NODE       firmware updates (modbee-ota), on topics of its own.

WITHOUT ANY OF THEM THE DEFAULTS ARE THE ONES YOU WANT: MQTT 5.0 falling back
to 3.1.1, a sixty second keepalive, a clean session, and automatic reconnect
with a backoff that spreads so forty PLCs restarting together do not arrive at
the broker in step: each wait is random, from 0.1 s up to the current backoff,
which doubles to its cap; it starts small again only once a connection has
stayed up for 30 s, so a link that drops straight after CONNACK keeps backing
off.

NOTHING HERE BLOCKS. connect() does not wait for the broker; it starts the
attempt and CONNECTED says when it arrived. That is what makes this safe in a
scan cycle, and it is why the library exists. On an ESP32 that includes
opening the socket and the TLS handshake: both run on a short task of their
own, below the PLC's tasks, while STATE says CONNECTING. A board without
threads opens the socket inside the scan, for as long as the medium takes.

Which pins matter depends on TRANSPORT, and the rest are ignored:

  MQTT_RUNTIME_TCP        HOST, PORT
  MQTT_ARDUINO_WIFI       HOST, PORT, and MQTT_ARDUINO for the credentials
  MQTT_ARDUINO_ETHERNET   HOST, PORT, and MQTT_ARDUINO for the MAC and address
  MQTT_CELLULAR           HOST, PORT, and a GSM_MODEM from the modbee-gsm
                          library in the same project. Opening the socket
                          takes about 1.5 s, never longer than
                          CONNECT_TIMEOUT, and on an ESP32 it does not hold
                          this block's task.
  MQTT_LINK_EXTERNAL      EXTERNAL_LINK, and nothing else

TLS ON A BOARD IS THE SAME ON EVERY MEDIUM. On an ESP32, Wi-Fi, Ethernet and
cellular all open a PLAIN connection and the TLS runs on the controller, with
the mbedTLS the board already carries for its Wi-Fi - so every SECURITY works
on every TRANSPORT, BROKER_KEY is filled, TRUST_NEW learns, and the handshake
runs beside the scan instead of in it. The CA comes from
MQTT_CA_CERT_PEM and a certificate of the board's own, for mutual TLS, from
MQTT_CLIENT_CERT_PEM and MQTT_CLIENT_KEY_PEM - defines in the board package's
compiler flags, since an OpenPLC project has no build flags of its own. For the
site's own broker none is needed: MQTT_TLS_PINNED with TRUST_NEW and a login.
A board WITHOUT mbedTLS keeps what its medium offers: WiFiClientSecure (no
PINNED), no TLS over Ethernet, and the modem's own TLS (INSECURE only).

SETTINGS MAY CHANGE WHILE IT RUNS. Every pin here and everything MQTT_CONFIG,
MQTT_TLS, MQTT_ARDUINO and MQTT_PRESENCE set is read every scan. Change the
broker, the port, SECURITY, TRANSPORT, the login, CLIENT_ID or PROTOCOL - from
an HMI settings page, say - and the client says goodbye on the old settings and
connects with the new ones, on the same client: subscriptions and every other
block carry on, nothing needs a restart. A pinned key stays pinned: a new
broker address shows a different key and is refused until TRUST_NEW is
switched off and on, as for a replaced broker.

ONE TASK. This block and every block given it - publishing, subscribing,
Sparkplug, OTA - run in one task, the network task, at a lower priority than
the machine's: T#50ms on a board, faster on the Runtime. The machine's program
trades values with them through globals. A block in any other task says
MQTT_WRONG_TASK and does nothing, rather than race the client from another
thread. See docs/10-scan-rate.md.

---

## MQTT_CLOCK

```
SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet,
the mobile network's own time over cellular - so Sparkplug timestamps and
CURRENT_DT are real time. One per controller.

TRANSPORT  where the time comes from - the same list as MQTT_CLIENT and
           SPARKPLUG_NODE, so a site that moves from Wi-Fi to cellular changes
           one pin on each:
             MQTT_RUNTIME_TCP       the Runtime's own clock, which its operating
                                    system already keeps. Nothing is set.
             MQTT_ARDUINO_WIFI      NTP from SERVER, through the board's IP
             MQTT_ARDUINO_ETHERNET  stack (ESP32). NETWORK or MQTT_ARDUINO
                                    brings the network up; this waits for it.
             MQTT_CELLULAR          the mobile network's time (NITZ) from the
                                    modem a modbee-gsm GSM_MODEM runs. Costs no
                                    data. Not every network sends it.
             MQTT_LINK_EXTERNAL     UTC_IN, when UTC_IN_VALID - an RTC,
                                    GSM_TIME.UTC, a time SCADA wrote.
SERVER     the NTP server. Default 'pool.ntp.org'; a site with its own (a
           router, a SCADA server) should use it.
REFRESH    how often to ask again. Default T#1h - a board's crystal drifts a
           second or two a day, so hourly is plenty.
UTC_IN     MQTT_LINK_EXTERNAL: the time to set, in UTC.
UTC_IN_VALID  MQTT_LINK_EXTERNAL: UTC_IN is good. Its rising edge sets the
           clock, and again every REFRESH while it stays TRUE.
ENABLE     FALSE stops asking. The clock keeps the time it has.

SYNCED     the clock holds real time - a date after 2024. Exactly what
           SPARKPLUG_NODE.CLOCK_SET reports.
UTC        the time now, in UTC. DT#1970-01-01 while not SYNCED.
AGE        how long since the clock was last set. Grows while the network is
           away - the clock keeps running on its own crystal meanwhile.
ERROR      the transport cannot give the time on this target, or NTP has not
           answered for a minute after starting.
LAST_ERROR why, in words. Empty when fine.
```

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TRANSPORT` | `MQTT_LINK` |  |
| `SERVER` | `STRING(64)` | `'pool.ntp.org'` |
| `REFRESH` | `TIME` | `T#1h` |
| `UTC_IN` | `DT` |  |
| `UTC_IN_VALID` | `BOOL` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SYNCED` | `BOOL` |  |
| `UTC` | `DT` |  |
| `AGE` | `TIME` |  |
| `ERROR` | `BOOL` |  |
| `LAST_ERROR` | `STRING(64)` |  |

wifi( ENABLE := TRUE, SSID := ..., PASSWORD := ... );   NETWORK, node-uio
  ntp ( TRANSPORT := MQTT_ARDUINO_WIFI );
  sp  ( TRANSPORT := MQTT_ARDUINO_WIFI, ... );            stamps with it

ONE CLOCK, AND EVERYTHING USES IT. This sets the board's system clock, so
SPARKPLUG_NODE's timestamps, CURRENT_DT and anything else that asks for the
date agree, with nothing to wire between them.

UNTIL IT IS SYNCED a board counts from when it started, and the timestamps it
sends are dates in January 1970 - unmistakably not real. A SCADA historian
should take a timestamp like that as "not synced" and stamp the value with
the time it arrived instead. SYNCED and CLOCK_SET say which it is. Once set,
the clock survives a loss of network and keeps time on its own.

ON THE RUNTIME THIS BLOCK SETS NOTHING. The operating system's time service
owns the clock there, and a PLC program stepping it under every other program
on the machine would be a fault, not a feature. SYNCED still reports it.

NOTHING HERE BLOCKS. NTP runs in the background on the board's network stack,
and the modem is asked through GSM_MODEM's queue. Put this in the network task
beside the MQTT blocks.

---

## MQTT_CONFIG

```
Everything about a connection that is not where it goes. Optional.

CLIENT             which client. Must be wired.
KEEP_ALIVE         how long the broker waits in silence before deciding we are
                   gone. T#0s for sixty seconds. The broker may lower it and
                   say so. MQTT carries this in WHOLE SECONDS, so anything
                   finer is rounded up to the next second.
CLEAN_START        TRUE starts a fresh session every connect. FALSE resumes
                   the one the broker kept, so QoS 1 and 2 messages survive a
                   drop.
KEEP_SESSION       how long the broker keeps that session after we disconnect.
                   T#0s means only while the connection lasts. Whole seconds
                   on the wire, as above. 5.0 only.
USERNAME           user name, if the broker wants one.
PASSWORD           and its password.
MAX_PENDING        how many publishes and subscribes may be waiting on the
                   broker at once. 0 for the library's own figure, 32. Any
                   number: the queue is taken when the client is made, and
                   only memory refuses it - then MQTT_CLIENT's LAST_ERROR says
                   so and how many it holds. Past it the next one is refused
                   with MQTT_QUEUE_FULL rather than dropped.
MAX_MESSAGE_IN     the biggest message this client can RECEIVE, in bytes. 0
                   for 4096. A larger one cannot be assembled, and the
                   connection drops rather than half-reading it.
MAX_MESSAGE_OUT    the biggest it can SEND. 0 for 4096. A larger publish is
                   refused with MQTT_PACKET_TOO_LARGE before it goes near the
                   wire.
RECONNECT          first backoff after a drop. T#0s for one second.
RECONNECT_MAX      ceiling on that backoff. T#0s for a minute.
CONNECT_TIMEOUT    how long to wait for a broker that accepts a socket and
                   then says nothing. T#0s for twenty seconds.
AUTO_RECONNECT     TRUE reconnects by itself. Turn it OFF on a cellular link,
                   where the reconnect is the one call that can stall a scan.

APPLIED         the settings reached the client.
ERROR           they did not.
STATUS          why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `KEEP_ALIVE` | `TIME` |  |
| `CLEAN_START` | `BOOL` | `TRUE` |
| `KEEP_SESSION` | `TIME` |  |
| `USERNAME` | `STRING(64)` |  |
| `PASSWORD` | `STRING(64)` |  |
| `MAX_PENDING` | `DINT` |  |
| `MAX_MESSAGE_IN` | `DINT` |  |
| `MAX_MESSAGE_OUT` | `DINT` |  |
| `RECONNECT` | `TIME` |  |
| `RECONNECT_MAX` | `TIME` |  |
| `CONNECT_TIMEOUT` | `TIME` |  |
| `AUTO_RECONNECT` | `BOOL` | `TRUE` |
| `RETRY_REJECTED_CREDENTIAL` | `BOOL` | `FALSE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `APPLIED` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

EVERY PIN HERE HAS A DEFAULT THAT WORKS. This block exists so that a client
which wants none of them is eight pins instead of twenty-six, not because a
client needs it. If you are not changing any of these, do not place it.

Place it anywhere in the rung - above the client or below it. The client waits one
scan before opening its link precisely so that this block has run first
whichever side of it you drew.

CLEAN_START is the one worth thinking about. TRUE is right for a sensor that
publishes the current value and has nothing to catch up on. FALSE is right for
anything that must not lose a message across a dropped link - a totaliser, a
command channel, an alarm - and it costs the broker memory per client, which
is why it is not the default.

AUTO_RECONNECT is the other. On WiFi or wired the reconnect is milliseconds
and you want it on. On cellular it is SECONDS, because the AT commands
underneath it are, and a scan cycle has nowhere to put that - so turn it off
and reconnect from your own logic where you can afford it.

THE TWO SIZE PINS ANSWER ONE SYMPTOM: a message plainly being published that
plainly never arrives. The default of 4096 bytes suits readings and setpoints
and is too small for a JSON document of any size. Raise MAX_MESSAGE_IN on the
subscribing end and MAX_MESSAGE_OUT on the publishing one - and remember they
cost RAM per client whether or not a big message ever comes.

RETRY_REJECTED_CREDENTIAL is OFF, and leaving it off is almost always right.
A dropped link is worth retrying because the link may come back; a password
the broker said no to will not become correct by itself, and sending it again
every second is how a device gets itself banned - by address, on some brokers,
which takes the whole site off with it. With this off, a rejected credential
sets ERROR on MQTT_CLIENT with the broker's own words in LAST_ERROR and stops.

Turn it on only where the credential is expected to become valid without the
program restarting: a broker whose access list loads after it starts
listening, or a token something else in the same program refreshes.

MAX_PENDING is a different kind of limit: not how big, but how many at once.
It only matters at QoS 1 and 2, where a publish stays outstanding until the
broker acknowledges it. A program firing faster than a slow link can drain
gets MQTT_QUEUE_FULL, which is the honest answer - the alternative is an
unbounded queue and a device that runs out of memory at three in the morning.

---

## MQTT_MESSAGE

```
The raw text of whatever arrives, for anything that is not a single number.
Standing - it subscribes once and maintains itself.

CLIENT         which client. Must be wired.
TOPIC       what to listen to. Wildcards allowed.
QOS          the most the broker may use to deliver.
ENABLE       FALSE unsubscribes without losing the topic.

PAYLOAD      the message, as text.
LENGTH       how many characters of it. 0 for an empty message, which is a
             real thing in MQTT and usually means "this retained value is
             cancelled".
TRUNCATED    the message was longer than PAYLOAD holds. Reported, never hidden,
             so a partial reading can never be mistaken for a complete one.
RECEIVED     running total of messages delivered.
NEW_MESSAGE  one scan, when a message arrived.
ERROR        something failed.
STATUS       why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TOPIC` | `STRING(128)` |  |
| `QOS` | `BYTE` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `PAYLOAD` | `STRING(254)` |  |
| `LENGTH` | `INT` |  |
| `TRUNCATED` | `BOOL` |  |
| `RECEIVED` | `DINT` |  |
| `NEW_MESSAGE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

USE MQTT_SUBSCRIBE FOR A NUMBER. This block is for the rest: a JSON document
you parse yourself, a command word, a state name, a message from a device that
does not know anything about this library.

NEW_MESSAGE is one scan wide, so latch it if a slower task has to see it. Note
that it is the arrival that is reported, not a change - the same value sent
twice is two messages, and for a command channel that is exactly right. "Open"
sent again means open again, and a block that suppressed it would swallow a
repeated instruction.

An EMPTY message is not nothing. Publishing an empty payload with RETAIN is
how MQTT deletes a retained value, so a subscriber seeing LENGTH 0 with
NEW_MESSAGE is being told the old value is withdrawn - which is different from
having heard nothing at all.

TRUNCATED matters on a JSON payload. A document cut in half parses as garbage
or, worse, as something plausible. Check the pin before you trust the text.

---

## MQTT_PRESENCE

```
Says this device is here, and arranges for the broker to say when it is not.
Optional, and the most useful optional block there is.

CLIENT        which client. Must be wired.
TOPIC       where to say it. "plant/tank-01/status" is the shape people use.
ONLINE      what to publish when connected. Empty for "online".
OFFLINE     what the broker publishes on our behalf when we vanish. Empty for
            "offline".
RETAINED      TRUE keeps both on the broker, so anything subscribing later is
            told immediately rather than waiting for the next change. This is
            almost always what you want.
QOS         0, 1 or 2 for both messages.
DELAY       how long the broker waits before publishing OFFLINE. T#0s publishes
            it at once. 5.0 only - at 3.1.1 the client refuses to connect rather
            than drop it, because a Will delay silently lost turns a flapping
            link into a stream of false alarms.

SENT   running total of ONLINE messages sent. A number that climbs is a
            link that keeps dropping and coming back.
ERROR       something failed.
STATUS      why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TOPIC` | `STRING(128)` |  |
| `ONLINE` | `STRING(128)` |  |
| `OFFLINE` | `STRING(128)` |  |
| `RETAINED` | `BOOL` | `TRUE` |
| `QOS` | `BYTE` |  |
| `DELAY` | `TIME` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SENT` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

THIS IS HOW A CONSUMER TELLS "OFFLINE" FROM "HAS NOT SENT YET", and in
plain MQTT there is no other way. Subscribe to a topic, hear nothing, and you
cannot tell whether the device is dead or simply has nothing to say. The pair
of messages here answers it: the Will is registered with the broker at connect
time and published BY THE BROKER when the connection dies without a goodbye -
a power cut, a pulled cable, a modem that lost coverage.

The ONLINE message goes out on the session-established hook, which runs before
anything else queued - so a subscriber sees this device come up before it sees
the device's first reading, in that order, every time.

DELAY is the pin that stops a marginal link crying wolf. A radio that drops
for eight seconds and comes back has not gone offline in any sense an operator
cares about; set DELAY to T#30s and the broker waits before announcing it,
and a reconnect inside that window cancels the announcement entirely.

NOT WITH SPARKPLUG. A connection carries one Will, and a SPARKPLUG_NODE or
SPARKPLUG_HOST on the same client owns it: its birth and death certificates are
the presence. This block then says MQTT_REFUSED and publishes nothing.

---

## MQTT_PROVISION

```
Lets this PLC register itself with a modbee broker, so nobody types a
password into it. Optional - place it beside MQTT_CLIENT.

CLIENT    which client. Must be wired. Its CLIENT_ID is this PLC's NAME on the
          broker - unique on the site, like "pump-station-3" - and becomes its
          user name.
KEY       the provisioning key, made once on the broker with
          `modbee key create <name>`. The SAME key goes into every PLC of a
          site; each gets its own login with it.
FORGET    a rising edge forgets the stored login, and the PLC registers again.
          Rarely needed: a PLC whose login stops working re-registers by
          itself.

PROVISIONED  this PLC has its own login, and the client is using it.
PENDING      the broker's admin must approve this PLC first:
             `modbee user approve <name>`. It asks again every thirty seconds.
REFUSED      the broker said no; REASON says why. It asks again every five
             minutes, in case somebody fixes it at the other end.
USERNAME     the login in use: CLIENT_ID, once provisioned.
GROUP        what the key says this site's Sparkplug group is ("" if it says
             nothing). Wire it to SPARKPLUG_NODE's GROUP.
PREFIX       what the key says this site's topic prefix is ("" if it says
             nothing) - for the topics of this PLC's own, such as its firmware
             updates: PREFIX/<name>/... .
REASON       what the broker said, in words.
ERROR        REFUSED, or a pin that is not set.
STATUS       why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `KEY` | `STRING(127)` |  |
| `FORGET` | `BOOL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `PROVISIONED` | `BOOL` |  |
| `PENDING` | `BOOL` |  |
| `REFUSED` | `BOOL` |  |
| `USERNAME` | `STRING(64)` |  |
| `GROUP` | `STRING(64)` |  |
| `PREFIX` | `STRING(127)` |  |
| `REASON` | `STRING(64)` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

HOW IT GOES. On its first start the PLC has no login. It connects with the
key - which lets it do one thing only, ask - and the broker answers with a
login made for this PLC: its name, and a secret only it holds, and the values
the key hands its devices (GROUP and PREFIX). They are kept in this block's
RETAINED memory, and the client reconnects with the login. From then on the
PLC connects as itself, and nobody ever types, records or looks up its
password. While it is asking, the client's CONNECTED stays FALSE, so the rest
of the program waits for the real connection.

EVERY CONNECT IT ASKS AGAIN for GROUP and PREFIX (no new password), so a
change made for the site on the broker reaches it by itself.

WHEN THINGS CHANGE IT SORTS ITSELF OUT. A PLC replaced by a new one: download
the same program - same CLIENT_ID, same KEY - and the new PLC registers and
takes the name over; the old one's login stops working. An admin resets the
login (`modbee user reset`): the stored one is refused, so the PLC registers
again with its key, with no visit to the site. The old login is KEPT until the
broker issues a new one - a registration that is pending or refused never
leaves the PLC with no login at all - and while it waits the PLC tries the old
login again every five minutes, so a login put back on the broker works
again by itself. The site's group changed on
the broker: the broker refuses a connect whose Will (the Sparkplug NDEATH) is
on the old group, so the PLC connects once without a Will, asks again, and
reconnects with the new one. An admin DISABLES the PLC: it stays out -
registering again does not undo that.

LEAVE USERNAME AND PASSWORD ON MQTT_CONFIG EMPTY. This block's login is used
instead of them.

WHAT IT MAY PUBLISH AND SUBSCRIBE TO is decided on the broker, by the key: a
key made with --publish 'plant/${username}/#' lets each PLC publish under its
own name and nowhere else. docs/logins.md in modbee-mqtt has the whole story.

For a modbee broker: the protocol is modbee's.

---

## MQTT_PUBLISH

```
Sends one message when you ask. Acted on the rising edge of REQ.

CLIENT     which client. Must be wired.
REQ      rising edge sends. Holding it TRUE does not send repeatedly.
TOPIC    where it goes. No wildcards - those are for subscribing.
VALUE    what to send. Pass the variable itself and its declared type is what
         travels: a REAL goes as "23.5", an INT as "42", a BOOL as "true", a
         STRING as its text.
QOS      0 fire and forget, 1 at least once, 2 exactly once.
RETAINED   TRUE and the broker keeps it, so whoever subscribes next is told
         straight away instead of waiting for the next change.

BUSY     a level: the message is out and not yet concluded.
DONE     one scan, when the broker has it.
ERROR    one scan, when it failed.
STATUS   why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REQ` | `BOOL` |  |
| `TOPIC` | `STRING(128)` |  |
| `VALUE` | `ANY` |  |
| `QOS` | `BYTE` |  |
| `RETAINED` | `BOOL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BUSY` | `BOOL` |  |
| `DONE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

DONE MEANS DIFFERENT THINGS AT DIFFERENT QOS, and the difference is the whole
point of the pin. At QoS 0 it means the bytes left this device. At QoS 1 it
means the broker acknowledged them. At QoS 2 it means the broker acknowledged
them exactly once and the four-packet handshake completed. Interlock on DONE
at QoS 1 or 2 and you have a real delivery receipt; at QoS 0 you have a
despatch note.

DONE and ERROR are one scan wide, so latch them if a slower task has to see
one. BUSY is a level and is the pin to gate a sequence on.

One instance can serve many topics. The block keeps its state against the
topic it was given, so calling the same instance twice in a scan with two
different topics is two publishes, each with its own outcome - and a program
publishing fifty points costs one block rather than fifty. The outputs
describe the last call.

Nothing is silently dropped. A topic the broker will not take, a payload
larger than the connection allows, a queue that is full - each comes back on
STATUS with its own name rather than disappearing.

---

## MQTT_REPORT

```
Publishes a variable. MODE says what makes it go. Standing - one instance
serves many topics.

CLIENT          which client. Must be wired.
TOPIC           where it goes.
VALUE           the variable to watch. Its declared type is what travels.
MODE            what triggers a message:
                  MQTT_ON_CHANGE    when the value moves past DEADBAND, and
                                    anyway every PERIOD so silence stays
                                    meaningful.
                  MQTT_ON_INTERVAL  every PERIOD, moved or not.
                  MQTT_ON_REQUEST   when REQ goes TRUE, and never otherwise.
                MQTT_CHANGED_EVERY is SPARKPLUG_STRUCT's and is refused
                here (MQTT_INVALID_ARGUMENT).
DEADBAND        how far it must move before that is worth a message. 0 sends
                on any change at all. MQTT_ON_CHANGE only.
PERIOD          MQTT_ON_CHANGE: send anyway after this long, even unchanged.
                T#0s never does, which is the mistake worth avoiding - see
                below. MQTT_ON_INTERVAL: how often. Required there.
REQ             MQTT_ON_REQUEST: a rising edge sends one. Ignored otherwise.
QOS             0, 1 or 2.
RETAINED        TRUE keeps the last value on the broker.
ENABLE          FALSE stops reporting without losing the topic.

SENT            running total of messages sent.
AGE             how long since the last one. T#0s until there has been one,
                which SENT = 0 distinguishes from one sent this scan.
ERROR           something failed.
STATUS          why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TOPIC` | `STRING(128)` |  |
| `VALUE` | `ANY` |  |
| `MODE` | `MQTT_TRIGGER` |  |
| `DEADBAND` | `LREAL` |  |
| `PERIOD` | `TIME` |  |
| `REQ` | `BOOL` |  |
| `QOS` | `BYTE` |  |
| `RETAINED` | `BOOL` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SENT` | `DINT` |  |
| `AGE` | `TIME` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

THIS IS THE BLOCK MOST PROGRAMS WANT, in its MQTT_ON_CHANGE default.

DEADBAND stops a noisy analogue input filling the broker. A level transmitter
that jitters by 0.02 m is not telling you anything, and publishing it four
times a second for a year is thirty million messages nobody reads. Set the
deadband to the smallest change an operator would act on.

PERIOD is the other half, and leaving it at T#0s is the mistake worth
avoiding. A value that never moves publishes nothing, and a consumer cannot
tell that from a device that has died - it just sees silence. Set it to a
minute or two and the silence becomes meaningful: no message inside the
interval is a fault, not a steady reading. That is what lets the subscribing
end run a quality on it, and it is what the subscriber's EXPECT is compared
against.

DEADBAND IS MEASURED ON THE NUMBER, so it has no meaning for a STRING - there
any change at all is a change, and PERIOD still applies. A BOOL counts as a
number, 1.0 or 0.0, so a DEADBAND above 1.0 would freeze one. Leave it at 0
for anything that is not an analogue.

MQTT_ON_INTERVAL WITH NO PERIOD IS REFUSED, not turned into "every scan".
STATUS says MQTT_INVALID_ARGUMENT and nothing is published, because a block
publishing at the task rate is how a broker falls over.

MQTT_ON_REQUEST PUBLISHES NOTHING UNTIL ASKED - no first value, no heartbeat.
Where an acknowledged send is wanted, with BUSY and DONE to sequence against,
that is MQTT_PUBLISH rather than this.

One instance serves many topics. Call it twice in a scan with two topics and
you get two reports, each with its own deadband and its own last value.

---

## MQTT_REQUEST

```
Asks a question and waits for the answer. MQTT 5.0 only.

CLIENT           which client. Must be wired.
REQ            rising edge sends the request.
TOPIC          where the question goes.
VALUE          what to ask. Its declared type is what travels.
REPLY_TOPIC    where the answer comes back. Give each requester its own -
               "plant/plc-01/reply" - so two of them cannot read each other's
               post.
QOS            0, 1 or 2 for the request.
TIMEOUT        how long to wait for an answer. T#0s for five seconds.

BUSY           a level: the question is out and unanswered.
DONE           one scan, when the answer arrived.
REPLY          the answer, as text.
REPLY_LENGTH   how much of it.
ERROR          one scan, when it failed or timed out.
STATUS         why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REQ` | `BOOL` |  |
| `TOPIC` | `STRING(128)` |  |
| `VALUE` | `ANY` |  |
| `REPLY_TOPIC` | `STRING(128)` |  |
| `QOS` | `BYTE` |  |
| `TIMEOUT` | `TIME` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BUSY` | `BOOL` |  |
| `DONE` | `BOOL` |  |
| `REPLY` | `STRING(254)` |  |
| `REPLY_LENGTH` | `INT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

REQUEST AND RESPONSE IS A 5.0 FEATURE and this block says so rather than
pretending. On a 3.1.1 connection it refuses with
MQTT_NOT_SUPPORTED_BY_PROTOCOL - because the Response Topic and Correlation
Data properties do not exist there at all, and sending the request stripped
would mean the responder has no idea where to reply to. A request nobody can
answer is worse than a request refused.

The request carries Response Topic, so a compliant responder knows where to
send the answer without either end agreeing it beforehand, and Correlation
Data, so it can quote the question back.

MATCHING HERE IS BY REPLY_TOPIC, not by correlation. This block reads the next
message that arrives on REPLY_TOPIC as the answer, which is right when each
requester owns its own reply topic and is why the pin documentation says to
give it one. Two blocks sharing a reply topic will read each other's answers,
and no amount of correlation would help a program that cannot tell which
answer it wanted.

TIMEOUT is the pin that keeps a sequence moving. An unanswered request is
otherwise indistinguishable from a slow one, and a rung waiting on BUSY that
never clears is a machine that stops with nothing on the screen to say why.
ERROR with MQTT_KEEPALIVE_TIMEOUT is what a timeout looks like.

---

## MQTT_STATUS

```
How this connection is doing. Every number is measured; nothing here is a
setting.

CLIENT            which client. Must be wired.

CONNECTED       the broker has acknowledged us.
STATE           where the connection is up to.
VERSION         5 or 4 - which protocol version is actually in force, which
                after a fallback is not always the one asked for.
CONNECTS        times this client has connected. Includes the first.
DISCONNECTS     times it has come down.
RECONNECTS      times it went and came back on its own.
PUBLISHED       messages this client sent that concluded successfully.
RECEIVED        messages delivered to it.
PUBLISH_FAILURES  messages that did not make it.
PROTOCOL_ERRORS the broker said something the standard does not allow. Not
                zero means one of the two ends has a bug; some brokers
                are known to.
PENDING          operations accepted and not yet concluded.
REASON_CODE     the last reason code the broker sent with any packet - a
                CONNACK, a SUBACK, a DISCONNECT. Read it WITH VERSION: at 3.1.1
                it is that version's return code, a different numbering (4
                there is a bad password; 4 at 5.0 is something else entirely).
                For why the link will not come up, MQTT_CLIENT's LAST_ERROR
                says it in words.
ERROR           no such client.
STATUS          why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `CONNECTED` | `BOOL` |  |
| `STATE` | `MQTT_STATE` |  |
| `VERSION` | `BYTE` |  |
| `CONNECTS` | `DINT` |  |
| `DISCONNECTS` | `DINT` |  |
| `RECONNECTS` | `DINT` |  |
| `PUBLISHED` | `DINT` |  |
| `RECEIVED` | `DINT` |  |
| `PUBLISH_FAILURES` | `DINT` |  |
| `PROTOCOL_ERRORS` | `DINT` |  |
| `PENDING` | `DINT` |  |
| `REASON_CODE` | `BYTE` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

THIS BLOCK HAS NO INPUTS. It reports and changes nothing, which is why it is
safe to drop onto a diagnostic page anywhere.

The numbers worth putting on a screen are CONNECTS and RECONNECTS. A link that
works but reconnects nightly is a completely different problem from one that
has never worked, and nothing else on this list tells them apart. A RECONNECTS
that climbs at the same time every day is a lease expiring or a scheduled job
on the broker; one that climbs with the weather is a radio.

PUBLISH_FAILURES against PUBLISHED is the other pair. A handful of failures
during a reconnect is ordinary. A ratio that stays steady means something is
refusing messages rather than losing them - check STATUS on the block that
sends them, which names the reason.

VERSION is the pin people forget. Ask for MQTT_V5_THEN_V311 and you may be
speaking either; a 5.0-only feature quietly unavailable on a 3.1.1 connection
is much easier to understand when this pin says 4.

---

## MQTT_STRUCT_PUBLISH

```
A whole STRUCT, one block. MODE says what makes it go.

CLIENT     which client. Must be wired.
BASE       the topic every member hangs off. A member called LEVEL under a
           BASE of 'plant/intake' is published as 'plant/intake/LEVEL'.
DATA       the STRUCT itself. Every member becomes its own topic.
MODE       what triggers a message:
             MQTT_ON_CHANGE    each member when that member changes, and
                               anyway every PERIOD so silence stays
                               meaningful.
             MQTT_ON_INTERVAL  all of them together, every PERIOD.
             MQTT_ON_REQUEST   all of them together when REQ goes TRUE, and
                               never otherwise.
PERIOD     MQTT_ON_CHANGE: send a member anyway after this long, unchanged.
           T#0s never does. MQTT_ON_INTERVAL: how often. Required there.
REQ        MQTT_ON_REQUEST: a rising edge sends the set. Ignored otherwise.
           (MQTT_CHANGED_EVERY is SPARKPLUG_STRUCT's: refused here.)
QOS        0, 1 or 2 for all of them.
RETAINED   TRUE keeps each on the broker.
ENABLE     FALSE stops publishing without losing the bindings.

POINTS     how many members are being published.
SKIPPED    how many were not - a type the wire cannot carry. Named on STATUS
           the first time, and counted here.
SENT       running total of messages sent across all members.
CHANGED    how many went out on this scan.
ERROR      something failed.
STATUS     why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BASE` | `STRING(128)` |  |
| `DATA` | `ANY` |  |
| `MODE` | `MQTT_TRIGGER` |  |
| `PERIOD` | `TIME` |  |
| `REQ` | `BOOL` |  |
| `QOS` | `BYTE` |  |
| `RETAINED` | `BOOL` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `POINTS` | `INT` |  |
| `SKIPPED` | `INT` |  |
| `SENT` | `DINT` |  |
| `CHANGED` | `INT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

FIFTY SETPOINTS, ONE BLOCK. That is the whole point, and the alternative is
fifty MQTT_REPORT instances or - in ladder, which has no FOR loop - fifty
rungs.

  TYPE S_INTAKE : STRUCT
    LEVEL    : REAL;
    FLOW     : REAL;
    RUNNING  : BOOL;
    PUMP_ID  : STRING(16);
  END_STRUCT END_TYPE

  pubAll( CLIENT := mqtt, BASE := 'plant/intake', DATA := stIntake,
          MODE := MQTT_ON_CHANGE, PERIOD := T#60s, RETAINED := TRUE );

publishes plant/intake/LEVEL, plant/intake/FLOW, plant/intake/RUNNING and
plant/intake/PUMP_ID, each only when it moves, and each at least once a
minute whether it moved or not.

THE MEMBER NAME IS THE TOPIC, so the STRUCT declaration IS the topic scheme.
Rename a member and you rename a topic - which is a real consequence and worth
knowing before the third device is commissioned.

THERE IS NO DEADBAND HERE, deliberately. One number covering fifty members of
mixed types is a trap: a BOOL counts as 1.0, so a deadband above that would
freeze every bit in the struct - including a FAULT - until the heartbeat
rescued it, and a counter moving by one would go the same way. Where a member
needs a deadband it gets an MQTT_REPORT of its own, which is one point, one
unit and one declared type, all visible on the rung. The two blocks coexist
happily on one client.

MQTT_ON_CHANGE COMPARES EACH MEMBER AGAINST WHAT WAS LAST PUBLISHED, not
against the last scan, so a slow drift accumulates and eventually goes rather
than creeping past unnoticed.

MQTT_ON_INTERVAL WITH NO PERIOD IS REFUSED, not turned into "every scan".
STATUS says MQTT_INVALID_ARGUMENT and nothing is published: fifty topics at
the task rate is how a broker falls over.

MQTT_ON_REQUEST SENDS THE WHOLE SET, changed or not. That is what a recipe
download wants - the receiving end gets a complete set it can act on, rather
than the three values that happened to differ.

A MEMBER THE WIRE CANNOT CARRY IS REFUSED, NOT SKIPPED QUIETLY. An array, a
nested STRUCT, a TIME: the first one found is named on STATUS as
MQTT_INVALID_ARGUMENT and counted on SKIPPED. A member silently missing from a
payload is the kind of fault that survives commissioning and turns up months
later in an argument about whose data is wrong.

ANY NUMBER OF MEMBERS. What the block remembers per member (24 bytes) is
allocated once, when the STRUCT is first bound, sized to that STRUCT; only
memory limits it. If there is none, ERROR with MQTT_QUEUE_FULL and nothing
is published until there is.

---

## MQTT_STRUCT_SUBSCRIBE

```
A whole STRUCT, one block. Keeps every member up to date from the broker.

CLIENT           which client. Must be wired.
BASE             the topic every member hangs off. A member called SETPOINT
                 under a BASE of 'plant/intake/cmd' is subscribed as
                 'plant/intake/cmd/SETPOINT'.
DATA             the STRUCT to keep up to date. Arriving text is read as each
                 member's declared type and lands in it directly.
EXPECT           how often a value is expected. Drives QUALITY. T#0s means
                 nothing was promised. Set it to a little more than the
                 publisher's own PERIOD.
QOS              the most the broker may use to deliver.
ENABLE           FALSE unsubscribes without losing the bindings.

POINTS           how many members are subscribed.
SKIPPED          how many were not - a type the wire cannot carry.
SUBSCRIBED       every one of them is established at the broker.
QUALITY          the WORST quality across all members. One stale value makes
                 the set no better than that value.
SEEN             EVERY member has arrived at least once. It is what tells
                 an OLDEST of T#0s apart, and it is how a LADDER asks what
                 QUALITY answers - a rung cannot compare an enumeration.
OLDEST           the age of the least recently updated member. T#0s while any
                 member has never arrived - QUALITY is UNKNOWN there, which is
                 what says which of the two zeroes this is.
RECEIVED         running total of messages accepted across all members.
MALFORMED        running total that would not parse into their type.
NEW_VALUES       how many members changed on this scan.
ERROR            something failed.
STATUS           why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BASE` | `STRING(128)` |  |
| `DATA` | `ANY` |  |
| `EXPECT` | `TIME` |  |
| `QOS` | `BYTE` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `POINTS` | `INT` |  |
| `SKIPPED` | `INT` |  |
| `SUBSCRIBED` | `BOOL` |  |
| `QUALITY` | `MQTT_QUALITY` |  |
| `SEEN` | `BOOL` |  |
| `OLDEST` | `TIME` |  |
| `RECEIVED` | `DINT` |  |
| `MALFORMED` | `DINT` |  |
| `NEW_VALUES` | `INT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

FIFTY SETPOINTS, ONE BLOCK, and the same argument as MQTT_STRUCT_PUBLISH: in
ladder there is no FOR loop, so the alternative is fifty rungs.

  subAll( CLIENT := mqtt, BASE := 'plant/intake/cmd', DATA := stSetpoints,
          EXPECT := T#0s, QOS := 2 );

QUALITY IS THE WORST ACROSS THE SET, deliberately. A recipe of twelve
setpoints where one is stale is not eleven-twelfths usable - it is a recipe
you should not run. Where a member needs to be judged on its own, give it an
MQTT_SUBSCRIBE of its own; the two blocks coexist happily on one client.

OLDEST READS T#0s WHILE ANY MEMBER HAS NEVER ARRIVED, for the same reason:
"partly commissioned" is not a state worth reporting as an age. QUALITY is
UNKNOWN throughout that, so the two zeroes are never confused.

A PAYLOAD THAT WILL NOT PARSE LEAVES ITS MEMBER ALONE and counts on
MALFORMED. A publisher sending '23,5' to a REAL is a real fault, and a block
that quietly wrote zero would hide it for a year.

EACH MEMBER COSTS A TOPIC HANDLE AND A SUBSCRIPTION on the client. Both
tables grow with the program, on a board and the Runtime alike, so the only
limit is memory. Past it, the block says so with MQTT_QUEUE_FULL - and
MQTT_CLIENT's LAST_ERROR says "out of memory" - rather than silently
subscribing to some members.

ANY NUMBER OF MEMBERS. What the block remembers per member (8 bytes) is
allocated once, when the STRUCT is first bound, sized to that STRUCT. If there
is no memory for it, ERROR with MQTT_QUEUE_FULL, tried again next scan.

---

## MQTT_SUBSCRIBE

```
Keeps a variable up to date from the broker, with a quality that says how much
to believe it. Standing - it subscribes once and maintains itself.

CLIENT            which client. Must be wired.
TOPIC          what to listen to. Wildcards allowed: + for one level, # for
                the rest. "plant/+/pressure" hears every line.
VALUE           the variable to keep up to date. Its declared type is what the
                text is read as; a payload that will not parse is counted on
                MALFORMED and the variable is left alone.
QOS             the most the broker may use to deliver. It may use less.
EXPECT          how often a value is expected. Drives QUALITY. T#0s means nothing
                was promised, so QUALITY is GOOD as soon as anything arrives.
ENABLE          FALSE unsubscribes without losing the topic.

SUBSCRIBED        the subscription is established at the broker.
QUALITY         how much to believe VALUE. See below.
SEEN            a message has arrived at least ONCE since the program
                started. It is what tells an AGE of T#0s apart, and it is
                how a LADDER asks what QUALITY answers - a rung cannot
                compare an enumeration.
AGE             since the last accepted message, or T#0s if there has not been
                one.
RECEIVED        running total of messages accepted.
MALFORMED       running total that would not parse into VALUE's type.
NEW_VALUE       one scan, when VALUE changed.
ERROR           something failed.
STATUS          why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `TOPIC` | `STRING(128)` |  |
| `VALUE` | `ANY` |  |
| `QOS` | `BYTE` |  |
| `EXPECT` | `TIME` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SUBSCRIBED` | `BOOL` |  |
| `QUALITY` | `MQTT_QUALITY` |  |
| `SEEN` | `BOOL` |  |
| `AGE` | `TIME` |  |
| `RECEIVED` | `DINT` |  |
| `MALFORMED` | `DINT` |  |
| `NEW_VALUE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

QUALITY IS THE PIN THAT MAKES A SUBSCRIBED NUMBER SAFE TO ACT ON, and it is
judged against EXPECT - the interval YOU asked for - rather than some
constant the library picked:

  MQTT_QUALITY_UNKNOWN    nothing has ever arrived. A COMMISSIONING fault:
                          wrong topic, publisher never deployed. Found at a
                          desk with a drawing.
  MQTT_QUALITY_BAD        the link is down, or the value is more than twice
                          overdue. A RUNNING fault. Found in the plant.
  MQTT_QUALITY_UNCERTAIN  overdue, but not by much.
  MQTT_QUALITY_GOOD       arrived inside the interval.

UNKNOWN and BAD are deliberately different. An alarm list that shows both as
"no comms" throws away the one piece of information that says which end of the
site to walk to.

ONE HONEST LIMIT, worth knowing before you rely on this. A connected broker
will happily serve a retained message published by a device that died last
Tuesday, and nothing in MQTT marks it as old. QUALITY knows whether WE are
connected and how long since WE last heard; it cannot know the publisher is
alive. Pair this with MQTT_PRESENCE at the publishing end and the question is
answered properly.

One instance serves many topics - call it twice in a scan with two filters and
each call keeps its own subscription, its own value and its own quality.

---

## MQTT_TLS

```
What to trust at the other end. Optional, and only read when the client's
SECURITY pin asks for TLS.

CLIENT         which client. Must be wired.
CA_FILE      path to the certificate authority to trust, in PEM. Runtime only -
             a board has no filesystem to read it from.
CERT_FILE    this device's own certificate, for mutual TLS. Runtime only.
KEY_FILE     and its private key. Runtime only.

APPLIED      the settings reached the client.
ERROR        they did not.
STATUS       why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `CA_FILE` | `STRING(128)` |  |
| `CERT_FILE` | `STRING(128)` |  |
| `KEY_FILE` | `STRING(128)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `APPLIED` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

Leave every pin empty and TLS still works on the Runtime: it falls back to the
system certificate store, which is what a plant server with a real certificate
needs.

THERE IS NO PIN FOR AN INLINE CERTIFICATE, and there cannot be. An IEC STRING
is limited to 254 characters and the shortest real CA certificate in PEM is
about eight times that, so a pin holding one would be a pin that never worked.
A BOARD GETS ITS CA FROM A DEFINE instead, MQTT_CA_CERT_PEM, set in the board
package's compiler flags - an OpenPLC project has no build flags of its own:

  -DMQTT_CA_CERT_PEM='"-----BEGIN CERTIFICATE-----\n...."'

which is also where a certificate belongs: it is part of the firmware, not
part of the program somebody edits on a Tuesday.

FOR THE SITE'S OWN BROKER NONE OF THIS IS NEEDED. Use MQTT_TLS_PINNED on the
client with TRUST_NEW and a login: the broker's key is learned once and
enforced after, with nothing to install or define. That is the simple default
for a board; a CA is for a broker somebody signed for. MQTT_TLS_INSECURE is a
bench setting and not a plant one.

A BOARD'S OWN CERTIFICATE, for mutual TLS, comes the same way, from the board
package - both or neither, and a build that names one without the other does
not compile:

  -DMQTT_CLIENT_CERT_PEM='"-----BEGIN CERTIFICATE-----\n...."'
  -DMQTT_CLIENT_KEY_PEM='"-----BEGIN PRIVATE KEY-----\n...."'

On an ESP32 all of this applies to Wi-Fi, Ethernet and cellular alike: the TLS
runs on the controller, over a plain connection on each.

THERE IS NO "IGNORE CERTIFICATES" PIN HERE. That decision lives on the client's
SECURITY pin as MQTT_TLS_INSECURE, where it is visible in the block that makes
the connection rather than buried in an optional one - and where nobody can
set it without meaning to.

Mutual TLS wants both CERT_FILE and KEY_FILE; one without the other is
refused, because a certificate with no key cannot be presented and silently
connecting without it would be the opposite of what was asked.

---

## SPARKPLUG_COMMAND

```
A SPARKPLUG COMMAND, ARRIVING.

NODE      which node. Must be wired.
NAME      the metric a command is expected on. It must have been declared
          writable, by SPARKPLUG_STRUCT with WRITABLE set or by
          SPARKPLUG_METRIC.
DEVICE    the device the metric is under, for a DCMD. Empty (the default)
          for a node metric and an NCMD. A name is only unique within its
          device, so a metric under a device is only found with it.
ACK       TRUE takes the pending command, clearing it. Leave it FALSE to watch
          without consuming. Two writes that arrive together are two
          commands: the second is PENDING after the first is taken.

PENDING   a command has arrived and has not been taken.
VALUE     the value it carried, valid on the scan PENDING first goes true.
TEXT      the same for a String metric: up to 126 characters, the most a
          board's command holds.
COUNT     how many commands have arrived on this metric.
LOST      writes dropped because four were already waiting on this metric:
          the oldest goes, the newest is kept. 0 in any sane system.
REFUSED   how many the NODE refused across all metrics - an undeclared name, a
          read-only metric, a value of the wrong type. A running total from the
          node, not this metric alone: a host writing to a name nobody declared
          has no metric to be counted against.
ERROR     something failed.
STATUS    MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `NAME` | `STRING(96)` |  |
| `ACK` | `BOOL` |  |
| `DEVICE` | `STRING(47)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `PENDING` | `BOOL` |  |
| `VALUE` | `LREAL` |  |
| `IS_TRUE` | `BOOL` |  |
| `TEXT` | `STRING(126)` |  |
| `COUNT` | `DINT` |  |
| `REFUSED` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `LOST` | `DINT` |  |

WHY THIS EXISTS WHEN SPARKPLUG_STRUCT ALREADY APPLIES COMMANDS. Because a
setpoint is usually not just a number to store. A recipe change wants to be
validated, a pump start wants an interlock checked, a mode change wants to be
logged. SPARKPLUG_STRUCT with WRITABLE writes the value straight into the
struct member and reports it back, which is right for a plain setpoint and
wrong for anything that needs a decision.

So: leave those members out of the writable struct, declare them with
SPARKPLUG_METRIC, and watch them here. PENDING goes true, the rung decides, and
the program writes the value where it belongs - or does not.

THE PAIR IS THE POINT. This is the callback-and-pollable pattern the whole
library follows, and it exists because generated ladder cannot register a
handler. PENDING and VALUE are the pollable half.

ACK CLEARS IT, so two rungs cannot both act on one command. That is the same
rule the MQTT_STATUS counters follow, and for the same reason: a command applied
twice is a pump started twice.

NO REPLY TOPIC. A Sparkplug command is not a request/response - the
acknowledgement is that the metric's next DATA message carries the new value,
which is what a host watches for. Publish the value back and the host has its
answer.

---

## SPARKPLUG_DAY_TOTALS

```
A small table of daily totals, kept by the project and sent on every birth
as historical values, so SCADA fills in the days the link was down.

NODE    which node. Must be wired.
TABLE   the days: ARRAY OF SPARKPLUG_DAY (DAY : DATE, TOTAL : REAL). Retain it.
        The FIRST row is today, saved every SAVE_EVERY; the rows after it
        are the days closed so far, newest first. 31 rows keep a month.
NAME    the metric, e.g. 'pumpedDay'. Its live value is the last closed day.
VALUE   today's running total, from your totaliser.
CLOCK   local date and time - the same clock your totaliser rolls its day on.
SAVE_EVERY  how often today's running total is written into TABLE (T#1h).
        TABLE is retained, and a retained store saves the whole of retained
        memory whenever any of it changes - every scan would be a save every
        flush period (flash wear on a board). A day that closes while the PLC
        runs is closed with its exact total all the same; only a power cut
        loses up to SAVE_EVERY of today. T#0s writes every scan.

DAYS    closed days held.
SENT    day values sent since the program started.
ERROR   the metric could not be declared, or TABLE has fewer than two rows.
STATUS  why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |
| `TABLE` | `ARRAY [*] OF SPARKPLUG_DAY` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `NAME` | `STRING(32)` |  |
| `VALUE` | `REAL` |  |
| `CLOCK` | `DT` |  |
| `SAVE_EVERY` | `TIME` | `T#1h` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `DAYS` | `INT` |  |
| `SENT` | `UDINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

VAR_GLOBAL RETAIN
    PUMPED_DAYS : ARRAY[0..31] OF SPARKPLUG_DAY;
  END_VAR

  days(NODE := sp, TABLE := PUMPED_DAYS, NAME := 'pumpedDay',
       VALUE := pumped.today, CLOCK := localNow);

WHEN THE DATE ON CLOCK CHANGES the day just ended is closed: its total - the
value VALUE had on the scan before - moves into the table as the newest
closed day, and the table shifts down a row (the oldest falls off). A day
closed across a power cut is closed when the PLC comes back, from the
retained table (today's total as last saved), so nothing is counted twice. Nothing happens while the
clock is not set (before 2020).

ON EVERY BIRTH every closed day is published as a historical value of NAME,
time-stamped at 00:00 of its date (the date as CLOCK has it, written as UTC -
read the date, not the hour). A host files them in its history and does not
overwrite the live value, which is the last closed day. Sending the same day
twice is harmless: it lands on the same timestamp. A day closed while the
node is born goes at once the same way.

Use it beside SPARKPLUG_HISTORY: the events say what happened and when, the
day totals and counters say how much.

---

## SPARKPLUG_DEVICE

```
A DEVICE UNDER A SPARKPLUG NODE.

NODE      which node. Must be wired.
DEVICE    this device's ID. Must be unique among this node's devices.
ONLINE    TRUE births the device, FALSE kills it. Edge triggered, so holding it
          TRUE does not republish.
ENABLE    FALSE leaves the device alone entirely.

IS_ONLINE whether the device's birth certificate has gone.
BIRTHS    how many times it has birthed - which rises on every reconnect,
          because a device's birth is owed again each time its node births.
          Counted when its birth has gone (IS_ONLINE rising), not when it
          was asked for: a birth the queue had no room for waits, owed.
DEATHS    how many death certificates have gone.
ERROR     something failed.
STATUS    MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `DEVICE` | `STRING(47)` |  |
| `ONLINE` | `BOOL` | `TRUE` |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `IS_ONLINE` | `BOOL` |  |
| `BIRTHS` | `DINT` |  |
| `DEATHS` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

WHAT A DEVICE IS FOR. A node is the thing with the MQTT connection; a device is
something the node speaks FOR - a pump, a meter, a drive on a bus behind it.
The distinction is worth making when the node can be up while the thing it
reports on is not: a PLC talking to four VFDs over Modbus is one node and four
devices, and a VFD that stops answering gets a death certificate while the node
stays connected and keeps reporting the other three.

If everything lives or dies with the PLC, do not use this. Put the metrics on
the node and save yourself four topics.

YOU DO NOT NEED THIS BLOCK TO USE A DEVICE. SPARKPLUG_STRUCT and
SPARKPLUG_METRIC add the device themselves when their DEVICE pin is set, and
bring it online. This block is for when the device's presence is a decision the
program makes - which is the case that matters, because a device that is
"online" whenever the PLC is running is not telling anybody anything.

WITH THIS BLOCK, ITS ONLINE PIN DECIDES, whichever block is called first: a
SPARKPLUG_STRUCT or SPARKPLUG_METRIC under the same DEVICE declares its metrics
there but leaves the device's presence alone, so ONLINE := FALSE holds it
offline from the first scan - births included.

A DEATH CERTIFICATE CARRIES A SEQUENCE NUMBER. A node's does not. That is the
specification's rule, not a choice, and the library handles it - mentioned here
because it is the single most surprising thing about Sparkplug's two death
messages.

ORDER IS ENFORCED FOR YOU. A device cannot birth before its node has; asking
for it early leaves the birth OWED and it goes as soon as the node births. So a
program does not have to sequence itself against the link coming up.

---

## SPARKPLUG_HISTORY

```
Keeps events while the link is down and sends them after it comes back,
flagged historical, in order, at the time they happened.

NODE       which node. Must be wired.
ADD        TRUE records one event on this call. Wire a one-scan pulse (an edge
           of the alarm, the stop, the deferral) - call the block again with
           other pins for more than one event in a scan.
SOURCE     what the event is about: a pump, an alarm number, a zone.
CODE       what happened: a status, fault or stop code. The HMI and SCADA hold
           the words for it.
VALUE      a number that goes with it: a level, a volume, a run time.
NAME       the metrics' prefix. 'Event' gives Event/source, Event/code,
           Event/value, Event/seq and Event/lost.
DEPTH      events kept while the node cannot publish. Fixed at the first
           call. 256 is about a week of a normal site's events, 6 KB of PSRAM.
BATCH      events per message when catching up.
PERIOD     the gap between catch-up messages, so a slow cellular link is not
           flooded.

STORED     events waiting to be sent.
LOST       events dropped because the buffer was full: the oldest go, the
           newest are kept. Also published as <NAME>/lost.
SENT       events sent since the program started.
REPLAYING  catching up after an outage.
ERROR      no memory for the buffer, or the metrics could not be declared.
STATUS     why. MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ADD` | `BOOL` |  |
| `SOURCE` | `UINT` |  |
| `CODE` | `UINT` |  |
| `VALUE` | `REAL` |  |
| `NAME` | `STRING(24)` | `'Event'` |
| `DEPTH` | `UINT` | `256` |
| `BATCH` | `UINT` | `20` |
| `PERIOD` | `TIME` | `T#1s` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `STORED` | `UINT` |  |
| `LOST` | `UDINT` |  |
| `SENT` | `UDINT` |  |
| `REPLAYING` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

history(NODE := sp, ADD := pumpStopped, SOURCE := 1, CODE := pump1.StopCode,
          VALUE := level);
  history(NODE := sp, ADD := alarmRaised, SOURCE := 100 + alarmNo, CODE := 1,
          VALUE := 0.0);

SPARKPLUG HAS NO STORE-AND-FORWARD OF ITS OWN. While the node is not born - no
cellular coverage, the broker away, the primary host offline - nothing is sent,
and after the next birth the host sees only the values as they are then: why
the pump stopped at 03:12 is gone. This block keeps those events and sends
them afterwards with Sparkplug's is_historical flag, which tells the host to
file each one at its own timestamp and NOT to overwrite the live tag with it
(Sparkplug B 3.0, the metric's is_historical field: "store and forward, or
sending local backup data during network communication losses").

EVERY EVENT IS ONE ROW of four metrics with the same timestamp: source, code,
value and seq (a count from 1 since the program started, so the host can see
that none is missing). While the node is born an event goes at once, as live
data; recorded while it is not, it waits and goes historical. A value that
repeats is still sent - an event is an event, not a change of value.

WHAT IS KEPT: events, not analogs. A level that moves every scan would fill
any buffer; the reasons, the stops, the alarms and the day totals
(SPARKPLUG_DAY_TOTALS) are what a host cannot reconstruct afterwards.
Totals and counters that only go up reconcile the rest by themselves.

NOT RETAINED. A power cut during an outage loses the waiting events; the
counters still reconcile. The buffer lives in PSRAM where the board has it.

THE CLOCK. An event recorded before MQTT_CLOCK has set the board's clock is
kept with the board's uptime and put on the clock as soon as it is set. Events
wait for the clock up to five minutes after the birth, then go with what they
have.

SENT AT LEAST ONCE. A message is published at QoS 0 like all Sparkplug data,
so an event is forgotten only after the node has stayed born for a moment
afterwards; a link that drops in that moment sends the batch again. The host
may see an event twice, never not at all - the timestamp and seq make the
duplicate obvious.

---

## SPARKPLUG_HOST

```
A SPARKPLUG B HOST APPLICATION: the other end of SPARKPLUG_NODE.

HOST_ID      this host's Sparkplug Host ID. It is a topic element and MUST be
             unique in the system. An edge node's PRIMARY_HOST pin carries this
             same string. Up to 47 characters.
GROUP        the group to watch, or empty for every group.
PRIMARY      whether to ask for a rebirth when a node's sequence skips.
REORDER      how long to let a gap fill before asking. T#0s asks at once.
ENABLE       FALSE publishes the offline STATE and stands the host down; the
             connection stays up for everything else on it.
CLIENT       the MQTT_CLIENT whose connection this host rides on. Must be
             wired; broker, TLS, login and protocol are set there.

LINK_UP      the client's MQTT session is up.
BORN         our STATE birth certificate is published, so nodes may rely on us.
NODES        edge nodes heard from.
ONLINE       how many of them are online now.
GAPS         sequence gaps seen across every node.
REBIRTHS     rebirths asked for.
ERROR        something is wrong; STATUS and LAST_ERROR say what. "out of
             memory for tracked nodes or metrics" when the host could not
             follow everything that arrived: it tracks as many nodes, and
             metrics per node, as memory holds, on a board and the Runtime
             alike. MQTT_WRONG_TASK: not in its MQTT_CLIENT's task.

     A host watches a group and keeps the current picture of every edge node in
     it - which nodes are online, what metrics they declared, what each one is
     reading now. SPARKPLUG_SUBSCRIBE reads a value out of that picture and
     SPARKPLUG_WRITE sends one back down.

     WHAT A HOST DOES THAT A NODE DOES NOT, and it is the reason this is a
     separate block rather than a mode of SPARKPLUG_NODE:

       - It publishes its OWN birth and death certificate on
         spBv1.0/STATE/<HOST_ID>, at QoS 1 and RETAINED. Retained, unlike a
         node's death certificate, because an edge node subscribing later has
         to find it waiting or it will never birth at all.
       - It reads names out of BIRTH certificates and resolves them against the
         aliases that data messages carry. A conformant node puts names only in
         its births; without the dictionary a host receives numbers it cannot
         name.
       - It notices gaps in a node's sequence number and, if PRIMARY is set,
         asks for a rebirth.

     PRIMARY_HOST on the node and HOST_ID here are the same string. A node
     configured with one will not birth until this host says it is online,
     which is how a plant avoids nodes publishing into a SCADA that is not
     listening.

     ONE CONNECTION, SHARED. The host is a layer on its MQTT_CLIENT's session
     and takes its Will - the offline STATE - and a clean session on every
     CONNECT, so no MQTT_PRESENCE and no SPARKPLUG_NODE on the same client: a
     connection carries one Will. Started on a session already up, it
     reconnects it once so the next CONNECT carries the STATE.

     ONE TASK. This block, SPARKPLUG_SUBSCRIBE and SPARKPLUG_WRITE run in the
     client's task, and the rest of the program trades values with them
     through globals.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `HOST_ID` | `STRING(47)` |  |
| `BROKER` | `STRING(128)` |  |
| `PORT` | `UINT` |  |
| `SECURITY` | `MQTT_SECURITY` |  |
| `USER` | `STRING(64)` |  |
| `PASSWORD` | `STRING(64)` |  |
| `PROTOCOL` | `MQTT_PROTOCOL` |  |
| `TRUST_NEW` | `BOOL` |  |
| `GROUP` | `STRING(47)` |  |
| `PRIMARY` | `BOOL` | `TRUE` |
| `REORDER` | `TIME` | `T#5s` |
| `CA_FILE` | `STRING(128)` |  |
| `CERT_FILE` | `STRING(128)` |  |
| `KEY_FILE` | `STRING(128)` |  |
| `KEEP_ALIVE` | `UINT` | `60` |
| `LINK` | `__XWORD` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `LINK_UP` | `BOOL` |  |
| `BORN` | `BOOL` |  |
| `NODES` | `INT` |  |
| `ONLINE` | `INT` |  |
| `GAPS` | `DINT` |  |
| `REBIRTHS` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |
| `BROKER_KEY` | `STRING(64)` |  |

---

## SPARKPLUG_METRIC

```
ONE SPARKPLUG METRIC, for what a STRUCT member cannot express.

NODE      which node. Must be wired.
NAME      the metric name, exactly as it will appear at the far end. Case
          matters: Sparkplug metric names are case sensitive. Up to 96
          characters, the most a board's metric holds.
VALUE     the value. Its DECLARED IEC type becomes the metric's datatype.
DEVICE    a device under the node, or empty for a node metric.
UNITS     engineering units - 'kPa', 'metres'. Carried in the birth certificate
          as the engUnit property, which is what makes a number mean something
          at the far end.
QUALITY   MQTT_QUALITY_GOOD, _UNCERTAIN, _BAD or _UNKNOWN. Carried in the
          birth as the Quality property, which Sparkplug fixes to one of
          three codes - so UNCERTAIN becomes stale and UNKNOWN becomes bad.
WRITABLE  TRUE lets a Host Application command it - an NCMD for a node
          metric, a DCMD for one under DEVICE.
          Every write is seen, one a scan, oldest first.
          Declared writable once; while WRITABLE is FALSE after that, a write
          is dropped at once and the metric reported back unchanged. It is
          never kept for later.
DEADBAND  for a number: a move of this much or less, from the value last SENT,
          is not reported. In VALUE's own units - 0.01 on a level in metres
          is 10 mm. 0 (the default) reports every change. A slow drift still
          adds up and goes, and a birth always carries the value as it is.
          Refused on a BOOL or a STRING.
ENABLE    FALSE stops publishing without losing the declaration.

ALIAS     the number the far end will see instead of NAME after the birth. 0
          means the declaration was refused.
WRITTEN   how many commands have been applied.
LOST      writes dropped because four were already waiting on this metric:
          the oldest goes, the newest is kept. 0 in any sane system.
ERROR     something failed.
STATUS    MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `NAME` | `STRING(96)` |  |
| `VALUE` | `ANY` |  |
| `DEVICE` | `STRING(47)` |  |
| `UNITS` | `STRING(16)` |  |
| `QUALITY` | `MQTT_QUALITY` |  |
| `WRITABLE` | `BOOL` |  |
| `PUBLISH` | `BOOL` | `TRUE` |
| `ENABLE` | `BOOL` | `TRUE` |
| `DEADBAND` | `REAL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ALIAS` | `UDINT` |  |
| `WRITTEN` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `LOST` | `DINT` |  |

USE SPARKPLUG_STRUCT WHERE YOU CAN. A struct gives you the metric name, the
datatype and the complete birth set from one declaration, and sends one message
for the lot. This block is for the cases it cannot cover: a value that is not a
member of anything, one that needs its own units and quality, or one whose
publishing is driven by different logic from the rest.

The two coexist happily on one node. Aliases come from a single counter, so a
metric here and thirty in a struct cannot collide.

NO QOS OR RETAINED PIN. Sparkplug fixes both.

THIS BLOCK DOES NOT PUBLISH ON ITS OWN. It writes the value into the node, and
the node publishes - one message carrying everything that moved, which is the
point of Sparkplug and the opposite of one topic per value. With PUBLISH (TRUE
unless wired otherwise) this block asks for that message, and SPARKPLUG_NODE
sends it on its next scan, once for every block that asked. Without it, a
SPARKPLUG_STRUCT or another SPARKPLUG_METRIC on the same node triggers the
send; if this is the only metric on the node, set MODE on its struct or use
REQ.

---

## SPARKPLUG_NODE

```
A SPARKPLUG B EDGE NODE. One block, and the other SPARKPLUG_* blocks hang
off it.

GROUP        the Sparkplug Group ID. A logical grouping of nodes - a pipeline
             segment, a manufacturing cell. Descriptive but small: it is in
             every topic. Up to 47 characters, as every Sparkplug id here.
NODE         this node's ID. GROUP and NODE together are the node's address in
             the whole system and MUST be unique in it.
PRIMARY_HOST the Sparkplug Host ID this node answers to, or empty for none.
             EMPTY BY DEFAULT - see below.
ENABLE       FALSE keeps the node down without losing its metric declarations.
CLIENT       the MQTT_CLIENT whose connection this node rides on. Must be
             wired. Everything about the connection is set there - broker,
             TLS, login, keep-alive, protocol - and with it the device's own
             topics and its firmware updates share the one session.

LINK_UP      the client's MQTT session is up.
BORN         the birth certificate has gone. NOT the same as LINK_UP: a node
             waiting for its primary host is connected and not born, and until
             it is born nothing else publishes.
SEQ          the current sequence number, 0-255.
BDSEQ        the birth/death sequence number for this connection.
POINTS       how many metrics are declared. There is no limit but memory,
             metrics and devices alike, on a board and the Runtime: the tables
             grow with what is declared and, on a board, live in PSRAM where
             there is some. Past what memory holds, the declaration is refused
             on the declaring block's ERROR and LAST_ERROR here says "out of
             memory for metrics or devices".
CLOCK_SET    the timestamps are real time. Always on the Runtime; on a board
             once MQTT_CLOCK (NTP, or the mobile network's time) has set the
             clock. Until then they count from boot - a date in January 1970 -
             which a host should take as "not synced" and replace with the time
             it received the message.
STATUS       MQTT_OK when fine. MQTT_WRONG_TASK: this block is not in its
             MQTT_CLIENT's task, and does nothing until it is.
LAST_ERROR   with LINK_UP and not BORN, what the node is waiting for, which
             says where to look (why the link is down is on MQTT_CLIENT):
               "no STATE from primary host 'scada'"     the host has never
                                                         reached this broker
               "offline STATE from primary host 'scada'" the host is down
               "broker refused STATE/scada subscription (not authorized)"
               "birth could not be queued - retrying"
               "out of memory for metrics or devices"
               "another layer owns the client's Will"   a SPARKPLUG_HOST or a
                                                         second node on CLIENT
             Empty once born.
(The handle the other SPARKPLUG_* blocks take is a local, not a pin - see the
declaration. Nothing on a rung needs it.)
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `CLIENT` | `MQTT_CLIENT` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `GROUP` | `STRING(47)` |  |
| `NODE` | `STRING(47)` |  |
| `BROKER` | `STRING(128)` |  |
| `PORT` | `UINT` |  |
| `SECURITY` | `MQTT_SECURITY` |  |
| `USER` | `STRING(64)` |  |
| `PASSWORD` | `STRING(64)` |  |
| `PROTOCOL` | `MQTT_PROTOCOL` |  |
| `TRUST_NEW` | `BOOL` |  |
| `PRIMARY_HOST` | `STRING(47)` |  |
| `CA_FILE` | `STRING(128)` |  |
| `CERT_FILE` | `STRING(128)` |  |
| `KEY_FILE` | `STRING(128)` |  |
| `KEEP_ALIVE` | `UINT` | `60` |
| `LINK` | `__XWORD` |  |
| `ENABLE` | `BOOL` | `TRUE` |
| `TRANSPORT` | `MQTT_LINK` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `LINK_UP` | `BOOL` |  |
| `BORN` | `BOOL` |  |
| `SEQ` | `USINT` |  |
| `BDSEQ` | `USINT` |  |
| `POINTS` | `INT` |  |
| `SERVER` | `INT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |
| `BROKER_KEY` | `STRING(64)` |  |
| `CLOCK_SET` | `BOOL` |  |

WHY SPARKPLUG AND NOT MQTT_CLIENT. Two things, and they are the reasons a SCADA
system wants it.

A TOPIC IS A ONE-WAY PIPE, so a writable setpoint under plain MQTT needs two of
them - one to write and one to read back. That is where the _FB suffix in the
pump-station project came from. Under Sparkplug the direction is in the MESSAGE
TYPE rather than the topic: the host writes SETPOINT with a command, the node
publishes SETPOINT with its data, one name, one struct member. No readback pair.

AND THE DATATYPE IS DECLARED. Every metric's type travels in the birth
certificate, so the far end is told REAL rather than inferring it from the first
sample it happens to see. A counter that started at zero will not be filed as an
integer and then refuse a decimal.

WHAT IT COSTS. The metric set is CLOSED. The birth certificate must carry every
metric the node will ever publish, so everything is declared before the node
births and a write to an undeclared name is refused rather than invented. In
practice that means SPARKPLUG_STRUCT blocks are wired on the first scan and the
node births on the second, which is what ENABLE and BORN are for.

PRIMARY_HOST IS EMPTY BY DEFAULT, deliberately. Set it and this node will not
publish ANYTHING until that host announces itself online - which is correct for
a system with one nominated master, and is what stops a node shouting into a
broker nobody is reading. Leave it empty and the node births as soon as it
connects. A node waiting for a host that does not exist looks exactly like a
node that is broken, so the default is the one that cannot be mistaken.

ONE CONNECTION, SHARED. Sparkplug runs over MQTT, and so does everything
else a device says: this node is a layer on the MQTT_CLIENT's session, not a
second connection. What Sparkplug needs of that session it takes on every
CONNECT: the Will is this node's NDEATH, so no MQTT_PRESENCE on the same client
(the birth and death certificates are the presence); the session is always
clean, whatever MQTT_CONFIG says; and the transmit buffer grows to hold the
birth certificate. Started on a session already up, the node reconnects it
once so the next CONNECT carries the NDEATH - every other block on the client
sees one reconnect. The same when the primary host goes offline: Sparkplug
requires a new session, so the client reconnects.

ONE MESSAGE A SCAN. The other blocks do not send their values: a
SPARKPLUG_STRUCT or SPARKPLUG_METRIC with something to say marks it and asks,
and this block, on its next scan, sends ONE NDATA - and one DDATA for each
online device with something to say - carrying everything on the node that
moved, however many blocks asked. Births, deaths and SPARKPLUG_HISTORY's
records still go when they happen.

ONE TASK. This block and every block on CLIENT run in the client's task - the
network task - and the machine's program trades values with them through
globals. In another task it says MQTT_WRONG_TASK and does nothing.

GROUP, NODE AND PRIMARY_HOST MAY CHANGE WHILE IT RUNS. A change leaves under
the old identity (the host sees the NDEATH) and births under the new one with
the next bdSeq; declarations and devices stay, so nothing else in the program
notices. ENABLE FALSE sends the NDEATH and leaves the connection to everything
else on it.

ONE NODE PER CLIENT: a connection carries one Will, so a second node needs a
second MQTT_CLIENT. Nothing here is process-wide.

---

## SPARKPLUG_STRUCT

```
A WHOLE STRUCT AS A SPARKPLUG METRIC SET. One block.

NODE       which node. Must be wired.
DATA       the STRUCT. Every value in it becomes one metric - nested STRUCTs
           and arrays included, named by path: level, pump.hours, spare[3].
DEVICE     a device under the node, or empty for the node's own metrics.
PREFIX     put before every metric name: 'Cmd/' makes systemMode the metric
           Cmd/systemMode. Empty by default. The same rule as BeeBus topics.
MODE       what triggers a message:
             MQTT_ON_CHANGE    only the members that moved, and all of them
                               anyway every PERIOD so silence stays
                               meaningful.
             MQTT_ON_INTERVAL  all of them, every PERIOD - and only then.
             MQTT_ON_REQUEST   all of them when REQ goes TRUE, never otherwise.
             MQTT_CHANGED_EVERY  the members that moved past their
                               deadband since they were last sent, together,
                               every PERIOD - and nothing when none moved. For
                               a metered link: a slow log of what changed. The
                               looks fall on the node's clock (whole PERIODs),
                               so every set with the same PERIOD goes in ONE
                               message.
           "All of them" is this block's members, never the rest of the
           node. In every mode but MQTT_ON_CHANGE the members are HELD: they
           do not ride along in other blocks' reports when they move, so a
           set of timers that changes every scan really goes every PERIOD.
PERIOD     MQTT_ON_CHANGE: send anyway after this long. T#0s never does.
           MQTT_ON_INTERVAL: how often. Required there.
           MQTT_CHANGED_EVERY: how often it looks for what moved. Required.
REQ        MQTT_ON_REQUEST: a rising edge sends the set.
WRITABLE   TRUE lets a Host Application COMMAND these members, each one by
           itself. Under a DEVICE the commands are DCMDs, and land the same way.
           Every write is seen, one a scan, oldest first: SCADA writing 1 and
           then 0 in one go leaves the member 1 for a scan and then 0.
           Declared writable once; while WRITABLE is FALSE after that, a write
           is dropped at once and counted on REFUSED, and the next message
           reports the member unchanged. It is never kept for later.
DEADBAND   REAL and LREAL members with no SETTINGS entry: a move of this much
           or less, from the value last SENT, is not reported. In the members'
           own units.
DEADBAND_PCT  the same, as a percentage of the value last sent. With both set
           a move must clear both. 0 (the default) reports every change.
SETTINGS   optional: an ARRAY OF SPARKPLUG_MEMBER, one entry per member that
           needs its own - see below.
ENABLE     FALSE stops publishing without losing the declarations. The set
           is held while FALSE and keeps its values current in the node, so a
           birth carries them as they are.

POINTS     how many values are declared as metrics.
SKIPPED    how many were not - a type the wire cannot carry, or a name already
           taken. Counted here, and ERROR is set.
SENT       running total of the messages that carried these members: one for
           each scan with something to send, not one per member. Counted when
           SPARKPLUG_NODE has sent it - on the scan after the one that asked.
           The members of every block that moved in one scan go in ONE
           message, and each of those blocks counts it.
CHANGED    how many members this scan handed to the node to send because they
           moved - past their deadband - or, when PERIOD or REQ sends them
           all, how many of them changed. They go on SPARKPLUG_NODE's next
           scan.
WRITTEN    how many commands have been applied to these members.
REFUSED    how many were refused - a value of the wrong type, or a write
           while WRITABLE is FALSE.
LOST       writes dropped because four were already waiting on one member:
           the oldest goes, the newest is kept. 0 in any sane system.
BAD_SETTING  the first SETTINGS entry that could not be used, counting from 1:
           a NAME that covers no member, a negative deadband or PULSE, a
           deadband on a BOOL or STRING. The other entries still apply. -1: SETTINGS is not an ARRAY OF
           SPARKPLUG_MEMBER, or DEADBAND is negative. 0 when all is well.
ERROR      something failed - including BAD_SETTING, until it is fixed.
STATUS     MQTT_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `NODE` | `SPARKPLUG_NODE` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `DATA` | `ANY` |  |
| `DEVICE` | `STRING(47)` |  |
| `MODE` | `MQTT_TRIGGER` |  |
| `PERIOD` | `TIME` |  |
| `REQ` | `BOOL` |  |
| `WRITABLE` | `BOOL` |  |
| `ENABLE` | `BOOL` | `TRUE` |
| `DEADBAND` | `REAL` |  |
| `DEADBAND_PCT` | `REAL` |  |
| `PREFIX` | `STRING(32)` |  |
| `SETTINGS` | `ANY` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `POINTS` | `INT` |  |
| `SKIPPED` | `INT` |  |
| `SENT` | `DINT` |  |
| `CHANGED` | `INT` |  |
| `WRITTEN` | `DINT` |  |
| `REFUSED` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |
| `BAD_SETTING` | `INT` |  |
| `LOST` | `DINT` |  |

SPARKPLUG_MEMBER, one entry per member that needs its own settings:

  NAME          the member's path: 'levelMm', 'pump.hours', 'spare[3]'.
                Without PREFIX. Case does not matter. A whole array or nested
                STRUCT ('spare', 'pump') covers every value in it; entries
                apply in order, so a later one for spare[2] wins for it.
  UNITS         engineering units, sent in the birth as engUnit: 'mm', 'bar'.
  DEADBAND      its own deadband, in its units. 0 = every change.
  DEADBAND_PCT  its own deadband as a percentage of the value last sent.
                An entry's deadband replaces the block's for that member.
  LOW, HIGH     the range a SCADA gauge or trend should show, sent in the
                birth as engLow and engHigh. LOW = HIGH (both 0) for none.
  PULSE         a writable command the PLC clears by itself: this long after
                a write lands, the member goes back to 0 (FALSE, ''). T#0s,
                the default, keeps what was written.
  SKIP          TRUE leaves the member out: not a metric at all. FALSE puts
                back one an earlier entry left out, with this entry's
                numbers: [(NAME := 'sts', SKIP := TRUE),
                (NAME := 'sts.mode', SKIP := FALSE)] leaves out all of sts
                but sts.mode. Read once, when the metrics are declared.

  VAR
    sp      : SPARKPLUG_NODE;
    core    : SPARKPLUG_STRUCT;
    coreSet : ARRAY[1..3] OF SPARKPLUG_MEMBER := [
                (NAME := 'levelMm', UNITS := 'mm', DEADBAND := 10.0,
                 LOW := 0.0, HIGH := 3000.0),
                (NAME := 'pressureBar', UNITS := 'bar', DEADBAND := 0.02),
                (NAME := 'pumpHours', UNITS := 'h', DEADBAND := 0.1)];
  END_VAR

  coreSet[1].DEADBAND := CFG.levelDeadband;
  core(NODE := sp, DATA := CORE, SETTINGS := coreSet);

The settings are read again whenever they change - a deadband may follow a
setting from CFG every scan. Units and ranges go out in the birth, so a change
to them shows at the next birth.

A COMMAND STRUCT. Commands from SCADA are members of a WRITABLE struct like
any setpoint, each its own metric, written one at a time:

  cmds(NODE := sp, DATA := CMD.remote, PREFIX := 'Cmd/', WRITABLE := TRUE,
       SETTINGS := cmdSet);

A held signal - a run request, a mode - stays as written. A momentary command
needs the bit to go back to 0 before the next one. Either SCADA writes the
bit and then 0 - every write is queued and taken in order, so even a 1 and a
0 sent together are both seen - or the member gets PULSE in SETTINGS
(T#500ms, longer than the slowest task that reads it) and the PLC clears it,
so SCADA writes once per command.

---

THE STRUCT DECLARATION IS THE METRIC SET, and under Sparkplug that buys three
things at once rather than one.

  1. THE MEMBER PATH IS THE METRIC NAME, after PREFIX. Rename a member and you
     rename a metric, which is a real consequence and worth knowing before the
     third device is commissioned.
  2. THE DECLARED IEC TYPE IS THE METRIC DATATYPE. REAL becomes Float, UDINT
     becomes UInt32, and the birth certificate carries it - so the receiving
     end is TOLD the type rather than guessing it from the first value.
  3. THE MEMBER SET IS THE BIRTH CERTIFICATE. Sparkplug requires the birth to
     carry every metric the node will ever publish; a STRUCT is a closed,
     declared set, so that is satisfied by construction.

ONE MESSAGE, NOT N. The node sends ONE message carrying every metric that
moved - this block's, and every other block's on the node. That is the whole
bandwidth argument for Sparkplug, and on a metered link it is most of the
saving. This block marks what is to go and asks; SPARKPLUG_NODE sends one
NDATA, and one DDATA for each online device with something to say, on its
next scan, with that moment's timestamp. A message the node could not queue
shows here as ERROR with MQTT_QUEUE_FULL, on the scan after, and is asked for
again.

WRITABLE MAKES IT BIDIRECTIONAL ON ONE NAME. The host commands SETPOINT, this
block publishes SETPOINT, one struct member. A command lands in the STRUCT and
the next publish reports it back - always, even inside a deadband, because the
host watches for that echo to know the write took. Put readings and setpoints
in separate structs: WRITABLE declares every member writable.

THERE IS NO QOS OR RETAINED PIN. Sparkplug fixes both: data at QoS 0 and never
retained.

THE BLOCK'S DEADBAND IS FOR THE ANALOGS. One number covering members of mixed
types is a trap - a BOOL counts as 1, so a deadband above that would freeze
every bit in the struct including a FAULT - so DEADBAND and DEADBAND_PCT apply
to the REAL and LREAL members without a SETTINGS entry. BOOLs, integers and
STRINGs report every change unless an entry gives an integer its own. Measured
from the value last SENT, never the last scan, so a slow drift still adds up
and goes; the PERIOD heartbeat and a birth always carry every value as it is.

A TIME GOES AS AN Int64 OF MILLISECONDS, both ways, with units ms in the
birth: T#10s is 10000, and a host writing 90000 sets T#90s. Negative writes are
refused.

WHEN IT GOES, IN EACH MODE. The birth carries every member, whatever the mode:
a device that comes online (SPARKPLUG_DEVICE's ONLINE going TRUE) sends the
whole set in its DBIRTH, and MQTT_ON_INTERVAL counts PERIOD from that birth.
ENABLE going TRUE sends an MQTT_ON_INTERVAL set at once, then every PERIOD;
an MQTT_CHANGED_EVERY set sends what moved at once (not when its device was
born that scan: the birth carried it), then looks every PERIOD.
Nothing goes for a device that is offline.

AN ENUMERATION GOES AS THE UNSIGNED INTEGER IT IS STORED AS (UInt8, UInt16 or
UInt32 by its size), both ways: the value's code, as the library documents it.
A written code the type does not have is the program's to refuse, as for any
setting.

A VALUE THE WIRE CANNOT CARRY IS REFUSED, NOT SKIPPED QUIETLY. A DATE,
TIME_OF_DAY, or an ARRAY OF STRING outside a STRUCT: counted on SKIPPED.

HOW MANY MEMBERS: as many as the node takes - as many as memory holds, on a
board (in PSRAM where there is some) and the Runtime alike. A member past that
is refused and counted on SKIPPED, and SPARKPLUG_NODE's LAST_ERROR says "out
of memory for metrics or devices".

---

## SPARKPLUG_SUBSCRIBE

```
READ ONE METRIC from a node a SPARKPLUG_HOST is watching.

The host keeps the current picture of the plant - every metric every edge node
declared, and what each one is reading now. This block takes one value out of
it and writes it into an IEC variable of the engineer's own type.

THE NAME IS THE ADDRESS, not a topic and not an alias. That is the whole point
of the protocol: the edge node declared "level" in its birth certificate and
this block asks for "level". A conformant node sends data by alias only and the
host resolves it back, so nothing here has to know what an alias is.

THE DECLARED TYPE IS CHECKED, not coerced. If the birth said "level" is a REAL
and VALUE is wired to a DINT, the read is REFUSED and TYPE_OK goes false rather
than silently truncating a reading a control decision is about to be made on.

NAME         the metric name, exactly as the edge node declared it.
VALUE        where to put it. Any IEC type; it must match what was declared.
NODE_ID      which edge node. Empty means the first node the host heard from,
             which is convenient with one node and wrong with two.
GROUP        which group. Empty means the host's watched group.
DEVICE       for a metric belonging to a device rather than the node itself.
ENABLE       false stops reading and holds VALUE at its last value.

VALID        the value was read and written into VALUE this scan.
TYPE_OK      false means VALUE's type does not match what the birth declared.
FRESH        the reading changed since the last scan.
AGE          milliseconds since the node's own timestamp on it. Not since we
             received it - on a slow link those differ by more than a control
             decision should ignore.
ERROR        something is wrong; STATUS says what.

NOT VALID IS NOT AN ERROR by itself. A node that has not birthed yet, a metric
that has not been published yet and a node that has died all read as VALID
false, and all three mean the same thing to a rung: do not act on this.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `HOST` | `SPARKPLUG_HOST` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `NAME` | `STRING(96)` |  |
| `VALUE` | `ANY` |  |
| `NODE_ID` | `STRING(47)` |  |
| `GROUP` | `STRING(47)` |  |
| `DEVICE` | `STRING(47)` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `VALID` | `BOOL` |  |
| `TYPE_OK` | `BOOL` |  |
| `FRESH` | `BOOL` |  |
| `AGE` | `DINT` |  |
| `READS` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

---

## SPARKPLUG_WRITE

```
WRITE ONE METRIC on an edge node, from a SPARKPLUG_HOST.

This is the other direction: an NCMD, or a DCMD for a device metric. The edge
node applies it to whatever its SPARKPLUG_METRIC or SPARKPLUG_STRUCT block is
wired to, and reports the new value back under the SAME metric name.

THAT IS WHY THERE IS NO `_fb` TOPIC HERE. Under plain MQTT a writable setpoint
needs two topics - one to command and one to read back - and two tags at the
far end that nothing guarantees are the same number. Under Sparkplug the
direction lives in the message type, so one name is read and written.

THE NODE DECIDES. A command for a metric the node never declared, or declared
read-only, or declared with a different type, is REFUSED there and counted -
this block reports that it sent one, not that it took effect. Wire a
SPARKPLUG_SUBSCRIBE to the same NAME to see the value come back.

NAME         the metric name, exactly as the edge node declared it.
VALUE        what to write. Its IEC type must match what the birth declared.
REQ          rising edge sends. A level would send every scan.
NODE_ID      which edge node. Empty means the first node the host heard from.
GROUP        which group. Empty means the host's watched group.
DEVICE       for a metric belonging to a device rather than the node itself.
ENABLE       false sends nothing.

SENT         one command left this scan.
COUNT        how many have been sent.
ERROR        something is wrong; STATUS says what.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `HOST` | `SPARKPLUG_HOST` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `NAME` | `STRING(96)` |  |
| `VALUE` | `ANY` |  |
| `REQ` | `BOOL` |  |
| `NODE_ID` | `STRING(47)` |  |
| `GROUP` | `STRING(47)` |  |
| `DEVICE` | `STRING(47)` |  |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SENT` | `BOOL` |  |
| `COUNT` | `DINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `MQTT_RESULT` |  |

---

**Next:** [08 Patterns](08-patterns.md)
