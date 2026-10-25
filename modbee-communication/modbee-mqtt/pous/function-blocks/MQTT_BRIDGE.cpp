(* Carries topics between two brokers. Standalone - it owns both connections and
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

---

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
MQTT_INVALID_ARGUMENT rather than accepted and regretted. *)

FUNCTION_BLOCK MQTT_BRIDGE
  VAR_INPUT
    ENABLE : BOOL := TRUE;
    LOCAL_HOST : STRING(64);
    LOCAL_PORT : UINT;
    LOCAL_SECURITY : MQTT_SECURITY;
    REMOTE_HOST : STRING(64);
    REMOTE_PORT : UINT;
    REMOTE_SECURITY : MQTT_SECURITY;
    REMOTE_USER : STRING(64);
    REMOTE_PASSWORD : STRING(64);
    BRIDGE_NAME : STRING(48);
    TOPIC : STRING(128);
    DIRECTION : MQTT_DIRECTION;
    QOS : BYTE;
    LOCAL_PREFIX : STRING(64);
    REMOTE_PREFIX : STRING(64);
    FORWARD_RETAINED : BOOL;
  END_VAR
  VAR_OUTPUT
    STATE : MQTT_BRIDGE_STATE;
    LOCAL_UP : BOOL;
    REMOTE_UP : BOOL;
    FORWARDED_OUT : DINT;
    FORWARDED_IN : DINT;
    REFUSED_OUT : DINT;
    REFUSED_IN : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR
    fbBridge : __XWORD;
    fbSettled : BOOL;
    fbStarted : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <string>
#include <vector>
#include <new>
#include <string.h>

namespace {

// MqttResult and MQTT_RESULT are declared in the same order on purpose, so a
// result becomes a pin without a 29-arm switch that would have to be edited
// twice every time a reason code is added. The same cast is in MQTT_PUBLISH.
static MQTT_RESULT mqPin(MqttResult result) {
    return (MQTT_RESULT)(int32_t)(int)result;
}

// Both connections, the bridge over them and the host strings they point at,
// with one lifetime. MqttStreamTransport keeps a host as a POINTER, so the
// strings have to outlive the transports.
struct MqBridgeRig {
    MqttBridge bridge;
    MqttBridgeConfig config;
    std::string localHost;
    std::string remoteHost;
    MqttTransport* local = nullptr;
    MqttTransport* remote = nullptr;
#if defined(MQTT_PLATFORM_HOST)
    MqttTcpTransport localTcp;
    MqttTcpTransport remoteTcp;
#if MQTT_TLS_AVAILABLE
    // Named ...Transport so the struct member cannot be confused with the
    // local "is this end encrypted" flags in loop(), which it silently was.
    MqttTlsTransport localTlsTransport;
    MqttTlsTransport remoteTlsTransport;
#endif
#endif
    ~MqBridgeRig() { bridge.stop(); }
};
}  // namespace

static std::vector<MqBridgeRig*> mqOwnedBridges;

namespace {
struct MqBridgeCleanup {
    ~MqBridgeCleanup() {
        for (size_t i = 0; i < mqOwnedBridges.size(); i++) delete mqOwnedBridges[i];
        mqOwnedBridges.clear();
    }
};
static MqBridgeCleanup mqBridgeCleanup;
}  // namespace

void setup()
{
    STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_IDLE;
    LOCAL_UP = false;
    REMOTE_UP = false;
    FORWARDED_OUT = 0;
    FORWARDED_IN = 0;
    REFUSED_OUT = 0;
    REFUSED_IN = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbBridge = (strucpp::XWORD_t)0;
    fbSettled = false;
    fbStarted = false;
}

void loop()
{
#if !defined(MQTT_PLATFORM_HOST)
    // A bridge is two simultaneous connections, two sessions and two send
    // queues, and one of them is usually TLS to a cloud broker. On an ESP32
    // that is most of the heap before the ladder logic gets any - so this is
    // a Runtime block, said plainly on the pins rather than half-built.
    //
    // The shape that works on a board is MQTT_BROKER on the panel, serving
    // the line, and the bridge upstream running on a Runtime. See page 11.
    ERROR = true;
    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
#else
    MqBridgeRig* rig = (MqBridgeRig*)(uintptr_t)(strucpp::XWORD_t)fbBridge;

    if (!(bool)ENABLE) {
        if (rig) {
            rig->bridge.stop();
            rig->config.topics.clear();
        }
        STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_IDLE;
        LOCAL_UP = false;
        REMOTE_UP = false;
        fbStarted = false;
        fbSettled = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (!rig) {
        rig = new (std::nothrow) MqBridgeRig();
        if (!rig) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            return;
        }
        mqOwnedBridges.push_back(rig);
        fbBridge = (strucpp::XWORD_t)(uintptr_t)rig;
    }

    // ONE INSTANCE, MANY RULES, and this is the half that makes it work.
    //
    // Every call in a scan adds its TOPIC to the mapping, so a site carrying
    // three topic trees is one block called three times rather than three
    // bridges with three pairs of connections. The rules are collected for a
    // whole scan and the connections built on the next one, which is why a
    // rule added later in the program still arrives before either end
    // connects - the same reason the client and the broker wait one scan.
    if (!(bool)fbStarted) {
        if (TOPIC.length() > 0) {
            MqttBridgeTopic rule;
            rule.filter = TOPIC.c_str();
            switch (DIRECTION) {
                case MQTT_DIRECTION::MQTT_IN:
                    rule.direction = MqttBridgeDirection::In; break;
                case MQTT_DIRECTION::MQTT_BOTH:
                    rule.direction = MqttBridgeDirection::Both; break;
                default:
                    rule.direction = MqttBridgeDirection::Out; break;
            }
            uint8_t qos = (uint8_t)(strucpp::BYTE_t)QOS;
            if (qos > MQ_QOS_2) qos = MQ_QOS_2;
            rule.qos = qos;
            rule.localPrefix = LOCAL_PREFIX.c_str();
            rule.remotePrefix = REMOTE_PREFIX.c_str();
            rule.forwardRetain = (bool)FORWARD_RETAINED;

            // A rule repeated in the same scan is one rule, not two. A block
            // called in a loop, or on both a rising edge and a level, would
            // otherwise subscribe twice and forward every message twice.
            bool already = false;
            for (size_t i = 0; i < rig->config.topics.size(); i++) {
                const MqttBridgeTopic& seen = rig->config.topics[i];
                if (seen.filter == rule.filter &&
                    seen.direction == rule.direction &&
                    seen.localPrefix == rule.localPrefix &&
                    seen.remotePrefix == rule.remotePrefix) {
                    already = true;
                    break;
                }
            }
            if (!already) rig->config.topics.push_back(rule);
        }

        if (!(bool)fbSettled) {
            fbSettled = true;
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
            STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_IDLE;
            return;
        }

        if (rig->config.topics.empty()) {
            // Nothing to carry. Refused rather than started, because a bridge
            // with no rules is two connections and a session on each broker
            // doing nothing, which looks healthy on every pin.
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }

        // --- The two connections ---

        rig->localHost = LOCAL_HOST.c_str();
        rig->remoteHost = REMOTE_HOST.c_str();
        if (rig->localHost.empty() || rig->remoteHost.empty()) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }

        const MQTT_SECURITY localSecurity = LOCAL_SECURITY;
        const MQTT_SECURITY remoteSecurity = REMOTE_SECURITY;
        const bool localTls = (localSecurity != MQTT_SECURITY::MQTT_PLAIN);
        const bool remoteTls = (remoteSecurity != MQTT_SECURITY::MQTT_PLAIN);

#if !MQTT_TLS_AVAILABLE
        if (localTls || remoteTls) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
#else
        // MQTT_TLS_PINNED NEEDS A KEY, AND THIS BLOCK HAS NO PIN FOR ONE.
        //
        // Refused rather than quietly downgraded to MQTT_TLS_VERIFY, which is
        // what "pin if you can, otherwise verify" would mean: the two trust
        // nothing in common, and a bridge that verified against the system
        // store when the engineer asked it to pin one key is trusting every
        // public CA instead of exactly one broker. Put the pinned end on an
        // MQTT_CLIENT, which has TRUST_NEW and PINNED_KEY.
        if (localSecurity == MQTT_SECURITY::MQTT_TLS_PINNED ||
            remoteSecurity == MQTT_SECURITY::MQTT_TLS_PINNED) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
#endif

        const uint16_t localPort = (uint16_t)LOCAL_PORT != 0
            ? (uint16_t)LOCAL_PORT
            : (localTls ? (uint16_t)MQ_PORT_TLS : (uint16_t)MQ_PORT_TCP);
        const uint16_t remotePort = (uint16_t)REMOTE_PORT != 0
            ? (uint16_t)REMOTE_PORT
            : (remoteTls ? (uint16_t)MQ_PORT_TLS : (uint16_t)MQ_PORT_TCP);

        if (!localTls) {
            rig->localTcp.configure(rig->localHost.c_str(), localPort);
            rig->local = &rig->localTcp;
        }
        if (!remoteTls) {
            rig->remoteTcp.configure(rig->remoteHost.c_str(), remotePort);
            rig->remote = &rig->remoteTcp;
        }
#if MQTT_TLS_AVAILABLE
        if (localTls) {
            rig->localTlsTransport.configure(rig->localHost.c_str(), localPort);
            if (localSecurity == MQTT_SECURITY::MQTT_TLS_INSECURE) {
                rig->localTlsTransport.setInsecureNoCertificateValidation();
            }
            rig->local = &rig->localTlsTransport;
        }
        if (remoteTls) {
            rig->remoteTlsTransport.configure(rig->remoteHost.c_str(), remotePort);
            if (remoteSecurity == MQTT_SECURITY::MQTT_TLS_INSECURE) {
                rig->remoteTlsTransport.setInsecureNoCertificateValidation();
            }
            rig->remote = &rig->remoteTlsTransport;
        }
#endif

        // --- Identity, and why it is two ---

        std::string name = BRIDGE_NAME.c_str();
        if (name.empty()) name = "bridge";
        rig->config.name = name;

        // THE TWO IDENTIFIERS MUST DIFFER. [V5:MQTT-3.1.4-3] means a second
        // connection using an existing client identifier displaces the first,
        // so a bridge using one name on both ends takes over its own session
        // the moment both brokers turn out to be the same box - which happens
        // on a bench more often than anyone expects.
        rig->config.local.host = rig->localHost;
        rig->config.local.port = localPort;
        rig->config.local.clientId = name + "-local";

        rig->config.remote.host = rig->remoteHost;
        rig->config.remote.port = remotePort;
        rig->config.remote.clientId = name + "-remote";

        if (REMOTE_USER.length() > 0) {
            rig->config.remote.userName = REMOTE_USER.c_str();
            rig->config.remote.hasUserName = true;
        }
        if (REMOTE_PASSWORD.length() > 0) {
            const char* text = REMOTE_PASSWORD.c_str();
            rig->config.remote.password.assign(text, text + strlen(text));
            rig->config.remote.hasPassword = true;
        }

        const MqttResult began = rig->bridge.begin(*rig->local, *rig->remote,
                                                   rig->config);
        if (began != MqttResult::Ok) {
            ERROR = true;
            STATUS = mqPin(began);
            return;
        }

        // A MAPPING THAT WOULD LOOP IS REFUSED HERE, not carried. start() is
        // where the library checks it, and two rules that would carry this
        // bridge's own output back into it come back as an invalid argument
        // rather than as a message storm that takes a broker down.
        const MqttResult started = rig->bridge.start();
        if (started != MqttResult::Ok) {
            ERROR = true;
            STATUS = mqPin(started);
            return;
        }

        fbStarted = true;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
    }

    rig->bridge.poll();

    const MqttBridgeStatus& s = rig->bridge.status();
    switch (s.state) {
        case MqttBridgeState::Connecting:
            STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_CONNECTING; break;
        case MqttBridgeState::Up:
            STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_UP; break;
        case MqttBridgeState::Degraded:
            STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_DEGRADED; break;
        default:
            STATE = MQTT_BRIDGE_STATE::MQTT_BRIDGE_IDLE; break;
    }
    LOCAL_UP = s.localUp;
    REMOTE_UP = s.remoteUp;
    FORWARDED_OUT = (int32_t)s.forwardedOut;
    FORWARDED_IN = (int32_t)s.forwardedIn;
    REFUSED_OUT = (int32_t)s.refusedOut;
    REFUSED_IN = (int32_t)s.refusedIn;
#endif
}

END_FUNCTION_BLOCK