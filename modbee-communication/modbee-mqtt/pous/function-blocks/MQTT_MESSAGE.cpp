(* The raw text of whatever arrives, for anything that is not a single number.
Standing - it subscribes once and maintains itself.

CLIENT         which client. Must be wired.
TOPIC       what to listen to. Wildcards allowed.
QOS          the most the broker may use to deliver.
ENABLE       FALSE unsubscribes without losing the topic.

PAYLOAD      the message, as text.
LENGTH       how many characters of it. 0 for an empty message, which is a
             real thing in MQTT and usually means "this retained value is
             cancelled".
TRUNCATED    the message was longer than PAYLOAD holds. Reported, never hidden,
             so a partial reading can never be mistaken for a complete one.
RECEIVED     running total of messages delivered.
NEW_MESSAGE  one scan, when a message arrived.
ERROR        something failed.
STATUS       why. MQTT_OK when fine.

---

USE MQTT_SUBSCRIBE FOR A NUMBER. This block is for the rest: a JSON document
you parse yourself, a command word, a state name, a message from a device that
does not know anything about this library.

NEW_MESSAGE is one scan wide, so latch it if a slower task has to see it. Note
that it is the arrival that is reported, not a change - the same value sent
twice is two messages, and for a command channel that is exactly right. "Open"
sent again means open again, and a block that suppressed it would swallow a
repeated instruction.

An EMPTY message is not nothing. Publishing an empty payload with RETAIN is
how MQTT deletes a retained value, so a subscriber seeing LENGTH 0 with
NEW_MESSAGE is being told the old value is withdrawn - which is different from
having heard nothing at all.

TRUNCATED matters on a JSON payload. A document cut in half parses as garbage
or, worse, as something plausible. Check the pin before you trust the text. *)

FUNCTION_BLOCK MQTT_MESSAGE
  VAR_INPUT
    TOPIC : STRING(128);
    QOS : BYTE;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    PAYLOAD : STRING(254);
    LENGTH : INT;
    TRUNCATED : BOOL;
    RECEIVED : DINT;
    NEW_MESSAGE : BOOL;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbHandle : INT := -1;
    fbAsked : BOOL;
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
    PAYLOAD = "";
    LENGTH = 0;
    TRUNCATED = false;
    RECEIVED = 0;
    NEW_MESSAGE = false;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbHandle = -1;
    fbAsked = false;
    fbSeenConnects = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    NEW_MESSAGE = false;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
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
    }

    if (!(bool)ENABLE) {
        if ((bool)fbAsked) {
            client->unsubscribe(topic);
            fbAsked = false;
        }
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

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

    // One message per scan. Unlike MQTT_SUBSCRIBE this block PRESENTS the
    // payload rather than folding it into a variable, so draining a backlog
    // in one scan would show the program only the last of them and quietly
    // lose the rest. One per scan means a slow task falls behind visibly
    // instead of invisibly.
    if (client->topics().hasMessage(handle)) {
        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        if (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            // The registry says whether IT had to cut the message down; this
            // block then says whether the PIN did. Both are truncation and a
            // reader needs to know about either.
            const bool cutByRegistry = client->topicState(handle).truncated;

            // The declared width of the PAYLOAD pin above. One spare byte for
            // the terminator, which the runtime keeps after every string.
            char text[255];
            size_t shown = length;
            if (shown > sizeof text - 1) shown = sizeof text - 1;
            memcpy(text, buffer, shown);
            text[shown] = '\0';

            PAYLOAD = text;
            LENGTH = (int16_t)shown;
            TRUNCATED = cutByRegistry || shown != length;
            RECEIVED = (int32_t)RECEIVED + 1;
            NEW_MESSAGE = true;
        }
    }

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK