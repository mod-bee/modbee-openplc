(* A SPARKPLUG B HOST APPLICATION: the other end of FB_SparkplugNode.

sHostId      this host's Sparkplug Host ID. It is a topic element and MUST be
             unique in the system. An edge node's sPrimaryHostId carries this
             same string. Up to 47 characters.
sGroupId     the group to watch, or empty for every group.
bPrimary     whether to ask for a rebirth when a node's sequence skips.
tReorder     how long to let a gap fill before asking. T#0s asks at once.
bEnable      FALSE publishes the offline STATE and stands the host down; the
             connection stays up for everything else on it.
fbClient     the FB_MqttClient whose connection this host rides on. Must be
             wired; broker, TLS, login and protocol are set there.

bLinkUp      the client's MQTT session is up.
bBorn        our STATE birth certificate is published, so nodes may rely on us.
nNodes       edge nodes heard from.
nOnline      how many of them are online now.
nGaps        sequence gaps seen across every node.
nRebirths    rebirths asked for.
bError       something is wrong; eErrorId and sLastError say what. "out of
             memory for tracked nodes or metrics" when the host could not
             follow everything that arrived: it tracks as many nodes, and
             metrics per node, as memory holds, on a board and the Runtime
             alike. E_MqttResult.WrongTask: not in its FB_MqttClient's task.

     A host watches a group and keeps the current picture of every edge node in
     it - which nodes are online, what metrics they declared, what each one is
     reading now. Watch reads a value out of that picture and Write sends one
     back down.

     WHAT A HOST DOES THAT A NODE DOES NOT, and it is the reason this is a
     separate block rather than a mode of FB_SparkplugNode:

       - It publishes its OWN birth and death certificate on
         spBv1.0/STATE/<sHostId>, at QoS 1 and RETAINED. Retained, unlike a
         node's death certificate, because an edge node subscribing later has
         to find it waiting or it will never birth at all.
       - It reads names out of BIRTH certificates and resolves them against the
         aliases that data messages carry. A conformant node puts names only in
         its births; without the dictionary a host receives numbers it cannot
         name.
       - It notices gaps in a node's sequence number and, if bPrimary is set,
         asks for a rebirth.

     sPrimaryHostId on the node and sHostId here are the same string. A node
     configured with one will not birth until this host says it is online,
     which is how a plant avoids nodes publishing into a SCADA that is not
     listening.

     ONE CONNECTION, SHARED. The host is a layer on its FB_MqttClient's session
     and takes its Will - the offline STATE - and a clean session on every
     CONNECT, so no presence (stWillConfig) and no FB_SparkplugNode on the same
     client: a connection carries one Will. Started on a session already up,
     it reconnects it once so the next CONNECT carries the STATE.

     ONE TASK. This block and its methods run in the client's task, and the
     rest of the program trades values with them through globals. A method
     called from another task returns E_MqttResult.WrongTask.

METHODS

  host.Watch(sMetricName, anyValue, sEdgeNodeId, sNodeGroupId, sDeviceId,
             bValid =>, bTypeOk =>, bFresh =>, nAge =>, nReadCnt =>)

     READS ONE METRIC into an IEC variable of the engineer's own type. Standing:
     call it every scan while the value is wanted; stop calling it and anyValue
     holds its last value.

     THE NAME IS THE ADDRESS, not a topic and not an alias. The edge node
     declared "level" in its birth certificate and Watch asks for "level". A
     conformant node sends data by alias only and the host resolves it back.

     THE DECLARED TYPE IS CHECKED, not coerced. If the birth said "level" is a
     REAL and anyValue is a DINT, the read is refused (E_MqttResult.
     InvalidArgument, bTypeOk FALSE) rather than silently truncating a reading
     a control decision is about to be made on.

     sMetricName   the metric name, exactly as the edge node declared it.
     anyValue      where to put it. Any IEC type; it must match what was
                   declared. Also the call's key: its declared name and type.
     sEdgeNodeId   which edge node. Empty means the first node the host heard
                   from, which is convenient with one node and wrong with two.
     sNodeGroupId  which group. Empty means any group the host watches.
     sDeviceId     for a metric belonging to a device rather than the node.

     bValid        the value was read and written into anyValue by this call.
     bTypeOk       FALSE means anyValue's type does not match the birth.
     bFresh        the reading changed since the last call.
     nAge          milliseconds since the node's own timestamp on it. Not since
                   we received it - on a slow link those differ by more than a
                   control decision should ignore.
     nReadCnt      reads written into anyValue.

     Returns E_MqttResult.Ok when anyValue holds a valid reading;
     NotInitialised while the host is not built, the node has not been heard
     or the metric has not been published (a plant starting up spends its
     first seconds here); NotConnected while the client is down;
     InvalidArgument for an empty sMetricName or a type mismatch; WrongTask.

  host.Write(sMetricName, anyValue, sEdgeNodeId, sNodeGroupId, sDeviceId,
             bExecute, nSentCnt =>)

     WRITES ONE METRIC on an edge node: an NCMD, or a DCMD for a device metric.
     The edge node applies it to whatever it recorded under that name and
     reports the new value back under the SAME metric name - one name is read
     and written, so Watch the same sMetricName to see it come back.

     THE NODE DECIDES. A command for a metric the node never declared, or
     declared read-only, or declared with a different type, is refused there
     and counted: Write reports that it sent one, not that it took effect.

     A request. The rising edge of bExecute starts it and latches every input,
     anyValue included. Not connected: E_MqttResult.NotConnected at once. A
     node not heard from yet: E_MqttResult.Queued while bExecute stays TRUE,
     sent as soon as it appears; bExecute falling first drops the command
     (E_MqttResult.Cancelled) - a command that arrives a minute after the
     operator let go is worse than one that never arrived. Then Ok (sent),
     Refused (the client would not take it) or InvalidArgument (empty
     sMetricName, or an IEC type with no Sparkplug datatype), held until the
     next rising edge. The call's key is anyValue's declared name and type with
     sMetricName.

     nSentCnt      commands this call has sent. *)

FUNCTION_BLOCK FB_SparkplugHost
  VAR_INPUT
    sHostId         : STRING(47);           (* this host's Sparkplug Host ID *)
    (* The group to watch, or empty for every group. Narrowing matters on a
       real plant: a host subscribed to spBv1.0/# in a large estate receives
       every other line's traffic to discard. *)
    sGroupId        : STRING(47);
    (* Whether to act as the PRIMARY host.
       Nothing in the protocol marks a host as primary - the NODES are
       configured with its id - so this only decides whether a sequence gap
       produces a rebirth request. Two hosts both asking would double the
       traffic for one missed message. *)
    bPrimary        : BOOL := TRUE;
    (* How long to wait for a gap to fill before asking for a rebirth.
       A link that reorders occasionally should not trigger a full birth every
       time. T#0s disables the window and asks immediately. *)
    tReorder        : TIME := T#5s;
    bEnable         : BOOL := TRUE;         (* FALSE publishes the offline STATE *)
  END_VAR
  VAR_IN_OUT
    fbClient        : FB_MqttClient;        (* the connection this host rides on *)
  END_VAR
  VAR_OUTPUT
    bLinkUp         : BOOL;                 (* the client's session is up *)
    (* Our own STATE birth certificate is published and the plant may rely on
       us. An edge node waiting for this host starts birthing once it sees it. *)
    bBorn           : BOOL;
    (* How many edge nodes we have heard from, and how many are online now. A
       node that has died stays tracked - knowing it is gone is worth more than
       forgetting it existed. *)
    nNodes          : INT;
    nOnline         : INT;
    (* Sequence gaps seen and rebirths asked for, across every node. Both
       climbing together is a lossy link; gaps climbing alone means the window
       is absorbing them, which is what it is for. *)
    nGaps           : DINT;
    nRebirths       : DINT;
    bError          : BOOL;
    eErrorId        : E_MqttResult;
    sLastError      : STRING(64);           (* what the host waits for, or what failed *)
  END_VAR
  VAR
    nApi            : __XWORD;              (* the host, for the methods *)
    bConnectAsked   : BOOL;
    nClient         : __XWORD;              (* the client the host was built on *)
    nTask           : __XWORD;              (* the task this block runs in *)
    nCalls          : __XWORD;              (* the methods' per-call state *)
  END_VAR

METHOD PUBLIC Watch : E_MqttResult
  VAR_INPUT
    sMetricName     : STRING(96);           (* the metric, as the node declared it *)
    anyValue        : ANY;                  (* where to put it; its type must match the birth *)
    sEdgeNodeId     : STRING(47);           (* empty: the first node heard from *)
    sNodeGroupId    : STRING(47);           (* empty: any watched group *)
    sDeviceId       : STRING(47);           (* for a device metric *)
  END_VAR
  VAR_OUTPUT
    bValid          : BOOL;                 (* anyValue was written by this call *)
    bTypeOk         : BOOL;                 (* FALSE: anyValue's type is not the declared one *)
    bFresh          : BOOL;                 (* the reading changed since the last call *)
    nAge            : DINT;                 (* ms since the node's timestamp on it *)
    nReadCnt        : DINT;                 (* readings written *)
  END_VAR
END_METHOD

METHOD PUBLIC Write : E_MqttResult
  VAR_INPUT
    sMetricName     : STRING(96);           (* the metric, as the node declared it *)
    anyValue        : ANY;                  (* what to write; its type must match the birth *)
    sEdgeNodeId     : STRING(47);           (* empty: the first node heard from *)
    sNodeGroupId    : STRING(47);           (* empty: any watched group *)
    sDeviceId       : STRING(47);           (* for a device metric *)
    bExecute        : BOOL;                 (* rising edge sends *)
  END_VAR
  VAR_OUTPUT
    nSentCnt        : DINT;                 (* commands sent *)
  END_VAR
END_METHOD

#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugHost.h>
#include <string>
#include <vector>
#include <string.h>

// Defined by FB_SparkplugNode, which sorts after this file - a declaration
// before use is all C++ needs in the one translation unit.
bool mq_spWriteAny(const strucpp::IEC_ANY& any, const MqttSparkplugValue& value);
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out);

// Defined by FB_MqttClient, which sorts before this file.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);

// --- The methods' state, one table per host block ---
//
// Keyed by the call's anyValue: its declared name and type (Write adds the
// metric name, so two writes of the same literal stay apart). The last index
// found is tried first, as calls come in the same order every scan.
namespace {
struct MqSpWatchCall {
    std::string name;
    std::string type;
    bool ever = false;
    int64_t lastAt = 0;
    bool typeOk = false;
    int32_t age = 0;
    int32_t reads = 0;
};

struct MqSpWriteCall {
    std::string name;
    std::string type;
    std::string metric;
    bool lastExecute = false;
    bool busy = false;
    E_MQTTRESULT result = E_MQTTRESULT::OK;
    int32_t sent = 0;
    // Latched at the rising edge.
    std::string node;
    std::string group;
    std::string device;
    std::string text;            // a STRING value's text; the value points at it when sent
    bool isText = false;
    MqttSparkplugValue value;
};

struct MqSpHostCalls {
    std::vector<MqSpWatchCall> watches;
    std::vector<MqSpWriteCall> writes;
    size_t nextWatch = 0;
    size_t nextWrite = 0;
};

// Everything this block made, freed when the program is unloaded. A host only
// leaves its client here: the connection is FB_MqttClient's, whose own cleanup
// runs after this one and closes the link WITHOUT a DISCONNECT - so the broker
// publishes this host's offline STATE, the Will it registered, the moment the
// PLC stops.
// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqSpHostsOwned {
    std::vector<MqttSparkplugHost*> hosts;
    std::vector<MqSpHostCalls*> calls;
    ~MqSpHostsOwned() {
        for (size_t i = 0; i < hosts.size(); i++) delete hosts[i];
        for (size_t i = 0; i < calls.size(); i++) delete calls[i];
    }
};
MqSpHostsOwned& mqSpHostsOwned() {
    static MqSpHostsOwned owned;
    return owned;
}
}  // namespace

MqttSparkplugHost* mq_spHostOf(strucpp::XWORD_t handle) {
    return (MqttSparkplugHost*)(uintptr_t)handle;
}

static MqSpHostCalls* mq_spHostCalls(strucpp::XWORD_t& handle) {
    if (handle) return (MqSpHostCalls*)(uintptr_t)handle;
    MqSpHostCalls* calls = new (std::nothrow) MqSpHostCalls();
    if (!calls) return nullptr;
    mqSpHostsOwned().calls.push_back(calls);
    handle = (strucpp::XWORD_t)(uintptr_t)calls;
    return calls;
}

static const char* mq_spHostCstr(const char* text) { return text ? text : ""; }

static bool mq_spSameKey(const std::string& name, const std::string& type,
                         const strucpp::IEC_ANY& any) {
    return name == mq_spHostCstr(any.NAME) && type == mq_spHostCstr(any.TYPENAME);
}

static MqSpWatchCall* mq_spWatchCall(MqSpHostCalls& calls, const strucpp::IEC_ANY& any) {
    std::vector<MqSpWatchCall>& table = calls.watches;
    size_t index = calls.nextWatch;
    if (index >= table.size() || !mq_spSameKey(table[index].name, table[index].type, any)) {
        for (index = 0; index < table.size(); index++) {
            if (mq_spSameKey(table[index].name, table[index].type, any)) break;
        }
        if (index == table.size()) {
            MqSpWatchCall fresh;
            fresh.name = mq_spHostCstr(any.NAME);
            fresh.type = mq_spHostCstr(any.TYPENAME);
            table.push_back(fresh);
        }
    }
    calls.nextWatch = index + 1;
    return &table[index];
}

static MqSpWriteCall* mq_spWriteCall(MqSpHostCalls& calls, const strucpp::IEC_ANY& any,
                                     const char* metric) {
    std::vector<MqSpWriteCall>& table = calls.writes;
    size_t index = calls.nextWrite;
    if (index >= table.size() ||
        !mq_spSameKey(table[index].name, table[index].type, any) ||
        table[index].metric != metric) {
        for (index = 0; index < table.size(); index++) {
            if (mq_spSameKey(table[index].name, table[index].type, any) &&
                table[index].metric == metric) break;
        }
        if (index == table.size()) {
            MqSpWriteCall fresh;
            fresh.name = mq_spHostCstr(any.NAME);
            fresh.type = mq_spHostCstr(any.TYPENAME);
            fresh.metric = metric;
            table.push_back(fresh);
        }
    }
    calls.nextWrite = index + 1;
    return &table[index];
}

// Which node. With one node on the plant the empty id is what an engineer
// expects to work, so it resolves to the only node there is. With two it
// would pick whichever birthed first, so name it. No group given: the node of
// that name whatever group it is in - one plant, one naming scheme.
static const MqttSparkplugTrackedNode* mq_spHostNode(MqttSparkplugHost& host,
                                                     const char* node,
                                                     const char* group) {
    if (node[0] != '\0') {
        if (group[0] != '\0') return host.findNode(group, node);
        for (size_t index = 0; index < host.nodeCount(); index++) {
            const MqttSparkplugTrackedNode* candidate = host.nodeAt(index);
            if (candidate == nullptr) continue;
            if (candidate->node != node) continue;
            return candidate;
        }
        return nullptr;
    }
    return host.nodeCount() > 0 ? host.nodeAt(0) : nullptr;
}

void setup()
{
    bLinkUp = false;
    bBorn = false;
    nNodes = 0;
    nOnline = 0;
    nGaps = 0;
    nRebirths = 0;
    bError = false;
    eErrorId = E_MQTTRESULT::OK;
    sLastError = "";
    nApi = (strucpp::XWORD_t)0;
    nClient = (strucpp::XWORD_t)0;
    bConnectAsked = false;
}

void loop()
{
    nTask = mq_currentTask();   // the methods are refused in any other task

    // --- THE CONNECTION IS FB_MqttClient'S --- as for FB_SparkplugNode: this
    // host is a layer on that session and takes the Will (its offline STATE)
    // and Clean Start on every CONNECT.
    if (!mq_inTask((strucpp::XWORD_t)fbClient.NTASK)) {   // one task per client
        bLinkUp = false;
        bBorn = false;
        bError = true;
        eErrorId = E_MQTTRESULT::WRONGTASK;
        sLastError = "put FB_SparkplugHost in its FB_MqttClient's task";
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)fbClient.NAPI);
    if (client == nullptr) {
        bLinkUp = false;
        bBorn = false;
        bError = false;
        eErrorId = E_MQTTRESULT::NOTINITIALISED;
        sLastError = "waiting for its FB_MqttClient";
        return;
    }

    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)nApi);
    if (!(bool)bEnable) {
        // The offline STATE goes by hand and the connection stays up for
        // everything else on it.
        if (host) {
            host->disconnect();
            host->poll();
        }
        bLinkUp = client->isConnected();
        bBorn = false;
        bConnectAsked = false;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
        sLastError = "";
        return;
    }

    // --- Build once ---
    //
    // On the first enabled scan, for the life of the program. A host that
    // rebuilt itself would drop every node's dictionary and read nothing until
    // each one birthed again.
    if (host == nullptr) {
        if (sHostId.length() == 0) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "a host application needs an sHostId";
            return;
        }
        // Kilobytes - and on the Runtime tens of them (every tracked node's
        // metric table) - so it is asked for, not assumed: a plain new that
        // fails is a hard fault on a board with no exceptions.
        host = new (std::nothrow) MqttSparkplugHost(*client);
        if (host == nullptr) {
            bError = true;
            eErrorId = E_MQTTRESULT::NOTINITIALISED;
            sLastError = "out of memory";
            return;
        }
        if (!host->hostId(sHostId.c_str())) {
            delete host;
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDTOPIC;
            sLastError = "sHostId is empty or contains + / or #";
            return;
        }
        // sGroupId empty watches every group.
        if (!host->watch(sGroupId.length() != 0 ? sGroupId.c_str() : nullptr)) {
            delete host;
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDTOPIC;
            sLastError = "sGroupId contains + / or #";
            return;
        }
        host->actAsPrimary((bool)bPrimary);
        host->reorderTimeout((mq_time_t)mq_millisOf(tReorder));
        mqSpHostsOwned().hosts.push_back(host);
        nApi = (strucpp::XWORD_t)(uintptr_t)host;
        nClient = (strucpp::XWORD_t)(uintptr_t)client;
    }
    if ((strucpp::XWORD_t)(uintptr_t)client != (strucpp::XWORD_t)nClient) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = "fbClient changed while running - restart the PLC";
        return;
    }

    // Refused only when another layer owns the client's Will, and asked again
    // every scan, so removing that one is enough.
    if (!bConnectAsked) bConnectAsked = host->connect();
    host->poll();

    bLinkUp = client->isConnected();
    bBorn = host->isBorn();
    nNodes = (int16_t)host->nodeCount();
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
    nOnline = online;
    nGaps = gaps;
    nRebirths = rebirths;

    if (!bConnectAsked) {
        bError = true;
        eErrorId = E_MQTTRESULT::REFUSED;
        sLastError = "another layer owns the client's Will";
        return;
    }
    const MqttSparkplugError payloadError = host->lastPayloadError();
    if (payloadError != MqttSparkplugError::None) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = mq_sparkplugErrorName(payloadError);
        return;
    }
    if (host->outOfMemory()) {
        bError = true;
        eErrorId = E_MQTTRESULT::QUEUEFULL;
        sLastError = "out of memory for tracked nodes or metrics";
        return;
    }
    bError = false;
    eErrorId = bLinkUp ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;
    sLastError = bLinkUp ? "" : "FB_MqttClient is not connected";
}

E_MQTTRESULT Watch()
{
    bValid = false;
    bFresh = false;
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;

    strucpp::XWORD_t handle = (strucpp::XWORD_t)nCalls;
    MqSpHostCalls* calls = mq_spHostCalls(handle);
    nCalls = handle;
    if (calls == nullptr) return E_MQTTRESULT::QUEUEFULL;
    MqSpWatchCall& call = *mq_spWatchCall(*calls, anyValue);
    bTypeOk = call.typeOk;
    nAge = call.age;
    nReadCnt = call.reads;

    if (sMetricName.length() == 0) return E_MQTTRESULT::INVALIDARGUMENT;

    // The host block has not built itself yet: ordinary on the first scan.
    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)nApi);
    if (host == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    // Kept, not dropped: the next reading after the link returns is valid.
    if (!host->isConnected()) return E_MQTTRESULT::NOTCONNECTED;

    // Nothing heard from, declared but never published, or never declared:
    // all mean the same thing to a rung - do not act on this.
    const MqttSparkplugTrackedNode* tracked =
        mq_spHostNode(*host, sEdgeNodeId.c_str(), sNodeGroupId.c_str());
    if (tracked == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    const MqttSparkplugTrackedMetric* metric =
        tracked->find(sMetricName.c_str(), sDeviceId.length() != 0 ? sDeviceId.c_str() : nullptr);
    if (metric == nullptr || !metric->hasValue) return E_MQTTRESULT::NOTINITIALISED;

    if (!mq_spWriteAny(anyValue, metric->value)) {
        // THE DECLARED TYPE DID NOT MATCH. The birth certificate is the
        // contract; writing a coerced value would hide a misread one until
        // something acted on a truncated number.
        call.typeOk = false;
        bTypeOk = false;
        return E_MQTTRESULT::INVALIDARGUMENT;
    }

    call.typeOk = true;
    call.reads = call.reads + 1;

    // Age from the NODE's timestamp, which is when the reading happened, not
    // when we received it.
    const int64_t at = (int64_t)metric->at;
    bFresh = !call.ever || at != call.lastAt;
    call.lastAt = at;
    call.ever = true;

    const int64_t now = (int64_t)mq_epochMillis();
    if (now > 0 && at > 0 && now >= at) {
        const int64_t age = now - at;
        // Clamped rather than wrapped: a DINT of milliseconds covers 24 days,
        // and anything past that is "very old" by any reading.
        call.age = (int32_t)(age > 2147483647LL ? 2147483647LL : age);
    } else {
        call.age = 0;
    }

    bValid = true;
    bTypeOk = true;
    nAge = call.age;
    nReadCnt = call.reads;
    return E_MQTTRESULT::OK;
}

E_MQTTRESULT Write()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;

    strucpp::XWORD_t handle = (strucpp::XWORD_t)nCalls;
    MqSpHostCalls* calls = mq_spHostCalls(handle);
    nCalls = handle;
    if (calls == nullptr) return E_MQTTRESULT::QUEUEFULL;
    MqSpWriteCall& call = *mq_spWriteCall(*calls, anyValue, sMetricName.c_str());

    const bool execute = (bool)bExecute;
    const bool rising = execute && !call.lastExecute;
    call.lastExecute = execute;
    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)nApi);

    if (rising) {
        // Every input is taken here; changing them while busy has no effect.
        call.busy = false;
        call.node = sEdgeNodeId.c_str();
        call.group = sNodeGroupId.c_str();
        call.device = sDeviceId.c_str();
        call.isText = anyValue.TYPECLASS == strucpp::TYPE_STRING && anyValue.PVALUE != nullptr;
        call.text = call.isText ? (const char*)anyValue.PVALUE : "";
        if (host == nullptr || !host->isConnected()) {
            call.result = E_MQTTRESULT::NOTCONNECTED;     // refused, never queued
        } else if (sMetricName.length() == 0) {
            call.result = E_MQTTRESULT::INVALIDARGUMENT;
        } else if (!mq_spValueOfAny(anyValue, &call.value)) {
            // An IEC type with no Sparkplug datatype - a DATE, a STRUCT -
            // refused rather than sent as something it is not.
            call.result = E_MQTTRESULT::INVALIDARGUMENT;
        } else {
            call.busy = true;
        }
    }

    if (call.busy) {
        if (!execute) {
            // bExecute fell before the node could be reached: dropped. The
            // plant has moved on from a command the operator let go of.
            call.busy = false;
            call.result = E_MQTTRESULT::CANCELLED;
        } else if (host == nullptr || !host->isConnected()) {
            call.busy = false;
            call.result = E_MQTTRESULT::NOTCONNECTED;
        } else {
            const MqttSparkplugTrackedNode* tracked =
                mq_spHostNode(*host, call.node.c_str(), call.group.c_str());
            if (tracked != nullptr) {
                // The value points at the latched text, not the caller's.
                if (call.isText) call.value = mq_spString(call.text.c_str());
                const char* metric = call.metric.c_str();
                bool ok = false;
                if (call.device.length() != 0) {
                    ok = host->commandDevice(tracked->group.c_str(), tracked->node.c_str(),
                                             call.device.c_str(), metric, call.value);
                } else {
                    ok = host->command(tracked->group.c_str(), tracked->node.c_str(),
                                       metric, call.value);
                }
                call.busy = false;
                if (ok) {
                    call.sent = call.sent + 1;
                    call.result = E_MQTTRESULT::OK;
                } else {
                    call.result = E_MQTTRESULT::REFUSED;
                }
            }
        }
    }

    nSentCnt = call.sent;
    return call.busy ? E_MQTTRESULT::QUEUED : call.result;
}

END_FUNCTION_BLOCK
