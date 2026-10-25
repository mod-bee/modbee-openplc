(* Starts a BeeBus node, and is the node every other block takes.

NODE_ID    1..254, unique on the ring.
TRANSPORT  which link. BEEBUS_NODE_RUNTIME_UDP unless you say otherwise.
           BEEBUS_NODE_RUNTIME_UDP, BEEBUS_NODE_RUNTIME_SERIAL, BEEBUS_NODE_ARDUINO_SERIAL,
           BEEBUS_NODE_ARDUINO_WIFI, BEEBUS_NODE_ARDUINO_ETHERNET
DEVICE     the serial device, e.g. /dev/ttyUSB0.
BAUD       0 for the transport's default.
GROUP      multicast group, empty for the protocol's own.
UDP_PORT   0 for the protocol's own.
TTL        multicast hops, 0 for the default. 1 keeps it on this subnet.
IFACE      the interface address to send from, empty to let the host choose.
PORT       which hardware serial port, 0 for the first.
RX_PIN     receive pin, -1 for the board's own. ESP32 only.
TX_PIN     transmit pin, -1 for the board's own. ESP32 only.
WIFI_SSID  the network to join.
PASSWORD   its password. Up to 63 characters, the most WPA2 allows.
MAC        six hex bytes, empty for a built-in default. Ethernet only, and
           the Arduino Ethernet library must be installed.
IP         a fixed address, empty for DHCP. Prefer a fixed address: DHCP
           blocks while it asks, so each attempt is bounded to a second and
           LINK stays false until a lease arrives.
FAILSAFE   apply each register's safe value when the owner goes silent.
CONNECT    be in the ring. TRUE unless you say otherwise, which is what almost
           every node wants — leave it unwired and the node joins and stays.

           Drop it to FALSE and the node disconnects: it stops taking the
           token and the peers see it go, which is what a node that wakes,
           reports and sleeps again wants. Raise it and the node rejoins.

           Bindings survive the gap: topics and registers stay bound, so
           nothing is registered again on waking and a subscriber's stream
           picks up where it left off.
QUEUE      how many requests (reads, writes, subscriptions) and how many
           answers can wait for the token at once, 1..255. 0, the default,
           is 16 on a board and 50 on the Runtime. Past it a request is
           refused with BEEBUS_QUEUE_FULL and its block asks again next scan;
           raise it for a node that keeps many requests in flight. Raise it
           on the node that answers too: a peer asking for more at once than
           this node can queue answers to loses the answers past it. Each
           place costs about 300 bytes of RAM, taken when the node starts:
           too many for the memory and the node does not start, LAST_ERROR
           saying so.

READY       the node started.
LINK        the network is up. WiFi and Ethernet only.
CONNECTED   in the ring, holding a place in the rotation.
ERROR       the node did not start, or has stood down.
STATUS      why. BEEBUS_OK when fine.
            BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
            BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
            BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
            BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
            BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
            BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED,
            BEEBUS_BUFFER_FULL

            BEEBUS_DUPLICATE_NODE_ID is the one to know: another device on this
            segment is transmitting under NODE_ID, so this node takes no token,
            claims no address and refuses every read and write. Without it that
            reads exactly like a node still starting up. It clears by itself
            once the other device stops, or on a rising edge of CONNECT.
LAST_ERROR  what failed, in the operating system's own words — "could not
            open serial device: No such file or directory", "could not join
            multicast group: No such device". Text, because that is the whole
            value of it: a code cannot say which of forty things went wrong at
            the socket. A setting that is wrong says which: "NODE_ID must be
            1..254", "no serial device named". On a board it also tells the
            network faults apart: "joining the network", "Ethernet cable
            unplugged", "no address from DHCP yet", "no Ethernet controller
            found on SPI", and "set BEEBUS_ENABLE_ETHERNET to use Ethernet".
ATTEMPTS    how many times the link has been opened, or tried.
RETRY_IN    while a failed open waits to be tried again, how long until it is.
            T#0s otherwise.

---

Declare one and pass it to the other blocks on their NODE pin:

  node( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );
  rd( NODE := node, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
      VALUE := myWords );

Call it first in the scan. Blocks below it act on the same scan; a block placed
above it acts one scan later, which costs a scan and corrects itself.

TRANSPORT picks the link. Which pins matter depends on it, and the rest are
ignored:

  BEEBUS_NODE_RUNTIME_UDP     GROUP, UDP_PORT, TTL, IFACE
  BEEBUS_NODE_RUNTIME_SERIAL  DEVICE, BAUD
  BEEBUS_NODE_ARDUINO_SERIAL  PORT, BAUD, RX_PIN, TX_PIN
  BEEBUS_NODE_ARDUINO_WIFI    WIFI_SSID, PASSWORD, GROUP, UDP_PORT
  BEEBUS_NODE_ARDUINO_ETHERNET     MAC, IP, GROUP, UDP_PORT

A BEEBUS_NODE_RUNTIME_* link runs on the OpenPLC Runtime, a BEEBUS_NODE_ARDUINO_* link on a
board. Choosing one the target does not have is reported, not built.

A LINK THAT WILL NOT OPEN IS TRIED AGAIN. A USB adapter plugged in after
boot, a network that comes up after the PLC, a port another program is
holding: STATUS reads BEEBUS_NOT_INITIALISED, LAST_ERROR says why, and the open
is tried again 1 s later, then 2, 4, 8, 16, and every 30 s from then on.
RETRY_IN counts down to the next try and ATTEMPTS counts them. The moment it
opens, ERROR clears and READY is set; nothing in the program has to do it.

A WRONG SETTING IS NOT RETRIED, because trying again cannot fix it: a link the
target does not have, NODE_ID 0 or 255, a serial link with no DEVICE, a
PORT the board has not got. STATUS reads BEEBUS_INVALID_ARGUMENT and LAST_ERROR
names the setting. Correct it and the link opens - no restart.

SETTINGS MAY CHANGE WHILE IT RUNS. NODE_ID, TRANSPORT, DEVICE, BAUD, GROUP,
UDP_PORT, TTL, IFACE, FAILSAFE, QUEUE and everything BEEBUS_ARDUINO sets (PORT, the
pins, the Wi-Fi login, MAC, IP) are read every scan. A change leaves the ring
and opens again with the new ones, on the same node: every register, topic
and subscription the other blocks bound stays bound, and the node's peers
subscribe again when it returns under its new ID. *)

FUNCTION_BLOCK BEEBUS_NODE
  VAR_INPUT
    NODE_ID : BYTE;
    TRANSPORT : BEEBUS_NODE_LINK;
    DEVICE : STRING(32);
    BAUD : DINT;
    GROUP : STRING(32);
    UDP_PORT : UINT;
    TTL : BYTE;
    IFACE : STRING(32);
    FAILSAFE : BOOL;
    CONNECT : BOOL := TRUE;
    QUEUE : USINT;
  END_VAR
  VAR_OUTPUT
    READY : BOOL;
    LINK : BOOL;
    CONNECTED : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    LAST_ERROR : STRING(80);
    ATTEMPTS : UDINT;
    RETRY_IN : TIME;
  END_VAR
  VAR
    api : __XWORD;
    wanted : BOOL;

    (* One scan passes before the link opens, so a helper block beside this one
       has run whatever its place in the rung. *)
    fbSettled : BOOL;
    fbTried : BOOL;

    (* What BEEBUS_ARDUINO sets, holding the defaults the pins used to. A node
       with no helper beside it behaves exactly as it always did. *)
    fbPort : BYTE;
    fbRxPin : INT := -1;
    fbTxPin : INT := -1;
    fbWifiSsid : STRING(32);
    fbPassword : STRING(63);
    fbMac : STRING(32);
    fbIp : STRING(32);
    fbRetryAt : UDINT;
    fbBackoff : UDINT;
    fbWaiting : BOOL;
    (* The settings the link was opened with, as one short fingerprint: NODE_ID,
       TRANSPORT and the line's or the socket's settings, and BEEBUS_ARDUINO's.
       A change re-opens the link under the same node, so every register and
       topic the other blocks bound stays bound. *)
    fbSettingsKey : UDINT;
    fbRebind : BOOL;
    fbChangeAt : UDINT;
    (* The transport this block made (the Runtime's, a board's UDP), freed when
       a settings change replaces it. A board's serial line is the node's own. *)
    fbTransport : __XWORD;
    fbOpenPort : BYTE := 255;
    (* The task this block runs in, for the blocks given it: see BEEBUS_ARDUINO, "ONE TASK PER NODE". *)
    fbTask : __XWORD;
  END_VAR
#include <BeeBusAPI.h>
#include <atomic>
#include <new>

#if defined(BEEBUS_PLATFORM_HOST)
#include <transport/BeeBusHostSerialTransport.h>
#include <transport/BeeBusHostUdpTransport.h>
#endif

#if defined(BEEBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// WiFi is detected: it ships inside the ESP32 core, so its header is already
// on the include path and __has_include can answer honestly. BEEBUS_NO_WIFI
// forces it off for a board that has none.
#if !defined(BEEBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define BEEBUS_HAS_WIFI 1
#include <WiFi.h>
#include <WiFiUdp.h>
#endif
#endif

// Ethernet is opt-in, and cannot be detected the same way. arduino-cli finds a
// user library by compiling, failing on the missing header, and then searching
// for whatever provides it -- so the include has to be one the compiler will
// actually try. Behind __has_include there is no failure to react to, the path
// is never added, and the header stays invisible however installed it is.
//
// Add BEEBUS_ENABLE_ETHERNET to the project's build flags to use it.
#if defined(BEEBUS_ENABLE_ETHERNET)
#define BEEBUS_HAS_ETHERNET 1
#include <Ethernet.h>
#include <EthernetUdp.h>
#endif

#include <transport/BeeBusArduinoUdpTransport.h>

#if defined(BEEBUS_HAS_ETHERNET)
// Six hex bytes with any separator, into the array Ethernet.begin takes.
static bool bbParseMac(const char* text, uint8_t out[6])
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

// The board's hardware serials, by the number the PORT pin gives. Not every
// board has all of them, which is why this is a switch and not an array. A
// number the board does not have is refused (nullptr), never quietly opened on
// UART0: on the ModBee Node UART0 is the HAT port, where a modem sits.
static HardwareSerial* bbSerialPort(uint8_t port)
{
  switch (port) {
    case 0:
#if defined(ARDUINO_ARCH_ESP32) && defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
      // This core boots Serial as the USB CDC device rather than a UART, so it
      // is not a HardwareSerial at all. Serial0 is UART0 and is always declared.
      return &Serial0;
#else
      return &Serial;
#endif
#if defined(SERIAL_PORT_HARDWARE_OPEN) || defined(HAVE_HWSERIAL1) || defined(ARDUINO_ARCH_ESP32)
    case 1: return &Serial1;
#endif
#if defined(HAVE_HWSERIAL2) || defined(ARDUINO_ARCH_ESP32)
    case 2: return &Serial2;
#endif
    default: return nullptr;
  }
}
#endif

// The wire type an IEC type class names, or BEEBUS_T_COUNT for one the wire
// does not carry. Defined here rather than in the protocol, which knows nothing
// about a toolchain; every project has a node, so every project has this.
// --- reading and writing a TIME pin --------------------------------------
//
// Every duration on every block is a TIME, so that T#500ms on one of these
// reads the same as T#500ms on a TON beside it. TIME is signed nanoseconds
// here and unsigned milliseconds in CODESYS, so nothing relies on a negative:
// below zero is treated as none at all. Rounded UP, because 0 means "the
// sensible default" on these pins and a value somebody set must not vanish.
int32_t bb_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = t.get();
    if (ns <= 0) return 0;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 2147483647LL ? 2147483647 : (int32_t)ms;
}

// And the way back, for an age or a hop time reported on a pin. A negative
// count - which here means "it has never happened" - comes out as T#0s,
// because TIME is unsigned in CODESYS and a pin showing a negative duration
// would be a lie about a type. The pin beside it says which zero it is:
// ALIVE, or QUALITY reading BEEBUS_TP_UNKNOWN.
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds)
{
    if (milliseconds <= 0) return strucpp::IEC_TIME((strucpp::TIME_t)0);
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

uint8_t bb_wireTypeOfClass(uint32_t typeClass)
{
  switch (typeClass) {
    case strucpp::TYPE_CLASS::TYPE_BOOL:   return BEEBUS_T_BOOL;
    case strucpp::TYPE_CLASS::TYPE_SINT:   return BEEBUS_T_I8;
    case strucpp::TYPE_CLASS::TYPE_BYTE:
    case strucpp::TYPE_CLASS::TYPE_USINT:  return BEEBUS_T_U8;
    case strucpp::TYPE_CLASS::TYPE_INT:    return BEEBUS_T_I16;
    case strucpp::TYPE_CLASS::TYPE_WORD:
    case strucpp::TYPE_CLASS::TYPE_UINT:   return BEEBUS_T_U16;
    case strucpp::TYPE_CLASS::TYPE_DINT:   return BEEBUS_T_I32;
    case strucpp::TYPE_CLASS::TYPE_DWORD:
    case strucpp::TYPE_CLASS::TYPE_UDINT:  return BEEBUS_T_U32;
    case strucpp::TYPE_CLASS::TYPE_REAL:   return BEEBUS_T_F32;
    case strucpp::TYPE_CLASS::TYPE_STRING: return BEEBUS_T_STRING;
    // The 64-bit types, bound in place. LTIME is IEC 61131-3's signed 64-bit
    // count of nanoseconds (2013, table 10 note m), which is what it holds.
    case strucpp::TYPE_CLASS::TYPE_LINT:
    case strucpp::TYPE_CLASS::TYPE_LTIME:  return BEEBUS_T_I64;
    case strucpp::TYPE_CLASS::TYPE_LWORD:
    case strucpp::TYPE_CLASS::TYPE_ULINT:  return BEEBUS_T_U64;
    case strucpp::TYPE_CLASS::TYPE_LREAL:  return BEEBUS_T_F64;
    default: break;
  }
  return BEEBUS_T_COUNT;
}

// BEEBUS_RESULT mirrors BeeBusResult member for member, so every block casts
// rather than translates. Asserted here because every project has a node.
static_assert((int)BEEBUS_RESULT::BEEBUS_BUFFER_FULL + 1 == BEEBUS_RESULT_COUNT,
              "BEEBUS_RESULT must mirror BeeBusResult member for member");

// The node this block owns. Held as a pointer-wide word because that is what a
// pin can carry; every other block reaches it through this block's instance.
static BeeBusAPI* bbApi(strucpp::IEC_XWORD& slot)
{
  return (BeeBusAPI*)(uintptr_t)(strucpp::XWORD_t)slot;
}


// =============================================================================
// A VARIABLE AS A LIST OF VALUES - the engine under every block that takes a
// STRUCT, an array or a single value on its VALUE pin.
// =============================================================================
//
// A STRUCT arrives on an ANY pin as an address and a layout (TYPEDESC, which
// STruC++ emits beside every STRUCT type). The layout names each member, its
// offset and its type, nested STRUCTs and arrays included. Walking it gives a
// flat list of values in declaration order, and that list is the whole design:
//
//   - its ORDER is the register order and the topic order,
//   - each value's PATH ("hmi.systemMode", "spareReal[3]") is its name,
//   - each value's TYPE fixes its width on the wire.
//
// The list is held in "runs": a scalar member is a run of one, an array of a
// simple type is one run of all its elements, and an array of STRUCTs is
// unrolled element by element. A 1000-element WORD array is therefore one
// entry, not a thousand.
//
// Defined here, in the block every project has, and reached from the other
// blocks through the bb_plan* functions below: every C++ POU lands in one
// translation unit in filename order, so a block sorting before this one sees
// declarations, never this file's types.
//
// Names number array elements by POSITION, counting from 1, whatever the
// declared bounds: the layout carries the element count but not the bounds.
// ARRAY[1..n], the usual declaration, reads exactly as declared.

#include <new>
#include <utility>

namespace {

// How a value reaches the wire when it is not already a wire type.
enum BbConv : uint8_t {
  BB_CONV_NONE = 0,   // bound in place
  BB_CONV_MS,         // TIME, TOD: nanoseconds <-> DINT milliseconds
  BB_CONV_DT,         // DT: nanoseconds since 1970 <-> UDINT seconds since 1970
  BB_CONV_DATE,       // DATE: days since 1970 <-> UDINT seconds since 1970
};

// A path is as long as this at most ("pumps[2].motor.fault"): one character
// past the longest topic name, so a path cut short here is always refused as a
// topic name too long, never carried cut. Only a diagnostic name shows it.
static const size_t BB_PATH_MAX = BEEBUS_TOPIC_NAME_MAX + 1;

struct BbRun {
  uint32_t path = 0;         // its path in BbPlan::paths, e.g. "hmi.systemMode"
  bool array = false;        // elements are named path[k], k from 1
  uint8_t* base = nullptr;   // the first element's payload
  uint32_t stride = 0;       // bytes from one element to the next
  uint32_t count = 1;        // elements
  uint32_t iecClass = 0;     // strucpp::TYPE_CLASS of an element
  uint8_t wire = 0;          // BEEBUS_T_*
  uint8_t conv = BB_CONV_NONE;
  uint16_t cap = 0;          // STRING(n): n
  uint16_t regsEach = 1;     // registers (or bits) one element takes
  uint32_t firstLeaf = 0;    // number of element 0 in the whole list, from 0
  uint32_t firstReg = 0;     // its register offset from the block's ADDRESS
  // A converted type is bound to a copy in its wire type, held in the plan's
  // shadow array from here on. `synced` (after the shadows) is what each copy
  // held when it was last brought into line with the variable, so a change in
  // it that the program did not make is a peer's.
  uint32_t shadow = 0;
};

// Everything a plan holds is taken when it is built or bound, never while it
// serves: the runs and their paths in one pass over the layout once they are
// counted, the topic names and counters when the topics are bound, the peer
// buffers on the first read or write.
struct BbPlan {
  BbRun* runs = nullptr;
  uint32_t runCount = 0;
  char* paths = nullptr;     // every run's path, NUL separated; "" is the root
  int32_t* shadows = nullptr;   // converted copies, then their synced values
  uint32_t shadowCount = 0;
  uint32_t leaves = 0;       // values in the list
  uint32_t regs = 0;         // registers (or bits) they take
  uint8_t* root = nullptr;   // the variable's address when the plan was made
  const char* rootName = "VALUE";   // the variable's own name, for a single value
  bool rootArray = false;           // VALUE is an ARRAY: topics named from "[i]" on
  bool bits = false;         // laid out for a coil or discrete-input table

  // Registers this node holds (BEEBUS_MB_MAP)
  bool bound = false;
  BeeBusRegisterType table = MB_HOLDING_REGISTER;
  uint16_t address = 0;
  uint32_t since = 0;        // registerWritesSince cursor

  // Topics (BEEBUS_TP_STRUCT, BEEBUS_TP_STRUCT_SUBSCRIBE)
  bool topics = false;
  bool remote = false;
  uint8_t peer = 0;
  uint16_t topicId = 0;
  char* names = nullptr;     // every value's name, NUL separated, never moved
  uint8_t* state = nullptr;  // per value: BB_ISSUED, BB_ARRIVED
  uint16_t* seen = nullptr;  // per value: received, then missed

  // A peer's registers, read or written (BEEBUS_MB_READ, BEEBUS_MB_WRITE)
  int16_t* regBuf = nullptr;
  uint8_t* bitBuf = nullptr; // bool-sized, so a bool* can walk it
  uint32_t ioLeaves = 0;     // values the outstanding request covers

  // Writes taken from the node's queue (BEEBUS_TP_STRUCT WRITABLE)
  void* wq = nullptr;        // the node's BbWq
  uint16_t wqRange = 0;      // this STRUCT's place in it
  // Momentary commands waiting to drop back to FALSE: room for every BOOL
  // member, taken when the writes are queued.
  uint32_t* pulseLeaf = nullptr;
  uint32_t* pulseAt = nullptr;
  uint32_t pulseCap = 0;
  uint32_t pulses = 0;
  // Writes taken this scan, told to the node once the queue's lock is let go
  // (topicApplied), so a write that asked for a result is read back. Room for
  // every member, taken when the writes are queued.
  uint16_t* appliedIds = nullptr;
  uint8_t* appliedCmd = nullptr;
  uint16_t settleMs = 0;     // the read-back's delay after the next scan
  bool command = false;      // every member is a command: answered once taken

  // Binds (BEEBUS_TP_BIND): the bound members' last states
  bool binds = false;

  ~BbPlan() {
    delete[] runs;
    delete[] paths;
    delete[] shadows;
    delete[] names;
    delete[] state;
    delete[] seen;
    delete[] regBuf;
    delete[] bitBuf;
    delete[] pulseLeaf;
    delete[] pulseAt;
    delete[] appliedIds;
    delete[] appliedCmd;
  }
};

enum : uint8_t { BB_ISSUED = 0x01, BB_ARRIVED = 0x02 };

const char* bbClassName(uint32_t cls)
{
  switch (cls) {
    case strucpp::TYPE_CLASS::TYPE_WSTRING: return "WSTRING";
    case strucpp::TYPE_CLASS::TYPE_POINTER: return "a POINTER";
    case strucpp::TYPE_CLASS::TYPE_REFERENCE: return "a REFERENCE";
    case strucpp::TYPE_CLASS::TYPE_ARRAY: return "an array of arrays";
    default: return "a type";
  }
}

// The wire type a value of this class travels as, and how it is converted.
bool bbLeafType(uint32_t cls, uint32_t bytes, uint8_t& wire, uint8_t& conv)
{
  conv = BB_CONV_NONE;
  switch (cls) {
    case strucpp::TYPE_CLASS::TYPE_BOOL:   wire = BEEBUS_T_BOOL; return true;
    case strucpp::TYPE_CLASS::TYPE_SINT:   wire = BEEBUS_T_I8;   return true;
    case strucpp::TYPE_CLASS::TYPE_BYTE:
    case strucpp::TYPE_CLASS::TYPE_USINT:  wire = BEEBUS_T_U8;   return true;
    case strucpp::TYPE_CLASS::TYPE_INT:    wire = BEEBUS_T_I16;  return true;
    case strucpp::TYPE_CLASS::TYPE_WORD:
    case strucpp::TYPE_CLASS::TYPE_UINT:   wire = BEEBUS_T_U16;  return true;
    case strucpp::TYPE_CLASS::TYPE_DINT:   wire = BEEBUS_T_I32;  return true;
    case strucpp::TYPE_CLASS::TYPE_DWORD:
    case strucpp::TYPE_CLASS::TYPE_UDINT:  wire = BEEBUS_T_U32;  return true;
    case strucpp::TYPE_CLASS::TYPE_REAL:   wire = BEEBUS_T_F32;  return true;
    case strucpp::TYPE_CLASS::TYPE_STRING: wire = BEEBUS_T_STRING; return true;
    case strucpp::TYPE_CLASS::TYPE_LINT:   wire = BEEBUS_T_I64;  return true;
    case strucpp::TYPE_CLASS::TYPE_LWORD:
    case strucpp::TYPE_CLASS::TYPE_ULINT:  wire = BEEBUS_T_U64;  return true;
    case strucpp::TYPE_CLASS::TYPE_LREAL:  wire = BEEBUS_T_F64;  return true;
    // IEC 61131-3 (2013, table 10 note m): a signed 64-bit count of
    // nanoseconds, which is what STruC++ stores, so it is bound in place.
    case strucpp::TYPE_CLASS::TYPE_LTIME:  wire = BEEBUS_T_I64;  return true;
    case strucpp::TYPE_CLASS::TYPE_TIME:
    case strucpp::TYPE_CLASS::TYPE_TIMEOFDAY:
      wire = BEEBUS_T_I32; conv = BB_CONV_MS; return true;
    case strucpp::TYPE_CLASS::TYPE_DATEANDTIME:
      wire = BEEBUS_T_U32; conv = BB_CONV_DT; return true;
    case strucpp::TYPE_CLASS::TYPE_DATE:
      wire = BEEBUS_T_U32; conv = BB_CONV_DATE; return true;
    case strucpp::TYPE_CLASS::TYPE_ENUM:
      // An enumeration travels as the integer it is stored as.
      if (bytes == 1) { wire = BEEBUS_T_I8;  return true; }
      if (bytes == 2) { wire = BEEBUS_T_I16; return true; }
      if (bytes == 4) { wire = BEEBUS_T_I32; return true; }
      if (bytes == 8) { wire = BEEBUS_T_I64; return true; }
      return false;
    default:
      return false;
  }
}

// The path being walked, one segment per level, and what the walk produces.
// The layout is walked twice: once to count the runs and the bytes their paths
// need (and to find any member that cannot be carried), then to fill storage
// taken once.
struct BbWalk {
  BbPlan& p;
  bool fill;                 // the second pass
  char path[BB_PATH_MAX];
  size_t len = 0;
  uint32_t runs = 0;
  uint32_t pathBytes = 0;
  uint32_t shadows = 0;
  char* err;
  size_t errCap;
  BbWalk(BbPlan& plan, bool second, char* e, size_t cap)
      : p(plan), fill(second), err(e), errCap(cap) { path[0] = '\0'; }

  // Appends text to the path; returns where it was, to put back.
  size_t push(const char* text) {
    const size_t mark = len;
    const int n = snprintf(path + len, sizeof(path) - len, "%s", text);
    if (n > 0) len = (len + (size_t)n < sizeof(path)) ? len + (size_t)n : sizeof(path) - 1;
    return mark;
  }
  size_t pushIndex(uint32_t position) {
    char index[16];
    snprintf(index, sizeof(index), "[%lu]", (unsigned long)position);
    return push(index);
  }
  void pop(size_t mark) { len = mark; path[len] = '\0'; }
  // The name to show for the path walked so far.
  const char* shown() const { return len ? path : p.rootName; }
};

// A path that ends in "." while a STRUCT is being entered.
bool bbAddRun(BbWalk& w, bool array, uint8_t* base, uint32_t stride, uint32_t count,
              uint32_t cls, uint32_t bytes, uint16_t cap)
{
  BbPlan& p = w.p;
  uint8_t wire = 0, conv = BB_CONV_NONE;
  if (!bbLeafType(cls, bytes, wire, conv)) {
    snprintf(w.err, w.errCap, "%s is %s, which BeeBus does not carry", w.shown(),
             bbClassName(cls));
    return false;
  }
  if (p.bits && wire != BEEBUS_T_BOOL) {
    snprintf(w.err, w.errCap, "%s is not a BOOL; a coil or input table holds BOOLs only",
             w.shown());
    return false;
  }
  uint16_t regsEach;
  if (wire == BEEBUS_T_STRING) {
    if (cap == 0) {
      snprintf(w.err, w.errCap, "%s: an ARRAY OF STRING needs a STRUCT around it", w.shown());
      return false;
    }
    regsEach = (uint16_t)(cap / 2 + 1);   // n characters and the terminator
  } else {
    regsEach = p.bits ? 1 : bb_registersOf(wire);
  }

  if (w.fill) {
    BbRun& r = p.runs[w.runs];
    r.path = w.pathBytes;
    memcpy(p.paths + w.pathBytes, w.path, w.len + 1);
    r.array = array;
    r.base = base;
    r.stride = stride;
    r.count = count;
    r.iecClass = cls;
    r.wire = wire;
    r.conv = conv;
    r.cap = cap;
    r.regsEach = regsEach;
    r.firstLeaf = p.leaves;
    r.firstReg = p.regs;
    r.shadow = w.shadows;
  }
  w.runs++;
  w.pathBytes += (uint32_t)w.len + 1;
  if (conv != BB_CONV_NONE) w.shadows += count;
  p.leaves += count;
  p.regs += count * regsEach;
  return true;
}

bool bbWalkStruct(BbWalk& w, const strucpp::TypeDesc* d, uint8_t* base, int depth)
{
  if (!d) {
    snprintf(w.err, w.errCap, "%s: no layout for this STRUCT", w.shown());
    return false;
  }
  if (depth > 8) {
    snprintf(w.err, w.errCap, "%s: STRUCTs nested deeper than 8", w.path);
    return false;
  }
  for (uint16_t i = 0; i < d->MEMBERCOUNT; i++) {
    const strucpp::MemberDesc& m = d->MEMBERS[i];
    const size_t mark = w.push(m.NAME ? m.NAME : "?");
    uint8_t* at = base + m.BYTEOFFSET;
    bool ok;

    if (m.TYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
      const size_t dot = w.push(".");
      ok = bbWalkStruct(w, m.NESTED, at, depth + 1);
      w.pop(dot);
    } else if (m.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY) {
      if (m.BASETYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
        ok = true;
        for (uint32_t e = 0; ok && e < m.NUMELEMENTS; e++) {
          const size_t element = w.pushIndex(e + 1);
          w.push(".");
          ok = bbWalkStruct(w, m.NESTED, at + (size_t)e * m.STRIDE, depth + 1);
          w.pop(element);
        }
      } else {
        ok = bbAddRun(w, true, at, m.STRIDE, m.NUMELEMENTS, m.BASETYPECLASS,
                      m.ELEMBITSIZE / 8, m.CAP);
      }
    } else {
      ok = bbAddRun(w, false, at, m.STRIDE, 1, m.TYPECLASS, m.BITSIZE / 8, m.CAP);
    }
    w.pop(mark);
    if (!ok) return false;
  }
  return true;
}

// One pass over whatever is on the VALUE pin.
bool bbWalkValue(BbWalk& w, const strucpp::IEC_ANY& v)
{
  if (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
    return bbWalkStruct(w, v.TYPEDESC, v.PVALUE, 0);
  }
  if (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY) {
    if (v.ELEMCLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
      for (int32_t e = 0; e < v.DICOUNT; e++) {
        const size_t mark = w.push(w.p.rootName);
        w.pushIndex((uint32_t)e + 1);
        w.push(".");
        const bool ok = bbWalkStruct(w, v.TYPEDESC, v.PVALUE + (size_t)e * (size_t)v.DISTRIDE, 0);
        w.pop(mark);
        if (!ok) return false;
      }
      return true;
    }
    const uint32_t bytes = (uint32_t)(v.DISIZE / v.DICOUNT);
    return bbAddRun(w, true, v.PVALUE, (uint32_t)v.DISTRIDE, (uint32_t)v.DICOUNT,
                    v.ELEMCLASS, bytes, 0);
  }
  // A STRING's DISIZE is its buffer, the capacity and the terminator.
  const uint16_t cap = (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING && v.DISIZE > 1)
      ? (uint16_t)(v.DISIZE - 1) : 0;
  return bbAddRun(w, false, v.PVALUE, (uint32_t)v.DISTRIDE, 1, v.TYPECLASS,
                  (uint32_t)v.DISIZE, cap);
}

BbRun* bbRunOf(BbPlan& p, uint32_t leaf, uint32_t& element)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (leaf >= r.firstLeaf && leaf < r.firstLeaf + r.count) {
      element = leaf - r.firstLeaf;
      return &r;
    }
  }
  return nullptr;
}

// A value's name, written into `out`: its path, numbered from 1 in an array.
// As a topic (`topic`), a VALUE that is itself an ARRAY is named from the
// element on - "[3].set.delay", "[3]" - without the variable's own name:
// PREFIX names the array, so the subscriber's variable need not be spelled as
// the owner's. Registers keep the variable's name, which only diagnostics show.
void bbLeafName(const BbPlan& p, const BbRun& r, uint32_t element, const char* prefix,
                bool topic, char* out, size_t cap)
{
  if (!out || cap == 0) return;
  const char* path = p.paths[r.path] ? p.paths + r.path : p.rootName;
  if (topic && p.rootArray) {
    const size_t root = strlen(p.rootName);
    if (strncmp(path, p.rootName, root) == 0) path += root;
  }
  if (r.array) {
    snprintf(out, cap, "%s%s[%lu]", prefix ? prefix : "", path, (unsigned long)(element + 1));
  } else {
    snprintf(out, cap, "%s%s", prefix ? prefix : "", path);
  }
}

uint8_t* bbElem(const BbRun& r, uint32_t e) { return r.base + (size_t)e * r.stride; }

int32_t& bbShadow(BbPlan& p, const BbRun& r, uint32_t e) { return p.shadows[r.shadow + e]; }
int32_t& bbSynced(BbPlan& p, const BbRun& r, uint32_t e)
{
  return p.shadows[p.shadowCount + r.shadow + e];
}

// The variable's value in its wire form, for a converted type.
int32_t bbToWire(const BbRun& r, uint32_t e)
{
  int64_t v;
  memcpy(&v, bbElem(r, e), 8);
  switch (r.conv) {
    case BB_CONV_MS: {
      // Rounded to the nearest millisecond and held inside a DINT.
      const int64_t ms = v >= 0 ? (v + 500000LL) / 1000000LL : -((-v + 500000LL) / 1000000LL);
      if (ms > 2147483647LL) return 2147483647;
      if (ms < -2147483647LL - 1) return (int32_t)(-2147483647LL - 1);
      return (int32_t)ms;
    }
    case BB_CONV_DT: {
      const int64_t s = v / 1000000000LL;
      return (int32_t)(uint32_t)(s < 0 ? 0 : (s > 0xFFFFFFFFLL ? 0xFFFFFFFFLL : s));
    }
    case BB_CONV_DATE: {
      const int64_t s = v * 86400LL;
      return (int32_t)(uint32_t)(s < 0 ? 0 : (s > 0xFFFFFFFFLL ? 0xFFFFFFFFLL : s));
    }
  }
  return 0;
}

void bbFromWire(const BbRun& r, uint32_t e, int32_t wire)
{
  int64_t v = 0;
  switch (r.conv) {
    case BB_CONV_MS:   v = (int64_t)wire * 1000000LL; break;
    case BB_CONV_DT:   v = (int64_t)(uint32_t)wire * 1000000000LL; break;
    case BB_CONV_DATE: v = (int64_t)((uint32_t)wire / 86400u); break;
    default: return;
  }
  memcpy(bbElem(r, e), &v, 8);
}

// Brings each converted copy into line with its variable. `peerWins`: a copy
// that moved since the last sync was written by a peer, and is taken into
// the variable; otherwise the variable is the truth and the copy follows.
void bbSyncShadows(BbPlan& p, bool peerWins)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (r.conv == BB_CONV_NONE) continue;
    for (uint32_t e = 0; e < r.count; e++) {
      int32_t& shadow = bbShadow(p, r, e);
      int32_t& synced = bbSynced(p, r, e);
      if (peerWins && shadow != synced) {
        bbFromWire(r, e, shadow);
      } else {
        shadow = bbToWire(r, e);
      }
      synced = shadow;
    }
  }
}

void* bbBindingOf(BbPlan& p, BbRun& r, uint32_t e)
{
  if (r.conv != BB_CONV_NONE) return (void*)&bbShadow(p, r, e);
  return (void*)bbElem(r, e);
}

// One value's register image, written into `out` (r.regsEach registers).
void bbEncode(BbPlan& p, BbRun& r, uint32_t e, int16_t* out)
{
  if (r.wire == BEEBUS_T_STRING) {
    const char* text = (const char*)bbElem(r, e);
    const uint32_t bytes = (uint32_t)r.regsEach * 2;
    for (uint32_t k = 0; k < bytes; k += 2) {
      // The buffer is cap + 1 bytes and NUL terminated; nothing past the
      // terminator is sent, so a shorter text leaves no tail of a longer one.
      const uint8_t hi = (k < r.cap) ? (uint8_t)text[k] : 0;
      const uint8_t lo = (k + 1 < r.cap) ? (uint8_t)text[k + 1] : 0;
      out[k / 2] = (int16_t)(((uint16_t)hi << 8) | lo);
    }
    // Stop at the terminator.
    bool ended = false;
    for (uint32_t k = 0; k < bytes; k++) {
      uint16_t reg = (uint16_t)out[k / 2];
      uint8_t ch = (k % 2 == 0) ? (uint8_t)(reg >> 8) : (uint8_t)(reg & 0xFF);
      if (ch == 0) ended = true;
      if (ended) {
        reg = (k % 2 == 0) ? (uint16_t)(reg & 0x00FF) : (uint16_t)(reg & 0xFF00);
        out[k / 2] = (int16_t)reg;
      }
    }
    return;
  }
  if (r.conv != BB_CONV_NONE) bbShadow(p, r, e) = bbToWire(r, e);
  const void* v = bbBindingOf(p, r, e);
  for (uint16_t w = 0; w < r.regsEach; w++) {
    out[w] = (int16_t)bb_valueRegister(v, r.wire, (uint8_t)w);
  }
}

// The way back. False if a register holds a number the type cannot.
bool bbDecode(BbPlan& p, BbRun& r, uint32_t e, const int16_t* in)
{
  if (r.wire == BEEBUS_T_STRING) {
    char* text = (char*)bbElem(r, e);
    uint32_t k = 0;
    for (; k < r.cap; k++) {
      const uint16_t reg = (uint16_t)in[k / 2];
      const char ch = (char)((k % 2 == 0) ? (reg >> 8) : (reg & 0xFF));
      text[k] = ch;
      if (ch == '\0') break;
    }
    if (k >= r.cap) text[r.cap] = '\0';
    return true;
  }
  void* v = bbBindingOf(p, r, e);
  // Built in a scratch copy and stored only once every register fits, so a
  // refused value is left whole.
  const size_t width = bb_topicTypeSize(r.wire);
  uint8_t scratch[8];
  memcpy(scratch, v, width);
  for (uint16_t w = 0; w < r.regsEach; w++) {
    if (!bb_setValueRegister(scratch, r.wire, (uint8_t)w, (uint16_t)in[w], nullptr)) return false;
  }
  memcpy(v, scratch, width);
  if (r.conv != BB_CONV_NONE) {
    bbFromWire(r, e, bbShadow(p, r, e));
    bbSynced(p, r, e) = bbShadow(p, r, e);
  }
  return true;
}

int bbQualityRank(uint8_t q)
{
  switch ((BeeBusQuality)q) {
    case BeeBusQuality::Good:      return 0;
    case BeeBusQuality::Unknown:   return 1;
    case BeeBusQuality::Uncertain: return 2;
    case BeeBusQuality::Bad:       return 3;
  }
  return 3;
}

// The peer buffers, taken on the first read or write at the plan's full size.
bool bbPeerBuffers(BbPlan& p, bool bits)
{
  if (bits && !p.bitBuf) p.bitBuf = new (std::nothrow) uint8_t[p.regs ? p.regs : 1];
  if (!bits && !p.regBuf) p.regBuf = new (std::nothrow) int16_t[p.regs ? p.regs : 1];
  return bits ? p.bitBuf != nullptr : p.regBuf != nullptr;
}

}  // namespace

// ---- The functions the blocks call --------------------------------------

// Builds the list for whatever is on a VALUE pin. nullptr, with the reason in
// `err`, for a variable that cannot be carried: the whole variable is refused
// rather than the member skipped, because a missing member would move every
// address and topic id after it.
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap)
{
  BbPlan* p = new (std::nothrow) BbPlan();
  if (!p) {
    snprintf(err, errCap, "no memory for the list");
    return nullptr;
  }
  p->bits = bits;
  p->root = v.PVALUE;
  p->rootName = v.NAME ? v.NAME : "VALUE";
  p->rootArray = v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY;

  if (!v.PVALUE || v.DICOUNT <= 0) {
    snprintf(err, errCap, "VALUE is not wired");
    delete p;
    return nullptr;
  }

  // Counted first, so the runs, their paths and the copies are taken once.
  BbWalk count(*p, false, err, errCap);
  if (!bbWalkValue(count, v)) {
    delete p;
    return nullptr;
  }
  if (p->leaves == 0) {
    snprintf(err, errCap, "%s has no members", p->rootName);
    delete p;
    return nullptr;
  }
  p->runs = new (std::nothrow) BbRun[count.runs];
  p->paths = new (std::nothrow) char[count.pathBytes ? count.pathBytes : 1];
  p->shadowCount = count.shadows;
  p->shadows = count.shadows ? new (std::nothrow) int32_t[2 * count.shadows]() : nullptr;
  if (!p->runs || !p->paths || (count.shadows && !p->shadows)) {
    snprintf(err, errCap, "no memory for the list");
    delete p;
    return nullptr;
  }
  p->runCount = count.runs;
  p->leaves = 0;
  p->regs = 0;
  BbWalk fill(*p, true, err, errCap);
  bbWalkValue(fill, v);

  bbSyncShadows(*p, false);
  return p;
}

uint32_t bb_planLeaves(void* plan) { return plan ? ((BbPlan*)plan)->leaves : 0; }
uint32_t bb_planRegisters(void* plan) { return plan ? ((BbPlan*)plan)->regs : 0; }
bool bb_planMoved(void* plan, const strucpp::IEC_ANY& v)
{
  return plan && ((BbPlan*)plan)->root != v.PVALUE;
}

// A value's name and its register offset, by its number in the list (from 0).
bool bb_planLeafInfo(void* plan, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  uint32_t e = 0;
  BbRun* r = bbRunOf(p, leaf, e);
  if (!r) return false;
  bbLeafName(p, *r, e, "", p.topics, name, cap);
  if (regOffset) *regOffset = r->firstReg + e * r->regsEach;
  return true;
}

// The value whose registers include this offset from ADDRESS, from 0.
bool bb_planLeafAt(void* plan, uint32_t regOffset, uint32_t* leaf)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  for (uint32_t i = 0; i < p.runCount; i++) {
    const BbRun& r = p.runs[i];
    const uint32_t span = r.count * r.regsEach;
    if (regOffset >= r.firstReg && regOffset < r.firstReg + span) {
      *leaf = r.firstLeaf + (regOffset - r.firstReg) / r.regsEach;
      return true;
    }
  }
  return false;
}

// A single number (not a string, not a list), and its wire type: the one case
// with a safe value to state.
bool bb_planSingle(void* plan, uint8_t* wire)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  if (p.leaves != 1 || p.runCount != 1 || p.runs[0].wire == BEEBUS_T_STRING) return false;
  if (wire) *wire = p.runs[0].wire;
  return true;
}

// ---- Registers this node holds (BEEBUS_MB_MAP) ----

bool bb_planBindRegisters(void* plan, BeeBusAPI* node, BeeBusRegisterType table,
                          uint16_t address, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  if ((uint32_t)address + p.regs > 0x10000u) {
    snprintf(err, errCap, "the registers would run past address 65535");
    return false;
  }
  bbSyncShadows(p, false);
  uint32_t done = 0;   // leaves bound, for an undo
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint16_t at = (uint16_t)(address + r.firstReg + e * r.regsEach);
      bool ok;
      if (r.wire == BEEBUS_T_STRING) {
        // The buffer is cap + 1 bytes: n characters and the terminator.
        char* text = (char*)bbElem(r, e);
        ok = (table == MB_HOLDING_REGISTER)
            ? node->addString(at, text, (uint16_t)(r.cap + 1))
            : (table == MB_INPUT_REGISTER)
                ? node->addInputString(at, text, (uint16_t)(r.cap + 1))
                : false;
      } else {
        ok = node->addRegister(table, at, bbBindingOf(p, r, e), r.wire);
      }
      if (!ok) {
        // Undo what was bound, so a refused STRUCT leaves nothing behind.
        uint32_t left = done;
        for (uint32_t j = 0; j <= i && left > 0; j++) {
          BbRun& u = p.runs[j];
          for (uint32_t f = 0; f < u.count && left > 0; f++, left--) {
            const uint16_t back = (uint16_t)(address + u.firstReg + f * u.regsEach);
            if (u.wire == BEEBUS_T_STRING) {
              if (table == MB_HOLDING_REGISTER) node->removeString(back);
              else node->removeInputString(back);
            } else {
              node->removeRegister(table, back);
            }
          }
        }
        char leafName[BB_PATH_MAX];
        bbLeafName(p, r, e, "", false, leafName, sizeof(leafName));
        snprintf(err, errCap, "address %u (%s) is already taken", (unsigned)at, leafName);
        return false;
      }
      done++;
    }
  }
  p.bound = true;
  p.table = table;
  p.address = address;
  p.since = 0;
  node->registerWritesSince(table, address, (uint16_t)(p.regs > 0xFFFF ? 0xFFFF : p.regs), p.since);
  return true;
}

// Once a scan: takes what peers wrote into converted values, and brings the
// rest of the copies up to date. Returns how many values peers wrote since the
// last call, and the first of them (by number from 0) in `firstLeaf`.
uint16_t bb_planServe(void* plan, BeeBusAPI* node, uint32_t* firstLeaf)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, bb_tableIsWritable(p.table));
  uint16_t first = 0;
  const uint16_t written = node->registerWritesSince(
      p.table, p.address, (uint16_t)(p.regs > 0xFFFF ? 0xFFFF : p.regs), p.since, &first);
  if (written > 0 && firstLeaf) {
    uint32_t leaf = 0;
    if (bb_planLeafAt(plan, (uint32_t)(uint16_t)(first - p.address), &leaf)) *firstLeaf = leaf;
  }
  return written;
}

// ---- A peer's registers (BEEBUS_MB_READ / BEEBUS_MB_WRITE) ----

// Registers covering the first `leaves` values (all of them for 0), or 0 if
// that is more than were passed.
uint32_t bb_planRegsFor(void* plan, uint32_t leaves)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0 || leaves == p.leaves) return p.regs;
  if (leaves > p.leaves) return 0;
  uint32_t e = 0;
  BbRun* r = bbRunOf(p, leaves, e);
  return r ? r->firstReg + e * r->regsEach : 0;
}

BeeBusResult bb_planWritePeer(void* plan, BeeBusAPI* node, uint8_t peer,
                              BeeBusRegisterType table, uint16_t address,
                              uint32_t leaves, BeeBusDelivery delivery)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0) leaves = p.leaves;
  const uint32_t regs = bb_planRegsFor(plan, leaves);
  if (regs == 0 || regs > 0xFFFF) return BeeBusResult::InvalidArgument;

  if (bb_tableIsBits(table)) {
    if (!bbPeerBuffers(p, true)) return BeeBusResult::QueueFull;
    memset(p.bitBuf, 0, regs);
    uint32_t k = 0;
    for (uint32_t i = 0; i < p.runCount && k < regs; i++) {
      BbRun& r = p.runs[i];
      for (uint32_t e = 0; e < r.count && k < regs; e++, k++) {
        p.bitBuf[k] = (*(const bool*)bbElem(r, e)) ? 1 : 0;
      }
    }
    return node->writeCoilManual(peer, address, (const bool*)p.bitBuf, (uint16_t)regs,
                                 delivery, (uint16_t)sizeof(uint8_t));
  }

  if (!bbPeerBuffers(p, false)) return BeeBusResult::QueueFull;
  memset(p.regBuf, 0, regs * sizeof(int16_t));
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t at = r.firstReg + e * r.regsEach;
      if (at + r.regsEach > regs) break;
      bbEncode(p, r, e, &p.regBuf[at]);
    }
  }
  return node->writeHregManual(peer, address, p.regBuf, (uint16_t)regs, delivery,
                               (uint16_t)sizeof(int16_t));
}

BeeBusResult bb_planReadPeer(void* plan, BeeBusAPI* node, uint8_t peer,
                             BeeBusRegisterType table, uint16_t address, uint32_t leaves)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0) leaves = p.leaves;
  const uint32_t regs = bb_planRegsFor(plan, leaves);
  if (regs == 0 || regs > 0xFFFF) return BeeBusResult::InvalidArgument;
  p.ioLeaves = leaves;
  if (bb_tableIsBits(table)) {
    if (!bbPeerBuffers(p, true)) return BeeBusResult::QueueFull;
    memset(p.bitBuf, 0, regs);
    bool* into = (bool*)p.bitBuf;
    return (table == MB_OUTPUT_COIL)
        ? node->readCoilManual(peer, address, into, (uint16_t)regs, 0, (uint16_t)sizeof(uint8_t))
        : node->readIstsManual(peer, address, into, (uint16_t)regs, 0, (uint16_t)sizeof(uint8_t));
  }
  if (!bbPeerBuffers(p, false)) return BeeBusResult::QueueFull;
  memset(p.regBuf, 0, regs * sizeof(int16_t));
  return (table == MB_HOLDING_REGISTER)
      ? node->readHregManual(peer, address, p.regBuf, (uint16_t)regs, 0, (uint16_t)sizeof(int16_t))
      : node->readIregManual(peer, address, p.regBuf, (uint16_t)regs, 0, (uint16_t)sizeof(int16_t));
}

// Unpacks a finished read into the variable. False if a register held a number
// a member's type cannot (that member is left as it was).
bool bb_planReadDone(void* plan, bool bits)
{
  BbPlan& p = *(BbPlan*)plan;
  if ((bits && !p.bitBuf) || (!bits && !p.regBuf)) return false;
  bool allOk = true;
  uint32_t k = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++, k++) {
      if (k >= p.ioLeaves) return allOk;
      if (bits) {
        *(bool*)bbElem(r, e) = p.bitBuf[r.firstReg + e] != 0;
      } else if (!bbDecode(p, r, e, &p.regBuf[r.firstReg + e * r.regsEach])) {
        allOk = false;
      }
    }
  }
  return allOk;
}

// ---- Topics (BEEBUS_TP_STRUCT, BEEBUS_TP_STRUCT_SUBSCRIBE) ----

// Binds every value as a topic: this node's own (`remote` false) or `peer`'s.
// Names are PREFIX + path, ids TOPIC_ID + the value's number from 0. A STRING
// member is bound to its own buffer, n characters and the terminator.
// writable (owner only): peers may write the members (BEEBUS_TP_STRUCT WRITABLE).
bool bb_planBindTopicsEx(void* plan, BeeBusAPI* node, bool remote, uint8_t peer,
                         uint16_t topicId, const char* prefix, bool writable,
                         char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  const char* pre = prefix ? prefix : "";

  if (topicId < BEEBUS_TOPIC_ID_MIN ||
      (uint32_t)topicId + p.leaves - 1 > (uint32_t)BEEBUS_TOPIC_ID_MAX) {
    snprintf(err, errCap, "TOPIC_ID + members runs past 32767, or TOPIC_ID is 0");
    return false;
  }

  // Every name is checked, and its bytes counted, before anything is bound.
  // The node keeps a pointer to each name, so they are held here, packed end
  // to end at their own length: a 10-character name costs 11 bytes, not a
  // fixed BEEBUS_TOPIC_NAME_MAX.
  char name[BB_PATH_MAX];
  size_t nameBytes = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      bbLeafName(p, r, e, pre, true, name, sizeof(name));
      const size_t length = strlen(name);
      if (length >= BEEBUS_TOPIC_NAME_MAX) {
        // The lengths first: LAST_ERROR is shorter than the longest name.
        snprintf(err, errCap, "name too long (%u > %u): %s", (unsigned)length,
                 (unsigned)(BEEBUS_TOPIC_NAME_MAX - 1), name);
        return false;
      }
      nameBytes += length + 1;
    }
  }
  // Taken once: the node points into it from the first bind on.
  if (!p.names) p.names = new (std::nothrow) char[nameBytes];
  if (!p.names) {
    snprintf(err, errCap, "no memory for the topic names");
    return false;
  }

  if (remote && (!p.state || !p.seen)) {
    delete[] p.state;
    delete[] p.seen;
    p.state = new (std::nothrow) uint8_t[p.leaves]();
    p.seen = new (std::nothrow) uint16_t[2 * (size_t)p.leaves]();
    if (!p.state || !p.seen) {
      snprintf(err, errCap, "no memory for the topic records");
      return false;
    }
  }

  bbSyncShadows(p, false);
  uint32_t done = 0;
  char* nm = p.names;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++, nm += strlen(nm) + 1) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(topicId + leaf);
      bbLeafName(p, r, e, pre, true, nm, BEEBUS_TOPIC_NAME_MAX);
      const bool isText = r.wire == BEEBUS_T_STRING;
      void* where = isText ? (void*)bbElem(r, e) : bbBindingOf(p, r, e);
      const uint16_t textCap = isText ? (uint16_t)(r.cap + 1) : 0;
      const bool ok = remote
          ? node->registerTopicRaw(peer, id, r.wire, where, nm, textCap)
          : node->addTopicRaw(id, r.wire, where, writable, nm, textCap);
      if (!ok) {
        // Undo, so a refused STRUCT leaves no half of itself on the node.
        for (uint32_t k = 0; k < done; k++) {
          const uint16_t back = (uint16_t)(topicId + k);
          if (remote) node->unregisterTopic(peer, back);
          else node->removeTopic(back);
        }
        snprintf(err, errCap, "topic %u (%s) is already bound", (unsigned)id, nm);
        return false;
      }
      done++;
    }
  }
  p.topics = true;
  p.remote = remote;
  p.peer = peer;
  p.topicId = topicId;
  return true;
}

// Owner, once a scan: the copies follow the variable, so the node publishes
// what the program holds. A string is bound in place and needs nothing.
void bb_planPublishSync(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, false);
}

// The read-only form every other block declares.
bool bb_planBindTopics(void* plan, BeeBusAPI* node, bool remote, uint8_t peer,
                       uint16_t topicId, const char* prefix, char* err, size_t errCap)
{
  return bb_planBindTopicsEx(plan, node, remote, peer, topicId, prefix, false, err, errCap);
}

// ---- Queued writes: BEEBUS_TP_STRUCT with WRITABLE ------------------------
// A peer's write to a writable STRUCT member is not stored by the node (the
// topic is queued, BeeBusAPI::setTopicQueued): the node's written handlers put
// it in this node's queue, from the node's task, and the STRUCT block
// that owns the member takes it in its own scan — one write per member a scan,
// oldest first, as Sparkplug WRITABLE does — so a command written 1 then 0
// between two scans is seen as both. A spinlock keeps the two tasks apart;
// nothing in it allocates or blocks for longer than a copy.
//
// Every node and every writable STRUCT gets a queue; only memory limits them.
// It is sized by what the program declares, as each writable STRUCT binds
// (start-up, never while serving): a waiting write for every writable member
// at once (at least 32), a text slot for every writable STRING member (at
// least 4) as long as the longest of them, and a count of dropped writes for
// each STRUCT.
static const uint16_t BB_WQ_SIZE = 32;      // waiting writes, at least
static const uint16_t BB_WQ_TEXTS = 4;      // text slots, at least, once there is a STRING
static const uint8_t BB_WQ_PER_TOPIC = 4;   // a fifth write to one member drops its oldest
static const uint16_t BB_WQ_NO_TEXT = 0xFFFF;

struct BbWqEntry {
  uint16_t id;
  uint16_t text;   // text slot, or BB_WQ_NO_TEXT for a number
  uint8_t by;      // the writing node
  BeeBusScalar value;
};

struct BbWqRange {
  uint16_t first;     // a writable STRUCT's topics
  uint16_t count;
  uint32_t dropped;   // its writes dropped, not yet counted by its block
  uint32_t refused;   // writes the node answered CHANGED or REFUSED, not yet counted
};

struct BbWq {
  std::atomic_flag lock = ATOMIC_FLAG_INIT;
  BeeBusAPI* node = nullptr;
  BbWq* next = nullptr;          // the next node's queue
  BbWqEntry* e = nullptr;        // `size` long, `count` waiting
  uint16_t* taken = nullptr;     // bb_planTakeWrites' scratch, `size` long
  uint16_t size = 0;
  uint16_t count = 0;
  char* text = nullptr;          // `texts` slots of `textCap` bytes
  uint16_t* textLen = nullptr;   // per slot, BB_WQ_NO_TEXT when free
  uint16_t texts = 0;
  uint16_t textCap = 0;
  BbWqRange* range = nullptr;    // one per writable STRUCT
  uint16_t ranges = 0;
  uint32_t members = 0;          // writable members, every STRUCT
  uint32_t strings = 0;          // STRINGs among them
};

static BbWq* bbWqs = nullptr;    // one per node, linked

struct BbWqLock {
  BbWq& q;
  explicit BbWqLock(BbWq& queue) : q(queue) {
    while (q.lock.test_and_set(std::memory_order_acquire)) {}
  }
  ~BbWqLock() { q.lock.clear(std::memory_order_release); }
};

// The writable STRUCT a member belongs to, or q.ranges for none.
static uint16_t bbWqRangeOf(const BbWq& q, uint16_t id)
{
  uint16_t r = 0;
  while (r < q.ranges && !(id >= q.range[r].first &&
                           (uint32_t)id < (uint32_t)q.range[r].first + q.range[r].count)) {
    r++;
  }
  return r;
}

static void bbWqRemove(BbWq& q, uint16_t i)
{
  if (q.e[i].text != BB_WQ_NO_TEXT) q.textLen[q.e[i].text] = BB_WQ_NO_TEXT;
  for (uint16_t k = i; k + 1 < q.count; k++) q.e[k] = q.e[k + 1];
  q.count--;
}

static void bbWqDropped(BbWq& q, uint16_t id)
{
  const uint16_t r = bbWqRangeOf(q, id);
  if (r < q.ranges) q.range[r].dropped++;
}

// The node's task: a peer wrote a queued member.
static void bbWqPush(BbWq& q, uint8_t by, uint16_t id, const BeeBusScalar* value,
                     const char* text, uint16_t length)
{
  BbWqLock guard(q);
  if (q.size == 0 || bbWqRangeOf(q, id) == q.ranges) return;
  uint16_t same = 0, oldest = 0;
  for (uint16_t i = 0; i < q.count; i++) {
    if (q.e[i].id != id) continue;
    if (same++ == 0) oldest = i;
  }
  if (same >= BB_WQ_PER_TOPIC) { bbWqRemove(q, oldest); bbWqDropped(q, id); }
  if (q.count == q.size) { bbWqDropped(q, q.e[0].id); bbWqRemove(q, 0); }
  BbWqEntry n{};
  n.id = id;
  n.by = by;
  n.text = BB_WQ_NO_TEXT;
  if (text) {
    uint16_t slot = 0;
    while (slot < q.texts && q.textLen[slot] != BB_WQ_NO_TEXT) slot++;
    if (slot == q.texts) { bbWqDropped(q, id); return; }
    // The longest writable STRING fits whole; the member takes its own n.
    const uint16_t keep = length < q.textCap - 1 ? length : (uint16_t)(q.textCap - 1);
    char* at = q.text + (size_t)slot * q.textCap;
    memcpy(at, text, keep);
    at[keep] = '\0';
    q.textLen[slot] = keep;
    n.text = slot;
  } else if (value) {
    n.value = *value;
  }
  q.e[q.count++] = n;
}

// The queue of a node, made (and its handlers registered) the first time a
// writable STRUCT binds on it.
static BbWq* bbWqOf(BeeBusAPI* node)
{
  for (BbWq* q = bbWqs; q; q = q->next) {
    if (q->node == node) return q;
  }
  BbWq* q = new (std::nothrow) BbWq();
  if (!q) return nullptr;
  q->node = node;
  q->next = bbWqs;
  bbWqs = q;
  node->onTopicWritten([q](uint8_t by, uint16_t id, const BeeBusScalar& value) {
    if (bb_topicTypeIsString(value.type)) return;   // the string handler takes it
    bbWqPush(*q, by, id, &value, nullptr, 0);
  });
  node->onTopicStringWritten([q](uint8_t by, uint16_t id, const char* text, uint16_t length) {
    bbWqPush(*q, by, id, nullptr, text ? text : "", text ? length : 0);
  });
  // A write that asked for a result and was not kept as written: counted for
  // the STRUCT it belongs to.
  node->onTopicDecided([q](uint8_t, uint16_t id, uint8_t outcome) {
    if (outcome != BEEBUS_OUTCOME_CHANGED && outcome != BEEBUS_OUTCOME_REFUSED) return;
    BbWqLock guard(*q);
    const uint16_t r = bbWqRangeOf(*q, id);
    if (r < q->ranges) q->range[r].refused++;
  });
  return q;
}

// Owner, once after a WRITABLE bind: every member is queued on the node, and
// the node's queue grows to hold this STRUCT's members too. The new storage is
// taken aside and swapped in under the lock, what is waiting copied across.
bool bb_planQueueWrites(void* plan, BeeBusAPI* node, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  uint32_t strings = 0, bools = 0;
  uint16_t longest = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    const BbRun& r = p.runs[i];
    if (r.wire == BEEBUS_T_STRING) {
      strings += r.count;
      if (r.cap + 1u > longest) longest = (uint16_t)(r.cap + 1u);
    } else if (r.wire == BEEBUS_T_BOOL) {
      bools += r.count;
    }
  }
  if (bools > 0 && !p.pulseLeaf) {
    p.pulseLeaf = new (std::nothrow) uint32_t[bools];
    p.pulseAt = new (std::nothrow) uint32_t[bools];
    if (!p.pulseLeaf || !p.pulseAt) {
      snprintf(err, errCap, "no memory for the momentary commands");
      return false;
    }
    p.pulseCap = bools;
  }
  if (!p.appliedIds) {
    p.appliedIds = new (std::nothrow) uint16_t[p.leaves];
    p.appliedCmd = new (std::nothrow) uint8_t[p.leaves];
    if (!p.appliedIds || !p.appliedCmd) {
      snprintf(err, errCap, "no memory for the write results");
      return false;
    }
  }

  BbWq* q = bbWqOf(node);
  const uint32_t members = (q ? q->members : 0) + p.leaves;
  const uint32_t allStrings = (q ? q->strings : 0) + strings;
  const uint32_t size = members > BB_WQ_SIZE ? members : BB_WQ_SIZE;
  const uint32_t texts = allStrings == 0 ? 0 : (allStrings > BB_WQ_TEXTS ? allStrings : BB_WQ_TEXTS);
  BbWqEntry* e = nullptr;
  uint16_t* taken = nullptr;
  char* text = nullptr;
  uint16_t* textLen = nullptr;
  BbWqRange* range = nullptr;
  uint16_t textCap = 0;
  bool ok = q != nullptr;
  if (ok) {
    textCap = longest > q->textCap ? longest : q->textCap;
    if (size > q->size) {
      e = new (std::nothrow) BbWqEntry[size];
      taken = new (std::nothrow) uint16_t[size];
      ok = e && taken;
    }
    if (ok && (texts > q->texts || textCap > q->textCap)) {
      text = new (std::nothrow) char[(size_t)texts * textCap];
      textLen = new (std::nothrow) uint16_t[texts];
      ok = text && textLen;
    }
    if (ok) {
      range = new (std::nothrow) BbWqRange[q->ranges + 1u];
      ok = range != nullptr;
    }
  }
  if (!ok) {
    delete[] e;
    delete[] taken;
    delete[] text;
    delete[] textLen;
    snprintf(err, errCap, "no memory for the write queue (%lu writable members)",
             (unsigned long)members);
    return false;
  }
  {
    BbWqLock guard(*q);
    if (e) {
      for (uint16_t i = 0; i < q->count; i++) e[i] = q->e[i];
      std::swap(e, q->e);
      std::swap(taken, q->taken);
      q->size = (uint16_t)size;
    }
    if (text) {
      for (uint32_t s = 0; s < texts; s++) textLen[s] = BB_WQ_NO_TEXT;
      for (uint16_t s = 0; s < q->texts; s++) {
        if (q->textLen[s] == BB_WQ_NO_TEXT) continue;
        memcpy(text + (size_t)s * textCap, q->text + (size_t)s * q->textCap, q->textLen[s] + 1u);
        textLen[s] = q->textLen[s];
      }
      std::swap(text, q->text);
      std::swap(textLen, q->textLen);
      q->texts = (uint16_t)texts;
      q->textCap = textCap;
    }
    for (uint16_t r = 0; r < q->ranges; r++) range[r] = q->range[r];
    range[q->ranges] = BbWqRange{p.topicId, (uint16_t)p.leaves, 0, 0};
    std::swap(range, q->range);
    p.wqRange = q->ranges;
    q->ranges++;
    q->members = members;
    q->strings = allStrings;
  }
  // What was swapped out.
  delete[] e;
  delete[] taken;
  delete[] text;
  delete[] textLen;
  delete[] range;
  for (uint32_t k = 0; k < p.leaves; k++) node->setTopicQueued((uint16_t)(p.topicId + k), true);
  p.wq = q;
  return true;
}

static bool bbLeafRun(BbPlan& p, uint32_t leaf, BbRun*& run, uint32_t& e)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (leaf >= r.firstLeaf && leaf < r.firstLeaf + r.count) { run = &r; e = leaf - r.firstLeaf; return true; }
  }
  return false;
}

// A taken write into the program's variable (and its wire copy, if converted).
static void bbApplyWrite(BbPlan& p, BbWq& q, const BbWqEntry& w, uint32_t pulseMs)
{
  const uint32_t leaf = (uint32_t)(w.id - p.topicId);
  BbRun* r = nullptr;
  uint32_t e = 0;
  if (!bbLeafRun(p, leaf, r, e)) return;
  if (r->wire == BEEBUS_T_STRING) {
    if (w.text == BB_WQ_NO_TEXT) return;
    char* to = (char*)bbElem(*r, e);
    const uint16_t keep = q.textLen[w.text] < r->cap ? q.textLen[w.text] : r->cap;
    memcpy(to, q.text + (size_t)w.text * q.textCap, keep);
    to[keep] = '\0';
    return;
  }
  if (r->conv != BB_CONV_NONE) {
    int32_t wire = 0;
    bb_scalarStore(w.value, &wire);
    bbFromWire(*r, e, wire);
    bbShadow(p, *r, e) = wire;
    bbSynced(p, *r, e) = wire;
    return;
  }
  bb_scalarStore(w.value, bbElem(*r, e));
  // A momentary command: a BOOL written TRUE goes back to FALSE after PULSE.
  // There is a place for every BOOL member, so none is ever cut short.
  if (pulseMs > 0 && r->wire == BEEBUS_T_BOOL && *(bool*)bbElem(*r, e)) {
    uint32_t slot = 0;
    while (slot < p.pulses && p.pulseLeaf[slot] != leaf) slot++;
    if (slot == p.pulses) {
      if (p.pulses == p.pulseCap) return;
      p.pulses++;
    }
    p.pulseLeaf[slot] = leaf;
    p.pulseAt[slot] = (uint32_t)bb_millis();
  }
}

// Owner, once a scan: one waiting write per member, oldest first, into the
// variable. Returns how many were taken; `firstLeaf` / `by` describe the first
// of them, `lost` adds the writes dropped since the last call (a member written
// more than 4 times between two scans, or a full queue).
uint32_t bb_planTakeWrites(void* plan, uint32_t pulseMs, uint32_t* firstLeaf, uint8_t* by,
                           uint32_t* lost)
{
  BbPlan& p = *(BbPlan*)plan;
  // Momentary commands whose pulse is over go back to FALSE.
  const uint32_t now = (uint32_t)bb_millis();
  for (uint32_t s = 0; s < p.pulses;) {
    if (pulseMs == 0 || now - p.pulseAt[s] >= pulseMs) {
      BbRun* r = nullptr;
      uint32_t e = 0;
      if (bbLeafRun(p, p.pulseLeaf[s], r, e)) *(bool*)bbElem(*r, e) = false;
      p.pulseLeaf[s] = p.pulseLeaf[p.pulses - 1];
      p.pulseAt[s] = p.pulseAt[p.pulses - 1];
      p.pulses--;
    } else {
      s++;
    }
  }
  BbWq* q = (BbWq*)p.wq;
  if (!q) return 0;
  uint32_t taken = 0;
  {
    BbWqLock guard(*q);
    uint16_t* takenIds = q->taken;
    for (uint16_t i = 0; i < q->count;) {
      const BbWqEntry w = q->e[i];
      const bool mine = w.id >= p.topicId && (uint32_t)w.id < (uint32_t)p.topicId + p.leaves;
      bool already = false;
      for (uint32_t k = 0; k < taken && !already; k++) already = takenIds[k] == w.id;
      if (!mine || already) { i++; continue; }
      bbApplyWrite(p, *q, w, pulseMs);
      if (taken == 0) {
        if (firstLeaf) *firstLeaf = (uint32_t)(w.id - p.topicId);
        if (by) *by = w.by;
      }
      // A momentary BOOL is a command: answered once taken, not read back,
      // since it drops back to FALSE on its own.
      BbRun* r = nullptr;
      uint32_t e = 0;
      const bool momentary = pulseMs > 0 && bbLeafRun(p, (uint32_t)(w.id - p.topicId), r, e) &&
                             r->wire == BEEBUS_T_BOOL;
      if (p.appliedIds) {
        p.appliedIds[taken] = w.id;
        p.appliedCmd[taken] = (uint8_t)(p.command || momentary);
      }
      takenIds[taken++] = w.id;
      bbWqRemove(*q, i);
    }
    BbWqRange& mine = q->range[p.wqRange];
    if (lost) *lost += mine.dropped;
    mine.dropped = 0;
  }
  // Outside the queue's lock: the node's task takes that lock inside its own,
  // so taking the node's here, under it, could stop both.
  if (p.appliedIds) {
    for (uint32_t k = 0; k < taken; k++) {
      q->node->topicApplied(p.appliedIds[k], p.settleMs, p.appliedCmd[k] != 0);
    }
  }
  return taken;
}

// Owner: the read-back's delay and whether every member is a command
// (BEEBUS_TP_SERVE, BEEBUS_TP_STRUCT's SETTLE).
void bb_planServeTerms(void* plan, uint32_t settleMs, bool command)
{
  BbPlan& p = *(BbPlan*)plan;
  p.settleMs = (uint16_t)(settleMs > 0xFFFFu ? 0xFFFFu : settleMs);
  p.command = command;
}

// Owner, once a scan: writes the node answered CHANGED or REFUSED since the
// last call.
uint32_t bb_planTakeRefused(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  BbWq* q = (BbWq*)p.wq;
  if (!q) return 0;
  BbWqLock guard(*q);
  BbWqRange& mine = q->range[p.wqRange];
  const uint32_t refused = mine.refused;
  mine.refused = 0;
  return refused;
}

// Owner: every member held in a ring of `depth` while the network is away
// (store and forward). 0 leaves them unbuffered.
bool bb_planBuffer(void* plan, BeeBusAPI* node, uint8_t depth, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  if (depth == 0) return true;
  for (uint32_t k = 0; k < p.leaves; k++) {
    if (!node->bufferTopic((uint16_t)(p.topicId + k), depth)) {
      snprintf(err, errCap, "no ring of %u for topic %u", (unsigned)depth,
               (unsigned)(p.topicId + k));
      return false;
    }
  }
  return true;
}

// Subscriber: asks for every topic not yet asked for, stopping at the first
// refusal the queue gives (QueueFull: the rest go next scan). `again` re-asks
// every one, for new terms. Returns the values still not asked for.
uint32_t bb_planSubscribe(void* plan, BeeBusAPI* node, float deadband, int32_t intervalMs,
                          bool again, BeeBusResult* last, bool reliable)
{
  BbPlan& p = *(BbPlan*)plan;
  if (!p.state) {
    if (last) *last = BeeBusResult::InvalidArgument;
    return p.leaves;
  }
  if (again) {
    for (uint32_t k = 0; k < p.leaves; k++) p.state[k] = (uint8_t)(p.state[k] & ~BB_ISSUED);
  }
  uint32_t pending = 0;
  bool full = false;
#if BEEBUS_TOPIC_NAMES
  for (uint32_t k = 0; k < p.leaves; k++) {
    if (p.state[k] & BB_ISSUED) continue;
    if (full) { pending++; continue; }
    const BeeBusResult result =
        node->subscribe(p.peer, (uint16_t)(p.topicId + k), deadband, (bb_time_t)intervalMs,
                        reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live);
    if (bb_accepted(result) || result == BeeBusResult::Duplicate) {
      p.state[k] = (uint8_t)(p.state[k] | BB_ISSUED);
    } else {
      if (last) *last = result;
      pending++;
      if (result == BeeBusResult::QueueFull) full = true;
    }
  }
#else
  (void)node; (void)deadband; (void)intervalMs;
  pending = p.leaves;
  if (last) *last = BeeBusResult::InvalidArgument;
#endif
  return pending;
}

// Subscriber, once a scan: copies arrivals into the variable and reports.
//   newCount   values that arrived since the last scan
//   firstNew   the first of them, by number from 0
//   missed     publishes the sequence says never arrived, since the last scan
//   worst      the worst quality across the values (BeeBusQuality order)
//   allSeen    every value has arrived at least once
// A string topic is bound to the variable's own buffer, so its text is there
// already; a converted value is taken from its copy.
void bb_planReceive(void* plan, BeeBusAPI* node, uint32_t* newCount, uint32_t* firstNew,
                    uint32_t* missed, uint8_t* worst, bool* allSeen, int32_t* oldestAgeMs)
{
  BbPlan& p = *(BbPlan*)plan;
  uint32_t fresh = 0, gaps = 0;
  bool seenAll = true;
  uint8_t bad = (uint8_t)BeeBusQuality::Good;
  int32_t oldest = 0;
  if (!p.state || !p.seen) return;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(p.topicId + leaf);
      uint16_t& seenReceived = p.seen[2 * (size_t)leaf];
      uint16_t& seenMissed = p.seen[2 * (size_t)leaf + 1];
      BeeBusTopicStream stream;
      bool isNew = false;
      if (node->topicStream(p.peer, id, stream)) {
        isNew = (stream.received != seenReceived);
        gaps += (uint16_t)(stream.missed - seenMissed);
        seenReceived = stream.received;
        seenMissed = stream.missed;
      }
      if (isNew) {
        if (fresh == 0 && firstNew) *firstNew = leaf;
        fresh++;
        p.state[leaf] = (uint8_t)(p.state[leaf] | BB_ARRIVED);
        if (r.conv != BB_CONV_NONE) {
          bbFromWire(r, e, bbShadow(p, r, e));
          bbSynced(p, r, e) = bbShadow(p, r, e);
        }
      }
      if (!(p.state[leaf] & BB_ARRIVED)) seenAll = false;
      // Ranked so the answer is the worst member: BAD, then UNCERTAIN, then
      // UNKNOWN (never arrived), and GOOD only when every member is good.
      const uint8_t q = (uint8_t)node->topicQuality(p.peer, id);
      if (bbQualityRank(q) > bbQualityRank(bad)) bad = q;
      const bb_time_t age = node->topicAge(p.peer, id);
      if (age != BEEBUS_SILENCE_NEVER && (int32_t)age > oldest) oldest = (int32_t)age;
    }
  }
  if (newCount) *newCount = fresh;
  if (missed) *missed = gaps;
  if (worst) *worst = bad;
  if (allSeen) *allSeen = seenAll;
  if (oldestAgeMs) *oldestAgeMs = oldest;
}

