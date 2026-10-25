(* Makes this PLC the broker other devices connect to. Standalone - it owns its
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

---

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
and lost. *)

FUNCTION_BLOCK MQTT_BROKER
  VAR_INPUT
    ENABLE : BOOL := TRUE;
    LISTEN_ON : STRING(48);
    PORT : UINT;
    MAX_CLIENTS : INT;
    MAX_RETAINED : INT;
    SECURITY : MQTT_SECURITY;
    CERT_FILE : STRING(128);
    KEY_FILE : STRING(128);
    MAX_SUBSCRIPTIONS : INT;
    MAX_QUEUED : INT;
    MAX_MESSAGE : DINT;
    MAX_SESSION_EXPIRY : TIME;
  END_VAR
  VAR_OUTPUT
    LISTENING : BOOL;
    CLIENTS : INT;
    SESSIONS : INT;
    ACCEPTED : DINT;
    ADMITTED : DINT;
    REFUSED : DINT;
    (* LINT AND NOT DINT, FOR THE THREE THAT COUNT MESSAGES.

       A DINT running total goes NEGATIVE at 2,147,483,648 and then keeps
       going, which breaks precisely the consumer these pins are for: a rung
       computing `now - last` sees a huge number, or a negative one. The C++
       library widened these three to 64 bits for that reason and this block
       was truncating them straight back.

       Only these three. ACCEPTED, ADMITTED, REFUSED and TAKEOVERS count
       CONNECTs and faults, which do not reach two billion in a plant that is
       working, and 64-bit arithmetic is not free on a 32-bit MCU reading them
       every scan. *)
    FROM_CLIENTS : LINT;
    TO_CLIENTS : LINT;
    DROPPED : LINT;
    TAKEOVERS : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;

    (* The SHA-256 of this broker's own public key, 64 hexadecimal characters.
       This is the number a client pins against: read it off the panel once at
       commissioning and it does not change again, because it is a fingerprint
       of the KEY rather than of the certificate - so it survives the
       certificate being reissued. Empty while the broker is serving plain
       TCP. *)
    BROKER_KEY : STRING(64);
  END_VAR
  VAR
    fbBroker : __XWORD;
    (* THE ACCOUNT TABLE, separate from fbBroker and made on the FIRST scan.
       The broker itself is only built on the second, after the settling scan,
       so a table living inside it would not exist when an MQTT_BROKER_USER
       drawn on an earlier rung first runs - and the broker could be listening
       before anybody had registered. Made first, it is full before the port
       opens, wherever the account rungs are drawn. Reached by
       MQTT_BROKER_USER as BROKER.FBACCOUNTS; not a pin, so nothing can wire
       it by mistake. *)
    fbAccounts : __XWORD;
    fbSettled : BOOL;
    fbTried : BOOL;
    fbRetryAt : DINT;
    (* The task this block runs in, for the blocks given it: see MQTT_ARDUINO,
       "ONE TASK PER CLIENT". *)
    fbTask : __XWORD;
  END_VAR
// The wolfSSL configuration, and nothing else, so arduino-cli's dependency
// scanner puts the library on the include path. The long version of why it is
// <modbee-wolfssl.h> rather than <wolfssl/ssl.h> or upstream's <wolfssl.h> is
// at the top of MQTT_CLIENT.cpp: the latter drag in the OpenSSL compatibility
// layer, which typedefs SHA_CTX, and so does the ESP32 ROM.
#if defined(ARDUINO)
  #include <modbee-wolfssl.h>
#endif

#include <ModBeeMqtt.h>
#include <string>
#include <vector>
#include <new>
#include <stdio.h>

// Defined by the MQTT_CLIENT block; declared here because every C++ POU lands
// in one translation unit, in filename order, and this one sorts before it.
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

// --- Account tables, one per MQTT_BROKER, freed when the program unloads ---
//
// Owned here rather than by the broker pair because they must exist a scan
// before the pair does - see fbAccounts. Plain `new` on purpose: this happens
// once per broker for the life of the program, which is the allocation a
// board can afford.
namespace {
std::vector<MqttBrokerAccounts*> mqOwnedAccounts;
struct MqAccountsCleanup {
    ~MqAccountsCleanup() {
        for (size_t i = 0; i < mqOwnedAccounts.size(); i++) delete mqOwnedAccounts[i];
        mqOwnedAccounts.clear();
    }
};
MqAccountsCleanup mqAccountsCleanup;
}  // namespace

// The table behind a handle, made if this is the first time it is asked for.
static MqttBrokerAccounts* mq_brokerAccounts(strucpp::XWORD_t& handle) {
    if (handle) return (MqttBrokerAccounts*)(uintptr_t)handle;
    MqttBrokerAccounts* accounts = new (std::nothrow) MqttBrokerAccounts();
    if (!accounts) return nullptr;
    mqOwnedAccounts.push_back(accounts);
    handle = (strucpp::XWORD_t)(uintptr_t)accounts;
    return accounts;
}

// What MQTT_BROKER_USER calls. Declared here, after the type exists, so that
// block - which sorts after this one in the single translation unit every C++
// POU lands in - can reach it.
MqttBrokerAccounts* mq_brokerAccountsOf(strucpp::XWORD_t handle) {
    return (MqttBrokerAccounts*)(uintptr_t)handle;
}

#if defined(MQTT_PLATFORM_ARDUINO)
  #include <Arduino.h>
  #if __has_include(<WiFi.h>) && !defined(MQTT_NO_WIFI)
    #include <WiFi.h>
    #define MQ_HAS_WIFI 1
  #endif
  // ETHERNET HAS TO BE ASKED FOR, for the reason set out at length in
  // MQTT_CLIENT.cpp: WiFi.h ships inside the ESP32 core and __has_include
  // finds it, while the Arduino Ethernet library is a USER library that
  // arduino-cli only puts on the include path when its dependency scanner
  // sees a plain #include. A header behind __has_include is invisible to that
  // scanner, so the guard would say "not installed" for ever.
  #if defined(MQTT_ENABLE_ETHERNET)
    #include <Ethernet.h>
    #define MQ_HAS_ETHERNET 1
  #endif
#endif

#if defined(MQTT_PLATFORM_HOST)
// Every broker this program made, closed when it is unloaded. A listening
// socket outlives the shared object otherwise, and the next download comes up
// reporting that it cannot bind a port nothing appears to be using.
namespace {
struct MqBrokerPair {
    MqttBroker broker;
    // The configuration it was started with, and whether it has been ended
    // since. Switching ENABLE off ends the broker; switching it on again has
    // to begin it again with the same settings - see the ENABLE path.
    MqttBrokerConfig config;
    bool needsBegin = false;
    MqttTcpListener listener;
#if MQTT_TLS_SOCKETS
    // Both, because a broker serving 1883 and 8883 at once is ordinary - the
    // sessions and the routing cannot tell them apart, which is exactly right:
    // a subscriber on one must receive what a publisher on the other sends.
    // Only the one the SECURITY pin asks for is started.
    MqttTlsListener secure;
    MqttIdentity identity;
#endif
    ~MqBrokerPair() {
        broker.end();
        listener.end();
#if MQTT_TLS_SOCKETS
        secure.end();
#endif
    }
};
}  // namespace

static std::vector<MqBrokerPair*> mqOwnedBrokers;

namespace {
struct MqBrokerCleanup {
    ~MqBrokerCleanup() {
        for (size_t i = 0; i < mqOwnedBrokers.size(); i++) delete mqOwnedBrokers[i];
        mqOwnedBrokers.clear();
    }
};
static MqBrokerCleanup mqBrokerCleanup;
}  // namespace

#else   // ------------------------------------------------------ a board

// THE BOARD CAN BE THE BROKER NOW, and for a while it could not.
//
// MqttBroker has never been host-only - the routing, the retained store, the
// session registry and takeover all compile anywhere. What was missing was a
// listener that could accept a connection without a BSD socket, and this
// block's comment used to say so: "an Arduino listener is a small addition to
// the C++ library and is the thing to write next". It was written, and then
// this block still said that, which is how a comment outlives the fact it
// described.
//
// Two listeners exist in the library now, both templates over an Arduino
// server type and its client type:
//
//   MqttStreamListener      plain, on 1883. Needs NOTHING installed.
//   MqttStreamTlsListener   the same with a TLS session over each connection,
//                           which needs wolfSSL.
namespace {

#if defined(MQ_HAS_WIFI)
typedef WiFiServer     MqAcceptor;
typedef WiFiClient     MqChannel;
#define MQ_BOARD_BROKER 1
#elif defined(MQ_HAS_ETHERNET)
typedef EthernetServer MqAcceptor;
typedef EthernetClient MqChannel;
#define MQ_BOARD_BROKER 1
#endif

#if defined(MQ_BOARD_BROKER)

struct MqBrokerPair {
    MqttBroker broker;
    // See the Runtime's MqBrokerPair: the settings to begin again with after
    // ENABLE has been cycled.
    MqttBrokerConfig config;
    bool needsBegin = false;

    // TWO ACCEPTORS ON ONE PORT, and only ever one of them started. An
    // Arduino server takes its port in the constructor - Ethernet's has no
    // other way to be told - so both are built and the SECURITY pin decides
    // which one begins. An acceptor that never begins holds no socket.
    MqAcceptor plainAcceptor;
    MqttStreamListener<MqAcceptor, MqChannel> listener;
#if MQTT_TLS_AVAILABLE
    MqAcceptor secureAcceptor;
    MqttStreamTlsListener<MqAcceptor, MqChannel> secure;
#endif

    explicit MqBrokerPair(uint16_t port)
        : plainAcceptor(port), listener(plainAcceptor)
#if MQTT_TLS_AVAILABLE
        , secureAcceptor(port), secure(secureAcceptor)
#endif
    {}

    ~MqBrokerPair() {
        broker.end();
        listener.end();
#if MQTT_TLS_AVAILABLE
        secure.end();
#endif
    }
};

#endif  // MQ_BOARD_BROKER
}  // namespace

// NO OWNED-BROKER VECTOR HERE, and no static destructor either. Both exist on
// the Runtime because it swaps a new program into the SAME process and a
// listening socket would outlive the shared object. A board runs one program
// until it is reflashed, so the block's own handle is the only owner it needs
// and a vector would be RAM spent on a case that cannot happen.
#endif

void setup()
{
    LISTENING = false;
    CLIENTS = 0;
    SESSIONS = 0;
    ACCEPTED = 0;
    ADMITTED = 0;
    REFUSED = 0;
    FROM_CLIENTS = 0;
    TO_CLIENTS = 0;
    DROPPED = 0;
    TAKEOVERS = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbBroker = (strucpp::XWORD_t)0;
    fbSettled = false;
    fbTried = false;
    fbRetryAt = 0;
    fbAccounts = (strucpp::XWORD_t)0;
}

