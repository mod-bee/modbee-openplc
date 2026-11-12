# Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## It never connects

Read `mqtt.sLastError` first. It carries the operating system's own words,
because no status code can say which of forty things went wrong at a socket.

| what it says | what it is |
| --- | --- |
| *Connection refused* | nothing is listening on that host and port. Wrong port, or the broker is not running |
| *Name or service not known* | DNS. Use an address, or fix the resolver |
| *No route to host* | wrong subnet, or a firewall |
| *Connection timed out* | a firewall dropping rather than refusing |
| *that transport needs a board, not the Runtime* | `eTransport` names an Arduino link on the Runtime |
| *set sHost to the broker* | the pin is empty |

If `sLastError` is empty and `eConnectionState` sits at `E_MqttState.Connecting`, the socket
opened and the broker has not answered. That is a broker that accepted a
connection and then said nothing - check it is actually an MQTT broker on that
port, and not, say, a web server.

Check it from a desk first:

```bash
mosquitto_pub -h 10.0.0.20 -t test -m hello
```

If that fails too, the PLC is not the problem.

## It connects, then drops, then connects again

`nReconnects` from `mqtt.Statistics` climbing is the symptom.

| | |
| --- | --- |
| **Another device has the same `sClientId`** | `eErrorId` shows `E_MqttResult.SessionTakenOver`. Two devices are displacing each other for ever. **Check this first** - it is the commonest cause and it looks healthy from either end |
| **Keep-alive too short for the link** | `E_MqttResult.KeepAliveTimeout`. Raise `stSessionConfig.tKeepAlive`, especially on cellular |
| **The broker is restarting** | its own log will say |
| **A NAT or firewall dropping idle connections** | lower `tKeepAlive` so traffic keeps the mapping alive. The opposite fix to the one above, which is why the log matters |

## It connects but nothing arrives

**Check the filter against the topic.** Wildcards are `+` for one level and
`#` for the rest, and `#` must be last. `plant/level` does not match
`plant/intake/level`.

**Check something is publishing.** From a desk:

```bash
mosquitto_sub -h 10.0.0.20 -t 'plant/#' -v
```

If that shows nothing, the problem is upstream of this PLC.

**Check `bSubscribed` on the `Subscribe` call.** FALSE means the subscription
is not established - usually not connected, sometimes refused by an access
rule, in which case the call returns `E_MqttResult.NotAuthorized`.

**Check `nMalformed`.** Climbing means messages *are* arriving and none of them
parse as `anyValue`'s type. A publisher sending `23,5` to a `REAL`, or JSON to a
number. Use `Message` to see the raw text.

## A value arrives but eQuality is never Good

`tExpect` is shorter than the publisher's own interval. Quality is
judged against the interval *you* asked for, so asking for a value every
second from something that publishes every minute is permanently overdue.

Set it to a little more than the publisher's `tPeriod`.

## eQuality is Unknown and stays Unknown

Nothing has ever arrived on that filter. This is a **commissioning** fault,
not a running one - a typo in the topic, a publisher never deployed, a
wildcard that does not match what you think. Take it to a desk with a drawing
rather than a torch to the plant.

## Publish says Ok but nobody sees it

**`E_MqttResult.NoMatchingSubscribers` as the result** means the broker took it and
nobody was listening. The link is fine.

**Check retain.** A subscriber that connects afterwards hears nothing unless
the message was retained.

**Check the prefix if a bridge is involved.** `sRemotePrefix := 'sites/site7/'`
means the far side sees `sites/site7/plant/intake/level`, not
`plant/intake/level`.

## Publish stays Queued

At QoS 1 or 2, `Publish` returns `Queued` until the broker acknowledges. If
it never does:

- the link dropped mid-flight - it ends with `E_MqttResult.NotConnected`
- the broker's receive maximum is exhausted - `E_MqttResult.QuotaExceededByPeer`

`Request` ends at `tTimeout` with `E_MqttResult.KeepAliveTimeout`. Left at
`T#0s` that is five seconds.

## Publish says NotConnected

The client was not connected at the rising edge of `bExecute`. A request is
refused at once and never queued for later - the host's `Write` too, which
in 0.1.x held the command until the link came back.
Gate the edge on `mqtt.bConnected`, or raise it again when the link is back.

