(* A SPARKPLUG B EDGE NODE. One block, and the other SPARKPLUG_* blocks hang
off it.

GROUP        the Sparkplug Group ID. A logical grouping of nodes - a pipeline
             segment, a manufacturing cell. Descriptive but small: it is in
             every topic. Up to 47 characters, as every Sparkplug id here.
NODE         this node's ID. GROUP and NODE together are the node's address in
             the whole system and MUST be unique in it.
PRIMARY_HOST the Sparkplug Host ID this node answers to, or empty for none.
             EMPTY BY DEFAULT - see below.
ENABLE       FALSE keeps the node down without losing its metric declarations.
CLIENT       the MQTT_CLIENT whose connection this node rides on. Must be
             wired. Everything about the connection is set there - broker,
             TLS, login, keep-alive, protocol - and with it the device's own
             topics and its firmware updates share the one session.

LINK_UP      the client's MQTT session is up.
BORN         the birth certificate has gone. NOT the same as LINK_UP: a node
             waiting for its primary host is connected and not born, and until
             it is born nothing else publishes.
SEQ          the current sequence number, 0-255.
BDSEQ        the birth/death sequence number for this connection.
POINTS       how many metrics are declared. There is no limit but memory,
             metrics and devices alike, on a board and the Runtime: the tables
             grow with what is declared and, on a board, live in PSRAM where
             there is some. Past what memory holds, the declaration is refused
             on the declaring block's ERROR and LAST_ERROR here says "out of
             memory for metrics or devices".
CLOCK_SET    the timestamps are real time. Always on the Runtime; on a board
             once MQTT_CLOCK (NTP, or the mobile network's time) has set the
             clock. Until then they count from boot - a date in January 1970 -
             which a host should take as "not synced" and replace with the time
             it received the message.
STATUS       MQTT_OK when fine. MQTT_WRONG_TASK: this block is not in its
             MQTT_CLIENT's task, and does nothing until it is.
LAST_ERROR   with LINK_UP and not BORN, what the node is waiting for, which
             says where to look (why the link is down is on MQTT_CLIENT):
               "no STATE from primary host 'scada'"     the host has never
                                                         reached this broker
               "offline STATE from primary host 'scada'" the host is down
               "broker refused STATE/scada subscription (not authorized)"
               "birth could not be queued - retrying"
               "out of memory for metrics or devices"
               "another layer owns the client's Will"   a SPARKPLUG_HOST or a
                                                         second node on CLIENT
             Empty once born.
(The handle the other SPARKPLUG_* blocks take is a local, not a pin - see the
declaration. Nothing on a rung needs it.)

---

WHY SPARKPLUG AND NOT MQTT_CLIENT. Two things, and they are the reasons a SCADA
system wants it.

A TOPIC IS A ONE-WAY PIPE, so a writable setpoint under plain MQTT needs two of
them - one to write and one to read back. That is where the _FB suffix in the
pump-station project came from. Under Sparkplug the direction is in the MESSAGE
TYPE rather than the topic: the host writes SETPOINT with a command, the node
publishes SETPOINT with its data, one name, one struct member. No readback pair.

AND THE DATATYPE IS DECLARED. Every metric's type travels in the birth
certificate, so the far end is told REAL rather than inferring it from the first
sample it happens to see. A counter that started at zero will not be filed as an
integer and then refuse a decimal.

WHAT IT COSTS. The metric set is CLOSED. The birth certificate must carry every
metric the node will ever publish, so everything is declared before the node
births and a write to an undeclared name is refused rather than invented. In
practice that means SPARKPLUG_STRUCT blocks are wired on the first scan and the
node births on the second, which is what ENABLE and BORN are for.

PRIMARY_HOST IS EMPTY BY DEFAULT, deliberately. Set it and this node will not
publish ANYTHING until that host announces itself online - which is correct for
a system with one nominated master, and is what stops a node shouting into a
broker nobody is reading. Leave it empty and the node births as soon as it
connects. A node waiting for a host that does not exist looks exactly like a
node that is broken, so the default is the one that cannot be mistaken.

ONE CONNECTION, SHARED. Sparkplug runs over MQTT, and so does everything
else a device says: this node is a layer on the MQTT_CLIENT's session, not a
second connection. What Sparkplug needs of that session it takes on every
CONNECT: the Will is this node's NDEATH, so no MQTT_PRESENCE on the same client
(the birth and death certificates are the presence); the session is always
clean, whatever MQTT_CONFIG says; and the transmit buffer grows to hold the
birth certificate. Started on a session already up, the node reconnects it
once so the next CONNECT carries the NDEATH - every other block on the client
sees one reconnect. The same when the primary host goes offline: Sparkplug
requires a new session, so the client reconnects.

ONE MESSAGE A SCAN. The other blocks do not send their values: a
SPARKPLUG_STRUCT or SPARKPLUG_METRIC with something to say marks it and asks,
and this block, on its next scan, sends ONE NDATA - and one DDATA for each
online device with something to say - carrying everything on the node that
moved, however many blocks asked. Births, deaths and SPARKPLUG_HISTORY's
records still go when they happen.

ONE TASK. This block and every block on CLIENT run in the client's task - the
network task - and the machine's program trades values with them through
globals. In another task it says MQTT_WRONG_TASK and does nothing.

GROUP, NODE AND PRIMARY_HOST MAY CHANGE WHILE IT RUNS. A change leaves under
the old identity (the host sees the NDEATH) and births under the new one with
the next bdSeq; declarations and devices stay, so nothing else in the program
notices. ENABLE FALSE sends the NDEATH and leaves the connection to everything
else on it.

ONE NODE PER CLIENT: a connection carries one Will, so a second node needs a
second MQTT_CLIENT. Nothing here is process-wide. *)

FUNCTION_BLOCK SPARKPLUG_NODE
  VAR_INPUT
    (* NO DEFAULT ON AN ENUM PIN, and that is the parser's rule rather than a
       preference: the block-header parser refuses a qualified enum literal in
       an initial value - "unexpected character: ->#<-". No MQTT_* block gives
       an enum pin a default either, for the same reason.

       Nothing is lost by it. Each enum TYPE carries its own default -
       MQTT_SECURITY is MQTT_PLAIN, MQTT_TRIGGER is MQTT_ON_CHANGE,
       MQTT_PROTOCOL is MQTT_V5_THEN_V311 - so an unwired pin behaves exactly
       as the prose above says. *)
    GROUP : STRING(47);
    NODE : STRING(47);
    BROKER : STRING(128);
    PORT : UINT;
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
    PRIMARY_HOST : STRING(47);
    (* THE CERTIFICATES, and without them SECURITY has almost no use on a
       plant.
       MQTT_TLS_VERIFY with no CA_FILE trusts the system certificate store,
       which is right for a public broker and wrong for every plant broker,
       because a plant broker is signed by the plant's own CA and nothing in
       /etc/ssl has heard of it. Leaving these off meant TLS could only be used
       insecurely here, which is not really using it.
       CERT_FILE and KEY_FILE are the node's own certificate, for a broker that
       authenticates clients by certificate rather than by password. Both or
       neither.
       All three are paths, so they are the Runtime's. A board takes the same
       things from defines in its board package - MQTT_CA_CERT_PEM,
       MQTT_CLIENT_CERT_PEM and MQTT_CLIENT_KEY_PEM - as MQTT_CLIENT does. *)
    CA_FILE : STRING(128);
    CERT_FILE : STRING(128);
    KEY_FILE : STRING(128);
    KEEP_ALIVE : UINT := 60;
    (* A TRANSPORT ANOTHER BLOCK MADE, for TRANSPORT := MQTT_LINK_EXTERNAL.
       Wired, it wins whatever TRANSPORT says, and BROKER/PORT/SECURITY are
       not used to open it. Leave it at 0 otherwise: the Runtime's socket and a
       board's Wi-Fi, Ethernet and modem are TRANSPORT's. *)
    LINK : __XWORD;
    ENABLE : BOOL := TRUE;
    TRANSPORT : MQTT_LINK;
  END_VAR
  VAR_OUTPUT
    LINK_UP : BOOL;
    BORN : BOOL;
    SEQ : USINT;
    BDSEQ : USINT;
    POINTS : INT;
    SERVER : INT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    LAST_ERROR : STRING(64);
    (* What the broker actually showed us, SHA-256 of its public key in
       hexadecimal. Read it at commissioning to record what was pinned. *)
    BROKER_KEY : STRING(64);
    CLOCK_SET : BOOL;
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
    (* THE HANDLE THE OTHER SPARKPLUG_* BLOCKS READ, and it is a LOCAL rather
       than an output pin - which is how MQTT_CLIENT does it too.

       A block reached through a VAR_IN_OUT can see the referenced block's
       locals, and IEC identifiers are case insensitive, so `NODE.FBAPI` in
       another block resolves to `fbApi` here. Keeping it off the pin list
       means it cannot be wired to anything on a rung by mistake.

       __XWORD, with two underscores: that is the runtime's pointer-width
       integer. Plain XWORD is not a type the block-header parser knows -
       "Undefined type 'XWORD'". *)
    fbApi : __XWORD;
    fbTransport : __XWORD;
    fbBegun : BOOL;
    fbConnectAsked : BOOL;
    fbDeclaredAt : DINT;
    fbWanted : BOOL;
    fbTransportTls : BOOL;
    fbBoardLink : __XWORD;
    (* The settings the node was built from, as two fingerprints - the
       medium (TRANSPORT, SECURITY, BROKER, PORT, LINK, the TLS files) and the
       CONNECT (GROUP, NODE, the login, PROTOCOL, KEEP_ALIVE, PRIMARY_HOST). A
       change of either reconnects, the first on a rebuilt medium. *)
    fbMediumKey : UDINT;
    fbSessionKey : UDINT;
    fbRelink : BOOL;
    fbReconfigure : BOOL;
    fbChangeAt : DINT;
    fbClient : __XWORD;
    (* The task this block runs in, for the blocks given it: see MQTT_ARDUINO,
       "ONE TASK PER CLIENT". *)
    fbTask : __XWORD;
  END_VAR
  VAR_IN_OUT
    (* THE CONNECTION THIS NODE RIDES ON. Sparkplug runs over MQTT, and so
       does everything else a device says: one radio, one login, one session.
       The node is a layer on the client, not a second connection. *)
    CLIENT : MQTT_CLIENT;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <vector>

// --- Everything this block made, freed when the program is unloaded ---
//
// The Runtime swaps a new program into the SAME process on every stop and
// re-download. A node only leaves its client here: the connection is
// MQTT_CLIENT's, whose own cleanup runs after this one (it was constructed
// first, in the one translation unit) and closes the link WITHOUT a
// DISCONNECT - so the broker publishes this node's NDEATH, the Will it
// registered, the moment the PLC stops.
namespace {
std::vector<MqttSparkplugNode*> mqSpNodesOwned;

struct MqSpNodeCleanup {
    ~MqSpNodeCleanup() {
        for (size_t i = 0; i < mqSpNodesOwned.size(); i++) delete mqSpNodesOwned[i];
        mqSpNodesOwned.clear();
    }
};
MqSpNodeCleanup mqSpNodesCleanupAtUnload;
}  // namespace
// Declared here because every C++ POU in a project lands in ONE translation
// unit, in filename order - and SPARKPLUG_NODE sorts after MQTT_CLIENT, which
// is where these are defined.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
uint32_t mq_fingerprint(uint32_t hash, const void* data, size_t length);
uint32_t mq_fingerprintText(uint32_t hash, const char* text);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);
bool mq_tolerated(MqttResult result);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
size_t mq_formatAny(const strucpp::IEC_ANY& any, char* out, size_t capacity);
bool mq_numberOf(const strucpp::IEC_ANY& any, double* out);
bool mq_memberAsAny(const strucpp::MemberDesc& member, uint8_t* base,
                    strucpp::IEC_ANY* out);
