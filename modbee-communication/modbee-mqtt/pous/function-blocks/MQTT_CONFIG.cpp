(* Everything about a connection that is not where it goes. Optional.

CLIENT             which client. Must be wired.
KEEP_ALIVE         how long the broker waits in silence before deciding we are
                   gone. T#0s for sixty seconds. The broker may lower it and
                   say so. MQTT carries this in WHOLE SECONDS, so anything
                   finer is rounded up to the next second.
CLEAN_START        TRUE starts a fresh session every connect. FALSE resumes
                   the one the broker kept, so QoS 1 and 2 messages survive a
                   drop.
KEEP_SESSION       how long the broker keeps that session after we disconnect.
                   T#0s means only while the connection lasts. Whole seconds
                   on the wire, as above. 5.0 only.
USERNAME           user name, if the broker wants one.
PASSWORD           and its password.
MAX_PENDING        how many publishes and subscribes may be waiting on the
                   broker at once. 0 for the library's own figure, 32. Any
                   number: the queue is taken when the client is made, and
                   only memory refuses it - then MQTT_CLIENT's LAST_ERROR says
                   so and how many it holds. Past it the next one is refused
                   with MQTT_QUEUE_FULL rather than dropped.
MAX_MESSAGE_IN     the biggest message this client can RECEIVE, in bytes. 0
                   for 4096. A larger one cannot be assembled, and the
                   connection drops rather than half-reading it.
MAX_MESSAGE_OUT    the biggest it can SEND. 0 for 4096. A larger publish is
                   refused with MQTT_PACKET_TOO_LARGE before it goes near the
                   wire.
RECONNECT          first backoff after a drop. T#0s for one second.
RECONNECT_MAX      ceiling on that backoff. T#0s for a minute.
CONNECT_TIMEOUT    how long to wait for a broker that accepts a socket and
                   then says nothing. T#0s for twenty seconds.
AUTO_RECONNECT     TRUE reconnects by itself. Turn it OFF on a cellular link,
                   where the reconnect is the one call that can stall a scan.

APPLIED         the settings reached the client.
ERROR           they did not.
STATUS          why. MQTT_OK when fine.

---

EVERY PIN HERE HAS A DEFAULT THAT WORKS. This block exists so that a client
which wants none of them is eight pins instead of twenty-six, not because a
client needs it. If you are not changing any of these, do not place it.

Place it anywhere in the rung - above the client or below it. The client waits one
scan before opening its link precisely so that this block has run first
whichever side of it you drew.

CLEAN_START is the one worth thinking about. TRUE is right for a sensor that
publishes the current value and has nothing to catch up on. FALSE is right for
anything that must not lose a message across a dropped link - a totaliser, a
command channel, an alarm - and it costs the broker memory per client, which
is why it is not the default.

AUTO_RECONNECT is the other. On WiFi or wired the reconnect is milliseconds
and you want it on. On cellular it is SECONDS, because the AT commands
underneath it are, and a scan cycle has nowhere to put that - so turn it off
and reconnect from your own logic where you can afford it.

THE TWO SIZE PINS ANSWER ONE SYMPTOM: a message plainly being published that
plainly never arrives. The default of 4096 bytes suits readings and setpoints
and is too small for a JSON document of any size. Raise MAX_MESSAGE_IN on the
subscribing end and MAX_MESSAGE_OUT on the publishing one - and remember they
cost RAM per client whether or not a big message ever comes.

RETRY_REJECTED_CREDENTIAL is OFF, and leaving it off is almost always right.
A dropped link is worth retrying because the link may come back; a password
the broker said no to will not become correct by itself, and sending it again
every second is how a device gets itself banned - by address, on some brokers,
which takes the whole site off with it. With this off, a rejected credential
sets ERROR on MQTT_CLIENT with the broker's own words in LAST_ERROR and stops.

Turn it on only where the credential is expected to become valid without the
program restarting: a broker whose access list loads after it starts
listening, or a token something else in the same program refreshes.

MAX_PENDING is a different kind of limit: not how big, but how many at once.
It only matters at QoS 1 and 2, where a publish stays outstanding until the
broker acknowledges it. A program firing faster than a slow link can drain
gets MQTT_QUEUE_FULL, which is the honest answer - the alternative is an
unbounded queue and a device that runs out of memory at three in the morning. *)

FUNCTION_BLOCK MQTT_CONFIG
  VAR_INPUT
    KEEP_ALIVE : TIME;
    CLEAN_START : BOOL := TRUE;
    KEEP_SESSION : TIME;
    USERNAME : STRING(64);
    PASSWORD : STRING(64);
    MAX_PENDING : DINT;
    MAX_MESSAGE_IN : DINT;
    MAX_MESSAGE_OUT : DINT;
    RECONNECT : TIME;
    RECONNECT_MAX : TIME;
    CONNECT_TIMEOUT : TIME;
    AUTO_RECONNECT : BOOL := TRUE;
    RETRY_REJECTED_CREDENTIAL : BOOL := FALSE;
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
    // NOT guarded on CLIENT.LINK_UP, unlike every other block that takes a client.
    // This one has to run BEFORE the link opens - that is its whole purpose -
    // so it writes into the client's own settings and lets the client use them
    // when it builds the connection.
    CLIENT.FBKEEPALIVE = mq_secondsOf(KEEP_ALIVE);
    CLIENT.FBCLEANSTART = CLEAN_START;
    CLIENT.FBSESSIONEXPIRY = mq_secondsOf(KEEP_SESSION);
    CLIENT.FBUSER = USERNAME;
    CLIENT.FBPASSWORD = PASSWORD;
    CLIENT.FBQUEUECAPACITY = MAX_PENDING;
    CLIENT.FBRXBUFFER = MAX_MESSAGE_IN;
    CLIENT.FBTXBUFFER = MAX_MESSAGE_OUT;
    CLIENT.FBRECONNECTMS = mq_millisOf(RECONNECT);
    CLIENT.FBRECONNECTMAXMS = mq_millisOf(RECONNECT_MAX);
    CLIENT.FBCONNECTTIMEOUTMS = mq_millisOf(CONNECT_TIMEOUT);
    CLIENT.FBAUTORECONNECT = AUTO_RECONNECT;
    CLIENT.FBRETRYREJECTED = RETRY_REJECTED_CREDENTIAL;

    APPLIED = true;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK