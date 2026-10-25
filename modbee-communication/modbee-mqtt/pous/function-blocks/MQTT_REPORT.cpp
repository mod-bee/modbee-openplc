(* Publishes a variable. MODE says what makes it go. Standing - one instance
serves many topics.

CLIENT          which client. Must be wired.
TOPIC           where it goes.
VALUE           the variable to watch. Its declared type is what travels.
MODE            what triggers a message:
                  MQTT_ON_CHANGE    when the value moves past DEADBAND, and
                                    anyway every PERIOD so silence stays
                                    meaningful.
                  MQTT_ON_INTERVAL  every PERIOD, moved or not.
                  MQTT_ON_REQUEST   when REQ goes TRUE, and never otherwise.
                MQTT_CHANGED_EVERY is SPARKPLUG_STRUCT's and is refused
                here (MQTT_INVALID_ARGUMENT).
DEADBAND        how far it must move before that is worth a message. 0 sends
                on any change at all. MQTT_ON_CHANGE only.
PERIOD          MQTT_ON_CHANGE: send anyway after this long, even unchanged.
                T#0s never does, which is the mistake worth avoiding - see
                below. MQTT_ON_INTERVAL: how often. Required there.
REQ             MQTT_ON_REQUEST: a rising edge sends one. Ignored otherwise.
QOS             0, 1 or 2.
RETAINED        TRUE keeps the last value on the broker.
ENABLE          FALSE stops reporting without losing the topic.

SENT            running total of messages sent.
AGE             how long since the last one. T#0s until there has been one,
                which SENT = 0 distinguishes from one sent this scan.
ERROR           something failed.
STATUS          why. MQTT_OK when fine.

---

THIS IS THE BLOCK MOST PROGRAMS WANT, in its MQTT_ON_CHANGE default.

DEADBAND stops a noisy analogue input filling the broker. A level transmitter
that jitters by 0.02 m is not telling you anything, and publishing it four
times a second for a year is thirty million messages nobody reads. Set the
deadband to the smallest change an operator would act on.

PERIOD is the other half, and leaving it at T#0s is the mistake worth
avoiding. A value that never moves publishes nothing, and a consumer cannot
tell that from a device that has died - it just sees silence. Set it to a
minute or two and the silence becomes meaningful: no message inside the
interval is a fault, not a steady reading. That is what lets the subscribing
end run a quality on it, and it is what the subscriber's EXPECT is compared
against.

DEADBAND IS MEASURED ON THE NUMBER, so it has no meaning for a STRING - there
any change at all is a change, and PERIOD still applies. A BOOL counts as a
number, 1.0 or 0.0, so a DEADBAND above 1.0 would freeze one. Leave it at 0
for anything that is not an analogue.

MQTT_ON_INTERVAL WITH NO PERIOD IS REFUSED, not turned into "every scan".
STATUS says MQTT_INVALID_ARGUMENT and nothing is published, because a block
publishing at the task rate is how a broker falls over.

MQTT_ON_REQUEST PUBLISHES NOTHING UNTIL ASKED - no first value, no heartbeat.
Where an acknowledged send is wanted, with BUSY and DONE to sequence against,
that is MQTT_PUBLISH rather than this.

One instance serves many topics. Call it twice in a scan with two topics and
you get two reports, each with its own deadband and its own last value. *)

FUNCTION_BLOCK MQTT_REPORT
  VAR_INPUT
    TOPIC : STRING(128);
    VALUE : ANY;
    MODE : MQTT_TRIGGER;
    DEADBAND : LREAL;
    PERIOD : TIME;
    REQ : BOOL;
    QOS : BYTE;
    RETAINED : BOOL;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    SENT : DINT;
    AGE : TIME;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbHandle : INT := -1;
    fbHasLast : BOOL;
    fbLast : LREAL;
    fbLastText : STRING(64);
    fbSentAt : DINT;
    fbEverSent : BOOL;
    fbLastReq : BOOL;
    fbAgeMs : DINT;
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
    SENT = 0;
    AGE = mq_timeOf(0);
    fbAgeMs = -1;
    fbLastReq = false;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbHandle = -1;
    fbHasLast = false;
    fbLast = 0.0;
    fbLastText = "";
    fbSentAt = 0;
    fbEverSent = false;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    const mq_time_t now = mq_millis();
    if ((bool)fbEverSent) {
        fbAgeMs = (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSentAt, now);
        AGE = mq_timeOf((int32_t)fbAgeMs);
    }

    // The edge is taken every scan, ENABLE or not: a REQ raised while the
    // block was disabled must not fire the moment it is enabled again.
    const bool asked = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;

    if (!(bool)ENABLE) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
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
        // A different topic is a different report, so nothing is carried over
        // from the last one - the first value on a new topic always goes.
        fbHasLast = false;
    }

    char payload[512];
    const size_t length = mq_formatAny(VALUE, payload, sizeof payload);
    if (length == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const int32_t intervalMs = mq_millisOf(PERIOD);
    bool due = false;

    // SPARKPLUG_STRUCT's mode: refused, never taken for MQTT_ON_CHANGE.
    if (MODE == MQTT_TRIGGER::MQTT_CHANGED_EVERY) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    if (MODE == MQTT_TRIGGER::MQTT_ON_REQUEST) {
        // Nothing until asked. No first value, no heartbeat - a block that
        // published on its own in request mode would surprise a sequence.
        due = asked;

    } else if (MODE == MQTT_TRIGGER::MQTT_ON_INTERVAL) {
        // An interval of nothing is a misconfiguration, not "as fast as the
        // task runs". Refused rather than obeyed: publishing at the task rate
        // is how a broker falls over.
        if (intervalMs <= 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
        due = !(bool)fbEverSent
              || (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSentAt, now)
                 >= intervalMs;

    } else {
        due = !(bool)fbHasLast;

        double number = 0.0;
        const bool numeric = mq_numberOf(VALUE, &number);
        if (!due) {
            if (numeric) {
                double moved = number - (double)fbLast;
                if (moved < 0) moved = -moved;
                due = moved >= (double)DEADBAND;
            } else {
                // No "how much has it moved" for text, so any difference counts.
                due = strcmp(payload, fbLastText.c_str()) != 0;
            }
        }

        // The heartbeat. Without it a value that never moves is
        // indistinguishable from a device that has died.
        if (!due && intervalMs > 0 && (bool)fbEverSent) {
            due = (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSentAt, now)
                  >= intervalMs;
        }
    }

    if (!due) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    double shadow = 0.0;
    const MqttResult sent = client->publishTo(
        handle, (const uint8_t*)payload, length, (uint8_t)QOS, (bool)RETAINED);

    if (!mq_tolerated(sent)) {
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)sent;
        return;
    }

    fbHasLast = true;
    mq_numberOf(VALUE, &shadow);
    fbLast = shadow;
    fbLastText = payload;
    fbSentAt = (int32_t)(uint32_t)now;
    fbEverSent = true;
    fbAgeMs = 0;
    AGE = mq_timeOf(0);
    SENT = (int32_t)SENT + 1;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK