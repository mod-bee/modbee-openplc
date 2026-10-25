(* Says this device is here, and arranges for the broker to say when it is not.
Optional, and the most useful optional block there is.

CLIENT        which client. Must be wired.
TOPIC       where to say it. "plant/tank-01/status" is the shape people use.
ONLINE      what to publish when connected. Empty for "online".
OFFLINE     what the broker publishes on our behalf when we vanish. Empty for
            "offline".
RETAINED      TRUE keeps both on the broker, so anything subscribing later is
            told immediately rather than waiting for the next change. This is
            almost always what you want.
QOS         0, 1 or 2 for both messages.
DELAY       how long the broker waits before publishing OFFLINE. T#0s publishes
            it at once. 5.0 only - at 3.1.1 the client refuses to connect rather
            than drop it, because a Will delay silently lost turns a flapping
            link into a stream of false alarms.

SENT   running total of ONLINE messages sent. A number that climbs is a
            link that keeps dropping and coming back.
ERROR       something failed.
STATUS      why. MQTT_OK when fine.

---

THIS IS HOW A CONSUMER TELLS "OFFLINE" FROM "HAS NOT SENT YET", and in
plain MQTT there is no other way. Subscribe to a topic, hear nothing, and you
cannot tell whether the device is dead or simply has nothing to say. The pair
of messages here answers it: the Will is registered with the broker at connect
time and published BY THE BROKER when the connection dies without a goodbye -
a power cut, a pulled cable, a modem that lost coverage.

The ONLINE message goes out on the session-established hook, which runs before
anything else queued - so a subscriber sees this device come up before it sees
the device's first reading, in that order, every time.

DELAY is the pin that stops a marginal link crying wolf. A radio that drops
for eight seconds and comes back has not gone offline in any sense an operator
cares about; set DELAY to T#30s and the broker waits before announcing it,
and a reconnect inside that window cancels the announcement entirely.

NOT WITH SPARKPLUG. A connection carries one Will, and a SPARKPLUG_NODE or
SPARKPLUG_HOST on the same client owns it: its birth and death certificates are
the presence. This block then says MQTT_REFUSED and publishes nothing. *)

FUNCTION_BLOCK MQTT_PRESENCE
  VAR_INPUT
    TOPIC : STRING(128);
    ONLINE : STRING(128);
    OFFLINE : STRING(128);
    RETAINED : BOOL := TRUE;
    QOS : BYTE;
    DELAY : TIME;
  END_VAR
  VAR_OUTPUT
    SENT : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbArmed : BOOL;
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
    SENT = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbArmed = false;
    fbSeenConnects = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    if (TOPIC.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_TOPIC;
        return;
    }

    // The Will has to be registered BEFORE the connection is built - it
    // travels inside CONNECT - so this half runs whether or not the client is
    // ready, exactly like MQTT_CONFIG.
    if (!(bool)fbArmed) {
        CLIENT.FBWILLTOPIC = TOPIC;
        if (OFFLINE.length() > 0) {
            CLIENT.FBWILLPAYLOAD = OFFLINE;
        } else {
            CLIENT.FBWILLPAYLOAD = "offline";
        }
        CLIENT.FBWILLQOS = QOS;
        CLIENT.FBWILLRETAIN = RETAINED;
        CLIENT.FBWILLDELAYS = mq_secondsOf(DELAY);
        fbArmed = true;
    }

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);

    // A CONNECT carries one Will. A SPARKPLUG_NODE or SPARKPLUG_HOST on this
    // client owns it - its death certificate IS the presence - so this block
    // would publish an "online" whose "offline" never comes. Said, not done.
    if (client && client->willOwner() != nullptr) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_REFUSED;
        return;
    }
    if (!client || !(bool)CLIENT.LINK_UP) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    // One birth per connection, and the counter is what says which. connects
    // is a RUNNING TOTAL, so comparing it with what was seen last cannot miss
    // an edge however slow this block's task is, and two blocks watching the
    // same client cannot take each other's.
    const int32_t connects = (int32_t)client->status().connects;
    if (client->isConnected() && connects != (int32_t)fbSeenConnects) {
        const char* text = ONLINE.length() > 0 ? ONLINE.c_str() : "online";
        const MqttResult sent =
            client->publish(TOPIC.c_str(), text, (uint8_t)QOS, (bool)RETAINED);
        if (mq_tolerated(sent)) {
            fbSeenConnects = connects;
            SENT = (int32_t)SENT + 1;
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
        } else {
            ERROR = true;
            STATUS = (MQTT_RESULT)(int32_t)(int)sent;
        }
        return;
    }

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK