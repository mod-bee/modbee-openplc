(* Makes this PLC the broker other devices connect to. Standalone - it owns its
listener and takes no FB_MqttClient. Call it once every scan, in the network
task; each device's account is a call of its User method.

bEnable            TRUE listens. A falling edge stops and releases the port.
sListenInterface   which interface to listen on. Empty for all of them.
                   Ignored on a board, which listens where its core is up.
nLocalPort         0 for 1883.
nMaxClients        connections served at once. 0 for 32 (4 on a board).
nMaxRetainedMessages  retained messages held. 0 for 256 (32 on a board).
eSecurity          E_MqttSecurity.Plain serves clear text. Anything else
                   serves TLS, and then:
                     no sServerCertificateFile      the broker makes its OWN certificate on
                                       first start, keeps it beside the
                                       program and presents the same one every
                                       start after. Zero configuration;
                                       clients pin sBrokerKeyFingerprint.
                     sServerCertificateFile + sServerPrivateKeyFile
                                       a real certificate - from the site's
                                       own CA, or a public one. Clients verify
                                       it the ordinary way, host name and all,
                                       with nothing pinned.
sServerCertificateFile  a certificate to present, as a path on the Runtime. Empty
                   to make one. Refused on a board, which has no file system
                   this block may assume.
sServerPrivateKeyFile  its private key. One without the other is refused rather
                   than half applied.
nMaxSubscriptionsPerClient  subscriptions each client session may hold. 0 for 32
                   (8 on a board).
nMaxQueuedPerClient  messages held for each client while it is away or slow.
                   0 for 64 (16 on a board).
nMaxMessageBytes   the largest message, in bytes, a client may send or be
                   sent; also each connection's buffer size. 0 for 8192
                   (1024 on a board).
tMaxSessionExpiryInterval  how long a session is kept after its client goes: a 3.1.1
                   client's persistent session, and the most a 5.0 client may
                   ask for. T#0s for 1 h. Read when the broker starts.

bListening         the port is open.
nClientsConnected  connections attached now. THIS PLC COUNTS AS ONE of them
                   if it also runs an FB_MqttClient against itself, which is
                   how a broker PLC publishes anything: a broker holds no
                   values of its own.
nSessionsHeld      sessions held, including those of clients currently away
                   whose state has not expired.
nAcceptedConnectionCount  connections accepted at the socket.
nAdmittedClientCount  of those, how many earned a successful CONNACK. A socket
                   that opens and never becomes a client is a scanner, or bad
                   credentials.
nRefusedConnectionCount  and how many were turned away - a client with another
                   login than the one that made an existing session among
                   them.
nMessageReceivedCount  messages accepted from clients.
nMessageSentCount  messages sent to clients.
nDroppedDeliveryCount  deliveries a full client queue could not take. Not silent:
                   at QoS above 0 the publisher is told (0x97) rather than
                   left believing it arrived.
nClientIdTakeoverCount  times a client identifier was claimed by a second
                   connection with the same login, and the first was
                   disconnected. Climbing usually means two devices share an
                   identifier.
bError             something failed.
eErrorId           why. E_MqttResult.Ok when fine.
sBrokerKeyFingerprint  the SHA-256 of this broker's public key, 64 hexadecimal
                   characters: what a client pins against. Empty while
                   serving plain.

METHODS

  broker.User(sUserName, sUserPassword, bAllowLogin, bAccountActive =>, nLoginCount =>,
              nRefusedLoginCount =>)

     ONE ACCOUNT ON THIS PLC'S BROKER. Standing: call it every scan, once per
     device that connects, in the broker's task. Declaring ANY account makes
     accounts REQUIRED for every connection - including one whose bAllowLogin is
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
     bAllowLogin    FALSE refuses this device without forgetting it.

     bAccountActive  the account is declared and allowed.
     nLoginCount    times this device has connected successfully.
     nRefusedLoginCount  times a connection under this name was turned away - a
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

---

WHY PUT A BROKER IN A PLC. A site with twenty sensors and an intermittent
uplink does not want twenty devices each retrying a connection to head office.
Point them at the PLC, let it hold the retained values and the sessions, and
carry one connection upstream with FB_MqttBridge. The site keeps working when
the link does not, and comes back in step when it returns.

A BROKER DOES NOT PUBLISH. It routes what clients send. A PLC that is the
broker and also publishes runs an FB_MqttClient against itself
(sHostName := '127.0.0.1') beside this block, in the same task.

ON A BOARD TOO. The routing, the retained store, the session registry and
takeover compile anywhere, and an Arduino listener accepts connections
without a BSD socket, so an ESP32 running this block is a real broker. What
differs on a board:

  sListenInterface  ignored.
  sServerCertificateFile,
  sServerPrivateKeyFile  refused rather than ignored: they are paths.
  sBrokerKeyFingerprint  the fingerprint of a certificate made on THIS run. There is
                   nowhere on a board to keep a key, so it moves on every
                   restart - either re-pin after a reflash, or serve plain on
                   an isolated line and put the TLS on the FB_MqttBridge that
                   leaves the site, which is the connection that needs it.
  the defaults     sized for a panel: four connections, eight sessions, 1 kB
                   buffers, 32 retained, 8 subscriptions and 16 queued
                   messages per session. Every one is a pin: raise the ones a
                   site needs, within the board's memory - each connection
                   holds two nMaxMessageBytes buffers.

Serving TLS on a board also needs wolfSSL on the include path; serving plain
needs nothing at all. WiFi comes with the ESP32 core, and Ethernet is opt-in:
MQTT_ENABLE_ETHERNET, a define in the board package's compiler flags.

SELF-SIGNED IS THE DEFAULT, NOT A CEILING. The obstacle was never the TLS
library; it was that a certificate does not fit on a pin, and a path does.

nClientIdTakeoverCount IS THE PIN TO WATCH ON A NEW SITE. MQTT says a second connection
using an existing client identifier displaces the first, so two devices
flashed with the same identifier knock each other off for ever, each looking
healthy on its own. This counter is the only place that shows from the
middle. A session belongs to the login that made it: a client with another
login and an existing identifier is refused (CONNACK 0x85; 0x02 at 3.1.1) and
counts on nRefusedConnectionCount, not here. Without logins every client is the same
nobody, so takeovers work as before.

SESSIONS EXPIRE. A persistent session of a 3.1.1 client is kept for
tMaxSessionExpiryInterval after it goes (an hour unless set), then dropped. A 5.0
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

ITS COST SCALES WITH nClientsConnected: it services each connection once per call.
Still bounded, still non-blocking, not free. Put it in the network task. *)

FUNCTION_BLOCK FB_MqttBroker
  VAR_INPUT
    bEnable           : BOOL := TRUE;       (* TRUE listens; a falling edge releases the port *)
    sListenInterface : STRING(48); (* the interface to listen on; empty for all; ignored on a board *)
    nLocalPort : UINT; (* the port to listen on; 0 = 1883 *)
    nMaxClients : INT; (* connections served at once; 0 = 32 (4 on a board) *)
    nMaxRetainedMessages : INT; (* retained messages held; 0 = 256 (32 on a board) *)
    eSecurity : E_MqttSecurity; (* Plain serves clear text; anything else serves TLS *)
    sServerCertificateFile : STRING(128); (* Runtime: certificate to present; empty = make its own *)
    sServerPrivateKeyFile : STRING(128); (* Runtime: that certificate's private key *)
    nMaxSubscriptionsPerClient : INT; (* subscriptions each client session may hold; 0 = 32 (8 on a board) *)
    nMaxQueuedPerClient : INT; (* messages held per client while away or slow; 0 = 64 (16 on a board) *)
    nMaxMessageBytes : DINT; (* largest message a client may send or be sent; 0 = 8192 (1024 on a board) *)
    tMaxSessionExpiryInterval : TIME; (* longest a session outlives its client; T#0s = 1 h; the MQTT 5 Session Expiry Interval cap *)
  END_VAR
  VAR_OUTPUT
    bListening        : BOOL;               (* the port is open *)
    nClientsConnected : INT; (* connections attached now, this PLC's own client included *)
    nSessionsHeld : INT; (* sessions held, away clients included *)
    nAcceptedConnectionCount : DINT; (* connections accepted at the socket *)
    nAdmittedClientCount : DINT; (* of those, given a successful CONNACK *)
    nRefusedConnectionCount : DINT; (* of those, turned away *)
    (* LINT AND NOT DINT, FOR THE THREE THAT COUNT MESSAGES.

       A DINT running total goes NEGATIVE at 2,147,483,648 and then keeps
       going, which breaks precisely the consumer these pins are for: a rung
       computing `now - last` sees a huge number, or a negative one.

       Only these three. nAcceptedConnectionCount, nAdmittedClientCount, nRefusedConnectionCount and nClientIdTakeoverCount count
       CONNECTs and faults, which do not reach two billion in a plant that is
       working, and 64-bit arithmetic is not free on a 32-bit MCU reading them
       every scan. *)
    nMessageReceivedCount : LINT; (* messages accepted from clients *)
    nMessageSentCount : LINT; (* messages sent to clients *)
    nDroppedDeliveryCount : LINT; (* deliveries a full client queue could not take *)
    nClientIdTakeoverCount : DINT; (* a client id claimed by a second connection; climbing = two devices share an id *)
    bError : BOOL; (* something failed *)
    eErrorId : E_MqttResult; (* why; Ok when fine *)
    (* The SHA-256 of this broker's own public key, 64 hexadecimal characters.
       This is the number a client pins against: read it off the panel once at
       commissioning and it does not change again, because it is a fingerprint
       of the KEY rather than of the certificate - so it survives the
       certificate being reissued. Empty while the broker is serving plain
       TCP. *)
    sBrokerKeyFingerprint : STRING(64); (* SHA-256 of this broker's own key, what clients pin; empty when plain *)
  END_VAR
  VAR
    nBroker           : __XWORD;            (* the broker and its listeners *)
    (* THE ACCOUNT TABLE, separate from nBroker and made on the FIRST scan, or
       by the first User call if that comes earlier. The broker itself is only
       built on the second scan, after the settling scan, so the table is full
       before the port opens, wherever the User calls are. *)
    nAccounts         : __XWORD;
    nUsers            : __XWORD;            (* the User calls seen, for retiring the stale ones *)
    bSettled          : BOOL;
    bTried            : BOOL;
    nRetryAt          : DINT;
    nTask             : __XWORD;            (* the task this block runs in *)
  END_VAR
(* One account on this broker, called every scan, once per device. Any
   account makes accounts required for every connection. Ok;
   InvalidArgument for an empty sUserName; QuotaExceeded out of memory. *)
METHOD PUBLIC User : E_MqttResult
  VAR_INPUT
    sUserName         : STRING(64);         (* the name the device logs in with; case-sensitive *)
    sUserPassword     : STRING(64);         (* its password *)
    bAllowLogin            : BOOL := TRUE;       (* FALSE refuses this device without forgetting it *)
  END_VAR
  VAR_OUTPUT
    bAccountActive           : BOOL;               (* the account is declared and allowed *)
    nLoginCount         : DINT;               (* times this device has connected *)
    nRefusedLoginCount       : DINT;               (* connections under this name turned away *)
  END_VAR
END_METHOD

// The wolfSSL configuration, and nothing else, so arduino-cli's dependency
// scanner puts the library on the include path. The long version of why it is
// <modbee-wolfssl.h> rather than <wolfssl/ssl.h> or upstream's <wolfssl.h> is
// at the top of FB_MqttClient.cpp: the latter drag in the OpenSSL compatibility
// layer, which typedefs SHA_CTX, and so does the ESP32 ROM.
#if defined(ARDUINO)
  #include <modbee-wolfssl.h>
#endif

#include <ModBeeMqtt.h>
#include <string>
#include <vector>
#include <new>
#include <stdio.h>

// Defined by FB_MqttClient; declared here because every C++ POU lands in one
// translation unit, in filename order, and this one sorts before it.
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);

// --- Account tables, one per FB_MqttBroker, freed when the program unloads ---
//
// Owned here rather than by the broker pair because they must exist a scan
// before the pair does - see nAccounts. Plain `new` on purpose: this happens
// once per broker for the life of the program, which is the allocation a
// board can afford.
//
// Beside each, the User calls seen, keyed by user name: one the broker's scan
// finds not called since its last scan is switched off and its password
// wiped. Switched off rather than removed, so the broker stays locked.
namespace {
struct MqBrokerUserCall {
    std::string name;
    bool seen = false;
    bool retired = false;
};
struct MqBrokerUsers {
    std::vector<MqBrokerUserCall> calls;
    size_t next = 0;             // calls come in the same order every scan
};

// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqAccountsOwned {
    std::vector<MqttBrokerAccounts*> accounts;
    std::vector<MqBrokerUsers*> users;
    ~MqAccountsOwned() {
        for (size_t i = 0; i < accounts.size(); i++) delete accounts[i];
        for (size_t i = 0; i < users.size(); i++) delete users[i];
    }
};
MqAccountsOwned& mqAccountsOwned() {
    static MqAccountsOwned owned;
    return owned;
}
}  // namespace

// The table behind a handle, made if this is the first time it is asked for.
static MqttBrokerAccounts* mq_brokerAccounts(strucpp::XWORD_t& handle) {
    if (handle) return (MqttBrokerAccounts*)(uintptr_t)handle;
    MqttBrokerAccounts* accounts = new (std::nothrow) MqttBrokerAccounts();
    if (!accounts) return nullptr;
    mqAccountsOwned().accounts.push_back(accounts);
    handle = (strucpp::XWORD_t)(uintptr_t)accounts;
    return accounts;
}

static MqBrokerUsers* mq_brokerUsers(strucpp::XWORD_t& handle) {
    if (handle) return (MqBrokerUsers*)(uintptr_t)handle;
    MqBrokerUsers* users = new (std::nothrow) MqBrokerUsers();
    if (!users) return nullptr;
    mqAccountsOwned().users.push_back(users);
    handle = (strucpp::XWORD_t)(uintptr_t)users;
    return users;
}

static MqBrokerUserCall* mq_brokerUserCall(MqBrokerUsers& users, const char* name) {
    std::vector<MqBrokerUserCall>& table = users.calls;
    size_t index = users.next;
    if (index >= table.size() || table[index].name != name) {
        for (index = 0; index < table.size(); index++) {
            if (table[index].name == name) break;
        }
        if (index == table.size()) {
            MqBrokerUserCall fresh;
            fresh.name = name;
            table.push_back(fresh);
        }
    }
    users.next = index + 1;
    return &table[index];
}

// Once per broker scan: an account not called since the last one goes off.
static void mq_brokerRetireUsers(MqBrokerUsers* users, MqttBrokerAccounts* accounts) {
    if (users == nullptr || accounts == nullptr) return;
    for (size_t i = 0; i < users->calls.size(); i++) {
        MqBrokerUserCall& call = users->calls[i];
        if (!call.seen && !call.retired) {
            accounts->set(call.name.c_str(), "", false);
            call.retired = true;
        }
        call.seen = false;
    }
}

#if defined(MQTT_PLATFORM_ARDUINO)
  #include <Arduino.h>
  #if __has_include(<WiFi.h>) && !defined(MQTT_NO_WIFI)
    #include <WiFi.h>
    #define MQ_HAS_WIFI 1
  #endif
  // ETHERNET HAS TO BE ASKED FOR, for the reason set out at length in
  // FB_MqttClient.cpp: WiFi.h ships inside the ESP32 core and __has_include
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
    // since. Switching bEnable off ends the broker; switching it on again has
    // to begin it again with the same settings - see the bEnable path.
    MqttBrokerConfig config;
    bool needsBegin = false;
    MqttTcpListener listener;
#if MQTT_TLS_SOCKETS
    // Both, because a broker serving 1883 and 8883 at once is ordinary - the
    // sessions and the routing cannot tell them apart, which is exactly right:
    // a subscriber on one must receive what a publisher on the other sends.
    // Only the one the eSecurity pin asks for is started.
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

namespace {
// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqBrokersOwned {
    std::vector<MqBrokerPair*> all;
    ~MqBrokersOwned() {
        for (size_t i = 0; i < all.size(); i++) delete all[i];
    }
};
MqBrokersOwned& mqBrokersOwned() {
    static MqBrokersOwned owned;
    return owned;
}
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
    // bEnable has been cycled.
    MqttBrokerConfig config;
    bool needsBegin = false;

    // TWO ACCEPTORS ON ONE nLocalPort, and only ever one of them started. An
    // Arduino server takes its port in the constructor - Ethernet's has no
    // other way to be told - so both are built and the eSecurity pin decides
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
    bListening = false;
    nClientsConnected = 0;
    nSessionsHeld = 0;
    nAcceptedConnectionCount = 0;
    nAdmittedClientCount = 0;
    nRefusedConnectionCount = 0;
    nMessageReceivedCount = 0;
    nMessageSentCount = 0;
    nDroppedDeliveryCount = 0;
    nClientIdTakeoverCount = 0;
    bError = false;
    eErrorId = E_MQTTRESULT::OK;
    nBroker = (strucpp::XWORD_t)0;
    bSettled = false;
    bTried = false;
    nRetryAt = 0;
    nAccounts = (strucpp::XWORD_t)0;
    nUsers = (strucpp::XWORD_t)0;
}

void loop()
{
    nTask = mq_currentTask();   // User is refused in any other task
    {
        // FIRST, before bEnable, the settling scan or the broker: the table has
        // to be there for any User call to register into, and it has to be
        // full before the port ever opens.
        strucpp::XWORD_t handle = (strucpp::XWORD_t)nAccounts;
        MqttBrokerAccounts* accounts = mq_brokerAccounts(handle);
        nAccounts = handle;
        mq_brokerRetireUsers((MqBrokerUsers*)(uintptr_t)(strucpp::XWORD_t)nUsers, accounts);
    }

#if !defined(MQTT_PLATFORM_HOST)

#if !defined(MQ_BOARD_BROKER)
    // A board with no network library on the include path. Said plainly on the
    // pins rather than silently doing nothing: there is no acceptor to listen
    // with. WiFi comes with the ESP32 core; Ethernet is opt-in with
    // MQTT_ENABLE_ETHERNET, for the dependency-scanner reason above.
    bListening = false;
    bError = true;
    eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
#else
    MqBrokerPair* pair = (MqBrokerPair*)(uintptr_t)(strucpp::XWORD_t)nBroker;

    if (!(bool)bEnable) {
        // --- SWITCHED OFF: THE BROKER IS ENDED BEFORE ITS LISTENERS ---
        //
        // THIS USED TO CRASH THE PLC. It ended the listeners and left the
        // broker running - but a listener OWNS the sockets of the connections
        // it accepted, so ending it destroyed transports the broker was still
        // holding. Switched back on, the broker polled freed memory and the
        // runtime killed the network task with signal 11: the broker, this
        // PLC's own client and every link on it gone, while APP_TASK carried
        // on as if nothing had happened. Found by cycling bEnable on a live
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
        bListening = false;
        sBrokerKeyFingerprint = "";
        nClientsConnected = 0;
        nSessionsHeld = 0;
        bTried = false;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
        return;
    }

    if (!(bool)bListening) {
        // One scan before opening, for the same reason the client waits: any
        // block that configures this one has then run at least once, wherever
        // it was drawn.
        if (!(bool)bSettled) {
            bSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)bTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)nRetryAt) < 0) {
            return;
        }
        bTried = true;
        nRetryAt = (int32_t)(uint32_t)(now + 2000);

        const uint16_t port = (uint16_t)nLocalPort != 0 ? (uint16_t)nLocalPort
                                                  : (uint16_t)MQ_PORT_TCP;
        const bool wantsTls = (eSecurity != E_MQTTSECURITY::PLAIN);

        if (!pair) {
            // SIZED FOR A PANEL, NOT FOR A HOST. Every one of these is
            // allocated here and never grows, which is what makes a broker
            // usable on a board at all: the RAM it needs is knowable before it
            // starts rather than a function of how busy the line gets. The
            // host defaults would be tens of kilobytes.
            pair = new (std::nothrow) MqBrokerPair(port);
            if (!pair) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTINITIALISED;
                return;
            }
            MqttBrokerConfig config;
            config.maxConnections = (int16_t)nMaxClients > 0
                ? (size_t)(int16_t)nMaxClients : (size_t)4;
            config.maxSessions = config.maxConnections * 2;
            config.maxSubscriptionsPerSession = (int16_t)nMaxSubscriptionsPerClient > 0
                ? (size_t)(int16_t)nMaxSubscriptionsPerClient : (size_t)8;
            config.maxQueuedPerSession = (int16_t)nMaxQueuedPerClient > 0
                ? (size_t)(int16_t)nMaxQueuedPerClient : (size_t)16;
            const size_t message = (int32_t)nMaxMessageBytes > 0
                ? (size_t)(int32_t)nMaxMessageBytes : (size_t)1024;
            config.receiveBufferSize = message;
            config.transmitBufferSize = message;
            config.maximumPacketSize = (uint32_t)message;
            config.maxRetained = (int16_t)nMaxRetainedMessages > 0
                ? (size_t)(int16_t)nMaxRetainedMessages : (size_t)32;

            // NO CONNECTION LIVES FOR EVER. A client that asks for no keep
            // alive and then loses its cellular link sends no FIN and no
            // packet again - and without a default it held its slot until the
            // PLC restarted, so a handful of those locked every device out of
            // a remote broker. 120 s is applied only where a client asked for
            // none; a client's own interval is honoured.
            config.defaultKeepAlive = 120;

            // How long a session outlives its client (tMaxSessionExpiryInterval; 0:
            // the library's hour). Whole seconds, at least one.
            const int32_t expiryMs = mq_millisOf(tMaxSessionExpiryInterval);
            if (expiryMs > 0) config.maximumSessionExpiry = expiryMs < 1000 ? 1u : (uint32_t)(expiryMs / 1000);

            pair->config = config;
            pair->broker.begin(config);

            // THE ACCOUNTS, installed before any listener is added, so there
            // is no moment at which this broker is open without them. An empty
            // table has no opinion and the broker behaves as it always has.
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)nAccounts);
            nBroker = (strucpp::XWORD_t)(uintptr_t)pair;
        }

        // SWITCHED BACK ON after bEnable was cycled: the broker was ended, so it
        // is begun again - and the accounts installed again - before any
        // listener can hand it a connection.
        if (pair->needsBegin) {
            pair->broker.begin(pair->config);
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)nAccounts);
            pair->needsBegin = false;
        }

        const size_t pool = (int16_t)nMaxClients > 0
            ? (size_t)(int16_t)nMaxClients : (size_t)4;

        // sListenInterface IS NOT A BOARD CONCEPT and is ignored rather than
        // half-honoured. An Arduino server listens on whatever interface the
        // core brought up; there is no second one to choose between.

        if (!wantsTls) {
            pair->listener.configure(pool);
            if (!pair->listener.begin()) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTCONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->listener)) {
                pair->listener.end();
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                return;
            }
            sBrokerKeyFingerprint = "";
        } else {
#if !MQTT_TLS_AVAILABLE
            // No engine on the board, so nothing to encrypt through. The plain
            // listener is still there and needs nothing.
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            return;
#else
            // sServerCertificateFile AND sServerPrivateKeyFile ARE PATHS, AND A BOARD HAS NO PATHS.
            // MqttIdentity compiles its file forms only on the Runtime -
            // wolfSSL is built NO_FILESYSTEM here - so naming one is refused
            // rather than quietly ignored, which would serve a different
            // certificate than the one the pins asked for.
            if (sServerCertificateFile.length() > 0 || sServerPrivateKeyFile.length() > 0) {
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
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
            // in a retained variable. So sBrokerKeyFingerprint is the fingerprint of THIS
            // run. On the Runtime the identity is written beside the program
            // and the fingerprint holds; on a board, either re-pin after a
            // reflash or serve plain on an isolated line and encrypt the
            // bridge that leaves it, which is the connection that needs it.
            pair->secure.identity().setCommonName("modbee-broker");
            pair->secure.configure(pool);
            if (!pair->secure.begin()) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTCONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->secure)) {
                pair->secure.end();
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                return;
            }
            sBrokerKeyFingerprint = pair->secure.fingerprint().c_str();
