(* Sends one message when you ask. Acted on the rising edge of REQ.

CLIENT     which client. Must be wired.
REQ      rising edge sends. Holding it TRUE does not send repeatedly.
TOPIC    where it goes. No wildcards - those are for subscribing.
VALUE    what to send. Pass the variable itself and its declared type is what
         travels: a REAL goes as "23.5", an INT as "42", a BOOL as "true", a
         STRING as its text.
QOS      0 fire and forget, 1 at least once, 2 exactly once.
RETAINED   TRUE and the broker keeps it, so whoever subscribes next is told
         straight away instead of waiting for the next change.

BUSY     a level: the message is out and not yet concluded.
DONE     one scan, when the broker has it.
ERROR    one scan, when it failed.
STATUS   why. MQTT_OK when fine.

---

DONE MEANS DIFFERENT THINGS AT DIFFERENT QOS, and the difference is the whole
point of the pin. At QoS 0 it means the bytes left this device. At QoS 1 it
means the broker acknowledged them. At QoS 2 it means the broker acknowledged
them exactly once and the four-packet handshake completed. Interlock on DONE
at QoS 1 or 2 and you have a real delivery receipt; at QoS 0 you have a
despatch note.

DONE and ERROR are one scan wide, so latch them if a slower task has to see
one. BUSY is a level and is the pin to gate a sequence on.

One instance can serve many topics. The block keeps its state against the
topic it was given, so calling the same instance twice in a scan with two
different topics is two publishes, each with its own outcome - and a program
publishing fifty points costs one block rather than fifty. The outputs
describe the last call.

Nothing is silently dropped. A topic the broker will not take, a payload
larger than the connection allows, a queue that is full - each comes back on
STATUS with its own name rather than disappearing. *)

FUNCTION_BLOCK MQTT_PUBLISH
  VAR_INPUT
    REQ : BOOL;
    TOPIC : STRING(128);
    VALUE : ANY;
    QOS : BYTE;
    RETAINED : BOOL;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbHandle : INT := -1;
    fbLastReq : BOOL;
    fbPending : BOOL;
    fbSeenOk : DINT;
    fbSeenFail : DINT;
  END_VAR
#include <ModBeeMqtt.h>

// Defined by the MQTT_CLIENT block, which every project has. Declared here
// because every C++ POU in a project lands in ONE translation unit, in
// filename order - so a block whose name sorts before MQTT_CLIENT would not
// otherwise have seen them.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
bool mq_tolerated(MqttResult result);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
int32_t mq_secondsOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME mq_timeOf(int32_t milliseconds);
size_t mq_formatAny(const strucpp::IEC_ANY& any, char* out, size_t capacity);
bool mq_parseAny(const char* text, size_t length, const strucpp::IEC_ANY& any);
bool mq_numberOf(const strucpp::IEC_ANY& any, double* out);
MQTT_QUALITY mq_qualityOf(bool everArrived, bool linkUp, int32_t ageMs,
                          int32_t maxIntervalMs);


void setup()
{
    BUSY = false;
    DONE = false;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbHandle = -1;
    fbLastReq = false;
    fbPending = false;
    fbSeenOk = 0;
    fbSeenFail = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    // One scan wide, set below only on the scan the outcome arrived.
    DONE = false;
    ERROR = false;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        BUSY = false;
        fbPending = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        fbLastReq = (bool)REQ;
        return;
    }

    // Registered once and referred to by number thereafter. Registering the
    // same text twice returns the SAME handle, so an instance called for two
    // topics in a scan costs two slots rather than two per call.
    MqttTopicHandle handle = (MqttTopicHandle)(int16_t)fbHandle;
    const char* topic = TOPIC.c_str();
    // topicOf() is null for a handle the registry does not have, which
    // is what a handle from a PREVIOUS client looks like. Checked
    // rather than assumed: it reads as a small valid index either way.
    const char* held = handle >= 0 ? client->topicOf(handle) : nullptr;
    if (!held || strcmp(held, topic) != 0) {
        handle = client->registerTopic(topic);
        if (handle == MQTT_TOPIC_HANDLE_NONE) {
            BUSY = false;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            fbLastReq = (bool)REQ;
            return;
        }
        fbHandle = (int16_t)handle;
        const MqttTopicState& fresh = client->topicState(handle);
        fbSeenOk = (int32_t)fresh.published;
        fbSeenFail = (int32_t)fresh.failed;
        fbPending = false;
    }

    const MqttTopicState& state = client->topicState(handle);

    // Outcomes are RUNNING TOTALS, so comparing them with what was seen last
    // cannot miss one however slow this block's task is - and two blocks
    // watching the same topic cannot take each other's edges.
    if ((bool)fbPending) {
        if ((int32_t)state.published != (int32_t)fbSeenOk) {
            fbSeenOk = (int32_t)state.published;
            fbPending = false;
            BUSY = false;
            DONE = true;
            STATUS = MQTT_RESULT::MQTT_OK;
        } else if ((int32_t)state.failed != (int32_t)fbSeenFail) {
            fbSeenFail = (int32_t)state.failed;
            fbPending = false;
            BUSY = false;
            ERROR = true;
            STATUS = (MQTT_RESULT)(int32_t)(int)state.lastResult;
        } else {
            BUSY = true;
        }
    }

    const bool rising = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;
    if (!rising) return;

    char payload[512];
    const size_t length = mq_formatAny(VALUE, payload, sizeof payload);
    if (length == 0) {
        // A type the wire cannot carry, or a value too long for the buffer.
        // Refused by name rather than sent wrong.
        BUSY = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const MqttResult asked = client->publishTo(
        handle, (const uint8_t*)payload, length, (uint8_t)QOS, (bool)RETAINED);

    if (!mq_tolerated(asked)) {
        BUSY = false;
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)asked;
        return;
    }

    fbSeenOk = (int32_t)state.published;
    fbSeenFail = (int32_t)state.failed;
    fbPending = true;
    BUSY = true;
    STATUS = MQTT_RESULT::MQTT_QUEUED;
}

END_FUNCTION_BLOCK