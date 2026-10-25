# Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## It never connects

Read `net.LAST_ERROR` first. It carries the operating system's own words,
because no status code can say which of forty things went wrong at a socket.

| what it says | what it is |
| --- | --- |
| *Connection refused* | nothing is listening on that host and port. Wrong port, or the broker is not running |
| *Name or service not known* | DNS. Use an address, or fix the resolver |
| *No route to host* | wrong subnet, or a firewall |
| *Connection timed out* | a firewall dropping rather than refusing |
| *that transport needs a board, not the Runtime* | `TRANSPORT` names an Arduino link on the Runtime |
| *set HOST to the broker* | the pin is empty |

If `LAST_ERROR` is empty and `STATE` sits at `MQTT_CONNECTING`, the socket
opened and the broker has not answered. That is a broker that accepted a
connection and then said nothing — check it is actually an MQTT broker on that
port, and not, say, a web server.

Check it from a desk first:

```bash
mosquitto_pub -h 10.0.0.20 -t test -m hello
```

If that fails too, the PLC is not the problem.

## It connects, then drops, then connects again

`MQTT_STATUS.RECONNECTS` climbing is the symptom.

| | |
| --- | --- |
| **Another device has the same `CLIENT_ID`** | `STATUS` shows `MQTT_SESSION_TAKEN_OVER`. Two devices are displacing each other for ever. **Check this first** — it is the commonest cause and it looks healthy from either end |
| **Keepalive too short for the link** | `MQTT_KEEPALIVE_TIMEOUT`. Raise `KEEP_ALIVE` on `MQTT_CONFIG`, especially on cellular |
| **The broker is restarting** | its own log will say |
| **A NAT or firewall dropping idle connections** | lower `KEEP_ALIVE` so traffic keeps the mapping alive. The opposite fix to the one above, which is why the log matters |

## It connects but nothing arrives

**Check the filter against the topic.** Wildcards are `+` for one level and
`#` for the rest, and `#` must be last. `plant/level` does not match
`plant/intake/level`.

**Check something is publishing.** From a desk:

```bash
mosquitto_sub -h 10.0.0.20 -t 'plant/#' -v
```

If that shows nothing, the problem is upstream of this PLC.

**Check `MQTT_SUBSCRIBE.SUBSCRIBED`.** False means the subscription is not
established — usually not connected, sometimes refused by an access rule, in
which case `STATUS` says `MQTT_NOT_AUTHORIZED`.

**Check `MALFORMED`.** Climbing means messages *are* arriving and none of them
parse as `VALUE`'s type. A publisher sending `23,5` to a `REAL`, or JSON to a
number. Use `MQTT_MESSAGE` to see the raw text.

## A value arrives but QUALITY is never GOOD

`EXPECT` is shorter than the publisher's own interval. Quality is
judged against the interval *you* asked for, so asking for a value every
second from something that publishes every minute is permanently overdue.

Set it to a little more than the publisher's `PERIOD`.

## QUALITY is UNKNOWN and stays UNKNOWN

Nothing has ever arrived on that filter. This is a **commissioning** fault,
not a running one — a typo in the topic, a publisher never deployed, a
wildcard that does not match what you think. Take it to a desk with a drawing
rather than a torch to the plant.

## Publishing says DONE but nobody sees it

**`MQTT_NO_MATCHING_SUBSCRIBERS` on `STATUS`** means the broker took it and
nobody was listening. The link is fine.

**Check retain.** A subscriber that connects afterwards hears nothing unless
the message was retained.

**Check the prefix if a bridge is involved.** `REMOTE_PREFIX := 'sites/site7/'`
means the far side sees `sites/site7/plant/intake/level`, not
`plant/intake/level`.

## BUSY never clears

On `MQTT_PUBLISH` at QoS 1 or 2, `BUSY` stays until the broker acknowledges.
If it never does:

- the link dropped mid-flight — `STATUS` becomes `MQTT_CONNECTION_LOST`
- the broker's receive maximum is exhausted — `MQTT_QUOTA_EXCEEDED_BY_PEER`

