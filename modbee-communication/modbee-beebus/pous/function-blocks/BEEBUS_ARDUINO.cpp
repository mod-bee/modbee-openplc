(* The pins only a board has. Optional, and ignored entirely on the Runtime.

NODE       which node. Must be wired.
PORT       which hardware serial port, 0 for the first.
RX_PIN     receive pin, -1 for the board's own. ESP32 only.
TX_PIN     transmit pin, -1 for the board's own. ESP32 only.
WIFI_SSID  the network to join. BEEBUS_NODE_ARDUINO_WIFI only.
PASSWORD   its password. Up to 63 characters, the most WPA2 allows.
MAC        six hex bytes, e.g. 'DE:AD:BE:EF:FE:ED'. Ethernet only. Empty takes
           a built-in default, which is fine for ONE device on a network and a
           collision the moment there are two.
IP         a fixed address, e.g. '192.168.1.60'. Empty asks DHCP, which blocks
           while it waits, so prefer a fixed address.

APPLIED  the settings reached the node.
ERROR    they did not.
STATUS   why. BEEBUS_OK when fine.

---

  board( NODE := node, PORT := 1, RX_PIN := 18, TX_PIN := 17 );

  wifi ( NODE := node, WIFI_SSID := 'plant', PASSWORD := 'secret' );

Put it in the same program as the node, above or below — the node waits a scan
before opening, so whatever this block sets has been seen by the time the link
is built.

ON THE RUNTIME YOU WILL NEVER NEED THIS BLOCK. Every pin on it describes
hardware a board has and a Linux runtime does not, which is exactly why they
are not on the node: a Runtime user should not scroll past seven pins that can
never apply to them.

RX_PIN and TX_PIN are taken only by cores that can remap them, which in
practice means ESP32. Elsewhere the board decides and these are ignored.

ETHERNET IS OPT-IN. Add BEEBUS_ENABLE_ETHERNET to the project's build flags and
install the Arduino Ethernet library, or the node reports it on LAST_ERROR. *)

FUNCTION_BLOCK BEEBUS_ARDUINO
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    PORT : BYTE;
    RX_PIN : INT := -1;
    TX_PIN : INT := -1;
    WIFI_SSID : STRING(32);
    PASSWORD : STRING(63);
    MAC : STRING(32);
    IP : STRING(32);
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
  END_VAR
#include <BeeBusAPI.h>

// =============================================================================
// ONE TASK PER NODE
// =============================================================================
//
// OPENPLC RUNS EVERY TASK ON A THREAD OF ITS OWN - on the Runtime, and on a
// board in RTOS mode - and the BeeBus library underneath these blocks is
// single-threaded by design. A node reached through a VAR_IN_OUT pin is a raw
// pointer by the time it arrives: a block in another task would be inside the
// node while the node's own scan is - one thread appending to its queue while
// the other walks it.
//
// A LOCK IS THE WRONG ANSWER: a block in the machine's task waiting for the
// node's scan holds the machine back by that scan, and OpenPLC stops a PLC
// whose task overruns ten periods (measured with the MQTT library on a Node
// UIO: 199 ms). So the rule PLCs have always had for communication blocks:
// the node and every block given it run in ONE task, and the machine's
// program trades values with them through globals. BEEBUS_NODE notes its task
// in fbTask every scan; every other block compares, and in another task does
// nothing and says BEEBUS_WRONG_TASK - never races, never waits.
//
// fbTask is 0 until the node's first scan: a block that runs before it, in
// the same scan, is let through, which is how configuration blocks placed
// ahead of their node work.
//
// Defined HERE because this file sorts first among this library's blocks, and
// every C++ POU lands in one translation unit in filename order.
#if defined(ESP_PLATFORM)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
strucpp::XWORD_t bb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#elif !defined(ARDUINO)
#include <pthread.h>
strucpp::XWORD_t bb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#else
// One task and nothing else: every block is in it.
strucpp::XWORD_t bb_currentTask() { return 1; }
#endif

bool bb_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == bb_currentTask();
}

void setup()
{
  APPLIED = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
}

void loop()
{
    if (!bb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see BEEBUS_ARDUINO
        ERROR = true;
        STATUS = BEEBUS_RESULT::BEEBUS_WRONG_TASK;
        return;
    }
  // Runs BEFORE the link opens, so it is not guarded on NODE.READY. It writes
  // the node's own settings and the node reads them when it builds the link.
  NODE.FBPORT = PORT;
  NODE.FBRXPIN = RX_PIN;
  NODE.FBTXPIN = TX_PIN;
  NODE.FBWIFISSID = WIFI_SSID;
  NODE.FBPASSWORD = PASSWORD;
  NODE.FBMAC = MAC;
  NODE.FBIP = IP;

  APPLIED = true;

#if defined(BEEBUS_PLATFORM_HOST)
  // Said plainly rather than silently ignored: every pin here describes
  // hardware the Runtime does not have, and a block that quietly does nothing
  // is how an afternoon goes missing.
  ERROR = true;
  STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
#else
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
#endif
}

END_FUNCTION_BLOCK