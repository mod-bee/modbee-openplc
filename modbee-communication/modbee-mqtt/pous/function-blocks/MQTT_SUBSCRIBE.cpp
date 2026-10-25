(* Keeps a variable up to date from the broker, with a quality that says how much
to believe it. Standing - it subscribes once and maintains itself.

CLIENT            which client. Must be wired.
TOPIC          what to listen to. Wildcards allowed: + for one level, # for
                the rest. "plant/+/pressure" hears every line.
VALUE           the variable to keep up to date. Its declared type is what the
                text is read as; a payload that will not parse is counted on
                MALFORMED and the variable is left alone.
QOS             the most the broker may use to deliver. It may use less.
EXPECT          how often a value is expected. Drives QUALITY. T#0s means nothing
                was promised, so QUALITY is GOOD as soon as anything arrives.
ENABLE          FALSE unsubscribes without losing the topic.

SUBSCRIBED        the subscription is established at the broker.
QUALITY         how much to believe VALUE. See below.
SEEN            a message has arrived at least ONCE since the program
                started. It is what tells an AGE of T#0s apart, and it is
                how a LADDER asks what QUALITY answers - a rung cannot
                compare an enumeration.
AGE             since the last accepted message, or T#0s if there has not been
                one.
RECEIVED        running total of messages accepted.
MALFORMED       running total that would not parse into VALUE's type.
NEW_VALUE       one scan, when VALUE changed.
ERROR           something failed.
STATUS          why. MQTT_OK when fine.

---

QUALITY IS THE PIN THAT MAKES A SUBSCRIBED NUMBER SAFE TO ACT ON, and it is
judged against EXPECT - the interval YOU asked for - rather than some
constant the library picked:

  MQTT_QUALITY_UNKNOWN    nothing has ever arrived. A COMMISSIONING fault:
                          wrong topic, publisher never deployed. Found at a
                          desk with a drawing.
  MQTT_QUALITY_BAD        the link is down, or the value is more than twice
                          overdue. A RUNNING fault. Found in the plant.
  MQTT_QUALITY_UNCERTAIN  overdue, but not by much.
  MQTT_QUALITY_GOOD       arrived inside the interval.

UNKNOWN and BAD are deliberately different. An alarm list that shows both as
"no comms" throws away the one piece of information that says which end of the
site to walk to.

ONE HONEST LIMIT, worth knowing before you rely on this. A connected broker
will happily serve a retained message published by a device that died last
Tuesday, and nothing in MQTT marks it as old. QUALITY knows whether WE are
connected and how long since WE last heard; it cannot know the publisher is
alive. Pair this with MQTT_PRESENCE at the publishing end and the question is
answered properly.

One instance serves many topics - call it twice in a scan with two filters and
each call keeps its own subscription, its own value and its own quality. *)

FUNCTION_BLOCK MQTT_SUBSCRIBE
  VAR_INPUT
    TOPIC : STRING(128);
    VALUE : ANY;
    QOS : BYTE;
    EXPECT : TIME;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    SUBSCRIBED : BOOL;
    QUALITY : MQTT_QUALITY;
    SEEN : BOOL;
    AGE : TIME;
    RECEIVED : DINT;
    MALFORMED : DINT;
    NEW_VALUE : BOOL;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbHandle : INT := -1;
    fbAsked : BOOL;
    fbSeenReceived : DINT;
    fbArrivedAt : DINT;
    fbAgeMs : DINT;
    fbEver : BOOL;
    fbSeenConnects : DINT;
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
    SUBSCRIBED = false;
    QUALITY = MQTT_QUALITY::MQTT_QUALITY_UNKNOWN;
    AGE = mq_timeOf(0);
    SEEN = false;
    fbAgeMs = -1;
    RECEIVED = 0;
    MALFORMED = 0;
    NEW_VALUE = false;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbHandle = -1;
    fbAsked = false;
    fbSeenReceived = 0;
    fbArrivedAt = 0;
    fbEver = false;
    fbSeenConnects = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    NEW_VALUE = false;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        SUBSCRIBED = false;
        QUALITY = mq_qualityOf((bool)fbEver, false, (int32_t)fbAgeMs,
                               mq_millisOf(EXPECT));
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    const mq_time_t now = mq_millis();
    if ((bool)fbEver) {
        fbAgeMs = (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbArrivedAt, now);
        AGE = mq_timeOf((int32_t)fbAgeMs);
    }

    MqttTopicHandle handle = (MqttTopicHandle)(int16_t)fbHandle;
    const char* topic = TOPIC.c_str();
    // topicOf() is null for a handle the registry does not have, which
    // is what a handle from a PREVIOUS client looks like. Checked
    // rather than assumed: it reads as a small valid index either way.
    const char* held = handle >= 0 ? client->topicOf(handle) : nullptr;
    if (!held || strcmp(held, topic) != 0) {
        handle = client->registerTopic(topic);
        if (handle == MQTT_TOPIC_HANDLE_NONE) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            return;
        }
        fbHandle = (int16_t)handle;
        fbAsked = false;
        fbSeenReceived = (int32_t)client->topicState(handle).received;

        // A DIFFERENT TOPIC IS A DIFFERENT SUBSCRIPTION, so nothing about the
        // last one carries over. Without this reset the block would report the
        // previous topic's freshness against the new one - and a topic that
        // has never published anything would come up BAD, which reads as a
        // cable fault, instead of UNKNOWN, which reads as a commissioning
        // error. Those send an engineer to opposite ends of a site.
        fbEver = false;
        fbArrivedAt = 0;
        fbAgeMs = -1;
        AGE = mq_timeOf(0);
        SEEN = false;
        QUALITY = MQTT_QUALITY::MQTT_QUALITY_UNKNOWN;
    }

    if (!(bool)ENABLE) {
        if ((bool)fbAsked) {
            client->unsubscribe(topic);
            fbAsked = false;
        }
        SUBSCRIBED = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    // A subscription is a STANDING INTENT. The library re-issues it after a
    // reconnect where the broker did not keep the session, and re-issues
    // nothing where it did - so asking again here would duplicate it. The
    // connect counter is how this block knows a fresh session happened at all;
    // it is a running total, so no edge can be missed between scans.
    const int32_t connects = (int32_t)client->status().connects;
    if (connects != (int32_t)fbSeenConnects) {
        fbSeenConnects = connects;
        fbAsked = false;
    }

    if (!(bool)fbAsked && client->isConnected()) {
        const MqttResult asked = client->subscribeTo(handle, (uint8_t)QOS);
        if (!mq_tolerated(asked)) {
            ERROR = true;
            STATUS = (MQTT_RESULT)(int32_t)(int)asked;
            return;
        }
        fbAsked = true;
    }
    SUBSCRIBED = (bool)fbAsked && client->isConnected();

    // Take every message that arrived since the last scan, not just the last
    // one - a fast publisher and a slow task must not silently lose values.
    uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
    size_t length = 0;
    while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
        if (mq_parseAny((const char*)buffer, length, VALUE)) {
            RECEIVED = (int32_t)RECEIVED + 1;
            fbArrivedAt = (int32_t)(uint32_t)now;
            fbEver = true;
            fbAgeMs = 0;
            AGE = mq_timeOf(0);
            SEEN = true;
            NEW_VALUE = true;
        } else {
            // Counted rather than hidden. A publisher sending "23,5" to a REAL
            // is a real fault and silence about it is how it survives a year.
            MALFORMED = (int32_t)MALFORMED + 1;
        }
    }

    QUALITY = mq_qualityOf((bool)fbEver, client->isConnected(), (int32_t)fbAgeMs,
                           mq_millisOf(EXPECT));
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK