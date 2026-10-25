(* Starts a Modbus link, and is the node every other block takes.

TRANSPORT       where the bytes go. MODBUS_RUNTIME_SERIAL unless you say
                otherwise.
                MODBUS_RUNTIME_SERIAL, MODBUS_RUNTIME_TCP,
                MODBUS_ARDUINO_SERIAL, MODBUS_ARDUINO_WIFI,
                MODBUS_ARDUINO_ETHERNET
ROLE            which half to be. Ask, answer, or both.
                MODBUS_ROLE_CLIENT, MODBUS_ROLE_SERVER, MODBUS_ROLE_BOTH

TCP_HOST        the device to connect to. Empty means be a server instead.
TCP_PORT        0 for 502.

SERIAL_DEVICE   the serial device, e.g. /dev/ttyUSB0. Runtime only.
SERIAL_BAUD     0 for 19200, the Modbus default.
SERIAL_PARITY   MODBUS_PARITY_EVEN is the Modbus default. MODBUS_PARITY_NONE
                is 8N2, per the specification, NOT 8N1.
                MODBUS_PARITY_EVEN, MODBUS_PARITY_ODD, MODBUS_PARITY_NONE,
                MODBUS_PARITY_NONE_8N1
SERIAL_UNIT_ID  the address THIS node answers to on a serial line, 1..247.
                Serial SERVER only - a TCP server needs none, because a client
                reaching it over IP has already addressed it.

RESET_STATS     rising edge zeroes this link's frame and error counters, which
                MODBUS_STATUS reports. The node owns the link, so the node
                clears them.
CONNECT         be on the bus. TRUE unless you say otherwise, which is what
                almost every node wants - leave it unwired and the link opens
                and stays.

                Drop it to FALSE and the link closes: the port is released and
                the socket dropped, which is what a node sharing a converter
                with something else wants. Raise it and the link opens again.

READY       the link is open.
CONNECTED   there is something at the other end. For a server, that it is
            listening - a server has no single peer, and answering FALSE while
            three clients are connected would be the wrong answer.
CLIENTS     how many clients are connected. Servers only.
ERROR       the link did not open, or has since failed.
STATUS      why. MODBUS_OK when fine.
            MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
            MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
            MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
            MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
            MODBUS_ACKNOWLEDGED, MODBUS_BUSY, MODBUS_GATEWAY_PATH_UNAVAILABLE,
            MODBUS_GATEWAY_TARGET_FAILED, MODBUS_LINK_DOWN,
            MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR
LAST_ERROR  the operating system's own words - "No such file or directory",
            "Address already in use", "Permission denied". Text, because that
            is the whole value of it: a code cannot say which of forty things
            went wrong at a socket, and "Permission denied" on a serial device
            is a user not in the dialout group, which no status pin can say.

---

THE PINS ARE PREFIXED BY WHAT THEY BELONG TO, and everything below TCP_PORT is
serial. A pin for a transport you are not using is ignored, so a TCP node
leaves the four SERIAL_ pins alone and a serial node leaves the two TCP_ pins
alone. SERIAL_UNIT_ID is the one people expect to need on TCP and do not: a
TCP server answers whatever unit id is asked for.

Declare one and pass it to the other blocks on their NODE pin:

  node( TRANSPORT := MODBUS_RUNTIME_SERIAL, SERIAL_DEVICE := '/dev/ttyUSB0',
        SERIAL_BAUD := 19200 );

  rd( NODE := node, UNIT := 2, FC := MODBUS_FC03_READ_HOLDING_REGISTERS,
      ADDRESS := 40, VALUE := myWords );

The NODE pin must be assigned at every call. Leaving it out is a compile error,
which is the point: a block with no node is a block that silently does nothing.

A LINK THAT DROPS COMES BACK ON ITS OWN, and you do not have to ask for it. The
far end of a Modbus link is a device that gets rebooted, a switch that gets
swapped, an adapter that gets unplugged and put back. A dropped link is retried
every two seconds until it returns, and every watched value is made due the
moment it does. MODBUS_CONFIG's RECONNECT is there only to pace that
differently, or to turn it off.

THESE ELEVEN PINS ARE THE WHOLE OF AN ORDINARY LINK. Everything else a node can
be told lives on three optional blocks, so it costs you nothing until you want
it:

  MODBUS_CONFIG    timeouts, retries, failsafe, how many clients to hold, and
                   how often to retry a link that dropped.
  MODBUS_IDENTITY  the nameplate this node answers function code 43 with.
  MODBUS_ARDUINO   the pins only a board has - which hardware serial, the
                   RS-485 direction pin, WiFi credentials, an Ethernet MAC.

All three take this node on their own NODE pin and may sit anywhere in the same
program - above or below. The node waits one scan before opening so that
whatever they set has been seen. WITHOUT ANY OF THEM THE DEFAULTS ARE THE ONES
YOU WANT: the timeout is measured per device, the retry count is the library's,
a dropped link recovers, nothing fails safe, a server holds eight clients, and
a board uses its own serial pins.

CALL THIS BLOCK, AND EVERY BLOCK GIVEN IT, IN A FAST TASK OF THEIR OWN. It is
the only block that touches the wire - it transmits, receives, retries and
times out, once per call. Your application sits in a slower task and trades
values with them through globals:

  APP_TASK  T#20ms  prio 0   the machine - no Modbus block at all
  NET_TASK  T#1ms   prio 20  MODBUS_NODE and every block given it
                             (on a board: T#50ms to start, then measure)

A block given this node from any other task says MODBUS_WRONG_TASK and does
nothing: OpenPLC runs each task on a thread of its own, and the node is
single-threaded.

That split is not a style preference. A read is sent on the node's next call,
so the node's period is the floor on how quickly anything happens, and a node
called every 20 ms on a 19200 baud bus wastes most of the bus waiting for a
task to come round.

TRANSPORT picks the link. Which pins matter depends on it, and the rest are
ignored:

  MODBUS_RUNTIME_SERIAL    SERIAL_DEVICE, SERIAL_BAUD, SERIAL_PARITY
  MODBUS_RUNTIME_TCP       TCP_HOST, TCP_PORT
  MODBUS_ARDUINO_SERIAL    SERIAL_BAUD, SERIAL_PARITY, and MODBUS_ARDUINO
  MODBUS_ARDUINO_WIFI      TCP_HOST, TCP_PORT, and MODBUS_ARDUINO
  MODBUS_ARDUINO_ETHERNET  TCP_HOST, TCP_PORT, and MODBUS_ARDUINO

A MODBUS_RUNTIME_* link runs on the OpenPLC Runtime, a MODBUS_ARDUINO_* link
on a board. Choosing one the target does not have is reported on the pins, not
built.

FRAMING IS NOT A PIN HERE, and it does not need to be. How frames are found is
worked out from the medium - RTU on a serial line, MBAP on a socket - and that
is right for every link that is not behind a converter. The two that are not
ordinary live on MODBUS_CONFIG's FRAMING pin:

  RTU OVER TCP - a serial-to-Ethernet converter, one of the boxes sold as a
  "Modbus gateway". They put a raw RTU frame inside a TCP stream with no MBAP
  header, and share port 502 with the real thing, so a normal TCP client gets
  silence and no explanation.

  ASCII - for a link that cannot hold RTU's character timing, such as a radio
  or a modem. Twice the bytes, and a full second allowed between them.

ASCII inside a TCP stream is refused with MODBUS_INVALID_ARGUMENT, and so is
MBAP framing on a serial line. Neither is a real thing, and pretending
otherwise would turn a typing mistake into a silence nobody can explain.

ROLE says which half of Modbus this node is:

  MODBUS_ROLE_CLIENT  it asks. MODBUS_READ and MODBUS_WRITE work.
  MODBUS_ROLE_SERVER  it answers. MODBUS_MAP puts your variables on the bus.
  MODBUS_ROLE_BOTH    both, which is ordinary on RS-485 and rarer on TCP.

A serial server also needs UNIT_ID - the address other devices call it by. A
TCP server does not: a client has already addressed it by IP, so it answers
whatever unit id is asked for. *)

FUNCTION_BLOCK MODBUS_NODE
  VAR_INPUT
    TRANSPORT : MODBUS_TRANSPORT;
    ROLE : MODBUS_ROLE;
    TCP_HOST : STRING(48);
    TCP_PORT : UINT;
    SERIAL_DEVICE : STRING(48);
    SERIAL_BAUD : DINT;
    SERIAL_PARITY : MODBUS_PARITY;
    SERIAL_UNIT_ID : BYTE;
    RESET_STATS : BOOL;
    CONNECT : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    READY : BOOL;
    CONNECTED : BOOL;
    CLIENTS : INT;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR
    fbApi : __XWORD;
    (* The server half (mbServe), handed over by MODBUS_MAP or MODBUS_IDENTITY.
       Zero in a project that only asks, which then carries none of it. *)
    fbServe : __XWORD;
    fbKind : BYTE;
    fbResetSeen : BOOL;
    fbTried : BOOL;
    fbRetryAt : DINT;
    fbSettled : BOOL;

    (* Everything the optional helper blocks set, holding the same defaults
       the pins used to. A node with no helper beside it behaves exactly as it
       always did, which is the whole point of them being optional. *)
    fbTimeoutMs : DINT;
    fbRetries : BYTE;
    fbFailsafeMs : DINT;
    fbMaxClients : BYTE;
    fbIdleMs : DINT;
    fbReconnectMs : DINT;
    fbFraming : MODBUS_FRAMING;
    fbVendor : STRING(32);
    fbProduct : STRING(32);
    fbRevision : STRING(32);
    fbPort : BYTE;
    fbRxPin : INT := -1;
    fbTxPin : INT := -1;
    fbDePin : INT := -1;
    fbDeHoldUs : DINT;
    fbSsid : STRING(48);
    fbPassword : STRING(63);
    fbMac : STRING(32);
    fbIp : STRING(32);
    fbGateway : STRING(32);
    fbSubnet : STRING(32);
    fbQueue : UINT;
    fbQueueBytes : UINT;
    (* The task this block runs in, for the blocks given it: see MODBUS_ARDUINO, "ONE TASK PER NODE". *)
    fbTask : __XWORD;
  END_VAR
#include <ModBeeModbus.h>

#include <new>

#if defined(MODBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// WIFI IS DETECTED. ETHERNET HAS TO BE ASKED FOR, and the reason is worth
// knowing because it is not obvious and it cost this library a bug.
//
// WiFi.h ships inside the ESP32 core, so it is on the include path already and
// __has_include finds it. A board without WiFi simply does not compile that
// path and says so on LAST_ERROR.
//
// The Arduino Ethernet library is a USER library, and arduino-cli puts a user
// library on the include path only when its dependency scanner sees a plain
// #include for it. A header hidden behind __has_include is invisible to that
// scanner - so the library can be installed, the guard still says it is not,
// and MODBUS_ARDUINO_ETHERNET reports "install the Arduino Ethernet library"
// for ever. Measured, not guessed: with the library installed and the include
// behind __has_include, MB_HAS_ETHERNET came out OFF.
//
// So Ethernet is opt-in. Define MODBUS_ENABLE_ETHERNET in the project's build
// flags and the include becomes plain, the scanner finds the library, and the
// path compiles - which it does cleanly, checked against the real library on
// an ESP32-S3.
//
// MODBUS_NO_WIFI forces WiFi off, for a board that has the header and cannot
// link it.
#if !defined(MODBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define MB_HAS_WIFI 1
#include <WiFi.h>
#endif
#endif

#if defined(MODBUS_ENABLE_ETHERNET)
#define MB_HAS_ETHERNET 1
#include <Ethernet.h>
#endif
#endif

// Every node this program made, so they can be closed when it is unloaded.
//
// The OpenPLC Runtime swaps a new program into the SAME process rather than
// restarting it, and a socket is owned by the process, not by the shared
// object. A node that simply leaked its ModbusTCP would leave its listening
// socket open for ever - and the next download would come up reporting "could
// not bind the port", on a port nothing appears to be using.
//
// A static destructor is the one hook a POU has: it runs when the program is
// unloaded and at process exit, which is exactly when these must go.
//
// A plain list, one entry per node, made when the node is: no container code.
struct MbOwnedNode {
    ModbusAPI* api;
    MbOwnedNode* next;
};
static MbOwnedNode* mbOwnedNodes = nullptr;

namespace {
struct MbNodeCleanup {
    ~MbNodeCleanup() {
        while (mbOwnedNodes) {
            MbOwnedNode* owned = mbOwnedNodes;
            mbOwnedNodes = owned->next;
            owned->api->end();
            delete owned->api;
            delete owned;
        }
    }
};
static MbNodeCleanup mbNodeCleanup;
}  // namespace

// Which concrete link this block made, so a re-open after CONNECT takes the
// same path the first open took.
#define MB_KIND_NONE  0
#define MB_KIND_RTU   1
#define MB_KIND_ASCII 2
#define MB_KIND_TCP   3

// How long to wait before trying a failed open again. An absent serial device
// fails in microseconds, and a 1 ms task retrying that every scan is a
// thousand identical failures a second in the log.
#define MB_REOPEN_MS  2000

// MODBUS_RESULT mirrors ModbusResult member for member, so every block casts
// rather than translates. Asserted here because every project has a node.
static_assert((int)MODBUS_RESULT::MODBUS_PROTOCOL_ERROR + 1 == MB_RESULT_COUNT,
              "MODBUS_RESULT must mirror ModbusResult member for member");

// The same for the three enumerations the blocks cast rather than translate.
static_assert((int)MODBUS_TABLE::MODBUS_COILS == (int)ModbusTable::Coil &&
              (int)MODBUS_TABLE::MODBUS_INPUT_REGISTERS == (int)ModbusTable::InputRegister,
              "MODBUS_TABLE must mirror ModbusTable");
static_assert((int)MODBUS_ORDER::MODBUS_ORDER_ABCD == (int)ModbusOrder::ABCD &&
              (int)MODBUS_ORDER::MODBUS_ORDER_DCBA == (int)ModbusOrder::DCBA,
              "MODBUS_ORDER must mirror ModbusOrder");
static_assert((int)MODBUS_QUALITY::MODBUS_QUALITY_UNKNOWN == (int)ModbusQuality::Unknown &&
              (int)MODBUS_QUALITY::MODBUS_QUALITY_BAD == (int)ModbusQuality::Bad,
              "MODBUS_QUALITY must mirror ModbusQuality");
static_assert((int)MODBUS_PARITY::MODBUS_PARITY_EVEN == (int)ModbusParity::Even &&
              (int)MODBUS_PARITY::MODBUS_PARITY_NONE_8N1 == (int)ModbusParity::None8N1,
              "MODBUS_PARITY must mirror ModbusParity");

// How wide one element of a generic pin is, in bits: 1 for a BOOL, then 16, 32
// or 64. Zero for a type Modbus does not carry.
//
// Plain numbers rather than an enumeration of our own, so the blocks that ask
// need nothing shared but this declaration. Defined here rather than in the
// protocol, which knows nothing about a toolchain; every project has a node,
// so every project has this.
// --- reading and writing a TIME pin --------------------------------------
//
// Every duration on every block is a TIME, so that T#500ms on one of these
// reads the same as T#500ms on a TON beside it. TIME is signed nanoseconds
// here and unsigned milliseconds in CODESYS, so nothing relies on a negative:
// below zero is treated as none at all.
//
// ROUNDED UP. Everywhere in this library 0 means "use the sensible default",
// so a pin somebody set to T#1ms must not arrive as 0 and silently become
// something else entirely.
int32_t mb_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = TIME_TO_NS(t);
    if (ns <= 0) return 0;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 2147483647LL ? 2147483647 : (int32_t)ms;
}

// The RS-485 driver-enable hold is microseconds, which a CODESYS TIME cannot
// resolve - that pin is an LTIME and this reads either.
int32_t mb_microsOf(const strucpp::IEC_LTIME& t)
{
    // LTIME_t and TIME_t are both int64 nanoseconds; get() is how a value
    // comes off an IECVar whatever it wraps.
    const int64_t ns = t.get();
    if (ns <= 0) return 0;
    const int64_t us = (ns + 999LL) / 1000LL;
    return us > 2147483647LL ? 2147483647 : (int32_t)us;
}

// And the way back, for an age or a round trip reported on a pin. A negative
// count - which inside these blocks means "it has never happened" - comes out
// as T#0s, because TIME is unsigned in CODESYS and a pin showing a negative
// duration would be a lie about a type. The pin beside it says which zero it
// is: ANSWERING, or QUALITY reading UNKNOWN.
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds)
{
    if (milliseconds <= 0) return strucpp::IEC_TIME((strucpp::TIME_t)0);
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

uint8_t mb_elementBits(uint32_t typeClass)
{
    switch (typeClass) {
        case strucpp::TYPE_CLASS::TYPE_BOOL:
        case strucpp::TYPE_CLASS::TYPE_BIT:    return 1;

        // A register is sixteen bits and nothing else. BYTE and SINT are
        // narrower than a register, so binding one would leave half a register
        // pointing at whatever sits beside it in memory.
        case strucpp::TYPE_CLASS::TYPE_WORD:
        case strucpp::TYPE_CLASS::TYPE_UINT:
        case strucpp::TYPE_CLASS::TYPE_INT:    return 16;

        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT:
        case strucpp::TYPE_CLASS::TYPE_DINT:
        case strucpp::TYPE_CLASS::TYPE_REAL:   return 32;

        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT:
        case strucpp::TYPE_CLASS::TYPE_LINT:
        case strucpp::TYPE_CLASS::TYPE_LREAL:  return 64;

        default: break;
    }
    return 0;
}

// Which wide type a 32- or 64-bit element is, so the value is converted rather
// than copied. ModbusWideType::None for anything a register holds directly.
ModbusWideType mb_wideTypeOfClass(uint32_t typeClass)
{
    switch (typeClass) {
        case strucpp::TYPE_CLASS::TYPE_REAL:   return ModbusWideType::Float32;
        case strucpp::TYPE_CLASS::TYPE_DINT:   return ModbusWideType::Int32;
        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT:  return ModbusWideType::UInt32;
        case strucpp::TYPE_CLASS::TYPE_LREAL:  return ModbusWideType::Float64;
        case strucpp::TYPE_CLASS::TYPE_LINT:   return ModbusWideType::Int64;
        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT:  return ModbusWideType::UInt64;
        default: break;
    }
    return ModbusWideType::None;
}

#if defined(MODBUS_PLATFORM_ARDUINO)
// The line settings SERIAL_PARITY asks for, as this core spells them. Modbus
// RTU is 8E1 by specification and that is this block's default, so a board
// that quietly opened 8N1 would talk past every conforming device on the
// segment - the frames would be the right length and the parity bit missing,
// which reads as noise rather than as a mistake.
uint32_t mb_serialConfig(uint8_t parity)
{
    switch ((ModbusParity)parity) {
        case ModbusParity::Odd:     return SERIAL_8O1;
        case ModbusParity::None:    return SERIAL_8N2;   // 8N2, per the spec
        case ModbusParity::None8N1: return SERIAL_8N1;
        case ModbusParity::Even:
        default:                    return SERIAL_8E1;
    }
}

// The board's hardware serials, by the number the fbPort pin gives. Not every
// board has all of them, which is why this is a switch and not an array.
static HardwareSerial* mbSerialPort(uint8_t port)
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

// A PLC gets a fixed address, and asking for one is not a formality.
//
// On Ethernet, DHCP BLOCKS in the Arduino library - sixty seconds by default -
// and on a 1 ms task that is a stopped PLC, not a delay. On WiFi it does not
// block, but a node that ANSWERS Modbus has to be findable: a SCADA package
// cannot poll an address that moved when the lease expired.
//
// So IP is required on both, and "dhcp" is how you say you meant it.
static bool mbWantsDhcp(const char* text)
{
    if (!text) return false;
    return (text[0] == 'd' || text[0] == 'D') &&
           (text[1] == 'h' || text[1] == 'H') &&
           (text[2] == 'c' || text[2] == 'C') &&
           (text[3] == 'p' || text[3] == 'P') && text[4] == '\0';
}

#if defined(MB_HAS_WIFI) || defined(MB_HAS_ETHERNET)
// The gateway a caller left empty: the address with its last octet set to 1,
// which is where it is on almost every small network.
static IPAddress mbGatewayFor(const IPAddress& address, const char* given)
{
    IPAddress gateway;
    if (given && given[0] && gateway.fromString(given)) return gateway;
    return IPAddress(address[0], address[1], address[2], 1);
}

static IPAddress mbSubnetFor(const char* given)
{
    IPAddress subnet;
    if (given && given[0] && subnet.fromString(given)) return subnet;
    return IPAddress(255, 255, 255, 0);
}
#endif

#if defined(MB_HAS_ETHERNET)
// Six hex bytes with any separator, into the array Ethernet.begin takes.
static bool mbParseMac(const char* text, uint8_t out[6])
{
    if (!text) return false;
    int byteIndex = 0;
    unsigned value = 0;
    int digits = 0;
    for (const char* p = text; ; p++) {
        const char c = *p;
        const bool separator = (c == ':' || c == '-' || c == '\0');
        if (separator) {
            if (digits == 0 || byteIndex > 5) return false;
            out[byteIndex++] = (uint8_t)value;
            value = 0;
            digits = 0;
            if (c == '\0') break;
            continue;
        }
        int nibble;
        if (c >= '0' && c <= '9') nibble = c - '0';
        else if (c >= 'a' && c <= 'f') nibble = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') nibble = c - 'A' + 10;
        else return false;
        if (++digits > 2) return false;
        value = (value << 4) | (unsigned)nibble;
    }
    return byteIndex == 6;
}
#endif

// The socket and the transport an Arduino TCP link needs.
//
// One pair PER MEDIUM. The Arduino network classes share no base - WiFiClient
// and EthernetClient are unrelated types with the same shape - so the library
// binds to them by template, and an Ethernet node must get an EthernetClient.
// It used to get a WiFiClient whatever it asked for, which is a link that
// brings up the right hardware and then talks over the wrong one.
#if defined(MB_HAS_WIFI)
static WiFiClient* mbWifiClient = nullptr;
static WiFiServer* mbWifiServer = nullptr;
#endif
#if defined(MB_HAS_ETHERNET)
static EthernetClient* mbEthClient = nullptr;
static EthernetServer* mbEthServer = nullptr;
#endif
static ModbusTransport* mbArduinoTransport = nullptr;
static ModbusListener* mbArduinoListener = nullptr;
#endif

// =============================================================================
// THE SERVER HALF
// =============================================================================
//
// Everything only a node that ANSWERS needs: the unit id on a serial line, the
// listening socket on TCP. The node never calls this by name. The blocks that
// give a server something to serve - MODBUS_MAP and MODBUS_IDENTITY - hand it
// over through fbServe, so a project with neither (a board reading sensors)
// carries none of it, nor the server code it reaches.
//
// MODBUS_OK when it is serving, or why not. `opened` is set by the TCP paths,
// where listening is what opens the node.
MODBUS_RESULT mbServe(ModbusAPI* mb, uint8_t kind, bool onWifi, uint16_t tcpPort,
                      uint8_t maxClients, mb_time_t idleMs, uint8_t unitId,
                      bool& opened, const char*& why)
{
    if (kind != MB_KIND_TCP) {
        // A serial server answers to a unit id; a TCP server does not, because
        // a client reaching it over TCP has already addressed it by IP.
        if (unitId < 1 || unitId > 247) {
            why = "a serial server needs SERIAL_UNIT_ID, 1 to 247";
            return MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        }
        if (kind == MB_KIND_ASCII) ((ModbusASCII*)mb)->slave(unitId);
        else ((ModbusRTU*)mb)->slave(unitId);
        return MODBUS_RESULT::MODBUS_OK;
    }

    ModbusTCP* tcp = (ModbusTCP*)mb;
#if defined(MODBUS_PLATFORM_HOST)
    (void)onWifi;
    if (maxClients > 0) tcp->maxClients((size_t)maxClients);
    tcp->idleTimeout(idleMs);
    opened = tcp->listen(tcpPort);
#endif
#if defined(MODBUS_PLATFORM_ARDUINO)
    // MODBUS_CONFIG's MAX_CLIENTS and IDLE, as on the host: the listener takes
    // the limit too, because it holds the sockets before the pool sees them.
    if (maxClients > 0) tcp->maxClients((size_t)maxClients);
    tcp->idleTimeout(idleMs);
    // MAX_CLIENTS 0 is the listener's own default (two). Any other figure is
    // held in full or refused out loud - never quietly fewer.
    const size_t limit = maxClients;
    bool roomForClients = true;
    if (!mbArduinoListener) {
#if defined(MB_HAS_WIFI)
        if (onWifi) {
            mbWifiServer = new (std::nothrow) WiFiServer(tcpPort);
            if (mbWifiServer) {
                ModbusArduinoServer<WiFiServer, WiFiClient>* server = new (std::nothrow)
                    ModbusArduinoServer<WiFiServer, WiFiClient>(*mbWifiServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbArduinoListener = server;
            }
        }
#endif
#if defined(MB_HAS_ETHERNET)
        if (!onWifi) {
            mbEthServer = new (std::nothrow) EthernetServer(tcpPort);
            if (mbEthServer) {
                ModbusArduinoServer<EthernetServer, EthernetClient>* server = new (std::nothrow)
                    ModbusArduinoServer<EthernetServer, EthernetClient>(*mbEthServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbArduinoListener = server;
            }
        }
#endif
    }
    if (!mbArduinoListener) {
        why = roomForClients ? "out of memory" : "out of memory for MAX_CLIENTS connections";
        return MODBUS_RESULT::MODBUS_NOT_INITIALISED;
    }
    opened = tcp->listen(*mbArduinoListener);
#endif
    return MODBUS_RESULT::MODBUS_OK;
}

typedef MODBUS_RESULT (*MbServeFn)(ModbusAPI*, uint8_t, bool, uint16_t, uint8_t, mb_time_t,
                                   uint8_t, bool&, const char*&);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);
#if defined(ARDUINO_ARCH_ESP32)
int mb_serialBegin(HardwareSerial* port, uint32_t baud, uint32_t cfg,
                   int rxPin, int txPin, int dePin);
#endif
void setup()
{
    READY = false;
    CONNECTED = false;
    CLIENTS = 0;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    LAST_ERROR = "";
    fbApi = (strucpp::XWORD_t)0;
    fbServe = (strucpp::XWORD_t)0;
    fbKind = MB_KIND_NONE;
    fbResetSeen = false;
    fbSettled = false;
    fbTried = false;
    fbRetryAt = 0;
}

void loop()
{
    fbTask = mb_currentTask();   // every block given this node shares it: see MODBUS_ARDUINO
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)fbApi;

    // Asked to stand down. The port is released and the socket dropped, so
    // something else may use the converter; the object stays, because the
    // pins that describe it have not changed and rebuilding it would lose the
    // register bindings other blocks made.
    if (!(bool)CONNECT) {
        if (mb && (bool)READY) mb->end();
        READY = false;
        CONNECTED = false;
        CLIENTS = 0;
        fbTried = false;
        return;
    }

    if (!(bool)READY) {
        // ONE SCAN BEFORE OPENING.
        //
        // MODBUS_ARDUINO and MODBUS_CONFIG write into this instance, and they
        // may sit above or below this block in the rung order. Waiting a scan
        // means both have run at least once before the link is built, so a
        // helper does not have to be placed in any particular place - which is
        // a rule nobody would remember and the compiler could not check.
        //
        // It costs one scan of the fast task. Opening a socket takes longer
        // than that on its own.
        if (!(bool)fbSettled) {
            fbSettled = true;
            return;
        }

        const mb_time_t now = mb_millis();
        if ((bool)fbTried &&
            (int32_t)(now - (mb_time_t)(uint32_t)(int32_t)fbRetryAt) < 0) {
            return;
        }
        fbTried = true;
        fbRetryAt = (int32_t)(uint32_t)(now + MB_REOPEN_MS);

        const MODBUS_TRANSPORT link = (MODBUS_TRANSPORT)TRANSPORT;
        const MODBUS_FRAMING frame = (MODBUS_FRAMING)fbFraming;
        const MODBUS_ROLE role = (MODBUS_ROLE)ROLE;

        const bool onSerial =
            (link == MODBUS_TRANSPORT::MODBUS_RUNTIME_SERIAL) ||
            (link == MODBUS_TRANSPORT::MODBUS_ARDUINO_SERIAL);
        const bool runtimeLink =
            (link == MODBUS_TRANSPORT::MODBUS_RUNTIME_SERIAL) ||
            (link == MODBUS_TRANSPORT::MODBUS_RUNTIME_TCP);

#if defined(MODBUS_PLATFORM_HOST)
        if (!runtimeLink) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "that transport needs a board, not the Runtime";
            return;
        }
#else
        if (runtimeLink) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "that transport needs the Runtime, not a board";
            return;
        }
#endif

        // Framing that the medium cannot carry is refused here rather than
        // turned into a silence at the far end.
        if (onSerial && frame == MODBUS_FRAMING::MODBUS_FRAMING_TCP) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "MBAP framing has no meaning on a serial line";
            return;
        }
        if (!onSerial && frame == MODBUS_FRAMING::MODBUS_FRAMING_ASCII) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "ASCII inside a TCP stream is not a Modbus transport";
            return;
        }

        const uint8_t wanted = onSerial
            ? ((frame == MODBUS_FRAMING::MODBUS_FRAMING_ASCII) ? MB_KIND_ASCII : MB_KIND_RTU)
            : MB_KIND_TCP;

        // Built once and kept. A re-open after CONNECT reuses it, which is why
        // the bindings MODBUS_MAP made survive the gap.
        if (!mb) {
            if (wanted == MB_KIND_RTU)        mb = new (std::nothrow) ModbusRTU();
            else if (wanted == MB_KIND_ASCII) mb = new (std::nothrow) ModbusASCII();
            else                              mb = new (std::nothrow) ModbusTCP();

            if (!mb) {
                // Arduino cores build without exceptions, so an exhausted heap
                // has to be handled here or it is a hard fault. The node
                // refuses to start and says so; it does not take the PLC down.
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
                LAST_ERROR = "out of memory";
                return;
            }
            fbApi = (strucpp::XWORD_t)(uintptr_t)mb;
            fbKind = wanted;
            // Out of memory here costs only the close at unload, not the node.
            MbOwnedNode* owned = new (std::nothrow) MbOwnedNode{ mb, mbOwnedNodes };
            if (owned) mbOwnedNodes = owned;
        } else if ((uint8_t)fbKind != wanted) {
            // The pins changed under a live node. Rebuilding would drop every
            // binding silently, so it is refused and said out loud instead.
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "TRANSPORT and fbFraming cannot change once started";
            return;
        }

        // Settings that belong to the node rather than the medium, applied
        // before it opens so the first request already has them.
        if ((int32_t)fbTimeoutMs > 0) mb->timeout((mb_time_t)(int32_t)fbTimeoutMs);
        if ((uint8_t)fbRetries > 0) mb->retries((uint8_t)fbRetries);
        if ((int32_t)fbFailsafeMs > 0) mb->failsafeAfter((mb_time_t)(int32_t)fbFailsafeMs);
        // MODBUS_CONFIG's QUEUE and QUEUE_BYTES. Taken when the link opens; a
        // figure the board cannot hold fails the open with the reason on
        // LAST_ERROR (mb->lastError()).
        if ((uint16_t)fbQueue > 0 || (uint16_t)fbQueueBytes > 0) {
            mb->queueSize((size_t)(uint16_t)fbQueue, (size_t)(uint16_t)fbQueueBytes);
        }

        // Automatic recovery is ON by default - the library's own two seconds -
        // because the far end of a Modbus link is a device that gets rebooted.
        // A positive figure paces it differently; -1 hands the decision back to
        // the application and the link then stays down until CONNECT is cycled.
        if ((int32_t)fbReconnectMs > 0) {
            mb->reconnectAfter((mb_time_t)(int32_t)fbReconnectMs);
        } else if ((int32_t)fbReconnectMs < 0) {
            mb->reconnectAfter(0);
        }
        if (fbVendor.length() > 0 || fbProduct.length() > 0 || fbRevision.length() > 0) {
            mb->identity(fbVendor.c_str(), fbProduct.c_str(), fbRevision.c_str());
        }

        const uint32_t baud = ((int32_t)SERIAL_BAUD > 0) ? (uint32_t)(int32_t)SERIAL_BAUD : 19200u;
        const uint16_t tcpPort =
            ((uint16_t)TCP_PORT != 0) ? (uint16_t)TCP_PORT : MODBUS_TCP_PORT;
        const bool asServer = (role == MODBUS_ROLE::MODBUS_ROLE_SERVER) ||
                              (role == MODBUS_ROLE::MODBUS_ROLE_BOTH);
        const bool asClient = (role == MODBUS_ROLE::MODBUS_ROLE_CLIENT) ||
                              (role == MODBUS_ROLE::MODBUS_ROLE_BOTH);

        // A server with nothing to serve. Said plainly rather than answering
        // every request with an exception for a reason nobody could see.
        const MbServeFn serve = (MbServeFn)(uintptr_t)(strucpp::XWORD_t)fbServe;
        if (asServer && !serve) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            LAST_ERROR = "a server needs a MODBUS_MAP or MODBUS_IDENTITY block";
            return;
        }

        bool opened = false;

#if defined(MODBUS_PLATFORM_HOST)
        if (onSerial) {
            if (SERIAL_DEVICE.length() == 0) {
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                LAST_ERROR = "no serial device named";
                return;
            }
            // The pins are members of this instance, so their buffers outlive
            // the scan and the transport may hold them.
            const ModbusParity parity = (ModbusParity)(MODBUS_PARITY)SERIAL_PARITY;
            opened = (wanted == MB_KIND_ASCII)
                ? ((ModbusASCII*)mb)->begin(SERIAL_DEVICE.c_str(), baud, parity)
                : ((ModbusRTU*)mb)->begin(SERIAL_DEVICE.c_str(), baud, parity);
        } else {
            ModbusTCP* tcp = (ModbusTCP*)mb;
            tcp->rtuOverTcp(frame == MODBUS_FRAMING::MODBUS_FRAMING_RTU);

            // TCP_HOST empty means be a server. Saying it that way rather than with
            // another pin keeps the two impossible states - a client with
            // nowhere to connect, a server pointed at somebody - unreachable.
            const bool wantsClient = asClient && TCP_HOST.length() > 0;
            if (asServer) {
                const char* why = "";
                const MODBUS_RESULT served =
                    serve(mb, wanted, false, tcpPort, (uint8_t)fbMaxClients,
                          (mb_time_t)(int32_t)fbIdleMs, 0, opened, why);
                if (served != MODBUS_RESULT::MODBUS_OK) {
                    ERROR = true;
                    STATUS = served;
                    LAST_ERROR = why;
                    return;
                }
            }
            if (wantsClient) opened = tcp->connect(TCP_HOST.c_str(), tcpPort) || opened;
            if (!asServer && !wantsClient) {
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                LAST_ERROR = "a TCP client needs TCP_HOST; leave it empty to be a server";
                return;
            }
        }
#endif

#if defined(MODBUS_PLATFORM_ARDUINO)
        if (onSerial) {
            HardwareSerial* port = mbSerialPort((uint8_t)fbPort);
            if (port == nullptr) {
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                LAST_ERROR = "PORT is not a hardware serial on this board";
                return;
            }
            const uint32_t cfg =
                mb_serialConfig((uint8_t)(MODBUS_PARITY)SERIAL_PARITY);
#if defined(ARDUINO_ARCH_ESP32)
            // Only this core takes the pins; elsewhere they are fixed by the
            // board. And here the UART drives DE: see mb_serialBegin().
            const int de = mb_serialBegin(port, baud, cfg, (int)(int16_t)fbRxPin,
                                          (int)(int16_t)fbTxPin, (int)(int16_t)fbDePin);
#else
            port->begin(baud, cfg);
            const int de = (int)(int16_t)fbDePin;
#endif
            const uint32_t hold =
                ((int32_t)fbDeHoldUs > 0) ? (uint32_t)(int32_t)fbDeHoldUs : 2000u;
            if (wanted == MB_KIND_ASCII) {
                if (de >= 0) ((ModbusASCII*)mb)->directionPin(de, true, hold);
                opened = ((ModbusASCII*)mb)->begin(port, baud);
            } else {
                if (de >= 0) ((ModbusRTU*)mb)->directionPin(de, true, hold);
                opened = ((ModbusRTU*)mb)->begin(port, baud);
            }
        } else {
            // --- bring the network up -------------------------------
            //
            // Nobody else can: an OpenPLC program has no sketch to put a
            // setup() in, so the node does it from the pins MODBUS_ARDUINO
            // supplies.
            if (link == MODBUS_TRANSPORT::MODBUS_ARDUINO_WIFI) {
#if defined(MB_HAS_WIFI)
                if (fbIp.length() == 0) {
                    ERROR = true;
                    STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                    LAST_ERROR = "set IP, or 'dhcp' to ask for one";
                    return;
                }
                if (WiFi.status() != WL_CONNECTED) {
                    // The address is set BEFORE joining: WiFi.config() after
                    // WiFi.begin() is a lease already taken and then argued
                    // with.
                    if (!mbWantsDhcp(fbIp.c_str())) {
                        IPAddress address;
                        if (!address.fromString(fbIp.c_str())) {
                            ERROR = true;
                            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                            LAST_ERROR = "IP is not an address";
                            return;
                        }
                        WiFi.config(address, mbGatewayFor(address, fbGateway.c_str()),
                                    mbSubnetFor(fbSubnet.c_str()));
                    }
                    WiFi.begin(fbSsid.c_str(), fbPassword.c_str());
                    // Not an error yet: joining takes seconds, and WiFi.begin
                    // returns at once rather than blocking the scan. The retry
                    // timer brings us back here until it is up.
                    STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
                    LAST_ERROR = "joining the network";
                    return;
                }
#else
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                LAST_ERROR = "this board has no WiFi";
                return;
#endif
            } else {
#if defined(MB_HAS_ETHERNET)
                // The Arduino Ethernet library: a W5100 or W5500 controller on
                // SPI, which is what almost every Ethernet shield and module
                // is. An ESP32's built-in RMII PHY is a different library
                // altogether and is NOT this - see the block documentation.
                if (fbIp.length() == 0) {
                    ERROR = true;
                    STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                    LAST_ERROR = "set IP, or 'dhcp' to ask for one";
                    return;
                }

                uint8_t mac[6] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
                mbParseMac(fbMac.c_str(), mac);

                if (mbWantsDhcp(fbIp.c_str())) {
                    // DHCP BLOCKS, and by default it blocks for sixty seconds -
                    // which on a 1 ms task is not a delay, it is a stopped PLC.
                    // Bounded to one second here and retried by the node's own
                    // timer instead. A fixed address avoids the wait entirely,
                    // which is why it is what you get unless you ask for this.
                    if (Ethernet.begin(mac, 1000, 1000) == 0) {
                        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
                        LAST_ERROR = "no address from DHCP yet";
                        return;
                    }
                } else {
                    IPAddress address;
                    if (!address.fromString(fbIp.c_str())) {
                        ERROR = true;
                        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                        LAST_ERROR = "IP is not an address";
                        return;
                    }
                    // Static, and instant: no negotiation at all. The gateway
                    // is given explicitly rather than left to the library's
                    // guess, and serves as the DNS address too - nothing here
                    // resolves a name, so it is never asked.
                    const IPAddress gateway = mbGatewayFor(address, fbGateway.c_str());
                    Ethernet.begin(mac, address, gateway, gateway,
                                   mbSubnetFor(fbSubnet.c_str()));
                }

                if (Ethernet.hardwareStatus() == EthernetNoHardware) {
                    ERROR = true;
                    STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
                    LAST_ERROR = "no Ethernet controller found on SPI";
                    return;
                }
                if (Ethernet.linkStatus() == LinkOFF) {
                    STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
                    LAST_ERROR = "Ethernet cable unplugged";
                    return;
                }
#else
                ERROR = true;
                STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                LAST_ERROR = "define MODBUS_ENABLE_ETHERNET to build Ethernet in";
                return;
#endif
            }

            ModbusTCP* tcp = (ModbusTCP*)mb;
            tcp->rtuOverTcp(frame == MODBUS_FRAMING::MODBUS_FRAMING_RTU);

            const bool onWifi = (link == MODBUS_TRANSPORT::MODBUS_ARDUINO_WIFI);

            if (asServer) {
                const char* why = "";
                const MODBUS_RESULT served =
                    serve(mb, wanted, onWifi, tcpPort, (uint8_t)fbMaxClients,
                          (mb_time_t)(int32_t)fbIdleMs, 0, opened, why);
                if (served != MODBUS_RESULT::MODBUS_OK) {
                    ERROR = true;
                    STATUS = served;
                    LAST_ERROR = why;
                    return;
                }
            } else {
                if (TCP_HOST.length() == 0) {
                    ERROR = true;
                    STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
                    LAST_ERROR = "a TCP client needs TCP_HOST";
                    return;
                }
                if (!mbArduinoTransport) {
#if defined(MB_HAS_WIFI)
                    if (onWifi) {
                        mbWifiClient = new (std::nothrow) WiFiClient();
                        if (mbWifiClient) {
                            mbArduinoTransport = new (std::nothrow)
                                ModbusArduinoClientTransport<WiFiClient>(
                                    *mbWifiClient, TCP_HOST.c_str(), tcpPort);
                        }
                    }
#endif
#if defined(MB_HAS_ETHERNET)
                    if (!onWifi) {
                        mbEthClient = new (std::nothrow) EthernetClient();
                        if (mbEthClient) {
                            mbArduinoTransport = new (std::nothrow)
                                ModbusArduinoClientTransport<EthernetClient>(
                                    *mbEthClient, TCP_HOST.c_str(), tcpPort);
                        }
                    }
#endif
                }
                if (!mbArduinoTransport) {
                    ERROR = true;
                    STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
                    LAST_ERROR = "out of memory";
                    return;
                }
                opened = tcp->connect(*mbArduinoTransport);
            }
        }
#endif

        if (opened && onSerial && asServer) {
            const char* why = "";
            const MODBUS_RESULT served =
                serve(mb, wanted, false, tcpPort, 0, 0, (uint8_t)SERIAL_UNIT_ID, opened, why);
            if (served != MODBUS_RESULT::MODBUS_OK) {
                ERROR = true;
                STATUS = served;
                LAST_ERROR = why;
                return;
            }
        }

        if (!opened) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            LAST_ERROR = mb->lastError();
            return;
        }

        READY = true;
        ERROR = false;
        STATUS = MODBUS_RESULT::MODBUS_OK;
        LAST_ERROR = "";
    }

    if (!mb) return;

    const bool resetRose = (bool)RESET_STATS && !(bool)fbResetSeen;
    fbResetSeen = (bool)RESET_STATS;
    if (resetRose) mb->resetStats();

    // Once per call, from the block that owns the node. Everything the
    // protocol does - transmitting, receiving, retrying, timing out - happens
    // here and nowhere else.
    mb->poll();

    CONNECTED = mb->connected();

    // Zero on a serial segment, which has a bus rather than connections.
    CLIENTS = (int16_t)mb->clients();
}

END_FUNCTION_BLOCK