#endif
        }

        bListening = true;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
    }

    if (!pair) return;

    pair->broker.poll();

    const MqttBrokerStatus& s = pair->broker.status();
    nClientsConnected = (int16_t)pair->broker.connectionCount();
    nSessionsHeld = (int16_t)pair->broker.sessionCount();
    nAcceptedConnectionCount = (int32_t)s.accepted;
    nAdmittedClientCount = (int32_t)s.connected;
    nRefusedConnectionCount = (int32_t)s.refused;
    nMessageReceivedCount = (int64_t)s.published;
    nMessageSentCount = (int64_t)s.delivered;
    nDroppedDeliveryCount = (int64_t)s.dropped;
    nClientIdTakeoverCount = (int32_t)s.takeovers;
    bListening = pair->listener.isListening()
#if MQTT_TLS_AVAILABLE
                || pair->secure.isListening()
#endif
                ;
#endif  // MQ_BOARD_BROKER

#else
    MqBrokerPair* pair = (MqBrokerPair*)(uintptr_t)(strucpp::XWORD_t)nBroker;

    if (!(bool)bEnable) {
        // --- SWITCHED OFF: THE BROKER IS ENDED BEFORE ITS LISTENERS ---
        //
        // THIS USED TO CRASH THE PLC. It ended the listeners and left the
        // broker running - but a listener OWNS the sockets of the connections
        // it accepted, so ending it destroyed transports the broker was still
        // holding. Switched back on, the broker polled freed memory and the
        // runtime killed the network task with signal 11: the broker, this
        // PLC's own client and every link on it gone, while APP_TASK carried
        // on as if nothing had happened. Found by cycling bEnable on a live
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
        bListening = false;
        sBrokerKeyFingerprint = "";
        nClientsConnected = 0;
        nSessionsHeld = 0;
        bTried = false;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
        return;
    }

    if (!(bool)bListening) {
        // One scan before opening, for the same reason the client waits: any
        // block that configures this one has then run at least once, wherever
        // it was drawn.
        if (!(bool)bSettled) {
            bSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)bTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)nRetryAt) < 0) {
            return;
        }
        bTried = true;
        nRetryAt = (int32_t)(uint32_t)(now + 2000);

        if (!pair) {
            pair = new (std::nothrow) MqBrokerPair();
            if (!pair) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTINITIALISED;
                return;
            }
            MqttBrokerConfig config;
            if ((int16_t)nMaxClients > 0) {
                config.maxConnections = (size_t)(int16_t)nMaxClients;
                // Sessions outlive connections: a plant at three in the
                // morning is mostly offline sessions, so holding only as many
                // as there are sockets would expire them the moment a device
                // slept.
                config.maxSessions = config.maxConnections * 2;
            }
            if ((int16_t)nMaxRetainedMessages > 0) {
                config.maxRetained = (size_t)(int16_t)nMaxRetainedMessages;
            }
            if ((int16_t)nMaxSubscriptionsPerClient > 0) {
                config.maxSubscriptionsPerSession = (size_t)(int16_t)nMaxSubscriptionsPerClient;
            }
            if ((int16_t)nMaxQueuedPerClient > 0) {
                config.maxQueuedPerSession = (size_t)(int16_t)nMaxQueuedPerClient;
            }
            if ((int32_t)nMaxMessageBytes > 0) {
                config.receiveBufferSize = (size_t)(int32_t)nMaxMessageBytes;
                config.transmitBufferSize = (size_t)(int32_t)nMaxMessageBytes;
                config.maximumPacketSize = (uint32_t)(int32_t)nMaxMessageBytes;
            }

            // NO CONNECTION LIVES FOR EVER. A client that asks for no keep
            // alive and then loses its cellular link sends no FIN and no
            // packet again - and without a default it held its slot until the
            // PLC restarted, so a handful of those locked every device out of
            // a remote broker. 120 s is applied only where a client asked for
            // none; a client's own interval is honoured.
            config.defaultKeepAlive = 120;

            // How long a session outlives its client (tMaxSessionExpiryInterval; 0:
            // the library's hour). Whole seconds, at least one.
            const int32_t expiryMs = mq_millisOf(tMaxSessionExpiryInterval);
            if (expiryMs > 0) config.maximumSessionExpiry = expiryMs < 1000 ? 1u : (uint32_t)(expiryMs / 1000);
            pair->config = config;
            pair->broker.begin(config);

            // THE ACCOUNTS, installed before any listener is added, so there
            // is no moment at which this broker is open without them. An empty
            // table has no opinion and the broker behaves as it always has.
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)nAccounts);
            mqBrokersOwned().all.push_back(pair);
            nBroker = (strucpp::XWORD_t)(uintptr_t)pair;
        }

        const uint16_t port = (uint16_t)nLocalPort != 0 ? (uint16_t)nLocalPort
                                                  : (uint16_t)MQ_PORT_TCP;
        // SWITCHED BACK ON after bEnable was cycled: the broker was ended, so it
        // is begun again - and the accounts installed again - before any
        // listener can hand it a connection.
        if (pair->needsBegin) {
            pair->broker.begin(pair->config);
            pair->broker.onAuthorise(
                &MqttBrokerAccounts::hook,
                (MqttBrokerAccounts*)(uintptr_t)(strucpp::XWORD_t)nAccounts);
            pair->needsBegin = false;
        }

        const size_t pool = (int16_t)nMaxClients > 0
            ? (size_t)(int16_t)nMaxClients : (size_t)32;
        const bool wantsTls = (eSecurity != E_MQTTSECURITY::PLAIN);

        if (!wantsTls) {
            pair->listener.configure(sListenInterface.c_str(), port, pool);

            if (!pair->listener.begin()) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTCONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->listener)) {
                pair->listener.end();
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                return;
            }
            sBrokerKeyFingerprint = "";
        } else {
#if !MQTT_TLS_SOCKETS
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
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
            if (sServerCertificateFile.length() > 0 && sServerPrivateKeyFile.length() > 0) {
                ready = pair->identity.loadFiles(sServerCertificateFile.c_str(), sServerPrivateKeyFile.c_str());
                if (!ready) {
                    bError = true;
                    eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                    return;
                }
            } else {
                // Beside the program, so it survives a restart and the
                // fingerprint an engineer wrote down stays true. A generated
                // identity that cannot be written down still serves this run;
                // it just moves on the next one, and loadOrGenerate says so.
                std::string base = "modbee-broker";
                if (nLocalPort != 0) {
                    char suffix[16];
                    snprintf(suffix, sizeof suffix, "-%u", (unsigned)(uint16_t)nLocalPort);
                    base += suffix;
                }
                const std::string certPath = base + ".crt";
                const std::string keyPath = base + ".key";

                pair->identity.setCommonName("modbee-broker");
                ready = pair->identity.loadOrGenerate(certPath.c_str(),
                                                      keyPath.c_str(), 3650);
                if (!ready) {
                    bError = true;
                    eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                    return;
                }
            }

            pair->secure.configure(sListenInterface.c_str(), port, pool);
            pair->secure.useCertificate(pair->identity.certificatePem().c_str(),
                                        pair->identity.privateKeyPem().c_str());

            if (!pair->secure.begin()) {
                bError = true;
                eErrorId = E_MQTTRESULT::NOTCONNECTED;
                return;
            }
            if (!pair->broker.addListener(pair->secure)) {
                pair->secure.end();
                bError = true;
                eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
                return;
            }
            sBrokerKeyFingerprint = pair->identity.fingerprint().c_str();
#endif
        }

        bListening = true;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
    }

    if (!pair) return;

    // Once per call, from the block that owns the broker. Accepting, routing,
    // retaining, expiring and every Will the broker owes happens here and
    // nowhere else.
    pair->broker.poll();

    const MqttBrokerStatus& s = pair->broker.status();
    nClientsConnected = (int16_t)pair->broker.connectionCount();
    nSessionsHeld = (int16_t)pair->broker.sessionCount();
    nAcceptedConnectionCount = (int32_t)s.accepted;
    nAdmittedClientCount = (int32_t)s.connected;
    nRefusedConnectionCount = (int32_t)s.refused;
    nMessageReceivedCount = (int64_t)s.published;
    nMessageSentCount = (int64_t)s.delivered;
    nDroppedDeliveryCount = (int64_t)s.dropped;
    nClientIdTakeoverCount = (int32_t)s.takeovers;
    // WHICHEVER LISTENER IS ACTUALLY SERVING, not "the plain one". Asking only
    // pair->listener meant that a TLS broker reported bListening false while
    // its socket was bound and accepting - and because the start path above
    // runs whenever bListening is false, the listener was torn down and rebuilt
    // every two seconds for ever. A client got as far as a completed handshake
    // and then had the connection destroyed underneath it, which looks from
    // the far end exactly like a broker that keeps crashing.
    bListening = pair->listener.isListening()
