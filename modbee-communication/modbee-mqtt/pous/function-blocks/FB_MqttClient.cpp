(* An MQTT client: one connection to one broker. Call it once every scan, in
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

---

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
from another thread. See docs/10-scan-rate.md. *)

FUNCTION_BLOCK FB_MqttClient
  VAR_INPUT
    eTransport : E_MqttTransport;    (* where the bytes go: RuntimeTcp, ArduinoWiFi, ArduinoEthernet, Cellular, External *)
    eSecurity : E_MqttSecurity;  (* Plain, TlsVerify, TlsPinned or TlsInsecure *)
    sHost : STRING(64);          (* the broker: a name or an address *)
    nPort : UINT;                (* 0 for the standard one: 1883 plain, 8883 TLS *)
    sClientId : STRING(48);      (* what the broker calls this device; unique on the broker *)
    eProtocol : E_MqttProtocol;  (* V5ThenV311 (default), V5 or V311 *)
    nExternalLink : __XWORD;     (* eTransport External: a transport another block made *)
    bConnect : BOOL := TRUE;     (* TRUE connects and stays connected; FALSE says goodbye *)
    bTrustNew : BOOL;            (* TlsPinned: learn the first key a broker shows; an edge forgets it *)
    stSessionConfig : ST_MqttSessionConfig;   (* keep-alive, session, login, queue and message sizes, reconnecting *)
    stTlsConfig : ST_MqttTlsConfig;           (* certificate authority and client certificate (Runtime) *)
    stNetworkConfig : ST_MqttNetworkConfig;   (* a board's Wi-Fi or Ethernet *)
    stWillConfig : ST_MqttWillConfig;         (* presence: online on connect, the Will when gone *)
  END_VAR
  VAR_OUTPUT
    bLinkUp : BOOL;              (* the client exists and its link is open *)
    bConnected : BOOL;           (* the broker has acknowledged us: the one to interlock on *)
    tHeardAgo : TIME;            (* since anything last arrived from the broker *)
    bSessionPresent : BOOL;      (* the broker had our session waiting *)
    sAssignedId : STRING(48);    (* the client identifier in force *)
    eConnectionState : E_MqttState;  (* where the connection is up to *)
    bError : BOOL;               (* something failed *)
    eErrorId : E_MqttResult;     (* why; Ok when fine *)
    sLastError : STRING(64);     (* why, in words *)
    sBrokerKey : STRING(64);     (* SHA-256 of the key the broker presented, hexadecimal *)
  END_VAR

  VAR RETAIN
    (* THE PIN, AND IT IS THE BLOCK'S OWN RETAINED VARIABLE - not a pin somebody
       has to wire, name or type.

       IEC 61131-3 6.5.6.2 allows RETAIN on a variable declared in a function
       block TYPE, and says that declaration overrides whatever the instance
       says - so a user cannot accidentally un-retain it, and there is nothing
       to get wrong. StruC++ implements exactly that: its debug table generator
       applies the flag per var block and lets NON_RETAIN clear it down a
       subtree.

       ONE STRING, AND IT IS FROZEN. A retained variable inside a library block
       joins the project's retain layout, so the layout hash covers it. If a
       later version of this library adds, removes or retypes a retained member,
       that hash changes and the WHOLE project's retained blob is refused -
       including the user's own setpoints. So this is one STRING, declared once,
       and treated as fixed ABI from here on.

       64 characters because that is a SHA-256 written in hexadecimal, and
       because a retained IEC STRING is a fixed 127 bytes whatever width it was
       declared - a value longer than that is truncated rather than refused. The
       PEM of the key itself is 178 characters and would have been silently cut
       in half. *)
    sPinnedKey : STRING(64);
  END_VAR
  VAR
    (* Whether sPinnedKey has been handed to the link. NOT retained: a fresh
       program start builds a fresh link and must hand it over again. *)
    bPinApplied : BOOL;
    (* bTrustNew as it was last scan, and whether there has BEEN a last scan.
       The rising edge is what forgets a stored key, and it must not fire at
       program start - a bTrustNew wired TRUE would otherwise forget the pin on
       every reboot, which is the one moment retaining it exists for. *)
    bLastTrust : BOOL;
    bTrustSeen : BOOL;
  END_VAR
  VAR
    nApi : __XWORD;
    nLink : __XWORD;
    bSettled : BOOL;
    bTried : BOOL;
    nRetryAt : DINT;
    bWanted : BOOL;
    bConnectAsked : BOOL;
    (* Written by Provision, when it is called: the login to connect
       with (its stored one, or "$provision" and the key), ahead of
       stSessionConfig's sUserName/sUserPassword; and whether the connection is only
       the key's, in which case bConnected stays FALSE - it is not this PLC
       yet. Not retained: Provision keeps its own, below. *)
    sProvUser : STRING(64);
    sProvPassword : STRING(127);
    bProvisioning : BOOL;
    (* SETTINGS AS THEY WERE WHEN THE LINK WAS BUILT, as two short
       fingerprints: what the medium is made from (eTransport, eSecurity, sHost,
       nPort, the TLS files, the board's network settings) and what the bConnect
       says (sClientId, eProtocol, the login, keepalive, session, Will). A change
       of either reconnects, the first on a rebuilt medium. Not retained: a
       program start builds from what the pins say anyway. *)
    nMediumKey : UDINT;
    nSessionKey : UDINT;
    nWiFiKeyHash : UDINT;
    bRelink : BOOL;
    bReconfigure : BOOL;
    nChangeAt : DINT;
    (* The task this block runs in, for its methods and the blocks given it:
       see ONE TASK in the comment above. *)
    nTask : __XWORD;
    (* The connection whose 'online' (stWillConfig) has gone. *)
    nWillConnects : DINT;
  END_VAR
  VAR RETAIN
    (* What Provision was given: this PLC's own login and the values its key
       hands its devices. Retained, so a power cut keeps them. *)
    sProvLoginUser : STRING(64);
    sProvLoginSecret : STRING(64);
    sProvGroup : STRING(64);
    sProvPrefix : STRING(127);
  END_VAR
  VAR
    (* The methods' state: their records, Provision's progress. *)
    nMethods : __XWORD;
  END_VAR


(* Sends anyValue to sTopic once, on a rising edge of bExecute. Inputs are
   taken at the edge. Returns E_MqttResult.Queued until the broker has it
   (QoS 1 and 2) or it has left (QoS 0), then E_MqttResult.Ok or the reason
   it failed, until the next edge. Not connected at the edge:
   E_MqttResult.NotConnected, nothing queued. *)
METHOD PUBLIC Publish : E_MqttResult
  VAR_INPUT
    anyValue : ANY;              (* what to send, as its declared type: 23.5, 42, true, text *)
    sTopic : STRING(128);        (* where it goes; no wildcards *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    bRetain : BOOL;              (* the broker keeps it for later subscribers *)
    bExecute : BOOL;             (* rising edge sends *)
  END_VAR
END_METHOD

(* Publishes anyValue on sTopic, called every scan. eTrigger says when:
   OnChange (moved by fDeadband, and every tPeriod anyway), OnInterval (every
   tPeriod, which must be set) or OnRequest (bExecute's rising edge).
   E_MqttResult.Ok while the record is valid. *)
METHOD PUBLIC Report : E_MqttResult
  VAR_INPUT
    anyValue : ANY;              (* the variable to report *)
    sTopic : STRING(128);        (* where it goes; no wildcards *)
    eTrigger : E_MqttTrigger;    (* OnChange (default), OnInterval or OnRequest *)
    fDeadband : LREAL;           (* OnChange: the least change worth a message; 0 = any change *)
    tPeriod : TIME;              (* OnChange: resend unchanged after this, T#0s never; OnInterval: the interval *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    bRetain : BOOL;              (* the broker keeps the last one for later subscribers *)
    bEnable : BOOL := TRUE;      (* FALSE stops reporting, keeping the record *)
    bExecute : BOOL;             (* OnRequest: rising edge sends *)
  END_VAR
  VAR_OUTPUT
    nSent : DINT;                (* messages sent for this record *)
    tAge : TIME;                 (* since the last one; T#0s before the first *)
  END_VAR
END_METHOD

(* Keeps anyValue up to date from sTopic, called every scan. A payload is read
   as anyValue's declared type; one that does not parse is counted on
   nMalformed and leaves anyValue alone. *)
METHOD PUBLIC Subscribe : E_MqttResult
  VAR_INPUT
    anyValue : ANY;              (* the variable kept up to date *)
    sTopic : STRING(128);        (* wildcards allowed *)
    eQos : E_MqttQos;            (* the most the broker may use *)
    tExpect : TIME;              (* how often a value is expected; drives eQuality. T#0s = no promise *)
    bEnable : BOOL := TRUE;      (* FALSE unsubscribes, keeping the record *)
  END_VAR
  VAR_OUTPUT
    bSubscribed : BOOL;          (* the subscription is in force *)
    eQuality : E_MqttQuality;    (* Unknown: never arrived; Bad: link down or twice overdue *)
    bSeen : BOOL;                (* a value has arrived for this record *)
    tAge : TIME;                 (* since the last accepted value *)
    nReceived : DINT;            (* values accepted *)
    nMalformed : DINT;           (* payloads that did not parse *)
    bNewValue : BOOL;            (* this call wrote anyValue *)
  END_VAR
END_METHOD

(* Publishes every member of the STRUCT anyData on sBase/<member>, called every
   scan. OnChange: a member when it changes, and every tPeriod anyway;
   OnInterval: the whole set every tPeriod; OnRequest: the whole set on
   bExecute's rising edge. A member the wire cannot carry is counted on
   nSkipped and returns E_MqttResult.InvalidArgument. *)
METHOD PUBLIC PublishStruct : E_MqttResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT *)
    sBase : STRING(128);         (* the topic the members hang off *)
    eTrigger : E_MqttTrigger;    (* OnChange (default), OnInterval or OnRequest *)
    tPeriod : TIME;              (* OnChange: resend unchanged after this; OnInterval: the interval *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    bRetain : BOOL;              (* the broker keeps the last one for later subscribers *)
    bEnable : BOOL := TRUE;      (* FALSE stops it, keeping the record *)
    bExecute : BOOL;             (* OnRequest: rising edge sends the set *)
  END_VAR
  VAR_OUTPUT
    nPoints : INT;               (* members published *)
    nSkipped : INT;              (* members refused *)
    nSent : DINT;                (* messages sent for this record *)
    nChanged : INT;              (* messages sent by this call *)
  END_VAR
END_METHOD

(* Keeps every member of the STRUCT anyData up to date from sBase/<member>,
   called every scan. eQuality is the worst member's, tOldest the oldest
   member's age. *)
METHOD PUBLIC SubscribeStruct : E_MqttResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT *)
    sBase : STRING(128);         (* the topic the members hang off *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    tExpect : TIME;              (* how often a value is expected; drives eQuality. T#0s = no promise *)
    bEnable : BOOL := TRUE;      (* FALSE stops it, keeping the record *)
  END_VAR
  VAR_OUTPUT
    nPoints : INT;               (* members bound *)
    nSkipped : INT;              (* members refused *)
    bSubscribed : BOOL;          (* the subscription is in force *)
    eQuality : E_MqttQuality;    (* the worst member's quality *)
    bSeen : BOOL;                (* every member has had a value *)
    tOldest : TIME;              (* the oldest member's age *)
    nReceived : DINT;            (* values accepted *)
    nMalformed : DINT;           (* payloads that did not parse *)
    nNewValues : INT;            (* members written by this call *)
  END_VAR
END_METHOD

(* Asks a question on sTopic and waits for the answer on sReplyTopic, MQTT 5
   only. The request carries Response Topic and Correlation Data. Rising edge
   of bExecute starts it; E_MqttResult.Queued until the answer
   (E_MqttResult.Ok, in sReply) or tTimeout (E_MqttResult.KeepAliveTimeout). *)
METHOD PUBLIC Request : E_MqttResult
  VAR_INPUT
    anyValue : ANY;              (* the question *)
    sTopic : STRING(128);        (* where it goes *)
    sReplyTopic : STRING(128);   (* where the answer comes back; one per requester *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    tTimeout : TIME;             (* T#0s = 5 s *)
    bExecute : BOOL;             (* rising edge starts it *)
  END_VAR
  VAR_OUTPUT
    sReply : STRING(254);        (* the answer's text *)
    nReplyLen : INT;             (* characters in sReply *)
  END_VAR
END_METHOD

(* Answers MQTT 5 requests arriving on sTopic, called every scan. A request's
   payload is written into anyRequest; a rising edge of bExecute sends
   anyReply to the last request's Response Topic with its Correlation Data. *)
METHOD PUBLIC Response : E_MqttResult
  VAR_INPUT
    anyRequest : ANY;            (* the request, read as its declared type *)
    sTopic : STRING(128);        (* where requests arrive; wildcards allowed *)
    anyReply : ANY;              (* the answer *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    bEnable : BOOL := TRUE;      (* FALSE unsubscribes, keeping the record *)
    bExecute : BOOL;             (* rising edge answers *)
  END_VAR
  VAR_OUTPUT
    bNewRequest : BOOL;          (* this call took a request *)
    bAwaitingReply : BOOL;       (* the last request has a Response Topic and is not answered yet *)
    sResponseTopic : STRING(128); (* where the last request asked its answer to go *)
    nReceived : DINT;            (* requests received *)
    nMalformed : DINT;           (* payloads that did not parse *)
  END_VAR
END_METHOD

(* The text of whatever arrives on sTopic, written into the STRING variable
   anyPayload, one message per call. Called every scan. *)
METHOD PUBLIC Message : E_MqttResult
  VAR_INPUT
    anyPayload : ANY;            (* a STRING variable *)
    sTopic : STRING(128);        (* wildcards allowed *)
    eQos : E_MqttQos;            (* AtMostOnceDelivery (default), AtLeastOnceDelivery, ExactlyOnceDelivery *)
    bEnable : BOOL := TRUE;      (* FALSE stops it, keeping the record *)
  END_VAR
  VAR_OUTPUT
    nLen : INT;                  (* characters written *)
    bTruncated : BOOL;           (* the message was longer than anyPayload or the client's buffer *)
    nReceived : DINT;            (* messages received *)
    bNewMessage : BOOL;          (* this call wrote anyPayload *)
  END_VAR
END_METHOD

(* Registers this PLC with a modbee broker using a provisioning key, and keeps
   the login it is given (retained). sClientId is the PLC's name. Called every
   scan, before the client's own call on the first scan. *)
METHOD PUBLIC Provision : E_MqttResult
  VAR_INPUT
    sKey : STRING(127);          (* from `modbee key create` on the broker *)
    bForget : BOOL;              (* rising edge forgets the stored login *)
  END_VAR
  VAR_OUTPUT
    bProvisioned : BOOL;         (* connected with this PLC's own login *)
    bPending : BOOL;             (* waiting for approval on the broker *)
    bRefused : BOOL;             (* the broker said no; sReason says why *)
    sUserName : STRING(64);      (* the login the key handed this PLC *)
    sGroup : STRING(64);         (* the Sparkplug group the key hands its devices *)
    sPrefix : STRING(127);       (* the topic prefix the key hands its devices *)
    sReason : STRING(64);        (* why the broker refused, when bRefused *)
  END_VAR
END_METHOD

(* The connection's counters. *)
METHOD PUBLIC Statistics : E_MqttResult
  VAR_OUTPUT
    nVersion : BYTE;             (* 5 or 4: the protocol in force *)
    nConnects : DINT;            (* connections made *)
    nDisconnects : DINT;         (* connections ended *)
    nReconnects : DINT;          (* reconnections after a loss *)
    nPublished : DINT;           (* messages published *)
    nReceived : DINT;            (* messages received *)
    nPublishFailures : DINT;     (* publishes that failed *)
    nProtocolErrors : DINT;      (* broker packets the standard does not allow *)
    nPending : DINT;             (* operations accepted and not yet concluded *)
    nReasonCode : BYTE;          (* the last reason code from the broker, read with nVersion *)
  END_VAR
END_METHOD

// THE TLS ENGINE, INCLUDED PLAINLY AND ON PURPOSE. Read the Ethernet note
// further down before changing this - it is the same trap, and this is the
// same answer.
//
// src/MqttFeatures.h decides whether TLS is compiled at all by asking
// __has_include(<wolfssl/ssl.h>). On the Runtime that works: the build puts
// every resource library's src/ on the include path, so the question has an
// answer before it is asked. On Arduino it CANNOT work on its own -
// arduino-cli adds a library to the include path only when its dependency
// scanner sees a PLAIN #include for it, and a header behind __has_include is
// invisible to that scanner. Without this, wolfSSL sits inside the .stlib,
// fully vendored, completely unreachable, and eSecurity := E_MqttSecurity.TlsVerify
// reports "this build has no TLS" on a board for ever.
//
// Measured rather than reasoned about: with the engine on the include path a
// board TU resolves MQTT_TLS_ENGINE_NAME to "wolfSSL", and without it to
// "none".
//
// depends=wolfssl in library.properties is the documented alternative and it
// does NOT work here. It makes arduino-cli's --only-compilation-database run
// fail outright, and the editor's pre-compile pass then gets no library
// include paths AT ALL - not merely wolfSSL's, every one of them, so even
// ModBeeMqtt.h stops resolving. Also measured.
//
// So the include is plain, and it comes FIRST, before <ModBeeMqtt.h>: the
// scanner meets a header it cannot find, resolves it to the vendored wolfssl
// library, adds that library's src/ and compiles again - and by the time
// MqttFeatures.h asks its question, the answer is yes.
//
// AND IT IS <modbee-wolfssl.h>, which is ours and sits at the top level of the
// vendored engine's src/ - arduino-cli matches an include against that top
// level, not against a path inside it, so <wolfssl/ssl.h> names nothing it can
// resolve.
//
// NOT upstream's <wolfssl.h>, even though it is also top-level: that one pulls
// <wolfssl/ssl.h> and with it the whole OpenSSL compatibility layer, which
// typedefs SHA_CTX - and so does the ESP32 ROM header this very file reaches
// through WiFiClientSecure. The two are different types and the translation
// unit will not compile. Ours brings in the configuration and nothing else,
// which is all the dependency scanner needs. The long version is in
// resources/wolfssl/modbee-wolfssl.h.
#if defined(ARDUINO)
  #include <modbee-wolfssl.h>
#endif

#include <ModBeeMqtt.h>
#include <string>
#include <vector>
#include <new>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <strings.h>

// The task a block runs in. Every method of this client runs in the task its
// own call is in, and is refused anywhere else (one task per client).
#if defined(MQTT_PLATFORM_HOST)
#include <pthread.h>
strucpp::XWORD_t mq_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#elif defined(ESP_PLATFORM)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
strucpp::XWORD_t mq_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#else
strucpp::XWORD_t mq_currentTask() { return 1; }
#endif
bool mq_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == mq_currentTask();
}

#if defined(MQTT_PLATFORM_ARDUINO)
  #include <Arduino.h>
  #if __has_include(<WiFi.h>) && !defined(MQTT_NO_WIFI)
    #include <WiFi.h>
    // TLS ON A BOARD IS THE LIBRARY'S, NOT THE MEDIUM'S, wherever the core
    // carries mbedTLS (every ESP32: MQTT_CHANNEL_TLS). WiFiClientSecure is
    // only the fallback for a board without it, and only then included.
    #if !MQTT_CHANNEL_TLS
      #include <WiFiClientSecure.h>
    #endif
    #define MQ_HAS_WIFI 1
  #endif
  // ETHERNET HAS TO BE ASKED FOR, and the reason is worth knowing because it
  // is not obvious and the sibling library paid for it.
  //
  // WiFi.h ships inside the ESP32 core, so it is on the include path already
  // and __has_include finds it. The Arduino Ethernet library is a USER
  // library, and arduino-cli puts one on the include path only when its
  // dependency scanner sees a plain #include for it. A header hidden behind
  // __has_include is invisible to that scanner - so the library can be
  // installed, the guard still says it is not, and the Ethernet link reports
  // "install the Arduino Ethernet library" for ever.
  //
  // So Ethernet is opt-in: define MQTT_ENABLE_ETHERNET in the board package's
  // compiler flags (an OpenPLC project has none of its own) and the plain
  // include below is what makes it resolvable.
  #if defined(MQTT_ENABLE_ETHERNET)
    #include <Ethernet.h>
    #define MQ_HAS_ETHERNET 1
  #endif

  // CELLULAR SWITCHES ON BY ITSELF when the modbee-gsm library is in the
  // project - an OpenPLC project cannot pass build flags, so Ethernet's
  // opt-in is not available to it. The Ethernet trap above does not apply:
  // every modbee-gsm block includes <ModBeeGsmPlc.h> PLAINLY, and a
  // project's blocks are one translation unit, so the dependency scanner
  // has already put the library on the include path when this asks. No
  // modbee-gsm block, no modem - and E_MQTTTRANSPORT::CELLULAR says so on its pins.
  //
  // GsmPlcClient IS a GsmClient, an Arduino Client like WiFiClient. It only
  // takes modbee-gsm's lock around each call, because GSM_MODEM may be
  // polling the same modem from another task.
  #if __has_include(<ModBeeGsmPlc.h>)
    #include <ModBeeGsmPlc.h>
  #endif
  #if defined(MODBEE_GSM_PLC_CLIENT)
    #define MQ_HAS_CELLULAR 1
  #endif
#endif

// Every client this program made, so they can be closed when it is unloaded.
//
// The OpenPLC Runtime swaps a new program into the SAME process rather than
// restarting it, and a socket is owned by the process, not by the shared
// object. A client that simply leaked its client would leave a TCP connection
// open and a broker holding a session for a client that is never coming back -
// and on the broker role, a listening socket on a port nothing appears to be
// using.
//
// A static destructor is the one hook a POU has: it runs when the program is
// unloaded and at process exit, which is exactly when these must go.
//
// The sibling BeeBus library does not do this and should. It is not optional.

namespace {

// One medium, owned whole. The channel, the transport over it and the host
// string all have the same lifetime, and MqttStreamTransport keeps the host as
// a POINTER - so the string has to outlive the transport or a reconnect reads
// freed memory at the worst possible moment.
struct MqLink {
    std::string host;
    virtual ~MqLink() = default;
    virtual MqttTransport& transport() = 0;
    virtual const char* why() const { return ""; }

    // The SHA-256 of the broker's public key, once the handshake has
    // completed. Empty on a link that is not encrypted - and on a board
    // without the core's mbedTLS, whose WiFiClientSecure does not hand the
    // peer's certificate back.
    virtual const char* peerKey() const { return ""; }

    // Pin this fingerprint from the NEXT handshake onwards.
    //
    // WHY THIS HAS TO EXIST AT ALL. Trust on first use configures the link
    // with NO pin - there is nothing to pin yet - reads the broker's key off
    // that first connection and stores it in sPinnedKey. But the link is
    // built ONCE, so without this nothing ever tells it, and it keeps its
    // commissioning configuration for the life of the program: a broker
    // reinstalled with a different key and a different CA is accepted without
    // complaint. The stored pin only started protecting anything after the
    // PLC restarted, when it is present at build time - which on a controller
    // can be months.
    //
    // Found by reinstalling a broker mid-run and watching the PLCs stay
    // connected. MqttClient::serviceReconnect() calls the transport's begin()
    // on every reconnect and that re-reads the pin, and the post-handshake
    // comparison is inside `if (pinning())` and does not depend on _validate -
    // so setting it here is enough for the next handshake to enforce it.
    //
    // A no-op on a link that cannot pin, which is the honest answer: the
    // fallback WiFiClientSecure (a board without the core's mbedTLS) is given
    // its trust at construction and has nothing to compare afterwards.
    virtual void pinKey(const char* fingerprint) { (void)fingerprint; }

    // Forget the pin and accept whatever the next handshake shows, so it can
    // be learned. What bTrustNew's rising edge does when a broker has been
    // replaced on purpose. BOTH halves are needed: a link that was built with
    // a stored pin was never told to skip chain verification, so dropping only
    // the pin would leave it verifying against a system store that has never
    // heard of this broker.
    virtual void forgetKey() {}

    // --- THE bConnect, OUTSIDE THE SCAN (an ESP32: MqttConnectTask) ---
    //
    // The client is given clientTransport(), not transport(). On a board with
    // threads that is a connect task wrapped round the medium: Client::
    // connect() and the TLS handshake run on a task of their own, and this
    // block's scan never waits for a network - it reads CONNECTING meanwhile,
    // and CONNECT_TIMEOUT and the reconnect backoff are the client's as
    // before. Without threads it is the medium itself, opened inside the scan
    // as it always was.
    //
    // While an attempt runs the task owns the medium, and nothing here may
    // touch it. So the pins read the link through the calls below: no key and
    // no reason while an attempt is under way - which is what a medium says
    // the moment it starts one - and a pin or a forget asked for meanwhile is
    // kept and applied by settle() before the next attempt.
#if MQTT_CONNECT_TASK
    MqttConnectTask connector;
    virtual MqttTransport& clientTransport() {
        connector.wrap(transport());
        return connector;
    }
    bool busy() const { return connector.busy(); }
    const char* refusal() const { return connector.lastError(); }
#else
    virtual MqttTransport& clientTransport() { return transport(); }
    bool busy() const { return false; }
    const char* refusal() const { return ""; }
#endif

    const char* seenKey() const { return busy() ? "" : peerKey(); }
    const char* reason() const {
        if (busy()) return "";
        return *refusal() != '\0' ? refusal() : why();
    }
    void pin(const char* fingerprint) {
        if (fingerprint == nullptr) return;
        if (!busy()) { pinKey(fingerprint); return; }
        owedPin = fingerprint;
        owed |= kOwedPin;
    }
    void forget() {
        if (!busy()) { forgetKey(); return; }
        owedPin.clear();
        owed = kOwedForget;   // a pin asked for before it is forgotten too
    }
    // Once a scan, before the client is polled: so a change of trust held
    // while the task had the medium reaches it before the next attempt does.
    void settle() {
        if (owed == 0 || busy()) return;
        if (owed & kOwedForget) forgetKey();
        if (owed & kOwedPin) pinKey(owedPin.c_str());
        owed = 0;
        owedPin.clear();
    }

private:
    static const uint8_t kOwedPin = 1;
    static const uint8_t kOwedForget = 2;
    uint8_t owed = 0;
    std::string owedPin;
};

#if defined(MQTT_PLATFORM_HOST)

struct MqTcpLink : MqLink {
    MqttTcpTransport tcp;
    MqttTransport& transport() override { return tcp; }
    const char* why() const override { return tcp.lastError().c_str(); }
};

#if MQTT_TLS_SOCKETS
struct MqTlsLink : MqLink {
    MqttTlsTransport tls;
    MqttTransport& transport() override { return tls; }
    const char* why() const override { return tls.lastError().c_str(); }
    const char* peerKey() const override { return tls.peerKeyFingerprint().c_str(); }
    void pinKey(const char* fingerprint) override {
        if (fingerprint != nullptr) tls.setPinnedKeyFingerprint(fingerprint);
    }
    void forgetKey() override {
        tls.setPinnedKeyFingerprint("");
        tls.setInsecureNoCertificateValidation();
    }
};
#endif

#else  // Arduino

#if defined(MQ_HAS_WIFI)
struct MqWifiLink : MqLink {
    WiFiClient channel;
    MqttStreamTransport<WiFiClient> stream;
    MqWifiLink() : stream(channel) {}
    MqttTransport& transport() override { return stream; }
};
#if !MQTT_CHANNEL_TLS
struct MqWifiTlsLink : MqLink {
    WiFiClientSecure channel;
    MqttStreamTransport<WiFiClientSecure> stream;
    MqWifiTlsLink() : stream(channel) {
#if MQTT_CONNECT_TASK
        connector.stackBytes(MQTT_CONNECT_TLS_STACK);   // the handshake runs on it
#endif
    }
    MqttTransport& transport() override { return stream; }
};
#endif
#endif

#if defined(MQ_HAS_ETHERNET)
struct MqEthernetLink : MqLink {
    EthernetClient channel;
    MqttStreamTransport<EthernetClient> stream;
    MqEthernetLink() : stream(channel) {}
    MqttTransport& transport() override { return stream; }
};
#endif

#if defined(MQ_HAS_CELLULAR)
// The modem GSM_MODEM runs. Plain, or - on a board without the core's mbedTLS
// - the module's own TLS, so the channel is told which it is rather than being
// a second type.
struct MqCellularLink : MqLink {
    GsmPlcClient channel;
    MqttStreamTransport<GsmPlcClient> stream;
    explicit MqCellularLink(GsmSecurity security) : channel(security), stream(channel) {
#if MQTT_CONNECT_TASK
        // The modem's AT exchange runs on it, and its depth was not measured:
        // the handshake's size, which only exists while an attempt runs.
        connector.stackBytes(MQTT_CONNECT_TLS_STACK);
#endif
    }
    MqttTransport& transport() override { return stream; }
    const char* why() const override { return channel.why(); }
};
#endif

#if MQTT_CHANNEL_TLS
// --- TLS ON A BOARD: ONE LINK FOR EVERY MEDIUM ---
//
// The channel is PLAIN - WiFiClient, EthernetClient, the modem's GsmPlcClient
// opened without the module's TLS - and the TLS is done on the controller by
// MqttChannelTlsTransport, with the mbedTLS the ESP32 core already links. So
// Wi-Fi, Ethernet and cellular check the broker the same way and can do
// everything the Runtime's MqTlsLink can: verify by CA, pin a key, learn one
// (bTrustNew), report it (sBrokerKey), and present a certificate.
//
// It replaces three things that each did less: WiFiClientSecure (could not
// pin, never reported the key), nothing at all over Ethernet (it needed
// SSLClient), and the modem's own TLS (encrypted and checked nothing). The
// modem's TLS is still there in modbee-gsm and is deliberately NOT used here,
// for E_MQTTSECURITY::TLSINSECURE included: one engine on every medium is the point,
// and the handshake then runs on the connect task (MqLink::clientTransport())
// instead of inside the modem's blocking connect.

// The channel's own reason, where it has one: the modem says whether it was
// registered at all, which beats "cannot connect" every time.
template <typename ChannelType>
const char* mq_channelWhy(const ChannelType&) { return ""; }
#if defined(MQ_HAS_CELLULAR)
inline const char* mq_channelWhy(const GsmPlcClient& channel) { return channel.why(); }
#endif

template <typename ChannelType>
struct MqChannelTlsLink : MqLink {
    ChannelType channel;
    MqttChannelTlsTransport<ChannelType> tls;
    MqChannelTlsLink() : tls(channel) { onTask(); }
    template <typename Argument>
    explicit MqChannelTlsLink(Argument argument) : channel(argument), tls(channel) { onTask(); }
    void onTask() {
#if MQTT_CONNECT_TASK
        connector.stackBytes(MQTT_CONNECT_TLS_STACK);   // the handshake runs on it
#endif
    }

    MqttTransport& transport() override { return tls; }
    const char* why() const override {
        const char* engine = tls.lastError();
        const char* medium = mq_channelWhy(channel);
        const bool dialFailed = tls.lastErrorCode() == MqttTlsError::Unreachable;
        if (*engine != '\0' && !(dialFailed && *medium != '\0')) return engine;
        return medium;
    }
    const char* peerKey() const override { return tls.peerKeyFingerprint(); }
    void pinKey(const char* fingerprint) override {
        if (fingerprint != nullptr) tls.setPinnedKeyFingerprint(fingerprint);
    }
    void forgetKey() override {
        tls.setPinnedKeyFingerprint("");
        tls.setInsecureNoCertificateValidation();
    }
};
#endif

#endif

// A transport another block made. The wrapper is ours; the transport is not.
//
// NOT GIVEN TO THE bConnect TASK. It is another block's, which may be using it
// from its own scan, so only that block knows whether another thread may call
// it; it opens the way its maker wrote it.
struct MqExternalLink : MqLink {
    MqttTransport* borrowed = nullptr;
    MqttTransport& transport() override { return *borrowed; }
    MqttTransport& clientTransport() override { return *borrowed; }
};

// Frees a link now - or, while its connect task still has the medium, hands it
// to the task, which frees it when the connect returns. Never a wait.
#if MQTT_CONNECT_TASK
void mq_freeLink(void* link) { delete (MqLink*)link; }
#endif
void mq_dropLink(MqLink* link) {
    if (link == nullptr) return;
#if MQTT_CONNECT_TASK
    if (link->connector.retire(&mq_freeLink, link)) return;
#endif
    delete link;
}

struct MqNode {
    MqttClient client;
    MqLink* link = nullptr;
    ~MqNode() {
        client.end();
        mq_dropLink(link);
    }
};

}  // namespace

// --- A BOARD'S MEDIUM, FROM A eTransport AND A eSecurity CHOICE ---
//
// FB_MqttClient builds its link here - the one block with a eTransport pin, now
// that FB_SparkplugNode and FB_SparkplugHost ride on its connection - so what a
// board can honour is decided in ONE place.
// The rules are the ones the client block has always had, and they are about
// honesty: a eSecurity pin that promises a certificate check is refused where
// the medium cannot do one, never quietly downgraded.
//
// ON AN ESP32 EVERY MEDIUM CAN DO EVERY CHECK. The TLS is the library's
// (MqChannelTlsLink above), so Wi-Fi, Ethernet and cellular honour
// E_MQTTSECURITY::TLSVERIFY, E_MQTTSECURITY::TLSPINNED and E_MQTTSECURITY::TLSINSECURE alike, with the
// trust the Runtime uses: the CA from MQTT_CA_CERT_PEM, the pin from the
// block's stored key, and the rule that PINNED with nothing stored needs
// bTrustNew. The refusals below the #else are for a board WITHOUT the core's
// mbedTLS, which still has only what its medium offers.
//
// It builds the link and nothing else. Bringing the medium up is not its job:
// the Wi-Fi radio is joined by NETWORK (node-uio) or stNetworkConfig, Ethernet is
// begun by FB_MqttClient from stNetworkConfig's MAC, and the modem is GSM_MODEM's.
//
// Null with *status and *why set when it refuses, or when the heap is
// exhausted - an Arduino core builds without exceptions, so that has to be an
// answer rather than a fault.
//
// Static: FB_MqttClient is the only block that opens a connection.
#if !defined(MQTT_PLATFORM_HOST)

#if MQTT_CHANNEL_TLS
// A BOARD'S OWN CERTIFICATE, for a broker that wants one, comes from the same
// place as its CA and for the same reason: a PEM does not fit an IEC STRING,
// and a certificate is firmware. stTlsConfig's sCertFile and sKeyFile stay the
// Runtime's - they are paths, and a board has no files.
#if defined(MQTT_CLIENT_CERT_PEM) != defined(MQTT_CLIENT_KEY_PEM)
#error "mutual TLS on a board needs both MQTT_CLIENT_CERT_PEM and MQTT_CLIENT_KEY_PEM"
#endif

// The trust a TLS link is built with - the Runtime's rules, a board's sources.
template <typename ChannelType>
static MqLink* mq_trustedLink(MqChannelTlsLink<ChannelType>* made,
                              E_MQTTSECURITY security, const char* host,
                              uint16_t port, const char* pinnedKey,
                              bool trustNew, E_MQTTRESULT* status,
                              const char** why) {
    if (made == nullptr) {
        *status = E_MQTTRESULT::NOTINITIALISED;
        *why = "out of memory";
        return nullptr;
    }
    if (security == E_MQTTSECURITY::TLSINSECURE) {
        made->tls.setInsecureNoCertificateValidation();
    } else if (security == E_MQTTSECURITY::TLSPINNED) {
        // PINNING TRUSTS ONE KEY INSTEAD OF AN AUTHORITY - a ModBee PLC broker
        // or a site's own Mosquitto - and skips chain, name and dates, as the
        // Runtime does. Nothing stored and nobody commissioning is refused
        // rather than connected unchecked: a pinned link that silently trusts
        // anybody is a pinned link in name only.
        if (pinnedKey != nullptr && *pinnedKey != '\0') {
            made->tls.setPinnedKeyFingerprint(pinnedKey);
        } else if (!trustNew) {
            delete made;
            *status = E_MQTTRESULT::NOTAUTHORIZED;
            *why = "no pinned key yet - set bTrustNew once to learn it";
            return nullptr;
        } else {
            // Trust on first use: up unvalidated exactly once, so the key can
            // be read and stored; from then on the stored key is enforced.
            made->tls.setInsecureNoCertificateValidation();
        }
    } else {
        // A BOARD'S CA COMES FROM A BUILD FLAG, not a pin: an IEC STRING stops
        // at 254 characters and the shortest real PEM is about eight times
        // that. A certificate is firmware anyway - it belongs with the build,
        // not with the program somebody edits on a Tuesday.
#if defined(MQTT_CA_CERT_PEM)
        made->tls.setCaCertificate(MQTT_CA_CERT_PEM);
#else
        delete made;
        *status = E_MQTTRESULT::INVALIDARGUMENT;
        *why = "a board needs the CA in MQTT_CA_CERT_PEM";
        return nullptr;
#endif
    }
#if defined(MQTT_CLIENT_CERT_PEM)
    made->tls.setClientCertificate(MQTT_CLIENT_CERT_PEM, MQTT_CLIENT_KEY_PEM);
#endif
    made->host = host;
    made->tls.configure(made->host.c_str(), port);
    return made;
}
#endif  // MQTT_CHANNEL_TLS

static MqLink* mq_boardLink(E_MQTTTRANSPORT link, E_MQTTSECURITY security,
                            const char* host, uint16_t port,
                            int32_t connectTimeoutMs, const char* pinnedKey,
                            bool trustNew, E_MQTTRESULT* status,
                            const char** why) {
    const bool wantsTls = (security != E_MQTTSECURITY::PLAIN);
    *status = E_MQTTRESULT::OK;
    *why = "";
    (void)port;
    (void)connectTimeoutMs;
    (void)wantsTls;
    (void)pinnedKey;
    (void)trustNew;

    if (link == E_MQTTTRANSPORT::ARDUINOWIFI) {
#if defined(MQ_HAS_WIFI)
        if (!wantsTls) {
            MqWifiLink* w = new (std::nothrow) MqWifiLink();
            if (w) {
                w->host = host;
                w->stream.target(w->host.c_str(), port);
                return w;
            }
        } else {
#if MQTT_CHANNEL_TLS
            return mq_trustedLink(new (std::nothrow) MqChannelTlsLink<WiFiClient>(),
                                  security, host, port, pinnedKey, trustNew,
                                  status, why);
#else
            // A board without the core's mbedTLS: WiFiClientSecure, and only
            // what it can do.
            //
            // THE eSecurity PIN DECIDES, AND IT DID NOT USED TO. This chose
            // between setCACert() and setInsecure() with #if
            // defined(MQTT_CA_CERT_PEM) - the PREPROCESSOR - so a board built
            // with a CA silently upgraded E_MQTTSECURITY::TLSINSECURE to a verified
            // connection, and one built without it silently downgraded
            // E_MQTTSECURITY::TLSVERIFY to an unverified one.
            if (security == E_MQTTSECURITY::TLSPINNED) {
                // WiFiClientSecure has no key-pinning call - setCACert,
                // setInsecure and a pre-shared key are the whole surface.
                *status = E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL;
                *why = "E_MQTTSECURITY::TLSPINNED needs an ESP32 or the Runtime";
                return nullptr;
            }
#if !defined(MQTT_CA_CERT_PEM)
            if (security != E_MQTTSECURITY::TLSINSECURE) {
                *status = E_MQTTRESULT::INVALIDARGUMENT;
                *why = "a board needs the CA in MQTT_CA_CERT_PEM";
                return nullptr;
            }
#endif
            MqWifiTlsLink* w = new (std::nothrow) MqWifiTlsLink();
            if (w) {
                w->host = host;
                if (security == E_MQTTSECURITY::TLSINSECURE) {
                    w->channel.setInsecure();
                } else {
#if defined(MQTT_CA_CERT_PEM)
                    w->channel.setCACert(MQTT_CA_CERT_PEM);
#else
                    // Unreachable: the guard above already refused. Here so
                    // the branch cannot rot into the old behaviour.
                    w->channel.setInsecure();
#endif
                }
                w->stream.target(w->host.c_str(), port);
                return w;
            }
#endif
        }
        *status = E_MQTTRESULT::NOTINITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = E_MQTTRESULT::INVALIDARGUMENT;
        *why = "this board has no WiFi";
        return nullptr;
#endif
    }

    if (link == E_MQTTTRANSPORT::ARDUINOETHERNET) {
#if defined(MQ_HAS_ETHERNET)
        if (wantsTls) {
#if MQTT_CHANNEL_TLS
            // TLS OVER ETHERNET, which used to need SSLClient: the Ethernet
            // chip has no TLS, and now it does not need one.
            return mq_trustedLink(new (std::nothrow) MqChannelTlsLink<EthernetClient>(),
                                  security, host, port, pinnedKey, trustNew,
                                  status, why);
#else
            *status = E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL;
            *why = "TLS over Ethernet needs an ESP32, or SSLClient; use external";
            return nullptr;
#endif
        }
        MqEthernetLink* e = new (std::nothrow) MqEthernetLink();
        if (e) {
            e->host = host;
            e->stream.target(e->host.c_str(), port);
            return e;
        }
        *status = E_MQTTRESULT::NOTINITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = E_MQTTRESULT::INVALIDARGUMENT;
        *why = "define MQTT_ENABLE_ETHERNET to use Ethernet";
        return nullptr;
#endif
    }

    if (link == E_MQTTTRANSPORT::CELLULAR) {
#if defined(MQ_HAS_CELLULAR)
        // Opening blocks - Arduino's Client::connect() must return a verdict -
        // so it is bounded: by the caller's limit, 20 s unset. It blocks the
        // connect task, not the scan (MqLink::clientTransport()).
        const int connectSeconds =
            connectTimeoutMs > 0 ? (int)((connectTimeoutMs + 999) / 1000) : 20;
#if MQTT_CHANNEL_TLS
        if (wantsTls) {
            // A PLAIN socket on the modem, and the TLS on the controller.
            MqChannelTlsLink<GsmPlcClient>* t =
                new (std::nothrow) MqChannelTlsLink<GsmPlcClient>(GsmSecurity::Plain);
            if (t) t->channel.setConnectSeconds(connectSeconds);
            return mq_trustedLink(t, security, host, port, pinnedKey, trustNew,
                                  status, why);
        }
#else
        // THE MODULE DOES THE TLS, AND IT CHECKS NOTHING: no CA is loaded into
        // it, so it encrypts to whoever answers. That is exactly
        // E_MQTTSECURITY::TLSINSECURE and nothing more, so the two pins that promise a
        // check are refused rather than quietly downgraded - the same rule the
        // WiFi link follows.
        if (security == E_MQTTSECURITY::TLSVERIFY ||
            security == E_MQTTSECURITY::TLSPINNED) {
            *status = E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL;
            *why = "the modem's TLS checks no certificate; use E_MQTTSECURITY::TLSINSECURE";
            return nullptr;
        }
#endif
        MqCellularLink* c = new (std::nothrow) MqCellularLink(
            wantsTls ? GsmSecurity::Module : GsmSecurity::Plain);
        if (c) {
            c->host = host;
            c->stream.target(c->host.c_str(), port);
            c->channel.setConnectSeconds(connectSeconds);
            return c;
        }
        *status = E_MQTTRESULT::NOTINITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = E_MQTTRESULT::INVALIDARGUMENT;
        *why = "E_MqttTransport.Cellular needs a modbee-gsm modem block";
        return nullptr;
#endif
    }

    if (link == E_MQTTTRANSPORT::RUNTIMETCP) {
        *status = E_MQTTRESULT::INVALIDARGUMENT;
        *why = "that transport needs the Runtime, not a board";
        return nullptr;
    }

    // Anything added later. Said plainly rather than silently doing nothing.
    *status = E_MQTTRESULT::INVALIDARGUMENT;
    *why = "this board has no such transport";
    return nullptr;
}
#endif

void mq_dropMethods();

namespace {
// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqNodesOwned {
    std::vector<MqNode*> all;
    ~MqNodesOwned() {
        mq_dropMethods();   // first: their hooks hang on these clients
        for (size_t i = 0; i < all.size(); i++) delete all[i];
    }
};
MqNodesOwned& mqNodesOwned() {
    static MqNodesOwned owned;
    return owned;
}
}  // namespace

// How long to wait before trying a failed open again. A refused connection
// fails in microseconds, and a 1 ms task retrying that every scan is a
// thousand identical failures a second in the log.
#define MQ_REOPEN_MS 2000

// E_MQTTRESULT mirrors MqttResult member for member, so every block casts
// rather than translates. Asserted here because every project has a client, and
// a member added on one side without the other is a wrong reason code on an
// operator's screen rather than a build error.
static_assert((int)E_MQTTRESULT::SESSIONTAKENOVER + 1 == MQ_RESULT_COUNT,
              "E_MQTTRESULT must mirror MqttResult member for member");
static_assert((int)E_MQTTRESULT::QUEUED == (int)MqttResult::Queued &&
              (int)E_MQTTRESULT::OK == (int)MqttResult::Ok &&
              (int)E_MQTTRESULT::CONNECTIONLOST == (int)MqttResult::ConnectionLost,
              "E_MQTTRESULT must mirror MqttResult member for member");

// The same for the enumerations the blocks cast rather than translate.
static_assert((int)E_MQTTSTATE::IDLE == (int)MqttState::Idle &&
              (int)E_MQTTSTATE::CONNECTED == (int)MqttState::Connected &&
              (int)E_MQTTSTATE::RECONNECTING == (int)MqttState::Reconnecting,
              "E_MQTTSTATE must mirror MqttState");

// mq_accepted() and mq_succeeded() come from MqttResult.h. Queued is the
// ordinary answer to anything that reaches the wire later, so a block that
// treated it as a fault would light bError on a healthy link.
//
// Duplicate is the one the library does not count as accepted and the blocks
// must: it is what stops a held REQ flooding the broker, and on a request
// block it means "the identical thing is already in flight", not a failure.
bool mq_tolerated(MqttResult result) {
    return mq_accepted(result) || result == MqttResult::Duplicate;
}

// --- reading a TIME pin --------------------------------------------------
//
// Every duration on every block is a TIME, so that T#5s on one of these reads
// the same as T#5s on a TON sitting next to it. TIME is signed nanoseconds
// here and unsigned milliseconds in CODESYS, so nothing relies on a negative:
// a duration below zero is treated as none at all.
//
// ROUNDED UP, deliberately. Everywhere in this library 0 means "use the
// sensible default", so a pin somebody set to T#1ms must not arrive as 0 and
// silently become sixty seconds. Anything above zero is at least one unit.
int32_t mq_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = TIME_TO_NS(t);
    if (ns <= 0) return 0;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 2147483647LL ? 2147483647 : (int32_t)ms;
}

// The three fields MQTT carries in whole seconds on the wire - Keep Alive,
// Session Expiry, Will Delay. The protocol has no finer unit for them, so a
// pin set to T#500ms goes out as one second rather than as nothing.
int32_t mq_secondsOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = TIME_TO_NS(t);
    if (ns <= 0) return 0;
    const int64_t s = (ns + 999999999LL) / 1000000000LL;
    return s > 2147483647LL ? 2147483647 : (int32_t)s;
}

// And the way back, for an age or a round trip reported on a pin. A negative
// millisecond count - which inside these blocks means "it has never happened"
// - comes out as T#0s, because TIME is unsigned in CODESYS and a pin showing
// a negative duration would be a lie about a type. The block beside it says
// whether that zero means never: QUALITY is UNKNOWN, or SENT is still 0.
strucpp::IEC_TIME mq_timeOf(int32_t milliseconds)
{
    if (milliseconds <= 0) return strucpp::IEC_TIME((strucpp::TIME_t)0);
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

// "DE:AD:BE:EF:00:01" into six bytes. Separators may be colons, hyphens or
// nothing at all, because every vendor prints them differently and a MAC
// copied off a label should just work.
bool mq_parseMac(const char* text, uint8_t* out) {
    if (!text) return false;
    int digits = 0;
    uint8_t value = 0;
    for (const char* p = text; *p; p++) {
        const char c = *p;
        int nibble;
        if (c >= '0' && c <= '9')      nibble = c - '0';
        else if (c >= 'a' && c <= 'f') nibble = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') nibble = c - 'A' + 10;
        else if (c == ':' || c == '-' || c == '.') continue;
        else return false;
        value = (uint8_t)((value << 4) | (uint8_t)nibble);
        if (++digits % 2 == 0) {
            const int index = digits / 2 - 1;
            if (index >= 6) return false;
            out[index] = value;
            value = 0;
        }
    }
    return digits == 12;
}

// =============================================================================
// VALUES ON THE WIRE
// =============================================================================
//
// A PLC variable becomes MQTT payload TEXT, and text is not a lazy choice - it
// is the only one that interoperates. A dashboard, a Client-RED flow, a Python
// script and mosquitto_sub all read "23.5"; none of them agree on what four
// raw bytes mean, and half of them would get the byte order wrong.
//
// THE TEXT OF A STRING IS PUBLISHED, NEVER ITS IEC REPRESENTATION. That is
// worth naming because a sibling platform gets it wrong: PLCnext documents
// that passing a STRING as a raw payload sends the four header bytes every
// IEC 61131 string carries, plus a trailing NUL, and anybody who has debugged
// that at two in the morning does not want to meet it again.
//
// Defined here because every project has a client, which is the same reason the
// BeeBus library puts its own shared helper in its client block.

// An empty STRING formats to no text, and that is a payload of its own: an
// empty retained message is how a retained topic is cleared at the broker.
static bool mq_isEmptyText(const strucpp::IEC_ANY& any)
{
    return any.wired() && any.PVALUE != nullptr &&
           any.TYPECLASS == strucpp::TYPE_STRING && *(const char*)any.PVALUE == '\0';
}

size_t mq_formatAny(const strucpp::IEC_ANY& any, char* out, size_t capacity)
{
    if (!any.wired() || !out || capacity < 2) return 0;
    const void* p = (const void*)any.PVALUE;
    int wrote = 0;

    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:
        // TRUE and FALSE, in the words the rest of MQTT uses. A PLC operator
        // reading a broker log should see the same words as the ST.
        wrote = snprintf(out, capacity, "%s",
                         *(const uint8_t*)p ? "true" : "false");
        break;
    case strucpp::TYPE_SINT:
        wrote = snprintf(out, capacity, "%d", (int)*(const int8_t*)p); break;
    case strucpp::TYPE_INT:
        wrote = snprintf(out, capacity, "%d", (int)*(const int16_t*)p); break;
    case strucpp::TYPE_DINT:
        wrote = snprintf(out, capacity, "%ld", (long)*(const int32_t*)p); break;
    case strucpp::TYPE_LINT:
        wrote = snprintf(out, capacity, "%lld",
                         (long long)*(const int64_t*)p); break;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:
        wrote = snprintf(out, capacity, "%u", (unsigned)*(const uint8_t*)p); break;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:
        wrote = snprintf(out, capacity, "%u", (unsigned)*(const uint16_t*)p); break;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD:
        wrote = snprintf(out, capacity, "%lu",
                         (unsigned long)*(const uint32_t*)p); break;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD:
        wrote = snprintf(out, capacity, "%llu",
                         (unsigned long long)*(const uint64_t*)p); break;
    case strucpp::TYPE_REAL:
        // Seven significant figures is exactly what a 32-bit float carries.
        // More digits would be inventing precision the sensor never had.
        wrote = snprintf(out, capacity, "%.7g", (double)*(const float*)p); break;
    case strucpp::TYPE_LREAL:
        wrote = snprintf(out, capacity, "%.15g", *(const double*)p); break;
    case strucpp::TYPE_STRING: {
        // NUL-terminated by the runtime, capacity() + 1 bytes long, so this is
        // bounded by the declared width and cannot run off the end.
        const char* text = (const char*)p;
        size_t length = 0;
        const size_t bound = (size_t)any.DISIZE;
        while (length < bound && text[length] != '\0') length++;
        if (length >= capacity) length = capacity - 1;
        memcpy(out, text, length);
        out[length] = '\0';
        return length;
    }
    default:
        // An enumeration, a structure, an array, a time. Refused rather than
        // guessed at: a wrong number on a SCADA screen is worse than none.
        return 0;
    }

    if (wrote <= 0) return 0;
    if ((size_t)wrote >= capacity) return 0;   // truncated, so say so
    return (size_t)wrote;
}

// The same value as a number, for a deadband to work on. False for anything
// that is not one - a STRING has no "how much has it moved".
bool mq_numberOf(const strucpp::IEC_ANY& any, double* out)
{
    if (!any.wired() || !out) return false;
    const void* p = (const void*)any.PVALUE;
    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:  *out = *(const uint8_t*)p ? 1.0 : 0.0; return true;
    case strucpp::TYPE_SINT:  *out = (double)*(const int8_t*)p;   return true;
    case strucpp::TYPE_INT:   *out = (double)*(const int16_t*)p;  return true;
    case strucpp::TYPE_DINT:  *out = (double)*(const int32_t*)p;  return true;
    case strucpp::TYPE_LINT:  *out = (double)*(const int64_t*)p;  return true;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:  *out = (double)*(const uint8_t*)p;  return true;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:  *out = (double)*(const uint16_t*)p; return true;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD: *out = (double)*(const uint32_t*)p; return true;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD: *out = (double)*(const uint64_t*)p; return true;
    case strucpp::TYPE_REAL:  *out = (double)*(const float*)p;    return true;
    case strucpp::TYPE_LREAL: *out = *(const double*)p;           return true;
    default: return false;
    }
}

// How much to believe a subscribed number, judged against THE INTERVAL THE
// CALLER ASKED FOR rather than a constant. A hard-coded "stale after five
// seconds" is wrong for a temperature sampled hourly and wrong for a pressure
// sampled ten times a second.
//
// Unknown and Bad stay distinct on purpose: one sends somebody to a
// commissioning error, the other to a cable.
E_MQTTQUALITY mq_qualityOf(bool everArrived, bool linkUp, int32_t ageMs,
                          int32_t maxIntervalMs)
{
    if (!everArrived) return E_MQTTQUALITY::UNKNOWN;
    if (!linkUp)      return E_MQTTQUALITY::BAD;
    if (maxIntervalMs <= 0) return E_MQTTQUALITY::GOOD;
    if (ageMs <= maxIntervalMs) return E_MQTTQUALITY::GOOD;
    if (ageMs <= maxIntervalMs * 2) return E_MQTTQUALITY::UNCERTAIN;
    return E_MQTTQUALITY::BAD;
}

// The other direction: text off the wire into the caller's variable.
//
// Writing through PVALUE is the runtime's own sanctioned route - iec_any.hpp
// says "writing *(T*)any.PVALUE writes what the caller passed" - so a value
// arriving here lands in the ST variable with nothing to copy afterwards and
// nothing to keep in step.
bool mq_parseAny(const char* text, size_t length, const strucpp::IEC_ANY& any)
{
    if (!any.wired() || !text) return false;

    char scratch[64];
    if (any.TYPECLASS != strucpp::TYPE_STRING) {
        if (length >= sizeof scratch) return false;
        memcpy(scratch, text, length);
        scratch[length] = '\0';
        text = scratch;
    }

    void* p = (void*)any.PVALUE;
    char* end = nullptr;

    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL: {
        // Everything a person or a broker might plausibly send. A publisher
        // that says "ON" and a subscriber that only understands "1" is a
        // commissioning afternoon nobody should have to spend.
        const bool on  = strcasecmp(text, "true") == 0 ||
                         strcasecmp(text, "on") == 0 ||
                         strcasecmp(text, "1") == 0;
        const bool off = strcasecmp(text, "false") == 0 ||
                         strcasecmp(text, "off") == 0 ||
                         strcasecmp(text, "0") == 0;
        if (!on && !off) return false;
        *(uint8_t*)p = on ? 1 : 0;
        return true;
    }
    case strucpp::TYPE_SINT:  { long v = strtol(text, &end, 10);
        if (end == text || v < -128 || v > 127) return false;
        *(int8_t*)p = (int8_t)v; return true; }
    case strucpp::TYPE_INT:   { long v = strtol(text, &end, 10);
        if (end == text || v < -32768 || v > 32767) return false;
        *(int16_t*)p = (int16_t)v; return true; }
    case strucpp::TYPE_DINT:  { long long v = strtoll(text, &end, 10);
        if (end == text || v < -2147483648LL || v > 2147483647LL) return false;
        *(int32_t*)p = (int32_t)v; return true; }
    case strucpp::TYPE_LINT:  { long long v = strtoll(text, &end, 10);
        if (end == text) return false;
        *(int64_t*)p = (int64_t)v; return true; }
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:  { unsigned long v = strtoul(text, &end, 0);
        if (end == text || v > 255) return false;
        *(uint8_t*)p = (uint8_t)v; return true; }
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:  { unsigned long v = strtoul(text, &end, 0);
        if (end == text || v > 65535) return false;
        *(uint16_t*)p = (uint16_t)v; return true; }
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD: { unsigned long long v = strtoull(text, &end, 0);
        if (end == text || v > 4294967295ULL) return false;
        *(uint32_t*)p = (uint32_t)v; return true; }
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD: { unsigned long long v = strtoull(text, &end, 0);
        if (end == text) return false;
        *(uint64_t*)p = (uint64_t)v; return true; }
    case strucpp::TYPE_REAL:  { double v = strtod(text, &end);
        if (end == text) return false;
        *(float*)p = (float)v; return true; }
    case strucpp::TYPE_LREAL: { double v = strtod(text, &end);
        if (end == text) return false;
        *(double*)p = v; return true; }
    case strucpp::TYPE_STRING: {
        // DISIZE is the declared width; the runtime keeps a NUL after it, so
        // there is one spare byte and truncating here cannot overrun.
        char* dest = (char*)p;
        const size_t bound = (size_t)any.DISIZE;
        size_t n = length < bound ? length : bound;
        memcpy(dest, text, n);
        dest[n] = '\0';
        return true;
    }
    default:
        return false;
    }
}

// =============================================================================
// A STRUCT'S MEMBERS, ONE AT A TIME
// =============================================================================
//
// A STRUCT arrives on an ANY pin as TYPE_USERDEF: an address, a size, and
// TYPEDESC - the layout STruC++ emits beside the type. That descriptor is what
// turns an opaque run of bytes into named members, and it is why the struct
// blocks can exist at all.
//
// MemberDesc::BYTEOFFSET addresses the member's PAYLOAD, not the IECVar
// wrapper around it, so nothing here has to know how forcing is stored.

// One member as an IEC_ANY, so it can go through the same formatter every
// other block uses. Written rather than assumed: a reader that recomputed the
// width from the class would get STRING wrong, where CAP is the number that
// matters and BITSIZE covers the whole string object.
bool mq_memberAsAny(const strucpp::MemberDesc& member, uint8_t* base,
                    strucpp::IEC_ANY* out)
{
    if (!out || !base) return false;
    out->TYPECLASS = member.TYPECLASS;
    out->PVALUE = base + member.BYTEOFFSET;
    out->DICOUNT = 1;
    out->DISTRIDE = (int32_t)member.STRIDE;
    out->ELEMCLASS = member.BASETYPECLASS;
    out->TYPEDESC = member.NESTED;

    if (member.TYPECLASS == strucpp::TYPE_STRING ||
        member.TYPECLASS == strucpp::TYPE_WSTRING) {
        // The declared capacity, which is what bounds a read or a write. The
        // runtime keeps a NUL after it, so neither can run off the end.
        out->DISIZE = (int32_t)member.CAP;
    } else {
        out->DISIZE = (int32_t)(member.BITSIZE / 8);
    }
    return true;
}

// Whether a member is one value this library can put on a wire.
//
// An array, a nested structure and anything else are REFUSED BY NAME rather
// than skipped, because a member silently missing from a payload is the kind
// of fault that survives a commissioning and turns up in an argument about
// whose data is wrong.
bool mq_memberIsPublishable(const strucpp::MemberDesc& member)
{
    if (member.NUMELEMENTS != 1) return false;
    switch (member.TYPECLASS) {
    case strucpp::TYPE_BOOL:  case strucpp::TYPE_SINT:
    case strucpp::TYPE_INT:   case strucpp::TYPE_DINT:
    case strucpp::TYPE_LINT:  case strucpp::TYPE_USINT:
    case strucpp::TYPE_UINT:  case strucpp::TYPE_UDINT:
    case strucpp::TYPE_ULINT: case strucpp::TYPE_BYTE:
    case strucpp::TYPE_WORD:  case strucpp::TYPE_DWORD:
    case strucpp::TYPE_LWORD: case strucpp::TYPE_REAL:
    case strucpp::TYPE_LREAL: case strucpp::TYPE_STRING:
        return true;
    default:
        return false;
    }
}

// A cheap fingerprint of a payload, so text can be compared without storing
// it. Thirty-two members of STRING(254) would be eight kilobytes of shadow
// per block instance; this is four bytes each.
//
// FNV-1a. A collision would mean one unchanged-looking update missed, not a
// wrong value published, and at 32 bits that is not a risk worth eight
// kilobytes of RAM on every device.
uint32_t mq_fingerprint(const char* text, size_t length)
{
    uint32_t hash = 2166136261u;
    for (size_t i = 0; i < length; i++) {
        hash ^= (uint8_t)text[i];
        hash *= 16777619u;
    }
    return hash;
}

// BASE + '/' + member name, bounded. Returns false rather than truncating: a
// topic cut short is a topic somebody else owns.
bool mq_memberTopic(const char* base, const char* name, char* out, size_t cap)
{
    const size_t b = base ? strlen(base) : 0;
    const size_t n = name ? strlen(name) : 0;
    if (b + 1 + n + 1 > cap) return false;
    if (b) { memcpy(out, base, b); out[b] = '/'; }
    memcpy(out + (b ? b + 1 : 0), name, n);
    out[(b ? b + 1 : 0) + n] = '\0';
    return true;
}

// The client every other block reaches through its CLIENT pin. Null until the
// client has opened its link, which is what bLinkUp says.
MqttClient* mq_clientOf(strucpp::XWORD_t handle) {
    return (MqttClient*)(uintptr_t)handle;
}

// --- A DELIBERATE GOODBYE, and whether it carries the Will ---
//
// A layer owns the Will - FB_SparkplugNode, FB_SparkplugHost - because it is a
// death certificate the plant must see whenever the connection ends: a
// settings change and bConnect := FALSE included, as Sparkplug requires of an
// intentional disconnect. So the broker is asked to publish it (at 3.1.1 the
// client publishes it, just ahead of the DISCONNECT). A stWillConfig Will
// is not owned, and keeps the plain goodbye it has always had.
static uint8_t mq_goodbyeReason(const MqttClient& client) {
    return client.willOwner() != nullptr ? MQ_REASON_DISCONNECT_WITH_WILL
                                         : MQ_REASON_NORMAL_DISCONNECTION;
}

// --- WHAT THE BROKER SAID TO THE LAST bConnect, in words ---
//
// Empty when the last attempt never reached a CONNACK, or was accepted.
//
// THE RIGHT TABLE FOR THE VERSION THE ANSWER CAME BACK IN. 3.1.1's CONNACK
// carries a RETURN CODE, not a 5.0 reason code, and the two tables disagree
// about nearly every number: read against 5.0, this printed "the broker
// refused the connection: Granted QoS 1" for a 3.1.1 broker saying
// "unacceptable protocol version". After a fallback the version in force is
// not the one asked for, so this picks by what is in force.
//
// AND ONLY THE bConnect'S OWN ANSWER - connectReasonCode, reset before every
// attempt - never lastReasonCode, which is the last code from ANY packet: a
// link that died at the TCP level was once reported as "the broker refused the
// connection: Granted QoS 2", the client's own SUBACK from an hour earlier.
std::string mq_connectRefusal(MqttClient& client) {
    const MqttStatus& status = client.status();
    if (status.connectReasonCode == 0) return std::string();
    const char* said = client.activeVersion() == MqttVersion::V311
                           ? mq_returnCodeName(status.connectReasonCode)
                           : mq_reasonName(status.connectReasonCode, MQ_PKT_CONNACK);
    if (said == nullptr || *said == '\0') return std::string();
    return std::string("the broker refused the connection: ") + said;
}

// --- A SHORT FINGERPRINT OF SETTINGS ---
//
// FNV-1a, 32 bits. Not for security: only to notice that a setting changed
// without keeping a second copy of every string in each instance (a few
// hundred bytes of RAM per client, doubled by the force shadow).
uint32_t mq_fingerprint(uint32_t hash, const void* data, size_t length)
{
    const uint8_t* bytes = (const uint8_t*)data;
    for (size_t i = 0; i < length; i++) {
        hash ^= bytes[i];
        hash *= 16777619u;
    }
    return hash;
}

uint32_t mq_fingerprintText(uint32_t hash, const char* text)
{
    hash = mq_fingerprint(hash, text, strlen(text));
    return mq_fingerprint(hash, "", 1);   // a separator: "ab"+"c" differs from "a"+"bc"
}

// =============================================================================
// THE METHODS' STATE
// =============================================================================
//
// A method keeps what it needs between calls in a record, keyed by the method
// and the declared name and type of its ANY argument (IEC_ANY::NAME,
// TYPENAME). An argument with no name - a literal, an expression - is keyed by
// its topic instead. PVALUE is kept only as a cache. The records belong to
// the client instance and are dropped when it is given a different client.

#ifndef MQ_MAX_RECORDS
#define MQ_MAX_RECORDS 256
#endif

// How often a pending PLC asks again, and how long after a refusal.
#ifndef MQ_PROVISION_PENDING_MS
#define MQ_PROVISION_PENDING_MS 30000
#endif
#ifndef MQ_PROVISION_REFUSED_MS
#define MQ_PROVISION_REFUSED_MS 300000
#endif

namespace {

enum MqRecordKind : uint8_t {
    MQ_REC_PUBLISH,
    MQ_REC_REPORT,
    MQ_REC_SUBSCRIBE,
    MQ_REC_PUBLISH_STRUCT,
    MQ_REC_SUBSCRIBE_STRUCT,
    MQ_REC_REQUEST,
    MQ_REC_RESPONSE,
    MQ_REC_MESSAGE,
};

// One STRUCT member: the publish side's last value, the subscribe side's
// handle and arrival.
struct MqMember {
    bool hasLast = false;
    double last = 0.0;
    uint32_t hash = 0;
    int32_t sentAt = 0;
    int16_t handle = -1;
    bool ever = false;
    int32_t arrivedAt = 0;
};

struct MqRecord {
    uint8_t kind = 0;
    uint32_t key = 0;
    std::string name;
    std::string type;
    const uint8_t* cache = nullptr;

    std::string topic;            // Response: the request filter the hook matches
    std::string replyTopic;       // Request: where the answer comes; Response: where it goes
    int16_t handle = -1;
    int16_t replyHandle = -1;
    bool asked = false;
    int32_t seenConnects = 0;

    bool lastExecute = false;
    bool pending = false;
    E_MQTTRESULT result = E_MQTTRESULT::OK;
    uint32_t seenOk = 0;
    uint32_t seenFail = 0;
    int32_t limitMs = 0;

    bool ever = false;            // sent (publishing) or arrived (subscribing)
    int32_t at = 0;
    int32_t ageMs = -1;
    bool hasLast = false;
    double last = 0.0;
    uint32_t lastHash = 0;
    E_MQTTQUALITY quality = E_MQTTQUALITY::UNKNOWN;
    bool subscribed = false;

    int32_t sent = 0;
    int32_t received = 0;
    int32_t malformed = 0;
    int32_t length = 0;
    bool truncated = false;
    int16_t points = 0;
    int16_t skipped = 0;

    int32_t correlation = 0;
    std::string reply;
    std::vector<uint8_t> correlationData;
    bool answerable = false;

    MqMember* members = nullptr;
    uint16_t memberCount = 0;

    MqRecord() = default;
    MqRecord(const MqRecord&) = delete;
    MqRecord& operator=(const MqRecord&) = delete;
    ~MqRecord() { delete[] members; }
};

// Provision's progress. Not dropped with the records: a login switch spans
// reconnects.
struct MqProvision {
    bool usingKey = false;
    int16_t handle = -1;
    bool asked = false;
    int32_t askedAt = 0;
    int32_t seenConnects = -1;
    int8_t switchTo = 0;          // 0 none, 1 to the stored login, 2 to the key, 3 the login without a Will
    bool switchClosed = false;
    int32_t refusedAt = 0;
    bool lastForget = false;
    bool forgetSeen = false;
    bool withoutWill = false;     // this session is the login without a Will: asking again, then back
    int32_t lockedAt = 0;         // when the login was last refused as not authorized
    int32_t oldTriedAt = 0;       // when the kept login was last tried, while registering again
    bool provisioned = false;
    bool waiting = false;
    bool refused = false;
    std::string userName;
    std::string reason;
    E_MQTTRESULT status = E_MQTTRESULT::OK;
};

struct MqMethods;

// Sees every inbound message with its properties, which the topic registry
// does not keep: a Response record takes the request's Response Topic and
// Correlation Data from here. Never takes a message.
struct MqRequestHook : MqttClientHook {
    MqMethods* owner = nullptr;
    bool message(const MqttMessage& message) override;
};

struct MqMethods {
    MqMethods* next = nullptr;
    strucpp::XWORD_t client = 0;
    std::vector<MqRecord*> records;
    MqProvision provision;
    MqRequestHook hook;
    // The last method call that failed, by method and record: the client's
    // bError / sLastError name it until that call succeeds.
    std::string failKey;
    std::string failText;
    uint8_t failResult = 0;

    void drop() {
        if (MqttClient* attached = hook.attachedTo()) attached->detach(hook);
        for (size_t i = 0; i < records.size(); i++) delete records[i];
        records.clear();
    }
    ~MqMethods() { drop(); }
};

// A plain pointer, so it needs no construction and outlives every destructor.
static MqMethods* mqMethodsHead = nullptr;

bool MqRequestHook::message(const MqttMessage& message) {
    if (owner == nullptr) return false;
    for (size_t i = 0; i < owner->records.size(); i++) {
        MqRecord* r = owner->records[i];
        if (r->kind != MQ_REC_RESPONSE || r->topic.empty()) continue;
        MqttSpan filter;
        filter.data = (const uint8_t*)r->topic.c_str();
        filter.length = (uint32_t)r->topic.size();
        if (!mq_topicMatches(filter, message.topic)) continue;
        const MqttProperties* p = message.properties;
        if (p != nullptr && p->has(MQ_PROP_RESPONSE_TOPIC) && !p->responseTopic.empty()) {
            r->replyTopic.assign((const char*)p->responseTopic.data, p->responseTopic.length);
            if (p->has(MQ_PROP_CORRELATION_DATA)) {
                r->correlationData.assign(p->correlationData.data,
                                          p->correlationData.data + p->correlationData.length);
            } else {
                r->correlationData.clear();
            }
            r->answerable = true;
        } else {
            // No Response Topic (or a 3.1.1 connection): nothing to answer to.
            r->replyTopic.clear();
            r->correlationData.clear();
            r->answerable = false;
        }
    }
    return false;
}

}  // namespace

// Called first by MqNodeCleanup, while the clients the hooks hang on still exist.
void mq_dropMethods() {
    while (mqMethodsHead != nullptr) {
        MqMethods* m = mqMethodsHead;
        mqMethodsHead = m->next;
        delete m;
    }
}

// This instance's method state, made on first use. A different client than
// the records were made on drops them.
static MqMethods* mq_methodsFor(strucpp::XWORD_t held, strucpp::XWORD_t api) {
    MqMethods* m = (MqMethods*)(uintptr_t)held;
    if (m == nullptr) {
        m = new (std::nothrow) MqMethods();
        if (m == nullptr) return nullptr;
        m->hook.owner = m;
        m->next = mqMethodsHead;
        mqMethodsHead = m;
    }
    if (api != 0 && m->client != api) {
        if (m->client != 0) m->drop();
        m->client = api;
    }
    return m;
}

// A method call's result, noted on the client. A failing call is named on
// the client's bError / sLastError ("Publish DEV.level: InvalidArgument") until
// the same call succeeds. Not connected, queued and not yet built are states,
// not failures.
static E_MQTTRESULT mq_noteCall(strucpp::XWORD_t held, const char* method,
                                const strucpp::IEC_ANY* any, const char* topic,
                                E_MQTTRESULT result) {
    MqMethods* m = (MqMethods*)(uintptr_t)held;
    if (m == nullptr) return result;
    const char* record = any != nullptr && any->NAME != nullptr && any->NAME[0] != '\0'
                             ? any->NAME : topic;
    std::string key = method;
    key += ' ';
    key += record != nullptr ? record : "";
    const bool failed = result != E_MQTTRESULT::OK && result != E_MQTTRESULT::QUEUED &&
                        result != E_MQTTRESULT::NOTCONNECTED &&
                        result != E_MQTTRESULT::NOTINITIALISED;
    if (failed) {
        m->failKey = key;
        m->failResult = (uint8_t)result;
        m->failText = key + ": " +
                      (result == E_MQTTRESULT::WRONGTASK ? "wrong task"
                                                         : mq_resultName((MqttResult)(int)result));
    } else if (m->failKey == key) {
        m->failKey.clear();
        m->failText.clear();
    }
    return result;
}

// The record of one call, found by its key or made. Null past MQ_MAX_RECORDS
// or out of memory.
static MqRecord* mq_recordOf(MqMethods* m, uint8_t kind, const strucpp::IEC_ANY& any,
                             const char* topic) {
    if (m == nullptr) return nullptr;
    std::string unnamed;
    const char* name = any.NAME;
    if (name == nullptr || *name == '\0') {
        unnamed = std::string("'") + (topic ? topic : "");
        name = unnamed.c_str();
    }
    const char* type = any.TYPENAME ? any.TYPENAME : "";
    uint32_t key = mq_fingerprint(2166136261u, &kind, sizeof kind);
    key = mq_fingerprintText(mq_fingerprintText(key, name), type);

    for (size_t i = 0; i < m->records.size(); i++) {
        MqRecord* r = m->records[i];
        if (r->kind != kind || r->key != key) continue;
        if (any.PVALUE != nullptr && r->cache == any.PVALUE && any.NAME != nullptr) return r;
        if (r->name == name && r->type == type) {
            r->cache = any.PVALUE;
            return r;
        }
    }
    if (m->records.size() >= (size_t)MQ_MAX_RECORDS) return nullptr;
    MqRecord* r = new (std::nothrow) MqRecord();
    if (r == nullptr) return nullptr;
    r->kind = kind;
    r->key = key;
    r->name = name;
    r->type = type;
    r->cache = any.PVALUE;
    m->records.push_back(r);
    return r;
}

// The handle for `topic`, registered when `held` has none or holds another
// text (or one from another client). *changed says it was registered.
static MqttTopicHandle mq_handleFor(MqttClient* client, int16_t& held, const char* topic,
                                    bool* changed) {
    MqttTopicHandle handle = (MqttTopicHandle)held;
    const char* text = handle >= 0 ? client->topicOf(handle) : nullptr;
    if (text != nullptr && strcmp(text, topic) == 0) return handle;
    handle = client->registerTopic(topic);
    if (handle == MQTT_TOPIC_HANDLE_NONE) return handle;
    held = (int16_t)handle;
    if (changed) *changed = true;
    return handle;
}

static uint8_t mq_qosOf(E_MQTTQOS qos) {
    const int q = (int)qos;
    return (uint8_t)(q < 0 ? 0 : (q > 2 ? 2 : q));
}

// One string field of the broker's provisioning answer, written without
// spaces: {"status":"ok","username":"...","password":"...","data":{"group":"..."}}.
// Found by its NAME (`"name":`), never by a value that happens to read the same.
static bool mq_provisionField(const char* doc, size_t length, const char* name, std::string& out)
{
    const std::string text(doc, length);
    const std::string key = std::string("\"") + name + "\":";
    size_t at = text.find(key);
    if (at == std::string::npos) return false;
    at = text.find('"', at + key.size());
    if (at == std::string::npos) return false;
    out.clear();
    for (size_t i = at + 1; i < text.size(); i++) {
        if (text[i] == '\\' && i + 1 < text.size()) { out.push_back(text[++i]); continue; }
        if (text[i] == '"') return true;
        out.push_back(text[i]);
    }
    return false;
}

void setup()
{
    bLinkUp = false;
    bConnected = false;
    tHeardAgo = mq_timeOf(0);
    bSessionPresent = false;
    sAssignedId = "";
    eConnectionState = E_MQTTSTATE::IDLE;
    bError = false;
    eErrorId = E_MQTTRESULT::OK;
    sLastError = "";
    nApi = (strucpp::XWORD_t)0;
    nLink = (strucpp::XWORD_t)0;
    // NOT sPinnedKey, which is retained and is the whole point of being so.
    bPinApplied = false;
    bLastTrust = false;
    bTrustSeen = false;
    bSettled = false;
    bTried = false;
    nRetryAt = 0;
    bWanted = false;
    bConnectAsked = false;
    nMediumKey = 0;
    nSessionKey = 0;
    nWiFiKeyHash = 0;
    bRelink = false;
    bReconfigure = false;
    nChangeAt = 0;
}

void loop()
{
    nTask = mq_currentTask();   // every block on this one shares it: ONE TASK, above
    MqNode* client = (MqNode*)(uintptr_t)(strucpp::XWORD_t)nLink;

    // What the medium is built from. A change rebuilds it under the same
    // client, so every handle the other blocks hold stays valid.
    auto mediumKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        const int32_t link = (int32_t)(E_MQTTTRANSPORT)eTransport;
        const int32_t security = (int32_t)(E_MQTTSECURITY)eSecurity;
        const uint16_t port = (uint16_t)nPort;
        const uintptr_t external = (uintptr_t)(strucpp::XWORD_t)nExternalLink;
        const int32_t timeout = (int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT);
        h = mq_fingerprint(h, &link, sizeof link);
        h = mq_fingerprint(h, &security, sizeof security);
        h = mq_fingerprint(h, &port, sizeof port);
        h = mq_fingerprint(h, &external, sizeof external);
        h = mq_fingerprint(h, &timeout, sizeof timeout);
        h = mq_fingerprintText(h, sHost.c_str());
        h = mq_fingerprintText(h, stTlsConfig.SCAFILE.c_str());
        h = mq_fingerprintText(h, stTlsConfig.SCERTFILE.c_str());
        h = mq_fingerprintText(h, stTlsConfig.SKEYFILE.c_str());
        h = mq_fingerprintText(h, stNetworkConfig.SMAC.c_str());
        h = mq_fingerprintText(h, stNetworkConfig.SIP.c_str());
        h = mq_fingerprintText(h, stNetworkConfig.SGATEWAY.c_str());
        h = mq_fingerprintText(h, stNetworkConfig.SSUBNET.c_str());
        return h;
    };
    // The board's Wi-Fi login, which stNetworkConfig hands to this block.
    auto wifiKey = [&]() -> uint32_t {
        uint32_t h = mq_fingerprintText(2166136261u, stNetworkConfig.SSSID.c_str());
        return mq_fingerprintText(h, stNetworkConfig.SWIFIPASSWORD.c_str());
    };
    // What the bConnect says. A change reconnects on the same medium.
    // Provision's login is its own business: it reconnects for itself.
    auto sessionKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        const int32_t protocol = (int32_t)(E_MQTTPROTOCOL)eProtocol;
        const uint16_t keepAlive = (uint16_t)mq_secondsOf(stSessionConfig.TKEEPALIVE);
        const bool clean = (bool)stSessionConfig.BCLEANSTART;
        const int32_t expiry = (int32_t)mq_secondsOf(stSessionConfig.TSESSIONEXPIRY);
        const uint8_t qos = (uint8_t)(int)(E_MQTTQOS)stWillConfig.EQOS;
        const bool retain = (bool)stWillConfig.BRETAIN;
        const int32_t delay = (int32_t)mq_secondsOf(stWillConfig.TDELAY);
        h = mq_fingerprint(h, &protocol, sizeof protocol);
        h = mq_fingerprint(h, &keepAlive, sizeof keepAlive);
        h = mq_fingerprint(h, &clean, sizeof clean);
        h = mq_fingerprint(h, &expiry, sizeof expiry);
        h = mq_fingerprint(h, &qos, sizeof qos);
        h = mq_fingerprint(h, &retain, sizeof retain);
        h = mq_fingerprint(h, &delay, sizeof delay);
        h = mq_fingerprintText(h, sClientId.c_str());
        h = mq_fingerprintText(h, stSessionConfig.SUSERNAME.c_str());
        h = mq_fingerprintText(h, stSessionConfig.SUSERPASSWORD.c_str());
        h = mq_fingerprintText(h, stWillConfig.STOPIC.c_str());
        h = mq_fingerprintText(h, (stWillConfig.SOFFLINE.length() > 0 ? stWillConfig.SOFFLINE.c_str() : "offline"));
        return h;
    };
    // What the client is told on bConnect, from the pins and the helpers as
    // they are now. Used when the link is built and again when the session
    // settings change.
    auto buildConnection = [&](const std::string& host, uint16_t port) -> MqttConnectionConfig {
        MqttConnectionConfig connection;
        connection.host = host;
        connection.port = port;
        connection.clientId = std::string(sClientId.c_str(), sClientId.length());
        connection.keepAlive = (uint16_t)mq_secondsOf(stSessionConfig.TKEEPALIVE) != 0
            ? (uint16_t)mq_secondsOf(stSessionConfig.TKEEPALIVE) : 60;
        connection.cleanStart = (bool)stSessionConfig.BCLEANSTART;
        if ((int32_t)mq_secondsOf(stSessionConfig.TSESSIONEXPIRY) > 0) {
            connection.sessionExpiryInterval = (uint32_t)(int32_t)mq_secondsOf(stSessionConfig.TSESSIONEXPIRY);
            connection.hasSessionExpiry = true;
        }
        // Asking with Provision's key: a registration session, which sends
        // no Will (stWillConfig's or FB_SparkplugNode's) - it may publish nothing
        // but its request, and a broker refuses a Will it may not publish.
        connection.registration = (bool)bProvisioning;
        if (sProvUser.length() > 0) {
            // Provision's login wins: it is either the one this PLC was
            // given, or the key it is about to ask with.
            connection.hasUserName = true;
            connection.userName = std::string(sProvUser.c_str(), sProvUser.length());
            connection.hasPassword = true;
            const char* pw = sProvPassword.c_str();
            connection.password.assign(pw, pw + sProvPassword.length());
        } else {
            if (stSessionConfig.SUSERNAME.length() > 0) {
                connection.hasUserName = true;
                connection.userName = std::string(stSessionConfig.SUSERNAME.c_str(), stSessionConfig.SUSERNAME.length());
            }
            if (stSessionConfig.SUSERPASSWORD.length() > 0) {
                connection.hasPassword = true;
                const char* pw = stSessionConfig.SUSERPASSWORD.c_str();
                connection.password.assign(pw, pw + stSessionConfig.SUSERPASSWORD.length());
            }
        }

        const E_MQTTPROTOCOL wanted = (E_MQTTPROTOCOL)eProtocol;
        if (wanted == E_MQTTPROTOCOL::V311) {
            connection.version = MqttVersion::V311;
        } else {
            connection.version = MqttVersion::V5;
            // Fallback triggers only on evidence the VERSION is the problem -
            // a 5.0 reason 0x84, or a 3.1.1 return code 0x01. Never on an
            // authentication or network failure, because treating those as a
            // version problem hides them.
            connection.fallbackEnabled =
                (wanted == E_MQTTPROTOCOL::V5THENV311);
        }

        if (stWillConfig.STOPIC.length() > 0) {
            connection.will.set(stWillConfig.STOPIC.c_str(), (stWillConfig.SOFFLINE.length() > 0 ? stWillConfig.SOFFLINE.c_str() : "offline"),
                                (uint8_t)(int)(E_MQTTQOS)stWillConfig.EQOS, (bool)stWillConfig.BRETAIN);
            if ((int32_t)mq_secondsOf(stWillConfig.TDELAY) > 0) {
                connection.will.delayInterval = (uint32_t)(int32_t)mq_secondsOf(stWillConfig.TDELAY);
            }
        }

        return connection;
    };

    // Asked to stand down. The connection closes and the object stays: the
    // pins that describe it have not changed, and rebuilding it would lose
    // every subscription and topic handle the other blocks registered.
    const bool want = (bool)bConnect;
    if (!want) {
        if (client) {
            if ((bool)bLinkUp) client->client.disconnect(mq_goodbyeReason(client->client));
            // Still polled, so the DISCONNECT actually leaves and the broker
            // sees a deliberate goodbye rather than a lost link.
            client->client.poll();
            eConnectionState = (E_MQTTSTATE)(int32_t)(int)client->client.status().state;
        } else {
            eConnectionState = E_MQTTSTATE::IDLE;
        }
        bLinkUp = false;
        bConnected = false;
        tHeardAgo = mq_timeOf(0);
        bTried = false;
        bConnectAsked = false;
        bWanted = false;
        return;
    }

    if (!(bool)bLinkUp) {
        // ONE SCAN BEFORE OPENING.
        //
        // Its methods - Provision among them - write into
        // this instance, and they may sit above or below this block in the
        // rung order. Waiting a scan means every one of them has run at least
        // once before the link is built, so a helper does not have to be
        // placed anywhere in particular - which is a rule nobody would
        // remember and the compiler could not check.
        //
        // It costs one scan of the fast task. Opening a socket takes longer
        // than that on its own.
        if (!(bool)bSettled) {
            bSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)bTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)nRetryAt) < 0) {
            return;
        }
        // A SETTINGS CHANGE IS UNDER WAY: let the DISCONNECT on the old
        // settings leave first (a second at most), so the broker sees a
        // goodbye rather than a dropped socket and publishes no Will.
        if (client && ((bool)bRelink || (bool)bReconfigure) &&
            client->client.status().state == MqttState::Disconnecting &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)nChangeAt) < 1000) {
            client->client.poll();
            return;
        }

        bTried = true;
        nRetryAt = (int32_t)(uint32_t)(now + MQ_REOPEN_MS);

        // ALREADY BUILT. Come back up on the SAME client.
        //
        // Building a second one here would be a quiet disaster: every other
        // block holds a topic handle, which is an index into THIS client's
        // registry, and a fresh client has an empty one. The handles would
        // still look valid - they are small non-negative integers - and would
        // address nothing. topicOf() returns null for one of those, and the
        // first block to compare it against its own filter dereferences it.
        //
        // That is not hypothetical; testing caught exactly that, which is
        // also what makes the promise in docs/03 true rather than aspirational:
        // subscriptions and handles survive a stand-down because the object
        // they belong to does.
        if (client && !(bool)bRelink) {
            if ((bool)bReconfigure) {
                // The session settings changed (login, client id, version,
                // keepalive, Will): the next bConnect says the new ones. The
                // medium is the same, so the host and port are the link's.
                const uint16_t samePort = (uint16_t)nPort != 0
                    ? (uint16_t)nPort
                    : (uint16_t)(eSecurity != E_MQTTSECURITY::PLAIN ? MQ_PORT_TLS
                                                                       : MQ_PORT_TCP);
                const std::string sameHost = client->link ? client->link->host : std::string();
                client->client.reconfigure(buildConnection(sameHost, samePort));
                bReconfigure = false;
            }
            bLinkUp = true;
            bConnectAsked = false;
            bError = false;
            eErrorId = E_MQTTRESULT::OK;
            sLastError = "";
            // Fall through to connect() below on this same scan.
        } else {

        // A rebuilt medium is told the stored key afresh, as a new one is.
        bPinApplied = false;

        // --- build the medium -------------------------------------------
        //
        // Inline rather than in a helper because a free function cannot see
        // the pins: they are macros over a `vars` struct that exists only
        // inside this function.
        const E_MQTTTRANSPORT link = (E_MQTTTRANSPORT)eTransport;
        const E_MQTTSECURITY security = (E_MQTTSECURITY)eSecurity;
        const bool wantsTls = (security != E_MQTTSECURITY::PLAIN);
        const bool runtimeLink = (link == E_MQTTTRANSPORT::RUNTIMETCP);
        const bool external = (link == E_MQTTTRANSPORT::EXTERNAL);

#if defined(MQTT_PLATFORM_HOST)
        if (!runtimeLink && !external) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "that transport needs a board, not the Runtime";
            return;
        }
#else
        if (runtimeLink) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "that transport needs the Runtime, not a board";
            return;
        }
#endif

        if (!external && sHost.length() == 0) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "set sHost to the broker";
            return;
        }

        const uint16_t port = (uint16_t)nPort != 0
            ? (uint16_t)nPort
            : (uint16_t)(wantsTls ? MQ_PORT_TLS : MQ_PORT_TCP);

        MqLink* made = nullptr;

        if (external) {
            MqttTransport* borrowed =
                (MqttTransport*)(uintptr_t)(strucpp::XWORD_t)nExternalLink;
            if (!borrowed) {
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                sLastError = "E_MqttTransport.External needs a transport on nExternalLink";
                return;
            }
            MqExternalLink* ext = new (std::nothrow) MqExternalLink();
            if (ext) ext->borrowed = borrowed;
            made = ext;
        }
#if defined(MQTT_PLATFORM_HOST)
        else if (!wantsTls) {
            MqTcpLink* tcp = new (std::nothrow) MqTcpLink();
            if (tcp) {
                tcp->host = std::string(sHost.c_str(), sHost.length());
                tcp->tcp.configure(tcp->host.c_str(), port);
            }
            made = tcp;
        } else {
#if MQTT_TLS_AVAILABLE
            MqTlsLink* tls = new (std::nothrow) MqTlsLink();
            if (tls) {
                tls->host = std::string(sHost.c_str(), sHost.length());
                tls->tls.configure(tls->host.c_str(), port);
                if (stTlsConfig.SCAFILE.length() > 0) tls->tls.setCaFile(stTlsConfig.SCAFILE.c_str());
#if defined(MQTT_CA_CERT_PEM)
                tls->tls.setCaCertificate(MQTT_CA_CERT_PEM);
#endif
                if (stTlsConfig.SCERTFILE.length() > 0 && stTlsConfig.SKEYFILE.length() > 0) {
                    tls->tls.setClientCertificate(stTlsConfig.SCERTFILE.c_str(),
                                                  stTlsConfig.SKEYFILE.c_str());
                }
                // Named at length in the library on purpose, and named here
                // too: this is the pin that turns a verified connection into
                // an encrypted conversation with whoever answered.
                if (security == E_MQTTSECURITY::TLSINSECURE) {
                    tls->tls.setInsecureNoCertificateValidation();
                } else if (security == E_MQTTSECURITY::TLSPINNED) {
                    // PINNING TRUSTS ONE KEY INSTEAD OF AN AUTHORITY, which is
                    // the only thing that can be done about a broker nobody
                    // signed for - a ModBee PLC broker, or a site's own
                    // Mosquitto. It deliberately skips chain and expiry
                    // checking: a controller with no clock cannot judge an
                    // expiry date, and a link that drops because a PLC booted
                    // believing it is 1970 is worse than one that trusts a key
                    // it recognises.
                    if (sPinnedKey.length() > 0) {
                        tls->tls.setPinnedKeyFingerprint(sPinnedKey.c_str());
                        bPinApplied = true;
                    } else if (!bTrustNew) {
                        // Nothing stored and nobody commissioning. Refused
                        // rather than connected unchecked, because a pinned
                        // link that silently falls back to trusting anybody is
                        // a pinned link in name only.
                        delete tls;
                        bError = true;
                        eErrorId = E_MQTTRESULT::NOTAUTHORIZED;
                        sLastError = "no pinned key yet - set bTrustNew once to learn it";
                        return;
                    } else {
                        // Trust on first use. The connection comes up
                        // unvalidated exactly once, so the fingerprint can be
                        // read and stored; from the next scan the stored value
                        // is what is checked.
                        tls->tls.setInsecureNoCertificateValidation();
                    }
                }
            }
            made = tls;
#else
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "this build has no TLS - no OpenSSL on the target";
            return;
#endif
        }
#else   // Arduino
        else if (link == E_MQTTTRANSPORT::ARDUINOWIFI) {
#if defined(MQ_HAS_WIFI)
            // Nobody else can bring the radio up: an OpenPLC program has no
            // sketch to put a setup() in, so the client does it from the pins
            // stNetworkConfig supplies.
            if (stNetworkConfig.SSSID.length() > 0 && WiFi.status() != WL_CONNECTED) {
                WiFi.begin(stNetworkConfig.SSSID.c_str(),
                           stNetworkConfig.SWIFIPASSWORD.length() > 0 ? stNetworkConfig.SWIFIPASSWORD.c_str() : nullptr);
            }
            if (WiFi.status() != WL_CONNECTED) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTCONNECTED;
                sLastError = stNetworkConfig.SSSID.length() > 0
                    ? "joining the WiFi network"
                    : "set stNetworkConfig.sSsid";
                return;     // retried on this block's own timer
            }
            // The link itself - and what eSecurity a board can honour - is
            // mq_boardLink()'s.
            {
                E_MQTTRESULT refusedAs = E_MQTTRESULT::OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, sHost.c_str(), port,
                                    (int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT),
                                    sPinnedKey.c_str(), (bool)bTrustNew,
                                    &refusedAs, &refusal);
                if (!made) {
                    bError = true;
                    eErrorId = refusedAs;
                    sLastError = refusal;
                    return;
                }
                if (security == E_MQTTSECURITY::TLSPINNED &&
                    sPinnedKey.length() > 0) {
                    bPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "this board has no WiFi";
            return;
#endif
        } else if (link == E_MQTTTRANSPORT::ARDUINOETHERNET) {
#if defined(MQ_HAS_ETHERNET)
#if !MQTT_CHANNEL_TLS
            // Refused before DHCP, not after it: a board without the core's
            // mbedTLS has no TLS for an Ethernet chip. An ESP32 has - see
            // mq_boardLink().
            if (wantsTls) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL;
                sLastError = "TLS over Ethernet needs an ESP32, or SSLClient; use external";
                return;
            }
#endif
            // A fixed address, unless stNetworkConfig asked for DHCP. DHCP BLOCKS
            // - up to sixty seconds in the Arduino library, which on a 1 ms
            // task is not a delay, it is a stopped PLC. Bounded to one second
            // here and retried by this block's own timer instead.
            uint8_t mac[6] = {0};
            if (!mq_parseMac(stNetworkConfig.SMAC.c_str(), mac)) {
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                sLastError = "set stNetworkConfig.sMac - each board needs one";
                return;
            }
            if (stNetworkConfig.SIP.length() == 0 || strcmp(stNetworkConfig.SIP.c_str(), "dhcp") == 0) {
                if (Ethernet.begin(mac, 1000, 1000) == 0) {
                    bError = true;
                    eErrorId = E_MQTTRESULT::NOTCONNECTED;
                    sLastError = "no DHCP lease - set stNetworkConfig.sIp";
                    return;
                }
            } else {
                IPAddress ip;
                if (!ip.fromString(stNetworkConfig.SIP.c_str())) {
                    bError = true;
                    eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                    sLastError = "stNetworkConfig.sIp is not an address";
                    return;
                }
                Ethernet.begin(mac, ip);
            }
            {
                E_MQTTRESULT refusedAs = E_MQTTRESULT::OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, sHost.c_str(), port,
                                    (int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT),
                                    sPinnedKey.c_str(), (bool)bTrustNew,
                                    &refusedAs, &refusal);
                if (!made) {
                    bError = true;
                    eErrorId = refusedAs;
                    sLastError = refusal;
                    return;
                }
                if (security == E_MQTTSECURITY::TLSPINNED &&
                    sPinnedKey.length() > 0) {
                    bPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "define MQTT_ENABLE_ETHERNET to use Ethernet";
            return;
#endif
        } else if (link == E_MQTTTRANSPORT::CELLULAR) {
#if defined(MQ_HAS_CELLULAR)
            // The policy - which eSecurity a cellular link can honour, and
            // whose TLS it is - is mq_boardLink()'s.
            // Opening blocks - Arduino's Client::connect() must return a
            // verdict - so it is bounded by CONNECT_TIMEOUT, 20 s unset. It
            // blocks the connect task, not the scan.
            {
                E_MQTTRESULT refusedAs = E_MQTTRESULT::OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, sHost.c_str(), port,
                                    (int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT),
                                    sPinnedKey.c_str(), (bool)bTrustNew,
                                    &refusedAs, &refusal);
                if (!made) {
                    bError = true;
                    eErrorId = refusedAs;
                    sLastError = refusal;
                    return;
                }
                if (security == E_MQTTSECURITY::TLSPINNED &&
                    sPinnedKey.length() > 0) {
                    bPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "E_MqttTransport.Cellular needs a modbee-gsm modem block";
            return;
#endif
        } else {
            // Anything added later. Said plainly rather than silently doing
            // nothing.
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "this board has no such transport";
            return;
        }
#endif

        if (!made) {
            // Arduino cores build without exceptions, so an exhausted heap has
            // to be handled here or it is a hard fault. The client refuses to
            // start and says so; it does not take the PLC down.
            bError = true;
            eErrorId = E_MQTTRESULT::NOTINITIALISED;
            sLastError = "out of memory";
            return;
        }

        MqttConnectionConfig connection = buildConnection(made->host, port);

        if (client) {
            // A SETTINGS CHANGE THAT NEEDS ANOTHER MEDIUM - a new broker,
            // plain to TLS, Wi-Fi to cellular. The SAME client moves to it, so
            // every topic handle and subscription the other blocks hold stays
            // valid (see "ALREADY BUILT" above for why a second client would
            // be a quiet disaster), and the old medium is closed and freed.
            MqLink* old = client->link;
            client->link = made;
            client->client.rebind(made->clientTransport());
            client->client.reconfigure(connection);
            mq_dropLink(old);
            bRelink = false;
            bReconfigure = false;
        } else {

        MqNode* fresh = new (std::nothrow) MqNode();
        if (!fresh) {
            delete made;
            bError = true;
            eErrorId = E_MQTTRESULT::NOTINITIALISED;
            sLastError = "out of memory";
            return;
        }
        fresh->link = made;

        MqttClientConfig behaviour;
        if ((int32_t)stSessionConfig.NMAXPENDING > 0) {
            behaviour.queueCapacity = (size_t)(int32_t)stSessionConfig.NMAXPENDING;
        }
        if ((int32_t)stSessionConfig.NMAXMSGIN > 0) {
            behaviour.receiveBufferSize = (size_t)(int32_t)stSessionConfig.NMAXMSGIN;
        }
        if ((int32_t)stSessionConfig.NMAXMSGOUT > 0) {
            behaviour.transmitBufferSize = (size_t)(int32_t)stSessionConfig.NMAXMSGOUT;
        }
        if ((int32_t)mq_millisOf(stSessionConfig.TRECONNECT) > 0) {
            behaviour.reconnectInitialMs = (mq_time_t)(int32_t)mq_millisOf(stSessionConfig.TRECONNECT);
        }
        if ((int32_t)mq_millisOf(stSessionConfig.TRECONNECTMAX) > 0) {
            behaviour.reconnectMaximumMs = (mq_time_t)(int32_t)mq_millisOf(stSessionConfig.TRECONNECTMAX);
        }
        if ((int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT) > 0) {
            behaviour.connectTimeoutMs = (mq_time_t)(int32_t)mq_millisOf(stSessionConfig.TCONNECTTIMEOUT);
        }
        // stSessionConfig.tMaxSilence: nothing from the broker this long ends the
        // connection however our own bytes move (a modem says "sent" either way).
        if ((int32_t)mq_millisOf(stSessionConfig.TMAXSILENCE) > 0) {
            behaviour.maxSilenceMs = (mq_time_t)(int32_t)mq_millisOf(stSessionConfig.TMAXSILENCE);
        }
        behaviour.autoReconnect = (bool)stSessionConfig.BAUTORECONNECT;

        // OFF UNLESS stSessionConfig ASKED FOR IT. After a CONNACK that rejected
        // the credential the library does not retry at the network backoff -
        // a PLC repeating a rejected password every second is how a site gets
        // itself banned - but every five minutes, never giving up, so a remote
        // site whose broker is fixed at the other end comes back by itself.
        behaviour.retryRejectedCredentials = (bool)stSessionConfig.BRETRYREJECTEDCREDENTIAL;

        fresh->client.begin(fresh->link->clientTransport(), connection, behaviour);

        mqNodesOwned().all.push_back(fresh);
        nLink = (strucpp::XWORD_t)(uintptr_t)fresh;
        nApi = (strucpp::XWORD_t)(uintptr_t)&fresh->client;
        }   // end of the "first build" branch

        // What the link was built from, for the change check below.
        nMediumKey = mediumKey();
        nSessionKey = sessionKey();
        nWiFiKeyHash = wifiKey();
        }   // end of the "not already built" branch

        bLinkUp = true;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
        sLastError = "";
        client = (MqNode*)(uintptr_t)(strucpp::XWORD_t)nLink;
    }

    if (!client) return;

    // --- RECONNECT WHEN THE SETTINGS CHANGE ---
    //
    // The pins and the helper blocks are read every scan, and a client used to
    // take them once, when it was built: a broker address, a port, a login or
    // TLS changed on the HMI did nothing until the PLC was restarted. Now a
    // change says goodbye on the old settings and comes back on the new ones,
    // on the same client - the medium rebuilt when what it is made from
    // changed, the bConnect rewritten when only the session did.
    //
    // A PINNED KEY IS NOT FORGOTTEN BY A NEW ADDRESS. A different broker shows
    // a different key and is refused until bTrustNew is switched off and on,
    // exactly as a replaced broker is: an address typed on a panel must not be
    // a way round the pin.
    {
        const uint32_t medium = mediumKey();
        const uint32_t session = sessionKey();
        const uint32_t wifi = wifiKey();
        if (medium != (uint32_t)nMediumKey || session != (uint32_t)nSessionKey ||
            wifi != (uint32_t)nWiFiKeyHash) {
            const bool relink = medium != (uint32_t)nMediumKey ||
                                wifi != (uint32_t)nWiFiKeyHash;
#if defined(MQ_HAS_WIFI)
            // The Wi-Fi this block joined itself (stNetworkConfig's SSID) is left
            // and joined again with the new login. A radio NETWORK or anyone
            // else brought up is not this block's to drop.
            if (wifi != (uint32_t)nWiFiKeyHash && stNetworkConfig.SSSID.length() > 0 &&
                (E_MQTTTRANSPORT)eTransport == E_MQTTTRANSPORT::ARDUINOWIFI) {
                WiFi.disconnect();
            }
#endif
            nMediumKey = medium;
            nSessionKey = session;
            nWiFiKeyHash = wifi;
            bRelink = (bool)bRelink || relink;
            bReconfigure = true;
            nChangeAt = (int32_t)(uint32_t)mq_millis();
            if (client->client.isConnected()) {
                client->client.disconnect(mq_goodbyeReason(client->client));
            }
            client->client.poll();
            bLinkUp = false;
            bConnected = false;
            tHeardAgo = mq_timeOf(0);
            bConnectAsked = false;
            bTried = false;
            eConnectionState = (E_MQTTSTATE)(int32_t)(int)client->client.status().state;
            return;
        }
    }

    // Ask once. connect() queues the intent and returns; whether it arrived
    // is what bConnected answers on a later scan.
    if (!(bool)bConnectAsked) {
        const MqttResult asked = client->client.connect();
        bConnectAsked = true;
        if (!mq_tolerated(asked)) {
            bError = true;
            eErrorId = (E_MQTTRESULT)(int32_t)(int)asked;
            sLastError = "the broker could not be asked - see eErrorId";
        }
    }

    // Everything the protocol does happens here and nowhere else: the
    // handshake, the keepalive, the send queue, the receive path, reconnect.
    // A change of trust held while the connect task had the medium first.
    if (client->link != nullptr) client->link->settle();
    client->client.poll();

    const MqttStatus& status = client->client.status();
    // Connected with only a provisioning key is not connected as this PLC:
    // nothing it publishes would be allowed, so the program is told to wait.
    bConnected = client->client.isConnected() && !(bool)bProvisioning;
    tHeardAgo = mq_timeOf((int32_t)client->client.heardAgoMs());
    eConnectionState = (E_MQTTSTATE)(int32_t)(int)status.state;
    bSessionPresent = client->client.capabilities().sessionPresent;

    // The broker may assign one when we sent an empty identifier, and a
    // device that cannot report what it is called is a device nobody can find
    // in the broker's own logs.
    const MqttSpan& assigned = client->client.capabilities().assignedClientIdentifier;
    if (!assigned.empty()) {
        sAssignedId = std::string((const char*)assigned.data, assigned.length).c_str();
    } else {
        sAssignedId = sClientId.c_str();
    }

    // WHAT THE BROKER ACTUALLY PRESENTED, on a pin, whether or not anything is
    // pinned. An engineer commissioning a plant reads this off the panel and
    // writes it down; an engineer diagnosing one compares it with what they
    // wrote down last year. A fingerprint that can only be inferred is a
    // fingerprint nobody checks.
    if (client->link != nullptr) {
        const char* seen = client->link->seenKey();
        sBrokerKey = (seen != nullptr) ? seen : "";

        // --- bTrustNew, AND WHAT IT NOW MEANS ---
        //
        // Trust on first use, the way SSH does it. With bTrustNew on and
        // nothing stored, the first key the broker shows is learned and kept.
        // ONCE LEARNED IT IS ENFORCED, whether bTrustNew stays on or not, and
        // across restarts - so a bTrustNew left wired TRUE, which is what most
        // projects do, still protects the link after its first connection.
        //
        // A BROKER REPLACED ON PURPOSE is refused like any other: both
        // fingerprints on the Runtime, "TLS: not the pinned key" on a board,
        // with the key it showed on sBrokerKey. To accept it, switch bTrustNew
        // off and on: the rising
        // edge forgets the stored key, and the next connection learns its
        // replacement.
        //
        // THIS REPLACES A RULE THAT WAS NEVER TRUE. The block used to say a
        // reinstalled broker was "silently trusted" while bTrustNew was left
        // on. In fact the pin was enforced after any restart regardless, and
        // within a run it was never applied at all - so a new broker was let
        // in but its key was never stored, and the PLC then refused that same
        // broker after its next reboot. And there was no way for an operator
        // to accept a legitimately replaced broker short of a new program.
        const bool trusting = (bool)bTrustNew;
        if ((bool)bTrustSeen && trusting && !(bool)bLastTrust &&
            eSecurity == E_MQTTSECURITY::TLSPINNED) {
            sPinnedKey = "";
            bPinApplied = false;
            client->link->forget();
        }
        bLastTrust = trusting;
        bTrustSeen = true;

        if (bConnected && trusting &&
            eSecurity == E_MQTTSECURITY::TLSPINNED &&
            sPinnedKey.length() == 0 && seen != nullptr && *seen != '\0') {
            sPinnedKey = seen;
        }

        // APPLIED AS SOON AS IT IS KNOWN, including the key just learned on
        // the line above. Without this sPinnedKey is only a stored string and
        // the link was built before there was anything to put in it. See
        // MqLink::pinKey().
        if (!(bool)bPinApplied && sPinnedKey.length() > 0 &&
            eSecurity == E_MQTTSECURITY::TLSPINNED) {
            client->link->pin(sPinnedKey.c_str());
            bPinApplied = true;
        }
    }

    if (status.lastError != MqttResult::Ok && !bConnected) {
        bError = true;
        eErrorId = (E_MQTTRESULT)(int32_t)(int)status.lastError;

        // THE MOST RECENT ANSWER, BUILT FRESH EVERY SCAN.
        //
        // sLastError is an output, so it PERSISTS - and this used to only
        // overwrite it when it had something new to say. A pump whose account
        // was revoked during a broker restart failed its TLS handshakes while
        // the broker was down, and then was refused by the broker once it was
        // back - and its panel went on reading "TLS handshake failed: error
        // state on socket" for the rest of the day, because the credential
        // sentence below only ran when sLastError was empty, and it never was
        // again. The wrong fault, shown confidently, is worse than none.
        //
        // So: the CONNACK first. connectReasonCode is reset before every
        // attempt, so a refusal there IS the latest attempt's answer, and the
        // single most likely commissioning fault - a wrong password - is one
        // the transport cannot see at all: the TCP and TLS layers succeeded.
        std::string sentence = mq_connectRefusal(client->client);

        // Then THE eTransport'S OWN WORDS, which TLS is where they matter:
        //
        //   "the broker's key is not the pinned one: expected 60d2ab..., got
        //    15798e..." (the Runtime) or "TLS: not the pinned key" (a board)
        //   - the broker was reinstalled, or this is not the broker you
        //   think it is
        //   "certificate has expired"          - somebody has a date to fix
        //   "connection refused"               - nothing is listening
        //
        // Also current: every transport clears its lastError() when it starts
        // an attempt.
        if (sentence.empty() && client->link != nullptr) {
            const char* detail = client->link->reason();
            if (detail != nullptr) sentence = detail;
        }
        sLastError = sentence.c_str();
    } else if (bConnected) {
        bError = false;
        eErrorId = E_MQTTRESULT::OK;

        // AND THE REASON THE LAST ATTEMPT FAILED GOES WITH IT. A connected
        // link beside a sentence saying the broker refused the connection is
        // the log line nobody can act on: a fallback tries 5.0, is refused,
        // retries at 3.1.1 and succeeds, and the pin kept the refusal for
        // ever. bLinkUp and sLastError have to agree.
        sLastError = "";
    }

    // A method call that failed, by method and record (mq_noteCall), where the
    // link itself has nothing to report.
    if (const MqMethods* calls = (const MqMethods*)(uintptr_t)(strucpp::XWORD_t)nMethods) {
        if (!calls->failKey.empty() && !(bool)bError) {
            bError = true;
            eErrorId = static_cast<E_MQTTRESULT>(calls->failResult);
            sLastError = calls->failText.c_str();
        }
    }

    // The topic and subscription tables grow with the program, on a board and
    // the Runtime alike, and only memory ends them: when it did, that is
    // said, connected or not. The block that was refused shows
    // E_MQTTRESULT::QUEUEFULL on its own eErrorId.
    if (client->client.outOfMemory()) {
        sLastError = "out of memory for topics or subscriptions";
    }
    // MAX_PENDING is taken when the client is made; if the memory for it was
    // not there, the queue kept its size, and a PLC told it could hold more
    // than it does would lose data at the next outage without a word.
    if (client->client.queueOutOfMemory()) {
        char line[80];
        snprintf(line, sizeof line, "out of memory for MAX_PENDING - the queue holds %u",
                 (unsigned)client->client.operations().capacity());
        sLastError = line;
    }

    // stTlsConfig: a client certificate goes with its key.
    if ((stTlsConfig.SCERTFILE.length() > 0) != (stTlsConfig.SKEYFILE.length() > 0)) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = "stTlsConfig: sCertFile and sKeyFile go together";
    }
#if defined(MQTT_PLATFORM_HOST)
    // stNetworkConfig is a board's; the Runtime is on its machine's network.
    if (stNetworkConfig.SSSID.length() > 0 || stNetworkConfig.SMAC.length() > 0) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = "stNetworkConfig is for a board; the Runtime uses its machine's network";
    }
#endif

    // stWillConfig: 'online' on every connection; the broker sends the Will
    // ('offline') when this device is gone. Sparkplug carries its own Will
    // (its death certificate), so the two do not share a client.
    if (stWillConfig.STOPIC.length() > 0) {
        if (client->client.willOwner() != nullptr) {
            bError = true;
            eErrorId = E_MQTTRESULT::REFUSED;
            sLastError = "the Will is Sparkplug's on this client: leave stWillConfig.sTopic empty";
        } else if (client->client.isConnected() &&
                   (int32_t)client->client.status().connects != (int32_t)nWillConnects) {
            const char* text = stWillConfig.SONLINE.length() > 0 ? stWillConfig.SONLINE.c_str() : "online";
            const MqttResult sent = client->client.publish(stWillConfig.STOPIC.c_str(), text,
                                                           (uint8_t)(int)(E_MQTTQOS)stWillConfig.EQOS,
                                                           (bool)stWillConfig.BRETAIN);
            if (mq_tolerated(sent)) {
                nWillConnects = (int32_t)client->client.status().connects;
            } else {
                bError = true;
                eErrorId = (E_MQTTRESULT)(int32_t)(int)sent;
            }
        }
    }
}

// =============================================================================
// THE METHODS
// =============================================================================
//
// Each runs in the caller's task and is refused in any other (one task per
// client). The record is found first, so a call that cannot go yet still
// keeps its record.

E_MQTTRESULT Publish()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_PUBLISH, anyValue, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);

        const bool execute = (bool)bExecute;
        const bool rising = execute && !r->lastExecute;
        r->lastExecute = execute;

        // Outcomes are running totals on the topic, so none is missed however
        // seldom this is called.
        if (r->pending) {
            if (client == nullptr || !(bool)bLinkUp) {
                r->pending = false;
                r->result = E_MQTTRESULT::NOTCONNECTED;
            } else {
                const MqttTopicState& state = client->topicState((MqttTopicHandle)r->handle);
                if (state.published != r->seenOk) {
                    r->pending = false;
                    r->result = E_MQTTRESULT::OK;
                } else if (state.failed != r->seenFail) {
                    r->pending = false;
                    r->result = (E_MQTTRESULT)(int32_t)(int)state.lastResult;
                }
            }
        }
        if (!rising || r->pending) return r->result;

        // A start: the inputs as they are now.
        if (client == nullptr || !(bool)bConnected) {
            r->result = E_MQTTRESULT::NOTCONNECTED;
            return r->result;
        }
        r->topic = sTopic.c_str();
        const MqttTopicHandle handle = mq_handleFor(client, r->handle, r->topic.c_str(), nullptr);
        if (handle == MQTT_TOPIC_HANDLE_NONE) {
            r->result = E_MQTTRESULT::QUEUEFULL;
            return r->result;
        }
        char payload[512];
        const size_t length = mq_formatAny(anyValue, payload, sizeof payload);
        if (length == 0 && !mq_isEmptyText(anyValue)) {
            r->result = E_MQTTRESULT::INVALIDARGUMENT;
            return r->result;
        }
        const MqttResult asked = client->publishTo(handle, (const uint8_t*)payload, length,
                                                   mq_qosOf((E_MQTTQOS)eQos), (bool)bRetain);
        if (!mq_tolerated(asked)) {
            r->result = (E_MQTTRESULT)(int32_t)(int)asked;
            return r->result;
        }
        const MqttTopicState& state = client->topicState(handle);
        r->seenOk = state.published;
        r->seenFail = state.failed;
        r->pending = true;
        r->result = E_MQTTRESULT::QUEUED;
        return r->result;
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Publish", &anyValue, sTopic.c_str(), result);
}

E_MQTTRESULT Report()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_REPORT, anyValue, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            nSent = r->sent;
            tAge = mq_timeOf(r->ageMs);
            return result;
        };

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) return done(E_MQTTRESULT::NOTCONNECTED);

        const mq_time_t now = mq_millis();
        if (r->ever) r->ageMs = (int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now);

        // The edge is taken whether enabled or not: a bExecute raised while
        // disabled does not fire on enabling.
        const bool execute = (bool)bExecute;
        const bool asked = execute && !r->lastExecute;
        r->lastExecute = execute;

        if (!(bool)bEnable) return done(E_MQTTRESULT::OK);

        bool changed = false;
        const MqttTopicHandle handle = mq_handleFor(client, r->handle, sTopic.c_str(), &changed);
        if (handle == MQTT_TOPIC_HANDLE_NONE) return done(E_MQTTRESULT::QUEUEFULL);
        if (changed) r->hasLast = false;   // a new topic: its first value always goes

        char payload[512];
        const size_t length = mq_formatAny(anyValue, payload, sizeof payload);
        if (length == 0 && !mq_isEmptyText(anyValue)) return done(E_MQTTRESULT::INVALIDARGUMENT);

        const E_MQTTTRIGGER trigger = (E_MQTTTRIGGER)eTrigger;
        const int32_t intervalMs = mq_millisOf(tPeriod);
        // ChangedEvery is the Sparkplug node's.
        if (trigger == E_MQTTTRIGGER::CHANGEDEVERY) return done(E_MQTTRESULT::INVALIDARGUMENT);

        bool due = false;
        if (trigger == E_MQTTTRIGGER::ONREQUEST) {
            due = asked;
        } else if (trigger == E_MQTTTRIGGER::ONINTERVAL) {
            // No interval is refused, never taken as every scan.
            if (intervalMs <= 0) return done(E_MQTTRESULT::INVALIDARGUMENT);
            due = !r->ever ||
                  (int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now) >= intervalMs;
        } else {
            due = !r->hasLast;
            double number = 0.0;
            const bool numeric = mq_numberOf(anyValue, &number);
            if (!due) {
                if (numeric) {
                    double moved = number - r->last;
                    if (moved < 0) moved = -moved;
                    // 0 is any change: `moved >= 0` held for an unchanged value too.
                    due = (double)fDeadband > 0.0 ? moved >= (double)fDeadband : moved > 0.0;
                } else {
                    due = mq_fingerprint(payload, length) != r->lastHash;
                }
            }
            // The heartbeat: an unchanged value still goes every tPeriod.
            if (!due && intervalMs > 0 && r->ever) {
                due = (int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now) >= intervalMs;
            }
        }
        if (!due) return done(E_MQTTRESULT::OK);

        const MqttResult sent = client->publishTo(handle, (const uint8_t*)payload, length,
                                                  mq_qosOf((E_MQTTQOS)eQos), (bool)bRetain);
        if (!mq_tolerated(sent)) return done((E_MQTTRESULT)(int32_t)(int)sent);

        double shadow = 0.0;
        mq_numberOf(anyValue, &shadow);
        r->hasLast = true;
        r->last = shadow;
        r->lastHash = mq_fingerprint(payload, length);
        r->at = (int32_t)(uint32_t)now;
        r->ever = true;
        r->ageMs = 0;
        r->sent++;
        return done(E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Report", &anyValue, sTopic.c_str(), result);
}

E_MQTTRESULT Subscribe()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        bNewValue = false;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_SUBSCRIBE, anyValue, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            bSubscribed = r->subscribed;
            eQuality = r->quality;
            bSeen = r->ever;
            tAge = mq_timeOf(r->ageMs);
            nReceived = r->received;
            nMalformed = r->malformed;
            return result;
        };

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) {
            r->subscribed = false;
            r->quality = mq_qualityOf(r->ever, false, r->ageMs, mq_millisOf(tExpect));
            return done(E_MQTTRESULT::NOTCONNECTED);
        }

        const mq_time_t now = mq_millis();
        if (r->ever) r->ageMs = (int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now);

        const char* topic = sTopic.c_str();
        bool changed = false;
        const MqttTopicHandle handle = mq_handleFor(client, r->handle, topic, &changed);
        if (handle == MQTT_TOPIC_HANDLE_NONE) return done(E_MQTTRESULT::QUEUEFULL);
        if (changed) {
            // A different topic is a different subscription: UNKNOWN until it
            // speaks, never the last topic's freshness.
            r->asked = false;
            r->ever = false;
            r->at = 0;
            r->ageMs = -1;
            r->quality = E_MQTTQUALITY::UNKNOWN;
        }

        if (!(bool)bEnable) {
            if (r->asked) {
                client->unsubscribe(topic);
                r->asked = false;
            }
            r->subscribed = false;
            return done(E_MQTTRESULT::OK);
        }

        // A fresh session needs the subscription again; the library re-issues it
        // only where the broker kept nothing, and the counter cannot be missed.
        const int32_t connects = (int32_t)client->status().connects;
        if (connects != r->seenConnects) {
            r->seenConnects = connects;
            r->asked = false;
        }
        if (!r->asked && client->isConnected()) {
            const MqttResult asked = client->subscribeTo(handle, mq_qosOf((E_MQTTQOS)eQos));
            if (!mq_tolerated(asked)) return done((E_MQTTRESULT)(int32_t)(int)asked);
            r->asked = true;
        }
        r->subscribed = r->asked && client->isConnected();

        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            if (mq_parseAny((const char*)buffer, length, anyValue)) {
                r->received++;
                r->at = (int32_t)(uint32_t)now;
                r->ever = true;
                r->ageMs = 0;
                bNewValue = true;
            } else {
                r->malformed++;
            }
        }

        r->quality = mq_qualityOf(r->ever, client->isConnected(), r->ageMs, mq_millisOf(tExpect));
        return done(E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Subscribe", &anyValue, sTopic.c_str(), result);
}

