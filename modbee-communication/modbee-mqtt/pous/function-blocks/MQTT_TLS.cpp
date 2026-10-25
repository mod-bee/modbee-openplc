(* What to trust at the other end. Optional, and only read when the client's
SECURITY pin asks for TLS.

CLIENT         which client. Must be wired.
CA_FILE      path to the certificate authority to trust, in PEM. Runtime only -
             a board has no filesystem to read it from.
CERT_FILE    this device's own certificate, for mutual TLS. Runtime only.
KEY_FILE     and its private key. Runtime only.

APPLIED      the settings reached the client.
ERROR        they did not.
STATUS       why. MQTT_OK when fine.

---

Leave every pin empty and TLS still works on the Runtime: it falls back to the
system certificate store, which is what a plant server with a real certificate
needs.

THERE IS NO PIN FOR AN INLINE CERTIFICATE, and there cannot be. An IEC STRING
is limited to 254 characters and the shortest real CA certificate in PEM is
about eight times that, so a pin holding one would be a pin that never worked.
A BOARD GETS ITS CA FROM A DEFINE instead, MQTT_CA_CERT_PEM, set in the board
package's compiler flags - an OpenPLC project has no build flags of its own:

  -DMQTT_CA_CERT_PEM='"-----BEGIN CERTIFICATE-----\n...."'

which is also where a certificate belongs: it is part of the firmware, not
part of the program somebody edits on a Tuesday.

FOR THE SITE'S OWN BROKER NONE OF THIS IS NEEDED. Use MQTT_TLS_PINNED on the
client with TRUST_NEW and a login: the broker's key is learned once and
enforced after, with nothing to install or define. That is the simple default
for a board; a CA is for a broker somebody signed for. MQTT_TLS_INSECURE is a
bench setting and not a plant one.

A BOARD'S OWN CERTIFICATE, for mutual TLS, comes the same way, from the board
package - both or neither, and a build that names one without the other does
not compile:

  -DMQTT_CLIENT_CERT_PEM='"-----BEGIN CERTIFICATE-----\n...."'
  -DMQTT_CLIENT_KEY_PEM='"-----BEGIN PRIVATE KEY-----\n...."'

On an ESP32 all of this applies to Wi-Fi, Ethernet and cellular alike: the TLS
runs on the controller, over a plain connection on each.

THERE IS NO "IGNORE CERTIFICATES" PIN HERE. That decision lives on the client's
SECURITY pin as MQTT_TLS_INSECURE, where it is visible in the block that makes
the connection rather than buried in an optional one - and where nobody can
set it without meaning to.

Mutual TLS wants both CERT_FILE and KEY_FILE; one without the other is
refused, because a certificate with no key cannot be presented and silently
connecting without it would be the opposite of what was asked. *)

FUNCTION_BLOCK MQTT_TLS
  VAR_INPUT
    CA_FILE : STRING(128);
    CERT_FILE : STRING(128);
    KEY_FILE : STRING(128);
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
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
    APPLIED = false;
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
    // One without the other cannot be presented, and connecting anyway would
    // be the opposite of what was asked for.
    if ((CERT_FILE.length() > 0) != (KEY_FILE.length() > 0)) {
        APPLIED = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    CLIENT.FBCAFILE = CA_FILE;
    CLIENT.FBCERTFILE = CERT_FILE;
    CLIENT.FBKEYFILE = KEY_FILE;

    APPLIED = true;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK