# The client block

`FB_MqttClient` owns the connection. It is the only block that touches the
network; its methods queue work and read results, and the Sparkplug blocks
ride on it.

## Call it first, every scan

```st
mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'plc-intake');
mqtt.Report(anyValue := rLevel, sTopic := 'plant/intake/level', tPeriod := T#1m);
```

The block call keeps the connection, the queues and the timers going. Its
methods may sit anywhere in the network task's program; a method called
before the block acts on the same scan's state and its message goes on the
block's next call, which costs one scan and corrects itself.

**Read the client's own outputs from the instance** - `mqtt.bConnected`,
`mqtt.sLastError` - in the network task, and hand the machine what it needs
through a global (page 10).

The client opens its link on its **second** scan, so every method has been
called once first, wherever it sits.

## Two pins decide the link

```
eTransport   where the bytes go
eSecurity    whether they are encrypted
```

They are separate because they are separate questions. One combined list would
make the combinations that do not exist look legal - a Runtime-only transport
with a board-only option, say - and the wrong one would be a silence nobody
could explain.

| `E_MqttTransport` | runs on | what matters |
| --- | --- | --- |
| `RuntimeTcp` | the Runtime | `sHost`, `nPort` |
| `ArduinoWiFi` | a board | `sHost`, `nPort`, and `stNetworkConfig.sSsid` - or node-uio's `NETWORK` joins the network |
| `ArduinoEthernet` | a board | `sHost`, `nPort`, and `stNetworkConfig`'s MAC and address |
| `Cellular` | a board | `sHost`, `nPort`, and a `GSM_MODEM` from the `modbee-gsm` library |
| `External` | either | `nExternalLink`, and nothing else |

| `E_MqttSecurity` | |
| --- | --- |
| `Plain` | no encryption. Port 1883 |
| `TlsVerify` | encrypted, and a **certificate authority** vouches for the broker. Port 8883. What a cloud broker needs |
| `TlsPinned` | encrypted, and **one key** is trusted. What a plant broker needs, because nobody signed for it |
| `TlsInsecure` | encrypted, and it is **not** checked |

Choosing a transport the target does not have is reported on `bError`,
`eErrorId` and `sLastError` - never built, and never a build failure. *"that
transport needs a board, not the Runtime"* is a sentence you can act on.

`nPort := 0` means the standard one for the security chosen: 1883 or 8883.

### Which `eSecurity` for a board

**A board talking to its own broker** - a site Mosquitto, or a ModBee PLC
broker - uses `E_MqttSecurity.TlsPinned` with `bTrustNew`, and a login
(`stSessionConfig.sUserName` and `sUserPassword`). Nothing to install and
nothing to define: the broker's key is learned on the first connection and
enforced from then on (see *About TlsPinned* below). This is the simple
default for a site.

`TlsVerify` is for a broker somebody signed for - a cloud platform - and needs
that authority's certificate in the board package (see *Defines*).

### TLS on a board

On an ESP32 - the ModBee Node and every other ESP32 board - **every
`eSecurity` works on every `eTransport`**, and works the same way. Wi-Fi,
Ethernet and cellular each open a plain connection, and the TLS runs on the
controller with the mbedTLS the board already carries for its Wi-Fi. So:

- `TlsVerify` checks the chain and the host name against the CA in
  `MQTT_CA_CERT_PEM`, a define the board package supplies (see *Defines*).
  Dates are not judged: a controller has no clock to judge them with until
  something sets it.
- `TlsPinned` and `bTrustNew` work exactly as on the Runtime, below.
- `sBrokerKey` shows the broker's key on every medium.
- Mutual TLS takes the board's own certificate and key from the
  `MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM` defines, also from the
  board package. `stTlsConfig`'s files are the Runtime's: a board has no files.
- Opening the socket and the handshake run on a short task of their own,
  below the PLC's tasks: the block's task never waits for them, and
  `eConnectionState` says `Connecting` meanwhile. A plain connection's socket
  opens the same way.

