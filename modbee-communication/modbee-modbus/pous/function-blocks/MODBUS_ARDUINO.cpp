(* The pins only a board has. Optional, and ignored entirely on the Runtime.

NODE        which node. Must be wired.
PORT        which hardware serial port, 0 for the first.
RX_PIN      receive pin, -1 for the board's own. ESP32 only.
TX_PIN      transmit pin, -1 for the board's own. ESP32 only.
DE_PIN      the RS-485 driver-enable pin, -1 if the board wires it itself.
DE_HOLD  how long to hold the driver after the last byte, where the UART
            cannot drive DE itself (an ESP32 does). T#0s for the default,
            which is two character times.
SSID        the network to join. MODBUS_ARDUINO_WIFI only.
PASSWORD    its password. Up to 63 characters, the most WPA2 allows.
MAC         six hex bytes, e.g. 'DE:AD:BE:EF:FE:ED'. Ethernet only. Empty
            takes a built-in default, which is fine for ONE device on a
            network and a collision the moment there are two.
IP          this node's fixed address, e.g. '192.168.1.60'. REQUIRED on WiFi
            and on Ethernet. Write 'dhcp' to ask a server instead, which is a
            decision rather than an oversight - see below.
GATEWAY     e.g. '192.168.1.1'. Empty derives it from IP, ending .1.
SUBNET      e.g. '255.255.255.0'. Empty uses that.

APPLIED  the settings reached the node.
ERROR    they did not.
STATUS   why. MODBUS_OK when fine.

---

  board( NODE := node, PORT := 2, RX_PIN := 16, TX_PIN := 17, DE_PIN := 4 );

  wifi ( NODE := node, SSID := 'plant', PASSWORD := 'secret',
         IP := '192.168.1.60', GATEWAY := '192.168.1.1' );

Put it in the same program as the node, above or below - the node waits a scan
before opening so that whatever this block sets has been seen.

ON THE RUNTIME YOU WILL NEVER NEED THIS BLOCK. Every pin on it describes
hardware a board has and a Linux runtime does not, which is exactly why they
are not on the node: a Runtime user should not scroll past ten pins that can
never apply to them.

DE_PIN IS THE ONE THAT BITES. A half-duplex RS-485 transceiver has to be
switched to transmit and back again: released too early, the last character is
cut in half and the far end reports a checksum error that points nowhere near
the transceiver; released too late, it talks over the reply. ON AN ESP32 THE
UART DOES IT - its RS-485 mode drives DE for exactly as long as bits leave and
drops it after the last stop bit, and nothing in the scan waits for the frame.
DE_HOLD is the pause before release where the core cannot: leave it at 0 for
two character times.

RX_PIN and TX_PIN are taken only by cores that can remap them, which in
practice means ESP32. Elsewhere the board decides and these are ignored.

---

HOW THE NETWORK ACTUALLY COMES UP, because nothing else is going to do it. An
OpenPLC program has no sketch and no setup() of its own, so MODBUS_NODE brings
the hardware up itself from the pins on this block.

A FIXED ADDRESS IS REQUIRED, ON BOTH. Leave IP empty and the node refuses to
start with "set IP, or 'dhcp' to ask for one". That is deliberate, and there
are two separate reasons:

  ON ETHERNET, DHCP BLOCKS. The Arduino library waits up to sixty seconds for
  a server, and on a 1 ms task that is not a delay - it is a stopped PLC. The
  node bounds it to one second per attempt and retries on its own timer, so it
  works, but it costs a stall every time it fails.

  ON WIFI it does not block, and the reason is the other one: A NODE THAT
  ANSWERS MODBUS HAS TO BE FINDABLE. A SCADA package cannot poll an address
  that moved when the lease expired, and an address that is right until the
  day somebody power-cycles the switch is worse than one that was never right.

Writing IP := 'dhcp' asks for a server-assigned address anyway. That is a
decision, and it reads like one.

WIFI, with MODBUS_ARDUINO_WIFI:

    WiFi.config(IP, GATEWAY, SUBNET)     unless IP is 'dhcp'
    WiFi.begin(SSID, PASSWORD)

  called by the node in that order - WiFi.config() AFTER WiFi.begin() is a
  lease already taken and then argued with. WiFi.begin does NOT block: it
  returns at once and the node reports MODBUS_LINK_DOWN with "joining the
  network" on LAST_ERROR until WiFi.status() says WL_CONNECTED. Joining takes
  a few seconds and the scan keeps running throughout.

ETHERNET, with MODBUS_ARDUINO_ETHERNET:

    Ethernet.begin(MAC, IP, GATEWAY, GATEWAY, SUBNET)   - fixed, and instant
    Ethernet.begin(MAC, 1000, 1000)                     - when IP is 'dhcp'

  The gateway is passed explicitly rather than left to the library's guess, and
  serves as the DNS address too: nothing here resolves a name, so it is never
  asked.

  from the STANDARD ARDUINO ETHERNET LIBRARY, the one you install from the
  Library Manager. That drives a W5100 or W5500 controller on SPI, which is
  what nearly every Ethernet shield and module is. The node then checks
  Ethernet.hardwareStatus() and Ethernet.linkStatus() and tells you which
  failed:

    "no Ethernet controller found on SPI"   the shield is not there, or the
                                            chip select is wrong
    "Ethernet cable unplugged"               the controller is there, the link
                                            is not
    "no address from DHCP yet"               no server answered

  AN ESP32'S BUILT-IN ETHERNET IS NOT THIS. A board with an RMII PHY - LAN8720,
  IP101 and the like - uses the core's own ETH library, with a PHY type, an
  address, MDC and MDIO pins and a clock mode. That is a different library with
  a different API and this block does not drive it. Only SPI controllers
  through the Arduino Ethernet library are supported.

WIFI IS FOUND ON ITS OWN. ETHERNET YOU HAVE TO ASK FOR.

  WiFi.h ships inside the ESP32 core, so it is already on the include path and
  the node finds it. A board without WiFi does not compile that path at all and
  says "this board has no WiFi" if you select it.

  The Arduino Ethernet library is a USER library, and the Arduino builder puts
  one on the include path only when it SEES a plain #include for it. A header
  hidden behind a conditional is invisible to that scanner - so the library can
  be installed and the build still not find it. That is not a guess: with the
  library installed and the include behind __has_include, it came out off.

  So to use MODBUS_ARDUINO_ETHERNET, add MODBUS_ENABLE_ETHERNET to your
  project's build flags. Without it the node reports "define
  MODBUS_ENABLE_ETHERNET to build Ethernet in" rather than failing quietly, and
  no board pays for an Ethernet library it does not have.

MODBUS_NO_WIFI forces WiFi off, for a board that has the header and cannot link
it.

ON AN ESP32-S3 WITH USB CDC ON BOOT, Serial is the USB device and not a UART at
all. The node falls back to Serial0, which is UART0. For a real port use
PORT := 1 or PORT := 2 with RX_PIN and TX_PIN. *)

FUNCTION_BLOCK MODBUS_ARDUINO
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    PORT : BYTE;
    RX_PIN : INT := -1;
    TX_PIN : INT := -1;
    DE_PIN : INT := -1;
    DE_HOLD : LTIME;
    SSID : STRING(48);
    PASSWORD : STRING(63);
    MAC : STRING(32);
    IP : STRING(32);
    GATEWAY : STRING(32);
    SUBNET : STRING(32);
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
  END_VAR
#include <ModBeeModbus.h>

// Defined in MODBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so a block sorting before it declares them.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
int32_t mb_microsOf(const strucpp::IEC_LTIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);

// =============================================================================
// ONE TASK PER NODE
// =============================================================================
//
// OPENPLC RUNS EVERY TASK ON A THREAD OF ITS OWN - on the Runtime, and on a
// board in RTOS mode - and the Modbus library underneath these blocks is
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
// program trades values with them through globals. MODBUS_NODE notes its task
// in fbTask every scan; every other block compares, and in another task does
// nothing and says MODBUS_WRONG_TASK - never races, never waits.
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
strucpp::XWORD_t mb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#elif !defined(ARDUINO)
#include <pthread.h>
strucpp::XWORD_t mb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#else
// One task and nothing else: every block is in it.
strucpp::XWORD_t mb_currentTask() { return 1; }
#endif

bool mb_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == mb_currentTask();
}

// =============================================================================
// AN RS-485 PORT THAT NEVER HOLDS THE SCAN
// =============================================================================
//
// Two waits used to sit in every transmission, both inside the node's scan:
//
//   - write() itself. The core's default is no software transmit buffer, so
//     it blocked until the UART's 128-byte FIFO had room: a 256-byte RTU
//     frame at 9600 baud held the scan about 130 ms.
//   - the driver enable. flush() waited for the last byte to leave the wire,
//     then a hold, then DE dropped: about 290 ms for the same frame.
//
// So the port gets a transmit buffer that holds any frame, and with a DE pin
// the UART's own RS-485 half-duplex mode: the hardware drives DE (on the RTS
// line) for exactly as long as bits are leaving and drops it after the last
// stop bit - never early, which cuts the last character, and never late,
// which talks over the reply. Nothing waits for it.
//
// Answers the DE pin the transport should still drive itself: -1 when the
// UART does it, the pin as given where this core cannot.
#if defined(ARDUINO_ARCH_ESP32)
#define MB_SERIAL_TX_BYTES 1024   // two of the largest frame, ASCII's 513
int mb_serialBegin(HardwareSerial* port, uint32_t baud, uint32_t cfg,
                   int rxPin, int txPin, int dePin) {
    port->end();                         // a buffer is only taken by begin()
    port->setTxBufferSize(MB_SERIAL_TX_BYTES);
    if (rxPin >= 0 && txPin >= 0) {
        port->begin(baud, cfg, (int8_t)rxPin, (int8_t)txPin);
    } else {
        port->begin(baud, cfg);
    }
    if (dePin >= 0 && port->setPins(-1, -1, -1, (int8_t)dePin) &&
        port->setMode(UART_MODE_RS485_HALF_DUPLEX)) {
        return -1;
    }
    return dePin;
}
#endif

void setup()
{
    APPLIED = false;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

void loop()
{
    if (!mb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see MODBUS_ARDUINO
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_WRONG_TASK;
        return;
    }
    // Like MODBUS_CONFIG, this runs BEFORE the link opens and so is not
    // guarded on NODE.READY. It writes the node's own settings and the node
    // reads them when it builds the link.
    NODE.FBPORT = PORT;
    NODE.FBRXPIN = RX_PIN;
    NODE.FBTXPIN = TX_PIN;
    NODE.FBDEPIN = DE_PIN;
    NODE.FBDEHOLDUS = mb_microsOf(DE_HOLD);
    NODE.FBSSID = SSID;
    NODE.FBPASSWORD = PASSWORD;
    NODE.FBMAC = MAC;
    NODE.FBIP = IP;
    NODE.FBGATEWAY = GATEWAY;
    NODE.FBSUBNET = SUBNET;

    APPLIED = true;

#if defined(MODBUS_PLATFORM_HOST)
    // Said plainly rather than silently ignored: every pin here describes
    // hardware the Runtime does not have, and a block that quietly does
    // nothing is how an afternoon goes missing.
    ERROR = true;
    STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
#else
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
#endif
}

END_FUNCTION_BLOCK