On `MQTT_REQUEST`, `BUSY` clears at `TIMEOUT` with
`MQTT_KEEPALIVE_TIMEOUT`. If you left `TIMEOUT` at `T#0s` that is five seconds.

## STATUS says MQTT_NOT_SUPPORTED_BY_PROTOCOL

You asked for something 3.1.1 cannot express, on a 3.1.1 connection. Check
`MQTT_STATUS.VERSION` — if it says 4, the fallback happened.

`MQTT_REQUEST` is the usual one: Response Topic and Correlation Data do not
exist before 5.0, and sending the request stripped would mean the responder
has nowhere to reply to. Refused rather than sent into the void.

A Will **delay** is the other. The node refuses to connect at 3.1.1 with a
delay set, rather than dropping it — a delay silently lost turns a flapping
link into a stream of false offline alarms, which is the exact failure the
delay was set to prevent.

## STATUS says MQTT_WRONG_TASK

The block is in a different task from its client - or, for a `SPARKPLUG_*`
block, from its node; for `MQTT_BROKER_USER`, from its broker. It does nothing
until it is moved: OpenPLC runs each task on a thread of its own, and a block
in another task would be inside the client while the client's own scan is.

Move it into the network task, beside its client. Where the machine's program
needs the value, hand it over through a global (page 10, "Trading values with
the machine").

## SPARKPLUG_NODE says "another layer owns the client's Will"

A connection carries one Will, and a `SPARKPLUG_HOST` or a second
`SPARKPLUG_NODE` on the same `MQTT_CLIENT` has it. Give the second one an
`MQTT_CLIENT` of its own.

An `MQTT_PRESENCE` on that client is the other way round: the node keeps the
Will and the presence block says `MQTT_REFUSED` - Sparkplug's birth and death
certificates are the presence.

## Everything works but feels slow

Page 10. The node's task interval is almost always the answer.

## It works on the Runtime and not on a board

**Ethernet needs `MQTT_ENABLE_ETHERNET`**, a define in the board package's
compiler flags. Page 03 explains why it is a define rather than automatic.

**Cellular needs `modbee-gsm`**, which is a separate library, and a `GSM_MODEM` in the
program. Until the modem has a data connection (`GSM_MODEM.READY`) the client
says why on `LAST_ERROR` and keeps retrying.

**TLS on a board** is the same on Wi-Fi, Ethernet and cellular on an ESP32 (page
03). It makes the same checks as the Runtime, and says why it refused in a
short fixed line. Where the TLS engine gave a code, it follows the line in
hexadecimal - *TLS: broker refused us -0x7780* - and is mbedTLS's own error
number, for when the line is not enough.

| `LAST_ERROR` on a board | What to do |
| --- | --- |
| *a board needs the CA in MQTT_CA_CERT_PEM* | `MQTT_TLS_VERIFY` with no CA defined. For the site's own broker use `MQTT_TLS_PINNED` with `TRUST_NEW`; for a signed one, add the CA to the board package |
| *no pinned key yet - set TRUST_NEW once to learn it* | `MQTT_TLS_PINNED` on a link that has never connected |
| *cannot connect to the broker* | nothing answered on `HOST` and `PORT`: the broker is down, the port is wrong, or the network is not up. On cellular the modem's own reason is shown instead when it has one |
| *TLS: certificate not trusted* | `MQTT_CA_CERT_PEM` is not the CA that signed this broker - or the broker sends its certificate without the intermediate |
| *TLS: wrong host name* | `HOST` is not a name on the certificate. Use the name it was issued to, not the address |
| *TLS: bad certificate* | the broker's certificate failed some other check (its key usage, its signature) or would not read |
| *TLS: not the pinned key* | the broker was replaced, or `HOST` is wrong. `BROKER_KEY` shows the key it presented. To accept a replacement, switch `TRUST_NEW` off and on |
| *TLS: broker sent no cert* | pinned, and the broker sent no certificate to compare |
| *TLS: broker refused us* | the broker ended the handshake. Most often it wants a client certificate (`MQTT_CLIENT_CERT_PEM`), or refuses the one sent |
| *TLS: no common version/cipher* | the broker allows only TLS 1.3, or only cipher suites a board does not offer. Allow TLS 1.2 on the broker |
| *TLS handshake timed out* | the handshake did not finish within the connect timeout: a slow or lossy link (cellular at the edge of coverage), or a broker that accepts and then says nothing. Raise `CONNECT_TIMEOUT` on `MQTT_CONFIG` for a slow link |
| *TLS handshake failed* | any other handshake failure; the code says which |
| *TLS: out of memory* | the board could not find the memory for a TLS session (about 40 kB, in PSRAM where the board has it) |
| *TLS: CA certificate unreadable* / *TLS: client cert/key unusable* | `MQTT_CA_CERT_PEM`, or `MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM`, are not PEM, or a certificate came without its key |
| *the last connect is still finishing* | the attempt before outlived `CONNECT_TIMEOUT` and its socket is still opening; the next attempt waits for it. Raise `CONNECT_TIMEOUT` on `MQTT_CONFIG` for a slow link |
| *no memory for the connect task* | the board could not find the few kB of internal memory the connect runs in; it tries again after the backoff. Something else is holding the internal memory |
| *broker closed the connection* / *TLS: connection dropped* | the connection ended after it was up: the broker closed it, or the network went |
| *TLS over Ethernet needs an ESP32, or SSLClient* / *the modem's TLS checks no certificate* | a board without the ESP32's TLS engine: only what its medium offers |

On the Runtime `LAST_ERROR` carries the TLS library's own words instead, and a
key that is not the pinned one names both fingerprints.

**Check `MQTT_ARDUINO` is placed** and that `MAC` and `IP` are set. A board
with no MAC cannot open an Ethernet link, and every board on a segment needs
its own.

## It says not authorised

`STATUS = MQTT_NOT_AUTHORIZED` and `LAST_ERROR` reading *"the broker refused
the connection: ..."* means the broker answered the CONNECT with a no. The TCP
connection worked; the credential did not.

**Check `USERNAME` and `PASSWORD` on `MQTT_CONFIG`.** They are separate pins
and either can be set without the other — which is legal MQTT and what a
token-based broker wants, and also what a typo looks like.

**Check the block is placed.** `MQTT_CONFIG` costs nothing until you place it,
so a program with no `MQTT_CONFIG` sends no credential at all and an
authenticating broker refuses it.

**`LAST_ERROR` says "Not authorized" and not "Bad user name or password".**
Those are two different reason codes and most brokers send the second only
when they can distinguish the cases. Mosquitto sends `0x87 Not authorized` for
both, so the text does not tell you which of the two pins is wrong.

**It will not retry, and that is deliberate.** A password does not become
correct by itself, and a PLC repeating a rejected one every second is how a
site gets itself banned. Fix the pins and cycle `CONNECT`, or set
`RETRY_REJECTED_CREDENTIAL := TRUE` if the credential genuinely is expected to
become valid on its own. Page 03.

## The broker block reports and does nothing

`MQTT_BROKER` runs on a board now, so this is no longer "it needs the Runtime".
Four things make it report instead:

**No network library on the include path.** WiFi comes with the ESP32 core;
Ethernet needs `MQTT_ENABLE_ETHERNET`, same as the node block.

**`CERT_FILE` or `KEY_FILE` set on a board.** They are paths, and a board has
no file system this block may assume. Clear them and let it mint its own, or
serve plain.

**`SECURITY` other than `MQTT_PLAIN` with no wolfSSL** on the include path.
Serving plain needs nothing installed; serving TLS needs an engine.

**The port is already taken** by another block or another program. `LISTENING`
stays false and the block retries every two seconds rather than giving up.

Page 11.

## The bridge block reports and does nothing

`MQTT_BRIDGE` needs the Runtime, and that one is real: it is two simultaneous
connections, two sessions and two send queues, usually with TLS on one of them.
On a board that is most of the heap before the ladder logic gets any.

On the Runtime it refuses three things at start rather than half-applying them
— no rules, `MQTT_TLS_PINNED` on a block with no key pin, and a mapping that
would loop. Page 12 says what each means.

**Next:** [10 Scan rate](10-scan-rate.md)
