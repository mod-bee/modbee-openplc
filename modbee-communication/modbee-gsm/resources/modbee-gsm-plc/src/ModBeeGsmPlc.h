// ModBee GSM for OpenPLC - the one modem a PLC has.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see the modbee-gsm LICENSE. Commercial use requires a
// separate licence.

#pragma once

// =============================================================================
// WHY THIS EXISTS
// =============================================================================
//
// modbee-gsm deliberately has no global: no singleton, no serial port, no pin.
// WiFi and Ethernet are globals their libraries provide, and this is the same
// thing for cellular - ONE MODEM PER PLC, owned here, in the OpenPLC layer,
// so that the core library never has to learn that a PLC exists.
//
//   FB_GsmModemA7670 / FB_GsmModemSim7070
//                    makes the one device, holding only its module's driver,
//                    opens it, configures it and polls it; its methods
//                    (GsmPlcMethods.h) do the rest
//   FB_MqttClient    reaches it too, through GsmPlcClient, when this header
//                    is on the include path (E_MqttTransport.Cellular)
//
// --- THE LOCK ---
//
// OpenPLC runs each task on its own thread - on the Runtime, and on an ESP32
// in RTOS mode, which is the default there. modbee-gsm is single-threaded by
// design, so every touch of the modem is made holding one recursive lock.
//
// The blocks TRY the lock and skip a scan when another task holds it, so no
// block ever waits on the modem. Nothing holds it for long: GsmClient's
// connect(), which Arduino's Client interface requires to return a verdict
// (1.35 s plain, 5.2 s TLS, measured on an A7670G - and up to its time limit
// over a poor cellular link), takes it for each check of the dial and never
// across it, through the GsmService this layer gives the modem's sockets.
//
// --- NAMING ---
//
// Every C++ POU of a project is emitted into ONE translation unit, and each
// block's pins are #defines there - bError, sHostName, nHostPort, stApnConfig and the
// rest. This header can be included under any block's defines, so it uses no
// all-capitals identifier and no name with a lower-case type prefix followed
// by a capital (internal/tools/check-names.py checks it).

#include <ModBeeGsm.h>
#include <GsmCmdBuf.h>

#include <new>
#include <stdint.h>
#include <stddef.h>

namespace gsmplc {

// --- The lock -----------------------------------------------------------------

void lock();
void unlock();
bool tryLock();

// Holds the lock for a scope, waiting for it.
class Hold {
public:
    Hold() { lock(); }
    ~Hold() { unlock(); }
    Hold(const Hold&) = delete;
    Hold& operator=(const Hold&) = delete;
};

// Holds it only if it is free. A block that cannot get it skips a scan.
class TryHold {
public:
    TryHold() : _owned(tryLock()) {}
    ~TryHold() { if (_owned) { unlock(); } }
    bool owned() const { return _owned; }
    TryHold(const TryHold&) = delete;
    TryHold& operator=(const TryHold&) = delete;
private:
    bool _owned;
};

// --- The device ---------------------------------------------------------------
//
// MADE BY THE MODEM BLOCK THAT RUNS IT, holding only that module's driver.
// FB_GsmModemA7670 makes a GsmDeviceWith<GsmDriverA76XX>, FB_GsmModemSim7070 a
// GsmDeviceWith<GsmDriverSIM707x>, so a program links the one driver its
// block names. Each IS a GsmDevice, so device() is a GsmDevice& as it always
// was, and code in other libraries (modbee-mqtt's FB_MqttClock) that holds it
// as one is unchanged. Made once, by the block that claims the modem, at its
// first scan; never replaced.

bool hasDevice();

// Only once hasDevice(): every caller checks it (isOpen() implies it).
GsmDevice& device();

// The module family of the block that made it: "A76XX" or "SIM707x".
const char* family();

// Memory for the device: PSRAM first on an ESP32, the heap otherwise.
void* allocate(size_t size, size_t alignment);
void release(void* memory);
// Hands the made device to the layer. `destroy` ends it at unload.
void attach(GsmDevice* made, void (*destroy)(GsmDevice*), const char* familyName);

// Ends the device and frees its memory - from the derived object's own
// address: the GsmDevice inside it does not start where the memory does.
template <typename DeviceType>
void destroyDevice(GsmDevice* made) {
    DeviceType* whole = static_cast<DeviceType*>(made);
    whole->~DeviceType();
    release(whole);
}

// The device, made if none is: false when there is no memory for it.
template <typename DeviceType>
bool makeDevice(const char* familyName) {
    if (hasDevice()) { return true; }
    void* memory = allocate(sizeof(DeviceType), alignof(DeviceType));
    if (memory == nullptr) { return false; }
    attach(new (memory) DeviceType(), &destroyDevice<DeviceType>, familyName);
    return true;
}

// Each modem block instance takes a number in its setup(). The first to run
// claims the modem; any other says so on its pins. Zero is never issued.
uint32_t nextId();
bool claim(uint32_t id);
bool isOwner(uint32_t id);
bool hasOwner();

// --- The link -----------------------------------------------------------------

struct Link {
    // A board. port is the UART peripheral, not a pin; -1 is "the board's own".
    int32_t port = 0;
    int32_t rxPin = 44;
    int32_t txPin = 43;
    int32_t rxBuffer = 4096;
    int32_t keyPin = 10;
    int32_t railPin = -1;

    // The Runtime: a serial device path.
    char path[49] = {0};

    uint32_t baud = 115200;

    // What the modem holds (stCapacityConfig), taken once when it is opened.
    // 0 is the library's default each time.
    int32_t sockets = 2;
    int32_t socketBuffer = 1500;      // bytes each way, per socket
    int32_t atQueue = 12;
};

bool sameLink(const Link& a, const Link& b);

// What is wrong with a board's link settings, or null when they are usable.
const char* checkLink(const Link& link);

// Opens the serial link and begins the modem, which starts its bring-up.
// False with a reason. Done once: a modem is not re-opened on other settings
// while the program runs, because closing one is an orderly shutdown that
// takes seconds. Needs the device (makeDevice()).
bool open(const Link& link, const char** why);
bool isOpen();

// THE SERIAL LINK IS HELD ONLY WHILE THE MODEM IS IN USE. On a board it is an
// interrupt, its rings and a service task, and their internal RAM is what
// Wi-Fi needs when a PLC switches to it. The modem block says each scan
// whether it wants the modem; service() gives the link back once it does not
// and the modem is stopped and quiet, and takeLink() takes it again - the
// block before it starts the modem, sendAt() for a command. False, with a
// reason, when it cannot be taken (no memory, or a close not yet finished:
// try next scan). open() takes it the first time.
void want(bool on);
bool wanted();
bool takeLink(const char** why);
const Link& openedWith();

// What the transport says it can hold - the number every read is capped to.
size_t receiveCapacity();

// --- What the core keeps by pointer, so it is kept here ----------------------
//
// Each returns true when the value CHANGED, so the modem block knows to
// restart the bring-up for it to take effect.

bool apn(const char* name, const char* user, const char* password);
bool pin(const char* code);
bool radio(GsmRadioPreference mode, const char* operatorCode,
           const char* catMBands, const char* nbIotBands);

// What is wrong with a radio setting, or null: an operator code of five or six
// digits, band lists of 1..255.
const char* checkRadio(int mode, const char* operatorCode,
                       const char* catMBands, const char* nbIotBands);

// "3, 28" -> {3, 28}. False on anything that is not a list of 1..255.
bool parseBands(const char* text, uint8_t* out, uint8_t capacity, uint8_t* count);

// --- Power --------------------------------------------------------------------

// The Power method's switch. While held off, the modem block does not start
// the modem whatever bConnect says.
void holdOff(bool held);
bool heldOff();

// Whether this board can cut the module's supply, and do it.
bool hasRail();
bool hasKey();
void railOff();

// --- Servicing ----------------------------------------------------------------

// Polls the modem and moves the SMS inbox along. The modem block calls it
// every scan, holding the lock.
void service();

// Bumped every time the module may have lost its settings: a new bring-up or
// a module restart. A method that configured something in the module (GNSS
// power) compares it and configures again.
uint32_t generation();

// --- The SMS inbox --------------------------------------------------------------
//
// THE INDEX IS KEPT, which the core's onSms() handler does not offer: a
// message is fetched by its storage index, handed over, and then deleted from
// the SIM. Without the delete a SIM fills in a few dozen messages and the
// network stops delivering - silently, on a site nobody visits.

struct Sms {
    char     sender[24] = {0};
    char     text[161] = {0};
    uint16_t index = 0;
    GsmParse::GsmDateTime timestamp;
    bool     hasTimestamp = false;
    bool     isPart = false;
    uint8_t  part = 0;
    uint8_t  parts = 0;
};

void smsReceive(bool on);
bool smsTake(Sms& out);
uint32_t smsUnreadable();     // fetched, could not be decoded, deleted

// --- Jobs: one AT command, one SMS ------------------------------------------------
//
// A method's record owns one. The callbacks run inside service() - in
// whichever task is polling - so they write only here, and the record is read
// holding the lock.

struct Job {
    bool busy = false;
    bool done = false;
    GsmResult result = GsmStatus::Ok;
    char reply[255] = {0};
    size_t replyLength = 0;
    bool replyTruncated = false;

    Job* next = nullptr;     // the layer's own list, for freeing at unload
};

// Owned here and freed when the program is unloaded.
Job* newJob();

GsmResult sendAt(Job& job, const char* command, uint32_t timeoutMs);
GsmResult sendSms(Job& job, const char* number, const char* text);

// --- Words -------------------------------------------------------------------

// The text for a result, with the ones that need a sentence of their own.
const char* describe(const GsmResult& result);

// Seconds since 1970 for a calendar date and time, as written - no zone.
int64_t unixSeconds(const GsmParse::GsmDateTime& when);

// TIME pins are signed nanoseconds; durations here are milliseconds. Below
// zero is none, and anything is rounded UP so a duration set never arrives
// as nothing.
inline uint32_t millisOf(int64_t nanoseconds) {
    if (nanoseconds <= 0) { return 0u; }
    const int64_t ms = (nanoseconds + 999999LL) / 1000000LL;
    return ms > 4294967295LL ? 4294967295u : (uint32_t)ms;
}

inline int64_t nanosOf(uint32_t milliseconds) {
    return (int64_t)milliseconds * 1000000LL;
}

} // namespace gsmplc

// =============================================================================
// Arduino's Client, over the one modem, holding the lock
// =============================================================================
//
// MQTT talks to it as it talks to WiFiClient: every call takes the lock and
// then does exactly what a GsmClient on the modem's sockets does.
//
// WHILE THE PUMP SERVICES THE MODEM (a board: see "the modem is serviced
// between scans" in the .cpp), the data calls - available, read, peek, write,
// connected, flush - neither wait for the lock nor poll the modem from the
// caller's task. They were called several times in every scan of the task
// that polls MQTT, and each one waited for the pump to finish its own poll
// and then polled the modem again (measured on a Node UIO: an idle TLS
// connection added about 12 ms to a 50 ms scan). Now a lock the pump holds
// reads as "nothing now": available() and read() answer 0, peek() and read()
// of one byte -1, write() takes nothing (a short write, which MQTT retries on
// its next poll), connected() answers what it last saw, and flush() returns
// at once - the pump sends what is in the socket's ring. stop() still waits
// for the lock: a close must happen, and it only queues the module's close.
// connect() waits for it only to start the dial and for each check of it, and
// never holds it while the dial waits, so the pump keeps servicing the modem
// and the blocks keep reading it. With no pump running, every call waits for
// the lock and polls as it always has, connect() between its checks.
//
// It is an Arduino Client that MAKES its GsmClient at the first connect():
// FB_MqttClient may build its cellular link before the modem block has made
// the device, and a GsmClient is bound to one device's sockets for life.
// Until then every call answers as a closed client does.
//
// Two additions, both because a PLC is not a sketch:
//   - connect() refuses at once, with a reason, when the modem has no data
//     connection, rather than opening a socket that cannot work.
//   - its time limit is settable, so the client that owns it can bound the
//     one call Arduino's interface makes block.

#if defined(GSM_PLATFORM_ARDUINO) || defined(GSM_ARDUINO_SHIM)

#define MODBEE_GSM_PLC_CLIENT 1

class GsmPlcClient : public Client {
public:
    explicit GsmPlcClient(GsmSecurity security = GsmSecurity::Plain) : _security(security) {}
    ~GsmPlcClient();

    // Seconds connect() may take. 0 keeps GsmClient's own limit.
    void setConnectSeconds(int seconds) { _connectSeconds = seconds; }

    int connect(const char* host, uint16_t port) override;
    int connect(IPAddress ip, uint16_t port) override;

    size_t write(uint8_t value) override;
    size_t write(const uint8_t* buffer, size_t size) override;
    int available() override;
    int read() override;
    int read(uint8_t* buffer, size_t size) override;
    int peek() override;
    void flush() override;
    void stop() override;
    uint8_t connected() override;
    operator bool() override { return connected() != 0; }

    // Why the last connect() failed, in words - the modem's state when it was
    // not up, otherwise the socket's own reason.
    const char* why() const { return _why; }

    // The GsmClient underneath, once the first connect() has made it.
    GsmClient* client() const { return _made ? (GsmClient*)(void*)_storage : nullptr; }

    GsmPlcClient(const GsmPlcClient&) = delete;
    GsmPlcClient& operator=(const GsmPlcClient&) = delete;

private:
    // Made at the first connect() with a device to make it on.
    GsmClient* made();

    GsmSecurity _security;
    int _connectSeconds = 0;
    uint8_t _connectedSeen = 0;     // connected() while the pump holds the lock
    bool _made = false;
    alignas(GsmClient) unsigned char _storage[sizeof(GsmClient)];
    char _why[64] = {0};
};

class GsmPlcClientSecure : public GsmPlcClient {
public:
    GsmPlcClientSecure() : GsmPlcClient(GsmSecurity::Module) {}
};

#endif
