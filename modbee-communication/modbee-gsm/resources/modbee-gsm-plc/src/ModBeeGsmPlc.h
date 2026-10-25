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
//   GSM_MODEM        opens it, configures it and polls it
//   every GSM_ block reaches it here
//   MQTT_CLIENT      reaches it here too, through GsmPlcClient, when this
//                    header is on the include path (TRANSPORT := MQTT_CELLULAR)
//
// --- THE LOCK ---
//
// OpenPLC runs each task on its own thread - on the Runtime, and on an ESP32
// in RTOS mode, which is the default there. modbee-gsm is single-threaded by
// design, so every touch of the modem is made holding one recursive lock.
//
// The blocks TRY the lock and skip a scan when another task holds it, so no
// block ever waits on the modem. The one thing that holds it for long is
// GsmClient::connect(), which Arduino's Client interface requires to return a
// verdict (1.35 s plain, 5.2 s TLS, measured on an A7670G); while it runs it
// pumps the modem itself, so nothing is lost by the other blocks standing back.
//
// --- NAMING ---
//
// Every C++ POU of a project is emitted into ONE translation unit, and each
// block's pins are #defines there - ERROR, STATUS, DEVICE, PORT and the rest.
// This header can be included under any block's defines, so it uses no
// all-capitals identifier and nothing that starts with "fb".

#include <ModBeeGsm.h>
#include <GsmCmdBuf.h>

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

// --- The modem ----------------------------------------------------------------

GsmDevice& device();

// Each GSM_MODEM instance takes a number in its setup(). The first to run
// claims the modem; any other says so on its pins. Zero is never issued.
uint32_t nextId();
bool claim(uint32_t id);
bool isOwner(uint32_t id);
bool hasOwner();

// --- The link -----------------------------------------------------------------

struct Link {
    // A board. PORT is the UART peripheral, not a pin; -1 is "the board's own".
    int32_t port = 0;
    int32_t rxPin = 44;
    int32_t txPin = 43;
    int32_t rxBuffer = 4096;
    int32_t keyPin = 10;
    int32_t railPin = -1;

    // The Runtime: a serial device path.
    char path[49] = {0};

    uint32_t baud = 115200;

    // What the modem holds (GSM_MODEM's SOCKETS, SOCKET_BUFFER, AT_QUEUE),
    // taken once when it is opened. 0 is the library's default each time.
    int32_t sockets = 2;
    int32_t socketBuffer = 1500;      // bytes each way, per socket
    int32_t atQueue = 12;
};

bool sameLink(const Link& a, const Link& b);

// Opens the serial link and begins the modem, which starts its bring-up.
// False with a reason. Done once: a modem is not re-opened on other settings
// while the program runs, because closing one is an orderly shutdown that
// takes seconds.
bool open(const Link& link, const char** why);
bool isOpen();

// THE SERIAL LINK IS HELD ONLY WHILE THE MODEM IS IN USE. On a board it is an
// interrupt, its rings and a service task, and their internal RAM is what
// Wi-Fi needs when a PLC switches to it. GSM_MODEM says each scan whether it
// wants the modem; service() gives the link back once it does not and the
// modem is stopped and quiet, and takeLink() takes it again - GSM_MODEM before
// it starts the modem, sendAt() for a command. False, with a reason, when it
// cannot be taken (no memory, or a close not yet finished: try next scan).
// open() takes it the first time.
void want(bool on);
bool takeLink(const char** why);
const Link& openedWith();

// What the transport says it can hold - the number every read is capped to.
size_t receiveCapacity();

// --- What the core keeps by pointer, so it is kept here ----------------------
//
// Each returns true when the value CHANGED, so GSM_MODEM knows to restart the
// bring-up for it to take effect.

bool apn(const char* name, const char* user, const char* password);
bool pin(const char* code);
bool radio(GsmRadioPreference mode, const char* operatorCode,
           const char* catMBands, const char* nbIotBands);

// "3, 28" -> {3, 28}. False on anything that is not a list of 1..255.
bool parseBands(const char* text, uint8_t* out, uint8_t capacity, uint8_t* count);

// --- Power --------------------------------------------------------------------

// GSM_POWER's switch. While held off, GSM_MODEM does not start the modem
// whatever CONNECT says.
void holdOff(bool held);
bool heldOff();

// Whether this board can cut the module's supply, and do it.
bool hasRail();
bool hasKey();
void railOff();

// --- Servicing ----------------------------------------------------------------

// Polls the modem and moves the SMS inbox along. GSM_MODEM calls it every
// scan, holding the lock.
void service();

// Bumped every time the module may have lost its settings: a new bring-up or
// a module restart. A block that configured something in the module (GNSS
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
// A block owns one and keeps it in an __XWORD local. The callbacks run inside
// service() - in whichever task is polling - so they write only here, and the
// block copies the result to its pins on its own next scan.

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

// The text for a result, with the two that need a sentence of their own.
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
// IS A GsmClient - no adapter, no handle. Every call takes the lock and then
// does exactly what GsmClient does, so MQTT talks to it as it talks to
// WiFiClient. GsmPlcClientSecure is the same over the module's TLS.
//
// Two additions, both because a PLC is not a sketch:
//   - connect() refuses at once, with a reason, when the modem has no data
//     connection, rather than opening a socket that cannot work.
//   - its time limit is settable, so the client that owns it can bound the
//     one call Arduino's interface makes block.

#if defined(GSM_PLATFORM_ARDUINO) || defined(GSM_ARDUINO_SHIM)

#define MODBEE_GSM_PLC_CLIENT 1

class GsmPlcClient : public GsmClient {
public:
    explicit GsmPlcClient(GsmSecurity security = GsmSecurity::Plain)
        : GsmClient(gsmplc::device().sockets(), security) {}

    // Seconds connect() may take. 0 keeps GsmClient's own limit.
    void setConnectSeconds(int seconds) { _connectSeconds = seconds; }

    int connect(const char* host, uint16_t port) override;
    int connect(IPAddress ip, uint16_t port) override;
    using GsmClient::connect;

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

private:
    int _connectSeconds = 0;
    char _why[64] = {0};
};

class GsmPlcClientSecure : public GsmPlcClient {
public:
    GsmPlcClientSecure() : GsmPlcClient(GsmSecurity::Module) {}
};

#endif
