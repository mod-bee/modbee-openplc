(* Puts TCP clients in front of a serial segment, routed by unit id.

      SCADA -+
        HMI -+- TCP --> [ bridge ] --RS-485--> unit 1  unit 2  unit 17 ...
     laptop -+

SERIAL_DEVICE  the serial device behind, e.g. /dev/ttyUSB0.
SERIAL_BAUD    0 for 19200, the Modbus default.
SERIAL_PARITY  MODBUS_PARITY_EVEN is the Modbus default.
             MODBUS_PARITY_EVEN, MODBUS_PARITY_ODD, MODBUS_PARITY_NONE,
             MODBUS_PARITY_NONE_8N1
PORT         which hardware serial port, 0 for the first. Boards only.
RX_PIN       receive pin, -1 for the board's own. ESP32 only.
TX_PIN       transmit pin, -1 for the board's own. ESP32 only.
DE_PIN       the RS-485 driver-enable pin, -1 if the board wires it itself.
DE_HOLD   how long to hold the driver after the last byte, where the UART
             cannot drive DE itself (an ESP32 does). T#0s for the default.
TCP_PORT     the port clients connect to. 0 for 502.
FIRST_UNIT   the lowest unit id out on the serial segment, 1..247.
LAST_UNIT    the highest. Equal to FIRST_UNIT routes one device.
MAX_CLIENTS  how many clients to hold at once. 0 for the default: eight on
             the Runtime, two on a board. No ceiling of its own - a board that
             cannot find room for that many says so on LAST_ERROR instead of
             holding fewer.
MAX_PENDING  how many transactions may be outstanding on the serial bus at
             once. 0 for the default of 8.
PASS_OTHERS  forward anything not routed, instead of answering "no such path".
             For a bus whose devices you do not know in advance.
CONNECT      run the bridge. TRUE unless you say otherwise.

READY        both ends are open.
CLIENTS      clients connected.
FORWARDED    requests sent to the serial segment.
NO_PATH      requests refused because we have no route - OUR problem.
NO_DEVICE    requests refused because the device did not answer - ITS problem.
FRAMING_REASON  how the serial segment finds frames, and why.
ERROR        it did not open, or has since failed.
STATUS       why. MODBUS_OK when fine.
             MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
             MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
             MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
             MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
             MODBUS_ACKNOWLEDGED, MODBUS_BUSY,
             MODBUS_GATEWAY_PATH_UNAVAILABLE, MODBUS_GATEWAY_TARGET_FAILED,
             MODBUS_LINK_DOWN, MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR
LAST_ERROR   the operating system's own words.

---

  MODBUS_BRIDGE( SERIAL_DEVICE := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
                 TCP_PORT := 502, FIRST_UNIT := 1, LAST_UNIT := 32 );

The oldest and most useful box in the Modbus world, and the reason it exists
is worth stating: several clients on the network side share one serial bus,
which can only carry one conversation at a time. The bridge is what turns the
second into the first. Without it, two SCADA packages polling one RS-485
segment talk over each other.

THIS BLOCK STANDS ALONE. It has no NODE pin and takes no node, because a
bridge is not a client or a server - it is both ends of a wire. Put it in the
network task a MODBUS_NODE would go in; it services both ends once per call.

IT DOES NOT DECODE WHAT IT CARRIES. A device behind it may speak function
codes this library has never heard of, and those pass through byte for byte.

NO_PATH AND NO_DEVICE ARE THE TWO NUMBERS TO PUT ON A SCREEN, and they are
worth separate alarms, because a plain timeout cannot tell an engineer which
end of the plant to walk to:

  NO_PATH    exception 0x0A. A client asked for a unit id we do not route, or
             there was no room to start another transaction. A problem with
             US - a routing range typed wrong, or MAX_PENDING too small.
  NO_DEVICE  exception 0x0B. The route exists and the device did not answer.
             A problem with THE DEVICE - it is off, unplugged, or set to a
             different address.

PASS_OTHERS is off by default, and it is worth knowing why. With it off, a
client asking for a unit id you did not route is told "no such path"
immediately and honestly. With it on, the same typing mistake becomes a
request sent to a device that is not there and a timeout several hundred
milliseconds later - during which the whole serial segment is blocked. Turn it
on only when you genuinely do not know what is out on the bus. *)

FUNCTION_BLOCK MODBUS_BRIDGE
  VAR_INPUT
    SERIAL_DEVICE : STRING(48);
    SERIAL_BAUD : DINT;
    SERIAL_PARITY : MODBUS_PARITY;
    PORT : BYTE;
    RX_PIN : INT := -1;
    TX_PIN : INT := -1;
    DE_PIN : INT := -1;
    DE_HOLD : LTIME;
    TCP_PORT : UINT;
    FIRST_UNIT : BYTE;
    LAST_UNIT : BYTE;
    MAX_CLIENTS : BYTE;
    MAX_PENDING : BYTE;
    PASS_OTHERS : BOOL;
    CONNECT : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    READY : BOOL;
    CLIENTS : INT;
    FORWARDED : DINT;
    NO_PATH : DINT;
    NO_DEVICE : DINT;
    FRAMING_REASON : STRING(160);
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR
    fbApi : __XWORD;
    fbTried : BOOL;
    fbRetryAt : DINT;
  END_VAR
#include <ModBeeModbus.h>

// Defined in MODBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so a block sorting before it declares them.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
int32_t mb_microsOf(const strucpp::IEC_LTIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);

#include <new>

#if defined(MODBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// A bridge's TCP front needs a network, and on Arduino the only one this block
// binds to is WiFi - the Arduino network classes share no base, so the library
// binds to them by template and the template has to name a concrete class.
//
// Detected rather than assumed, for the same reason MODBUS_NODE detects it:
// WiFi.h ships inside the ESP32 core so __has_include finds it, while a board
// without it would otherwise fail to compile a block the project may not even
// use. Without a network the serial half still works and the TCP half reports
// on LAST_ERROR.
#if !defined(MODBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define MB_HAS_WIFI 1
#include <WiFi.h>
#endif
#endif
#endif

// The line settings SERIAL_PARITY asks for. Modbus RTU is 8E1 by
// specification; a bridge that opened 8N1 instead would answer every TCP
// client with a timeout and leave nothing on the serial side to explain it.
#if defined(MODBUS_PLATFORM_ARDUINO)
static uint32_t mbBridgeSerialConfig(uint8_t parity)
{
    switch ((ModbusParity)parity) {
        case ModbusParity::Odd:     return SERIAL_8O1;
        case ModbusParity::None:    return SERIAL_8N2;   // 8N2, per the spec
        case ModbusParity::None8N1: return SERIAL_8N1;
        case ModbusParity::Even:
        default:                    return SERIAL_8E1;
    }
}
#endif

#define MB_BRIDGE_REOPEN_MS 2000

// The same reason as MODBUS_NODE: the Runtime swaps a program into the same
// process, and a listening socket outlives the shared object unless somebody
// closes it.
//
// Each entry carries its own way to close: the cleanup below is in every
// program that uses this library, and naming the bridge there would put the
// whole gateway into projects that have no bridge.
struct MbOwnedBridge {
    ModbusBridge* bridge;
    void (*close)(ModbusBridge*);
    MbOwnedBridge* next;
};
static MbOwnedBridge* mbOwnedBridges = nullptr;

static void mbCloseBridge(ModbusBridge* bridge) {
    bridge->end();
    delete bridge;
}

namespace {
struct MbBridgeCleanup {
    ~MbBridgeCleanup() {
        while (mbOwnedBridges) {
            MbOwnedBridge* owned = mbOwnedBridges;
            mbOwnedBridges = owned->next;
            owned->close(owned->bridge);
            delete owned;
        }
    }
};
static MbBridgeCleanup mbBridgeCleanup;
}  // namespace

#if defined(MODBUS_PLATFORM_ARDUINO)
// The one listener an Arduino bridge needs. The Arduino network classes share
// no base, so the library binds to them by template.
#if defined(MB_HAS_WIFI)
static WiFiServer* mbBridgeServer = nullptr;
#endif
static ModbusListener* mbBridgeListener = nullptr;

static HardwareSerial* mbBridgeSerialPort(uint8_t port)
{
    // A number the board does not have is refused (nullptr), never quietly
    // opened on UART0: on the ModBee Node UART0 is the HAT port, where a modem
    // sits.
    switch (port) {
        case 0:
#if defined(ARDUINO_ARCH_ESP32) && defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
            // This core boots Serial as the USB CDC device rather than a UART,
            // so it is not a HardwareSerial at all. Serial0 is UART0.
            return &Serial0;
#else
            return &Serial;
#endif
#if defined(HAVE_HWSERIAL1) || defined(ARDUINO_ARCH_ESP32)
        case 1: return &Serial1;
#endif
#if defined(HAVE_HWSERIAL2) || defined(ARDUINO_ARCH_ESP32)
        case 2: return &Serial2;
#endif
        default: return nullptr;
    }
}
#endif

#if defined(ARDUINO_ARCH_ESP32)
// Defined by MODBUS_ARDUINO, which sorts first.
int mb_serialBegin(HardwareSerial* port, uint32_t baud, uint32_t cfg,
                   int rxPin, int txPin, int dePin);
#endif

void setup()
{
    READY = false;
    CLIENTS = 0;
    FORWARDED = 0;
    NO_PATH = 0;
    NO_DEVICE = 0;
    FRAMING_REASON = "";
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    LAST_ERROR = "";
    fbApi = (strucpp::XWORD_t)0;
    fbTried = false;
    fbRetryAt = 0;
}

void loop()
{
    ModbusBridge* bridge = (ModbusBridge*)(uintptr_t)(strucpp::XWORD_t)fbApi;

    if (!(bool)CONNECT) {
        if (bridge && (bool)READY) bridge->end();
        READY = false;
        CLIENTS = 0;
        fbTried = false;
        return;
    }

    if (!(bool)READY) {
        const mb_time_t now = mb_millis();
        if ((bool)fbTried &&
            (int32_t)(now - (mb_time_t)(uint32_t)(int32_t)fbRetryAt) < 0) {
            return;
        }
        fbTried = true;
        fbRetryAt = (int32_t)(uint32_t)(now + MB_BRIDGE_REOPEN_MS);

        if ((uint8_t)FIRST_UNIT < 1 || (uint8_t)LAST_UNIT < (uint8_t)FIRST_UNIT) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "FIRST_UNIT and LAST_UNIT name the devices out there";
            return;
        }

        if (!bridge) {
            bridge = new (std::nothrow) ModbusBridge();
            if (!bridge) {
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
                LAST_ERROR = "out of memory";
                return;
            }
            fbApi = (strucpp::XWORD_t)(uintptr_t)bridge;
            MbOwnedBridge* owned =
                new (std::nothrow) MbOwnedBridge{ bridge, &mbCloseBridge, mbOwnedBridges };
            if (owned) mbOwnedBridges = owned;
        }

        const uint32_t baud = ((int32_t)SERIAL_BAUD > 0) ? (uint32_t)(int32_t)SERIAL_BAUD : 19200u;
        const uint16_t tcpPort =
            ((uint16_t)TCP_PORT != 0) ? (uint16_t)TCP_PORT : MODBUS_TCP_PORT;

        if ((uint8_t)MAX_CLIENTS > 0) bridge->maxClients((size_t)(uint8_t)MAX_CLIENTS);
        if ((uint8_t)MAX_PENDING > 0) bridge->maxOutstanding((size_t)(uint8_t)MAX_PENDING);
        bridge->route((uint8_t)FIRST_UNIT, (uint8_t)LAST_UNIT);
        bridge->routeEverythingElse((bool)PASS_OTHERS);

#if defined(MODBUS_PLATFORM_HOST)
        if (SERIAL_DEVICE.length() == 0) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "no serial device named";
            return;
        }
        // The pins are members of this instance, so their buffers outlive the
        // scan and the transport may hold them.
        bridge->serial(SERIAL_DEVICE.c_str(), baud, (ModbusParity)(MODBUS_PARITY)SERIAL_PARITY);
        bridge->listen(tcpPort);
#endif

#if defined(MODBUS_PLATFORM_ARDUINO)
        HardwareSerial* port = mbBridgeSerialPort((uint8_t)PORT);
        if (port == nullptr) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "PORT is not a hardware serial on this board";
            return;
        }
        const uint32_t cfg =
            mbBridgeSerialConfig((uint8_t)(MODBUS_PARITY)SERIAL_PARITY);
#if defined(ARDUINO_ARCH_ESP32)
        // The UART drives DE here: see mb_serialBegin() in MODBUS_ARDUINO.
        const int de = mb_serialBegin(port, baud, cfg, (int)(int16_t)RX_PIN,
                                      (int)(int16_t)TX_PIN, (int)(int16_t)DE_PIN);
#else
        port->begin(baud, cfg);
        const int de = (int)(int16_t)DE_PIN;
#endif
        bridge->serial(port, baud);
        if (de >= 0) {
            const uint32_t hold =
                (mb_microsOf(DE_HOLD) > 0) ? (uint32_t)mb_microsOf(DE_HOLD) : 2000u;
            bridge->directionPin(de, true, hold);
        }

#if defined(MB_HAS_WIFI)
        bool roomForClients = true;
        if (!mbBridgeListener) {
            // 0 is the listener's own default (two); any other figure is held
            // in full or refused out loud - never quietly fewer.
            const size_t limit = (uint8_t)MAX_CLIENTS;
            mbBridgeServer = new (std::nothrow) WiFiServer(tcpPort);
            if (mbBridgeServer) {
                ModbusArduinoServer<WiFiServer, WiFiClient>* server =
                    new (std::nothrow) ModbusArduinoServer<WiFiServer, WiFiClient>(
                        *mbBridgeServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbBridgeListener = server;
            }
        }
        if (!mbBridgeListener) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            LAST_ERROR = roomForClients ? "out of memory" : "out of memory for MAX_CLIENTS connections";
            return;
        }
#else
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        LAST_ERROR = "this board has no WiFi; a bridge needs a TCP front";
        return;
#endif
        bridge->listen(*mbBridgeListener);
#endif

        if (!bridge->begin()) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            LAST_ERROR = "the serial device or the TCP port would not open";
            return;
        }

        READY = true;
        ERROR = false;
        STATUS = MODBUS_RESULT::MODBUS_OK;
        LAST_ERROR = "";
        FRAMING_REASON = bridge->framingReason();
    }

    if (!bridge) return;

    // Both ends, once per call.
    bridge->poll();

    CLIENTS = (int16_t)bridge->clients();
    FORWARDED = (int32_t)bridge->forwarded();
    NO_PATH = (int32_t)bridge->noPath();
    NO_DEVICE = (int32_t)bridge->deviceAbsent();
}

END_FUNCTION_BLOCK