E_MQTTRESULT Statistics()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
    if (client == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    // Counted across outages: the reconnects are worth reading most while the link is down.
    const MqttStatus& s = client->status();
    nVersion = (uint8_t)s.version;
    nConnects = (int32_t)s.connects;
    nDisconnects = (int32_t)s.disconnects;
    nReconnects = (int32_t)s.reconnects;
    nPublished = (int32_t)s.published;
    nReceived = (int32_t)s.received;
    nPublishFailures = (int32_t)s.publishFailures;
    nProtocolErrors = (int32_t)s.protocolErrors;
    nPending = (int32_t)client->operations().pending();
    nReasonCode = s.lastReasonCode;
    return (bool)bLinkUp ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;
}

// A STRUCT record's member table, made again for a new base or a first bind.
static bool mq_bindMembers(MqRecord* r, const char* base, uint16_t count) {
    if (r->members != nullptr && r->topic == base) return true;
    delete[] r->members;
    r->members = new (std::nothrow) MqMember[count ? count : 1];
    r->memberCount = r->members ? count : (uint16_t)0;
    if (r->members == nullptr) return false;
    r->topic = base;
    return true;
}

E_MQTTRESULT PublishStruct()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        nChanged = 0;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_PUBLISH_STRUCT, anyData, sBase.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            nPoints = r->points;
            nSkipped = r->skipped;
            nSent = r->sent;
            return result;
        };

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) return done(E_MQTTRESULT::NOTCONNECTED);

        const strucpp::TypeDesc* layout = anyData.TYPEDESC;
        if (anyData.TYPECLASS != strucpp::TYPE_USERDEF || !layout || !anyData.PVALUE) {
            r->points = 0;
            return done(E_MQTTRESULT::INVALIDARGUMENT);
        }
        // A different base is a different set of topics: nothing carries over.
        if (!mq_bindMembers(r, sBase.c_str(), layout->MEMBERCOUNT)) {
            return done(E_MQTTRESULT::QUEUEFULL);
        }

        const bool execute = (bool)bExecute;
        const bool asked = execute && !r->lastExecute;
        r->lastExecute = execute;

        if (!(bool)bEnable) return done(E_MQTTRESULT::OK);

        const int32_t intervalMs = mq_millisOf(tPeriod);
        const E_MQTTTRIGGER trigger = (E_MQTTTRIGGER)eTrigger;
        if ((trigger == E_MQTTTRIGGER::ONINTERVAL && intervalMs <= 0) ||
            trigger == E_MQTTTRIGGER::CHANGEDEVERY) {
            return done(E_MQTTRESULT::INVALIDARGUMENT);
        }

        uint8_t* base = anyData.PVALUE;
        const mq_time_t now = mq_millis();
        // OnInterval and OnRequest send the whole set together.
        const bool sendAll =
            trigger == E_MQTTTRIGGER::ONREQUEST
                ? asked
                : (trigger == E_MQTTTRIGGER::ONINTERVAL &&
                   (!r->ever || (int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now) >= intervalMs));

        int published = 0, refused = 0;
        MqttResult worst = MqttResult::Ok;
        MqMember* table = r->members;
        const uint16_t count = layout->MEMBERCOUNT < r->memberCount ? layout->MEMBERCOUNT : r->memberCount;
        const uint8_t qos = mq_qosOf((E_MQTTQOS)eQos);

        for (uint16_t i = 0; i < count; i++) {
            const strucpp::MemberDesc& member = layout->MEMBERS[i];
            // A member the wire cannot carry is refused by name, never skipped quietly.
            if (!mq_memberIsPublishable(member)) {
                refused++;
                if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
                continue;
            }
            strucpp::IEC_ANY any;
            if (!mq_memberAsAny(member, base, &any)) { refused++; continue; }

            char payload[512];
            const size_t length = mq_formatAny(any, payload, sizeof payload);
            if (length == 0 && !mq_isEmptyText(any)) {
                refused++;
                if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
                continue;
            }
            published++;

            double number = 0.0;
            const bool numeric = mq_numberOf(any, &number);
            const uint32_t hash = mq_fingerprint(payload, length);

            bool due;
            if (trigger == E_MQTTTRIGGER::ONCHANGE) {
                due = !table[i].hasLast;
                // Against what was last published, so a slow drift still goes.
                if (!due) due = numeric ? number != table[i].last : hash != table[i].hash;
                if (!due && intervalMs > 0 && table[i].hasLast) {
                    due = (int32_t)mq_elapsed((mq_time_t)(uint32_t)table[i].sentAt, now) >= intervalMs;
                }
            } else {
                due = sendAll;
            }
            if (!due) continue;

            char topic[256];
            if (!mq_memberTopic(sBase.c_str(), member.NAME, topic, sizeof topic)) {
                refused++;
                if (worst == MqttResult::Ok) worst = MqttResult::InvalidTopic;
                continue;
            }
            const MqttResult sent = client->publish(topic, (const uint8_t*)payload, length, qos,
                                                    (bool)bRetain);
            if (!mq_tolerated(sent)) {
                if (worst == MqttResult::Ok) worst = sent;
                continue;
            }
            table[i].hasLast = true;
            table[i].last = number;
            table[i].hash = hash;
            table[i].sentAt = (int32_t)(uint32_t)now;
            r->ever = true;
            r->sent++;
            nChanged = (int16_t)((int16_t)nChanged + 1);
        }
        if (sendAll) r->at = (int32_t)(uint32_t)now;

        r->points = (int16_t)published;
        r->skipped = (int16_t)refused;
        return done(worst != MqttResult::Ok ? (E_MQTTRESULT)(int32_t)(int)worst : E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "PublishStruct", &anyData, sBase.c_str(), result);
}

E_MQTTRESULT SubscribeStruct()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        nNewValues = 0;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_SUBSCRIBE_STRUCT, anyData, sBase.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            nPoints = r->points;
            nSkipped = r->skipped;
            bSubscribed = r->subscribed;
            eQuality = r->quality;
            bSeen = r->ever;
            tOldest = mq_timeOf(r->ageMs);
            nReceived = r->received;
            nMalformed = r->malformed;
            return result;
        };

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) {
            r->subscribed = false;
            r->quality = E_MQTTQUALITY::BAD;
            return done(E_MQTTRESULT::NOTCONNECTED);
        }

        const strucpp::TypeDesc* layout = anyData.TYPEDESC;
        if (anyData.TYPECLASS != strucpp::TYPE_USERDEF || !layout || !anyData.PVALUE) {
            r->points = 0;
            r->subscribed = false;
            return done(E_MQTTRESULT::INVALIDARGUMENT);
        }
        const bool rebind = r->members == nullptr || r->topic != sBase.c_str();
        if (!mq_bindMembers(r, sBase.c_str(), layout->MEMBERCOUNT)) {
            r->subscribed = false;
            return done(E_MQTTRESULT::QUEUEFULL);
        }
        if (rebind) {
            r->ageMs = -1;
            r->ever = false;
            r->quality = E_MQTTQUALITY::UNKNOWN;
            r->asked = false;
        }

        const int32_t connects = (int32_t)client->status().connects;
        if (connects != r->seenConnects) {
            r->seenConnects = connects;
            r->asked = false;
        }

        uint8_t* base = anyData.PVALUE;
        const mq_time_t now = mq_millis();
        MqMember* table = r->members;
        const uint16_t count = layout->MEMBERCOUNT < r->memberCount ? layout->MEMBERCOUNT : r->memberCount;
        const bool enabled = (bool)bEnable;
        const uint8_t qos = mq_qosOf((E_MQTTQOS)eQos);
        const int32_t expectMs = mq_millisOf(tExpect);

        int bound = 0, refused = 0;
        bool allAsked = true;
        MqttResult worst = MqttResult::Ok;
        // The worst quality and the oldest age across the set: one stale member
        // makes the set stale.
        E_MQTTQUALITY worstQuality = E_MQTTQUALITY::GOOD;
        int32_t oldest = 0;
        bool anyNever = false;

        for (uint16_t i = 0; i < count; i++) {
            const strucpp::MemberDesc& member = layout->MEMBERS[i];
            if (!mq_memberIsPublishable(member)) {
                refused++;
                if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
                continue;
            }
            strucpp::IEC_ANY any;
            if (!mq_memberAsAny(member, base, &any)) { refused++; continue; }

            char topic[256];
            if (!mq_memberTopic(sBase.c_str(), member.NAME, topic, sizeof topic)) {
                refused++;
                if (worst == MqttResult::Ok) worst = MqttResult::InvalidTopic;
                continue;
            }
            MqttTopicHandle handle = (MqttTopicHandle)table[i].handle;
            if (handle < 0) {
                handle = client->registerTopic(topic);
                if (handle == MQTT_TOPIC_HANDLE_NONE) {
                    refused++;
                    allAsked = false;
                    if (worst == MqttResult::Ok) worst = MqttResult::QueueFull;
                    continue;
                }
                table[i].handle = (int16_t)handle;
            }
            bound++;

            if (!enabled) {
                client->unsubscribe(topic);
                allAsked = false;
                continue;
            }
            if (!r->asked && client->isConnected()) {
                const MqttResult asked = client->subscribeTo(handle, qos);
                if (!mq_tolerated(asked)) {
                    allAsked = false;
                    if (worst == MqttResult::Ok) worst = asked;
                }
            }

            uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
            size_t length = 0;
            while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
                if (mq_parseAny((const char*)buffer, length, any)) {
                    r->received++;
                    table[i].arrivedAt = (int32_t)(uint32_t)now;
                    table[i].ever = true;
                    nNewValues = (int16_t)((int16_t)nNewValues + 1);
                } else {
                    r->malformed++;
                }
            }

            const int32_t age = table[i].ever
                ? (int32_t)mq_elapsed((mq_time_t)(uint32_t)table[i].arrivedAt, now) : 0;
            if (!table[i].ever) anyNever = true;
            else if (age > oldest) oldest = age;
            const E_MQTTQUALITY q = mq_qualityOf(table[i].ever, client->isConnected(), age, expectMs);
            if ((int)q < (int)worstQuality) worstQuality = q;
        }

        if (enabled && allAsked && client->isConnected()) r->asked = true;

        r->points = (int16_t)bound;
        r->skipped = (int16_t)refused;
        r->subscribed = enabled && r->asked && client->isConnected();
        r->ageMs = anyNever ? 0 : oldest;
        r->ever = bound > 0 && !anyNever;
        r->quality = bound == 0 ? E_MQTTQUALITY::UNKNOWN : worstQuality;
        return done(worst != MqttResult::Ok ? (E_MQTTRESULT)(int32_t)(int)worst : E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "SubscribeStruct", &anyData, sBase.c_str(), result);
}

