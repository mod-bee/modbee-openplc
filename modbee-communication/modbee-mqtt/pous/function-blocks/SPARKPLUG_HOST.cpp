(* A SPARKPLUG B HOST APPLICATION: the other end of SPARKPLUG_NODE.

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
     through globals. *)

FUNCTION_BLOCK SPARKPLUG_HOST
  VAR_INPUT
    (* PIN ORDER IS A DESIGN DECISION. The first input is read - by an engineer
       and by `check --lint` - as the one that makes the block do something, so
       the identity comes first and the options follow. *)
    HOST_ID : STRING(47);
    BROKER : STRING(128);
    PORT : UINT;
    (* NO DEFAULT ON AN ENUM PIN. The block-header parser refuses a qualified
       enum literal in an initial value - "unexpected character: ->#<-". The
       TYPE carries the default instead: MQTT_SECURITY is MQTT_PLAIN and
       MQTT_PROTOCOL is MQTT_V5_THEN_V311, so an unwired pin behaves as the
       prose says. *)
    SECURITY : MQTT_SECURITY;
    USER : STRING(64);
    PASSWORD : STRING(64);
    PROTOCOL : MQTT_PROTOCOL;
    (* For MQTT_TLS_PINNED and nothing else, and the same rule as
       MQTT_CLIENT. TRUE lets the FIRST key a broker shows be learned and kept
       (trust on first use). Once learned it is ENFORCED, whether TRUST_NEW
       stays on or not and across restarts, so wiring it TRUE is safe. To
       accept a broker REPLACED ON PURPOSE, switch it off and on again: the
       rising edge forgets the stored key and the next connection learns the
       new one. FALSE with nothing stored refuses to connect. *)
    TRUST_NEW : BOOL;
    (* The group to watch, or empty for every group. Narrowing matters on a
       real plant: a host subscribed to spBv1.0/# in a large estate receives
       every other line's traffic to discard. *)
    GROUP : STRING(47);
    (* Whether to act as the PRIMARY host.
       Nothing in the protocol marks a host as primary - the NODES are
       configured with its id - so this only decides whether a sequence gap
       produces a rebirth request. Two hosts both asking would double the
       traffic for one missed message. *)
    PRIMARY : BOOL := TRUE;
    (* How long to wait for a gap to fill before asking for a rebirth.
       A link that reorders occasionally should not trigger a full birth every
       time. T#0s disables the window and asks immediately. *)
    REORDER : TIME := T#5s;
    (* See SPARKPLUG_NODE for why these exist: MQTT_TLS_VERIFY with no CA_FILE
       trusts the system store, which no plant CA is in. *)
    CA_FILE : STRING(128);
    CERT_FILE : STRING(128);
    KEY_FILE : STRING(128);
    KEEP_ALIVE : UINT := 60;
    (* A TRANSPORT SOMETHING ELSE OWNS, for a board. On the Runtime this is
       left at 0 and the block opens its own socket. On a board there is no
       socket to open, so wire this to a WiFiClient-backed transport and
       BROKER/PORT/SECURITY are ignored. *)
    LINK : __XWORD;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    LINK_UP : BOOL;
    (* Our own STATE birth certificate is published and the plant may rely on
       us. An edge node waiting for this host starts birthing once it sees it. *)
    BORN : BOOL;
    (* How many edge nodes we have heard from, and how many are online now. A
       node that has died stays tracked - knowing it is gone is worth more than
       forgetting it existed. *)
    NODES : INT;
    ONLINE : INT;
    (* Sequence gaps seen and rebirths asked for, across every node. Both
       climbing together is a lossy link; gaps climbing alone means the window
       is absorbing them, which is what it is for. *)
    GAPS : DINT;
    REBIRTHS : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    LAST_ERROR : STRING(64);
    (* What the broker actually showed us, SHA-256 of its public key in
       hexadecimal. Read it at commissioning to record what was pinned. *)
    BROKER_KEY : STRING(64);
  END_VAR
  (* THE PIN, AND IT IS THE BLOCK'S OWN RETAINED VARIABLE - not a pin somebody
     has to wire, name or type. The same arrangement MQTT_CLIENT uses, for the
     same reason: MQTT_TLS_PINNED is the mode a PLANT broker is reached in, and
     it must need nothing from the file system.

     IEC 61131-3 6.5.6.2 allows RETAIN on a variable declared in a function
     block TYPE and says that declaration overrides whatever the instance says,
     so a user cannot accidentally un-retain it.

     ONE STRING, AND IT IS FROZEN. A retained variable inside a library block
     joins the project's retain layout, so the layout hash covers it - add,
     remove or retype one later and the WHOLE project's retained blob is
     refused, including the user's own setpoints. 64 characters because that is
     a SHA-256 in hexadecimal, and because a retained IEC STRING is a fixed 127
     bytes whatever width it was declared. *)
  VAR RETAIN
    fbPinnedKey : STRING(64);
  END_VAR
  VAR
    fbPinApplied : BOOL;
    (* TRUST_NEW last scan, and whether there has been a last scan - the
       rising edge forgets a stored key and must not fire at program start, or
       a TRUST_NEW wired TRUE would forget the pin on every reboot. *)
    fbLastTrust : BOOL;
    fbTrustSeen : BOOL;
  END_VAR
  VAR
    (* THE HANDLE THE OTHER HOST-SIDE BLOCKS READ, a local rather than an
       output pin - the same arrangement SPARKPLUG_NODE and MQTT_CLIENT use.
       A block reached through a VAR_IN_OUT can see the referenced block's
       locals, and IEC identifiers are case insensitive, so `HOST.FBAPI` in
       another block resolves to `fbApi` here. Keeping it off the pin list
       means it cannot be wired to anything on a rung by mistake.

       __XWORD, with two underscores: plain XWORD is not a type the
       block-header parser knows. *)
    fbApi : __XWORD;
    fbTransport : __XWORD;
    fbConnectAsked : BOOL;
    fbTransportTls : BOOL;
    fbClient : __XWORD;
    (* The task this block runs in, for the blocks given it: see MQTT_ARDUINO,
       "ONE TASK PER CLIENT". *)
    fbTask : __XWORD;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugHost.h>
#include <vector>

// --- Everything this block made, freed when the program is unloaded ---
//
// A host only leaves its client here: the connection is MQTT_CLIENT's, whose
// own cleanup runs after this one and closes the link WITHOUT a DISCONNECT -
// so the broker publishes this host's offline STATE, the Will it registered,
// the moment the PLC stops.
namespace {
std::vector<MqttSparkplugHost*> mqSpHostsOwned;

struct MqSpHostCleanup {
    ~MqSpHostCleanup() {
        for (size_t i = 0; i < mqSpHostsOwned.size(); i++) delete mqSpHostsOwned[i];
        mqSpHostsOwned.clear();
    }
};
MqSpHostCleanup mqSpHostsCleanupAtUnload;
}  // namespace

// --- What the host-side blocks reach through their HOST pin ---
//
// Null until the host has been built. A handle rather than a pointer on the
// pin because that is what an IEC XWORD is.
//
// SPARKPLUG_SUBSCRIBE and SPARKPLUG_WRITE sort after this file, and every C++
// POU in a project lands in one translation unit in filename order, so they
// see this definition.
MqttSparkplugHost* mq_spHostOf(strucpp::XWORD_t handle) {
    return (MqttSparkplugHost*)(uintptr_t)handle;
}

// Defined by SPARKPLUG_NODE, which sorts AFTER this file - a declaration
// before use is all C++ needs, the definition may come later in the same
// translation unit.
bool mq_spWriteAny(const strucpp::IEC_ANY& any, const MqttSparkplugValue& value);
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out);

// Defined by MQTT_CLIENT and MQTT_ARDUINO, which sort before every SPARKPLUG_*
// file.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);

void setup()
{
    LINK_UP = false;
    BORN = false;
    NODES = 0;
    ONLINE = 0;
    GAPS = 0;
    REBIRTHS = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    LAST_ERROR = "";
    fbApi = (strucpp::XWORD_t)0;
    fbClient = (strucpp::XWORD_t)0;
    fbConnectAsked = false;
}

void loop()
{
    fbTask = mq_currentTask();   // every block on this one shares it: see MQTT_ARDUINO

    // --- THE CONNECTION IS MQTT_CLIENT'S --- as for SPARKPLUG_NODE: this host
    // is a layer on that session and takes the Will (its offline STATE) and
    // Clean Start on every CONNECT.
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        LINK_UP = false;
        BORN = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        LAST_ERROR = "put SPARKPLUG_HOST in its MQTT_CLIENT's task";
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (client == nullptr) {
        LINK_UP = false;
        BORN = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
        LAST_ERROR = "waiting for its MQTT_CLIENT";
        return;
    }

    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)fbApi);
    if (!(bool)ENABLE) {
        // The offline STATE goes by hand and the connection stays up for
        // everything else on it.
        if (host) {
            host->disconnect();
            host->poll();
        }
        LINK_UP = client->isConnected();
        BORN = false;
        fbConnectAsked = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        LAST_ERROR = "";
        return;
    }

    // --- Build once ---
    //
    // On the first enabled scan, for the life of the program. A host that
    // rebuilt itself would drop every node's dictionary and read nothing until
    // each one birthed again.
    if (host == nullptr) {
        if (HOST_ID.length() == 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "a host application needs a HOST_ID";
            return;
        }
        // Kilobytes - and on the Runtime tens of them (every tracked node's
        // metric table) - so it is asked for, not assumed: a plain new that
        // fails is a hard fault on a board with no exceptions.
        host = new (std::nothrow) MqttSparkplugHost(*client);
        if (host == nullptr) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            LAST_ERROR = "out of memory";
            return;
        }
        if (!host->hostId(HOST_ID.c_str())) {
            delete host;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_TOPIC;
            LAST_ERROR = "HOST_ID is empty or contains + / or #";
            return;
        }
        // GROUP empty watches every group.
        if (!host->watch(GROUP.length() != 0 ? GROUP.c_str() : nullptr)) {
            delete host;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_TOPIC;
            LAST_ERROR = "GROUP contains + / or #";
            return;
        }
        host->actAsPrimary((bool)PRIMARY);
        host->reorderTimeout((mq_time_t)mq_millisOf(REORDER));
        mqSpHostsOwned.push_back(host);
        fbApi = (strucpp::XWORD_t)(uintptr_t)host;
        fbClient = (strucpp::XWORD_t)(uintptr_t)client;
    }
    if ((strucpp::XWORD_t)(uintptr_t)client != (strucpp::XWORD_t)fbClient) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        LAST_ERROR = "CLIENT changed while running - restart the PLC";
        return;
    }

    // Refused only when another layer owns the client's Will, and asked again
    // every scan, so removing that one is enough.
    if (!fbConnectAsked) fbConnectAsked = host->connect();
    host->poll();

    LINK_UP = client->isConnected();
    BORN = host->isBorn();
    NODES = (int16_t)host->nodeCount();
    int16_t online = 0;
    int32_t gaps = 0;
    int32_t rebirths = 0;
    for (size_t index = 0; index < host->nodeCount(); index++) {
        const MqttSparkplugTrackedNode* node = host->nodeAt(index);
        if (node == nullptr) continue;
        if (node->online) online++;
        gaps += (int32_t)node->gaps;
        rebirths += (int32_t)node->rebirthsRequested;
    }
    ONLINE = online;
    GAPS = gaps;
    REBIRTHS = rebirths;

    if (!fbConnectAsked) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_REFUSED;
        LAST_ERROR = "another layer owns the client's Will";
        return;
    }
    const MqttSparkplugError payloadError = host->lastPayloadError();
    if (payloadError != MqttSparkplugError::None) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        LAST_ERROR = mq_sparkplugErrorName(payloadError);
        return;
    }
    if (host->outOfMemory()) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
        LAST_ERROR = "out of memory for tracked nodes or metrics";
        return;
    }
    ERROR = false;
    STATUS = LINK_UP ? MQTT_RESULT::MQTT_OK : MQTT_RESULT::MQTT_NOT_CONNECTED;
    LAST_ERROR = LINK_UP ? "" : "MQTT_CLIENT is not connected";
}

END_FUNCTION_BLOCK