bool mq_memberIsPublishable(const strucpp::MemberDesc& member);

// --- What the other SPARKPLUG_* blocks reach through their NODE pin ---
//
// Null until the node has been built, which is what LINK_UP says. A handle
// rather than a pointer on the pin because that is what an IEC XWORD is.
MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle) {
    return (MqttSparkplugNode*)(uintptr_t)handle;
}

// --- IEC type to Sparkplug datatype ---
//
// THE DECLARED TYPE IS THE ANSWER, which is the whole point: an IEC declaration
// already says REAL or DINT, so nothing has to be inferred from a value. This
// is the mapping in MqttSparkplugValue.h, applied to strucpp's type classes.
//
// All seventeen IEC types the MQTT blocks can publish have a Sparkplug
// datatype, so a STRUCT that MQTT_STRUCT_PUBLISH would accept is one
// SPARKPLUG_STRUCT accepts too.
//
// AND TIME, which Sparkplug alone carries: an Int64 of MILLISECONDS. Sparkplug
// has no duration type, and a setpoint struct is full of TIMEs - a run time, a
// delay, a stagger - so refusing them left half a settings struct unwritable
// from SCADA while the panel next to it could write all of it. Milliseconds
// because that is what CODESYS and every SCADA tag editor mean by a TIME, and
// Int64 because the IEC range does not fit in 32 bits of them. (The text
// payloads of MQTT_STRUCT_PUBLISH still refuse a TIME: there is no one way to
// write it as text that every subscriber would read the same.)
bool mq_spTypeOfClass(int typeClass, MqttSparkplugDataType* out) {
    switch (typeClass) {
    case strucpp::TYPE_BOOL:  *out = MqttSparkplugDataType::Boolean; return true;
    case strucpp::TYPE_SINT:  *out = MqttSparkplugDataType::Int8;    return true;
    case strucpp::TYPE_INT:   *out = MqttSparkplugDataType::Int16;   return true;
    case strucpp::TYPE_DINT:  *out = MqttSparkplugDataType::Int32;   return true;
    case strucpp::TYPE_LINT:  *out = MqttSparkplugDataType::Int64;   return true;
    case strucpp::TYPE_USINT: *out = MqttSparkplugDataType::UInt8;   return true;
    case strucpp::TYPE_BYTE:  *out = MqttSparkplugDataType::UInt8;   return true;
    case strucpp::TYPE_UINT:  *out = MqttSparkplugDataType::UInt16;  return true;
    case strucpp::TYPE_WORD:  *out = MqttSparkplugDataType::UInt16;  return true;
    case strucpp::TYPE_UDINT: *out = MqttSparkplugDataType::UInt32;  return true;
    case strucpp::TYPE_DWORD: *out = MqttSparkplugDataType::UInt32;  return true;
    case strucpp::TYPE_ULINT: *out = MqttSparkplugDataType::UInt64;  return true;
    case strucpp::TYPE_LWORD: *out = MqttSparkplugDataType::UInt64;  return true;
    case strucpp::TYPE_REAL:  *out = MqttSparkplugDataType::Float;   return true;
    case strucpp::TYPE_LREAL: *out = MqttSparkplugDataType::Double;  return true;
    case strucpp::TYPE_STRING: *out = MqttSparkplugDataType::String; return true;
    case strucpp::TYPE_TIME:  *out = MqttSparkplugDataType::Int64;   return true;
    default:
        return false;
    }
}

// TIME is signed nanoseconds in strucpp. On the wire it is milliseconds,
// truncated: T#1500us goes as 1, and a value read back is the same TIME to the
// millisecond, which is the resolution every PLC timer here has anyway.
static const int64_t MQ_SP_NS_PER_MS = 1000000LL;

// Reads one IEC value as a Sparkplug value of its declared type.
//
// The declared type decides, not the value: a DINT holding 1 is an Int32 of 1
// and not a UInt8, because the birth certificate said Int32 and the far end is
// entitled to rely on that.
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out) {
    if (!out || !any.PVALUE) return false;
    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:
        *out = mq_spBool(*(const bool*)any.PVALUE);
        return true;
    case strucpp::TYPE_SINT:
        *out = mq_spInt8(*(const int8_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_INT:
        *out = mq_spInt16(*(const int16_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_DINT:
        *out = mq_spInt32(*(const int32_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_LINT:
        *out = mq_spInt64(*(const int64_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:
        *out = mq_spUInt8(*(const uint8_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:
        *out = mq_spUInt16(*(const uint16_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD:
        *out = mq_spUInt32(*(const uint32_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD:
        *out = mq_spUInt64(*(const uint64_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_REAL:
        *out = mq_spFloat(*(const float*)any.PVALUE);
        return true;
    case strucpp::TYPE_LREAL:
        *out = mq_spDouble(*(const double*)any.PVALUE);
        return true;
    case strucpp::TYPE_STRING:
        // Points at the runtime's own buffer, which outlives the publish -
        // MqttSparkplugValue deliberately does not copy text.
        *out = mq_spString((const char*)any.PVALUE);
        return true;
    case strucpp::TYPE_TIME:
        *out = mq_spInt64(*(const int64_t*)any.PVALUE / MQ_SP_NS_PER_MS);
        return true;
    default:
        return false;
    }
}

// Writes a Sparkplug value back into one IEC value. What a command does.
//
// Refuses on a type mismatch rather than coercing: a host writing a float into
// a BOOL has made a mistake, and rounding it would hide that.
bool mq_spWriteAny(const strucpp::IEC_ANY& any,
                   const MqttSparkplugValue& value) {
    if (!any.PVALUE) return false;
    if (value.isNull) return false;

    MqttSparkplugDataType declared = MqttSparkplugDataType::Unknown;
    if (!mq_spTypeOfClass(any.TYPECLASS, &declared)) return false;
    if (declared != value.type) return false;

    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:
        *(bool*)any.PVALUE = value.as.boolean;
        return true;
    case strucpp::TYPE_SINT:
        *(int8_t*)any.PVALUE = (int8_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_INT:
        *(int16_t*)any.PVALUE = (int16_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_DINT:
        *(int32_t*)any.PVALUE = (int32_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_LINT:
        *(int64_t*)any.PVALUE = value.as.signedValue;
        return true;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:
        *(uint8_t*)any.PVALUE = (uint8_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:
        *(uint16_t*)any.PVALUE = (uint16_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD:
        *(uint32_t*)any.PVALUE = (uint32_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD:
        *(uint64_t*)any.PVALUE = value.as.unsignedValue;
        return true;
    case strucpp::TYPE_REAL:
        *(float*)any.PVALUE = value.as.float32;
        return true;
    case strucpp::TYPE_LREAL:
        *(double*)any.PVALUE = value.as.float64;
        return true;
    case strucpp::TYPE_STRING: {
        // Bounded by the DECLARED capacity, which is what any.DISIZE carries.
        // A longer value is refused rather than truncated: a truncated
        // setpoint name or recipe id is worse than none.
        if (value.as.bytes.data == nullptr) return false;
        const int32_t capacity = any.DISIZE;
        if (capacity <= 0) return false;
        if ((int32_t)value.as.bytes.length >= capacity) return false;
        char* target = (char*)any.PVALUE;
        memcpy(target, value.as.bytes.data, value.as.bytes.length);
        target[value.as.bytes.length] = '\0';
        return true;
    }
    case strucpp::TYPE_TIME: {
        // Milliseconds. A negative duration is refused (TIME is unsigned in
        // CODESYS, and no setting here means anything by one), and so is one
        // past what nanoseconds can hold - about 292 years - rather than
        // wrapped into a small number that looks plausible.
        const int64_t ms = value.as.signedValue;
        if (ms < 0 || ms > INT64_MAX / MQ_SP_NS_PER_MS) return false;
        *(int64_t*)any.PVALUE = ms * MQ_SP_NS_PER_MS;
        return true;
    }
    default:
        return false;
    }
}

void setup()
{
    LINK_UP = false;
    BORN = false;
    SEQ = 0;
    BDSEQ = 0;
    POINTS = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    LAST_ERROR = "";
    CLOCK_SET = false;
    fbApi = (strucpp::XWORD_t)0;
    fbClient = (strucpp::XWORD_t)0;
    fbConnectAsked = false;
    fbDeclaredAt = 0;
    fbSessionKey = 0;
}

void loop()
{
    fbTask = mq_currentTask();   // every block on this one shares it: see MQTT_ARDUINO

    // --- THE CONNECTION IS MQTT_CLIENT'S ---
    //
    // Where, how, as whom and whether to be connected at all: its pins, its
    // MQTT_CONFIG, MQTT_TLS and MQTT_ARDUINO. This node rides on that session,
    // with the device's own topics and its firmware updates beside it, and
    // takes what Sparkplug needs of it on every CONNECT: the Will (its NDEATH),
    // Clean Start, and a transmit buffer that holds the birth certificate.
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        LINK_UP = false;
        BORN = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        LAST_ERROR = "put SPARKPLUG_NODE in its MQTT_CLIENT's task";
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (client == nullptr) {
        // Not built yet - its first scan has not run, or it is out of memory,
        // which it says itself.
        LINK_UP = false;
        BORN = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
        LAST_ERROR = "waiting for its MQTT_CLIENT";
        return;
    }

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)fbApi);
    if (!(bool)ENABLE) {
        // The NDEATH goes by hand and the connection stays up for everything
        // else on it; declarations stay for the next ENABLE.
        if (node) {
            node->disconnect();
            node->poll();
        }
        LINK_UP = client->isConnected();
        BORN = false;
        fbConnectAsked = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        LAST_ERROR = "";
        return;
    }

    // GROUP, NODE and PRIMARY_HOST: who this node is. Read every scan.
    auto identityKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        h = mq_fingerprintText(h, GROUP.c_str());
        h = mq_fingerprintText(h, NODE.c_str());
        h = mq_fingerprintText(h, PRIMARY_HOST.c_str());
        return h;
    };
    auto applyIdentity = [&](MqttSparkplugNode* n) -> bool {
        if (GROUP.length() == 0 || NODE.length() == 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            LAST_ERROR = "a Sparkplug node needs a GROUP and a NODE";
            return false;
        }
        if (!n->group(GROUP.c_str()) || !n->node(NODE.c_str())) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_TOPIC;
            LAST_ERROR = "GROUP or NODE contains + / or #";
            return false;
        }
        n->primaryHost(PRIMARY_HOST.c_str());   // empty: none
        return true;
    };

    // --- Build once ---
    //
    // On the first enabled scan, for the life of the program. A PLC does not
    // restart its blocks, and a node that rebuilt itself would lose its metric
    // declarations - which cannot be re-made, because the birth certificate
    // has already described them.
    if (node == nullptr) {
        node = new (std::nothrow) MqttSparkplugNode(*client);
        if (node == nullptr) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            LAST_ERROR = "out of memory";
            return;
        }
        if (!applyIdentity(node)) {
            delete node;
            return;
        }
        // Up to four host writes per writable metric are kept between scans,
        // so a setpoint written twice in one scan loses neither.
        node->queueWrites(4);
        mqSpNodesOwned.push_back(node);
        fbApi = (strucpp::XWORD_t)(uintptr_t)node;
        fbClient = (strucpp::XWORD_t)(uintptr_t)client;
        fbSessionKey = identityKey();
        // The other SPARKPLUG_* blocks declare on this scan, wherever they
        // sit in the program; the node connects on a later one.
        fbDeclaredAt = (int32_t)mq_millis();
        LINK_UP = client->isConnected();
        return;
    }
    if ((strucpp::XWORD_t)(uintptr_t)client != (strucpp::XWORD_t)fbClient) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        LAST_ERROR = "CLIENT changed while running - restart the PLC";
        return;
    }

    // --- A NEW IDENTITY IS A NEW NODE TO THE HOST ---
    //
    // It leaves under the old one (the host sees that NDEATH) and births under
    // the new one with the next bdSeq. Declarations and devices stay, so
    // nothing else in the program notices.
    const uint32_t identity = identityKey();
    if (identity != (uint32_t)fbSessionKey) {
        fbSessionKey = identity;
        node->disconnect();
        if (!applyIdentity(node)) {
            LINK_UP = client->isConnected();
            BORN = false;
            return;
        }
        fbConnectAsked = false;
        fbDeclaredAt = (int32_t)mq_millis();
    }

    if (!fbConnectAsked) {
        // A node with nothing declared would birth an empty certificate and
        // have to rebirth for the first metric: give the declaring blocks a
        // moment, then birth whatever there is.
        if (node->pointCount() == 0 &&
            (int32_t)mq_elapsed((mq_time_t)(uint32_t)fbDeclaredAt, mq_millis()) < 2000) {
            node->poll();
            LINK_UP = client->isConnected();
            return;
        }
        // Refused only when another layer owns the client's Will - a
        // SPARKPLUG_HOST, or a second node on the same client - and then it is
        // asked again every scan, so removing that one is enough.
        fbConnectAsked = node->connect();
    }
    node->poll();

    LINK_UP = client->isConnected();
    BORN = node->isBorn();
    SEQ = (uint8_t)node->sequence();
    BDSEQ = (uint8_t)node->birthDeathSequence();
    POINTS = (int16_t)node->pointCount();
    CLOCK_SET = node->clockIsSet();

    if (!fbConnectAsked) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_REFUSED;
        LAST_ERROR = node->waitingFor();
        return;
    }
    if (node->outOfMemory()) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
        LAST_ERROR = "out of memory for metrics or devices";
        return;
    }
    const MqttSparkplugError payloadError = node->lastPayloadError();
    if (payloadError != MqttSparkplugError::None) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        LAST_ERROR = mq_sparkplugErrorName(payloadError);
        return;
    }
    if (!LINK_UP) {
        // Why the link is down is MQTT_CLIENT's to say, on its own pins.
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        LAST_ERROR = "MQTT_CLIENT is not connected";
        return;
    }
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    LAST_ERROR = node->waitingFor();
}

END_FUNCTION_BLOCK