E_MQTTRESULT Message()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        bNewMessage = false;
        if (anyPayload.TYPECLASS != strucpp::TYPE_STRING || !anyPayload.wired()) {
            return E_MQTTRESULT::INVALIDARGUMENT;
        }
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_MESSAGE, anyPayload, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            nLen = (int16_t)r->length;
            bTruncated = r->truncated;
            nReceived = r->received;
            return result;
        };

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) return done(E_MQTTRESULT::NOTCONNECTED);

        const char* topic = sTopic.c_str();
        bool changed = false;
        const MqttTopicHandle handle = mq_handleFor(client, r->handle, topic, &changed);
        if (handle == MQTT_TOPIC_HANDLE_NONE) return done(E_MQTTRESULT::QUEUEFULL);
        if (changed) r->asked = false;

        if (!(bool)bEnable) {
            if (r->asked) {
                client->unsubscribe(topic);
                r->asked = false;
            }
            return done(E_MQTTRESULT::OK);
        }

        const int32_t connects = (int32_t)client->status().connects;
        if (connects != r->seenConnects) {
            r->seenConnects = connects;
            r->asked = false;
        }
        if (!r->asked && client->isConnected()) {
            const MqttResult asked = client->subscribeTo(handle, mq_qosOf((E_MQTTQOS)eQos));
            if (!mq_tolerated(asked)) return done((E_MQTTRESULT)(int32_t)(int)asked);
            r->asked = true;
        }

        // One message per call: a payload is presented, not folded into a value,
        // so a backlog drained at once would show only its last message.
        if (client->topics().hasMessage(handle)) {
            uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
            size_t length = 0;
            if (client->takeMessage(handle, buffer, sizeof buffer, length)) {
                // Cut by the client's buffer, or by the variable's declared width.
                const bool cutByRegistry = client->topicState(handle).truncated;
                const size_t width = (size_t)anyPayload.DISIZE;
                const size_t shown = length < width ? length : width;
                mq_parseAny((const char*)buffer, shown, anyPayload);
                r->length = (int32_t)shown;
                r->truncated = cutByRegistry || shown != length;
                r->received++;
                bNewMessage = true;
            }
        }
        return done(E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Message", &anyPayload, sTopic.c_str(), result);
}

E_MQTTRESULT Request()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_REQUEST, anyValue, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&]() -> E_MQTTRESULT {
            sReply = r->reply.c_str();
            nReplyLen = (int16_t)r->reply.size();
            return r->result;
        };
        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);

        const bool execute = (bool)bExecute;
        const bool rising = execute && !r->lastExecute;
        r->lastExecute = execute;

        if (client == nullptr || !(bool)bLinkUp) {
            if (rising) r->reply.clear();
            if (r->pending || rising) {
                r->pending = false;
                r->result = E_MQTTRESULT::NOTCONNECTED;
            }
            return done();
        }

        // The reply topic is subscribed and kept, so an answer cannot arrive
        // before anyone listens. Latched while a request waits.
        const std::string replyTopic = r->pending ? r->replyTopic : std::string(sReplyTopic.c_str());
        MqttTopicHandle reply = MQTT_TOPIC_HANDLE_NONE;
        if (!replyTopic.empty()) {
            bool changed = false;
            reply = mq_handleFor(client, r->replyHandle, replyTopic.c_str(), &changed);
            if (changed) r->asked = false;
        }
        if (reply != MQTT_TOPIC_HANDLE_NONE) {
            const int32_t connects = (int32_t)client->status().connects;
            if (connects != r->seenConnects) {
                r->seenConnects = connects;
                r->asked = false;
            }
            if (!r->asked && client->isConnected()) {
                if (mq_tolerated(client->subscribeTo(reply, mq_qosOf((E_MQTTQOS)eQos)))) r->asked = true;
            }
        }

        const mq_time_t now = mq_millis();
        if (r->pending) {
            uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
            size_t length = 0;
            if (reply == MQTT_TOPIC_HANDLE_NONE) {
                r->pending = false;
                r->result = E_MQTTRESULT::QUEUEFULL;
            } else if (client->takeMessage(reply, buffer, sizeof buffer, length)) {
                // As wide as sReply.
                const size_t shown = length > 254 ? 254 : length;
                r->reply.assign((const char*)buffer, shown);
                r->pending = false;
                r->result = E_MQTTRESULT::OK;
            } else if ((int32_t)mq_elapsed((mq_time_t)(uint32_t)r->at, now) >= r->limitMs) {
                // Unanswered: said, so a sequence waiting on it does not hang.
                r->pending = false;
                r->result = E_MQTTRESULT::KEEPALIVETIMEOUT;
            }
            return done();
        }
        if (!rising) return done();

        // A start: the inputs as they are now, the outputs cleared.
        r->reply.clear();
        if (!(bool)bConnected) {
            r->result = E_MQTTRESULT::NOTCONNECTED;
            return done();
        }
        if (replyTopic.empty()) {
            r->result = E_MQTTRESULT::INVALIDTOPIC;
            return done();
        }
        if (reply == MQTT_TOPIC_HANDLE_NONE) {
            r->result = E_MQTTRESULT::QUEUEFULL;
            return done();
        }
        // Refused rather than sent stripped: without Response Topic the responder
        // has nowhere to answer.
        if (client->status().version != MqttVersion::V5) {
            r->result = E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL;
            return done();
        }
        char payload[512];
        const size_t length = mq_formatAny(anyValue, payload, sizeof payload);
        if (length == 0 && !mq_isEmptyText(anyValue)) {
            r->result = E_MQTTRESULT::INVALIDARGUMENT;
            return done();
        }

        // Counted, not random: a PLC has no entropy at start-up, and a counter
        // tells this record's questions apart.
        r->correlation++;
        char correlation[16];
        snprintf(correlation, sizeof correlation, "%ld", (long)r->correlation);
        MqttOwnedProperties properties;
        properties.setResponseTopic(replyTopic.c_str());
        properties.setCorrelationData(correlation);
        properties.setPayloadFormat(true);

        const MqttResult asked = client->publish(sTopic.c_str(), (const uint8_t*)payload, length,
                                                 mq_qosOf((E_MQTTQOS)eQos), false, properties);
        if (!mq_tolerated(asked)) {
            r->result = (E_MQTTRESULT)(int32_t)(int)asked;
            return done();
        }
        const int32_t ms = mq_millisOf(tTimeout);
        r->limitMs = ms > 0 ? ms : 5000;
        r->replyTopic = replyTopic;
        r->pending = true;
        r->at = (int32_t)(uint32_t)now;
        r->result = E_MQTTRESULT::QUEUED;
        return done();
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Request", &anyValue, sTopic.c_str(), result);
}