void loop()
{
    fbTask = mq_currentTask();   // every block on this one shares it: see MQTT_ARDUINO
    {
        // FIRST, before ENABLE, the settling scan or the broker: the table has
        // to be there for any MQTT_BROKER_USER to register into, and it has to
        // be full before the port ever opens.
        strucpp::XWORD_t handle = (strucpp::XWORD_t)fbAccounts;
        mq_brokerAccounts(handle);
        fbAccounts = handle;
    }

#if !defined(MQTT_PLATFORM_HOST)

#if !defined(MQ_BOARD_BROKER)
    // A board with no network library on the include path. Said plainly on the
    // pins rather than silently doing nothing: there is no acceptor to listen
    // with. WiFi comes with the ESP32 core; Ethernet is opt-in with
    // MQTT_ENABLE_ETHERNET, for the dependency-scanner reason above.
    LISTENING = false;
    ERROR = true;
    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
#else
    MqBrokerPair* pair = (MqBrokerPair*)(uintptr_t)(strucpp::XWORD_t)fbBroker;

    if (!(bool)ENABLE) {
        // --- SWITCHED OFF: THE BROKER IS ENDED BEFORE ITS LISTENERS ---
        //
        // THIS USED TO CRASH THE PLC. It ended the listeners and left the
        // broker running - but a listener OWNS the sockets of the connections
        // it accepted, so ending it destroyed transports the broker was still
        // holding. Switched back on, the broker polled freed memory and the
        // runtime killed the network task with signal 11: the broker, this
        // PLC's own client and every link on it gone, while APP_TASK carried
        // on as if nothing had happened. Found by cycling ENABLE on a live
        // plant, which is what a site does for maintenance.
        //
        // So the broker is ended FIRST - each connection closed with 0x8B
        // Server shutting down and its socket handed back to the listener that
        // owns it - and only then the listeners. The pair itself is KEPT: on a
        // board the TLS identity cannot be written anywhere, so rebuilding the
        // pair would change the key every pinned client trusts on every
        // maintenance cycle. Switched on again, the start path begins the
        // broker afresh with the settings it was built with.
        //
        // Sessions do not survive this. A broker that is switched off is off,
        // and they would not survive a program restart either.
        if (pair && !pair->needsBegin) {
            pair->broker.end();
            pair->listener.end();
#if MQTT_TLS_AVAILABLE
            pair->secure.end();
#endif
            pair->needsBegin = true;
        }
        LISTENING = false;
        BROKER_KEY = "";
        CLIENTS = 0;
        SESSIONS = 0;
        fbTried = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (!(bool)LISTENING) {
        // One scan before opening, for the same reason the client waits: any
        // block that configures this one has then run at least once, wherever
        // it was drawn.
        if (!(bool)fbSettled) {
            fbSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)fbTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbRetryAt) < 0) {
            return;
        }
        fbTried = true;
        fbRetryAt = (int32_t)(uint32_t)(now + 2000);

        const uint16_t port = (uint16_t)PORT != 0 ? (uint16_t)PORT
                                                  : (uint16_t)MQ_PORT_TCP;
        const bool wantsTls = (SECURITY != MQTT_SECURITY::MQTT_PLAIN);

        if (!pair) {
            // SIZED FOR A PANEL, NOT FOR A HOST. Every one of these is
            // allocated here and never grows, which is what makes a broker
            // usable on a board at all: the RAM it needs is knowable before it
            // starts rather than a function of how busy the line gets. The
            // host defaults would be tens of kilobytes.
            pair = new (std::nothrow) MqBrokerPair(port);
            if (!pair) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
                return;
            }
            MqttBrokerConfig config;
            config.maxConnections = (int16_t)MAX_CLIENTS > 0
                ? (size_t)(int16_t)MAX_CLIENTS : (size_t)4;
            config.maxSessions = config.maxConnections * 2;
            config.maxSubscriptionsPerSession = (int16_t)MAX_SUBSCRIPTIONS > 0
                ? (size_t)(int16_t)MAX_SUBSCRIPTIONS : (size_t)8;
            config.maxQueuedPerSession = (int16_t)MAX_QUEUED > 0
                ? (size_t)(int16_t)MAX_QUEUED : (size_t)16;
            const size_t message = (int32_t)MAX_MESSAGE > 0
                ? (size_t)(int32_t)MAX_MESSAGE : (size_t)1024;
            config.receiveBufferSize = message;
            config.transmitBufferSize = message;
            config.maximumPacketSize = (uint32_t)message;
            config.maxRetained = (int16_t)MAX_RETAINED > 0
                ? (size_t)(int16_t)MAX_RETAINED : (size_t)32;

            // NO CONNECTION LIVES FOR EVER. A client that asks for no keep
            // alive and then loses its cellular link sends no FIN and no
            // packet again - and without a default it held its slot until the
            // PLC restarted, so a handful of those locked every device out of
            // a remote broker. 120 s is applied only where a client asked for
            // none; a client's own interval is honoured.
            config.defaultKeepAlive = 120;

            // How long a session outlives its client (MAX_SESSION_EXPIRY; 0:
            // the library's hour). Whole seconds, at least one.
            const int32_t expiryMs = mq_millisOf(MAX_SESSION_EXPIRY);
            if (expiryMs > 0) config.maximumSessionExpiry = expiryMs < 1000 ? 1u : (uint32_t)(expiryMs / 1000);

            pair->config = config;
            pair->broker.begin(config);

            // THE ACCOUNTS, installed before any listener is added, so there
            // is no moment at which this broker is open without them. An empty
            // table has no opinion and the broker behaves as it always has.
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)fbAccounts);
            fbBroker = (strucpp::XWORD_t)(uintptr_t)pair;
        }

        // SWITCHED BACK ON after ENABLE was cycled: the broker was ended, so it
        // is begun again - and the accounts installed again - before any
        // listener can hand it a connection.
        if (pair->needsBegin) {
            pair->broker.begin(pair->config);
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)fbAccounts);
            pair->needsBegin = false;
        }

        const size_t pool = (int16_t)MAX_CLIENTS > 0
            ? (size_t)(int16_t)MAX_CLIENTS : (size_t)4;

        // LISTEN_ON IS NOT A BOARD CONCEPT and is ignored rather than
        // half-honoured. An Arduino server listens on whatever interface the
        // core brought up; there is no second one to choose between.

        if (!wantsTls) {
            pair->listener.configure(pool);
            if (!pair->listener.begin()) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->listener)) {
                pair->listener.end();
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
            BROKER_KEY = "";
        } else {
#if !MQTT_TLS_AVAILABLE
            // No engine on the board, so nothing to encrypt through. The plain
            // listener is still there and needs nothing.
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
#else
            // CERT_FILE AND KEY_FILE ARE PATHS, AND A BOARD HAS NO PATHS.
            // MqttIdentity compiles its file forms only on the Runtime -
            // wolfSSL is built NO_FILESYSTEM here - so naming one is refused
            // rather than quietly ignored, which would serve a different
            // certificate than the one the pins asked for.
            if (CERT_FILE.length() > 0 || KEY_FILE.length() > 0) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }

            // The certificate is made ON THE BOARD, by wc_MakeCert over an EC
            // P-256 key - about a second on an ESP32, where RSA-2048 would be
            // minutes. That is also why wolfSSL is the engine: BearSSL can
            // read an X.509 and cannot write one.
            //
            // AND IT MOVES ON EVERY RESTART, which is the one thing to know
            // before pinning it. There is nowhere on a board for this block to
            // keep a key: no file system it can assume, and a PEM does not fit
            // in a retained variable. So BROKER_KEY is the fingerprint of THIS
            // run. On the Runtime the identity is written beside the program
            // and the fingerprint holds; on a board, either re-pin after a
            // reflash or serve plain on an isolated line and encrypt the
            // bridge that leaves it, which is the connection that needs it.
            pair->secure.identity().setCommonName("modbee-broker");
            pair->secure.configure(pool);
            if (!pair->secure.begin()) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->secure)) {
                pair->secure.end();
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
            BROKER_KEY = pair->secure.fingerprint().c_str();
#endif
        }

        LISTENING = true;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
    }

    if (!pair) return;

    pair->broker.poll();

    const MqttBrokerStatus& s = pair->broker.status();
    CLIENTS = (int16_t)pair->broker.connectionCount();
    SESSIONS = (int16_t)pair->broker.sessionCount();
    ACCEPTED = (int32_t)s.accepted;
    ADMITTED = (int32_t)s.connected;
    REFUSED = (int32_t)s.refused;
    FROM_CLIENTS = (int64_t)s.published;
    TO_CLIENTS = (int64_t)s.delivered;
    DROPPED = (int64_t)s.dropped;
    TAKEOVERS = (int32_t)s.takeovers;
    LISTENING = pair->listener.isListening()
#if MQTT_TLS_AVAILABLE
                || pair->secure.isListening()
#endif
                ;
#endif  // MQ_BOARD_BROKER

#else
    MqBrokerPair* pair = (MqBrokerPair*)(uintptr_t)(strucpp::XWORD_t)fbBroker;

    if (!(bool)ENABLE) {
        // --- SWITCHED OFF: THE BROKER IS ENDED BEFORE ITS LISTENERS ---
        //
        // THIS USED TO CRASH THE PLC. It ended the listeners and left the
        // broker running - but a listener OWNS the sockets of the connections
        // it accepted, so ending it destroyed transports the broker was still
        // holding. Switched back on, the broker polled freed memory and the
        // runtime killed the network task with signal 11: the broker, this
        // PLC's own client and every link on it gone, while APP_TASK carried
        // on as if nothing had happened. Found by cycling ENABLE on a live
        // plant, which is what a site does for maintenance.
        //
        // So the broker is ended FIRST - each connection closed with 0x8B
        // Server shutting down and its socket handed back to the listener that
        // owns it - and only then the listeners. The pair itself is KEPT: on a
        // board the TLS identity cannot be written anywhere, so rebuilding the
        // pair would change the key every pinned client trusts on every
        // maintenance cycle. Switched on again, the start path begins the
        // broker afresh with the settings it was built with.
        //
        // Sessions do not survive this. A broker that is switched off is off,
        // and they would not survive a program restart either.
        if (pair && !pair->needsBegin) {
            pair->broker.end();
            pair->listener.end();
#if MQTT_TLS_SOCKETS
            pair->secure.end();
#endif
            pair->needsBegin = true;
        }
        LISTENING = false;
        BROKER_KEY = "";
        CLIENTS = 0;
        SESSIONS = 0;
        fbTried = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (!(bool)LISTENING) {
        // One scan before opening, for the same reason the client waits: any
        // block that configures this one has then run at least once, wherever
        // it was drawn.
        if (!(bool)fbSettled) {
            fbSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)fbTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbRetryAt) < 0) {
            return;
        }
        fbTried = true;
        fbRetryAt = (int32_t)(uint32_t)(now + 2000);

        if (!pair) {
            pair = new (std::nothrow) MqBrokerPair();
            if (!pair) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
                return;
            }
            MqttBrokerConfig config;
            if ((int16_t)MAX_CLIENTS > 0) {
                config.maxConnections = (size_t)(int16_t)MAX_CLIENTS;
                // Sessions outlive connections: a plant at three in the
                // morning is mostly offline sessions, so holding only as many
                // as there are sockets would expire them the moment a device
                // slept.
                config.maxSessions = config.maxConnections * 2;
            }
            if ((int16_t)MAX_RETAINED > 0) {
                config.maxRetained = (size_t)(int16_t)MAX_RETAINED;
            }
            if ((int16_t)MAX_SUBSCRIPTIONS > 0) {
                config.maxSubscriptionsPerSession = (size_t)(int16_t)MAX_SUBSCRIPTIONS;
            }
            if ((int16_t)MAX_QUEUED > 0) {
                config.maxQueuedPerSession = (size_t)(int16_t)MAX_QUEUED;
            }
            if ((int32_t)MAX_MESSAGE > 0) {
                config.receiveBufferSize = (size_t)(int32_t)MAX_MESSAGE;
                config.transmitBufferSize = (size_t)(int32_t)MAX_MESSAGE;
                config.maximumPacketSize = (uint32_t)(int32_t)MAX_MESSAGE;
            }

            // NO CONNECTION LIVES FOR EVER. A client that asks for no keep
            // alive and then loses its cellular link sends no FIN and no
            // packet again - and without a default it held its slot until the
            // PLC restarted, so a handful of those locked every device out of
            // a remote broker. 120 s is applied only where a client asked for
            // none; a client's own interval is honoured.
            config.defaultKeepAlive = 120;

            // How long a session outlives its client (MAX_SESSION_EXPIRY; 0:
            // the library's hour). Whole seconds, at least one.
            const int32_t expiryMs = mq_millisOf(MAX_SESSION_EXPIRY);
            if (expiryMs > 0) config.maximumSessionExpiry = expiryMs < 1000 ? 1u : (uint32_t)(expiryMs / 1000);
            pair->config = config;
            pair->broker.begin(config);

            // THE ACCOUNTS, installed before any listener is added, so there
            // is no moment at which this broker is open without them. An empty
            // table has no opinion and the broker behaves as it always has.
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)fbAccounts);
            mqOwnedBrokers.push_back(pair);
            fbBroker = (strucpp::XWORD_t)(uintptr_t)pair;
        }

        const uint16_t port = (uint16_t)PORT != 0 ? (uint16_t)PORT
                                                  : (uint16_t)MQ_PORT_TCP;
        // SWITCHED BACK ON after ENABLE was cycled: the broker was ended, so it
        // is begun again - and the accounts installed again - before any
        // listener can hand it a connection.
        if (pair->needsBegin) {
            pair->broker.begin(pair->config);
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)fbAccounts);
            pair->needsBegin = false;
        }

        const size_t pool = (int16_t)MAX_CLIENTS > 0
            ? (size_t)(int16_t)MAX_CLIENTS : (size_t)32;
        const bool wantsTls = (SECURITY != MQTT_SECURITY::MQTT_PLAIN);

        if (!wantsTls) {
            pair->listener.configure(LISTEN_ON.c_str(), port, pool);

            if (!pair->listener.begin()) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->listener)) {
                pair->listener.end();
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
            BROKER_KEY = "";
        } else {
#if !MQTT_TLS_SOCKETS
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
#else
            // WHERE THE CERTIFICATE COMES FROM, in the order a plant actually
            // wants it:
            //
            //   named on the pins   a real certificate from the site's own CA,
            //                       or a public one. Clients verify it the
            //                       ordinary way, hostname and all.
            //   not named           one this broker made for itself on first
            //                       start, kept beside the program, and
            //                       presented unchanged every start after.
            //                       Clients pin the key.
            //
            // Self-signed is the ZERO-CONFIGURATION DEFAULT, not a ceiling.
            // The obstacle was never the engine - it was that a certificate
            // does not fit on a pin, and a PATH does.
            bool ready = false;
            if (CERT_FILE.length() > 0 && KEY_FILE.length() > 0) {
                ready = pair->identity.loadFiles(CERT_FILE.c_str(), KEY_FILE.c_str());
                if (!ready) {
                    ERROR = true;
                    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                    return;
                }
            } else {
                // Beside the program, so it survives a restart and the
                // fingerprint an engineer wrote down stays true. A generated
                // identity that cannot be written down still serves this run;
                // it just moves on the next one, and loadOrGenerate says so.
                std::string base = "modbee-broker";
                if (PORT != 0) {
                    char suffix[16];
                    snprintf(suffix, sizeof suffix, "-%u", (unsigned)(uint16_t)PORT);
                    base += suffix;
                }
                const std::string certPath = base + ".crt";
                const std::string keyPath = base + ".key";

                pair->identity.setCommonName("modbee-broker");
                ready = pair->identity.loadOrGenerate(certPath.c_str(),
                                                      keyPath.c_str(), 3650);
                if (!ready) {
                    ERROR = true;
                    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                    return;
                }
            }

            pair->secure.configure(LISTEN_ON.c_str(), port, pool);
            pair->secure.useCertificate(pair->identity.certificatePem().c_str(),
                                        pair->identity.privateKeyPem().c_str());

            if (!pair->secure.begin()) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->secure)) {
                pair->secure.end();
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
            BROKER_KEY = pair->identity.fingerprint().c_str();
#endif
        }

        LISTENING = true;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
    }

    if (!pair) return;

    // Once per call, from the block that owns the broker. Accepting, routing,
    // retaining, expiring and every Will the broker owes happens here and
    // nowhere else.
    pair->broker.poll();

    const MqttBrokerStatus& s = pair->broker.status();
    CLIENTS = (int16_t)pair->broker.connectionCount();
    SESSIONS = (int16_t)pair->broker.sessionCount();
    ACCEPTED = (int32_t)s.accepted;
    ADMITTED = (int32_t)s.connected;
    REFUSED = (int32_t)s.refused;
    FROM_CLIENTS = (int64_t)s.published;
    TO_CLIENTS = (int64_t)s.delivered;
    DROPPED = (int64_t)s.dropped;
    TAKEOVERS = (int32_t)s.takeovers;
    // WHICHEVER LISTENER IS ACTUALLY SERVING, not "the plain one". Asking only
    // pair->listener meant that a TLS broker reported LISTENING false while
    // its socket was bound and accepting - and because the start path above
    // runs whenever LISTENING is false, the listener was torn down and rebuilt
    // every two seconds for ever. A client got as far as a completed handshake
    // and then had the connection destroyed underneath it, which looks from
    // the far end exactly like a broker that keeps crashing.
    LISTENING = pair->listener.isListening()
#if MQTT_TLS_SOCKETS
                || pair->secure.isListening()
#endif
                ;
#endif
}

END_FUNCTION_BLOCK