A TLS session holds about 40 kB of memory while it is up and none while it is
down. On a board with PSRAM, the Node included, it is placed there.

Over cellular this replaces the modem's own TLS, which encrypted and checked
nothing. A board **without** mbedTLS keeps what its medium offers:
`WiFiClientSecure` (no `TlsPinned`), no TLS over Ethernet, and the modem's TLS
(`TlsInsecure` only).

### About TlsInsecure

It encrypts the traffic and does not check who is at the other end, which
means an encrypted conversation with whoever answered. It is named at length
so nobody selects it by accident, and it is a pin on the client rather than a
member of `stTlsConfig` so the decision is visible where the connection is
made.

Use it to get a link working on a bench. Take it off before the plant runs.

### About TlsPinned

A certificate authority answers *"is this certificate vouched for"*. On a plant
broker nobody vouched for anything - a ModBee PLC serving its own certificate,
or a site Mosquitto somebody generated one for on a Tuesday - so there is no
authority to ask. Pinning trusts **one key** instead, and there is nothing to
type:

```st
mqtt(eTransport := E_MqttTransport.RuntimeTcp,
     eSecurity  := E_MqttSecurity.TlsPinned,
     sHost      := '10.0.0.10',
     nPort      := 8883,
     sClientId  := 'plc-intake',
     bTrustNew  := bCommissioning);   (* TRUE once, FALSE for ever after *)
```

`bTrustNew` TRUE, on a link that has never connected, brings it up unverified
exactly once so the broker's key can be learned. The block keeps it in **its
own retained variable** - no pin to wire, nothing to name, nothing to mistype,
and nothing a user can accidentally un-retain: IEC 61131-3 6.5.6.2 says a
`RETAIN` declared in a function block type overrides the instance's qualifier.

Once learned the key is the pin. A broker showing a different one is refused
- on the Runtime `sLastError` names both fingerprints, on a board it reads
*TLS: not the pinned key* and `sBrokerKey` shows the key that was presented -
because the useful question is always which one moved: a broker that was
reinstalled, or an address that is wrong. **Wiring `bTrustNew` TRUE is safe**:
it learns only when nothing is stored.

To accept a broker **replaced on purpose**, switch `bTrustNew` FALSE and TRUE
again: the rising edge forgets the stored key and the next connection learns
the new one.

`FB_MqttBroker` publishes its own key on `sBrokerKey`, and the client shows
what it was shown on `sBrokerKey` too. Read one, compare with the other.

> **Turn on persistent storage.** The pin is a retained variable, and a project
> without storage configured starts every retained variable at its initial
> value - so the pump relearns the key on every restart, which is not pinning.
> The runtime says so in its log at start.

**Do not pin a cloud broker.** AWS IoT, HiveMQ and the rest rotate every ninety
days, and the key usually rotates with the certificate. Use `TlsVerify` there.

## Defines come from the board package