E_MQTTRESULT Response()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        bNewRequest = false;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        MqRecord* r = mq_recordOf(m, MQ_REC_RESPONSE, anyRequest, sTopic.c_str());
        if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
        auto done = [&](E_MQTTRESULT result) -> E_MQTTRESULT {
            bAwaitingReply = r->answerable;
            sResponseTopic = r->replyTopic.c_str();
            nReceived = r->received;
            nMalformed = r->malformed;
            return result;
        };

        const bool execute = (bool)bExecute;
        const bool rising = execute && !r->lastExecute;
        r->lastExecute = execute;

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr || !(bool)bLinkUp) return done(E_MQTTRESULT::NOTCONNECTED);
        // The request's properties reach the record through the hook.
        client->attach(m->hook);

        const char* topic = sTopic.c_str();
        bool changed = false;
        const MqttTopicHandle handle = mq_handleFor(client, r->handle, topic, &changed);
        if (handle == MQTT_TOPIC_HANDLE_NONE) return done(E_MQTTRESULT::QUEUEFULL);
        if (changed || r->topic != topic) {
            r->topic = topic;
            r->asked = false;
            r->answerable = false;
            r->replyTopic.clear();
            r->correlationData.clear();
        }

        if (!(bool)bEnable) {
            if (r->asked) {
                client->unsubscribe(topic);
                r->asked = false;
            }
            return done(E_MQTTRESULT::OK);
        }

        const int32_t connects = (int32_t)client->status().connects;
        if (connects != r->seenConnects) {
            r->seenConnects = connects;
            r->asked = false;
        }
        const uint8_t qos = mq_qosOf((E_MQTTQOS)eQos);
        if (!r->asked && client->isConnected()) {
            const MqttResult asked = client->subscribeTo(handle, qos);
            if (!mq_tolerated(asked)) return done((E_MQTTRESULT)(int32_t)(int)asked);
            r->asked = true;
        }

        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            r->received++;
            bNewRequest = true;
            if (anyRequest.wired() && !mq_parseAny((const char*)buffer, length, anyRequest)) {
                r->malformed++;
            }
        }

        if (!rising) return done(E_MQTTRESULT::OK);

        // The answer: to the last request's Response Topic, quoting its
        // Correlation Data. Once per request.
        if (client->status().version != MqttVersion::V5) {
            return done(E_MQTTRESULT::NOTSUPPORTEDBYPROTOCOL);
        }
        if (!client->isConnected()) return done(E_MQTTRESULT::NOTCONNECTED);
        if (!r->answerable) return done(E_MQTTRESULT::INVALIDTOPIC);
        char payload[512];
        const size_t replyLength = mq_formatAny(anyReply, payload, sizeof payload);
        if (replyLength == 0 && !mq_isEmptyText(anyReply)) return done(E_MQTTRESULT::INVALIDARGUMENT);

        MqttOwnedProperties properties;
        if (!r->correlationData.empty()) {
            properties.setCorrelationData(r->correlationData.data(), r->correlationData.size());
        }
        properties.setPayloadFormat(true);
        const MqttResult sent = client->publish(r->replyTopic.c_str(), (const uint8_t*)payload,
                                                replyLength, qos, false, properties);
        if (!mq_tolerated(sent)) return done((E_MQTTRESULT)(int32_t)(int)sent);
        r->answerable = false;
        return done(E_MQTTRESULT::OK);
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Response", &anyRequest, sTopic.c_str(), result);
}