#if MQTT_TLS_SOCKETS
                || pair->secure.isListening()
#endif
                ;
#endif
}

E_MQTTRESULT User()
{
    bAccountActive = false;
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;

    // The table is made here if this call comes before the broker's first
    // scan, so it is full before the port opens wherever the call is.
    strucpp::XWORD_t handle = (strucpp::XWORD_t)nAccounts;
    MqttBrokerAccounts* accounts = mq_brokerAccounts(handle);
    nAccounts = handle;
    handle = (strucpp::XWORD_t)nUsers;
    MqBrokerUsers* users = mq_brokerUsers(handle);
    nUsers = handle;
    if (accounts == nullptr || users == nullptr) return E_MQTTRESULT::QUOTAEXCEEDED;

    // An account with no name would make anonymous a password.
    if (sUserName.length() == 0) return E_MQTTRESULT::INVALIDARGUMENT;

    MqBrokerUserCall& call = *mq_brokerUserCall(*users, sUserName.c_str());

    // Every scan, deliberately: the arguments are the truth. A password changed
    // on the HMI takes effect on the next connection without a download, and
    // the counters survive because set() only resets them for a NEW account.
    // STRING(64) cannot exceed the field size, so the only way left to fail is
    // a table memory could not grow.
    if (!accounts->set(sUserName.c_str(), sUserPassword.c_str(), (bool)bAllowLogin)) {
        return E_MQTTRESULT::QUOTAEXCEEDED;
    }
    call.seen = true;
    call.retired = false;

    bAccountActive = (bool)bAllowLogin;
    nLoginCount = (int32_t)accounts->logins(sUserName.c_str());
    nRefusedLoginCount = (int32_t)accounts->refusals(sUserName.c_str());
    return E_MQTTRESULT::OK;
}

END_FUNCTION_BLOCK