(* Starts an MQTT client and hands itself to every other block. Call it first.

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

---

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
thread. See docs/10-scan-rate.md. *)

FUNCTION_BLOCK MQTT_CLIENT
  VAR_INPUT
    TRANSPORT : MQTT_LINK;
    SECURITY : MQTT_SECURITY;
    HOST : STRING(64);
    PORT : UINT;
    CLIENT_ID : STRING(48);
    PROTOCOL : MQTT_PROTOCOL;
    EXTERNAL_LINK : __XWORD;
    CONNECT : BOOL := TRUE;
    TRUST_NEW : BOOL;
  END_VAR
  VAR_OUTPUT
    LINK_UP : BOOL;
    CONNECTED : BOOL;
    SESSION_PRESENT : BOOL;
    ASSIGNED_ID : STRING(48);
    STATE : MQTT_STATE;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    LAST_ERROR : STRING(64);
    BROKER_KEY : STRING(64);
  END_VAR

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
    fbPinnedKey : STRING(64);
  END_VAR
  VAR
    (* Whether fbPinnedKey has been handed to the link. NOT retained: a fresh
       program start builds a fresh link and must hand it over again. *)
    fbPinApplied : BOOL;
    (* TRUST_NEW as it was last scan, and whether there has BEEN a last scan.
       The rising edge is what forgets a stored key, and it must not fire at
       program start - a TRUST_NEW wired TRUE would otherwise forget the pin on
       every reboot, which is the one moment retaining it exists for. *)
    fbLastTrust : BOOL;
    fbTrustSeen : BOOL;
  END_VAR
  VAR
    fbApi : __XWORD;
    fbLink : __XWORD;
    fbSettled : BOOL;
    fbTried : BOOL;
    fbRetryAt : DINT;
    fbWanted : BOOL;
    fbConnectAsked : BOOL;
    fbKeepAlive : UINT;
    fbCleanStart : BOOL := TRUE;
    fbSessionExpiry : DINT;
    fbUser : STRING(64);
    fbPassword : STRING(64);
    fbRetryRejected : BOOL;
    fbQueueCapacity : DINT;
    fbRxBuffer : DINT;
    fbTxBuffer : DINT;
    fbReconnectMs : DINT;
    fbReconnectMaxMs : DINT;
    fbConnectTimeoutMs : DINT;
    fbAutoReconnect : BOOL := TRUE;
    fbCaFile : STRING(128);
    fbCertFile : STRING(128);
    fbKeyFile : STRING(128);
    fbSsid : STRING(48);
    fbWifiKey : STRING(64);
    fbMac : STRING(32);
    fbIp : STRING(32);
    fbGateway : STRING(32);
    fbSubnet : STRING(32);
    fbWillTopic : STRING(128);
    fbWillPayload : STRING(128);
    fbWillQos : BYTE;
    fbWillRetain : BOOL;
    fbWillDelayS : DINT;
    (* Written by MQTT_PROVISION, when there is one: the login to connect
       with (its stored one, or "$provision" and the key), ahead of
       MQTT_CONFIG's USERNAME/PASSWORD; and whether the connection is only
       the key's, in which case CONNECTED stays FALSE - it is not this PLC
       yet. Not retained: MQTT_PROVISION keeps its own. *)
    fbProvUser : STRING(64);
    fbProvPassword : STRING(127);
    fbProvisioning : BOOL;
    (* SETTINGS AS THEY WERE WHEN THE LINK WAS BUILT, as two short
       fingerprints: what the medium is made from (TRANSPORT, SECURITY, HOST,
       PORT, the TLS files, the board's network settings) and what the CONNECT
       says (CLIENT_ID, PROTOCOL, the login, keepalive, session, Will). A change
       of either reconnects, the first on a rebuilt medium. Not retained: a
       program start builds from what the pins say anyway. *)
    fbMediumKey : UDINT;
    fbSessionKey : UDINT;
    fbWifiKeyHash : UDINT;
    fbRelink : BOOL;
    fbReconfigure : BOOL;
    fbChangeAt : DINT;
    (* The task this block runs in, for the blocks given it: see MQTT_ARDUINO,
       "ONE TASK PER CLIENT". *)
    fbTask : __XWORD;
  END_VAR
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
// fully vendored, completely unreachable, and SECURITY := MQTT_TLS_VERIFY
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
  // modbee-gsm block, no modem - and MQTT_CELLULAR says so on its pins.
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
    // that first connection and stores it in fbPinnedKey. But the link is
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
    // be learned. What TRUST_NEW's rising edge does when a broker has been
    // replaced on purpose. BOTH halves are needed: a link that was built with
    // a stored pin was never told to skip chain verification, so dropping only
    // the pin would leave it verifying against a system store that has never
    // heard of this broker.
    virtual void forgetKey() {}

    // --- THE CONNECT, OUTSIDE THE SCAN (an ESP32: MqttConnectTask) ---
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
// (TRUST_NEW), report it (BROKER_KEY), and present a certificate.
//
// It replaces three things that each did less: WiFiClientSecure (could not
// pin, never reported the key), nothing at all over Ethernet (it needed
// SSLClient), and the modem's own TLS (encrypted and checked nothing). The
// modem's TLS is still there in modbee-gsm and is deliberately NOT used here,
// for MQTT_TLS_INSECURE included: one engine on every medium is the point,
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
// NOT GIVEN TO THE CONNECT TASK. It is another block's, which may be using it
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

// --- A BOARD'S MEDIUM, FROM A TRANSPORT AND A SECURITY CHOICE ---
//
// MQTT_CLIENT builds its link here - the one block with a TRANSPORT pin, now
// that SPARKPLUG_NODE and SPARKPLUG_HOST ride on its connection - so what a
// board can honour is decided in ONE place.
// The rules are the ones MQTT_CLIENT has always had, and they are about
// honesty: a SECURITY pin that promises a certificate check is refused where
// the medium cannot do one, never quietly downgraded.
//
// ON AN ESP32 EVERY MEDIUM CAN DO EVERY CHECK. The TLS is the library's
// (MqChannelTlsLink above), so Wi-Fi, Ethernet and cellular honour
// MQTT_TLS_VERIFY, MQTT_TLS_PINNED and MQTT_TLS_INSECURE alike, with the
// trust the Runtime uses: the CA from MQTT_CA_CERT_PEM, the pin from the
// block's stored key, and the rule that PINNED with nothing stored needs
// TRUST_NEW. The refusals below the #else are for a board WITHOUT the core's
// mbedTLS, which still has only what its medium offers.
//
// It builds the link and nothing else. Bringing the medium up is not its job:
// the Wi-Fi radio is joined by NETWORK (node-uio) or MQTT_ARDUINO, Ethernet is
// begun by MQTT_CLIENT from MQTT_ARDUINO's MAC, and the modem is GSM_MODEM's.
//
// Null with *status and *why set when it refuses, or when the heap is
// exhausted - an Arduino core builds without exceptions, so that has to be an
// answer rather than a fault.
//
// Static: MQTT_CLIENT is the only block that opens a connection.
#if !defined(MQTT_PLATFORM_HOST)

#if MQTT_CHANNEL_TLS
// A BOARD'S OWN CERTIFICATE, for a broker that wants one, comes from the same
// place as its CA and for the same reason: a PEM does not fit an IEC STRING,
// and a certificate is firmware. MQTT_TLS's CERT_FILE and KEY_FILE stay the
// Runtime's - they are paths, and a board has no files.
#if defined(MQTT_CLIENT_CERT_PEM) != defined(MQTT_CLIENT_KEY_PEM)
#error "mutual TLS on a board needs both MQTT_CLIENT_CERT_PEM and MQTT_CLIENT_KEY_PEM"
#endif

// The trust a TLS link is built with - the Runtime's rules, a board's sources.
template <typename ChannelType>
static MqLink* mq_trustedLink(MqChannelTlsLink<ChannelType>* made,
                              MQTT_SECURITY security, const char* host,
                              uint16_t port, const char* pinnedKey,
                              bool trustNew, MQTT_RESULT* status,
                              const char** why) {
    if (made == nullptr) {
        *status = MQTT_RESULT::MQTT_NOT_INITIALISED;
        *why = "out of memory";
        return nullptr;
    }
    if (security == MQTT_SECURITY::MQTT_TLS_INSECURE) {
        made->tls.setInsecureNoCertificateValidation();
    } else if (security == MQTT_SECURITY::MQTT_TLS_PINNED) {
        // PINNING TRUSTS ONE KEY INSTEAD OF AN AUTHORITY - a ModBee PLC broker
        // or a site's own Mosquitto - and skips chain, name and dates, as the
        // Runtime does. Nothing stored and nobody commissioning is refused
        // rather than connected unchecked: a pinned link that silently trusts
        // anybody is a pinned link in name only.
        if (pinnedKey != nullptr && *pinnedKey != '\0') {
            made->tls.setPinnedKeyFingerprint(pinnedKey);
        } else if (!trustNew) {
            delete made;
            *status = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
            *why = "no pinned key yet - set TRUST_NEW once to learn it";
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
        *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
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

static MqLink* mq_boardLink(MQTT_LINK link, MQTT_SECURITY security,
                            const char* host, uint16_t port,
                            int32_t connectTimeoutMs, const char* pinnedKey,
                            bool trustNew, MQTT_RESULT* status,
                            const char** why) {
    const bool wantsTls = (security != MQTT_SECURITY::MQTT_PLAIN);
    *status = MQTT_RESULT::MQTT_OK;
    *why = "";
    (void)port;
    (void)connectTimeoutMs;
    (void)wantsTls;
    (void)pinnedKey;
    (void)trustNew;

    if (link == MQTT_LINK::MQTT_ARDUINO_WIFI) {
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
            // THE SECURITY PIN DECIDES, AND IT DID NOT USED TO. This chose
            // between setCACert() and setInsecure() with #if
            // defined(MQTT_CA_CERT_PEM) - the PREPROCESSOR - so a board built
            // with a CA silently upgraded MQTT_TLS_INSECURE to a verified
            // connection, and one built without it silently downgraded
            // MQTT_TLS_VERIFY to an unverified one.
            if (security == MQTT_SECURITY::MQTT_TLS_PINNED) {
                // WiFiClientSecure has no key-pinning call - setCACert,
                // setInsecure and a pre-shared key are the whole surface.
                *status = MQTT_RESULT::MQTT_NOT_SUPPORTED_BY_PROTOCOL;
                *why = "MQTT_TLS_PINNED needs an ESP32 or the Runtime";
                return nullptr;
            }
#if !defined(MQTT_CA_CERT_PEM)
            if (security != MQTT_SECURITY::MQTT_TLS_INSECURE) {
                *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                *why = "a board needs the CA in MQTT_CA_CERT_PEM";
                return nullptr;
            }
#endif
            MqWifiTlsLink* w = new (std::nothrow) MqWifiTlsLink();
            if (w) {
                w->host = host;
                if (security == MQTT_SECURITY::MQTT_TLS_INSECURE) {
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
        *status = MQTT_RESULT::MQTT_NOT_INITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        *why = "this board has no WiFi";
        return nullptr;
#endif
    }

    if (link == MQTT_LINK::MQTT_ARDUINO_ETHERNET) {
#if defined(MQ_HAS_ETHERNET)
        if (wantsTls) {
#if MQTT_CHANNEL_TLS
            // TLS OVER ETHERNET, which used to need SSLClient: the Ethernet
            // chip has no TLS, and now it does not need one.
            return mq_trustedLink(new (std::nothrow) MqChannelTlsLink<EthernetClient>(),
                                  security, host, port, pinnedKey, trustNew,
                                  status, why);
#else
            *status = MQTT_RESULT::MQTT_NOT_SUPPORTED_BY_PROTOCOL;
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
        *status = MQTT_RESULT::MQTT_NOT_INITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        *why = "define MQTT_ENABLE_ETHERNET to use Ethernet";
        return nullptr;
#endif
    }

    if (link == MQTT_LINK::MQTT_CELLULAR) {
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
        // MQTT_TLS_INSECURE and nothing more, so the two pins that promise a
        // check are refused rather than quietly downgraded - the same rule the
        // WiFi link follows.
        if (security == MQTT_SECURITY::MQTT_TLS_VERIFY ||
            security == MQTT_SECURITY::MQTT_TLS_PINNED) {
            *status = MQTT_RESULT::MQTT_NOT_SUPPORTED_BY_PROTOCOL;
            *why = "the modem's TLS checks no certificate; use MQTT_TLS_INSECURE";
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
        *status = MQTT_RESULT::MQTT_NOT_INITIALISED;
        *why = "out of memory";
        return nullptr;
#else
        *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        *why = "MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM";
        return nullptr;
#endif
    }

    if (link == MQTT_LINK::MQTT_RUNTIME_TCP) {
        *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        *why = "that transport needs the Runtime, not a board";
        return nullptr;
    }

    // Anything added later. Said plainly rather than silently doing nothing.
    *status = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
    *why = "this board has no such transport";
    return nullptr;
}
#endif

static std::vector<MqNode*> mqOwnedNodes;

namespace {
struct MqNodeCleanup {
    ~MqNodeCleanup() {
        for (size_t i = 0; i < mqOwnedNodes.size(); i++) delete mqOwnedNodes[i];
        mqOwnedNodes.clear();
    }
};
static MqNodeCleanup mqNodeCleanup;
}  // namespace

// How long to wait before trying a failed open again. A refused connection
// fails in microseconds, and a 1 ms task retrying that every scan is a
// thousand identical failures a second in the log.
#define MQ_REOPEN_MS 2000

// MQTT_RESULT mirrors MqttResult member for member, so every block casts
// rather than translates. Asserted here because every project has a client, and
// a member added on one side without the other is a wrong reason code on an
// operator's screen rather than a build error.
static_assert((int)MQTT_RESULT::MQTT_SESSION_TAKEN_OVER + 1 == MQ_RESULT_COUNT,
              "MQTT_RESULT must mirror MqttResult member for member");
static_assert((int)MQTT_RESULT::MQTT_QUEUED == (int)MqttResult::Queued &&
              (int)MQTT_RESULT::MQTT_OK == (int)MqttResult::Ok &&
              (int)MQTT_RESULT::MQTT_CONNECTION_LOST == (int)MqttResult::ConnectionLost,
              "MQTT_RESULT must mirror MqttResult member for member");

// The same for the enumerations the blocks cast rather than translate.
static_assert((int)MQTT_STATE::MQTT_IDLE == (int)MqttState::Idle &&
              (int)MQTT_STATE::MQTT_CONNECTED == (int)MqttState::Connected &&
              (int)MQTT_STATE::MQTT_RECONNECTING == (int)MqttState::Reconnecting,
              "MQTT_STATE must mirror MqttState");

// mq_accepted() and mq_succeeded() come from MqttResult.h. Queued is the
// ordinary answer to anything that reaches the wire later, so a block that
// treated it as a fault would light ERROR on a healthy link.
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
MQTT_QUALITY mq_qualityOf(bool everArrived, bool linkUp, int32_t ageMs,
                          int32_t maxIntervalMs)
{
    if (!everArrived) return MQTT_QUALITY::MQTT_QUALITY_UNKNOWN;
    if (!linkUp)      return MQTT_QUALITY::MQTT_QUALITY_BAD;
    if (maxIntervalMs <= 0) return MQTT_QUALITY::MQTT_QUALITY_GOOD;
    if (ageMs <= maxIntervalMs) return MQTT_QUALITY::MQTT_QUALITY_GOOD;
    if (ageMs <= maxIntervalMs * 2) return MQTT_QUALITY::MQTT_QUALITY_UNCERTAIN;
    return MQTT_QUALITY::MQTT_QUALITY_BAD;
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
// client has opened its link, which is what LINK_UP says.
MqttClient* mq_clientOf(strucpp::XWORD_t handle) {
    return (MqttClient*)(uintptr_t)handle;
}

// --- A DELIBERATE GOODBYE, and whether it carries the Will ---
//
// A layer owns the Will - SPARKPLUG_NODE, SPARKPLUG_HOST - because it is a
// death certificate the plant must see whenever the connection ends: a
// settings change and CONNECT := FALSE included, as Sparkplug requires of an
// intentional disconnect. So the broker is asked to publish it (at 3.1.1 the
// client publishes it, just ahead of the DISCONNECT). An MQTT_PRESENCE Will
// is not owned, and keeps the plain goodbye it has always had.
static uint8_t mq_goodbyeReason(const MqttClient& client) {
    return client.willOwner() != nullptr ? MQ_REASON_DISCONNECT_WITH_WILL
                                         : MQ_REASON_NORMAL_DISCONNECTION;
}

// --- WHAT THE BROKER SAID TO THE LAST CONNECT, in words ---
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
// AND ONLY THE CONNECT'S OWN ANSWER - connectReasonCode, reset before every
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

void setup()
{
    LINK_UP = false;
    CONNECTED = false;
    SESSION_PRESENT = false;
    ASSIGNED_ID = "";
    STATE = MQTT_STATE::MQTT_IDLE;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    LAST_ERROR = "";
    fbApi = (strucpp::XWORD_t)0;
    fbLink = (strucpp::XWORD_t)0;
    // NOT fbPinnedKey, which is retained and is the whole point of being so.
    fbPinApplied = false;
    fbLastTrust = false;
    fbTrustSeen = false;
    fbSettled = false;
    fbTried = false;
    fbRetryAt = 0;
    fbWanted = false;
    fbConnectAsked = false;
    fbMediumKey = 0;
    fbSessionKey = 0;
    fbWifiKeyHash = 0;
    fbRelink = false;
    fbReconfigure = false;
    fbChangeAt = 0;
}

void loop()
{
    fbTask = mq_currentTask();   // every block on this one shares it: see MQTT_ARDUINO
    MqNode* client = (MqNode*)(uintptr_t)(strucpp::XWORD_t)fbLink;

    // What the medium is built from. A change rebuilds it under the same
    // client, so every handle the other blocks hold stays valid.
    auto mediumKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        const int32_t link = (int32_t)(MQTT_LINK)TRANSPORT;
        const int32_t security = (int32_t)(MQTT_SECURITY)SECURITY;
        const uint16_t port = (uint16_t)PORT;
        const uintptr_t external = (uintptr_t)(strucpp::XWORD_t)EXTERNAL_LINK;
        const int32_t timeout = (int32_t)fbConnectTimeoutMs;
        h = mq_fingerprint(h, &link, sizeof link);
        h = mq_fingerprint(h, &security, sizeof security);
        h = mq_fingerprint(h, &port, sizeof port);
        h = mq_fingerprint(h, &external, sizeof external);
        h = mq_fingerprint(h, &timeout, sizeof timeout);
        h = mq_fingerprintText(h, HOST.c_str());
        h = mq_fingerprintText(h, fbCaFile.c_str());
        h = mq_fingerprintText(h, fbCertFile.c_str());
        h = mq_fingerprintText(h, fbKeyFile.c_str());
        h = mq_fingerprintText(h, fbMac.c_str());
        h = mq_fingerprintText(h, fbIp.c_str());
        h = mq_fingerprintText(h, fbGateway.c_str());
        h = mq_fingerprintText(h, fbSubnet.c_str());
        return h;
    };
    // The board's Wi-Fi login, which MQTT_ARDUINO hands to this block.
    auto wifiKey = [&]() -> uint32_t {
        uint32_t h = mq_fingerprintText(2166136261u, fbSsid.c_str());
        return mq_fingerprintText(h, fbWifiKey.c_str());
    };
    // What the CONNECT says. A change reconnects on the same medium.
    // MQTT_PROVISION's login is its own business: it reconnects for itself.
    auto sessionKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        const int32_t protocol = (int32_t)(MQTT_PROTOCOL)PROTOCOL;
        const uint16_t keepAlive = (uint16_t)fbKeepAlive;
        const bool clean = (bool)fbCleanStart;
        const int32_t expiry = (int32_t)fbSessionExpiry;
        const uint8_t qos = (uint8_t)fbWillQos;
        const bool retain = (bool)fbWillRetain;
        const int32_t delay = (int32_t)fbWillDelayS;
        h = mq_fingerprint(h, &protocol, sizeof protocol);
        h = mq_fingerprint(h, &keepAlive, sizeof keepAlive);
        h = mq_fingerprint(h, &clean, sizeof clean);
        h = mq_fingerprint(h, &expiry, sizeof expiry);
        h = mq_fingerprint(h, &qos, sizeof qos);
        h = mq_fingerprint(h, &retain, sizeof retain);
        h = mq_fingerprint(h, &delay, sizeof delay);
        h = mq_fingerprintText(h, CLIENT_ID.c_str());
        h = mq_fingerprintText(h, fbUser.c_str());
        h = mq_fingerprintText(h, fbPassword.c_str());
        h = mq_fingerprintText(h, fbWillTopic.c_str());
        h = mq_fingerprintText(h, fbWillPayload.c_str());
        return h;
    };
    // What the client is told on CONNECT, from the pins and the helpers as
    // they are now. Used when the link is built and again when the session
    // settings change.
    auto buildConnection = [&](const std::string& host, uint16_t port) -> MqttConnectionConfig {
        MqttConnectionConfig connection;
        connection.host = host;
        connection.port = port;
        connection.clientId = std::string(CLIENT_ID.c_str(), CLIENT_ID.length());
        connection.keepAlive = (uint16_t)fbKeepAlive != 0
            ? (uint16_t)fbKeepAlive : 60;
        connection.cleanStart = (bool)fbCleanStart;
        if ((int32_t)fbSessionExpiry > 0) {
            connection.sessionExpiryInterval = (uint32_t)(int32_t)fbSessionExpiry;
            connection.hasSessionExpiry = true;
        }
        // Asking with MQTT_PROVISION's key: a registration session, which sends
        // no Will (MQTT_PRESENCE's or SPARKPLUG_NODE's) - it may publish nothing
        // but its request, and a broker refuses a Will it may not publish.
        connection.registration = (bool)fbProvisioning;
        if (fbProvUser.length() > 0) {
            // MQTT_PROVISION's login wins: it is either the one this PLC was
            // given, or the key it is about to ask with.
            connection.hasUserName = true;
            connection.userName = std::string(fbProvUser.c_str(), fbProvUser.length());
            connection.hasPassword = true;
            const char* pw = fbProvPassword.c_str();
            connection.password.assign(pw, pw + fbProvPassword.length());
        } else {
            if (fbUser.length() > 0) {
                connection.hasUserName = true;
                connection.userName = std::string(fbUser.c_str(), fbUser.length());
            }
            if (fbPassword.length() > 0) {
                connection.hasPassword = true;
                const char* pw = fbPassword.c_str();
                connection.password.assign(pw, pw + fbPassword.length());
            }
        }

        const MQTT_PROTOCOL wanted = (MQTT_PROTOCOL)PROTOCOL;
        if (wanted == MQTT_PROTOCOL::MQTT_V311) {
            connection.version = MqttVersion::V311;
        } else {
            connection.version = MqttVersion::V5;
            // Fallback triggers only on evidence the VERSION is the problem -
            // a 5.0 reason 0x84, or a 3.1.1 return code 0x01. Never on an
            // authentication or network failure, because treating those as a
            // version problem hides them.
            connection.fallbackEnabled =
                (wanted == MQTT_PROTOCOL::MQTT_V5_THEN_V311);
        }

        if (fbWillTopic.length() > 0) {
            connection.will.set(fbWillTopic.c_str(), fbWillPayload.c_str(),
                                (uint8_t)fbWillQos, (bool)fbWillRetain);
            if ((int32_t)fbWillDelayS > 0) {
                connection.will.delayInterval = (uint32_t)(int32_t)fbWillDelayS;
            }
        }

        return connection;
    };

    // Asked to stand down. The connection closes and the object stays: the
    // pins that describe it have not changed, and rebuilding it would lose
    // every subscription and topic handle the other blocks registered.
    const bool want = (bool)CONNECT;
    if (!want) {
        if (client) {
            if ((bool)LINK_UP) client->client.disconnect(mq_goodbyeReason(client->client));
            // Still polled, so the DISCONNECT actually leaves and the broker
            // sees a deliberate goodbye rather than a lost link.
            client->client.poll();
            STATE = (MQTT_STATE)(int32_t)(int)client->client.status().state;
        } else {
            STATE = MQTT_STATE::MQTT_IDLE;
        }
        LINK_UP = false;
        CONNECTED = false;
        fbTried = false;
        fbConnectAsked = false;
        fbWanted = false;
        return;
    }

    if (!(bool)LINK_UP) {
        // ONE SCAN BEFORE OPENING.
        //
        // MQTT_CONFIG, MQTT_TLS, MQTT_ARDUINO and MQTT_PRESENCE write into
        // this instance, and they may sit above or below this block in the
        // rung order. Waiting a scan means every one of them has run at least
        // once before the link is built, so a helper does not have to be
        // placed anywhere in particular - which is a rule nobody would
        // remember and the compiler could not check.
        //
        // It costs one scan of the fast task. Opening a socket takes longer
        // than that on its own.
        if (!(bool)fbSettled) {
            fbSettled = true;
            return;
        }

        const mq_time_t now = mq_millis();
        if ((bool)fbTried &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbRetryAt) < 0) {
            return;
        }
        // A SETTINGS CHANGE IS UNDER WAY: let the DISCONNECT on the old
        // settings leave first (a second at most), so the broker sees a
        // goodbye rather than a dropped socket and publishes no Will.
        if (client && ((bool)fbRelink || (bool)fbReconfigure) &&
            client->client.status().state == MqttState::Disconnecting &&
            (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbChangeAt) < 1000) {
            client->client.poll();
            return;
        }

        fbTried = true;
        fbRetryAt = (int32_t)(uint32_t)(now + MQ_REOPEN_MS);

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
        if (client && !(bool)fbRelink) {
            if ((bool)fbReconfigure) {
                // The session settings changed (login, client id, version,
                // keepalive, Will): the next CONNECT says the new ones. The
                // medium is the same, so the host and port are the link's.
                const uint16_t samePort = (uint16_t)PORT != 0
                    ? (uint16_t)PORT
                    : (uint16_t)(SECURITY != MQTT_SECURITY::MQTT_PLAIN ? MQ_PORT_TLS
                                                                       : MQ_PORT_TCP);
                const std::string sameHost = client->link ? client->link->host : std::string();
                client->client.reconfigure(buildConnection(sameHost, samePort));
                fbReconfigure = false;
            }
            LINK_UP = true;
            fbConnectAsked = false;
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
            LAST_ERROR = "";
            // Fall through to connect() below on this same scan.
        } else {

        // A rebuilt medium is told the stored key afresh, as a new one is.
        fbPinApplied = false;

        // --- build the medium -------------------------------------------
        //
        // Inline rather than in a helper because a free function cannot see
        // the pins: they are macros over a `vars` struct that exists only
        // inside this function.
        const MQTT_LINK link = (MQTT_LINK)TRANSPORT;
        const MQTT_SECURITY security = (MQTT_SECURITY)SECURITY;
        const bool wantsTls = (security != MQTT_SECURITY::MQTT_PLAIN);
        const bool runtimeLink = (link == MQTT_LINK::MQTT_RUNTIME_TCP);
        const bool external = (link == MQTT_LINK::MQTT_LINK_EXTERNAL);

#if defined(MQTT_PLATFORM_HOST)
        if (!runtimeLink && !external) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "that transport needs a board, not the Runtime";
            return;
        }
#else
        if (runtimeLink) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "that transport needs the Runtime, not a board";
            return;
        }
#endif

        if (!external && HOST.length() == 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "set HOST to the broker";
            return;
        }

        const uint16_t port = (uint16_t)PORT != 0
            ? (uint16_t)PORT
            : (uint16_t)(wantsTls ? MQ_PORT_TLS : MQ_PORT_TCP);

        MqLink* made = nullptr;

        if (external) {
            MqttTransport* borrowed =
                (MqttTransport*)(uintptr_t)(strucpp::XWORD_t)EXTERNAL_LINK;
            if (!borrowed) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                LAST_ERROR = "MQTT_LINK_EXTERNAL needs a transport on EXTERNAL_LINK";
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
                tcp->host = std::string(HOST.c_str(), HOST.length());
                tcp->tcp.configure(tcp->host.c_str(), port);
            }
            made = tcp;
        } else {
#if MQTT_TLS_AVAILABLE
            MqTlsLink* tls = new (std::nothrow) MqTlsLink();
            if (tls) {
                tls->host = std::string(HOST.c_str(), HOST.length());
                tls->tls.configure(tls->host.c_str(), port);
                if (fbCaFile.length() > 0) tls->tls.setCaFile(fbCaFile.c_str());
#if defined(MQTT_CA_CERT_PEM)
                tls->tls.setCaCertificate(MQTT_CA_CERT_PEM);
#endif
                if (fbCertFile.length() > 0 && fbKeyFile.length() > 0) {
                    tls->tls.setClientCertificate(fbCertFile.c_str(),
                                                  fbKeyFile.c_str());
                }
                // Named at length in the library on purpose, and named here
                // too: this is the pin that turns a verified connection into
                // an encrypted conversation with whoever answered.
                if (security == MQTT_SECURITY::MQTT_TLS_INSECURE) {
                    tls->tls.setInsecureNoCertificateValidation();
                } else if (security == MQTT_SECURITY::MQTT_TLS_PINNED) {
                    // PINNING TRUSTS ONE KEY INSTEAD OF AN AUTHORITY, which is
                    // the only thing that can be done about a broker nobody
                    // signed for - a ModBee PLC broker, or a site's own
                    // Mosquitto. It deliberately skips chain and expiry
                    // checking: a controller with no clock cannot judge an
                    // expiry date, and a link that drops because a PLC booted
                    // believing it is 1970 is worse than one that trusts a key
                    // it recognises.
                    if (fbPinnedKey.length() > 0) {
                        tls->tls.setPinnedKeyFingerprint(fbPinnedKey.c_str());
                        fbPinApplied = true;
                    } else if (!TRUST_NEW) {
                        // Nothing stored and nobody commissioning. Refused
                        // rather than connected unchecked, because a pinned
                        // link that silently falls back to trusting anybody is
                        // a pinned link in name only.
                        delete tls;
                        ERROR = true;
                        STATUS = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
                        LAST_ERROR = "no pinned key yet - set TRUST_NEW once to learn it";
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
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "this build has no TLS - no OpenSSL on the target";
            return;
#endif
        }
#else   // Arduino
        else if (link == MQTT_LINK::MQTT_ARDUINO_WIFI) {
#if defined(MQ_HAS_WIFI)
            // Nobody else can bring the radio up: an OpenPLC program has no
            // sketch to put a setup() in, so the client does it from the pins
            // MQTT_ARDUINO supplies.
            if (fbSsid.length() > 0 && WiFi.status() != WL_CONNECTED) {
                WiFi.begin(fbSsid.c_str(),
                           fbWifiKey.length() > 0 ? fbWifiKey.c_str() : nullptr);
            }
            if (WiFi.status() != WL_CONNECTED) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                LAST_ERROR = fbSsid.length() > 0
                    ? "joining the WiFi network"
                    : "set SSID on MQTT_ARDUINO";
                return;     // retried on this block's own timer
            }
            // The link itself - and what SECURITY a board can honour - is
            // mq_boardLink()'s.
            {
                MQTT_RESULT refusedAs = MQTT_RESULT::MQTT_OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, HOST.c_str(), port,
                                    (int32_t)fbConnectTimeoutMs,
                                    fbPinnedKey.c_str(), (bool)TRUST_NEW,
                                    &refusedAs, &refusal);
                if (!made) {
                    ERROR = true;
                    STATUS = refusedAs;
                    LAST_ERROR = refusal;
                    return;
                }
                if (security == MQTT_SECURITY::MQTT_TLS_PINNED &&
                    fbPinnedKey.length() > 0) {
                    fbPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "this board has no WiFi";
            return;
#endif
        } else if (link == MQTT_LINK::MQTT_ARDUINO_ETHERNET) {
#if defined(MQ_HAS_ETHERNET)
#if !MQTT_CHANNEL_TLS
            // Refused before DHCP, not after it: a board without the core's
            // mbedTLS has no TLS for an Ethernet chip. An ESP32 has - see
            // mq_boardLink().
            if (wantsTls) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_NOT_SUPPORTED_BY_PROTOCOL;
                LAST_ERROR = "TLS over Ethernet needs an ESP32, or SSLClient; use external";
                return;
            }
#endif
            // A fixed address, unless MQTT_ARDUINO asked for DHCP. DHCP BLOCKS
            // - up to sixty seconds in the Arduino library, which on a 1 ms
            // task is not a delay, it is a stopped PLC. Bounded to one second
            // here and retried by this block's own timer instead.
            uint8_t mac[6] = {0};
            if (!mq_parseMac(fbMac.c_str(), mac)) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                LAST_ERROR = "set MAC on MQTT_ARDUINO - each board needs one";
                return;
            }
            if (fbIp.length() == 0 || strcmp(fbIp.c_str(), "dhcp") == 0) {
                if (Ethernet.begin(mac, 1000, 1000) == 0) {
                    ERROR = true;
                    STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
                    LAST_ERROR = "no DHCP lease - set IP on MQTT_ARDUINO";
                    return;
                }
            } else {
                IPAddress ip;
                if (!ip.fromString(fbIp.c_str())) {
                    ERROR = true;
                    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                    LAST_ERROR = "IP on MQTT_ARDUINO is not an address";
                    return;
                }
                Ethernet.begin(mac, ip);
            }
            {
                MQTT_RESULT refusedAs = MQTT_RESULT::MQTT_OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, HOST.c_str(), port,
                                    (int32_t)fbConnectTimeoutMs,
                                    fbPinnedKey.c_str(), (bool)TRUST_NEW,
                                    &refusedAs, &refusal);
                if (!made) {
                    ERROR = true;
                    STATUS = refusedAs;
                    LAST_ERROR = refusal;
                    return;
                }
                if (security == MQTT_SECURITY::MQTT_TLS_PINNED &&
                    fbPinnedKey.length() > 0) {
                    fbPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "define MQTT_ENABLE_ETHERNET to use Ethernet";
            return;
#endif
        } else if (link == MQTT_LINK::MQTT_CELLULAR) {
#if defined(MQ_HAS_CELLULAR)
            // The policy - which SECURITY a cellular link can honour, and
            // whose TLS it is - is mq_boardLink()'s.
            // Opening blocks - Arduino's Client::connect() must return a
            // verdict - so it is bounded by CONNECT_TIMEOUT, 20 s unset. It
            // blocks the connect task, not the scan.
            {
                MQTT_RESULT refusedAs = MQTT_RESULT::MQTT_OK;
                const char* refusal = "";
                made = mq_boardLink(link, security, HOST.c_str(), port,
                                    (int32_t)fbConnectTimeoutMs,
                                    fbPinnedKey.c_str(), (bool)TRUST_NEW,
                                    &refusedAs, &refusal);
                if (!made) {
                    ERROR = true;
                    STATUS = refusedAs;
                    LAST_ERROR = refusal;
                    return;
                }
                if (security == MQTT_SECURITY::MQTT_TLS_PINNED &&
                    fbPinnedKey.length() > 0) {
                    fbPinApplied = true;   // built with it, as the Runtime's is
                }
            }
#else
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM";
            return;
#endif
        } else {
            // Anything added later. Said plainly rather than silently doing
            // nothing.
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "this board has no such transport";
            return;
        }
#endif

        if (!made) {
            // Arduino cores build without exceptions, so an exhausted heap has
            // to be handled here or it is a hard fault. The client refuses to
            // start and says so; it does not take the PLC down.
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            LAST_ERROR = "out of memory";
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
            fbRelink = false;
            fbReconfigure = false;
        } else {

        MqNode* fresh = new (std::nothrow) MqNode();
        if (!fresh) {
            delete made;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            LAST_ERROR = "out of memory";
            return;
        }
        fresh->link = made;

        MqttClientConfig behaviour;
        if ((int32_t)fbQueueCapacity > 0) {
            behaviour.queueCapacity = (size_t)(int32_t)fbQueueCapacity;
        }
        if ((int32_t)fbRxBuffer > 0) {
            behaviour.receiveBufferSize = (size_t)(int32_t)fbRxBuffer;
        }
        if ((int32_t)fbTxBuffer > 0) {
            behaviour.transmitBufferSize = (size_t)(int32_t)fbTxBuffer;
        }
        if ((int32_t)fbReconnectMs > 0) {
            behaviour.reconnectInitialMs = (mq_time_t)(int32_t)fbReconnectMs;
        }
        if ((int32_t)fbReconnectMaxMs > 0) {
            behaviour.reconnectMaximumMs = (mq_time_t)(int32_t)fbReconnectMaxMs;
        }
        if ((int32_t)fbConnectTimeoutMs > 0) {
            behaviour.connectTimeoutMs = (mq_time_t)(int32_t)fbConnectTimeoutMs;
        }
        behaviour.autoReconnect = (bool)fbAutoReconnect;

        // OFF UNLESS MQTT_CONFIG ASKED FOR IT. After a CONNACK that rejected
        // the credential the library does not retry at the network backoff -
        // a PLC repeating a rejected password every second is how a site gets
        // itself banned - but every five minutes, never giving up, so a remote
        // site whose broker is fixed at the other end comes back by itself.
        behaviour.retryRejectedCredentials = (bool)fbRetryRejected;

        fresh->client.begin(fresh->link->clientTransport(), connection, behaviour);

        mqOwnedNodes.push_back(fresh);
        fbLink = (strucpp::XWORD_t)(uintptr_t)fresh;
        fbApi = (strucpp::XWORD_t)(uintptr_t)&fresh->client;
        }   // end of the "first build" branch

        // What the link was built from, for the change check below.
        fbMediumKey = mediumKey();
        fbSessionKey = sessionKey();
        fbWifiKeyHash = wifiKey();
        }   // end of the "not already built" branch

        LINK_UP = true;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        LAST_ERROR = "";
        client = (MqNode*)(uintptr_t)(strucpp::XWORD_t)fbLink;
    }

    if (!client) return;

    // --- RECONNECT WHEN THE SETTINGS CHANGE ---
    //
    // The pins and the helper blocks are read every scan, and a client used to
    // take them once, when it was built: a broker address, a port, a login or
    // TLS changed on the HMI did nothing until the PLC was restarted. Now a
    // change says goodbye on the old settings and comes back on the new ones,
    // on the same client - the medium rebuilt when what it is made from
    // changed, the CONNECT rewritten when only the session did.
    //
    // A PINNED KEY IS NOT FORGOTTEN BY A NEW ADDRESS. A different broker shows
    // a different key and is refused until TRUST_NEW is switched off and on,
    // exactly as a replaced broker is: an address typed on a panel must not be
    // a way round the pin.
    {
        const uint32_t medium = mediumKey();
        const uint32_t session = sessionKey();
        const uint32_t wifi = wifiKey();
        if (medium != (uint32_t)fbMediumKey || session != (uint32_t)fbSessionKey ||
            wifi != (uint32_t)fbWifiKeyHash) {
            const bool relink = medium != (uint32_t)fbMediumKey ||
                                wifi != (uint32_t)fbWifiKeyHash;
#if defined(MQ_HAS_WIFI)
            // The Wi-Fi this block joined itself (MQTT_ARDUINO's SSID) is left
            // and joined again with the new login. A radio NETWORK or anyone
            // else brought up is not this block's to drop.
            if (wifi != (uint32_t)fbWifiKeyHash && fbSsid.length() > 0 &&
                (MQTT_LINK)TRANSPORT == MQTT_LINK::MQTT_ARDUINO_WIFI) {
                WiFi.disconnect();
            }
#endif
            fbMediumKey = medium;
            fbSessionKey = session;
            fbWifiKeyHash = wifi;
            fbRelink = (bool)fbRelink || relink;
            fbReconfigure = true;
            fbChangeAt = (int32_t)(uint32_t)mq_millis();
            if (client->client.isConnected()) {
                client->client.disconnect(mq_goodbyeReason(client->client));
            }
            client->client.poll();
            LINK_UP = false;
            CONNECTED = false;
            fbConnectAsked = false;
            fbTried = false;
            STATE = (MQTT_STATE)(int32_t)(int)client->client.status().state;
            return;
        }
    }

    // Ask once. connect() queues the intent and returns; whether it arrived
    // is what CONNECTED answers on a later scan.
    if (!(bool)fbConnectAsked) {
        const MqttResult asked = client->client.connect();
        fbConnectAsked = true;
        if (!mq_tolerated(asked)) {
            ERROR = true;
            STATUS = (MQTT_RESULT)(int32_t)(int)asked;
            LAST_ERROR = "the broker could not be asked - see STATUS";
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
    CONNECTED = client->client.isConnected() && !(bool)fbProvisioning;
    STATE = (MQTT_STATE)(int32_t)(int)status.state;
    SESSION_PRESENT = client->client.capabilities().sessionPresent;

    // The broker may assign one when we sent an empty identifier, and a
    // device that cannot report what it is called is a device nobody can find
    // in the broker's own logs.
    const MqttSpan& assigned = client->client.capabilities().assignedClientIdentifier;
    if (!assigned.empty()) {
        ASSIGNED_ID = std::string((const char*)assigned.data, assigned.length).c_str();
    } else {
        ASSIGNED_ID = CLIENT_ID.c_str();
    }

    // WHAT THE BROKER ACTUALLY PRESENTED, on a pin, whether or not anything is
    // pinned. An engineer commissioning a plant reads this off the panel and
    // writes it down; an engineer diagnosing one compares it with what they
    // wrote down last year. A fingerprint that can only be inferred is a
    // fingerprint nobody checks.
    if (client->link != nullptr) {
        const char* seen = client->link->seenKey();
        BROKER_KEY = (seen != nullptr) ? seen : "";

        // --- TRUST_NEW, AND WHAT IT NOW MEANS ---
        //
        // Trust on first use, the way SSH does it. With TRUST_NEW on and
        // nothing stored, the first key the broker shows is learned and kept.
        // ONCE LEARNED IT IS ENFORCED, whether TRUST_NEW stays on or not, and
        // across restarts - so a TRUST_NEW left wired TRUE, which is what most
        // projects do, still protects the link after its first connection.
        //
        // A BROKER REPLACED ON PURPOSE is refused like any other: both
        // fingerprints on the Runtime, "TLS: not the pinned key" on a board,
        // with the key it showed on BROKER_KEY. To accept it, switch TRUST_NEW
        // off and on: the rising
        // edge forgets the stored key, and the next connection learns its
        // replacement.
        //
        // THIS REPLACES A RULE THAT WAS NEVER TRUE. The block used to say a
        // reinstalled broker was "silently trusted" while TRUST_NEW was left
        // on. In fact the pin was enforced after any restart regardless, and
        // within a run it was never applied at all - so a new broker was let
        // in but its key was never stored, and the PLC then refused that same
        // broker after its next reboot. And there was no way for an operator
        // to accept a legitimately replaced broker short of a new program.
        const bool trusting = (bool)TRUST_NEW;
        if ((bool)fbTrustSeen && trusting && !(bool)fbLastTrust &&
            SECURITY == MQTT_SECURITY::MQTT_TLS_PINNED) {
            fbPinnedKey = "";
            fbPinApplied = false;
            client->link->forget();
        }
        fbLastTrust = trusting;
        fbTrustSeen = true;

        if (CONNECTED && trusting &&
            SECURITY == MQTT_SECURITY::MQTT_TLS_PINNED &&
            fbPinnedKey.length() == 0 && seen != nullptr && *seen != '\0') {
            fbPinnedKey = seen;
        }

        // APPLIED AS SOON AS IT IS KNOWN, including the key just learned on
        // the line above. Without this fbPinnedKey is only a stored string and
        // the link was built before there was anything to put in it. See
        // MqLink::pinKey().
        if (!(bool)fbPinApplied && fbPinnedKey.length() > 0 &&
            SECURITY == MQTT_SECURITY::MQTT_TLS_PINNED) {
            client->link->pin(fbPinnedKey.c_str());
            fbPinApplied = true;
        }
    }

    if (status.lastError != MqttResult::Ok && !CONNECTED) {
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)status.lastError;

        // THE MOST RECENT ANSWER, BUILT FRESH EVERY SCAN.
        //
        // LAST_ERROR is an output, so it PERSISTS - and this used to only
        // overwrite it when it had something new to say. A pump whose account
        // was revoked during a broker restart failed its TLS handshakes while
        // the broker was down, and then was refused by the broker once it was
        // back - and its panel went on reading "TLS handshake failed: error
        // state on socket" for the rest of the day, because the credential
        // sentence below only ran when LAST_ERROR was empty, and it never was
        // again. The wrong fault, shown confidently, is worse than none.
        //
        // So: the CONNACK first. connectReasonCode is reset before every
        // attempt, so a refusal there IS the latest attempt's answer, and the
        // single most likely commissioning fault - a wrong password - is one
        // the transport cannot see at all: the TCP and TLS layers succeeded.
        std::string sentence = mq_connectRefusal(client->client);

        // Then THE TRANSPORT'S OWN WORDS, which TLS is where they matter:
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
        LAST_ERROR = sentence.c_str();
    } else if (CONNECTED) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;

        // AND THE REASON THE LAST ATTEMPT FAILED GOES WITH IT. A connected
        // link beside a sentence saying the broker refused the connection is
        // the log line nobody can act on: a fallback tries 5.0, is refused,
        // retries at 3.1.1 and succeeds, and the pin kept the refusal for
        // ever. LINK_UP and LAST_ERROR have to agree.
        LAST_ERROR = "";
    }

    // The topic and subscription tables grow with the program, on a board and
    // the Runtime alike, and only memory ends them: when it did, that is
    // said, connected or not. The block that was refused shows
    // MQTT_QUEUE_FULL on its own STATUS.
    if (client->client.outOfMemory()) {
        LAST_ERROR = "out of memory for topics or subscriptions";
    }
    // MAX_PENDING is taken when the client is made; if the memory for it was
    // not there, the queue kept its size, and a PLC told it could hold more
    // than it does would lose data at the next outage without a word.
    if (client->client.queueOutOfMemory()) {
        char line[80];
        snprintf(line, sizeof line, "out of memory for MAX_PENDING - the queue holds %u",
                 (unsigned)client->client.operations().capacity());
        LAST_ERROR = line;
    }
}

END_FUNCTION_BLOCK