E_MQTTRESULT Provision()
{
    const E_MQTTRESULT result = [&]() -> E_MQTTRESULT {
        // What the key handed this PLC, as kept: valid before the first connect,
        // so a Sparkplug node's Will is on the right group from the start.
        sGroup = sProvGroup.c_str();
        sPrefix = sProvPrefix.c_str();
        if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
        MqMethods* m = mq_methodsFor((strucpp::XWORD_t)nMethods, (strucpp::XWORD_t)nApi);
        nMethods = (strucpp::XWORD_t)(uintptr_t)m;
        if (m == nullptr) return E_MQTTRESULT::QUEUEFULL;
        MqProvision& p = m->provision;
        auto done = [&]() -> E_MQTTRESULT {
            bProvisioned = p.provisioned;
            bPending = p.waiting;
            bRefused = p.refused;
            sUserName = p.userName.c_str();
            sGroup = sProvGroup.c_str();
            sPrefix = sProvPrefix.c_str();
            sReason = p.reason.c_str();
            return p.status;
        };
        const mq_time_t now = mq_millis();

        if (sClientId.length() == 0) {
            p.status = E_MQTTRESULT::INVALIDARGUMENT;
            p.reason = "set sClientId - it is this PLC's name";
            return done();
        }
        const bool haveLogin = sProvLoginUser.length() > 0 && sProvLoginSecret.length() > 0;
        if (!haveLogin && sKey.length() == 0) {
            p.status = E_MQTTRESULT::INVALIDARGUMENT;
            p.reason = "set sKey - from `modbee key create` on the broker";
            return done();
        }

        // bForget's rising edge - not at program start, where one wired TRUE
        // would throw the login away on every reboot.
        const bool forget = (bool)bForget;
        if (p.forgetSeen && forget && !p.lastForget) {
            sProvLoginUser = "";
            sProvLoginSecret = "";
            if ((bool)bLinkUp) p.switchTo = 2;
        }
        p.lastForget = forget;
        p.forgetSeen = true;

        // Before the client builds its link: which login it uses.
        if (!(bool)bLinkUp) {
            const bool stored = sProvLoginUser.length() > 0 && sProvLoginSecret.length() > 0;
            if (stored) {
                sProvUser = sProvLoginUser.c_str();
                sProvPassword = sProvLoginSecret.c_str();
            } else {
                sProvUser = "$provision";
                sProvPassword = sKey.c_str();
            }
            p.usingKey = !stored;
            p.withoutWill = false;
            bProvisioning = !stored;
            p.provisioned = false;
            p.userName = stored ? sProvLoginUser.c_str() : "";
            return done();
        }

        MqttClient* client = mq_clientOf((strucpp::XWORD_t)nApi);
        if (client == nullptr) return done();

        // Changing logins on the SAME client, which every record's handles are
        // into: down first, then the new login, then up.
        if (p.switchTo != 0) {
            if (client->isConnected()) {
                if (!p.switchClosed) {
                    client->disconnect();
                    p.switchClosed = true;
                }
            } else if (client->state() == MqttState::Idle || client->state() == MqttState::Reconnecting) {
                const bool toKey = p.switchTo == 2;
                const bool withoutWill = p.switchTo == 3;
                MqttConnectionConfig c = client->connection();
                c.hasUserName = true;
                c.hasPassword = true;
                // With the key, or the login only asking again: a session without
                // the node's Will (registration).
                c.registration = toKey || withoutWill;
                if (toKey) {
                    c.userName = "$provision";
                    c.password.assign(sKey.c_str(), sKey.c_str() + sKey.length());
                } else {
                    c.userName = std::string(sProvLoginUser.c_str(), sProvLoginUser.length());
                    c.password.assign(sProvLoginSecret.c_str(),
                                      sProvLoginSecret.c_str() + sProvLoginSecret.length());
                }
                client->reconfigure(c);
                client->connect();
                p.usingKey = toKey;
                p.withoutWill = withoutWill;
                // Holds the rest of the program off a session that only asks.
                bProvisioning = toKey || withoutWill;
                p.switchTo = 0;
                p.switchClosed = false;
                p.asked = false;
            }
        }

        const uint8_t refusal = client->status().connectReasonCode;
        const bool v311 = client->activeVersion() == MqttVersion::V311;
        const bool badLogin = !client->isConnected() &&
                              (refusal == MQ_REASON_BAD_USER_NAME_OR_PASSWORD ||
                               (v311 && refusal == MQ_RETURN_BAD_CREDENTIALS));
        const bool notAuthorized = !client->isConnected() &&
                                   (refusal == MQ_REASON_NOT_AUTHORIZED ||
                                    (v311 && refusal == MQ_RETURN_NOT_AUTHORIZED));

        // The reply topic, kept registered: the key's answer, or the login's
        // when it asks again.
        const std::string id(sClientId.c_str(), sClientId.length());
        const std::string base = "$modbee/provision/" + id;
        const std::string replyTopic = base + "/reply";
        bool changed = false;
        const MqttTopicHandle handle = mq_handleFor(client, p.handle, replyTopic.c_str(), &changed);
        if (handle == MQTT_TOPIC_HANDLE_NONE) {
            p.status = E_MQTTRESULT::QUEUEFULL;
            p.reason = "no topic slot left on the client";
            return done();
        }
        if (changed) p.asked = false;
        // The subscription and the request belong to the session they were made on.
        const int32_t connects = (int32_t)client->status().connects;
        if (connects != p.seenConnects) {
            p.seenConnects = connects;
            p.asked = false;
        }

        if (!p.usingKey) {
            // Its own login. Refused as wrong (reset by an admin, or taken over
            // by a replacement): ask again with the key, keeping the old login
            // until a new one is issued; it is retried every five minutes.
            if (badLogin && p.switchTo == 0 && sKey.length() > 0) {
                p.oldTriedAt = (int32_t)(uint32_t)now;
                p.switchTo = 2;
            }
            // Not authorized: disabled or pending, or a Will the login may no
            // longer publish because the site's group changed. Connect once
            // without the Will and ask again.
            if (notAuthorized && p.switchTo == 0 && !p.withoutWill &&
                (p.lockedAt == 0 ||
                 mq_elapsed((mq_time_t)(uint32_t)p.lockedAt, now) >= MQ_PROVISION_REFUSED_MS)) {
                p.lockedAt = (int32_t)(uint32_t)(now | 1u);
                p.switchTo = 3;
            }
            if (p.withoutWill && notAuthorized && p.switchTo == 0) {
                p.refused = true;
                p.status = E_MQTTRESULT::NOTAUTHORIZED;
                p.reason = "this PLC's login is disabled or waiting for approval";
                p.switchTo = 1;   // back to the normal session, Will and all; asks again later
                return done();
            }

            // Connected: ask again for what the key hands its devices.
            if (client->isConnected() && !p.asked) {
                client->subscribeTo(handle, MQ_QOS_1);
                const std::string request = base + "/request";
                const char refresh[] = "{\"refresh\":true}";
                const MqttResult asked = client->publish(request.c_str(), (const uint8_t*)refresh,
                                                         sizeof refresh - 1, MQ_QOS_1, false);
                if (mq_tolerated(asked)) {
                    p.asked = true;
                    p.askedAt = (int32_t)(uint32_t)now;
                }
            }
            uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
            size_t length = 0;
            while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
                std::string status, group, prefix;
                mq_provisionField((const char*)buffer, length, "status", status);
                if (status != "ok") continue;
                // The whole set: a value the broker no longer has is gone here too.
                mq_provisionField((const char*)buffer, length, "group", group);
                mq_provisionField((const char*)buffer, length, "prefix", prefix);
                const bool moved = group.size() <= 64 &&
                                   group != std::string(sProvGroup.c_str(), sProvGroup.length());
                if (group.size() <= 64) sProvGroup = group.c_str();
                if (prefix.size() <= 127) sProvPrefix = prefix.c_str();
                if (!p.withoutWill) {
                    p.lockedAt = 0;
                } else {
                    // Only asking: back to the real session, Will on the new group.
                    p.switchTo = 1;
                    if (moved) {
                        p.lockedAt = 0;
                    } else {
                        // The same group: the login's rights no longer cover its
                        // Will. The hold is kept, so a refused session does not
                        // start again at once.
                        p.refused = true;
                        p.status = E_MQTTRESULT::NOTAUTHORIZED;
                        p.reason = "the broker refuses this PLC's Will";
                    }
                }
            }

            p.provisioned = sProvLoginUser.length() > 0 && client->isConnected() && !p.withoutWill;
            p.waiting = false;
            if (p.provisioned) p.refused = false;
            p.userName = sProvLoginUser.c_str();
            if (p.switchTo == 0 && !p.refused) {
                p.status = E_MQTTRESULT::OK;
                p.reason = "";
            }
            return done();
        }

        // Connected with the key: ask for a login.
        p.provisioned = false;
        p.userName = "";

        // Pending or refused, with a login kept from before: try it again every
        // five minutes - a login put back on the broker works again by itself.
        const bool keptLogin = sProvLoginUser.length() > 0 && sProvLoginSecret.length() > 0;
        if (keptLogin && (p.waiting || p.refused || badLogin) && p.switchTo == 0 &&
            mq_elapsed((mq_time_t)(uint32_t)p.oldTriedAt, now) >= MQ_PROVISION_REFUSED_MS) {
            p.oldTriedAt = (int32_t)(uint32_t)now;
            p.switchTo = 1;
            return done();
        }

        if (badLogin) {
            // The key itself was refused at CONNECT.
            if (!p.refused) p.refusedAt = (int32_t)(uint32_t)now;
            p.refused = true;
            p.waiting = false;
            p.status = E_MQTTRESULT::NOTAUTHORIZED;
            p.reason = "the broker refused the provisioning key";
            if (client->state() == MqttState::Idle &&
                mq_elapsed((mq_time_t)(uint32_t)p.refusedAt, now) >= MQ_PROVISION_REFUSED_MS) {
                p.refusedAt = (int32_t)(uint32_t)now;
                client->connect();
            }
            return done();
        }
        if (!client->isConnected()) return done();

        const mq_time_t since = mq_elapsed((mq_time_t)(uint32_t)p.askedAt, now);
        const bool askAgain = (p.waiting && since >= MQ_PROVISION_PENDING_MS) ||
                              (p.refused && since >= MQ_PROVISION_REFUSED_MS);
        if (!p.asked || askAgain) {
            if (!p.asked) client->subscribeTo(handle, MQ_QOS_1);
            const std::string request = base + "/request";
            const MqttResult asked =
                client->publish(request.c_str(), (const uint8_t*)"{}", 2, MQ_QOS_1, false);
            if (mq_tolerated(asked)) {
                p.asked = true;
                p.askedAt = (int32_t)(uint32_t)now;
            }
        }

        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            std::string status, user, secret, why, group, prefix;
            mq_provisionField((const char*)buffer, length, "status", status);
            if (status == "ok" && mq_provisionField((const char*)buffer, length, "username", user) &&
                mq_provisionField((const char*)buffer, length, "password", secret) &&
                !user.empty() && user.size() <= 64 && !secret.empty() && secret.size() <= 64) {
                mq_provisionField((const char*)buffer, length, "group", group);
                mq_provisionField((const char*)buffer, length, "prefix", prefix);
                sProvLoginUser = user.c_str();
                sProvLoginSecret = secret.c_str();
                sProvGroup = group.size() <= 64 ? group.c_str() : "";
                sProvPrefix = prefix.size() <= 127 ? prefix.c_str() : "";
                p.switchTo = 1;
                p.waiting = false;
                p.refused = false;
                p.status = E_MQTTRESULT::OK;
                p.reason = "";
            } else if (status == "pending") {
                p.waiting = true;
                p.refused = false;
                p.status = E_MQTTRESULT::OK;
                p.reason = "waiting for approval on the broker";
            } else {
                p.waiting = false;
                p.refused = true;
                p.status = E_MQTTRESULT::NOTAUTHORIZED;
                if (!mq_provisionField((const char*)buffer, length, "reason", why)) why = "refused";
                if (why.size() > 63) why.resize(63);
                p.reason = why;
            }
        }
        return done();
    }();
    return mq_noteCall((strucpp::XWORD_t)nMethods, "Provision", nullptr, "", result);
}

END_FUNCTION_BLOCK