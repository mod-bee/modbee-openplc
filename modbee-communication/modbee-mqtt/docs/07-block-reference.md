# Block reference

Six blocks. `FB_MqttClient`, `FB_MqttBroker`, `FB_MqttBridge` and `FB_MqttClock`
stand alone; `FB_SparkplugNode` and `FB_SparkplugHost` ride on a client, given
on their `fbClient` in-out, which **must be assigned at every call** - leaving it
out is a compile error. Everything per topic, record or account is a **method**
of its block: `mqtt.Publish(...)`, `sp.Record(...)`, `broker.User(...)`. Call the
block itself once every scan, in the network task; call its methods after it.

Every method returns an `E_MqttResult`. A **request** (`Publish`, `Request`,
`Write`) starts on a rising edge of `bExecute`, returns `Queued` while it runs and
then holds its outcome until the next edge. A **standing** method is called every
scan while it is wanted and returns `Ok` while its record is valid. A method's
outputs are read with `=>`: `ok := mqtt.Subscribe(..., eQuality => q);`. An
input left out takes its default.

> Generated from each block's own comment and declarations by
> `internal/make-block-reference.py`; edit the block, not this page.

| Block | What it does | Methods |
| --- | --- | --- |
| [`FB_MqttBridge`](#fb_mqttbridge) | Carries topics between two brokers. |  |
| [`FB_MqttBroker`](#fb_mqttbroker) | Makes this PLC the broker other devices connect to. | [`User`](#fb_mqttbrokeruser) |
| [`FB_MqttClient`](#fb_mqttclient) | An MQTT client: one connection to one broker. | [`Publish`](#fb_mqttclientpublish), [`Report`](#fb_mqttclientreport), [`Subscribe`](#fb_mqttclientsubscribe), [`PublishStruct`](#fb_mqttclientpublishstruct), [`SubscribeStruct`](#fb_mqttclientsubscribestruct), [`Request`](#fb_mqttclientrequest), [`Response`](#fb_mqttclientresponse), [`Message`](#fb_mqttclientmessage), [`Provision`](#fb_mqttclientprovision), [`Statistics`](#fb_mqttclientstatistics) |
| [`FB_MqttClock`](#fb_mqttclock) | SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet, the mobile network's own time over cellular - so Sparkplug timestamps and CURRENT_DT are real time. |  |
| [`FB_SparkplugHost`](#fb_sparkplughost) | A SPARKPLUG B HOST APPLICATION on an FB_MqttClient's connection: the other end of FB_SparkplugNode. | [`Watch`](#fb_sparkplughostwatch), [`Write`](#fb_sparkplughostwrite) |
| [`FB_SparkplugNode`](#fb_sparkplugnode) | A SPARKPLUG B EDGE NODE on an FB_MqttClient's connection. | [`Record`](#fb_sparkplugnoderecord), [`Metric`](#fb_sparkplugnodemetric), [`Device`](#fb_sparkplugnodedevice), [`Command`](#fb_sparkplugnodecommand), [`History`](#fb_sparkplugnodehistory), [`DayTotals`](#fb_sparkplugnodedaytotals) |

The option structures and enumerations are at the end: [Structures](#structures), [Enumerations](#enumerations).

---

## FB_MqttBridge

```
Carries topics between two brokers. Standalone - it owns both connections and
takes no FB_MqttClient. The OpenPLC Runtime only. Call it every scan, once per
rule, in the network task.

bEnable             TRUE connects both ends and starts forwarding. FALSE
                    closes both and forgets the rules, which are collected
                    again on the next start.
sLocalHost          the near broker. Usually the site one, often this PLC
                    itself ('127.0.0.1').
nLocalPort          0 for the standard port.
eLocalSecurity      plain or TLS on the near side.
sRemoteHost         the far broker. Usually head office or a cloud service.
nRemotePort         0 for the standard port.
eRemoteSecurity     plain or TLS on the far side. Separate pins because the
                    two sides are genuinely different: a site broker on the
                    same switch needs no TLS, and the link out of the building
                    always does. E_MqttSecurity.TlsPinned is refused on either
                    side: this block has nowhere to keep a key.
sRemoteUserName     the far side's login, which it usually wants.
sRemoteUserPassword its password.
sBridgeName         what to call this bridge; empty for 'bridge'. It becomes
                    part of both client identifiers, WHICH MUST DIFFER - a
                    bridge using one identifier on both ends would take over
                    its own session the moment both brokers turned out to be
                    the same box.
sTopic              one rule: what to carry, without either prefix. Wildcards
                    allowed.
eDirection          E_MqttDirection.Out local to remote (readings going up),
                    E_MqttDirection.In remote to local (commands coming down),
                    E_MqttDirection.Both. Prefer an Out and an In rule to one
                    Both unless you mean it: a tree carried both ways is the
                    shape that loops.
eQos                the most this rule carries. Never higher than it arrived.
sLocalPrefix        what the near side sees in front of the topic.
sRemotePrefix       and the far side. 'site7/' on the remote turns
                    'plant/a/temp' into 'site7/plant/a/temp' upstream, so ten
                    sites can share one broker without colliding.
bForwardRetained    whether a retained message stays retained across. FALSE
                    by default and usually right: a retained value that
                    crosses a bridge outlives the link that carried it, and a
                    stale reading on a head-office dashboard is worse than
                    none.

eBridgeState        Idle, Connecting, Up or Degraded.
bLocalUp            the near end is connected.
bRemoteUp           the far end is connected.
nForwardedOut       running total carried local to remote.
nForwardedIn        and the other way.
nRefusedOut         the far side would not take it.
nRefusedIn          the near side would not take it.
bError              something failed.
eErrorId            why. E_MqttResult.Ok when fine; InvalidArgument for a
                    configuration refused at start (below).
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | connects both ends and forwards |
| `sLocalHost` | `STRING(64)` |  | the near broker |
| `nLocalPort` | `UINT` |  | 0 for the standard port |
| `eLocalSecurity` | `E_MqttSecurity` |  | plain or TLS on the near side |
| `sRemoteHost` | `STRING(64)` |  | the far broker |
| `nRemotePort` | `UINT` |  | 0 for the standard port |
| `eRemoteSecurity` | `E_MqttSecurity` |  | plain or TLS on the far side |
| `sRemoteUserName` | `STRING(64)` |  | the far side's login; empty for none |
| `sRemoteUserPassword` | `STRING(64)` |  |  |
| `sBridgeName` | `STRING(48)` |  | part of both client identifiers; empty for 'bridge' |
| `sTopic` | `STRING(128)` |  | one rule: what to carry, wildcards allowed |
| `eDirection` | `E_MqttDirection` |  | Out, In or Both |
| `eQos` | `E_MqttQos` |  | the most this rule carries |
| `sLocalPrefix` | `STRING(64)` |  | in front of the topic on the near side |
| `sRemotePrefix` | `STRING(64)` |  | in front of the topic on the far side |
| `bForwardRetained` | `BOOL` |  | a retained message stays retained across |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `eBridgeState` | `E_MqttBridgeState` |  |  |
| `bLocalUp` | `BOOL` |  | the near end is connected |
| `bRemoteUp` | `BOOL` |  | the far end is connected |
| `nForwardedOut` | `DINT` |  | carried local to remote |
| `nForwardedIn` | `DINT` |  | carried remote to local |
| `nRefusedOut` | `DINT` |  | the far side would not take it |
| `nRefusedIn` | `DINT` |  | the near side would not take it |
| `bError` | `BOOL` |  |  |
| `eErrorId` | `E_MqttResult` |  |  |

ONE INSTANCE, MANY RULES. Call the same instance several times in a scan,
each with a different sTopic, and each call adds a rule - the connection pins
are read from the first call and the rest add to the mapping. A site carrying
three topic trees is one block called three times, not three bridges. The
rules are collected on the first scan and the connections built on the
second, so a rule called later in the program still arrives before either
end connects. A rule repeated in a scan is one rule. Once started the rules
are fixed: a changed sTopic takes effect when bEnable goes FALSE and TRUE.

E_MqttBridgeState.Degraded IS THE STATE WORTH ALARMING ON. One end is
connected and the other is not, so half the traffic is flowing and the other
half piling up - which from the site looks like everything working and from
head office looks like the site has died.

REFUSED AT START, rather than half applied, each with bError and
E_MqttResult.InvalidArgument: no rules (two connections carrying nothing and
looking healthy); TlsPinned on either side; and a mapping that would loop.
Two rules carrying this bridge's own output back into it are a message storm
that takes a broker down; at 5.0 the No Local subscription option prevents it
outright, and where the version cannot express that, the configuration is
rejected.

THE RUNTIME ONLY. A bridge is two simultaneous connections, two sessions and
two send queues, usually with TLS on one. On a board that is most of the heap,
so there it sets bError with InvalidArgument and does nothing. The shape that works on a board is
FB_MqttBroker on the panel serving the line, and the bridge upstream on a
Runtime.

A BRIDGE IS NOT A CLIENT. It owns two clients of its own, named from
sBridgeName, and carries what its rules say. A PLC that bridges and also
publishes runs an FB_MqttClient of its own beside it.

---

## FB_MqttBroker

```
Makes this PLC the broker other devices connect to. Standalone - it owns its
listener and takes no FB_MqttClient. Call it once every scan, in the network
task; each device's account is a call of its User method.

bEnable            TRUE listens. A falling edge stops and releases the port.
sListenOn          which interface to listen on. Empty for all of them.
                   Ignored on a board, which listens where its core is up.
nPort              0 for 1883.
nMaxClients        connections served at once. 0 for 32 (4 on a board).
nMaxRetained       retained messages held. 0 for 256 (32 on a board).
eSecurity          E_MqttSecurity.Plain serves clear text. Anything else
                   serves TLS, and then:
                     no sCertFile      the broker makes its OWN certificate on
                                       first start, keeps it beside the
                                       program and presents the same one every
                                       start after. Zero configuration;
                                       clients pin sBrokerKey.
                     sCertFile + sKeyFile
                                       a real certificate - from the site's
                                       own CA, or a public one. Clients verify
                                       it the ordinary way, host name and all,
                                       with nothing pinned.
sCertFile          a certificate to present, as a path on the Runtime. Empty
                   to make one. Refused on a board, which has no file system
                   this block may assume.
sKeyFile           its private key. One without the other is refused rather
                   than half applied.
nMaxSubscriptions  subscriptions each client session may hold. 0 for 32
                   (8 on a board).
nMaxQueued         messages held for each client while it is away or slow.
                   0 for 64 (16 on a board).
nMaxMsgSize        the largest message, in bytes, a client may send or be
                   sent; also each connection's buffer size. 0 for 8192
                   (1024 on a board).
tMaxSessionExpiry  how long a session is kept after its client goes: a 3.1.1
                   client's persistent session, and the most a 5.0 client may
                   ask for. T#0s for 1 h. Read when the broker starts.

bListening         the port is open.
nClients           connections attached now. THIS PLC COUNTS AS ONE of them
                   if it also runs an FB_MqttClient against itself, which is
                   how a broker PLC publishes anything: a broker holds no
                   values of its own.
nSessions          sessions held, including those of clients currently away
                   whose state has not expired.
nAccepted          connections accepted at the socket.
nAdmitted          of those, how many earned a successful CONNACK. A socket
                   that opens and never becomes a client is a scanner, or bad
                   credentials.
nRefused           and how many were turned away - a client with another
                   login than the one that made an existing session among
                   them.
nFromClients       messages accepted from clients.
nToClients         messages sent to clients.
nDropped           deliveries a full client queue could not take. Not silent:
                   at QoS above 0 the publisher is told (0x97) rather than
                   left believing it arrived.
nTakeovers         times a client identifier was claimed by a second
                   connection with the same login, and the first was
                   disconnected. Climbing usually means two devices share an
                   identifier.
bError             something failed.
eErrorId           why. E_MqttResult.Ok when fine.
sBrokerKey         the SHA-256 of this broker's public key, 64 hexadecimal
                   characters: what a client pins against. Empty while
                   serving plain.

METHODS

  broker.User(sUserName, sUserPassword, bAllow, bActive =>, nLoginCnt =>,
              nRefusedCnt =>)

     ONE ACCOUNT ON THIS PLC'S BROKER. Standing: call it every scan, once per
     device that connects, in the broker's task. Declaring ANY account makes
     accounts REQUIRED for every connection - including one whose bAllow is
     FALSE, so switching off the last account locks the broker rather than
     quietly opening it. With no User call at all the broker admits anybody;
     on a network that is not isolated, declare accounts.

     An account whose call stops (renamed while running, or no longer
     called) is switched off and its password wiped at the broker's next
     scan, so nothing can still log in under a name nobody can see in the
     program; it still counts as declared, so the broker stays locked. Call
     it again and it is back, its counters kept.

     sUserName      the name the device logs in with. Compared exactly, case
                    included. The call's key.
     sUserPassword  its password. Up to 64 characters; compared in full,
                    never stopping at the first difference.
     bAllow         FALSE refuses this device without forgetting it.

     bActive        the account is declared and allowed.
     nLoginCnt      times this device has connected successfully.
     nRefusedCnt    times a connection under this name was turned away - a
                    wrong password, or the account switched off. Climbing on
                    one device and not the others is that device's settings.

     Returns E_MqttResult.Ok, InvalidArgument for an empty sUserName,
     QuotaExceeded when memory for one more account ran out (the table grows
     with the calls, on a board and the Runtime alike), or WrongTask.

     ONE CALL PER ACCOUNT rather than a list: an account is something an
     engineer adds, removes and switches off one device at a time, and a call
     per device makes each one visible, commentable and interlockable. AND
     EACH DEVICE ITS OWN: a shared password cannot be revoked from one
     controller without changing all of them, and a log that says
     "plant-user refused" does not say which panel to go to. Topic
     permissions are not here: this decides who may CONNECT.
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | TRUE listens; a falling edge releases the port |
| `sListenOn` | `STRING(48)` |  | the interface to listen on; empty for all |
| `nPort` | `UINT` |  | 0 for 1883 |
| `nMaxClients` | `INT` |  | connections served at once; 0 for the default |
| `nMaxRetained` | `INT` |  | retained messages held; 0 for the default |
| `eSecurity` | `E_MqttSecurity` |  | E_MqttSecurity.Plain, or TLS |
| `sCertFile` | `STRING(128)` |  | a certificate to present (Runtime); empty to make one |
| `sKeyFile` | `STRING(128)` |  | its private key |
| `nMaxSubscriptions` | `INT` |  | subscriptions per client session; 0 for the default |
| `nMaxQueued` | `INT` |  | messages held per client while away; 0 for the default |
| `nMaxMsgSize` | `DINT` |  | the largest message in bytes; 0 for the default |
| `tMaxSessionExpiry` | `TIME` |  | how long a session outlives its client; T#0s for 1 h |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bListening` | `BOOL` |  | the port is open |
| `nClients` | `INT` |  | connections attached now |
| `nSessions` | `INT` |  | sessions held, away clients included |
| `nAccepted` | `DINT` |  | connections accepted at the socket |
| `nAdmitted` | `DINT` |  | of those, given a successful CONNACK |
| `nRefused` | `DINT` |  | of those, turned away |
| `nFromClients` | `LINT` |  | messages accepted from clients |
| `nToClients` | `LINT` |  | messages sent to clients |
| `nDropped` | `LINT` |  | deliveries a full client queue could not take |
| `nTakeovers` | `DINT` |  | client identifiers claimed by a second connection |
| `bError` | `BOOL` |  |  |
| `eErrorId` | `E_MqttResult` |  |  |
| `sBrokerKey` | `STRING(64)` |  | The SHA-256 of this broker's own public key, 64 hexadecimal characters. This is the number a client pins against: read it off the panel once at commissioning and it does not change again, because it is a fingerprint of the KEY rather than of the certificate - so it survives the certificate being reissued. Empty while the broker is serving plain TCP. |

### FB_MqttBroker.User

```
result := broker.User(sUserName := ..., sUserPassword := ..., bAllow := ...,
                      bActive => ..., nLoginCnt => ..., nRefusedCnt => ...);
```

Returns `E_MqttResult`.
One account on this broker, called every scan, once per device. Any account makes accounts required for every connection. Ok; InvalidArgument for an empty sUserName; QuotaExceeded out of memory.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sUserName` | `STRING(64)` |  | the name the device logs in with; case-sensitive |
| `sUserPassword` | `STRING(64)` |  | its password |
| `bAllow` | `BOOL` | `TRUE` | FALSE refuses this device without forgetting it |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bActive` | `BOOL` |  | the account is declared and allowed |
| `nLoginCnt` | `DINT` |  | times this device has connected |
| `nRefusedCnt` | `DINT` |  | connections under this name turned away |

WHY PUT A BROKER IN A PLC. A site with twenty sensors and an intermittent
uplink does not want twenty devices each retrying a connection to head office.
Point them at the PLC, let it hold the retained values and the sessions, and
carry one connection upstream with FB_MqttBridge. The site keeps working when
the link does not, and comes back in step when it returns.

A BROKER DOES NOT PUBLISH. It routes what clients send. A PLC that is the
broker and also publishes runs an FB_MqttClient against itself
(sHost := '127.0.0.1') beside this block, in the same task.

ON A BOARD TOO. The routing, the retained store, the session registry and
takeover compile anywhere, and an Arduino listener accepts connections
without a BSD socket, so an ESP32 running this block is a real broker. What
differs on a board:

  sListenOn        ignored.
  sCertFile,
  sKeyFile         refused rather than ignored: they are paths.
  sBrokerKey       the fingerprint of a certificate made on THIS run. There is
                   nowhere on a board to keep a key, so it moves on every
                   restart - either re-pin after a reflash, or serve plain on
                   an isolated line and put the TLS on the FB_MqttBridge that
                   leaves the site, which is the connection that needs it.
  the defaults     sized for a panel: four connections, eight sessions, 1 kB
                   buffers, 32 retained, 8 subscriptions and 16 queued
                   messages per session. Every one is a pin: raise the ones a
                   site needs, within the board's memory - each connection
                   holds two nMaxMsgSize buffers.

Serving TLS on a board also needs wolfSSL on the include path; serving plain
needs nothing at all. WiFi comes with the ESP32 core, and Ethernet is opt-in:
MQTT_ENABLE_ETHERNET, a define in the board package's compiler flags.

SELF-SIGNED IS THE DEFAULT, NOT A CEILING. The obstacle was never the TLS
library; it was that a certificate does not fit on a pin, and a path does.

nTakeovers IS THE PIN TO WATCH ON A NEW SITE. MQTT says a second connection
using an existing client identifier displaces the first, so two devices
flashed with the same identifier knock each other off for ever, each looking
healthy on its own. This counter is the only place that shows from the
middle. A session belongs to the login that made it: a client with another
login and an existing identifier is refused (CONNACK 0x85; 0x02 at 3.1.1) and
counts on nRefused, not here. Without logins every client is the same
nobody, so takeovers work as before.

SESSIONS EXPIRE. A persistent session of a 3.1.1 client is kept for
tMaxSessionExpiry after it goes (an hour unless set), then dropped. A 5.0
client says how long itself, up to the same limit. Raise it for devices that
sleep longer; every session held keeps its queue. Sessions and retained
messages are in RAM: a power cut loses them, which is legal MQTT.

REFUSED AS THE STANDARD SAYS. A Will topic with wildcards (0x90), a Will
declared UTF-8 that is not (0x99), a PUBLISH from a client carrying a
Subscription Identifier, two Subscription Identifiers in one SUBSCRIBE, No
Local on a $share subscription, and a 3.1.1 CONNECT with a password but no
user name are refused or disconnected. A 3.1.1 QoS 2 message when the
client's inbound table is full closes the connection rather than being
acknowledged and lost.

ITS COST SCALES WITH nClients: it services each connection once per call.
Still bounded, still non-blocking, not free. Put it in the network task.

---

## FB_MqttClient

```
An MQTT client: one connection to one broker. Call it once every scan, in
the network task. Everything this PLC publishes and subscribes on that broker
is a method of this block, and the Sparkplug blocks ride on its connection.

eTransport  where the bytes go. The target must have it; one it does not have
           is reported on bError and sLastError, never built.
             E_MqttTransport.RuntimeTcp       the OpenPLC Runtime's network
             E_MqttTransport.ArduinoWiFi      a board's Wi-Fi. stNetworkConfig
                                              joins it, or node-uio's NETWORK
             E_MqttTransport.ArduinoEthernet  a board's Ethernet, from
                                              stNetworkConfig's MAC and address
             E_MqttTransport.Cellular         the modem a modbee-gsm GSM_MODEM
                                              runs, on a board. Opening the
                                              socket takes about 1.5 s, never
                                              longer than tConnectTimeout
             E_MqttTransport.External         nExternalLink, and nothing else
eSecurity   plain or TLS, and which kind of TLS. Separate from eTransport,
           because they are separate questions: one list of every combination
           would make the ones that do not exist look legal.
             E_MqttSecurity.Plain        no encryption. Port 1883
             E_MqttSecurity.TlsVerify    a broker somebody signed for: chain,
                                         dates and host name are checked (a
                                         board checks chain and host name - it
                                         has no clock to judge a date). For
                                         anything public - AWS IoT, HiveMQ, a
                                         platform - whose key rotates every
                                         ninety days and would break a pin
             E_MqttSecurity.TlsPinned    a broker nobody signed for: a ModBee
                                         PLC broker, a site's own Mosquitto.
                                         Trusts ONE key and skips chain and
                                         expiry on purpose. See bTrustNew
             E_MqttSecurity.TlsInsecure  encrypted and NOT checked. For a
                                         bench, never for a plant
sHost       the broker: a name or an address. Empty is refused.
nPort       0 for the standard one: 1883 plain, 8883 TLS.
sClientId   what the broker calls this device. EVERY DEVICE ON A BROKER NEEDS
           ITS OWN: two sharing one knock each other off for ever. Empty asks
           the broker to assign one, shown on sAssignedId. Provision uses it
           as the PLC's name.
eProtocol   which MQTT version to speak. E_MqttProtocol.V5ThenV311 (the
           default) tries 5.0 and drops to 3.1.1 only when the broker says the
           VERSION is the problem - never on a login or network failure.
           E_MqttProtocol.V5 and E_MqttProtocol.V311 speak one only.
nExternalLink  a transport another block made, for
           eTransport := E_MqttTransport.External. Not something to wire by
           hand.
bConnect    TRUE connects and stays connected. FALSE says goodbye properly -
           the broker publishes no Will - and keeps the client, so every
           method's record survives the gap.
bTrustNew   for E_MqttSecurity.TlsPinned only. TRUE lets the FIRST key a broker
           shows be learned and kept, in this block's own retained memory
           (trust on first use, as SSH does). Once learned it is ENFORCED,
           whether bTrustNew stays TRUE or not and across restarts: a broker
           showing another key is refused and sBrokerKey shows the key it
           presented. Wiring it TRUE is therefore safe. To accept a broker
           REPLACED ON PURPOSE, switch it FALSE and TRUE again: the rising
           edge forgets the stored key and the next connection learns the new
           one. FALSE with nothing stored refuses to connect. Turn on the
           project's persistent storage, or the key is learned again on every
           start.

stSessionConfig  ST_MqttSessionConfig, everything about the session. Every
           member left at its default is the right answer for most sites.
             tKeepAlive     how often client and broker show they are there.
                            T#0s = 60 s. Whole seconds, rounded up
             bCleanStart    TRUE (default) starts a fresh session each time:
                            right for a sensor with nothing to catch up on.
                            FALSE keeps the session for what must not be
                            lost across a drop, at the broker's memory
             tSessionExpiry MQTT 5: how long the broker keeps the session
                            after a disconnect. T#0s = not at all
             sUserName      the login; empty for none. Leave empty when
                            Provision gives the login
             sUserPassword  its password. In the clear unless eSecurity is
                            TLS. Put it in a variable, not a literal
             nMaxPending    publishes and subscribes that may wait for the
                            broker at once (QoS 1 and 2). 0 = 32. Past it a
                            method gets QueueFull, never a silent drop
             nMaxMsgIn      the largest message received, bytes. 0 = 4096.
                            Raise it on the subscribing end for JSON
             nMaxMsgOut     the largest message sent, bytes. 0 = 4096. A
                            larger publish is refused with PacketTooLarge
             tReconnect     the first wait before reconnecting. T#0s = 1 s
             tReconnectMax  the longest wait between attempts. T#0s = 1 min
             tConnectTimeout how long a broker that accepts a socket may say
                            nothing. T#0s = 20 s. Raise it for a slow
                            cellular or TLS link
             tMaxSilence    reconnect when nothing at all arrives for this
                            long, whatever our own sending looks like.
                            T#0s = never. On cellular, three keep-alives: a
                            modem takes our bytes and says "sent" whether or
                            not anything reaches the broker
             bAutoReconnect TRUE (default) reconnects by itself after a loss.
                            On cellular the reconnect can stall a scan:
                            consider FALSE and reconnect from your logic
             bRetryRejectedCredential  TRUE retries a refused login at the
                            usual backoff. FALSE (default) tries a refused
                            login again only every five minutes
stTlsConfig  ST_MqttTlsConfig, what to trust. Files on the Runtime; a board
           takes them from the board package's defines (below).
             sCaFile        the certificate authority. Empty = the system's
             sCertFile      this client's certificate, for mutual TLS
             sKeyFile       its private key. One without the other is refused
stNetworkConfig  ST_MqttNetworkConfig, what only a board has. Refused on the
           Runtime, which uses its machine's network.
             sSsid          ArduinoWiFi: the network to join. Empty when
                            node-uio's NETWORK joins it
             sWiFiPassword  its password; empty for an open network
             sMac           ArduinoEthernet: this board's MAC,
                            'DE:AD:BE:EF:FE:ED'. Each board needs its own
             sIp            a fixed address; empty or 'dhcp' = DHCP. A fixed
                            address is what you want: DHCP is bounded to 1 s
                            an attempt and retried, a stall each time, and a
                            plant network rarely runs it
             sGateway       the router, with a fixed address
             sSubnet        the mask, with a fixed address
stWillConfig  ST_MqttWillConfig, presence: 'online' on every connection and
           the Will the broker sends when this device is gone without a
           goodbye. Not with a Sparkplug node or host on this client: their
           birth and death certificates are the presence.
             sTopic         where; empty = no presence
             sOnline        sent on every connection. Empty = 'online'
             sOffline       the Will. Empty = 'offline'
             bRetain        TRUE (default): late subscribers are told too
             eQos           for both
             tDelay         MQTT 5: how long the broker waits before sending
                            the Will. A reconnect inside it sends nothing, so
                            a marginal radio does not cry wolf. Refused at
                            3.1.1, which cannot carry it

bLinkUp     the client exists and its link is open.
bConnected  the broker has acknowledged us. THE ONE TO INTERLOCK ON. FALSE
           while Provision is connected only with its key.
tHeardAgo   how long since anything arrived from the broker on this
           connection (T#0s while not connected). A healthy broker is heard at
           least once a keep-alive - it answers our ping - so "bConnected and
           tHeardAgo under three keep-alives" proves the broker is really
           there, which a modem that only buffers our bytes cannot fake.
bSessionPresent  the broker had our session waiting. FALSE after a clean
           start and on a first connection.
sAssignedId the client identifier in force, ours or the broker's.
eConnectionState  where the connection is up to: Idle, Connecting,
           AwaitingConnAck, Authenticating, Connected, Disconnecting,
           Reconnecting.
bError      something failed.
eErrorId    why. E_MqttResult.Ok when fine; E_MqttResult.NotAuthorized when
           the broker refused the login.
sLastError  in words: the operating system's ("Connection refused", "Name or
           service not known"), the broker's ("the broker refused the
           connection: Not authorized"), or TLS's, which on a board is a short
           fixed line with the TLS library's code ("TLS: wrong host name",
           "TLS: broker refused us -0x7780"; docs/09 lists them). "out of
           memory for topics or subscriptions" when a method's topic could not
           be held; "out of memory for MAX_PENDING - the queue holds N" when
           stSessionConfig.nMaxPending could not be taken.
sBrokerKey  the SHA-256 of the key the broker presented, 64 hexadecimal
           characters, pinned or not. Write it down at commissioning. Empty on
           a plain connection.

METHODS

Each call is found again by what it is about: anyValue's (anyData's)
declared name and type, and the method. A literal or an expression has no
name, and is found by its topic. So one variable is one record per method:
to send one variable to two topics, give each call its own variable. A
client holds up to 256 records; past that a method returns
E_MqttResult.QueueFull. Every method runs in this block's task and returns
E_MqttResult.WrongTask in any other.

A REQUEST (Publish, Request) starts on a rising edge of bExecute and takes
its inputs at that edge; changing them while it runs has no effect. It
returns E_MqttResult.Queued while it runs, then its outcome, held until the
next edge. Not connected at the edge: E_MqttResult.NotConnected at once,
never queued for later.

A STANDING METHOD (Report, Subscribe, PublishStruct, SubscribeStruct,
Response, Message, Provision) is called every scan while it is wanted, and
its inputs may change while it runs. E_MqttResult.Ok means the record is
valid; E_MqttResult.NotConnected while there is no link, the record kept.
Subscriptions are made again by themselves after a reconnect where the broker
kept no session.

  mqtt.Publish(anyValue, sTopic, eQos, bRetain, bExecute)
     ONE MESSAGE, on a rising edge of bExecute. anyValue goes as the text of
     its declared type: 23.5, 42, true, a STRING's text. A STRUCT, an array
     or a TIME is refused. sTopic has no wildcards. bRetain keeps it on the
     broker for later subscribers: retain a state, never an event.
     Queued until the broker has it (QoS 1 and 2) or it has left (QoS 0),
     then Ok - a delivery receipt at QoS 1 and 2, a despatch note at QoS 0.
     NotConnected (at the edge, or the link lost while it ran),
     InvalidArgument (a type the wire cannot carry), InvalidTopic,
     QueueFull, or the broker's refusal.

  mqtt.Report(anyValue, sTopic, eTrigger, fDeadband, tPeriod, eQos, bRetain,
              bEnable, bExecute, nSent =>, tAge =>)
     A VARIABLE, published when it is worth publishing. eTrigger:
       E_MqttTrigger.OnChange    when it moves by fDeadband or more from the
                                 value last sent, and every tPeriod anyway.
                                 A STRING (no number) when its text changes
       E_MqttTrigger.OnInterval  every tPeriod, which must be set
       E_MqttTrigger.OnRequest   on bExecute's rising edge; nothing else, no
                                 first value, no heartbeat
     ALWAYS SET tPeriod WITH OnChange: a value that never moves otherwise
     publishes nothing, and the far end cannot tell that from a dead device.
     A BOOL counts as 1.0 or 0.0, so leave fDeadband 0 for anything that is
     not an analogue. bEnable FALSE stops it, keeping the record; an edge of
     bExecute raised meanwhile does not fire on enabling. A new sTopic sends
     its first value at once. nSent counts messages; tAge is the time since
     the last one (T#0s before the first, which nSent = 0 tells apart).
     Ok, NotConnected, InvalidArgument (a type the wire cannot carry,
     OnInterval with no tPeriod, E_MqttTrigger.ChangedEvery, which is
     Sparkplug's), QueueFull, or the broker's refusal.

  mqtt.Subscribe(anyValue, sTopic, eQos, tExpect, bEnable, bSubscribed =>,
                 eQuality =>, bSeen =>, tAge =>, nReceived =>, nMalformed =>,
                 bNewValue =>)
     A VARIABLE KEPT UP TO DATE from sTopic (wildcards allowed: the variable
     then holds whichever arrived last). A payload is read as anyValue's
     declared type and written straight into it; one that does not parse is
     counted on nMalformed and leaves anyValue alone. eQos is the most the
     broker may use. eQuality is judged against tExpect, the interval YOU
     expect a value in:
       E_MqttQuality.Unknown    nothing has EVER arrived: a desk fault - a
                                topic typo, a publisher never deployed
       E_MqttQuality.Bad        the link is down, or more than twice overdue:
                                a plant fault
       E_MqttQuality.Uncertain  overdue, but not by twice
       E_MqttQuality.Good       arrived inside tExpect. tExpect T#0s = no
                                promise: Good once anything has arrived
     bSeen is the same distinction as a BOOL, for a ladder rung, which cannot
     compare an enumeration. tAge is the time since the last accepted value.
     bNewValue: this call wrote anyValue. A new sTopic is a new subscription,
     Unknown until it speaks. bEnable FALSE unsubscribes, keeping the record.
     Ok, NotConnected, QueueFull, or the broker's refusal.

  mqtt.PublishStruct(anyData, sBase, eTrigger, tPeriod, eQos, bRetain,
                     bEnable, bExecute, nPoints =>, nSkipped =>, nSent =>,
                     nChanged =>)
     A WHOLE STRUCT, each member on sBase/<member>: the member name IS the
     topic, so the STRUCT is the topic scheme. OnChange sends a member when
     it changes and every tPeriod anyway; OnInterval the whole set every
     tPeriod; OnRequest the whole set on bExecute's rising edge, changed or
     not. No deadband, on purpose: one number over mixed types would freeze
     a BOOL. A member the wire cannot carry - an array, a nested STRUCT, a
     TIME - is refused, counted on nSkipped, and the call returns
     InvalidArgument; the other members still go. nPoints: members
     published. nSent: messages for this record. nChanged: sent by this
     call. Ok, NotConnected, InvalidArgument (also: not a STRUCT, OnInterval
     with no tPeriod, ChangedEvery), InvalidTopic, QueueFull.

  mqtt.SubscribeStruct(anyData, sBase, eQos, tExpect, bEnable, nPoints =>,
                       nSkipped =>, bSubscribed =>, eQuality =>, bSeen =>,
                       tOldest =>, nReceived =>, nMalformed =>,
                       nNewValues =>)
     A WHOLE STRUCT KEPT UP TO DATE, each member from sBase/<member>.
     eQuality is the WORST member's: a recipe with one stale setpoint is not
     a recipe to run. bSeen is FALSE, and tOldest T#0s, while any member has
     never had a value; tOldest is the oldest member's age. nNewValues:
     members written by this call. Members it cannot carry as for
     PublishStruct. Link down: eQuality Bad. Ok, NotConnected,
     InvalidArgument, InvalidTopic, QueueFull.

  mqtt.Request(anyValue, sTopic, sReplyTopic, eQos, tTimeout, bExecute,
               sReply =>, nReplyLen =>)
     A QUESTION AND ITS ANSWER, MQTT 5 only. The rising edge of bExecute
     clears sReply and publishes anyValue on sTopic with sReplyTopic as its
     Response Topic and a counted Correlation Data; sReplyTopic is
     subscribed beforehand, so the answer cannot arrive before anyone
     listens. Give each requester its own sReplyTopic. Queued until the
     answer (Ok, its text in sReply, up to 254 characters, nReplyLen
     characters) or tTimeout (T#0s = 5 s: KeepAliveTimeout). NotConnected,
     InvalidTopic (no sReplyTopic), NotSupportedByProtocol (a 3.1.1
     connection: refused rather than sent with nowhere to answer),
     InvalidArgument, QueueFull.

  mqtt.Response(anyRequest, sTopic, anyReply, eQos, bEnable, bExecute,
                bNewRequest =>, bAwaitingReply =>, sResponseTopic =>,
                nReceived =>, nMalformed =>)
     ANSWERS ANOTHER DEVICE'S MQTT 5 REQUEST. Requests arriving on sTopic
     (wildcards allowed) are written into anyRequest as its declared type;
     one that does not parse counts on nMalformed. bNewRequest: this call
     took one. bAwaitingReply: the last request gave a Response Topic
     (sResponseTopic) and is not answered yet. A rising edge of bExecute
     sends anyReply there, quoting the request's Correlation Data, once per
     request. Ok, NotConnected, and at the edge: InvalidTopic (nothing to
     answer), NotSupportedByProtocol (3.1.1), InvalidArgument (anyReply's
     type).

  mqtt.Message(anyPayload, sTopic, eQos, bEnable, nLen =>, bTruncated =>,
               nReceived =>, bNewMessage =>)
     THE TEXT OF WHATEVER ARRIVES on sTopic (wildcards allowed), written into
     the STRING variable anyPayload, one message per call. For JSON you
     parse yourself, a state name, a command word. bNewMessage reports an
     ARRIVAL, not a change: "open" sent twice is two messages. An EMPTY
     message is not nothing - with retain it is how MQTT withdraws a value:
     bNewMessage with nLen 0. bTruncated: longer than anyPayload or the
     client's buffer - check it before trusting a JSON document. Ok,
     NotConnected, InvalidArgument (anyPayload is not a STRING variable),
     QueueFull.

  mqtt.Provision(sKey, bForget, bProvisioned =>, bPending =>, bRefused =>,
                 sUserName =>, sGroup =>, sPrefix =>, sReason =>)
     ON A MODBEE BROKER, THE PLC GETS ITS OWN LOGIN by itself. sClientId is
     its name and must be set; sKey comes from `modbee key create` on the
     broker. The first start connects with the key, asks for a login and
     keeps it in this block's retained memory, then reconnects as itself;
     bConnected stays FALSE until then. Leave stSessionConfig's login empty.
     Call it every scan, before this block's own call. bProvisioned: this
     PLC has its own login and is connected with it. bPending: waiting for
     approval on the broker (asked again every 30 s). bRefused: the broker
     said no, sReason why (asked again every 5 minutes). sUserName: the
     login in use. sGroup and sPrefix: what the key hands its devices - the
     Sparkplug group and a topic prefix - kept with the login and valid from
     the first scan. A login that stops working is replaced by itself; a
     rising edge of bForget throws it away and registers again. Ok,
     InvalidArgument (no sClientId; no sKey and no stored login),
     NotAuthorized (refused), QueueFull.

  mqtt.Statistics(nVersion =>, nConnects =>, nDisconnects =>,
                  nReconnects =>, nPublished =>, nReceived =>,
                  nPublishFailures =>, nProtocolErrors =>, nPending =>,
                  nReasonCode =>)
     THE CONNECTION'S COUNTERS, running totals since the program started.
     nVersion: 5 or 4, the protocol in force. nReconnects climbing at the
     same time each day is a lease or a job; with the weather, a radio.
     nPublishFailures in a steady ratio to nPublished: something refuses
     messages - read the sending method's result. nPending: operations
     accepted and not yet concluded; climbing and never falling is a broker
     that stopped acknowledging. nProtocolErrors not 0: one end has a bug.
     nReasonCode: the broker's last reason code (always 0 at 3.1.1). Ok;
     NotConnected while there is no link, the figures still written (they count across outages).
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `eTransport` | `E_MqttTransport` |  | where the bytes go: RuntimeTcp, ArduinoWiFi, ArduinoEthernet, Cellular, External |
| `eSecurity` | `E_MqttSecurity` |  | Plain, TlsVerify, TlsPinned or TlsInsecure |
| `sHost` | `STRING(64)` |  | the broker: a name or an address |
| `nPort` | `UINT` |  | 0 for the standard one: 1883 plain, 8883 TLS |
| `sClientId` | `STRING(48)` |  | what the broker calls this device; unique on the broker |
| `eProtocol` | `E_MqttProtocol` |  | V5ThenV311 (default), V5 or V311 |
| `nExternalLink` | `__XWORD` |  | eTransport External: a transport another block made |
| `bConnect` | `BOOL` | `TRUE` | TRUE connects and stays connected; FALSE says goodbye |
| `bTrustNew` | `BOOL` |  | TlsPinned: learn the first key a broker shows; an edge forgets it |
| `stSessionConfig` | `ST_MqttSessionConfig` |  | keep-alive, session, login, queue and message sizes, reconnecting |
| `stTlsConfig` | `ST_MqttTlsConfig` |  | certificate authority and client certificate (Runtime) |
| `stNetworkConfig` | `ST_MqttNetworkConfig` |  | a board's Wi-Fi or Ethernet |
| `stWillConfig` | `ST_MqttWillConfig` |  | presence: online on connect, the Will when gone |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkUp` | `BOOL` |  | the client exists and its link is open |
| `bConnected` | `BOOL` |  | the broker has acknowledged us: the one to interlock on |
| `tHeardAgo` | `TIME` |  | since anything last arrived from the broker |
| `bSessionPresent` | `BOOL` |  | the broker had our session waiting |
| `sAssignedId` | `STRING(48)` |  | the client identifier in force |
| `eConnectionState` | `E_MqttState` |  | where the connection is up to |
| `bError` | `BOOL` |  | something failed |
| `eErrorId` | `E_MqttResult` |  | why; Ok when fine |
| `sLastError` | `STRING(64)` |  | why, in words |
| `sBrokerKey` | `STRING(64)` |  | SHA-256 of the key the broker presented, hexadecimal |

### FB_MqttClient.Publish

```
result := mqtt.Publish(anyValue := ..., sTopic := ..., eQos := ...,
                       bRetain := ..., bExecute := ...);
```

Returns `E_MqttResult`.
Sends anyValue to sTopic once, on a rising edge of bExecute. Inputs are taken at the edge. Returns E_MqttResult.Queued until the broker has it (QoS 1 and 2) or it has left (QoS 0), then E_MqttResult.Ok or the reason it failed, until the next edge. Not connected at the edge: E_MqttResult.NotConnected, nothing queued.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | what to send, as its declared type: 23.5, 42, true, text |
| `sTopic` | `STRING(128)` |  | where it goes; no wildcards |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `bRetain` | `BOOL` |  | the broker keeps it for later subscribers |
| `bExecute` | `BOOL` |  | rising edge sends |

### FB_MqttClient.Report

```
result := mqtt.Report(anyValue := ..., sTopic := ..., eTrigger := ...,
                      fDeadband := ..., tPeriod := ..., eQos := ...,
                      bRetain := ..., bEnable := ..., bExecute := ...,
                      nSent => ..., tAge => ...);
```

Returns `E_MqttResult`.
Publishes anyValue on sTopic, called every scan. eTrigger says when: OnChange (moved by fDeadband, and every tPeriod anyway), OnInterval (every tPeriod, which must be set) or OnRequest (bExecute's rising edge). E_MqttResult.Ok while the record is valid.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the variable to report |
| `sTopic` | `STRING(128)` |  | where it goes; no wildcards |
| `eTrigger` | `E_MqttTrigger` |  | OnChange (default), OnInterval or OnRequest |
| `fDeadband` | `LREAL` |  | OnChange: the least change worth a message; 0 = any change |
| `tPeriod` | `TIME` |  | OnChange: resend unchanged after this, T#0s never; OnInterval: the interval |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `bRetain` | `BOOL` |  | the broker keeps the last one for later subscribers |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops reporting, keeping the record |
| `bExecute` | `BOOL` |  | OnRequest: rising edge sends |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nSent` | `DINT` |  | messages sent for this record |
| `tAge` | `TIME` |  | since the last one; T#0s before the first |

### FB_MqttClient.Subscribe

```
result := mqtt.Subscribe(anyValue := ..., sTopic := ..., eQos := ...,
                         tExpect := ..., bEnable := ..., bSubscribed => ...,
                         eQuality => ..., bSeen => ..., tAge => ...,
                         nReceived => ..., nMalformed => ...,
                         bNewValue => ...);
```

Returns `E_MqttResult`.
Keeps anyValue up to date from sTopic, called every scan. A payload is read as anyValue's declared type; one that does not parse is counted on nMalformed and leaves anyValue alone.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the variable kept up to date |
| `sTopic` | `STRING(128)` |  | wildcards allowed |
| `eQos` | `E_MqttQos` |  | the most the broker may use |
| `tExpect` | `TIME` |  | how often a value is expected; drives eQuality. T#0s = no promise |
| `bEnable` | `BOOL` | `TRUE` | FALSE unsubscribes, keeping the record |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bSubscribed` | `BOOL` |  | the subscription is in force |
| `eQuality` | `E_MqttQuality` |  | Unknown: never arrived; Bad: link down or twice overdue |
| `bSeen` | `BOOL` |  | a value has arrived for this record |
| `tAge` | `TIME` |  | since the last accepted value |
| `nReceived` | `DINT` |  | values accepted |
| `nMalformed` | `DINT` |  | payloads that did not parse |
| `bNewValue` | `BOOL` |  | this call wrote anyValue |

### FB_MqttClient.PublishStruct

```
result := mqtt.PublishStruct(anyData := ..., sBase := ..., eTrigger := ...,
                             tPeriod := ..., eQos := ..., bRetain := ...,
                             bEnable := ..., bExecute := ..., nPoints => ...,
                             nSkipped => ..., nSent => ..., nChanged => ...);
```

Returns `E_MqttResult`.
Publishes every member of the STRUCT anyData on sBase/<member>, called every scan. OnChange: a member when it changes, and every tPeriod anyway; OnInterval: the whole set every tPeriod; OnRequest: the whole set on bExecute's rising edge. A member the wire cannot carry is counted on nSkipped and returns E_MqttResult.InvalidArgument.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT |
| `sBase` | `STRING(128)` |  | the topic the members hang off |
| `eTrigger` | `E_MqttTrigger` |  | OnChange (default), OnInterval or OnRequest |
| `tPeriod` | `TIME` |  | OnChange: resend unchanged after this; OnInterval: the interval |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `bRetain` | `BOOL` |  | the broker keeps the last one for later subscribers |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops it, keeping the record |
| `bExecute` | `BOOL` |  | OnRequest: rising edge sends the set |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nPoints` | `INT` |  | members published |
| `nSkipped` | `INT` |  | members refused |
| `nSent` | `DINT` |  | messages sent for this record |
| `nChanged` | `INT` |  | messages sent by this call |

### FB_MqttClient.SubscribeStruct

```
result := mqtt.SubscribeStruct(anyData := ..., sBase := ..., eQos := ...,
                               tExpect := ..., bEnable := ...,
                               nPoints => ..., nSkipped => ...,
                               bSubscribed => ..., eQuality => ...,
                               bSeen => ..., tOldest => ...,
                               nReceived => ..., nMalformed => ...,
                               nNewValues => ...);
```

Returns `E_MqttResult`.
Keeps every member of the STRUCT anyData up to date from sBase/<member>, called every scan. eQuality is the worst member's, tOldest the oldest member's age.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT |
| `sBase` | `STRING(128)` |  | the topic the members hang off |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `tExpect` | `TIME` |  | how often a value is expected; drives eQuality. T#0s = no promise |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops it, keeping the record |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nPoints` | `INT` |  | members bound |
| `nSkipped` | `INT` |  | members refused |
| `bSubscribed` | `BOOL` |  | the subscription is in force |
| `eQuality` | `E_MqttQuality` |  | the worst member's quality |
| `bSeen` | `BOOL` |  | every member has had a value |
| `tOldest` | `TIME` |  | the oldest member's age |
| `nReceived` | `DINT` |  | values accepted |
| `nMalformed` | `DINT` |  | payloads that did not parse |
| `nNewValues` | `INT` |  | members written by this call |

### FB_MqttClient.Request

```
result := mqtt.Request(anyValue := ..., sTopic := ..., sReplyTopic := ...,
                       eQos := ..., tTimeout := ..., bExecute := ...,
                       sReply => ..., nReplyLen => ...);
```

Returns `E_MqttResult`.
Asks a question on sTopic and waits for the answer on sReplyTopic, MQTT 5 only. The request carries Response Topic and Correlation Data. Rising edge of bExecute starts it; E_MqttResult.Queued until the answer (E_MqttResult.Ok, in sReply) or tTimeout (E_MqttResult.KeepAliveTimeout).

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the question |
| `sTopic` | `STRING(128)` |  | where it goes |
| `sReplyTopic` | `STRING(128)` |  | where the answer comes back; one per requester |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `tTimeout` | `TIME` |  | T#0s = 5 s |
| `bExecute` | `BOOL` |  | rising edge starts it |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sReply` | `STRING(254)` |  | the answer's text |
| `nReplyLen` | `INT` |  | characters in sReply |

### FB_MqttClient.Response

```
result := mqtt.Response(anyRequest := ..., sTopic := ..., anyReply := ...,
                        eQos := ..., bEnable := ..., bExecute := ...,
                        bNewRequest => ..., bAwaitingReply => ...,
                        sResponseTopic => ..., nReceived => ...,
                        nMalformed => ...);
```

Returns `E_MqttResult`.
Answers MQTT 5 requests arriving on sTopic, called every scan. A request's payload is written into anyRequest; a rising edge of bExecute sends anyReply to the last request's Response Topic with its Correlation Data.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyRequest` | `ANY` |  | the request, read as its declared type |
| `sTopic` | `STRING(128)` |  | where requests arrive; wildcards allowed |
| `anyReply` | `ANY` |  | the answer |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `bEnable` | `BOOL` | `TRUE` | FALSE unsubscribes, keeping the record |
| `bExecute` | `BOOL` |  | rising edge answers |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bNewRequest` | `BOOL` |  | this call took a request |
| `bAwaitingReply` | `BOOL` |  | the last request has a Response Topic and is not answered yet |
| `sResponseTopic` | `STRING(128)` |  | where the last request asked its answer to go |
| `nReceived` | `DINT` |  | requests received |
| `nMalformed` | `DINT` |  | payloads that did not parse |

### FB_MqttClient.Message

```
result := mqtt.Message(anyPayload := ..., sTopic := ..., eQos := ...,
                       bEnable := ..., nLen => ..., bTruncated => ...,
                       nReceived => ..., bNewMessage => ...);
```

Returns `E_MqttResult`.
The text of whatever arrives on sTopic, written into the STRING variable anyPayload, one message per call. Called every scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyPayload` | `ANY` |  | a STRING variable |
| `sTopic` | `STRING(128)` |  | wildcards allowed |
| `eQos` | `E_MqttQos` |  | AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops it, keeping the record |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nLen` | `INT` |  | characters written |
| `bTruncated` | `BOOL` |  | the message was longer than anyPayload or the client's buffer |
| `nReceived` | `DINT` |  | messages received |
| `bNewMessage` | `BOOL` |  | this call wrote anyPayload |

### FB_MqttClient.Provision

```
result := mqtt.Provision(sKey := ..., bForget := ..., bProvisioned => ...,
                         bPending => ..., bRefused => ..., sUserName => ...,
                         sGroup => ..., sPrefix => ..., sReason => ...);
```

Returns `E_MqttResult`.
Registers this PLC with a modbee broker using a provisioning key, and keeps the login it is given (retained). sClientId is the PLC's name. Called every scan, before the client's own call on the first scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sKey` | `STRING(127)` |  | from `modbee key create` on the broker |
| `bForget` | `BOOL` |  | rising edge forgets the stored login |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bProvisioned` | `BOOL` |  | connected with this PLC's own login |
| `bPending` | `BOOL` |  | waiting for approval on the broker |
| `bRefused` | `BOOL` |  | the broker said no; sReason says why |
| `sUserName` | `STRING(64)` |  | the login the key handed this PLC |
| `sGroup` | `STRING(64)` |  | the Sparkplug group the key hands its devices |
| `sPrefix` | `STRING(127)` |  | the topic prefix the key hands its devices |
| `sReason` | `STRING(64)` |  | why the broker refused, when bRefused |

### FB_MqttClient.Statistics

```
result := mqtt.Statistics(nVersion => ..., nConnects => ...,
                          nDisconnects => ..., nReconnects => ...,
                          nPublished => ..., nReceived => ...,
                          nPublishFailures => ..., nProtocolErrors => ...,
                          nPending => ..., nReasonCode => ...);
```

Returns `E_MqttResult`.
The connection's counters.

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nVersion` | `BYTE` |  | 5 or 4: the protocol in force |
| `nConnects` | `DINT` |  | connections made |
| `nDisconnects` | `DINT` |  | connections ended |
| `nReconnects` | `DINT` |  | reconnections after a loss |
| `nPublished` | `DINT` |  | messages published |
| `nReceived` | `DINT` |  | messages received |
| `nPublishFailures` | `DINT` |  | publishes that failed |
| `nProtocolErrors` | `DINT` |  | broker packets the standard does not allow |
| `nPending` | `DINT` |  | operations accepted and not yet concluded |
| `nReasonCode` | `BYTE` |  | the last reason code from the broker, read with nVersion |

DEFAULTS ARE THE ONES YOU WANT. MQTT 5.0 falling back to 3.1.1, a sixty
second keep-alive, a clean session, and automatic reconnect with a backoff
that spreads, so forty PLCs restarting together do not arrive at the broker
in step: each wait is random, from 0.1 s up to the current backoff, which
doubles to its cap; it starts small again only once a connection has stayed
up for 30 s, so a link that drops straight after CONNACK keeps backing off.

A REFUSED LOGIN STOPS, AND SAYS WHY. eErrorId NotAuthorized and sLastError
the broker's own reason. It is tried again every five minutes, not at the
usual backoff: a PLC repeating a rejected password every second is how a
site gets itself banned, and a broker fixed at the other end still gets the
PLC back by itself. stSessionConfig.bRetryRejectedCredential TRUE retries at
the backoff, for a broker whose access list loads after it listens.

NOTHING HERE BLOCKS. connect() does not wait for the broker; it starts the
attempt and bConnected says when it arrived. That is what makes MQTT safe in
a scan cycle, and it is why the library exists. On an ESP32 that includes
opening the socket and the TLS handshake: both run on a short task of their
own, below the PLC's tasks, while eConnectionState says Connecting. A board
without threads opens the socket inside the scan, for as long as the medium
takes.

ONE SCAN BEFORE OPENING. The link is built on the block's second scan, so
every method has been called once first, wherever it sits in the program.

TLS ON A BOARD IS THE SAME ON EVERY MEDIUM. On an ESP32, Wi-Fi, Ethernet and
cellular all open a PLAIN connection and the TLS runs on the controller, with
the mbedTLS the board already carries for its Wi-Fi - so every eSecurity
works on every eTransport, sBrokerKey is filled, bTrustNew learns, and the
handshake runs beside the scan instead of in it. A TLS session holds about
40 kB while it is up, in PSRAM where the board has it. The CA comes from
MQTT_CA_CERT_PEM and a certificate of the board's own, for mutual TLS, from
MQTT_CLIENT_CERT_PEM and MQTT_CLIENT_KEY_PEM - defines in the board package's
compiler flags, since an OpenPLC project has no build flags of its own; an
IEC STRING stops at 254 characters and a PEM is about eight times that. For
the site's own broker none is needed: E_MqttSecurity.TlsPinned with bTrustNew
and a login. A board WITHOUT mbedTLS keeps what its medium offers:
WiFiClientSecure (no TlsPinned), no TLS over Ethernet, and the modem's own
TLS (TlsInsecure only). Ethernet itself needs MQTT_ENABLE_ETHERNET in the
board package's compiler flags.

SETTINGS MAY CHANGE WHILE IT RUNS. Every pin and every member of the four
option structures is read every scan. Change the broker, the port, eSecurity,
eTransport, the login, sClientId or eProtocol - from an HMI settings page,
say - and the client says goodbye on the old settings and connects with the
new ones, on the same client: every method's record carries on, nothing
needs a restart. The medium is rebuilt only when what it is made from
changed. A pinned key stays pinned: a new broker address shows a different
key and is refused until bTrustNew is switched off and on, as for a replaced
broker.

PROTOCOLS THAT RIDE ON IT, as layers on this one connection - one radio, one
login, one session for everything the device says:

  FB_SparkplugNode, FB_SparkplugHost  Sparkplug B. Each takes the Will (its
                 death certificate) and a clean session on every connection,
                 so not with stWillConfig, and one of them per client.
  FB_OtaNode     firmware updates (modbee-ota), on topics of its own; its
                 Sparkplug method reports them as a node's metrics.

ONE TASK. This block, its methods and every block given it - Sparkplug,
FB_OtaNode - run in one task, the network task, at a lower priority than the
machine's: T#50ms on a board, faster on the Runtime. The machine's program
trades values with them through globals. Declare the instance in the network
task's program, never in a global list: a machine task that names a global
client waits for the network task's scan. A method called from another task
returns E_MqttResult.WrongTask and does nothing, rather than race the client
from another thread. See docs/10-scan-rate.md.

---

## FB_MqttClock

```
SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet,
the mobile network's own time over cellular - so Sparkplug timestamps and
CURRENT_DT are real time. One per controller, called every scan in the
network task. Standalone: it takes no FB_MqttClient.

eTransport  where the time comes from - the same list as FB_MqttClient, so a
           site that moves from Wi-Fi to cellular changes one pin on each:
             E_MqttTransport.RuntimeTcp       the Runtime's own clock, which
                                              its operating system keeps.
                                              Nothing is set
             E_MqttTransport.ArduinoWiFi      NTP from sServer, through the
             E_MqttTransport.ArduinoEthernet  board's IP stack (ESP32).
                                              node-uio's NETWORK or the
                                              FB_MqttClient brings the
                                              network up; this waits for it
             E_MqttTransport.Cellular         the mobile network's time
                                              (NITZ) from the modem a
                                              modbee-gsm GSM_MODEM runs.
                                              Costs no data. Not every
                                              network sends it
             E_MqttTransport.External         dtUtcIn, when bUtcInValid - an
                                              RTC, GSM_TIME's UTC, a time a
                                              SCADA wrote
sServer     the NTP server. 'pool.ntp.org' by default; a site with its own (a
           router, a SCADA server) should use it.
tRefresh    how often to ask again. T#1h by default - a board's crystal
           drifts a second or two a day, so hourly is plenty.
dtUtcIn     E_MqttTransport.External: the time to set, in UTC.
bUtcInValid E_MqttTransport.External: dtUtcIn is good. Its rising edge sets
           the clock, and again every tRefresh while it stays TRUE.
bEnable     FALSE stops asking. The clock keeps the time it has.

bSynced     the clock holds real time - a date after 2024. Exactly what
           FB_SparkplugNode's bClockSet reports.
dtUtc       the time now, in UTC. DT#1970-01-01 while not bSynced.
tAge        how long since the clock was last set. Grows while the network
           is away - the clock keeps running on its own crystal meanwhile.
bError      the transport cannot give the time on this target, or NTP has
           not answered for a minute after starting.
sLastError  why, in words. Empty when fine.
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `eTransport` | `E_MqttTransport` |  | where the time comes from |
| `sServer` | `STRING(64)` | `'pool.ntp.org'` | the NTP server |
| `tRefresh` | `TIME` | `T#1h` | how often to ask again |
| `dtUtcIn` | `DT` |  | E_MqttTransport.External: the time to set, in UTC |
| `bUtcInValid` | `BOOL` |  | E_MqttTransport.External: dtUtcIn is good |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops asking; the clock keeps its time |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bSynced` | `BOOL` |  | the clock holds real time |
| `dtUtc` | `DT` |  | the time now, in UTC |
| `tAge` | `TIME` |  | since the clock was last set |
| `bError` | `BOOL` |  |  |
| `sLastError` | `STRING(64)` |  | why, in words; empty when fine |

wifi ( ENABLE := TRUE, SSID := ..., PASSWORD := ... );   NETWORK, node-uio
  ntp  ( eTransport := E_MqttTransport.ArduinoWiFi );
  mqtt ( eTransport := E_MqttTransport.ArduinoWiFi, sHost := ..., ... );
  sp   ( fbClient := mqtt, ... );                          stamps with it

ONE CLOCK, AND EVERYTHING USES IT. This sets the board's system clock, so
FB_SparkplugNode's timestamps, CURRENT_DT and anything else that asks for the
date agree, with nothing to wire between them.

UNTIL IT IS SYNCED a board counts from when it started, and the timestamps it
sends are dates in January 1970 - unmistakably not real. A SCADA historian
should take a timestamp like that as "not synced" and stamp the value with
the time it arrived instead. bSynced and bClockSet say which it is. Once set,
the clock survives a loss of network and keeps time on its own.

ON THE RUNTIME THIS BLOCK SETS NOTHING. The operating system's time service
owns the clock there, and a PLC program stepping it under every other program
on the machine would be a fault, not a feature. bSynced still reports it.

NOTHING HERE BLOCKS. NTP runs in the background on the board's network stack,
and the modem is asked through GSM_MODEM's queue. Put this in the network
task beside the MQTT blocks.

---

## FB_SparkplugHost

```
A SPARKPLUG B HOST APPLICATION on an FB_MqttClient's connection: the other
end of FB_SparkplugNode. Call it once every scan, in the client's task. It
keeps the current picture of every edge node it watches; Watch reads a value
out of that picture and Write sends one back down.

sHostId     this host's Sparkplug Host ID. It is a topic element and MUST be
           unique in the system. An edge node's sPrimaryHostId carries this
           same string. Up to 47 characters.
sGroupId    the group to watch, or empty for every group. Narrow it on a real
           plant: a host on spBv1.0/# receives every other line's traffic.
bPrimary    TRUE (default): ask for a rebirth when a node's sequence skips.
           Nothing in the protocol marks a host primary - the NODES name it -
           so this only decides whether a gap asks; two hosts both asking
           double the traffic for one missed message.
tReorder    how long to let a gap fill before asking. T#5s by default; T#0s
           asks at once. A link that reorders now and then should not cost a
           full birth each time.
bEnable     FALSE publishes the offline STATE and stands the host down; the
           connection stays up for everything else on it.
fbClient    the FB_MqttClient this host rides on. Must be assigned; broker,
           TLS, login and protocol are set there.

bLinkUp     the client's session is up.
bBorn       our STATE birth certificate is published, so nodes may rely on us.
           A node waiting for this host starts birthing once it sees it.
nNodes      edge nodes heard from. A node that died stays tracked: knowing it
           is gone is worth more than forgetting it existed.
nOnline     how many of them are online now.
nGaps       sequence gaps seen, every node together.
nRebirths   rebirths asked for. Both climbing together is a lossy link; gaps
           climbing alone means tReorder is absorbing them.
bError, eErrorId  E_MqttResult.Ok when fine; WrongTask: not in its client's
           task.
sLastError  what the host waits for, or what failed: "out of memory for
           tracked nodes or metrics" when it could not follow everything that
           arrived. It tracks as many nodes, and metrics per node, as memory
           holds, on a board and the Runtime alike.

METHODS

Both run in the host's task and return E_MqttResult.WrongTask in any other.
A call is found again by anyValue's declared name and type with sMetricName.

  host.Watch(sMetricName, anyValue, sEdgeNodeId, sNodeGroupId, sDeviceId,
             bValid =>, bTypeOk =>, bFresh =>, nAge =>, nReadCnt =>)
     READS ONE METRIC into a variable of your own type. Standing: call it
     every scan while the value is wanted; stop and anyValue holds its last
     value.
     THE NAME IS THE ADDRESS, not a topic and not an alias: the node declared
     "level" in its birth and Watch asks for "level"; the host resolves the
     aliases data messages carry. THE DECLARED TYPE IS CHECKED, NOT COERCED:
     if the birth said REAL and anyValue is a DINT the read is refused rather
     than a reading truncated.
     sMetricName   the metric, exactly as the node declared it.
     anyValue      where to put it. Any IEC type matching the birth.
     sEdgeNodeId   which node. Empty: the first node heard from - convenient
                   with one node, wrong with two.
     sNodeGroupId  which group. Empty: any group the host watches.
     sDeviceId     for a metric of a device rather than the node.
     bValid        this call wrote anyValue.
     bTypeOk       FALSE: anyValue's type is not the declared one.
     bFresh        the reading changed since the last call.
     nAge          milliseconds since the NODE's timestamp on it - not since
                   we received it; on a slow link those differ by more than a
                   control decision should ignore.
     nReadCnt      readings written into anyValue.
     Ok when anyValue holds a valid reading; NotInitialised while the host is
     not built, the node not heard or the metric not published (a plant
     starting up spends its first seconds here); NotConnected while the
     client is down; InvalidArgument for an empty sMetricName or a type
     mismatch.

  host.Write(sMetricName, anyValue, sEdgeNodeId, sNodeGroupId, sDeviceId,
             bExecute, nSentCnt =>)
     WRITES ONE METRIC on an edge node: an NCMD, or a DCMD for a device
     metric. The node applies it to whatever it reports under that name and
     reports the new value back under the SAME name, so Watch that name to
     see it come back. THE NODE DECIDES: a command for a metric it never
     declared, declared read-only or with another type is refused there and
     counted - Write reports that it sent one, not that it took effect.
     A request: the rising edge of bExecute takes every input, anyValue
     included. Not connected: NotConnected at once, never queued. A node not
     heard from yet: Queued while bExecute stays TRUE, sent as soon as it
     appears; bExecute falling first drops it (Cancelled) - a command that
     arrives a minute after the operator let go is worse than one that never
     arrived. Then Ok (sent), Refused (the client would not take it) or
     InvalidArgument (empty sMetricName, or an IEC type with no Sparkplug
     datatype), held until the next rising edge. nSentCnt: commands this
     call has sent.
```

**In-out**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `fbClient` | `FB_MqttClient` |  | the connection this host rides on |

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `sHostId` | `STRING(47)` |  | this host's Sparkplug Host ID |
| `sGroupId` | `STRING(47)` |  | The group to watch, or empty for every group. Narrowing matters on a real plant: a host subscribed to spBv1.0/# in a large estate receives every other line's traffic to discard. |
| `bPrimary` | `BOOL` | `TRUE` | Whether to act as the PRIMARY host. Nothing in the protocol marks a host as primary - the NODES are configured with its id - so this only decides whether a sequence gap produces a rebirth request. Two hosts both asking would double the traffic for one missed message. |
| `tReorder` | `TIME` | `T#5s` | How long to wait for a gap to fill before asking for a rebirth. A link that reorders occasionally should not trigger a full birth every time. T#0s disables the window and asks immediately. |
| `bEnable` | `BOOL` | `TRUE` | FALSE publishes the offline STATE |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkUp` | `BOOL` |  | the client's session is up |
| `bBorn` | `BOOL` |  | Our own STATE birth certificate is published and the plant may rely on us. An edge node waiting for this host starts birthing once it sees it. |
| `nNodes` | `INT` |  | How many edge nodes we have heard from, and how many are online now. A node that has died stays tracked - knowing it is gone is worth more than forgetting it existed. |
| `nOnline` | `INT` |  |  |
| `nGaps` | `DINT` |  | Sequence gaps seen and rebirths asked for, across every node. Both climbing together is a lossy link; gaps climbing alone means the window is absorbing them, which is what it is for. |
| `nRebirths` | `DINT` |  |  |
| `bError` | `BOOL` |  |  |
| `eErrorId` | `E_MqttResult` |  |  |
| `sLastError` | `STRING(64)` |  | what the host waits for, or what failed |

### FB_SparkplugHost.Watch

```
result := host.Watch(sMetricName := ..., anyValue := ..., sEdgeNodeId := ...,
                     sNodeGroupId := ..., sDeviceId := ..., bValid => ...,
                     bTypeOk => ..., bFresh => ..., nAge => ...,
                     nReadCnt => ...);
```

Returns `E_MqttResult`.
Reads one metric of a watched node into anyValue, called every scan. The metric's declared type must match anyValue's. Ok while anyValue holds a valid reading; NotInitialised until the node and the metric are heard.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sMetricName` | `STRING(96)` |  | the metric, as the node declared it |
| `anyValue` | `ANY` |  | where to put it; its type must match the birth |
| `sEdgeNodeId` | `STRING(47)` |  | empty: the first node heard from |
| `sNodeGroupId` | `STRING(47)` |  | empty: any watched group |
| `sDeviceId` | `STRING(47)` |  | for a device metric |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bValid` | `BOOL` |  | anyValue was written by this call |
| `bTypeOk` | `BOOL` |  | FALSE: anyValue's type is not the declared one |
| `bFresh` | `BOOL` |  | the reading changed since the last call |
| `nAge` | `DINT` |  | ms since the node's timestamp on it |
| `nReadCnt` | `DINT` |  | readings written |

### FB_SparkplugHost.Write

```
result := host.Write(sMetricName := ..., anyValue := ..., sEdgeNodeId := ...,
                     sNodeGroupId := ..., sDeviceId := ..., bExecute := ...,
                     nSentCnt => ...);
```

Returns `E_MqttResult`.
Sends one command (NCMD, or DCMD for a device) on a rising edge of bExecute. Queued while the node is not heard yet and bExecute stays TRUE; Cancelled if bExecute falls first; then Ok (sent) or the reason. Not connected at the edge: NotConnected, nothing queued.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sMetricName` | `STRING(96)` |  | the metric, as the node declared it |
| `anyValue` | `ANY` |  | what to write; its type must match the birth |
| `sEdgeNodeId` | `STRING(47)` |  | empty: the first node heard from |
| `sNodeGroupId` | `STRING(47)` |  | empty: any watched group |
| `sDeviceId` | `STRING(47)` |  | for a device metric |
| `bExecute` | `BOOL` |  | rising edge sends |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nSentCnt` | `DINT` |  | commands sent |

WHAT A HOST DOES THAT A NODE DOES NOT, and why this is a separate block:

  - It publishes its OWN birth and death certificate on
    spBv1.0/STATE/<sHostId>, at QoS 1 and RETAINED - retained, unlike a
    node's death certificate, because a node subscribing later has to find
    it waiting or it will never birth at all.
  - It reads names out of BIRTH certificates and resolves them against the
    aliases data messages carry. A conformant node puts names only in its
    births; without the dictionary a host receives numbers it cannot name.
  - It notices gaps in a node's sequence number and, with bPrimary, asks for
    a rebirth.

sPrimaryHostId on the node and sHostId here are the same string. A node
configured with one will not birth until this host says it is online, which
is how a plant avoids nodes publishing into a SCADA that is not listening.

ONE CONNECTION, SHARED. The host is a layer on its client's session and
takes its Will - the offline STATE - and a clean session on every CONNECT, so
no stWillConfig and no FB_SparkplugNode on the same client: a connection
carries one Will. Started on a session already up, it reconnects it once so
the next CONNECT carries the STATE.

ONE TASK. This block, its methods and fbClient run in the network task, and
the rest of the program trades values with them through globals.

---

## FB_SparkplugNode

```
A SPARKPLUG B EDGE NODE on an FB_MqttClient's connection. Call it once every
scan, in the client's task. What it reports is its methods: a whole STRUCT by
point list (Record), one value (Metric), a device (Device), a host's write
(Command), events kept through an outage (History) and daily totals
(DayTotals).

sGroupId    the Sparkplug Group ID: a logical grouping of nodes - a site, a
           pipeline segment, a cell. Descriptive but small: it is in every
           topic. Up to 47 characters, as every Sparkplug id here; no + / #.
sEdgeNodeId this node's ID. sGroupId and sEdgeNodeId together are the node's
           address in the whole system and MUST be unique in it.
sPrimaryHostId  the Sparkplug Host ID this node answers to, or empty for none.
           EMPTY BY DEFAULT - see below.
tRebirthHoldoff  the shortest time between two answers to rebirth requests
           (Node Control/Rebirth): requests in between are answered together,
           once, when it is up. T#2s by default. On a metered link (a cellular
           SIM) set a minute or more: a host that asks again and again then
           costs one birth a minute at most.
bEnable     FALSE sends the NDEATH and keeps the node down without losing a
           metric; the connection stays up for everything else on it.
stReportConfig  ST_SparkplugReportConfig, how Record's classes report:
             tLogInterval   how often the log class looks for what moved.
                            T#15m by default and at most; T#0s is refused
             tLiveInterval  how often the live class sends what moved, and
                            the log class while someone views. T#30s by
                            default. T#0s is refused, never every scan
             fDeadbandPct   the log class's deadband, in % of the value last
                            sent, for a REAL or LREAL member whose clause
                            gives no pct=. 0 = none
             bRemoteControl TRUE: the host may write the cmd and set classes.
                            FALSE: a write is dropped at once and the value
                            reported back unchanged, so the host sees it did
                            not take. Never kept for later
anyUnits    optional: a STRUCT of STRINGs whose members a point list names
           with u=@<member>, so units can come from a settings page. A change
           shows at the next birth.
fbClient    the FB_MqttClient this node rides on. Must be assigned.
           Everything about the connection is set there - broker, TLS, login,
           keep-alive, protocol - and the device's own topics and its firmware
           updates share the one session.

bLinkUp     the client's session is up.
bBorn       the birth certificate has gone. NOT the same as bLinkUp: a node
           waiting for its primary host is connected and not born.
nSeq        the current sequence number, 0-255.
nBdSeq      the birth/death sequence number of this connection.
nPoints     metrics declared, node and devices together. No limit but memory:
           past it the declaration is refused and sLastError says "out of
           memory for metrics or devices".
bError, eErrorId  E_MqttResult.Ok when fine. WrongTask: this block is not in
           its client's task, and does nothing until it is. QueueFull: out of
           memory. InvalidArgument: a Record call whose point list is wrong.
           NotConnected (bError FALSE): the client is not connected.
sLastError  what the node waits for, or what failed:
             "no STATE from primary host 'scada'"   the host has never
                                    reached this broker - or the id differs
             "offline STATE from primary host 'scada'"  the host is down
             "broker refused STATE/scada subscription (not authorized)"
             "birth could not be queued - retrying"
             "out of memory for metrics or devices"
             "another layer owns the client's Will"  an FB_SparkplugHost or a
                                    second node on fbClient
             "Record pump: clause 3"  that record's point list; also "not a
                                    STRUCT with a STRING point list",
                                    "tLiveInterval is T#0s", "message not
                                    queued"
           Empty once born.
bClockSet   the timestamps are real time. Always on the Runtime; on a board
           once FB_MqttClock has set the clock. Until then they count from
           boot - a date in January 1970 - which a host should take as "not
           synced" and replace with the time it received the message.
bViewed     Live Demand: a host says someone is viewing this node now.
sDemand     Live Demand: the devices demanded now, e.g. 'live,cfg-pump'.

METHODS

Every method is standing: call it every scan while it is wanted, after the
node's own call. Ok while the node is born; E_MqttResult.NotConnected while it
is not, the value kept for the next birth. WrongTask in any other task than
the node's; NotInitialised before the node's first call. A node holds up to
1024 Metric, Device, Command, History and DayTotals calls; past that,
QueueFull. A BIRTH CARRIES EVERY METRIC: declare on the first scans and the
node births with all of them (it waits up to 2 s for the first declaration).
A metric first declared after the birth makes the node birth again.

  sp.Record(anyData, sSettings, sPrefix, bSend, nMetricCnt =>, nBadClause =>)
     A WHOLE STRUCT, EACH MEMBER BY ITS CLASS. anyData is the record (nested
     STRUCTs and arrays included); sSettings its point list, a STRING of any
     length or a literal; sPrefix goes before every metric name. A record is
     found by its declared name and type and sPrefix: the same STRUCT with
     two prefixes is two records. nMetricCnt: metrics it declared.
     nBadClause: the first clause that cannot be used, counting from 1; 0
     none; -1 when anyData is not a STRUCT or sSettings not a STRING. The
     other clauses still apply.

     THE POINT LIST is clauses split by ';':
         <members> = <class> [, <option>]*
     <members> is a comma list of paths: 'level', 'pump.hours', 'spare[2]'.
     A path covers everything below it ('pump' is every value in pump), a
     name without an index covers every element ('spare' is spare[1] ..
     spare[n]), and '*' is any one segment ('*' alone is every member,
     'sts.*' everything in sts). A member no clause covers is not reported.
     Case does not matter; spaces are ignored.

     <class> says when it goes, where, and whether the host may write it:
       now         at once, always. Read only. Alarms, states, faults
       cmd         at once, always; the host writes it while
                   stReportConfig.bRemoteControl is TRUE
       view        at once while someone views (bViewed); otherwise held
       log         what moved past its deadband, every tLogInterval (every
                   tLiveInterval while someone views). For a metered link:
                   a value that sits still costs nothing
       live        on device 'live': what moved, every tLiveInterval, while
                   a host demands it
       set:<page>  on device 'cfg-<page>': at once while demanded; the host
                   writes it while bRemoteControl is TRUE. <page> up to 43
                   characters, no + / #
       every:<time>  all of them every <time> (T#1m, 30s, 1h30m), moved or
                   not; a birth counts as a send
       onreq       all of them on a rising edge of Record's bSend
     A value takes the class of the LAST now/cmd/view/log/every/onreq clause
     covering it, on the node and, separately, on each dev= device; it may
     also be in live and in any number of set pages, each a metric of its own
     on that device. Options come from the clause that gave the class.

     <option>:
       db=<n>      deadband in the member's units: a move this size or less
                   from the value last sent is not reported
       pct=<n>     deadband in % of the value last sent. With db=, a move
                   must clear both. Not given on a log REAL: fDeadbandPct
       u=<text>    engineering units, in the birth (engUnit). A TIME says
                   'ms' by itself
       u=@<member> the units are that STRING member of anyUnits
       lo=<n>, hi=<n>  the range a gauge or trend should show (engLow,
                   engHigh); equal = none
       pulse=<ms>  cmd and set only: the PLC puts the member back to 0,
                   FALSE or '' this many milliseconds after a host write,
                   for a command that acts on an edge
       dev=<name>  now, cmd, view, log, every and onreq: the members go
                   under the program's own device <name> instead of the
                   node. The program brings it on and off line with
                   sp.Device; Live Demand never touches it. Not 'live' or
                   'cfg-...'
     A deadband on a BOOL or STRING the clause names itself is an error;
     covered by a wider path, the BOOL simply reports every change. A value
     the host writes is always reported back, whatever the deadband.

     METRIC NAMES are sPrefix and the path: 'pump/' and sts.fault give
     'pump/sts.fault'; array elements count from 1 whatever the bounds. The
     live class drops a leading 'det.' and a set page a leading 'set.', so
     det.rate on 'live' is 'pump/rate' and set.onLevel on 'cfg-pump' is
     'pump/onLevel'. An enumeration goes as its unsigned integer; a TIME as
     Int64 milliseconds; a DATE or TIME_OF_DAY has no Sparkplug type and is
     left out.

     WHICH MEMBERS, AND THEIR CLASS, ARE READ AT THE FIRST CALL. Options
     follow later changes of the text, of anyUnits and of fDeadbandPct (units
     and ranges show at the next birth); adding or removing a clause later is
     reported on nBadClause - restart the PLC to change membership.
     Ok, NotConnected, InvalidArgument (a bad clause, or tLogInterval or
     tLiveInterval T#0s where it is used), QueueFull (out of memory, or a message
     asked for could not be queued: it asks again).

     LIVE DEMAND. A record with a view, log, live or set class makes the
     node offer the metric 'Node Control/Live Demand', a String whose value
     names what can be demanded:
         {"devices":["live","cfg-pump"],"required":false}
     A host viewing the node writes it:
         {"demand":true,"leaseS":120,"devices":["live","cfg-pump"]}
     Then bViewed is TRUE for leaseS seconds (120 when missing or outside 1
     to 86399): the view class sends, the log class goes at tLiveInterval,
     and each device listed is born (DBIRTH) and sends; a device not listed
     dies (DDEATH). The host writes again before the lease ends to keep it;
     {"demand":false} ends it at once; a write without "demand", or longer
     than 200 characters, is ignored. The offer is put back after every
     write. sDemand lists the devices demanded now. Devices 'live' and
     'cfg-...' are the node's: Device and Metric refuse them.

  sp.Metric(anyValue, sMetricName, sDeviceId, sUnits, eQuality, fDeadband,
            bWritable, bPublish, bUpdate, nAlias =>, nWrittenCnt =>,
            nLostCnt =>)
     ONE VALUE THE PROGRAM SETS. anyValue's declared type is the metric's
     datatype, declared at the first call; sMetricName is the name the host
     sees (case matters); sDeviceId puts it under a device of this node,
     which the first such call adds and brings online unless a Device call
     added it. sUnits goes in the birth. eQuality (Good by default) goes
     with the value: Uncertain as stale, Bad and Unknown as bad. fDeadband:
     a move this size or less from the value last sent is not reported
     (numbers only; InvalidArgument on a BOOL or STRING). bWritable TRUE at
     the first call declares it writable: a host command is written into
     anyValue, one a call, oldest first, up to four waiting (nLostCnt counts
     the dropped); bWritable FALSE later drops a write at once and reports
     the value back. bUpdate FALSE holds the last value and takes no
     command. nAlias: the alias the host sees, 0 refused. nWrittenCnt: host
     commands written. Ok, NotConnected, InvalidArgument (empty name, a type
     with no Sparkplug datatype, a name taken, a device the node manages),
     QueueFull.

  sp.Device(sDeviceId, bOnline, bDeviceOnline =>, nBirthCnt =>,
            nDeathCnt =>)
     A DEVICE THE PROGRAM BRINGS ONLINE AND OFFLINE: a pump skid, a remote
     I/O drop - something that can be lost while the node is fine. Acts on a
     change of bOnline (TRUE: DBIRTH, FALSE: DDEATH), never every scan, and
     births the device again after every node birth. Its metrics are
     Metric calls with this sDeviceId. bDeviceOnline: its birth has gone.
     nBirthCnt, nDeathCnt: births gone, deaths of an online device. Ok,
     NotConnected, InvalidArgument (empty, or 'live' or 'cfg-...', which
     Live Demand manages), QueueFull.

  sp.Command(sMetricName, sDeviceId, bAck, bPending =>, fValue =>,
             bValue =>, sText =>, nCmdCnt =>, nRefusedCnt =>, nLostCnt =>)
     A HOST'S WRITE FOR THE PROGRAM TO DECIDE ON, on a metric declared
     writable with Metric; call it BEFORE that Metric call. bPending shows
     the oldest write waiting, read without taking it, so a rung can look
     before it decides; a rising edge of bAck takes it, so two rungs cannot
     both act on one command. fValue: its value as a number (bValue = fValue
     <> 0), sText a String metric's value cut to 126 characters. nCmdCnt:
     commands seen on this metric. nRefusedCnt: commands the node refused -
     undeclared, read only or the wrong type - all metrics together.
     nLostCnt: writes dropped with four waiting. Ok, NotInitialised (the
     metric is not declared yet), InvalidArgument (not writable), QueueFull.

  sp.History(nSource, nCode, fValue, sMetricPrefix, nDepth, nBatch, tPeriod,
             bAdd, nStoredCnt =>, nLostCnt =>, nSentCnt =>, bReplaying =>)
     EVENTS KEPT THROUGH AN OUTAGE. bAdd TRUE records one event on this call
     - wire a one-scan pulse - with what it is about (nSource: a pump, an
     alarm number), what happened (nCode) and a number (fValue). While the
     node is born it goes at once as live data; recorded while it is not, it
     waits and goes after the next node birth flagged historical, at its own
     time, oldest first, nBatch at a time (at most 64) every tPeriod. Each
     event is the metrics <sMetricPrefix>/source, /code, /value and /seq (a
     count from 1, so the host sees a gap), plus /lost. Calls with one
     sMetricPrefix share one buffer of nDepth events (256: about a week of a
     normal site, 24 bytes each, in PSRAM on a board); nDepth and nBatch are
     fixed at the first call. A full buffer drops the oldest (nLostCnt).
     Not retained. Sent at least once: an event is forgotten only after the
     node stays born on the same birth for half a second; a device's birth
     does not count. Events recorded before the clock is set are placed on
     it once set; they wait for the clock up to five minutes after a birth.
     nStoredCnt waiting, nSentCnt sent, bReplaying catching up. Ok,
     NotConnected, NotInitialised (no memory for the buffer),
     InvalidArgument (the metrics could not be declared), QueueFull.

  sp.DayTotals(anyDays, sMetricName, fValue, dtClock, tSaveEvery, nDays =>,
               nSentCnt =>)
     DAILY TOTALS, sent on every node birth as historical values, so a host
     fills in the days the link was down. anyDays is a RETAINED ARRAY OF
     ST_SparkplugDay, two rows or more: the first is today, the rest closed
     days, newest first. fValue is today's running total; dtClock the local
     date and time the totaliser rolls its day on. When dtClock's date
     changes the day is closed with the total of its last call and becomes
     the newest closed day; the oldest falls off. A day that ended during a
     power cut is closed when the PLC returns, from the total last saved:
     today's total is written into anyDays every tSaveEvery (T#1h; T#0s
     every call). Each closed day goes as a value of sMetricName stamped
     00:00 of its date (the date as dtClock has it, written as UTC: read
     the date, not the hour), on every node birth and every close - not on
     a device's birth. The live value is the last closed day. Nothing
     happens while the clock is not set. nDays: closed days held. Ok,
     NotConnected, InvalidArgument (anyDays is not an ARRAY OF
     ST_SparkplugDay of two rows or more, or the metric could not be
     declared), QueueFull.
```

**In-out**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `fbClient` | `FB_MqttClient` |  | the connection this node rides on |

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `sGroupId` | `STRING(47)` |  | the Sparkplug Group ID |
| `sEdgeNodeId` | `STRING(47)` |  | this node's Edge Node ID; with sGroupId unique in the system |
| `sPrimaryHostId` | `STRING(47)` |  | the Primary Host this node answers to; empty for none |
| `tRebirthHoldoff` | `TIME` | `T#2s` | the shortest time between two answers to rebirth requests |
| `bEnable` | `BOOL` | `TRUE` | FALSE keeps the node down without losing its metrics |
| `stReportConfig` | `ST_SparkplugReportConfig` |  | Record: intervals, log deadband, remote control |
| `anyUnits` | `ANY` |  | Record: a STRUCT of STRINGs that u=@<member> names; optional |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkUp` | `BOOL` |  | the client's session is up |
| `bBorn` | `BOOL` |  | the birth certificate has gone |
| `nSeq` | `USINT` |  | the current sequence number |
| `nBdSeq` | `USINT` |  | the birth/death sequence number of this connection |
| `nPoints` | `INT` |  | metrics declared |
| `bError` | `BOOL` |  |  |
| `eErrorId` | `E_MqttResult` |  |  |
| `sLastError` | `STRING(64)` |  | what the node waits for, or what failed |
| `bClockSet` | `BOOL` |  | the timestamps are real time |
| `bViewed` | `BOOL` |  | Live Demand: someone views this node now |
| `sDemand` | `STRING(200)` |  | Live Demand: the devices demanded now, e.g. 'live,cfg-pump' |

### FB_SparkplugNode.Record

```
result := sp.Record(anyData := ..., sSettings := ..., sPrefix := ...,
                    bSend := ..., nMetricCnt => ..., nBadClause => ...);
```

Returns `E_MqttResult`.
A STRUCT's members as metrics, each by its class, from one point list of clauses '<members> = <class> [, <option>]*' split by ';'. Classes now, cmd, view, log, live, set:<page>; options db=, pct=, u=, u=@<member>, lo=, hi=, pulse=. Called every scan. Ok while the node is born, NotConnected while not (the record goes in the next birth).

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | the record: a STRUCT |
| `sSettings` | `ANY` |  | its point list: a STRING of any length, or a literal |
| `sPrefix` | `STRING(32)` |  | put before every metric name |
| `bSend` | `BOOL` |  | onreq: a rising edge sends those members, all of them |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nMetricCnt` | `INT` |  | metrics the record declared |
| `nBadClause` | `INT` |  | the first clause that cannot be used, from 1; 0 none |

### FB_SparkplugNode.Metric

```
result := sp.Metric(anyValue := ..., sMetricName := ..., sDeviceId := ...,
                    sUnits := ..., eQuality := ..., fDeadband := ...,
                    bWritable := ..., bPublish := ..., bUpdate := ...,
                    nAlias => ..., nWrittenCnt => ..., nLostCnt => ...);
```

Returns `E_MqttResult`.
One metric the program sets, called every scan. anyValue's declared type is its datatype, declared at the first call. Ok while the node is born, NotConnected while not (the value goes in the next birth).

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the value; a host command is written here when bWritable |
| `sMetricName` | `STRING(96)` |  | the name the host sees; case matters |
| `sDeviceId` | `STRING(47)` |  | a device of this node; empty for a node metric |
| `sUnits` | `STRING(16)` |  | engUnit in the birth |
| `eQuality` | `E_MqttQuality` | `E_MqttQuality.Good` | Uncertain goes as stale, Unknown as bad |
| `fDeadband` | `REAL` |  | numbers: a move this size or less from the value last sent is not reported |
| `bWritable` | `BOOL` |  | a host may command it; declared once, writes dropped while FALSE |
| `bPublish` | `BOOL` | `TRUE` | asks the node for this scan's data message |
| `bUpdate` | `BOOL` | `TRUE` | FALSE holds the last value and takes no command |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nAlias` | `UDINT` |  | the alias the host sees after the birth; 0 refused |
| `nWrittenCnt` | `DINT` |  | host commands written into anyValue |
| `nLostCnt` | `DINT` |  | writes dropped with four already waiting |

### FB_SparkplugNode.Device

```
result := sp.Device(sDeviceId := ..., bOnline := ..., bDeviceOnline => ...,
                    nBirthCnt => ..., nDeathCnt => ...);
```

Returns `E_MqttResult`.
A device the program brings online and offline, called every scan. Acts on a change of bOnline; births it again after every node birth. Ok while the node is born. Devices the node manages itself ('live', 'cfg-...') are refused.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sDeviceId` | `STRING(47)` |  | unique among this node's devices |
| `bOnline` | `BOOL` | `TRUE` | TRUE births the device, FALSE sends its death |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bDeviceOnline` | `BOOL` |  | its birth has gone |
| `nBirthCnt` | `DINT` |  | births gone; one more after every node birth |
| `nDeathCnt` | `DINT` |  | deaths of an online device |

### FB_SparkplugNode.Command

```
result := sp.Command(sMetricName := ..., sDeviceId := ..., bAck := ...,
                     bPending => ..., fValue => ..., bValue => ...,
                     sText => ..., nCmdCnt => ..., nRefusedCnt => ...,
                     nLostCnt => ...);
```

Returns `E_MqttResult`.
A host command on a writable metric, for the program to decide on, called every scan. bPending shows the oldest write; a rising edge of bAck takes it. NotInitialised until the metric is declared.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sMetricName` | `STRING(96)` |  | a metric declared writable |
| `sDeviceId` | `STRING(47)` |  | its device; empty for a node metric |
| `bAck` | `BOOL` |  | rising edge takes the pending command |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bPending` | `BOOL` |  | a command waits, not taken |
| `fValue` | `LREAL` |  | its value as a number, from the call it was first seen |
| `bValue` | `BOOL` |  | fValue <> 0 |
| `sText` | `STRING(126)` |  | a String metric's value, cut to 126 characters |
| `nCmdCnt` | `DINT` |  | commands seen on this metric |
| `nRefusedCnt` | `DINT` |  | commands the node refused, all metrics together |
| `nLostCnt` | `DINT` |  | writes dropped on this metric with four already waiting |

### FB_SparkplugNode.History

```
result := sp.History(nSource := ..., nCode := ..., fValue := ...,
                     sMetricPrefix := ..., nDepth := ..., nBatch := ...,
                     tPeriod := ..., bAdd := ..., nStoredCnt => ...,
                     nLostCnt => ..., nSentCnt => ..., bReplaying => ...);
```

Returns `E_MqttResult`.
Events kept while the node cannot publish, sent after the next birth flagged historical, in order, at their own time. Called every scan; calls with one sMetricPrefix share one buffer.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nSource` | `UINT` |  | what the event is about: a pump, an alarm number |
| `nCode` | `UINT` |  | what happened: a status, fault or stop code |
| `fValue` | `REAL` |  | a number that goes with it |
| `sMetricPrefix` | `STRING(24)` | `'Event'` | metrics <prefix>/source, /code, /value, /seq, /lost |
| `nDepth` | `UINT` | `256` | events kept; fixed at the first call |
| `nBatch` | `UINT` | `20` | events a catch-up message, at most 64; fixed at the first call |
| `tPeriod` | `TIME` | `T#1s` | between catch-up messages |
| `bAdd` | `BOOL` |  | TRUE records one event on this call |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nStoredCnt` | `UINT` |  | events waiting to be sent |
| `nLostCnt` | `UDINT` |  | events dropped with the buffer full: the oldest go |
| `nSentCnt` | `UDINT` |  | events sent since the program started |
| `bReplaying` | `BOOL` |  | sending what was kept during an outage |

### FB_SparkplugNode.DayTotals

```
result := sp.DayTotals(anyDays := ..., sMetricName := ..., fValue := ...,
                       dtClock := ..., tSaveEvery := ..., nDays => ...,
                       nSentCnt => ...);
```

Returns `E_MqttResult`.
A table of daily totals kept by the program and sent on every birth as historical values, so the host fills in the days the link was down. Called every scan. A change of date on dtClock closes the day. Ok while born.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyDays` | `ANY` |  | ARRAY OF ST_SparkplugDay, retained, 2 rows or more: today, then closed days newest first |
| `sMetricName` | `STRING(32)` |  | the metric; its live value is the last closed day |
| `fValue` | `REAL` |  | today's running total |
| `dtClock` | `DT` |  | local date and time, the clock the total rolls its day on |
| `tSaveEvery` | `TIME` | `T#1h` | how often today's total is written into anyDays; T#0s every call |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nDays` | `INT` |  | closed days held |
| `nSentCnt` | `UDINT` |  | day values sent since the program started |

WHY SPARKPLUG AND NOT PLAIN MQTT. Two things, and they are why a SCADA
system wants it.

A TOPIC IS A ONE-WAY PIPE, so a writable setpoint under plain MQTT needs two
of them, one to write and one to read back. Under Sparkplug the direction is
in the MESSAGE TYPE: the host writes SETPOINT with a command, the node
publishes SETPOINT with its data. One name, one member.

AND THE DATATYPE IS DECLARED. Every metric's type travels in the birth
certificate, so the far end is told REAL rather than guessing from the first
sample. A counter that started at zero is not filed as an integer.

WHAT IT COSTS. The metric set is CLOSED. The birth certificate carries every
metric the node will publish, and a write to an undeclared name is refused
rather than invented. So the methods are called from the first scan; one
first called later costs a rebirth.

sPrimaryHostId IS EMPTY BY DEFAULT, deliberately. Set it and this node
publishes NOTHING until that host announces itself online - right for a
system with one nominated master, and what stops a node shouting into a
broker nobody is reading. Empty, the node births as soon as it connects. A
node waiting for a host that does not exist looks exactly like a node that is
broken, so the default is the one that cannot be mistaken.

ONE CONNECTION, SHARED. This node is a layer on fbClient's session, not a
second connection. What Sparkplug needs of that session it takes on every
CONNECT: the Will is this node's NDEATH, so no stWillConfig on that client
(the birth and death certificates are the presence); the session is always
clean, whatever stSessionConfig says; and the transmit buffer grows to hold
the birth certificate. Started on a session already up, the node reconnects
it once so the next CONNECT carries the NDEATH. The same when the primary
host goes offline: Sparkplug requires a new session. One node per client: a
connection carries one Will.

ONE MESSAGE A SCAN. The methods do not send: each marks what moved and asks,
and this block, on its next scan, sends ONE NDATA - and one DDATA for each
online device with something to say - carrying everything that moved. Births,
deaths and History's events go when they happen.

ONE TASK. This block, its methods and fbClient run in the network task, and
the machine's program trades values with them through globals.

sGroupId, sEdgeNodeId AND sPrimaryHostId MAY CHANGE WHILE IT RUNS. The node
leaves under the old identity (the host sees the NDEATH) and births under the
new one with the next bdSeq; declarations and devices stay, so nothing else in
the program notices.

---

## Structures

Option structures are inputs of a block, set in the declaration or from an
HMI and read every scan. A member left at its default is the right answer
for most sites; `0` and `T#0s` mean the library's default.

### ST_MqttNetworkConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sSsid` | `STRING(48)` |  | E_MqttTransport.ArduinoWiFi: the network to join |
| `sWiFiPassword` | `STRING(64)` |  |  |
| `sMac` | `STRING(32)` |  | E_MqttTransport.ArduinoEthernet: the board's MAC, 'DE:AD:BE:EF:FE:ED' |
| `sIp` | `STRING(32)` |  | a fixed address; empty = DHCP |
| `sGateway` | `STRING(32)` |  |  |
| `sSubnet` | `STRING(32)` |  |  |

### ST_MqttSessionConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `tKeepAlive` | `TIME` |  | how often the client and the broker show they are there; T#0s = 60 s |
| `bCleanStart` | `BOOL` | `TRUE` | start a fresh session on every connection |
| `tSessionExpiry` | `TIME` |  | how long the broker keeps the session after a disconnect (MQTT 5); T#0s = not at all |
| `sUserName` | `STRING(64)` |  | the login; empty for none |
| `sUserPassword` | `STRING(64)` |  |  |
| `nMaxPending` | `DINT` |  | publishes and subscribes that may wait for the broker; 0 = the library's default |
| `nMaxMsgIn` | `DINT` |  | the largest message accepted, in bytes; 0 = the library's default |
| `nMaxMsgOut` | `DINT` |  | the largest message sent, in bytes; 0 = the library's default |
| `tReconnect` | `TIME` |  | the first wait before reconnecting; T#0s = the library's default |
| `tReconnectMax` | `TIME` |  | the longest wait between attempts; T#0s = the library's default |
| `tConnectTimeout` | `TIME` |  | how long one connection attempt may take; T#0s = the library's default |
| `tMaxSilence` | `TIME` |  | reconnect when nothing arrives for this long; T#0s = never |
| `bAutoReconnect` | `BOOL` | `TRUE` | reconnect by itself after a loss |
| `bRetryRejectedCredential` | `BOOL` |  | keep retrying a login the broker refused |

### ST_MqttTlsConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sCaFile` | `STRING(128)` |  | the certificate authority (Runtime: a file path); empty = the system's |
| `sCertFile` | `STRING(128)` |  | this client's certificate, for mutual TLS; empty for none |
| `sKeyFile` | `STRING(128)` |  | its private key |

### ST_MqttWillConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sTopic` | `STRING(128)` |  | where this device says it is online or gone; empty = no presence |
| `sOnline` | `STRING(128)` |  | sent on every connection |
| `sOffline` | `STRING(128)` |  | the Will: sent by the broker when this device is gone |
| `bRetain` | `BOOL` | `TRUE` | the broker keeps the last one for late subscribers |
| `eQos` | `E_MqttQos` |  |  |
| `tDelay` | `TIME` |  | MQTT 5: how long the broker waits before sending the Will |

### ST_SparkplugDay

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `dDay` | `DATE` |  | the day the total belongs to: the local date, from dtClock |
| `fTotal` | `REAL` |  | that day's total, in the units the total is kept in |

### ST_SparkplugReportConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `tLogInterval` | `TIME` | `T#15m` | the log class looks for what moved this often; at most T#15m, never T#0s |
| `tLiveInterval` | `TIME` | `T#30s` | the live class, and the log class while someone views |
| `fDeadbandPct` | `REAL` |  | the log class's deadband in % where a member gives no pct= |
| `bRemoteControl` | `BOOL` |  | the cmd and set classes take writes from the host |

## Enumerations

Used qualified: `E_MqttQos.AtLeastOnceDelivery`, `E_MqttResult.Ok`.

| Enumeration | Values, in order | Default |
| --- | --- | --- |
| `E_MqttBridgeState` | `Idle`, `Connecting`, `Up`, `Degraded` | `Idle` |
| `E_MqttDirection` | `Out`, `In`, `Both` | `Out` |
| `E_MqttProtocol` | `V5`, `V311`, `V5ThenV311` | `V5ThenV311` |
| `E_MqttQos` | `AtMostOnceDelivery`, `AtLeastOnceDelivery`, `ExactlyOnceDelivery` | `AtMostOnceDelivery` |
| `E_MqttQuality` | `Unknown`, `Bad`, `Uncertain`, `Good` | `Unknown` |
| `E_MqttResult` | `Queued`, `Ok`, `NotInitialised`, `InvalidArgument`, `InvalidTopic`, `NotConnected`, `QueueFull`, `Duplicate`, `Superseded`, `Cancelled`, `NotSupportedByProtocol`, `NotSupportedByPeer`, `PacketTooLarge`, `QuotaExceeded`, `NoPacketIdentifier`, `Refused`, `NoMatchingSubscribers`, `TopicNameInvalid`, `NotAuthorized`, `PayloadFormatInvalid`, `QuotaExceededByPeer`, `PacketIdentifierInUse`, `ConnectionLost`, `SessionLost`, `ConnectionRefused`, `ProtocolError`, `MalformedPacket`, `KeepAliveTimeout`, `AckTimeout`, `SessionTakenOver`, `WrongTask` | `Ok` |
| `E_MqttSecurity` | `Plain`, `TlsVerify`, `TlsPinned`, `TlsInsecure` | `Plain` |
| `E_MqttState` | `Idle`, `Connecting`, `AwaitingConnAck`, `Authenticating`, `Connected`, `Disconnecting`, `Reconnecting` | `Idle` |
| `E_MqttTransport` | `RuntimeTcp`, `ArduinoWiFi`, `ArduinoEthernet`, `Cellular`, `External` | `RuntimeTcp` |
| `E_MqttTrigger` | `OnChange`, `OnInterval`, `OnRequest`, `ChangedEvery` | `OnChange` |

[06 Diagnostics](06-diagnostics.md) explains every `E_MqttResult` value.

---

**Next:** [08 Patterns](08-patterns.md)
