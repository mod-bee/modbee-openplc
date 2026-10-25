(* Keeps events while the link is down and sends them after it comes back,
flagged historical, in order, at the time they happened.

NODE       which node. Must be wired.
ADD        TRUE records one event on this call. Wire a one-scan pulse (an edge
           of the alarm, the stop, the deferral) - call the block again with
           other pins for more than one event in a scan.
SOURCE     what the event is about: a pump, an alarm number, a zone.
CODE       what happened: a status, fault or stop code. The HMI and SCADA hold
           the words for it.
VALUE      a number that goes with it: a level, a volume, a run time.
NAME       the metrics' prefix. 'Event' gives Event/source, Event/code,
           Event/value, Event/seq and Event/lost.
DEPTH      events kept while the node cannot publish. Fixed at the first
           call. 256 is about a week of a normal site's events, 6 KB of PSRAM.
BATCH      events per message when catching up.
PERIOD     the gap between catch-up messages, so a slow cellular link is not
           flooded.

STORED     events waiting to be sent.
LOST       events dropped because the buffer was full: the oldest go, the
           newest are kept. Also published as <NAME>/lost.
SENT       events sent since the program started.
REPLAYING  catching up after an outage.
ERROR      no memory for the buffer, or the metrics could not be declared.
STATUS     why. MQTT_OK when fine.

---

  history(NODE := sp, ADD := pumpStopped, SOURCE := 1, CODE := pump1.StopCode,
          VALUE := level);
  history(NODE := sp, ADD := alarmRaised, SOURCE := 100 + alarmNo, CODE := 1,
          VALUE := 0.0);

SPARKPLUG HAS NO STORE-AND-FORWARD OF ITS OWN. While the node is not born - no
cellular coverage, the broker away, the primary host offline - nothing is sent,
and after the next birth the host sees only the values as they are then: why
the pump stopped at 03:12 is gone. This block keeps those events and sends
them afterwards with Sparkplug's is_historical flag, which tells the host to
file each one at its own timestamp and NOT to overwrite the live tag with it
(Sparkplug B 3.0, the metric's is_historical field: "store and forward, or
sending local backup data during network communication losses").

EVERY EVENT IS ONE ROW of four metrics with the same timestamp: source, code,
value and seq (a count from 1 since the program started, so the host can see
that none is missing). While the node is born an event goes at once, as live
data; recorded while it is not, it waits and goes historical. A value that
repeats is still sent - an event is an event, not a change of value.

WHAT IS KEPT: events, not analogs. A level that moves every scan would fill
any buffer; the reasons, the stops, the alarms and the day totals
(SPARKPLUG_DAY_TOTALS) are what a host cannot reconstruct afterwards.
Totals and counters that only go up reconcile the rest by themselves.

NOT RETAINED. A power cut during an outage loses the waiting events; the
counters still reconcile. The buffer lives in PSRAM where the board has it.

THE CLOCK. An event recorded before MQTT_CLOCK has set the board's clock is
kept with the board's uptime and put on the clock as soon as it is set. Events
wait for the clock up to five minutes after the birth, then go with what they
have.

SENT AT LEAST ONCE. A message is published at QoS 0 like all Sparkplug data,
so an event is forgotten only after the node has stayed born for a moment
afterwards; a link that drops in that moment sends the batch again. The host
may see an event twice, never not at all - the timestamp and seq make the
duplicate obvious. *)

FUNCTION_BLOCK SPARKPLUG_HISTORY
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
  END_VAR
  VAR_INPUT
    ADD : BOOL;
    SOURCE : UINT;
    CODE : UINT;
    VALUE : REAL;
    NAME : STRING(24) := 'Event';
    DEPTH : UINT := 256;
    BATCH : UINT := 20;
    PERIOD : TIME := T#1s;
  END_VAR
  VAR_OUTPUT
    STORED : UINT;
    LOST : UDINT;
    SENT : UDINT;
    REPLAYING : BOOL;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR
    fbState : __XWORD;
    fbDeclared : BOOL;
    fbSeq : UDINT;
    fbPending : UINT;
    fbSentAt : DINT;
    fbBirths : UDINT;
    fbBornAt : DINT;
    fbWasBorn : BOOL;
    fbLimit : UINT;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <sparkplug/MqttSparkplugHistory.h>
#include <new>
#include <string>
#include <vector>

MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

namespace {

// Everything one block instance owns, on the heap: the ring (its events in
// PSRAM, see MqttSparkplugHistory), the metric indexes, and the records a
// batch is built in - also PSRAM, so a catch-up message costs the task's stack
// nothing.
struct MqSpHistoryState {
    MqttSparkplugHistory ring;
    MqttSparkplugRecord* scratch = nullptr;
    size_t scratchCount = 0;
    int index[5] = {-1, -1, -1, -1, -1};   // source, code, value, seq, lost
    ~MqSpHistoryState() {
        if (scratch != nullptr) {
            for (size_t i = 0; i < scratchCount; i++) scratch[i].~MqttSparkplugRecord();
            mq_freeLarge(scratch);
        }
    }
};

// Freed with the program: the Runtime loads a new program into the same
// process, and a buffer per download would add up.
struct MqSpHistoryCleanup {
    std::vector<MqSpHistoryState*> owned;
    ~MqSpHistoryCleanup() {
        for (size_t i = 0; i < owned.size(); i++) delete owned[i];
    }
};
MqSpHistoryCleanup mqSpHistoryCleanup;

const char* const kMqSpHistoryParts[5] = {"/source", "/code", "/value", "/seq", "/lost"};

}  // namespace

void setup()
{
    STORED = 0;
    LOST = 0;
    SENT = 0;
    REPLAYING = false;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbState = (strucpp::XWORD_t)0;
    fbDeclared = false;
    fbSeq = 0;
    fbPending = 0;
    fbSentAt = 0;
    fbBirths = 0;
    fbBornAt = 0;
    fbWasBorn = false;
    fbLimit = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }

    // --- The buffer, on the first call: a scan, long after PSRAM is up ---
    MqSpHistoryState* state = (MqSpHistoryState*)(uintptr_t)(strucpp::XWORD_t)fbState;
    if (state == nullptr) {
        state = new (std::nothrow) MqSpHistoryState();
        if (state == nullptr) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            return;
        }
        mqSpHistoryCleanup.owned.push_back(state);
        fbState = (strucpp::XWORD_t)(uintptr_t)state;
        const size_t depth = (uint16_t)DEPTH != 0 ? (size_t)(uint16_t)DEPTH : 256u;
        size_t batch = (uint16_t)BATCH != 0 ? (size_t)(uint16_t)BATCH : 20u;
        if (batch > 64) batch = 64;
        state->ring.begin(depth);
        void* raw = mq_allocLarge(batch * 4 * sizeof(MqttSparkplugRecord));
        if (raw != nullptr) {
            state->scratch = static_cast<MqttSparkplugRecord*>(raw);
            state->scratchCount = batch * 4;
            for (size_t i = 0; i < state->scratchCount; i++) {
                new (&state->scratch[i]) MqttSparkplugRecord();
            }
        }
        fbLimit = (uint16_t)batch;
    }
    if (!state->ring.ready() || state->scratch == nullptr) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
        if ((bool)ADD) state->ring.add(MqttSparkplugEvent());   // counted as lost
        LOST = state->ring.lost();
        return;
    }

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)NODE.FBAPI);
    const mq_time_t now = mq_millis();

    // --- Record ---
    if ((bool)ADD) {
        MqttSparkplugEvent event;
        event.source = (uint16_t)SOURCE;
        event.code = (uint16_t)CODE;
        event.value = (float)VALUE;
        fbSeq = (uint32_t)fbSeq + 1u;
        event.seq = (uint32_t)fbSeq;
        const bool clockSet = node != nullptr ? node->clockIsSet() : mq_epochMillis() != 0;
        if (clockSet) {
            event.timestamp = node != nullptr ? node->timestamp() : mq_epochMillis();
        } else {
            event.timestamp = (uint64_t)now;
            event.flags |= MQ_SP_EVENT_UPTIME;
        }
        if (node == nullptr || !node->isBorn()) event.flags |= MQ_SP_EVENT_OFFLINE;
        state->ring.add(event);
    }

    STORED = (uint16_t)state->ring.count();
    LOST = state->ring.lost();
    if (node == nullptr) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    // --- Declare, once, before the node births ---
    if (!(bool)fbDeclared) {
        fbDeclared = true;
        static const MqttSparkplugDataType types[5] = {
            MqttSparkplugDataType::UInt16, MqttSparkplugDataType::UInt16,
            MqttSparkplugDataType::Float, MqttSparkplugDataType::UInt32,
            MqttSparkplugDataType::UInt32};
        const std::string prefix = NAME.length() != 0 ? NAME.c_str() : "Event";
        for (int k = 0; k < 5; k++) {
            const std::string name = prefix + kMqSpHistoryParts[k];
            if (node->declare(name.c_str(), types[k]) == 0) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
            state->index[k] = node->indexOf(nullptr, name.c_str());
        }
        node->setAt((size_t)state->index[4], mq_spUInt32(state->ring.lost()));
    }
    if (state->index[0] < 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;

    // The lost count is live data, reported by exception with the rest.
    node->setAt((size_t)state->index[4], mq_spUInt32(state->ring.lost()));

    const bool born = node->isBorn();
    if (born && !(bool)fbWasBorn) fbBornAt = (int32_t)(uint32_t)now;
    fbWasBorn = born;

    // --- Confirm what went: the node stayed born on the same birth ---
    if ((uint16_t)fbPending > 0) {
        if (!born || node->birthCount() != (uint32_t)fbBirths) {
            fbPending = 0;   // not known to have arrived: sent again
        } else if ((int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbSentAt) >= 500) {
            state->ring.drop((uint16_t)fbPending);
            SENT = (uint32_t)SENT + (uint16_t)fbPending;
            fbPending = 0;
        }
    }

    STORED = (uint16_t)state->ring.count();
    REPLAYING = born && state->ring.count() > 0 &&
                (state->ring.peek(0)->flags & MQ_SP_EVENT_OFFLINE) != 0;
    if (!born || (uint16_t)fbPending > 0 || state->ring.empty()) return;

    // --- Send the next batch ---
    if (node->clockIsSet()) state->ring.placeOnClock(node->timestamp(), now);
    const MqttSparkplugEvent* first = state->ring.peek(0);
    const bool historical = (first->flags & MQ_SP_EVENT_OFFLINE) != 0;
    if ((first->flags & MQ_SP_EVENT_UPTIME) != 0 &&
        (int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbBornAt) < 300000) {
        return;   // wait for the clock, a while
    }
    if (historical) {
        const int32_t period = mq_millisOf(PERIOD) > 0 ? mq_millisOf(PERIOD) : 1000;
        if ((int32_t)(now - (mq_time_t)(uint32_t)(int32_t)fbSentAt) < period) return;
    }

    size_t limit = (uint16_t)fbLimit != 0 ? (size_t)(uint16_t)fbLimit : 1u;
    if (limit * 4 > state->scratchCount) limit = state->scratchCount / 4;
    size_t n = 0;
    while (n < limit && n < state->ring.count()) {
        const MqttSparkplugEvent* e = state->ring.peek(n);
        // One message is all historical or all live.
        if (((e->flags & MQ_SP_EVENT_OFFLINE) != 0) != historical) break;
        MqttSparkplugRecord* r = &state->scratch[n * 4];
        for (int k = 0; k < 4; k++) {
            r[k].index = (size_t)state->index[k];
            r[k].timestamp = e->timestamp;
        }
        r[0].value = mq_spUInt16(e->source);
        r[1].value = mq_spUInt16(e->code);
        r[2].value = mq_spFloat(e->value);
        r[3].value = mq_spUInt32(e->seq);
        n++;
    }
    if (n == 0) return;

    if (node->publishRecords(state->scratch, n * 4, historical)) {
        fbPending = (uint16_t)n;
        fbSentAt = (int32_t)(uint32_t)now;
        fbBirths = node->birthCount();
    } else if (n > 1 && node->isBorn()) {
        // Too big for the link's buffer, most likely: smaller batches.
        fbLimit = (uint16_t)(n / 2);
    }
}

END_FUNCTION_BLOCK