## A method says E_MqttResult.NotSupportedByProtocol

You asked for something 3.1.1 cannot express, on a 3.1.1 connection. Check
`nVersion` from `mqtt.Statistics` - if it says 4, the fallback happened.

`Request` and `Response` are the usual ones: Response Topic and Correlation Data do not
exist before 5.0, and sending the request stripped would mean the responder
has nowhere to reply to. Refused rather than sent into the void.

A Will **delay** (`stWillConfig.tDelay`) is the other. The client refuses to connect at 3.1.1 with a
delay set, rather than dropping it - a delay silently lost turns a flapping
link into a stream of false offline alarms, which is the exact failure the
delay was set to prevent.

## A method says E_MqttResult.WrongTask

The method is called from a different task than its block - a client's, a
Sparkplug node's, a broker's - or a Sparkplug block is in another task than
its client. It does nothing until it is moved: OpenPLC runs each task on a
thread of its own, and a call from another task would be inside the client
while the client's own scan is.

Move it into the network task, beside its block. Where the machine's program
needs the value, hand it over through a global (page 10, "Trading values with
the machine").

## FB_SparkplugNode says "another layer owns the client's Will"

A connection carries one Will, and an `FB_SparkplugHost` or a second
`FB_SparkplugNode` on the same `FB_MqttClient` has it. Give the second one an
`FB_MqttClient` of its own.

`stWillConfig` on that client is the other way round: the node keeps the
Will and the client says *"the Will is Sparkplug's on this client: leave
stWillConfig.sTopic empty"* with `E_MqttResult.Refused` - Sparkplug's birth and
death certificates are the presence.

## Everything works but feels slow

Page 10. The client's task interval is almost always the answer.

## It works on the Runtime and not on a board

**Ethernet needs `MQTT_ENABLE_ETHERNET`**, a define in the board package's
compiler flags. Page 03 explains why it is a define rather than automatic.

**Cellular needs `modbee-gsm`**, which is a separate library, and a `GSM_MODEM` in the
program. Until the modem has a data connection (`GSM_MODEM`'s `READY`) the
client says why on `sLastError` and keeps retrying.

**TLS on a board** is the same on Wi-Fi, Ethernet and cellular on an ESP32 (page
03). It makes the same checks as the Runtime, and says why it refused in a
short fixed line. Where the TLS engine gave a code, it follows the line in
hexadecimal - *TLS: broker refused us -0x7780* - and is mbedTLS's own error
number, for when the line is not enough.

| `sLastError` on a board | What to do |
| --- | --- |
| *a board needs the CA in MQTT_CA_CERT_PEM* | `E_MqttSecurity.TlsVerify` with no CA defined. For the site's own broker use `E_MqttSecurity.TlsPinned` with `bTrustNew`; for a signed one, add the CA to the board package |
| *no pinned key yet - set bTrustNew once to learn it* | `E_MqttSecurity.TlsPinned` on a link that has never connected |
| *cannot connect to the broker* | nothing answered on `sHost` and `nPort`: the broker is down, the port is wrong, or the network is not up. On cellular the modem's own reason is shown instead when it has one |
| *TLS: certificate not trusted* | `MQTT_CA_CERT_PEM` is not the CA that signed this broker - or the broker sends its certificate without the intermediate |
| *TLS: wrong host name* | `sHost` is not a name on the certificate. Use the name it was issued to, not the address |
| *TLS: bad certificate* | the broker's certificate failed some other check (its key usage, its signature) or would not read |
| *TLS: not the pinned key* | the broker was replaced, or `sHost` is wrong. `sBrokerKey` shows the key it presented. To accept a replacement, switch `bTrustNew` off and on |
| *TLS: broker sent no cert* | pinned, and the broker sent no certificate to compare |
| *TLS: broker refused us* | the broker ended the handshake. Most often it wants a client certificate (`MQTT_CLIENT_CERT_PEM`), or refuses the one sent |
| *TLS: no common version/cipher* | the broker allows only TLS 1.3, or only cipher suites a board does not offer. Allow TLS 1.2 on the broker |
| *TLS handshake timed out* | the handshake did not finish within the connect timeout: a slow or lossy link (cellular at the edge of coverage), or a broker that accepts and then says nothing. Raise `stSessionConfig.tConnectTimeout` for a slow link |
| *TLS handshake failed* | any other handshake failure; the code says which |
| *TLS: out of memory* | the board could not find the memory for a TLS session (about 40 kB, in PSRAM where the board has it) |
| *TLS: CA certificate unreadable* / *TLS: client cert/key unusable* | `MQTT_CA_CERT_PEM`, or `MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM`, are not PEM, or a certificate came without its key |
| *the last connect is still finishing* | the attempt before outlived `tConnectTimeout` and its socket is still opening; the next attempt waits for it. Raise `stSessionConfig.tConnectTimeout` for a slow link |
| *no memory for the connect task* | the board could not find the few kB of internal memory the connect runs in; it tries again after the backoff. Something else is holding the internal memory |
| *broker closed the connection* / *TLS: connection dropped* | the connection ended after it was up: the broker closed it, or the network went |
| *TLS over Ethernet needs an ESP32, or SSLClient* / *the modem's TLS checks no certificate* | a board without the ESP32's mbedTLS: only what its medium offers |

On the Runtime `sLastError` carries the TLS library's own words instead, and a
key that is not the pinned one names both fingerprints.

**Check `stNetworkConfig`**: `sMac` and `sIp` set for Ethernet, `sSsid` for
Wi-Fi (or node-uio's `NETWORK` joining it). A board with no MAC cannot open
an Ethernet link - *set MAC on MQTT_ARDUINO* is that message, naming the
structure by its 0.1 name - and every board on a segment needs its own.

## It says not authorised

`eErrorId = E_MqttResult.NotAuthorized` and `sLastError` reading *"the broker refused
the connection: ..."* means the broker answered the CONNECT with a no. The TCP
connection worked; the credential did not.

**Check `sUserName` and `sUserPassword` in `stSessionConfig`.** They are separate members
and either can be set without the other - which is legal MQTT and what a
token-based broker wants, and also what a typo looks like.

**Check the structure reaches the client.** A `stSessionConfig` declared and
filled but not given to the call (`stSessionConfig := session`) sends no
credential at all, and an authenticating broker refuses it.

**`sLastError` says "Not authorized" and not "Bad user name or password".**
Those are two different reason codes and most brokers send the second only
when they can distinguish the cases. Mosquitto sends `0x87 Not authorized` for
both, so the text does not tell you which of the two pins is wrong.

**It retries only every five minutes, and that is deliberate.** A password
does not become correct by itself, and a PLC repeating a rejected one every
second is how a site gets itself banned. Fix the login and cycle `bConnect`,
or set `stSessionConfig.bRetryRejectedCredential := TRUE` if the credential
genuinely is expected to become valid on its own. Page 03.

## The broker block reports and does nothing

`FB_MqttBroker` runs on a board too, so this is not "it needs the Runtime".
Four things make it report instead:

**No network library on the include path.** WiFi comes with the ESP32 core;
Ethernet needs `MQTT_ENABLE_ETHERNET`, same as the client.

**`sCertFile` or `sKeyFile` set on a board.** They are paths, and a board has
no file system this block may assume. Clear them and let it mint its own, or
serve plain.

**`eSecurity` other than `E_MqttSecurity.Plain` with no wolfSSL** on the include path.
Serving plain needs nothing installed; serving TLS needs a TLS library.

**The port is already taken** by another block or another program. `bListening`
stays false and the block retries every two seconds rather than giving up.

Page 11.

## The bridge block reports and does nothing

`FB_MqttBridge` needs the Runtime, and that one is real: it is two simultaneous
connections, two sessions and two send queues, usually with TLS on one of them.
On a board that is most of the heap before the ladder logic gets any.

On the Runtime it refuses three things at start rather than half-applying them
- no rules, `E_MqttSecurity.TlsPinned` on a block with no key pin, and a mapping that
would loop. Page 12 says what each means. A 0.1.x bridge that set `ERROR` with
`STATUS = Queued` and never forwarded is the start fault 0.2.0 fixed.

**Next:** [10 Scan rate](10-scan-rate.md)
