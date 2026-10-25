(* Asks a question and waits for the answer. MQTT 5.0 only.

CLIENT           which client. Must be wired.
REQ            rising edge sends the request.
TOPIC          where the question goes.
VALUE          what to ask. Its declared type is what travels.
REPLY_TOPIC    where the answer comes back. Give each requester its own -
               "plant/plc-01/reply" - so two of them cannot read each other's
               post.
QOS            0, 1 or 2 for the request.
TIMEOUT        how long to wait for an answer. T#0s for five seconds.

BUSY           a level: the question is out and unanswered.
DONE           one scan, when the answer arrived.
REPLY          the answer, as text.
REPLY_LENGTH   how much of it.
ERROR          one scan, when it failed or timed out.
STATUS         why. MQTT_OK when fine.

---

REQUEST AND RESPONSE IS A 5.0 FEATURE and this block says so rather than
pretending. On a 3.1.1 connection it refuses with
MQTT_NOT_SUPPORTED_BY_PROTOCOL - because the Response Topic and Correlation
Data properties do not exist there at all, and sending the request stripped
would mean the responder has no idea where to reply to. A request nobody can
answer is worse than a request refused.

The request carries Response Topic, so a compliant responder knows where to
send the answer without either end agreeing it beforehand, and Correlation
Data, so it can quote the question back.

MATCHING HERE IS BY REPLY_TOPIC, not by correlation. This block reads the next
message that arrives on REPLY_TOPIC as the answer, which is right when each
requester owns its own reply topic and is why the pin documentation says to
give it one. Two blocks sharing a reply topic will read each other's answers,
and no amount of correlation would help a program that cannot tell which
answer it wanted.

TIMEOUT is the pin that keeps a sequence moving. An unanswered request is
otherwise indistinguishable from a slow one, and a rung waiting on BUSY that
never clears is a machine that stops with nothing on the screen to say why.
ERROR with MQTT_KEEPALIVE_TIMEOUT is what a timeout looks like. *)

FUNCTION_BLOCK MQTT_REQUEST
  VAR_INPUT
    REQ : BOOL;
    TOPIC : STRING(128);
    VALUE : ANY;
    REPLY_TOPIC : STRING(128);
    QOS : BYTE;
    TIMEOUT : TIME;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    REPLY : STRING(254);
    REPLY_LENGTH : INT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbReplyHandle : INT := -1;
    fbAsked : BOOL;
    fbLastReq : BOOL;
    fbPending : BOOL;
    fbSentAt : DINT;
    fbCorrelation : DINT;
    fbSeenConnects : DINT;
  END_VAR
#include <ModBeeMqtt.h>

// Defined in MQTT_CLIENT.cpp. Every block lands in one translation unit, but
// the order is the file order, so the declaration is written rather than
// assumed.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

void setup()
{
    BUSY = false;
    DONE = false;
    REPLY = "";
    REPLY_LENGTH = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbReplyHandle = -1;
    fbAsked = false;
    fbLastReq = false;
    fbPending = false;
    fbSentAt = 0;
    fbCorrelation = 0;
    fbSeenConnects = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
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

    if (REPLY_TOPIC.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_TOPIC;
        fbLastReq = (bool)REQ;
        return;
    }

    // The reply topic is subscribed once and kept, so the answer cannot
    // arrive before we are listening for it.
    MqttTopicHandle reply = (MqttTopicHandle)(int16_t)fbReplyHandle;
    const char* replyTopic = REPLY_TOPIC.c_str();
    // topicOf() is null for a handle the registry does not have, which
    // is what a handle from a PREVIOUS client looks like. Checked
    // rather than assumed: it reads as a small valid index either way.
    const char* held = reply >= 0 ? client->topicOf(reply) : nullptr;
    if (!held || strcmp(held, replyTopic) != 0) {
        reply = client->registerTopic(replyTopic);
        if (reply == MQTT_TOPIC_HANDLE_NONE) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            fbLastReq = (bool)REQ;
            return;
        }
        fbReplyHandle = (int16_t)reply;
        fbAsked = false;
    }

    const int32_t connects = (int32_t)client->status().connects;
    if (connects != (int32_t)fbSeenConnects) {
        fbSeenConnects = connects;
        fbAsked = false;
    }
    if (!(bool)fbAsked && client->isConnected()) {
        if (mq_tolerated(client->subscribeTo(reply, (uint8_t)QOS))) {
            fbAsked = true;
        }
    }

    const mq_time_t now = mq_millis();

    if ((bool)fbPending) {
        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        if (client->takeMessage(reply, buffer, sizeof buffer, length)) {
            char text[255];
            size_t shown = length;
            if (shown > sizeof text - 1) shown = sizeof text - 1;
            memcpy(text, buffer, shown);
            text[shown] = '\0';
            REPLY = text;
            REPLY_LENGTH = (int16_t)shown;
            fbPending = false;
            BUSY = false;
            DONE = true;
            STATUS = MQTT_RESULT::MQTT_OK;
            fbLastReq = (bool)REQ;
            return;
        }

        const int32_t ms = mq_millisOf(TIMEOUT);
        const int32_t limit = ms > 0 ? ms : 5000;
        if ((int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSentAt, now) >= limit) {
            // A question nobody answered. Said out loud, because a rung
            // waiting on BUSY that never clears is a machine that stops with
            // nothing on the screen to explain it.
            fbPending = false;
            BUSY = false;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_KEEPALIVE_TIMEOUT;
            fbLastReq = (bool)REQ;
            return;
        }
        BUSY = true;
    }

    const bool rising = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;
    if (!rising) return;

    // Refused rather than sent stripped. Without Response Topic the responder
    // has nowhere to reply to, so a 3.1.1 request is a message into the void.
    if (client->status().version != MqttVersion::V5) {
        BUSY = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_SUPPORTED_BY_PROTOCOL;
        return;
    }

    char payload[512];
    const size_t length = mq_formatAny(VALUE, payload, sizeof payload);
    if (length == 0) {
        BUSY = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // Correlation data the responder quotes back. Counted rather than random:
    // a PLC has no entropy at start-up, and a counter is enough to tell one
    // of this block's own questions from another.
    fbCorrelation = (int32_t)fbCorrelation + 1;
    char correlation[16];
    snprintf(correlation, sizeof correlation, "%ld", (long)(int32_t)fbCorrelation);

    MqttOwnedProperties properties;
    properties.setResponseTopic(replyTopic);
    properties.setCorrelationData(correlation);
    properties.setPayloadFormat(true);   // the payload is UTF-8 text

    const MqttResult asked = client->publish(
        TOPIC.c_str(), (const uint8_t*)payload, length, (uint8_t)QOS, false,
        properties);

    if (!mq_tolerated(asked)) {
        BUSY = false;
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)asked;
        return;
    }

    fbPending = true;
    fbSentAt = (int32_t)(uint32_t)now;
    BUSY = true;
    STATUS = MQTT_RESULT::MQTT_QUEUED;
}

END_FUNCTION_BLOCK