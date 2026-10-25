// ModBee GSM for OpenPLC - the one modem a PLC has.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see the modbee-gsm LICENSE. Commercial use requires a
// separate licence.

#include "ModBeeGsmPlc.h"
#include "GsmPlcUart.h"

#include <new>
#include <stdio.h>
#include <string.h>

#if defined(GSM_PLATFORM_ARDUINO)
    #include <Arduino.h>
    #if defined(ARDUINO_ARCH_ESP32)
        #include <freertos/FreeRTOS.h>
        #include <freertos/semphr.h>
        #include <esp_heap_caps.h>
        #include <stdlib.h>
    #endif
#else
    #include <mutex>
#endif
#include <GsmNoExcept.h>   // last: no exception tables for this file either

namespace gsmplc {

namespace {

void copyText(char* out, size_t capacity, const char* in) {
    size_t i = 0;
    if (in != nullptr) {
        for (; i + 1 < capacity && in[i] != '\0'; i++) { out[i] = in[i]; }
    }
    out[i] = '\0';
}

bool sameText(const char* a, const char* b) {
    return strcmp(a != nullptr ? a : "", b != nullptr ? b : "") == 0;
}

// --- Power: the two lines a board may have -----------------------------------
//
// GsmPowerControl's line-level hooks. modbee-gsm owns the ORDER and the PULSE
// WIDTHS - they are module facts, 50 ms on an A7670 and 500 ms on a SIM707x -
// and these only move the lines. HIGH presses the key and HIGH powers the
// rail, which is how the ModBee HATs (and SIMCom's reference design, an NPN
// pulling PWRKEY down) are wired.
class PlcPower : public GsmPowerControl {
public:
    int32_t key = -1;
    int32_t rail = -1;
    bool railCommanded = false;
    bool railOn = false;

    bool setPowerKey(bool asserted) override {
#if defined(GSM_PLATFORM_ARDUINO)
        if (key < 0) { return false; }
        digitalWrite((uint8_t)key, asserted ? HIGH : LOW);
        return true;
#else
        (void)asserted;
        return false;
#endif
    }

    bool setSupply(bool on) override {
#if defined(GSM_PLATFORM_ARDUINO)
        if (rail < 0) { return false; }
        digitalWrite((uint8_t)rail, on ? HIGH : LOW);
        railCommanded = true;
        railOn = on;
        return true;
#else
        (void)on;
        return false;
#endif
    }

    // With the rail down the module is DEFINITELY off. With it up nobody can
    // say: no STATUS line reaches the header, and a pulsed key is a toggle.
    GsmTristate isPoweredOn() const override {
        if (rail >= 0 && railCommanded && !railOn) { return GsmTristate::No; }
        return GsmTristate::Unknown;
    }
};

// --- The SMS pipeline -----------------------------------------------------------

const uint8_t kPendingMax = 16;
const uint8_t kInboxMax = 4;
const uint8_t kFetchAttempts = 3;

struct SmsPipeline {
    bool on = false;

    // serviceSms(), set by the first smsReceive(): a program with no
    // GSM_SMS_RECEIVE never calls it, so it links none of the fetch and PDU
    // code. Until then nothing is pending (onModemEvent records only when on).
    void (*service)() = nullptr;

    uint16_t pending[kPendingMax] = {0};
    uint8_t  pendingCount = 0;
    uint8_t  attempts = 0;

    Sms     inbox[kInboxMax];
    uint8_t inboxHead = 0;
    uint8_t inboxCount = 0;

    bool     fetching = false;
    uint16_t fetchIndex = 0;
    bool     expectingPdu = false;
    uint8_t  pdu[GSM_SMS_PDU_MAX] = {0};
    size_t   pduLength = 0;

    uint32_t unreadable = 0;
};

struct State {
    // Declared first so it is destroyed last: a job outlives the device that
    // might still hold a pointer to it.
    Job* jobs = nullptr;

    GsmDevice device;
    PlcPower  power;

#if defined(GSM_PLATFORM_HOST)
    GsmSerialTransport serial;
#endif
    GsmTransport* transport = nullptr;

    bool   open = false;
    Link   link;
    size_t capacity = 0;
    char   why[96] = {0};

    uint32_t lastId = 0;
    uint32_t owner = 0;

    bool held = false;

    // Whether GSM_MODEM wants the modem (CONNECT, and not held off). While it
    // does not, and the modem is quiet, the serial link is given back.
    bool wanted = false;

    bool apnSet = false;
    char apnName[GSM_APN_MAX + 1] = {0};
    char apnUser[GSM_APN_USER_MAX + 1] = {0};
    char apnPassword[GSM_APN_PASSWORD_MAX + 1] = {0};

    bool pinSet = false;
    char pinCode[9] = {0};

    bool radioSet = false;
    GsmRadioPreference radioMode = GsmRadioPreference::Automatic;
    char operatorCode[8] = {0};
    char catMText[65] = {0};
    char nbIotText[65] = {0};
    uint8_t catM[32] = {0};
    uint8_t catMCount = 0;
    uint8_t nbIot[32] = {0};
    uint8_t nbIotCount = 0;

    uint32_t generation = 1;
    uint32_t seenBringUps = 0;
    uint32_t seenRestarts = 0;
    uint32_t seenRecoveries = 0;

    SmsPipeline sms;

    ~State() {
        while (jobs != nullptr) {
            Job* next = jobs->next;
            delete jobs;
            jobs = next;
        }
    }
};

// THE STATE IS ON THE HEAP ON AN ESP32, IN PSRAM WHERE THERE IS ANY. It is
// about 5 kB - the GsmDevice, the SMS pipeline, the APN and band settings -
// and the sockets' buffers and the AT queue (about 9 kB at the defaults, sized
// by GSM_MODEM's SOCKETS, SOCKET_BUFFER and AT_QUEUE) are taken the same way
// when the modem is opened (gsm_allocLarge). In .bss it was 14 kB of the
// internal RAM the PLC program's own variables need. Nothing in it is touched
// from an interrupt or with the flash cache off, so external RAM costs it
// nothing that matters.
//
// BUILT AT THE FIRST CALL, NEVER DURING STATIC INITIALISATION, and that is
// what puts it in PSRAM: the Arduino core adds PSRAM to the heap in
// initArduino(), after every static constructor has run. The first call is a
// GSM block's setup(), which runs in the first scan - long after that. If a
// call ever did come earlier, or the board has no PSRAM, it falls back to
// internal RAM and still works.
//
// Never destroyed: a PLC does not exit. The Runtime (a host) keeps the
// ordinary static, which its exit destroys in order.
State& state() {
#if defined(ARDUINO_ARCH_ESP32)
    static State* const s = []() -> State* {
        void* memory = heap_caps_aligned_alloc(alignof(State), sizeof(State),
                                               MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
        if (memory == nullptr) {
            memory = heap_caps_aligned_alloc(alignof(State), sizeof(State),
                                             MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
        }
        // No exceptions on this core, and no PLC without its modem state: a
        // board that cannot find 14 kB at its first GSM scan cannot run.
        if (memory == nullptr) { abort(); }
        return new (memory) State();
    }();
    return *s;
#else
    static State s;
    return s;
#endif
}

// --- The lock ------------------------------------------------------------------

#if defined(ARDUINO_ARCH_ESP32)
SemaphoreHandle_t theLock() {
    static SemaphoreHandle_t handle = xSemaphoreCreateRecursiveMutex();
    return handle;
}
#elif defined(GSM_PLATFORM_HOST)
std::recursive_mutex& theLock() {
    static std::recursive_mutex mutex;
    return mutex;
}
#endif

// --- Events: what GsmDevice routes, plus the SMS index -------------------------
//
// GsmDevice routes the modem's events to its socket and SMS layers. This
// replaces that routing with the same call to the socket layer - and, for an
// arriving SMS, keeps the STORAGE INDEX, which the core's own handler drops.
// An SMS that arrives while no GSM_SMS_RECEIVE is enabled is left on the SIM,
// unread, rather than fetched and thrown away.
void onModemEvent(void* context, GsmUrcKind kind, const GsmUrcInfo& info) {
    (void)context;
    State& s = state();
    s.device.sockets().handleEvent(kind, info);

    if (kind != GsmUrcKind::SmsReceived || !s.sms.on) { return; }
    const uint16_t index = (uint16_t)info.value;
    for (uint8_t i = 0; i < s.sms.pendingCount; i++) {
        if (s.sms.pending[i] == index) { return; }
    }
    if (s.sms.pendingCount < kPendingMax) {
        s.sms.pending[s.sms.pendingCount++] = index;
    }
}

void dropPending() {
    SmsPipeline& p = state().sms;
    if (p.pendingCount == 0) { return; }
    for (uint8_t i = 1; i < p.pendingCount; i++) { p.pending[i - 1] = p.pending[i]; }
    p.pendingCount--;
    p.attempts = 0;
}

// The same reading of a +CMGR reply as GsmSms::onFetchReply: a header line,
// then the PDU as hexadecimal.
void onFetchReply(void* context, const char* line, size_t length) {
    (void)context;
    SmsPipeline& p = state().sms;
    if (length >= 5 && line[0] == '+') {
        p.expectingPdu = true;
        return;
    }
    if (!p.expectingPdu || length < 2) { return; }
    const size_t octets = GsmSmsPdu::hexToOctets(line, length, p.pdu, sizeof p.pdu);
    if (octets > 0) {
        p.pduLength = octets;
        p.expectingPdu = false;
    }
}

void deleteStored(uint16_t index) {
    // Fire and forget: a delete that fails leaves the message on the SIM,
    // where the next one to arrive at that index replaces it anyway.
    state().device.deleteSms(index);
}

void onFetchDone(void* context, GsmResult result) {
    (void)context;
    State& s = state();
    SmsPipeline& p = s.sms;
    p.fetching = false;
    p.expectingPdu = false;

    if (result.isOk() && p.pduLength > 0) {
        GsmSmsMessage message;
        if (GsmSmsPdu::decodeDeliver(p.pdu, p.pduLength, message)) {
            const uint8_t slot = (uint8_t)((p.inboxHead + p.inboxCount) % kInboxMax);
            Sms& out = p.inbox[slot];
            out = Sms();
            copyText(out.sender, sizeof out.sender, message.sender);
            copyText(out.text, sizeof out.text, message.text);
            out.index = p.fetchIndex;
            out.timestamp = message.timestamp;
            out.hasTimestamp = message.hasTimestamp;
            out.isPart = message.isPart;
            out.part = message.partIndex;
            out.parts = message.partCount;
            p.inboxCount++;
        } else {
            // Not something this library can read - a status report, a
            // class it does not decode. Deleted all the same: left there it
            // would hold a slot for ever.
            p.unreadable++;
        }
        deleteStored(p.fetchIndex);
        dropPending();
        return;
    }

    // The module answered with an error (an empty slot, a bad index): there is
    // nothing to fetch, and nothing to delete.
    if (result.status() == GsmStatus::ModuleError || result.status() == GsmStatus::Error) {
        dropPending();
        return;
    }

    // A timeout or a cancellation is the modem's trouble, not the message's.
    // Tried again, a few times.
    if (++p.attempts >= kFetchAttempts) { dropPending(); }
}

void serviceSms() {
    State& s = state();
    SmsPipeline& p = s.sms;
    GsmDriver* driver = s.device.driver();
    if (!p.on || driver == nullptr) { return; }
    // Switched off: nothing to configure or fetch, and nothing to hold the
    // serial link for. Configured again when it is wanted.
    if (!s.wanted) { return; }

    // PDU mode and new-message reports: idempotent, and a no-op once done.
    if (!s.device.sms().isReady()) { s.device.sms().configure(); }

    if (p.fetching || p.pendingCount == 0 || p.inboxCount >= kInboxMax) { return; }
    if (!s.device.isRegistered()) { return; }

    GsmCmdBuf command;
    driver->smsReadCommand(p.pending[0], command);
    if (command.isEmpty() || command.overflowed()) {
        dropPending();
        return;
    }

    p.fetchIndex = p.pending[0];
    p.pduLength = 0;
    p.expectingPdu = false;
    const GsmResult accepted = s.device.sendAt(command.text(), 10000,
                                               &onFetchReply, &onFetchDone, nullptr);
    if (accepted.status() == GsmStatus::Queued) { p.fetching = true; }
}

void onJobReply(void* context, const char* line, size_t length) {
    Job* job = (Job*)context;
    if (job->replyLength > 0 && job->replyLength + 1 < sizeof job->reply) {
        job->reply[job->replyLength++] = '\n';
    }
    for (size_t i = 0; i < length; i++) {
        if (job->replyLength + 1 >= sizeof job->reply) {
            job->replyTruncated = true;
            break;
        }
        job->reply[job->replyLength++] = line[i];
    }
    job->reply[job->replyLength] = '\0';
}

void onJobDone(void* context, GsmResult result) {
    Job* job = (Job*)context;
    job->result = result;
    job->done = true;
    job->busy = false;
}

} // namespace

// =============================================================================

void lock() {
#if defined(ARDUINO_ARCH_ESP32)
    xSemaphoreTakeRecursive(theLock(), portMAX_DELAY);
#elif defined(GSM_PLATFORM_HOST)
    theLock().lock();
#endif
}

void unlock() {
#if defined(ARDUINO_ARCH_ESP32)
    xSemaphoreGiveRecursive(theLock());
#elif defined(GSM_PLATFORM_HOST)
    theLock().unlock();
#endif
}

bool tryLock() {
#if defined(ARDUINO_ARCH_ESP32)
    return xSemaphoreTakeRecursive(theLock(), 0) == pdTRUE;
#elif defined(GSM_PLATFORM_HOST)
    return theLock().try_lock();
#else
    return true;     // one thread, nothing to exclude
#endif
}

GsmDevice& device() { return state().device; }

#if defined(ARDUINO_ARCH_ESP32)
// =============================================================================
// THE MODEM IS SERVICED BETWEEN SCANS, NOT ONLY IN THEM
// =============================================================================
//
// Every AT exchange is a turn-around: the command goes, the module answers,
// and only a poll that reads the answer sends the next command. Polled from
// the PLC's scan alone, each turn-around waited for the next scan - measured
// on a Node UIO with a 50 ms COMMS task, a socket send (command, "> ",
// payload, OK, +CIPSEND) took 108 ms on average and the 115200 baud link sat
// idle 38% of an OTA download, which ran at 6.4 kB/s of an 11.5 kB/s line.
//
// So a small task polls the modem whenever the UART interrupt says bytes
// arrived, and every couple of milliseconds besides, under the same lock the
// blocks take. It does nothing the blocks did not already do in their scan -
// GsmDevice::poll() - it just does it when the modem is ready rather than when
// the PLC next looks. Core 0, below every PLC task, which run on core 1.
//
// IT EXISTS ONLY WHILE THE MODEM IS IN USE, like the serial link it serves:
// started when the link is taken and stopped before the link is given back
// (see takeLink() / releaseLink() below).
//
// It also moves what the UART interrupt staged (a small ring in internal
// RAM) into the receive ring (PSRAM), without the lock: that hand-over must
// keep up with the line even while a block holds the lock for a while.
//
// ITS STACK, measured on a Node UIO (A7670, 2026-10-16): 3808 bytes at the
// deepest seen - bring-up, reconnects, MQTT and a signed OTA over LTE - so
// the 4096 it had left 288. An arriving SMS is decoded in the same callbacks
// (a 200-byte septet buffer and the ~200-byte message on top) and was not
// part of that run. 5120 covers both with ~700 bytes to spare. It is internal
// RAM only while the modem is in use; switched off, it is given back.
constexpr uint32_t kPumpEveryMs = 2;
constexpr uint32_t kPumpStack = 5120;
constexpr UBaseType_t kPumpPriority = 2;

// The task's handle and its two flags: asked to stop, and gone. Written by
// the layer under the lock and by the task as its last act.
struct Pump {
    TaskHandle_t task = nullptr;
    volatile bool quit = false;
    volatile bool gone = true;
};

Pump& thePump() {
    static Pump one;
    return one;
}

void pump(void*) {
    Pump& p = thePump();
    IramUart& uart = iramUart();
    while (!p.quit) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(kPumpEveryMs));
        if (p.quit) { break; }
        uart.drain();
        if (xSemaphoreTakeRecursive(theLock(), pdMS_TO_TICKS(kPumpEveryMs)) != pdTRUE) {
            continue;               // a block has it; it is polling anyway
        }
        State& s = state();
        if (s.open && !p.quit) { s.device.poll(); }
        xSemaphoreGiveRecursive(theLock());
    }
    // The last thing it touches. The layer frees the rings only after this,
    // and the interrupt that woke it was removed before quit was set.
    p.gone = true;
    vTaskDelete(nullptr);
}

bool startPump() {
    Pump& p = thePump();
    if (p.task != nullptr) { return true; }
    p.quit = false;
    p.gone = false;
    IramUart& uart = iramUart();
    uart.setMover(true);            // before the task runs: one mover at a time
    if (xTaskCreatePinnedToCore(&pump, "modbee-gsm", kPumpStack, nullptr, kPumpPriority,
                                &p.task, 0) != pdPASS) {
        p.task = nullptr;
        p.gone = true;
        uart.setMover(false);       // readable() moves the bytes itself
        return false;
    }
    uart.wakeOnReceive(p.task);
    return true;
}

// Asks the task to stop and waits for it, briefly: it sees the request
// within one tick unless it is waiting for the lock, which the caller holds
// and which it gives up on after kPumpEveryMs. True once it is gone.
bool stopPump() {
    Pump& p = thePump();
    if (p.task == nullptr) { return true; }
    // Woken first, told second: it cannot leave (and free its handle) before
    // quit is set, so the notification never reaches a task that is gone.
    xTaskNotifyGive(p.task);
    p.quit = true;
    for (int waited = 0; !p.gone && waited < 50; waited++) { vTaskDelay(1); }
    if (!p.gone) { return false; }  // asked again on the next scan
    p.task = nullptr;
    return true;
}
#endif

uint32_t nextId() {
    Hold hold;
    return ++state().lastId;
}

bool claim(uint32_t id) {
    State& s = state();
    if (id == 0) { return false; }
    if (s.owner == 0) { s.owner = id; }
    return s.owner == id;
}

bool isOwner(uint32_t id) { return id != 0 && state().owner == id; }
bool hasOwner() { return state().owner != 0; }

bool sameLink(const Link& a, const Link& b) {
    return a.port == b.port && a.rxPin == b.rxPin && a.txPin == b.txPin &&
           a.rxBuffer == b.rxBuffer && a.keyPin == b.keyPin &&
           a.railPin == b.railPin && a.baud == b.baud &&
           a.sockets == b.sockets && a.socketBuffer == b.socketBuffer &&
           a.atQueue == b.atQueue &&
           strcmp(a.path, b.path) == 0;
}

bool open(const Link& link, const char** why) {
    State& s = state();
    *why = nullptr;
    if (s.open) { return true; }

    const uint32_t baud = link.baud != 0 ? link.baud : 115200;

#if defined(GSM_PLATFORM_ARDUINO)
  #if defined(ARDUINO_ARCH_ESP32)
    if (link.rxBuffer < 256 || link.rxBuffer > 32768) {
        *why = "RX_BUFFER must be 256 to 32768";
        return false;
    }

    // THE UART IS DRIVEN FROM AN IRAM INTERRUPT, NOT BY HardwareSerial - see
    // GsmPlcUart.h. The core's own interrupt cannot run while flash is being
    // erased or written, the HAT header has no RTS or CTS, and the bytes that
    // arrived then were lost. The receive ring is RX_BUFFER bytes and the
    // library is told exactly that, because every modem read is capped to it.
    //
    // Taken here and given back while the modem is switched off: see
    // takeLink() and releaseLink().
    IramUart& uart = iramUart();
    if (!uart.open((int)link.port, baud, (int)link.rxPin, (int)link.txPin,
                   (size_t)link.rxBuffer, why)) {
        return false;
    }
    s.transport = &uart;
  #else
    *why = "modbee-gsm drives a modem from ESP32 boards";
    return false;
  #endif

    // The key released before anything else: a line left floating, or high
    // from a warm reset, is a held power button.
    if (link.keyPin >= 0) {
        pinMode((uint8_t)link.keyPin, OUTPUT);
        digitalWrite((uint8_t)link.keyPin, LOW);
    }
    if (link.railPin >= 0) { pinMode((uint8_t)link.railPin, OUTPUT); }
    s.power.key = link.keyPin;
    s.power.rail = link.railPin;
    s.device.powerControl(&s.power);
#else
    if (link.path[0] == '\0') {
        *why = "set DEVICE to the modem's serial port";
        return false;
    }
    s.serial.configure(link.path, baud);
    s.transport = &s.serial;
#endif

    if (link.sockets < 0 || link.sockets > 255 || link.socketBuffer < 0 ||
        link.atQueue < 0 || link.atQueue > 255) {
        *why = "SOCKETS and AT_QUEUE must be 0 to 255, SOCKET_BUFFER 0 or more";
        return false;
    }
    s.device.setCapacity((uint8_t)link.sockets, (size_t)link.socketBuffer,
                         (size_t)link.socketBuffer, (size_t)link.atQueue);

    if (!s.device.begin(s.transport)) {
        if (s.device.beginError() != nullptr) {
            // Ours, not the link's: the board has no room for what was asked.
            *why = s.device.beginError();
            return false;
        }
#if defined(GSM_PLATFORM_HOST)
        copyText(s.why, sizeof s.why, s.serial.lastError().c_str());
        *why = s.why[0] != '\0' ? s.why : "the serial device would not open";
#else
        *why = "the serial link would not open";
#endif
        return false;
    }

    // After begin(), which installs GsmDevice's own routing.
    s.device.modem().onEvent(&onModemEvent, nullptr);

    s.link = link;
    s.link.baud = baud;
    s.capacity = s.transport->receiveCapacity();
    s.open = true;
#if defined(ARDUINO_ARCH_ESP32)
    // Without it the modem still works, at the scan's pace - so a failure to
    // start it is not a failure to open.
    startPump();
#endif
    return true;
}

namespace {

#if defined(ARDUINO_ARCH_ESP32)
// A block's command (sendAt, sendSms) still waiting for its answer.
bool jobsBusy() {
    for (const Job* job = state().jobs; job != nullptr; job = job->next) {
        if (job->busy) { return true; }
    }
    return false;
}
#endif

// Gives the serial link back - the interrupt, the rings, the service task -
// and with them all the internal RAM the modem holds. True once nothing is
// held. Called holding the lock.
bool releaseLink() {
#if defined(ARDUINO_ARCH_ESP32)
    IramUart& uart = iramUart();
    if (!uart.holdsAnything()) { return true; }
    uart.stopInterrupt();               // nothing arrives, nothing wakes the task
    if (!stopPump()) { return false; }  // the rings wait for the task to go
    uart.close();
#endif
    return true;
}

} // namespace

bool takeLink(const char** why) {
    State& s = state();
    *why = nullptr;
    if (!s.open) {
        *why = "no GSM_MODEM has opened the modem";
        return false;
    }
#if defined(ARDUINO_ARCH_ESP32)
    IramUart& uart = iramUart();
    if (uart.isOpen()) { return true; }
    if (!releaseLink()) {
        *why = "the modem's serial link is still closing";
        return false;
    }
    const Link& l = s.link;
    if (!uart.open((int)l.port, l.baud, (int)l.rxPin, (int)l.txPin, (size_t)l.rxBuffer, why)) {
        return false;
    }
    startPump();
#endif
    return true;
}

void want(bool on) { state().wanted = on; }

bool isOpen() { return state().open; }
const Link& openedWith() { return state().link; }
size_t receiveCapacity() { return state().capacity; }

bool apn(const char* name, const char* user, const char* password) {
    State& s = state();
    if (s.apnSet && sameText(s.apnName, name) && sameText(s.apnUser, user) &&
        sameText(s.apnPassword, password)) {
        return false;
    }
    copyText(s.apnName, sizeof s.apnName, name);
    copyText(s.apnUser, sizeof s.apnUser, user);
    copyText(s.apnPassword, sizeof s.apnPassword, password);
    s.device.apn(s.apnName, s.apnUser, s.apnPassword);
    s.apnSet = true;
    return true;
}

bool pin(const char* code) {
    State& s = state();
    if (s.pinSet && sameText(s.pinCode, code)) { return false; }
    copyText(s.pinCode, sizeof s.pinCode, code);
    s.device.pin(s.pinCode);
    s.pinSet = true;
    return true;
}

bool parseBands(const char* text, uint8_t* out, uint8_t capacity, uint8_t* count) {
    *count = 0;
    if (text == nullptr) { return true; }
    const char* at = text;
    while (*at != '\0') {
        while (*at == ' ' || *at == ',' || *at == ';') { at++; }
        if (*at == '\0') { break; }
        if (*at < '0' || *at > '9') { return false; }
        uint32_t value = 0;
        while (*at >= '0' && *at <= '9') {
            value = value * 10u + (uint32_t)(*at - '0');
            if (value > 255u) { return false; }
            at++;
        }
        if (value == 0) { return false; }
        if (*at != '\0' && *at != ' ' && *at != ',' && *at != ';') { return false; }
        if (*count >= capacity) { return false; }
        out[(*count)++] = (uint8_t)value;
    }
    return true;
}

bool radio(GsmRadioPreference mode, const char* operatorCode,
           const char* catMBands, const char* nbIotBands) {
    State& s = state();
    if (s.radioSet && s.radioMode == mode && sameText(s.operatorCode, operatorCode) &&
        sameText(s.catMText, catMBands) && sameText(s.nbIotText, nbIotBands)) {
        return false;
    }
    s.radioMode = mode;
    copyText(s.operatorCode, sizeof s.operatorCode, operatorCode);
    copyText(s.catMText, sizeof s.catMText, catMBands);
    copyText(s.nbIotText, sizeof s.nbIotText, nbIotBands);
    if (!parseBands(s.catMText, s.catM, sizeof s.catM, &s.catMCount)) { s.catMCount = 0; }
    if (!parseBands(s.nbIotText, s.nbIot, sizeof s.nbIot, &s.nbIotCount)) { s.nbIotCount = 0; }

    s.device.radioPreference(mode);
    s.device.operatorCode(s.operatorCode[0] != '\0' ? s.operatorCode : nullptr);
    GsmBandList catM;
    catM.bands = s.catMCount > 0 ? s.catM : nullptr;
    catM.count = s.catMCount;
    GsmBandList nbIot;
    nbIot.bands = s.nbIotCount > 0 ? s.nbIot : nullptr;
    nbIot.count = s.nbIotCount;
    s.device.bands(catM, nbIot);

    // The first call only records the defaults; it is not a change anybody
    // made, and must not restart a bring-up.
    const bool first = !s.radioSet;
    s.radioSet = true;
    return !first;
}

void holdOff(bool held) { state().held = held; }
bool heldOff() { return state().held; }
bool hasRail() { return state().power.rail >= 0; }
bool hasKey() { return state().power.key >= 0; }
void railOff() { state().power.setSupply(false); }

void service() {
    State& s = state();
    if (!s.open) { return; }
    s.device.poll();
    if (s.sms.service != nullptr) { s.sms.service(); }

    const GsmModem::Counters& c = s.device.counters();
    if (c.bringUps != s.seenBringUps || c.moduleRestarts != s.seenRestarts ||
        c.recoveries != s.seenRecoveries) {
        s.seenBringUps = c.bringUps;
        s.seenRestarts = c.moduleRestarts;
        s.seenRecoveries = c.recoveries;
        s.generation++;
    }

    // NOT IN USE: the link is given back, AT ONCE - a PLC switching to Wi-Fi
    // needs the RAM while Wi-Fi joins, not seconds later. Switched off
    // (CONNECT FALSE, or held off by GSM_POWER) and stopped (Off, or Failed,
    // which does nothing while the modem is not wanted).
    //
    // What a block asked for is answered first - GSM_POWER's power-down
    // command, a GSM_AT, an SMS - so nothing anyone waits on is cut off. What
    // the library itself still had going (a bring-up step that was on the
    // wire, a status query, a socket's close) is for a modem nobody wants:
    // concluded as cancelled, each caller told once, as the engine promises.
    // The next takeLink() opens the link again. A board only: the Runtime's
    // serial device holds no internal RAM and stays open.
#if defined(ARDUINO_ARCH_ESP32)
    const GsmState now = s.device.state();
    if (!s.wanted && (now == GsmState::Off || now == GsmState::Failed) && !jobsBusy()) {
        GsmAtEngine& engine = s.device.engine();
        if (!engine.isIdle()) { engine.abandonAll(GsmStatus::Cancelled); }
        releaseLink();
    }
#endif
}

uint32_t generation() { return state().generation; }

void smsReceive(bool on) {
    SmsPipeline& p = state().sms;
    if (p.on && !on) { p.pendingCount = 0; }
    p.on = on;
    p.service = &serviceSms;
}

bool smsTake(Sms& out) {
    SmsPipeline& p = state().sms;
    if (p.inboxCount == 0) { return false; }
    out = p.inbox[p.inboxHead];
    p.inboxHead = (uint8_t)((p.inboxHead + 1) % kInboxMax);
    p.inboxCount--;
    return true;
}

uint32_t smsUnreadable() { return state().sms.unreadable; }

Job* newJob() {
    State& s = state();
    Job* job = new (std::nothrow) Job();
    if (job == nullptr) { return nullptr; }
    job->next = s.jobs;
    s.jobs = job;
    return job;
}

GsmResult sendAt(Job& job, const char* command, uint32_t timeoutMs) {
    if (!state().open) { return GsmStatus::NotInitialised; }
    // A command is a use: the link is taken for it, and given back once the
    // modem is quiet again if nobody wants it.
    const char* why = nullptr;
    if (!takeLink(&why)) { return GsmStatus::NotReady; }
    job.done = false;
    job.reply[0] = '\0';
    job.replyLength = 0;
    job.replyTruncated = false;
    job.result = GsmStatus::Queued;
    const GsmResult accepted = state().device.sendAt(command, timeoutMs, &onJobReply,
                                                     &onJobDone, &job);
    job.busy = (accepted.status() == GsmStatus::Queued);
    if (!job.busy) { job.result = accepted; }
    return accepted;
}

GsmResult sendSms(Job& job, const char* number, const char* text) {
    State& s = state();
    if (!s.open) { return GsmStatus::NotInitialised; }
    if (!s.device.isRegistered()) { return GsmStatus::NotReady; }
    job.done = false;
    job.result = GsmStatus::Queued;
    const GsmResult accepted = s.device.sendSms(number, text, &onJobDone, &job);
    job.busy = (accepted.status() == GsmStatus::Queued);
    if (!job.busy) { job.result = accepted; }
    return accepted;
}

const char* describe(const GsmResult& result) {
    if (result.space() == GsmErrorSpace::Cme && result.code() == 16 &&
        state().device.modem().pinRejected()) {
        return "the SIM refused SIM_PIN; it is not tried again until it changes";
    }
    if (result.space() == GsmErrorSpace::Cme && result.code() == 11) {
        return "the SIM wants a PIN; set SIM_PIN";
    }
    if (result.space() == GsmErrorSpace::Cme && result.code() == 12) {
        return "the SIM is PUK-locked; it needs its PUK, on site";
    }
    return result.describe();
}

int64_t unixSeconds(const GsmParse::GsmDateTime& when) {
    // Howard Hinnant's days_from_civil: exact for every Gregorian date.
    int64_t year = (int64_t)when.year;
    const int64_t month = (int64_t)when.month;
    year -= (month <= 2) ? 1 : 0;
    const int64_t era = (year >= 0 ? year : year - 399) / 400;
    const int64_t yearOfEra = year - era * 400;
    const int64_t dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + (int64_t)when.day - 1;
    const int64_t dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    const int64_t days = era * 146097 + dayOfEra - 719468;
    return days * 86400 + (int64_t)when.hour * 3600 + (int64_t)when.minute * 60 +
           (int64_t)when.second;
}

} // namespace gsmplc

// =============================================================================

#if defined(MODBEE_GSM_PLC_CLIENT)

int GsmPlcClient::connect(const char* host, uint16_t port) {
    gsmplc::Hold hold;
    _why[0] = '\0';
    if (!gsmplc::isOpen()) {
        snprintf(_why, sizeof _why, "no GSM_MODEM has opened the modem");
        return 0;
    }
    GsmDevice& gsm = gsmplc::device();
    if (!gsm.isReady()) {
        snprintf(_why, sizeof _why, "the modem has no data connection (%s)",
                 gsm.stateName());
        return 0;
    }
    const int opened = _connectSeconds > 0
        ? GsmClient::connect(host, port, _connectSeconds)
        : GsmClient::connect(host, port);
    if (opened == 0) {
        snprintf(_why, sizeof _why, "%s", gsmplc::describe(lastError()));
    }
    return opened;
}

int GsmPlcClient::connect(IPAddress ip, uint16_t port) {
    gsmplc::Hold hold;
    _why[0] = '\0';
    if (!gsmplc::isOpen() || !gsmplc::device().isReady()) {
        snprintf(_why, sizeof _why, "the modem has no data connection");
        return 0;
    }
    const int opened = GsmClient::connect(ip, port);
    if (opened == 0) {
        snprintf(_why, sizeof _why, "%s", gsmplc::describe(lastError()));
    }
    return opened;
}

size_t GsmPlcClient::write(uint8_t value) {
    gsmplc::Hold hold;
    return GsmClient::write(value);
}

size_t GsmPlcClient::write(const uint8_t* buffer, size_t size) {
    gsmplc::Hold hold;
    return GsmClient::write(buffer, size);
}

int GsmPlcClient::available() {
    gsmplc::Hold hold;
    return GsmClient::available();
}

int GsmPlcClient::read() {
    gsmplc::Hold hold;
    return GsmClient::read();
}

int GsmPlcClient::read(uint8_t* buffer, size_t size) {
    gsmplc::Hold hold;
    return GsmClient::read(buffer, size);
}

int GsmPlcClient::peek() {
    gsmplc::Hold hold;
    return GsmClient::peek();
}

void GsmPlcClient::flush() {
    gsmplc::Hold hold;
    GsmClient::flush();
}

void GsmPlcClient::stop() {
    gsmplc::Hold hold;
    GsmClient::stop();
}

uint8_t GsmPlcClient::connected() {
    gsmplc::Hold hold;
    return GsmClient::connected();
}

#endif
