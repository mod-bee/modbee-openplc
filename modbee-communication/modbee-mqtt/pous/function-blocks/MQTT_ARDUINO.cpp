(* The things only a board has. Optional, and ignored on the Runtime.

CLIENT       which client. Must be wired.
SSID       the WiFi network to join.
WIFI_PASSWORD   its password. Empty for an open network.
MAC        this board's MAC address, for Ethernet. "DE:AD:BE:EF:00:01" -
          colons, hyphens or nothing between the pairs, whichever the label
          uses. EVERY BOARD ON A SEGMENT NEEDS ITS OWN.
IP         a fixed address for Ethernet, or "dhcp" to ask for one.
GATEWAY    the router, when the address is fixed.
SUBNET     the mask, when the address is fixed.

APPLIED    the settings reached the client.
ERROR      they did not - this is the Runtime, which has none of this hardware.
STATUS     why. MQTT_OK when fine.

---

A FIXED ADDRESS IS WHAT YOU WANT, for two reasons. DHCP blocks - up to sixty
seconds in the Arduino library, which on a 1 ms task is not a delay, it is a
stopped PLC. The client bounds it to one second an attempt and retries on its
own timer, so it works and it costs a stall. And a plant network rarely runs
DHCP at all, so a board that cannot get a lease sits there publishing into
nothing.

Set IP to "dhcp" only when you know there is a server and you can afford the
first attempt.

On the Runtime every pin here describes hardware that is not there, so the
block says so on ERROR rather than quietly doing nothing. A block that
silently ignores what it was told is how an afternoon goes missing. *)

FUNCTION_BLOCK MQTT_ARDUINO
  VAR_INPUT
    SSID : STRING(48);
    WIFI_PASSWORD : STRING(64);
    MAC : STRING(32);
    IP : STRING(32);
    GATEWAY : STRING(32);
    SUBNET : STRING(32);
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

// =============================================================================
// ONE TASK PER CLIENT
// =============================================================================
//
// OPENPLC RUNS EVERY TASK ON A THREAD OF ITS OWN - on the Runtime, and on a
// board in RTOS mode - and the library underneath these blocks is
// single-threaded by design. A client reached through a VAR_IN_OUT pin
// (CLIENT := net.mqtt) is a raw pointer by the time it arrives; no compiler
// lock can follow it, and two threads inside one client lose queue entries
// rather than crash politely.
//
// A LOCK WAS TRIED AND IS THE WRONG ANSWER. A block in the machine's task
// waiting for the network task to finish its scan holds the machine back by
// that scan: on a Node UIO the 20 ms logic task waited 199 ms and OpenPLC
// stopped the PLC. And there is no lock that gives up instead of waiting.
//
// So the rule PLCs have always had for communication blocks: the client and
// every block that uses it run in ONE task - the network task - and the
// machine's program trades values with it through globals, which OpenPLC
// already makes safe between tasks. Each owner (MQTT_CLIENT, MQTT_BROKER,
// SPARKPLUG_NODE, SPARKPLUG_HOST) notes its task in fbTask every scan; every
// block that uses one compares, and in another task does nothing and says
// MQTT_WRONG_TASK - never races, never waits.
//
// fbTask is 0 until the owner's first scan: a block that runs before it, in
// the same scan, is let through, which is how configuration blocks placed
// ahead of their client work.
//
// Defined HERE because this file sorts first: every C++ POU lands in one
// translation unit in filename order, so this is the one place every other
// block can see.
#if defined(MQTT_PLATFORM_HOST)
#include <pthread.h>
strucpp::XWORD_t mq_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#elif defined(ESP_PLATFORM)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
strucpp::XWORD_t mq_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#else
// One task and nothing else: every block is in it.
strucpp::XWORD_t mq_currentTask() { return 1; }
#endif

bool mq_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == mq_currentTask();
}

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
#if defined(MQTT_PLATFORM_HOST)
    // Said plainly rather than silently ignored: every pin here describes
    // hardware the Runtime does not have.
    APPLIED = false;
    ERROR = true;
    STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
#else
    CLIENT.FBSSID = SSID;
    CLIENT.FBWIFIKEY = WIFI_PASSWORD;
    CLIENT.FBMAC = MAC;
    CLIENT.FBIP = IP;
    CLIENT.FBGATEWAY = GATEWAY;
    CLIENT.FBSUBNET = SUBNET;

    APPLIED = true;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
#endif
}

END_FUNCTION_BLOCK