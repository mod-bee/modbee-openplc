(* A SPARKPLUG B HOST APPLICATION on an FB_MqttClient's connection: the other
end of FB_SparkplugNode. Call it once every scan, in the client's task. It
keeps the current picture of every edge node it watches; Watch reads a value
out of that picture and Write sends one back down.

sHostId     this host's Sparkplug Host ID. It is a topic element and MUST be
           unique in the system. An edge node's sPrimaryHostId carries this
           same string. Up to 47 characters.
sWatchedGroupId  the group to watch, or empty for every group. Narrow it on a real
           plant: a host on spBv1.0/# receives every other line's traffic.
bRequestRebirthOnGap  TRUE (default): ask for a rebirth when a node's sequence skips.
           Nothing in the protocol marks a host primary - the NODES name it -
           so this only decides whether a gap asks; two hosts both asking
           double the traffic for one missed message.
tSequenceGapDelay  how long to let a gap fill before asking. T#5s by default; T#0s
           asks at once. A link that reorders now and then should not cost a
           full birth each time.
bEnable     FALSE publishes the offline STATE and stands the host down; the
           connection stays up for everything else on it.
fbClient    the FB_MqttClient this host rides on. Must be assigned; broker,
           TLS, login and protocol are set there.

bConnected  the client's bConnected: the broker has accepted it.
bHostOnline  our STATE birth certificate is published, so nodes may rely on us.
           A node waiting for this host starts birthing once it sees it.
nNodesKnown  edge nodes heard from. A node that died stays tracked: knowing it
           is gone is worth more than forgetting it existed.
nNodesOnline  how many of them are online now.
nSequenceGapCount  sequence gaps seen, every node together.
nRebirthRequestCount  rebirths asked for. Both climbing together is a lossy link; gaps
           climbing alone means tSequenceGapDelay is absorbing them.
bError, eErrorId  E_MqttResult.Ok when fine; WrongTask: not in its client's
           task.
sLastError  what the host waits for, or what failed: "out of memory for
           tracked nodes or metrics" when it could not follow everything that
           arrived. It tracks as many nodes, and metrics per node, as memory
           holds, on a board and the Runtime alike.

METHODS

Both run in the host's task and return E_MqttResult.WrongTask in any other.
A call is found again by anyValue's declared name and type with sMetricName.

  host.Watch(sMetricName, anyValue, sEdgeNodeId, sGroupId, sDeviceId,
             bValid =>, bTypeMatches =>, bValueReceived =>, nValueAgeMs =>, nReadingCount =>)
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
     sGroupId      which group. Empty: any group the host watches.
     sDeviceId     for a metric of a device rather than the node.
     bValid        this call wrote anyValue.
     bTypeMatches  FALSE: anyValue's type is not the declared one.
     bValueReceived  the reading changed since the last call.
     nValueAgeMs   milliseconds since the NODE's timestamp on it - not since
                   we received it; on a slow link those differ by more than a
                   control decision should ignore.
     nReadingCount  readings written into anyValue.
     Ok when anyValue holds a valid reading; NotInitialised while the host is
     not built, the node not heard or the metric not published (a plant
     starting up spends its first seconds here); NotConnected while the
     client is down; InvalidArgument for an empty sMetricName or a type
     mismatch.

  host.Write(sMetricName, anyValue, sEdgeNodeId, sGroupId, sDeviceId,
             bExecute, nSentCommandCount =>)
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
     datatype), held until the next rising edge. nSentCommandCount: commands this
     call has sent.

---

WHAT A HOST DOES THAT A NODE DOES NOT, and why this is a separate block:

  - It publishes its OWN birth and death certificate on
    spBv1.0/STATE/<sHostId>, at QoS 1 and RETAINED - retained, unlike a
    node's death certificate, because a node subscribing later has to find
    it waiting or it will never birth at all.
  - It reads names out of BIRTH certificates and resolves them against the
    aliases data messages carry. A conformant node puts names only in its
    births; without the dictionary a host receives numbers it cannot name.
  - It notices gaps in a node's sequence number and, with bRequestRebirthOnGap, asks for
    a rebirth.

sPrimaryHostId on the node and sHostId here are the same string. A node
configured with one will not birth until this host says it is online, which
is how a plant avoids nodes publishing into a SCADA that is not listening.

ONE CONNECTION, SHARED. The host is a layer on its client's session and
takes its Will - the offline STATE - and a clean session on every CONNECT, so
no stWill and no FB_SparkplugNode on the same client: a connection
carries one Will. Started on a session already up, it reconnects it once so
the next CONNECT carries the STATE.

ONE TASK. This block, its methods and fbClient run in the network task, and
the rest of the program trades values with them through globals. *)

FUNCTION_BLOCK FB_SparkplugHost
  VAR_INPUT
    sHostId         : STRING(47);           (* this host's Sparkplug Host ID; nodes' sPrimaryHostId is this string *)
    (* The group to watch, or empty for every group. Narrowing matters on a
       real plant: a host subscribed to spBv1.0/# in a large estate receives
       every other line's traffic to discard. *)
    sWatchedGroupId : STRING(47); (* the group to watch; empty for every group *)
    (* Whether to act as the PRIMARY host.
       Nothing in the protocol marks a host as primary - the NODES are
       configured with its id - so this only decides whether a sequence gap
       produces a rebirth request. Two hosts both asking would double the
       traffic for one missed message. *)
    bRequestRebirthOnGap : BOOL := TRUE; (* ask a node for a rebirth when its sequence skips (all this pin does) *)
    (* How long to wait for a gap to fill before asking for a rebirth.
       A link that reorders occasionally should not trigger a full birth every
       time. T#0s disables the window and asks immediately. *)
    tSequenceGapDelay : TIME := T#5s; (* how long a sequence gap may fill before a rebirth is asked; T#0s asks at once *)
    bEnable : BOOL := TRUE; (* FALSE publishes the offline STATE and stands the host down *)
  END_VAR
  VAR_IN_OUT
    fbClient : FB_MqttClient; (* the connection this host rides on *)
  END_VAR
  VAR_OUTPUT
    bConnected : BOOL; (* the client's broker connection is accepted (the client's bConnected): interlock on this *)
    (* Our own STATE birth certificate is published and the plant may rely on
       us. An edge node waiting for this host starts birthing once it sees it. *)
    bHostOnline : BOOL; (* our online STATE is published, so nodes may rely on us *)
    (* How many edge nodes we have heard from, and how many are online now. A
       node that has died stays tracked - knowing it is gone is worth more than
       forgetting it existed. *)
    nNodesKnown : INT; (* edge nodes heard from, dead ones included *)
    nNodesOnline : INT; (* of those, online now *)
    (* Sequence gaps seen and rebirths asked for, across every node. Both
       climbing together is a lossy link; gaps climbing alone means the window
       is absorbing them, which is what it is for. *)
    nSequenceGapCount : DINT; (* sequence gaps seen, all nodes together *)
    nRebirthRequestCount : DINT; (* rebirths asked for *)
    bError : BOOL; (* something failed *)
    eErrorId : E_MqttResult; (* why; Ok when fine, WrongTask outside the client's task *)
    sLastError : STRING(64); (* what the host waits for, or what failed *)
  END_VAR
  VAR
    nApi            : __XWORD;              (* the host, for the methods *)
    bConnectAsked   : BOOL;
    nClient         : __XWORD;              (* the client the host was built on *)
    nTask           : __XWORD;              (* the task this block runs in *)
    nCalls          : __XWORD;              (* the methods' per-call state *)
  END_VAR
(* Reads one metric of a watched node into anyValue, called every scan. The
   metric's declared type must match anyValue's. Ok while anyValue holds a
   valid reading; NotInitialised until the node and the metric are heard. *)
METHOD PUBLIC Watch : E_MqttResult
  VAR_INPUT
    sMetricName     : STRING(96);           (* the metric, as the node declared it *)
    anyValue        : ANY;                  (* where to put it; its type must match the birth *)
    sEdgeNodeId     : STRING(47);           (* which node; empty = the first node heard from *)
    sGroupId    : STRING(47);           (* the node's Sparkplug Group ID; empty = any watched group *)
    sDeviceId       : STRING(47);           (* for a device metric; empty for a node metric *)
  END_VAR
  VAR_OUTPUT
    bValid          : BOOL;                 (* anyValue holds a valid reading, written by this call *)
    bTypeMatches         : BOOL;                 (* anyValue's type is the declared one *)
    bValueReceived          : BOOL;                 (* a new reading arrived since the last call (same name as Subscribe) *)
    nValueAgeMs            : DINT;                 (* ms since the node's timestamp on it *)
    nReadingCount        : DINT;                 (* readings written into anyValue *)
  END_VAR
END_METHOD

(* Sends one command (NCMD, or DCMD for a device) on a rising edge of
   bExecute. Queued while the node is not heard yet and bExecute stays
   TRUE; Cancelled if bExecute falls first; then Ok (sent) or the reason.
   Not connected at the edge: NotConnected, nothing queued. *)
METHOD PUBLIC Write : E_MqttResult
  VAR_INPUT
    sMetricName     : STRING(96);           (* the metric, as the node declared it *)
    anyValue        : ANY;                  (* the value to write; its type must match the birth *)
    sEdgeNodeId     : STRING(47);           (* which node; empty = the first node heard from *)
    sGroupId    : STRING(47);           (* the node's Sparkplug Group ID; empty = any watched group *)
    sDeviceId       : STRING(47);           (* for a device metric (DCMD) *)
    bExecute        : BOOL;                 (* rising edge sends; falling before the node is heard cancels *)
  END_VAR
  VAR_OUTPUT
    nSentCommandCount        : DINT;                 (* commands this call has sent *)
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
    bConnected = false;
    bHostOnline = false;
    nNodesKnown = 0;
    nNodesOnline = 0;
    nSequenceGapCount = 0;
    nRebirthRequestCount = 0;
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
        bConnected = false;
        bHostOnline = false;
        bError = true;
        eErrorId = E_MQTTRESULT::WRONGTASK;
        sLastError = "put FB_SparkplugHost in its FB_MqttClient's task";
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)fbClient.NAPI);
    if (client == nullptr) {
        bConnected = false;
        bHostOnline = false;
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
        bConnected = client->isConnected();
        bHostOnline = false;
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
        // sWatchedGroupId empty watches every group.
        if (!host->watch(sWatchedGroupId.length() != 0 ? sWatchedGroupId.c_str() : nullptr)) {
            delete host;
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDTOPIC;
            sLastError = "sWatchedGroupId contains + / or #";
            return;
        }
        host->actAsPrimary((bool)bRequestRebirthOnGap);
        host->reorderTimeout((mq_time_t)mq_millisOf(tSequenceGapDelay));
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

    bConnected = client->isConnected();
    bHostOnline = host->isBorn();
    nNodesKnown = (int16_t)host->nodeCount();
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
    nNodesOnline = online;
    nSequenceGapCount = gaps;
    nRebirthRequestCount = rebirths;

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
    eErrorId = bConnected ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;
    sLastError = bConnected ? "" : "FB_MqttClient is not connected";
}

E_MQTTRESULT Watch()
{
    bValid = false;
    bValueReceived = false;
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;

    strucpp::XWORD_t handle = (strucpp::XWORD_t)nCalls;
    MqSpHostCalls* calls = mq_spHostCalls(handle);
    nCalls = handle;
    if (calls == nullptr) return E_MQTTRESULT::QUEUEFULL;
    MqSpWatchCall& call = *mq_spWatchCall(*calls, anyValue);
    bTypeMatches = call.typeOk;
    nValueAgeMs = call.age;
    nReadingCount = call.reads;

    if (sMetricName.length() == 0) return E_MQTTRESULT::INVALIDARGUMENT;

    // The host block has not built itself yet: ordinary on the first scan.
    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)nApi);
    if (host == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    // Kept, not dropped: the next reading after the link returns is valid.
    if (!host->isConnected()) return E_MQTTRESULT::NOTCONNECTED;

    // Nothing heard from, declared but never published, or never declared:
    // all mean the same thing to a rung - do not act on this.
    const MqttSparkplugTrackedNode* tracked =
        mq_spHostNode(*host, sEdgeNodeId.c_str(), sGroupId.c_str());
    if (tracked == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    const MqttSparkplugTrackedMetric* metric =
        tracked->find(sMetricName.c_str(), sDeviceId.length() != 0 ? sDeviceId.c_str() : nullptr);
    if (metric == nullptr || !metric->hasValue) return E_MQTTRESULT::NOTINITIALISED;

    if (!mq_spWriteAny(anyValue, metric->value)) {
        // THE DECLARED TYPE DID NOT MATCH. The birth certificate is the
        // contract; writing a coerced value would hide a misread one until
        // something acted on a truncated number.
        call.typeOk = false;
        bTypeMatches = false;
        return E_MQTTRESULT::INVALIDARGUMENT;
    }

    call.typeOk = true;
    call.reads = call.reads + 1;

    // Age from the NODE's timestamp, which is when the reading happened, not
    // when we received it.
    const int64_t at = (int64_t)metric->at;
    bValueReceived = !call.ever || at != call.lastAt;
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
    bTypeMatches = true;
    nValueAgeMs = call.age;
    nReadingCount = call.reads;
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
        call.group = sGroupId.c_str();
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

    nSentCommandCount = call.sent;
    return call.busy ? E_MQTTRESULT::QUEUED : call.result;
}

END_FUNCTION_BLOCK