A few settings are compile-time defines: `MQTT_CA_CERT_PEM`,
`MQTT_CLIENT_CERT_PEM` and `MQTT_CLIENT_KEY_PEM`, and `MQTT_ENABLE_ETHERNET`.
An IEC `STRING` stops at 254 characters and the shortest real PEM is about
eight times that, so a certificate is firmware. No limit is a define: the
tables (topics, subscriptions, Sparkplug metrics and devices, a Sparkplug
host's nodes, broker accounts) grow with the program until memory runs out, on
a board and the Runtime alike, and the sizes that are settings are members of
`stSessionConfig`. The OpenPLC editor has no per-project build flags, so a
define comes from the **board package** (the VPP): its compiler flags, as
com.modbee.node sets them for the ModBee Node. To change one, change the
board package.

## Ethernet has to be asked for

Define `MQTT_ENABLE_ETHERNET` in the board package's compiler flags.

This is not fussiness. The Arduino Ethernet library is a *user* library, and
arduino-cli puts one on the include path only when its dependency scanner sees
a plain `#include` for it. A header hidden behind `__has_include` is invisible
to that scanner - so the library can be installed, the guard still reports it
missing, and the block says "install the Arduino Ethernet library" for ever.
WiFi needs no flag because it ships inside the ESP32 core.

**Give a board a fixed address.** `stNetworkConfig.sIp` empty (or `'dhcp'`)
asks DHCP, which the Arduino library may block on for a minute; the client
bounds it to one second an attempt and retries on its own timer, so it works
and it costs a stall each time. A plant network rarely runs DHCP anyway. Every
board on a segment needs its own `sMac`.

```st
VAR
  net : ST_MqttNetworkConfig := (sMac := 'DE:AD:BE:EF:00:01', sIp := '10.0.0.51',
                                 sGateway := '10.0.0.1', sSubnet := '255.255.255.0');
END_VAR

mqtt(eTransport := E_MqttTransport.ArduinoEthernet, sHost := '10.0.0.20',
     sClientId := 'panel-3', stNetworkConfig := net);
```

## Which version you get

```
eProtocol := E_MqttProtocol.V5ThenV311      (* the default *)
```

| | |
| --- | --- |
| `V5` | 5.0 only. Refuse anything older |
| `V311` | 3.1.1 only |
| `V5ThenV311` | try 5.0, drop to 3.1.1 if the broker is older |

**Fallback happens only on evidence that the VERSION is the problem** - a 5.0
reason code `0x84`, or a 3.1.1 return code `0x01`. Never on an authentication
failure, never on a network error. Treating those as a version problem would
hide them, and you would spend an afternoon on the wrong thing.

`mqtt.Statistics(nVersion => ...)` reports what is actually in force: 5 or 4.
Worth putting on a screen, because a 5.0-only feature quietly unavailable makes
much more sense when that says 4.

## The option structures

Nine pins are the whole of an ordinary connection. Everything else is grouped
in four structures on the client's inputs. Each member has a default that
works; leave a structure out and nothing changes. Set them in the declaration,
or member by member from an HMI - they are read every scan.

| | |
| --- | --- |
| `stSessionConfig : ST_MqttSessionConfig` | keep-alive, clean start, session expiry, login, queue and message sizes, reconnect backoff, silence, retrying a refused login |
| `stTlsConfig : ST_MqttTlsConfig` | the certificate authority, and mutual TLS - files on the Runtime |
| `stNetworkConfig : ST_MqttNetworkConfig` | SSID, MAC, IP - the things only a board has. Refused on the Runtime |
| `stWillConfig : ST_MqttWillConfig` | presence: the online message and the Will that answers for it |

Every member is in [07 Block reference](07-block-reference.md#structures).
Three are worth thinking about:

**`bCleanStart`.** TRUE (the default) is right for a sensor that publishes the
current value and has nothing to catch up on. FALSE, with a
`tSessionExpiry`, is right for anything that must not lose a message across a
dropped link - a totaliser, a command channel - and it costs the broker memory
per client.

**`nMaxMsgIn` and `nMaxMsgOut`** answer one symptom: a message plainly being
published that plainly never arrives. The default 4096 bytes suits readings
and setpoints and is too small for a JSON document of any size. Raise
`nMaxMsgIn` on the subscribing end and `nMaxMsgOut` on the publishing one; they
cost RAM per client whether or not a big message ever comes.

**`bAutoReconnect`.** On Wi-Fi or wired the reconnect is milliseconds and you
want it on. On cellular `tMaxSilence` is the one to set - three keep-alives -
because a modem takes our bytes into its own buffer and says "sent" whether or
not anything reaches the broker.

### Presence

```st
VAR
  will : ST_MqttWillConfig := (sTopic := 'plant/intake/status', tDelay := T#30s);
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'plc-intake', stWillConfig := will);
```

`sOnline` (`'online'` when empty) goes out on every connection before anything
else queued, so a subscriber sees this device come up before it sees its first
reading. `sOffline` (`'offline'`) is the Will, published **by the broker** when
the connection dies without a goodbye - a power cut, a pulled cable, a modem
out of coverage. `tDelay` makes the broker wait, and a reconnect inside it
cancels the announcement; it is MQTT 5 only, and at 3.1.1 the client refuses
to connect rather than drop it, because a delay silently lost turns a flapping
link into a stream of false alarms.

**Not with Sparkplug.** A connection carries one Will, and an
`FB_SparkplugNode` or `FB_SparkplugHost` on the client owns it: its birth and
death certificates are the presence. Leave `stWillConfig.sTopic` empty there,
or the client says *"the Will is Sparkplug's on this client"*.

## Logins

On a modbee broker, the PLC can get its own login instead, and nobody types a
password at all: [13 Provisioning](13-provisioning.md). Otherwise it lives in
`stSessionConfig`:

```st
VAR
  session : ST_MqttSessionConfig;
  tls     : ST_MqttTlsConfig := (sCaFile := '/etc/ssl/certs/ca-certificates.crt');
END_VAR

session.sUserName := 'plant-operator';
session.sUserPassword := sPassword;
mqtt(eTransport := E_MqttTransport.RuntimeTcp, eSecurity := E_MqttSecurity.TlsVerify,
     sHost := 'mqtt.example.com', nPort := 8883, sClientId := 'plc-intake',
     stSessionConfig := session, stTlsConfig := tls);
```

**A user name and password travel in the clear unless `eSecurity` is a TLS
one.** MQTT has no challenge and no hashing: the password is bytes in the
first packet the PLC sends. On a plant segment nobody else is on that may be
fine; on anything that leaves the building it is a password published to
whoever is on the path.

**Put the password in a variable, not a literal.** A literal ends up in the
project file, in every backup of it, and on the screen of whoever opens the
program next.

**A refused login stops, and says why.** `bError` goes TRUE, `eErrorId`
carries `E_MqttResult.NotAuthorized`, and `sLastError` reads *"the broker
refused the connection: Not authorized"* - the broker's own reason. The client
does **not** repeat it at its usual backoff - a PLC sending a rejected
password every second is how a site gets itself banned - but it does not give
up either: it tries again every five minutes, so a remote site whose broker is
fixed at the other end comes back by itself.

Where the login really is expected to become valid on its own - a broker whose
access list loads after it starts listening -
`stSessionConfig.bRetryRejectedCredential := TRUE` retries at the backoff.

## Standing down

`bConnect := FALSE` disconnects properly - the broker sees a goodbye rather
than a Will - and the client stays. Every method's record survives the gap.
`bConnect := TRUE` again and it reconnects.

## Changing settings while it runs

Every pin and every member of the four structures is read every scan. A broker
address, a port, the security mode, the login or the client ID changed on an
HMI settings page takes effect at once, without a restart:

1. the client says goodbye on the old settings (a DISCONNECT, so the broker
   does not publish the Will), giving it up to a second to leave;
2. it comes back on the new ones - on a rebuilt connection when `eTransport`,
   `eSecurity`, `sHost`, `nPort`, the TLS files or the board's network
   settings changed, on the same connection when only the CONNECT changed
   (login, `sClientId`, `eProtocol`, keep-alive, session, Will).

It is the **same client** either way, so every method's record carries on.
`bConnected` drops for the moment it takes.

A Wi-Fi login in `stNetworkConfig` that changes makes the client leave the
network and join again with the new one (a radio node-uio's `NETWORK` brought
up is `NETWORK`'s to rejoin).

**A pinned key stays pinned.** With `TlsPinned`, a new `sHost` is a new broker
with a different key, and it is refused until `bTrustNew` is switched off and
on - exactly as for a broker replaced on purpose. An address typed on a panel
is not a way round the pin.

**Next:** [04 Publishing](04-publishing.md)