// ---- Binds: BEEBUS_TP_BIND ---------------------------------------------------
// Every member of the STRUCT bound to the owner's topic of the same place
// (BeeBusAPI::bind): the owner's value lands in the member, a change of the
// member goes to the owner, which decides. A converted member (TIME, DT ...)
// is bound through its copy, kept in step both ways each scan.
bool bb_planBind(void* plan, BeeBusAPI* node, uint8_t peer, uint16_t topicId,
                 const char* prefix, bool reliable, float deadband, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  const char* pre = prefix ? prefix : "";
  if (topicId < BEEBUS_TOPIC_ID_MIN ||
      (uint32_t)topicId + p.leaves - 1 > (uint32_t)BEEBUS_TOPIC_ID_MAX) {
    snprintf(err, errCap, "TOPIC_ID + members runs past 32767, or TOPIC_ID is 0");
    return false;
  }
  if (!p.state || !p.seen) {
    delete[] p.state;
    delete[] p.seen;
    p.state = new (std::nothrow) uint8_t[p.leaves]();
    p.seen = new (std::nothrow) uint16_t[2 * (size_t)p.leaves]();
    if (!p.state || !p.seen) {
      snprintf(err, errCap, "no memory for the bind records");
      return false;
    }
  }
  BeeBusBindTerms terms;
  terms.qos = reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live;
  terms.deadband = deadband;

  bbSyncShadows(p, false);
  uint32_t done = 0;
  char name[BB_PATH_MAX];
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(topicId + leaf);
      bbLeafName(p, r, e, pre, true, name, sizeof(name));
      const bool isText = r.wire == BEEBUS_T_STRING;
      void* where = isText ? (void*)bbElem(r, e) : bbBindingOf(p, r, e);
      const uint16_t textCap = isText ? (uint16_t)(r.cap + 1) : 0;
      if (!node->bindRaw(peer, id, r.wire, where, terms, nullptr, textCap)) {
        for (uint32_t k = 0; k < done; k++) node->unbind(peer, (uint16_t)(topicId + k));
        snprintf(err, errCap, "topic %u (%s) is already bound", (unsigned)id, name);
        return false;
      }
      done++;
    }
  }
  p.topics = true;
  p.binds = true;
  p.remote = true;
  p.peer = peer;
  p.topicId = topicId;
  return true;
}

// Once a scan: the copies of converted members in step both ways - a copy the
// bind moved (the owner's value) goes into the member, otherwise the member
// (the program's change) goes into the copy for the bind to send.
void bb_planBindSync(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, true);
}

// Once a scan, the members' states:
//   worst      the worst member: OFFLINE, SYNCING, FAILED, REFUSED, PENDING,
//              IN_SYNC, in that order
//   pending, refused, failed   how many members are in each
//   firstRefused               the first member REFUSED, by number from 0
//   allInSync                  every member IN_SYNC
void bb_planBindStatus(void* plan, BeeBusAPI* node, uint8_t* worst, uint32_t* pending,
                       uint32_t* refused, uint32_t* failed, uint32_t* firstRefused,
                       bool* allInSync)
{
  BbPlan& p = *(BbPlan*)plan;
  // Rank: the higher, the worse.
  static const uint8_t rank[] = {5, 4, 0, 1, 2, 3};   // by BeeBusBindState
  uint8_t bad = (uint8_t)BeeBusBindState::InSync;
  uint32_t nPending = 0, nRefused = 0, nFailed = 0, first = 0;
  bool all = true;
  for (uint32_t k = 0; k < p.leaves; k++) {
    const BeeBusBindState s = node->bindState(p.peer, (uint16_t)(p.topicId + k));
    const uint8_t v = (uint8_t)s;
    if (v < sizeof(rank) && rank[v] > rank[bad]) bad = v;
    if (s != BeeBusBindState::InSync) all = false;
    if (s == BeeBusBindState::Pending) nPending++;
    if (s == BeeBusBindState::Failed) nFailed++;
    if (s == BeeBusBindState::Refused) {
      if (nRefused == 0) first = k;
      nRefused++;
    }
  }
  if (worst) *worst = bad;
  if (pending) *pending = nPending;
  if (refused) *refused = nRefused;
  if (failed) *failed = nFailed;
  if (firstRefused) *firstRefused = first;
  if (allInSync) *allInSync = all;
}

// A plan that was never bound to a node (a read or a write buffer) can go.
void bb_planFree(void* plan)
{
  if (!plan) return;
  BbPlan* p = (BbPlan*)plan;
  if (p->bound || p->topics) return;   // the node holds pointers into it
  delete p;
}

// --- opening the link, and trying again ------------------------------------
//
// A link that does not open now may open later: a USB adapter plugged in after
// boot, a network interface that comes up after the PLC, a port another
// program is holding. So a failed open (BEEBUS_NOT_INITIALISED) is tried again,
// 1 s after the first failure, then 2, 4, 8, 16 and every 30 s after that.
// A wrong SETTING stays wrong however often it is tried, so those
// (BEEBUS_INVALID_ARGUMENT) are reported once, with LAST_ERROR saying which,
// and not retried. Correct the pin and restart the PLC.
static const uint32_t BB_RETRY_FIRST_MS = 1000;
static const uint32_t BB_RETRY_MAX_MS = 30000;

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  READY = false;
  LINK = false;
  CONNECTED = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
  ATTEMPTS = 0;
  RETRY_IN = bb_timeOf(0);
  api = (strucpp::XWORD_t)0;
  wanted = false;
  fbSettled = false;
  fbTried = false;
  fbRetryAt = 0;
  fbBackoff = 0;
  fbWaiting = false;
  fbSettingsKey = 0;
  fbRebind = false;
  fbChangeAt = 0;
  fbTransport = (strucpp::XWORD_t)0;
  fbOpenPort = 255;
}

// A short fingerprint of settings (FNV-1a, 32 bits): only to notice a change
// without keeping a second copy of every string.
static uint32_t bb_fingerprint(uint32_t hash, const void* data, size_t length)
{
  const uint8_t* bytes = (const uint8_t*)data;
  for (size_t i = 0; i < length; i++) {
    hash ^= bytes[i];
    hash *= 16777619u;
  }
  return hash;
}

static uint32_t bb_fingerprintText(uint32_t hash, const char* text)
{
  hash = bb_fingerprint(hash, text, strlen(text));
  return bb_fingerprint(hash, "", 1);
}

void loop()
{
    fbTask = bb_currentTask();   // every block given this node shares it: see BEEBUS_ARDUINO
  // ONE SCAN BEFORE OPENING.
  //
  // BEEBUS_ARDUINO writes into this instance and may sit above or below this
  // block in the rung. Waiting a scan means it has run at least once before
  // the link is built, so it needs no particular place -- a rule nobody would
  // remember and the compiler could not check. Opening a socket costs longer
  // than the scan does.
  // What the link is opened from. A change re-opens it (below).
  auto settingsKey = [&]() -> uint32_t {
    uint32_t h = 2166136261u;
    const uint8_t id = (uint8_t)NODE_ID;
    const int32_t link = (int32_t)(BEEBUS_NODE_LINK)TRANSPORT;
    const int32_t baud = (int32_t)BAUD;
    const uint16_t udpPort = (uint16_t)UDP_PORT;
    const uint8_t ttl = (uint8_t)TTL;
    const bool failsafe = (bool)FAILSAFE;
    const uint8_t queue = (uint8_t)QUEUE;
    const uint8_t port = (uint8_t)fbPort;
    const int16_t rx = (int16_t)fbRxPin;
    const int16_t tx = (int16_t)fbTxPin;
    h = bb_fingerprint(h, &id, sizeof id);
    h = bb_fingerprint(h, &link, sizeof link);
    h = bb_fingerprint(h, &baud, sizeof baud);
    h = bb_fingerprint(h, &udpPort, sizeof udpPort);
    h = bb_fingerprint(h, &ttl, sizeof ttl);
    h = bb_fingerprint(h, &failsafe, sizeof failsafe);
    h = bb_fingerprint(h, &queue, sizeof queue);
    h = bb_fingerprint(h, &port, sizeof port);
    h = bb_fingerprint(h, &rx, sizeof rx);
    h = bb_fingerprint(h, &tx, sizeof tx);
    h = bb_fingerprintText(h, DEVICE.c_str());
    h = bb_fingerprintText(h, GROUP.c_str());
    h = bb_fingerprintText(h, IFACE.c_str());
    h = bb_fingerprintText(h, fbWifiSsid.c_str());
    h = bb_fingerprintText(h, fbPassword.c_str());
    h = bb_fingerprintText(h, fbMac.c_str());
    h = bb_fingerprintText(h, fbIp.c_str());
    return h;
  };

  if (!(bool)READY || (bool)fbRebind) {
    if (!(bool)fbSettled) {
      fbSettled = true;
      return;
    }

    // A SETTINGS CHANGE ON A RUNNING NODE: the same node is re-opened (see
    // BeeBusAPI::rebind), after a moment for it to leave the old ring.
    BeeBusAPI* existing = (bool)READY ? bbApi(api) : nullptr;
    if (existing && (existing->isConnected() || existing->isLeaving()) &&
        (uint32_t)((uint32_t)bb_millis() - (uint32_t)fbChangeAt) < 1000u) {
      existing->loop();
      return;
    }

    if ((bool)fbTried) {
      // A settings fault: said once, and not retried until a setting changes -
      // retrying the same ones cannot fix it, and a settings page can.
      if (!(bool)fbWaiting) {
        if (settingsKey() == (uint32_t)fbSettingsKey) return;
        fbTried = false;
      }
    }
    if ((bool)fbTried) {
      const int32_t left = (int32_t)((uint32_t)fbRetryAt - (uint32_t)bb_millis());
      if (left > 0) {
        RETRY_IN = bb_timeOf(left);
        return;
      }
    }
    fbTried = true;
    fbWaiting = false;
    RETRY_IN = bb_timeOf(0);
    ATTEMPTS = (uint32_t)ATTEMPTS + 1;

    // A settings fault. Reported, and left: retrying cannot fix it.
    auto refuse = [&](const char* why) {
      fbSettingsKey = settingsKey();
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      LAST_ERROR = why;
    };

    // The link did not open. Tried again later, each wait twice the last.
    auto later = [&](const char* why) {
      const uint32_t wait = ((uint32_t)fbBackoff == 0)
          ? BB_RETRY_FIRST_MS
          : (((uint32_t)fbBackoff * 2u > BB_RETRY_MAX_MS) ? BB_RETRY_MAX_MS
                                                          : (uint32_t)fbBackoff * 2u);
      fbBackoff = wait;
      fbRetryAt = (uint32_t)bb_millis() + wait;
      fbWaiting = true;
      RETRY_IN = bb_timeOf((int32_t)wait);
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_NOT_INITIALISED;
      LAST_ERROR = why;
    };

    // 0 means "nobody" on the wire and 255 is the join token: the protocol's
    // own range, so the block and the core can never disagree.
    if ((uint8_t)NODE_ID < BEEBUS_NODE_ID_MIN || (uint8_t)NODE_ID > BEEBUS_NODE_ID_MAX) {
      refuse("NODE_ID must be 1..254");
      return;
    }

    const bool runtimeLink = (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_RUNTIME_UDP) ||
                             (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_RUNTIME_SERIAL);

#if defined(BEEBUS_PLATFORM_HOST)
    if (!runtimeLink) {
      refuse("that link needs a board, not the Runtime");
      return;
    }
    if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_RUNTIME_SERIAL && DEVICE.length() == 0) {
      refuse("no serial device named");
      return;
    }

    BeeBusConfig config;
    config.enableFailSafe = (bool)FAILSAFE;
    config.maxPendingOps = (uint8_t)QUEUE;         // 0: the platform's default
    config.maxPendingResponses = (uint8_t)QUEUE;

    // nothrow throughout: a board has no exceptions, and the Runtime is told
    // the same way - out of memory is a reason on LAST_ERROR, not a crash.
    BeeBusAPI* node = existing ? existing : new (std::nothrow) BeeBusAPI();
    if (!node) {
      later("out of memory for the node");
      return;
    }
    BeeBusTransport* transport = nullptr;
    bool started = false;
    // Copied out: the text lives in the transport, which a failure deletes.
    char failure[96] = "";

    if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_RUNTIME_SERIAL) {
      // The pins are members of this instance, so their buffers outlive the scan
      // and the transport may hold them.
      BeeBusSerialConfig serial;
      serial.device = DEVICE.c_str();
      if ((int32_t)BAUD > 0) serial.baudRate = (uint32_t)(int32_t)BAUD;

      BeeBusHostSerialTransport* port = new (std::nothrow) BeeBusHostSerialTransport(serial);
      if (!port) {
        if (!existing) delete node;
        later("out of memory for the link");
        return;
      }
      transport = port;
      started = existing ? existing->rebind(port, (uint8_t)NODE_ID, &config)
                         : node->begin(port, (uint8_t)NODE_ID, config);
      if (!started) snprintf(failure, sizeof(failure), "%s",
                             node->startError() ? node->startError() : port->lastError());
    } else {
      BeeBusUdpConfig udp;
      if (GROUP.length() > 0) udp.groupAddress = GROUP.c_str();
      if ((uint16_t)UDP_PORT != 0) udp.port = (uint16_t)UDP_PORT;
      if ((uint8_t)TTL != 0) udp.ttl = (uint8_t)TTL;
      if (IFACE.length() > 0) udp.interfaceAddress = IFACE.c_str();

      BeeBusHostUdpTransport* socket = new (std::nothrow) BeeBusHostUdpTransport(udp);
      if (!socket) {
        if (!existing) delete node;
        later("out of memory for the link");
        return;
      }
      transport = socket;
      started = existing ? existing->rebind(socket, (uint8_t)NODE_ID, &config)
                         : node->begin(socket, (uint8_t)NODE_ID, config);
      if (!started) snprintf(failure, sizeof(failure), "%s",
                             node->startError() ? node->startError() : socket->lastError());
    }

    if (!started) {
      // The node does not own the transport, so both go: a retry builds new.
      // A node being re-opened stays, on its old link.
      if (!existing) delete node;
      delete transport;
      later(failure[0] == '\0' ? "the link did not open" : failure);
      return;
    }
    {
      BeeBusTransport* replaced = (BeeBusTransport*)(uintptr_t)(strucpp::XWORD_t)fbTransport;
      fbTransport = (strucpp::XWORD_t)(uintptr_t)transport;
      if (replaced && replaced != transport) {
        replaced->end();
        delete replaced;
      }
    }

    if ((bool)CONNECT) node->connect();
    wanted = (bool)CONNECT;
    api = (strucpp::XWORD_t)(uintptr_t)node;
#endif

#if defined(BEEBUS_PLATFORM_ARDUINO)
    if (runtimeLink) {
      refuse("that link needs the Runtime, not a board");
      return;
    }

    BeeBusConfig config;
    config.enableFailSafe = (bool)FAILSAFE;
    config.maxPendingOps = (uint8_t)QUEUE;         // 0: the platform's default
    config.maxPendingResponses = (uint8_t)QUEUE;

    BeeBusAPI* node = existing;
    bool started = false;
    BeeBusTransport* made = nullptr;   // ours to free when replaced; a serial line is the node's

    if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_ARDUINO_SERIAL) {
      const uint32_t baud = ((int32_t)BAUD > 0) ? (uint32_t)(int32_t)BAUD : 115200u;
      HardwareSerial* port = bbSerialPort((uint8_t)fbPort);
      if (port == nullptr) {
        refuse("PORT is not a hardware serial on this board");
        return;
      }

      // Re-opened: the line in use is closed first - the same one at a new
      // speed or on new pins, or one this node is leaving.
      if (existing && (uint8_t)fbOpenPort != 255) {
        HardwareSerial* old = bbSerialPort((uint8_t)fbOpenPort);
        if (old) old->end();
      }
#if defined(ARDUINO_ARCH_ESP32)
      // Buffers that cover a scan. This core opens a UART with 256 bytes in and
      // none out: a write then waits inside the PLC scan until the frame is
      // nearly on the wire (about 9 ms per 100 bytes at 115200), and whatever
      // arrives after the first 256 bytes of a scan is lost (22 ms of line at
      // 115200). On the Node UIO the HMI was heard but the ring never formed.
      // Out: two whole frames, so a write never waits. In: four, more than a
      // scan's worth. Both only take effect before begin().
      port->setRxBufferSize(4u * BEEBUS_MAX_WIRE_FRAME);
      port->setTxBufferSize(2u * BEEBUS_MAX_WIRE_FRAME);
      // Only this core takes the pins; elsewhere they are fixed by the board.
      if ((int16_t)fbRxPin >= 0 && (int16_t)fbTxPin >= 0) {
        port->begin(baud, SERIAL_8N1, (int16_t)fbRxPin, (int16_t)fbTxPin);
      } else {
        port->begin(baud);
      }
#else
      port->begin(baud);
#endif
      if (existing) {
        started = existing->rebind(port, (uint8_t)NODE_ID, baud, &config);
      } else {
        node = new (std::nothrow) BeeBusAPI();
        if (!node) {
          later("out of memory for the node");
          return;
        }
        started = node->begin(port, (uint8_t)NODE_ID, config, baud);
      }
      if (started) fbOpenPort = (uint8_t)fbPort;
    } else {
      BeeBusUdpConfig udp;
      if (GROUP.length() > 0) udp.groupAddress = GROUP.c_str();
      if ((uint16_t)UDP_PORT != 0) udp.port = (uint16_t)UDP_PORT;

      IPAddress group;
      group.fromString(udp.groupAddress);

      BeeBusArduinoUdpTransport* transport = nullptr;

      if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_ARDUINO_WIFI) {
#if defined(BEEBUS_HAS_WIFI)
        static WiFiUDP wifiSocket;
        if (existing) {
          // Re-opened: leave the network and the group, then join again
          // with what the settings say now.
          wifiSocket.stop();
          WiFi.disconnect();
        }
        WiFi.begin(fbWifiSsid.c_str(), fbPassword.c_str());
        wifiSocket.beginMulticast(group, udp.port);
        transport = new (std::nothrow) BeeBusArduinoUdpTransport(&wifiSocket, udp);
#else
        refuse("this board has no WiFi");
        return;
#endif
      } else {
#if defined(BEEBUS_HAS_ETHERNET)
        static EthernetUDP ethSocket;
        if (existing) ethSocket.stop();
        uint8_t mac[6] = {0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};
        bbParseMac(fbMac.c_str(), mac);

        IPAddress address;
        if (address.fromString(fbIp.c_str())) {
          Ethernet.begin(mac, address);
        } else {
          // DHCP blocks, and the library waits 60 s by default -- on a 1 ms task
          // that is a stopped PLC. Bound it to one second and let the node's own
          // retry carry the wait. A static IP avoids the stall altogether.
          Ethernet.begin(mac, 1000, 1000);
        }

        // Tell "no controller on the SPI bus" apart from "nothing plugged in":
        // the first is wiring the user got wrong, the second is a cable.
        if (Ethernet.hardwareStatus() == EthernetNoHardware) {
          refuse("no Ethernet controller found on SPI");
          return;
        }

        ethSocket.beginMulticast(group, udp.port);
        transport = new (std::nothrow) BeeBusArduinoUdpTransport(&ethSocket, udp);
#else
        refuse("set BEEBUS_ENABLE_ETHERNET to use Ethernet");
        return;
#endif
      }

      if (!transport) {
        later("out of memory for the link");
        return;
      }
      if (existing) {
        started = existing->rebind(transport, (uint8_t)NODE_ID, &config);
      } else {
        node = new (std::nothrow) BeeBusAPI();
        if (!node) {
          delete transport;
          later("out of memory for the node");
          return;
        }
        started = node->begin(transport, (uint8_t)NODE_ID, config);
      }
      if (!started) delete transport;
      else made = transport;
    }

    if (!started) {
      // The reason is a string constant of the core's, so it outlives the node.
      const char* why = (node && node->startError()) ? node->startError()
                                                      : "the link did not open";
      if (!existing) delete node;
      later(why);
      return;
    }
    {
      BeeBusTransport* replaced = (BeeBusTransport*)(uintptr_t)(strucpp::XWORD_t)fbTransport;
      fbTransport = (strucpp::XWORD_t)(uintptr_t)made;
      if (replaced && replaced != made) {
        replaced->end();
        delete replaced;
      }
    }

    if ((bool)CONNECT) node->connect();
    wanted = (bool)CONNECT;
    api = (strucpp::XWORD_t)(uintptr_t)node;
#endif

    // Open. Whatever an earlier attempt said is over.
    fbBackoff = 0;
    ERROR = false;
    STATUS = BEEBUS_RESULT::BEEBUS_OK;
    LAST_ERROR = "";
    READY = true;
    fbRebind = false;
    fbSettingsKey = settingsKey();
  }

  if (!(bool)READY) return;

  BeeBusAPI* node = bbApi(api);

  // --- RE-OPEN WHEN THE SETTINGS CHANGE ---
  //
  // NODE_ID, the line and BEEBUS_ARDUINO's settings were read once, when the
  // link opened, so an HMI that moved this node to another ID or baud rate did
  // nothing until the PLC restarted. Now a change leaves the ring and opens
  // again on the new settings, on the same node: registers, topics and
  // subscriptions stay bound, and peers subscribe again when it returns.
  if (node && settingsKey() != (uint32_t)fbSettingsKey) {
    fbRebind = true;
    fbTried = false;
    fbWaiting = false;
    fbBackoff = 0;
    fbChangeAt = (uint32_t)bb_millis();
    node->disconnect();
    wanted = false;
    node->loop();
    CONNECTED = false;
    return;
  }
  if (!node) {
    READY = false;
    CONNECTED = false;
    return;
  }

#if defined(BEEBUS_PLATFORM_ARDUINO)
  if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_ARDUINO_WIFI) {
#if defined(BEEBUS_HAS_WIFI)
    LINK = (WiFi.status() == WL_CONNECTED);
    // Joining takes seconds, and is not a fault. Say which it is while it lasts.
    LAST_ERROR = LINK ? "" : "joining the network";
#else
    LINK = false;
#endif
  } else if (TRANSPORT == BEEBUS_NODE_LINK::BEEBUS_NODE_ARDUINO_ETHERNET) {
#if defined(BEEBUS_HAS_ETHERNET)
    LINK = (Ethernet.linkStatus() != LinkOFF);
    if (!LINK) {
      LAST_ERROR = "Ethernet cable unplugged";
    } else if (Ethernet.localIP() == IPAddress(0, 0, 0, 0)) {
      // The cable is live but DHCP has not answered yet. Each begin() attempt
      // is bounded, so this clears itself once a lease arrives.
      LAST_ERROR = "no address from DHCP yet";
    } else {
      LAST_ERROR = "";
    }
#else
    LINK = false;
#endif
  } else {
    LINK = false;
  }
#endif

  // Acted on the edge: connect() and disconnect() every scan would restart the
  // join each time and the node would never settle.
  const bool want = (bool)CONNECT;
  if (want != (bool)wanted) {
    wanted = want;
    if (want) {
      node->connect();
    } else {
      node->disconnect();
    }
  }

  // Once per scan, from the block that owns the node. Everything the protocol
  // does — the token, the retries, the receive path — happens here.
  node->loop();
  CONNECTED = node->isConnected();

  // Held while the address is in use elsewhere, and dropped when it is not.
  if (node->hasDuplicateNodeID()) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_DUPLICATE_NODE_ID;
  } else if (STATUS == BEEBUS_RESULT::BEEBUS_DUPLICATE_NODE_ID) {
    ERROR = false;
    STATUS = BEEBUS_RESULT::BEEBUS_OK;
  }
}

END_FUNCTION_BLOCK