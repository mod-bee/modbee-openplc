(* How this connection is doing. Every number is measured; nothing here is a
setting.

CLIENT            which client. Must be wired.

CONNECTED       the broker has acknowledged us.
STATE           where the connection is up to.
VERSION         5 or 4 - which protocol version is actually in force, which
                after a fallback is not always the one asked for.
CONNECTS        times this client has connected. Includes the first.
DISCONNECTS     times it has come down.
RECONNECTS      times it went and came back on its own.
PUBLISHED       messages this client sent that concluded successfully.
RECEIVED        messages delivered to it.
PUBLISH_FAILURES  messages that did not make it.
PROTOCOL_ERRORS the broker said something the standard does not allow. Not
                zero means one of the two ends has a bug; some brokers
                are known to.
PENDING          operations accepted and not yet concluded.
REASON_CODE     the last reason code the broker sent with any packet - a
                CONNACK, a SUBACK, a DISCONNECT. Read it WITH VERSION: at 3.1.1
                it is that version's return code, a different numbering (4
                there is a bad password; 4 at 5.0 is something else entirely).
                For why the link will not come up, MQTT_CLIENT's LAST_ERROR
                says it in words.
ERROR           no such client.
STATUS          why. MQTT_OK when fine.

---

THIS BLOCK HAS NO INPUTS. It reports and changes nothing, which is why it is
safe to drop onto a diagnostic page anywhere.

The numbers worth putting on a screen are CONNECTS and RECONNECTS. A link that
works but reconnects nightly is a completely different problem from one that
has never worked, and nothing else on this list tells them apart. A RECONNECTS
that climbs at the same time every day is a lease expiring or a scheduled job
on the broker; one that climbs with the weather is a radio.

PUBLISH_FAILURES against PUBLISHED is the other pair. A handful of failures
during a reconnect is ordinary. A ratio that stays steady means something is
refusing messages rather than losing them - check STATUS on the block that
sends them, which names the reason.

VERSION is the pin people forget. Ask for MQTT_V5_THEN_V311 and you may be
speaking either; a 5.0-only feature quietly unavailable on a 3.1.1 connection
is much easier to understand when this pin says 4. *)

FUNCTION_BLOCK MQTT_STATUS
  VAR_OUTPUT
    CONNECTED : BOOL;
    STATE : MQTT_STATE;
    VERSION : BYTE;
    CONNECTS : DINT;
    DISCONNECTS : DINT;
    RECONNECTS : DINT;
    PUBLISHED : DINT;
    RECEIVED : DINT;
    PUBLISH_FAILURES : DINT;
    PROTOCOL_ERRORS : DINT;
    PENDING : DINT;
    REASON_CODE : BYTE;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
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
    CONNECTED = false;
    STATE = MQTT_STATE::MQTT_IDLE;
    VERSION = 0;
    CONNECTS = 0;
    DISCONNECTS = 0;
    RECONNECTS = 0;
    PUBLISHED = 0;
    RECEIVED = 0;
    PUBLISH_FAILURES = 0;
    PROTOCOL_ERRORS = 0;
    PENDING = 0;
    REASON_CODE = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
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
        CONNECTED = false;
        STATE = MQTT_STATE::MQTT_IDLE;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    const MqttStatus& s = client->status();
    CONNECTED = client->isConnected();
    STATE = (MQTT_STATE)(int32_t)(int)s.state;
    VERSION = (uint8_t)s.version;
    CONNECTS = (int32_t)s.connects;
    DISCONNECTS = (int32_t)s.disconnects;
    RECONNECTS = (int32_t)s.reconnects;
    PUBLISHED = (int32_t)s.published;
    RECEIVED = (int32_t)s.received;
    PUBLISH_FAILURES = (int32_t)s.publishFailures;
    PROTOCOL_ERRORS = (int32_t)s.protocolErrors;
    PENDING = (int32_t)client->operations().pending();
    REASON_CODE = s.lastReasonCode;

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK