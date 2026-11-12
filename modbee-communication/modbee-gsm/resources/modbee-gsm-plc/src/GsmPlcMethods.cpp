// ModBee GSM for OpenPLC - the modem block's methods.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see the modbee-gsm LICENSE. Commercial use requires a
// separate licence.

#include "GsmPlcMethods.h"

#include <new>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(ARDUINO_ARCH_ESP32)
    #include <freertos/FreeRTOS.h>
    #include <freertos/task.h>
#elif defined(GSM_PLATFORM_HOST)
    #include <pthread.h>
#endif
#include <GsmNoExcept.h>   // last: no exception tables for this file either

#ifndef GSM_PLC_MAX_RECORDS
#define GSM_PLC_MAX_RECORDS 64
#endif

namespace gsmplc {

uintptr_t currentTask() {
#if defined(ARDUINO_ARCH_ESP32)
    return (uintptr_t)xTaskGetCurrentTaskHandle();
#elif defined(GSM_PLATFORM_HOST)
    return (uintptr_t)pthread_self();
#else
    return 1;
#endif
}

namespace {

void copyText(char* out, size_t capacity, const char* in, size_t length = (size_t)-1) {
    size_t i = 0;
    if (in != nullptr) {
        for (; i + 1 < capacity && i < length && in[i] != '\0'; i++) { out[i] = in[i]; }
    }
    out[i] = '\0';
}

uint32_t hashText(uint32_t h, const char* text) {
    for (; text != nullptr && *text != '\0'; ++text) {
        h ^= (uint8_t)*text;
        h *= 16777619u;
    }
    return h;
}

// E_GsmResult's names, for a failing call named on the block.
const char* resultName(int result) {
    static const char* const names[] = {
        "Queued", "Ok", "NotInitialised", "InvalidArgument", "NotReady", "NoBearer",
        "NoSocketAvailable", "QueueFull", "Superseded", "Cancelled", "TooLarge",
        "NotSupportedByModule", "Error", "ModuleError", "Timeout", "SocketClosed",
        "BearerLost", "Unresponsive", "PoweredOff", "RegistrationDenied", "WrongTask"};
    return result >= 0 && result <= kWrongTask ? names[result] : "?";
}

int statusOf(const GsmResult& result) { return (int)result.status(); }

const int kQueued = (int)GsmStatus::Queued;
const int kOk = (int)GsmStatus::Ok;
const int kNotInitialised = (int)GsmStatus::NotInitialised;
const int kInvalidArgument = (int)GsmStatus::InvalidArgument;
const int kNotReady = (int)GsmStatus::NotReady;
const int kQueueFull = (int)GsmStatus::QueueFull;
const int kTooLarge = (int)GsmStatus::TooLarge;
const int kNotSupported = (int)GsmStatus::NotSupportedByModule;
const int kNoSocket = (int)GsmStatus::NoSocketAvailable;
const int kSocketClosed = (int)GsmStatus::SocketClosed;
const int kTimeout = (int)GsmStatus::Timeout;

enum Kind : uint8_t {
    kindSms, kindAt, kindInbox, kindCommand, kindSocket, kindStatus, kindTime, kindGnss, kindPower
};

const char* const kindNames[] = {"SendSms", "At", "Inbox", "SmsCommand", "Socket",
                                 "Status", "Time", "Gnss", "Power"};

// One call's record. Each kind adds what it keeps.
struct Record {
    Record* next = nullptr;
    uint8_t kind = 0;
    uint32_t hash = 0;
    char id[64] = {0};            // name and type, or the key: what the record is found by
    char label[48] = {0};         // what a failure is named by: the name, or the key
    int result = kOk;
    GsmResult why = GsmStatus::Ok;
    virtual ~Record() {}
};

// A request: the edge, and whether it is running.
struct RequestRecord : Record {
    bool lastExecute = false;
    bool asked = false;           // an edge seen, not yet started
    bool pending = false;         // started, not yet concluded
    Job* job = nullptr;
};

struct SmsRecord : RequestRecord {
    char number[21] = {0};
    char text[161] = {0};
};

struct AtRecord : RequestRecord {
    char command[128] = {0};
    uint32_t timeoutMs = 5000;
    char reply[255] = {0};
};

struct InboxRecord : Record {
    bool started = false;
    uint32_t seen = 0;
    char sender[24] = {0};
    char text[161] = {0};
    uint16_t index = 0;
    int64_t sentAtNs = 0;
    uint32_t count = 0;
};

struct CommandRecord : Record {
    uint32_t seen = 0;
    Job* job = nullptr;
    bool started = false;
    uint32_t hourAt = 0;
    uint16_t hourCount = 0;
    uint32_t activeAt = 0;
    bool replyWanted = false;
    char replyTo[24] = {0};
    char replyText[161] = {0};
    CommandView view;
    char matched[33] = {0};
    char arg[65] = {0};
    char sentBy[24] = {0};
    char lastRefused[65] = {0};
};

struct SocketRecord : Record {
    GsmSocket* socket = nullptr;
    char host[64] = {0};
    uint16_t port = 0;
    bool tls = false;
    bool lastSend = false;
    bool sendAsked = false;
    char tx[255] = {0};
    size_t txLength = 0;
    size_t txAt = 0;
    bool txPending = false;
    bool txFlushing = false;
    bool retrying = false;
    uint32_t retryAt = 0;
};

struct StatusRecord : Record {
    bool asked = false;
    uint32_t askedAt = 0;
    StatusView view;
};

struct TimeRecord : Record {
    bool asked = false;
    uint32_t askedAt = 0;
    uint32_t generation = 0;
    TimeView view;
};

struct GnssRecord : Record {
    bool powered = false;
    uint32_t generation = 0;
    uint32_t askedAt = 0;
    GnssView view;
};

struct PowerRecord : RequestRecord {
    int command = 0;
    int8_t op = 0;                // running: 0 none, 1 on, 2 off, 3 restart
    int8_t phase = 0;
    uint32_t until = 0;
};

struct Calls;
typedef void (*TickFn)(Calls&);

// The methods' state: one modem per PLC, so one of these.
struct Calls {
    Record* records = nullptr;
    uint16_t count = 0;

    bool failing = false;
    char failKey[64] = {0};
    char failText[128] = {0};    // cut to sLastError's 64 by the block
    int failResult = kOk;

    // What the block's own call saw this scan, holding the lock.
    bool open = false;
    bool registered = false;
    bool powered = true;

    // The current message: taken by the block's call, one a scan.
    Sms current;
    uint32_t seq = 0;
    bool smsAsked = false;        // an enabled Inbox or SmsCommand since the last tick
    bool smsOffAsked = false;     // one called with bEnable FALSE, and none enabled
    bool smsOn = false;
    TickFn smsTick = nullptr;     // set by the first Inbox or SmsCommand

    PowerRecord* power = nullptr;
    TickFn powerTick = nullptr;   // set by the first Power

    ~Calls() {
        while (records != nullptr) {
            Record* next = records->next;
            if (records->kind == kindSocket && hasDevice()) {
                SocketRecord* s = static_cast<SocketRecord*>(records);
                if (s->socket != nullptr) { device().close(s->socket); }
            }
            delete records;
            records = next;
        }
    }
};

// Read by the block's call every scan; made by the first method call, so a
// program that calls none links none of this.
Calls* g_calls = nullptr;

struct CallsOwned {
    ~CallsOwned() {
        delete g_calls;
        g_calls = nullptr;
    }
};

Calls* calls() {
    if (g_calls == nullptr) {
        static CallsOwned owned;   // frees it when the program is unloaded
        (void)owned;
        g_calls = new (std::nothrow) Calls();
    }
    return g_calls;
}

// A call's result, noted: a failing call is named on the block until the same
// call succeeds. Queued, not ready and not yet running are states, not failures.
int noteCall(Calls* c, const Record* r, int result, const char* method) {
    if (c == nullptr) { return result; }
    char key[64];
    if (r != nullptr && r->label[0] != '\0') {
        snprintf(key, sizeof key, "%s %s", method, r->label);
    } else {
        snprintf(key, sizeof key, "%s", method);
    }
    const bool failed = result != kOk && result != kQueued && result != kNotReady &&
                        result != kNotInitialised;
    if (failed) {
        c->failing = true;
        c->failResult = result;
        copyText(c->failKey, sizeof c->failKey, key);
        const bool words = r != nullptr && r->result == result &&
                           (r->why.space() != GsmErrorSpace::None);
        if (words) {
            snprintf(c->failText, sizeof c->failText, "%s: %s (%s)", key, resultName(result),
                     describe(r->why));
        } else {
            snprintf(c->failText, sizeof c->failText, "%s: %s", key, resultName(result));
        }
    } else if (c->failing && strcmp(c->failKey, key) == 0) {
        c->failing = false;
        c->failKey[0] = '\0';
        c->failText[0] = '\0';
    }
    return result;
}

template <typename RecordType>
RecordType* findOrMake(Calls* c, uint8_t kind, const Call& call) {
    char id[64];
    char label[48];
    const bool named = call.name != nullptr && call.name[0] != '\0';
    if (named) {
        snprintf(id, sizeof id, "%s|%s", call.name, call.type != nullptr ? call.type : "");
        copyText(label, sizeof label, call.name);
    } else {
        // A literal, found by its text; a method with one record has none.
        const char* key = call.key != nullptr ? call.key : "";
        snprintf(id, sizeof id, "'%s", key);
        if (key[0] != '\0') {
            snprintf(label, sizeof label, "'%s'", key);
        } else {
            label[0] = '\0';
        }
    }
    uint32_t hash = hashText(2166136261u ^ kind, id);
    for (Record* r = c->records; r != nullptr; r = r->next) {
        if (r->kind == kind && r->hash == hash && strcmp(r->id, id) == 0) {
            return static_cast<RecordType*>(r);
        }
    }
    if (c->count >= GSM_PLC_MAX_RECORDS) { return nullptr; }
    RecordType* made = new (std::nothrow) RecordType();
    if (made == nullptr) { return nullptr; }
    made->kind = kind;
    made->hash = hash;
    copyText(made->id, sizeof made->id, id);
    copyText(made->label, sizeof made->label, label);
    made->next = c->records;
    c->records = made;
    c->count++;
    return made;
}

// Every method's first steps: the task, the modem, the record.
template <typename RecordType>
RecordType* enter(const Call& call, uint8_t kind, Calls** cOut, int* refused) {
    *cOut = nullptr;
    if (call.task != 0 && call.task != currentTask()) {
        *refused = kWrongTask;
        return nullptr;
    }
    Calls* c = calls();
    *cOut = c;
    if (c == nullptr) {
        *refused = kNotInitialised;
        return nullptr;
    }
    if (!isOwner(call.block)) {
        *refused = kNotInitialised;
        return nullptr;
    }
    RecordType* r = findOrMake<RecordType>(c, kind, call);
    if (r == nullptr) { *refused = kQueueFull; }
    return r;
}

int done(Calls* c, Record* r, int result) {
    if (r != nullptr) { r->result = result; }
    return noteCall(c, r, result, kindNames[r != nullptr ? r->kind : 0]);
}

int refusedCall(Calls* c, uint8_t kind, const Call& call, int result) {
    // Named by what it would have been found by, as a record is.
    Record named;
    named.kind = kind;
    const bool hasName = call.name != nullptr && call.name[0] != '\0';
    if (hasName) {
        copyText(named.label, sizeof named.label, call.name);
    } else if (call.key != nullptr && call.key[0] != '\0') {
        snprintf(named.label, sizeof named.label, "'%s'", call.key);
    }
    return noteCall(c, &named, result, kindNames[kind]);
}

Job* jobOf(Job*& held) {
    if (held == nullptr) { held = newJob(); }
    return held;
}

// The job's conclusion, taken once, holding the lock.
bool concluded(RequestRecord* r) {
    if (!r->pending || r->job == nullptr || r->job->busy || !r->job->done) { return false; }
    r->job->done = false;
    r->pending = false;
    r->why = r->job->result;
    r->result = r->job->result.isOk() ? kOk : statusOf(r->job->result);
    return true;
}

} // namespace

// =============================================================================
// The block's own call
// =============================================================================

namespace {

// The current message, one a scan: Inbox and SmsCommand look at it until the
// next one replaces it. Receiving runs while one of them was enabled since the
// last scan; messages that arrive with none stay on the SIM.
void smsTickFn(Calls& c) {
    // A call skipped for a scan changes nothing: receiving stops only when one
    // says bEnable FALSE and none says TRUE.
    if (c.smsAsked) {
        c.smsOn = true;
    } else if (c.smsOffAsked) {
        c.smsOn = false;
    }
    c.smsAsked = false;
    c.smsOffAsked = false;
    smsReceive(c.smsOn);
    if (!c.smsOn) { return; }
    Sms message;
    if (!smsTake(message)) { return; }
    c.current = message;
    c.seq++;
    if (c.seq == 0) { c.seq = 1; }
}

void startPower(Calls& c, PowerRecord* r);
void powerTickFn(Calls& c);

} // namespace

void tickCalls(uint32_t block) {
    Calls* c = g_calls;
    if (c == nullptr || !isOwner(block)) { return; }
    c->open = isOpen();
    c->registered = c->open && device().isRegistered();
    c->powered = !heldOff();
    if (c->smsTick != nullptr) { c->smsTick(*c); }
    if (c->powerTick != nullptr) { c->powerTick(*c); }
}

const char* callError(int* result) {
    const Calls* c = g_calls;
    if (c == nullptr || !c->failing) { return nullptr; }
    if (result != nullptr) { *result = c->failResult; }
    return c->failText;
}

// =============================================================================
// SendSms
// =============================================================================

int sendSmsCall(const Call& call, const char* text, size_t textLength,
                const char* number, bool execute) {
    Calls* c = nullptr;
    int refused = kOk;
    SmsRecord* r = enter<SmsRecord>(call, kindSms, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindSms, call, refused); }

    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    if (rising && !r->pending && !r->asked) {
        // The inputs as they are at the edge.
        r->asked = true;
        r->why = GsmStatus::Ok;
        if (text == nullptr || textLength > 160) {
            r->asked = false;
            return done(c, r, text == nullptr ? kInvalidArgument : kTooLarge);
        }
        copyText(r->text, sizeof r->text, text, textLength);
        copyText(r->number, sizeof r->number, number);
        r->result = kQueued;
    }

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    if (concluded(r)) { return done(c, r, r->result); }
    if (r->pending) { return done(c, r, kQueued); }
    if (!r->asked) { return done(c, r, r->result); }
    r->asked = false;

    if (r->number[0] == '\0' || r->text[0] == '\0') { return done(c, r, kInvalidArgument); }
    if (!isOpen()) { return done(c, r, kNotReady); }
    Job* job = jobOf(r->job);
    if (job == nullptr) { return done(c, r, kNotInitialised); }
    const GsmResult accepted = sendSms(*job, r->number, r->text);
    if (accepted.status() == GsmStatus::Queued) {
        r->pending = true;
        return done(c, r, kQueued);
    }
    r->why = accepted;
    return done(c, r, statusOf(accepted));
}

// =============================================================================
// At
// =============================================================================

int atCall(const Call& call, const char* command, size_t commandLength,
           uint32_t timeoutMs, bool execute, const char** reply) {
    *reply = "";
    Calls* c = nullptr;
    int refused = kOk;
    AtRecord* r = enter<AtRecord>(call, kindAt, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindAt, call, refused); }
    *reply = r->reply;

    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    if (rising && !r->pending && !r->asked) {
        r->asked = true;
        r->why = GsmStatus::Ok;
        r->reply[0] = '\0';
        if (command == nullptr || commandLength > 127) {
            r->asked = false;
            return done(c, r, command == nullptr ? kInvalidArgument : kTooLarge);
        }
        copyText(r->command, sizeof r->command, command, commandLength);
        r->timeoutMs = timeoutMs == 0 ? 5000u : (timeoutMs > 180000u ? 180000u : timeoutMs);
        r->result = kQueued;
    }

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    if (concluded(r)) {
        copyText(r->reply, sizeof r->reply, r->job->reply);
        return done(c, r, r->result);
    }
    if (r->pending) { return done(c, r, kQueued); }
    if (!r->asked) { return done(c, r, r->result); }
    r->asked = false;

    if (r->command[0] == '\0') { return done(c, r, kInvalidArgument); }
    if (!isOpen() || device().driver() == nullptr) { return done(c, r, kNotReady); }
    Job* job = jobOf(r->job);
    if (job == nullptr) { return done(c, r, kNotInitialised); }
    const GsmResult accepted = sendAt(*job, r->command, r->timeoutMs);
    if (accepted.status() == GsmStatus::Queued) {
        r->pending = true;
        return done(c, r, kQueued);
    }
    r->why = accepted;
    return done(c, r, statusOf(accepted));
}

// =============================================================================
// Power
// =============================================================================

namespace {

// A new operation, holding the lock.
void startPower(Calls& c, PowerRecord* r) {
    r->asked = false;
    GsmDevice& gsm = device();
    const uint32_t now = gsm_millis();
    r->why = GsmStatus::Ok;

    if (r->command == 0) {                     // switch off
        holdOff(true);
        c.powered = false;
        if (!isOpen() || gsm.driver() == nullptr) {
            // It never answered, so there is nothing to tell it; the supply,
            // where there is one, is all there is.
            gsm.stop();
            if (hasRail()) { railOff(); }
            r->result = kOk;
            return;
        }
        gsm.stop();
        Job* job = jobOf(r->job);
        GsmCmdBuf command;
        gsm.driver()->powerDownCommand(command);
        const GsmProfile* profile = gsm.profile();
        const uint32_t settle = profile != nullptr ? profile->powerOffSettleMs : 3000u;
        if (job == nullptr || command.isEmpty() || command.overflowed() ||
            sendAt(*job, command.text(), 9000u + settle).status() != GsmStatus::Queued) {
            if (job != nullptr) {
                job->busy = false;
                job->done = false;
                job->result = GsmStatus::NotSupportedByModule;
            }
        }
        r->op = 2;
        r->result = kQueued;
        return;
    }

    if (r->command == 1) {                     // switch on
        holdOff(false);
        c.powered = true;
        r->op = 1;
        r->until = now + 90000u;
        r->result = kQueued;
        return;
    }

    // restart
    if (!isOpen() || gsm.driver() == nullptr) {
        r->result = kNotReady;
        return;
    }
    Job* job = jobOf(r->job);
    if (job == nullptr) {
        r->result = kNotInitialised;
        return;
    }
    GsmCmdBuf command;
    gsm.driver()->resetCommand(command);
    const GsmResult accepted = command.isEmpty() || command.overflowed()
        ? GsmResult(GsmStatus::NotSupportedByModule)
        : sendAt(*job, command.text(), 9000u);
    if (accepted.status() != GsmStatus::Queued) {
        r->why = accepted;
        r->result = statusOf(accepted);
        return;
    }
    r->op = 3;
    r->phase = 0;
    r->result = kQueued;
}

// Moves an operation along, every scan, holding the lock - whether or not
// Power is called again.
void powerTickFn(Calls& c) {
    PowerRecord* r = c.power;
    if (r == nullptr) { return; }
    if (r->asked && r->op == 0) { startPower(c, r); }
    const int8_t op = r->op;
    if (op == 0) { return; }
    GsmDevice& gsm = device();
    const uint32_t now = gsm_millis();
    Job* job = r->job;

    if (op == 2) {
        if (job != nullptr && job->busy) { return; }
        // Acknowledged, refused or unanswered: the module has had its command
        // and its time, so the supply may go now.
        const bool answered = job != nullptr && job->done && job->result.isOk();
        if (job != nullptr) { job->done = false; }
        if (hasRail()) { railOff(); }
        r->op = 0;
        if (answered || hasRail()) {
            r->result = kOk;
        } else {
            r->why = job != nullptr ? job->result : GsmResult(GsmStatus::NotSupportedByModule);
            r->result = statusOf(r->why);
            if (r->result == kOk) { r->result = kTimeout; }
        }
        return;
    }

    if (op == 1) {
        const GsmState state = gsm.state();
        if (!isOpen() || !wanted()) {
            r->op = 0;
            r->result = kNotReady;     // the modem block's bConnect is FALSE
        } else if (state == GsmState::Failed) {
            r->op = 0;
            r->why = gsm.lastError();
            r->result = statusOf(r->why);
        } else if ((int)state >= (int)GsmState::Identifying && state != GsmState::Recovering) {
            r->op = 0;
            r->result = kOk;
        } else if (!gsm_isFuture(now, r->until)) {
            r->op = 0;
            r->result = kTimeout;
        }
        return;
    }

    // op == 3, a restart: the command, then the module's reboot time.
    if (r->phase == 0) {
        if (job == nullptr || job->busy) { return; }
        job->done = false;
        if (!job->result.isOk()) {
            // A module that does not answer its reset is the one a restart is
            // for: start the bring-up again, which powers it up afresh.
            gsm.stop();
            if (wanted()) { gsm.start(); }
            r->op = 0;
            r->why = job->result;
            r->result = statusOf(job->result);
            return;
        }
        // Left alone while it reboots: talking to it, or pressing its key, in
        // the middle of a boot is how a module ends up off.
        gsm.stop();
        const GsmProfile* profile = gsm.profile();
        const uint32_t settle = profile != nullptr && profile->resetSettleMs > 0
            ? profile->resetSettleMs : 3000u;
        r->until = now + settle;
        r->phase = 1;
        return;
    }
    if (gsm_isFuture(now, r->until)) { return; }
    if (wanted()) { gsm.start(); }
    r->op = 0;
    r->result = kOk;
}

} // namespace

int powerCall(const Call& call, int command, bool execute, PowerView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    Call single = call;
    single.name = nullptr;
    single.key = "";              // one record: the modem has one power switch
    PowerRecord* r = enter<PowerRecord>(single, kindPower, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindPower, single, refused); }
    c->power = r;
    c->powerTick = &powerTickFn;

    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    if (rising && r->op == 0 && !r->asked) {
        if (command < 0 || command > 2) {
            out.powered = c->powered;
            return done(c, r, kInvalidArgument);
        }
        r->command = command;
        r->asked = true;
        r->result = kQueued;
        TryHold hold;
        if (hold.owned()) { startPower(*c, r); }
    }
    out.powered = c->powered;
    out.busy = r->op != 0 || r->asked;
    return done(c, r, out.busy ? kQueued : r->result);
}

// =============================================================================
// Inbox and SmsCommand
// =============================================================================

int inboxCall(const Call& call, bool enable, InboxView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    Call single = call;
    single.name = nullptr;
    single.key = "";              // the SIM has one inbox
    InboxRecord* r = enter<InboxRecord>(single, kindInbox, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindInbox, single, refused); }
    if (c->smsTick == nullptr) { c->smsTick = &smsTickFn; }
    if (!r->started) {
        r->started = true;
        r->seen = c->seq;         // what was taken before this record existed is not new
    }

    out.received = false;
    if (enable) {
        c->smsAsked = true;
        if (r->seen != c->seq) {
            r->seen = c->seq;
            const Sms& m = c->current;
            copyText(r->sender, sizeof r->sender, m.sender);
            copyText(r->text, sizeof r->text, m.text);
            r->index = m.index;
            int64_t seconds = 0;
            if (m.hasTimestamp) {
                // The centre writes its local time and its offset from GMT.
                seconds = unixSeconds(m.timestamp) - (int64_t)m.timestamp.zoneMinutes() * 60;
            }
            r->sentAtNs = seconds * 1000000000LL;
            r->count++;
            out.received = true;
        }
    } else {
        c->smsOffAsked = true;
        r->seen = c->seq;
    }
    out.sender = r->sender;
    out.text = r->text;
    out.index = r->index;
    out.sentAtNs = r->sentAtNs;
    out.count = r->count;
    if (!enable) { return done(c, r, kOk); }
    return done(c, r, c->registered ? kOk : kNotReady);
}

namespace {

// Upper case, one space between words, none at either end.
void smsNormalise(const char* in, char* out, size_t cap) {
    size_t n = 0;
    bool space = false;
    for (; *in != '\0' && n + 1 < cap; ++in) {
        char ch = *in;
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
            space = n > 0;
            continue;
        }
        if (space && n + 2 < cap) out[n++] = ' ';
        space = false;
        if (ch >= 'a' && ch <= 'z') ch = (char)(ch - 'a' + 'A');
        out[n++] = ch;
    }
    out[n] = '\0';
}

// The last 8 digits of a number ('' when it has fewer than 6): +64 21 123 4567
// and 021 123 4567 are one number.
void smsTail(const char* number, char* out) {
    char digits[32];
    size_t n = 0;
    for (; *number != '\0' && n + 1 < sizeof digits; ++number) {
        if (*number >= '0' && *number <= '9') digits[n++] = *number;
    }
    digits[n] = '\0';
    if (n < 6) {
        out[0] = '\0';
        return;
    }
    strcpy(out, n > 8 ? digits + (n - 8) : digits);
}

// Whether `sender` is on the list ('*' = anybody, empty = nobody). Entries are
// separated by commas or semicolons; spaces inside a number are part of it. A
// phone number matches on its last 8 digits; a name or short code (fewer than 6
// digits: 'PTT NZ', '2001') matches whole, upper or lower case.
bool smsAllowed(const char* list, const char* sender) {
    char want[16];
    smsTail(sender, want);
    char wantWhole[32];
    smsNormalise(sender, wantWhole, sizeof wantWhole);
    if (want[0] == '\0' && wantWhole[0] == '\0') return false;
    char entry[32];
    size_t n = 0;
    for (const char* p = list;; ++p) {
        const char ch = *p;
        if (ch == ',' || ch == ';' || ch == '\n' || ch == '\0') {
            entry[n] = '\0';
            char trimmed[32];
            smsNormalise(entry, trimmed, sizeof trimmed);
            if (strcmp(trimmed, "*") == 0) return true;
            if (n > 0) {
                char have[16];
                smsTail(entry, have);
                if (want[0] != '\0') {
                    if (have[0] != '\0' && strcmp(have, want) == 0) return true;
                } else if (have[0] == '\0' && strcmp(trimmed, wantWhole) == 0) {
                    return true;
                }
            }
            n = 0;
            if (ch == '\0') return false;
            continue;
        }
        if (n + 1 < sizeof entry) entry[n++] = ch;
    }
}

// Whether `text` starts with the PIN as its own word: the PIN's length, else 0.
size_t smsPinAt(const char* text, int32_t pin) {
    if (pin <= 0) return 0;
    char p[16];
    snprintf(p, sizeof p, "%ld", (long)pin);
    const size_t pl = strlen(p);
    return strncmp(text, p, pl) == 0 && (text[pl] == ' ' || text[pl] == '\0') ? pl : 0;
}

// The first of a comma list's commands `rest` starts with (normalised, as a
// whole word): its position in the list from 1, its words in `out`; 0 none.
int smsFind(const char* list, const char* rest, char* out, size_t cap) {
    char item[48];
    size_t n = 0;
    int index = 0;
    for (const char* q = list;; ++q) {
        if (*q == ',' || *q == ';' || *q == '\0') {
            item[n] = '\0';
            char word[40];
            smsNormalise(item, word, sizeof word);
            if (word[0] != '\0') {
                ++index;
                const size_t wl = strlen(word);
                if (strncmp(rest, word, wl) == 0 && (rest[wl] == ' ' || rest[wl] == '\0')) {
                    snprintf(out, cap, "%s", word);
                    return index;
                }
            }
            n = 0;
            if (*q == '\0') return 0;
            continue;
        }
        if (n + 1 < sizeof item) item[n++] = *q;
    }
}

// How many commands a comma list holds.
int smsCount(const char* list) {
    char none[4];
    int count = 0;
    char item[48];
    size_t n = 0;
    for (const char* q = list;; ++q) {
        if (*q == ',' || *q == ';' || *q == '\0') {
            item[n] = '\0';
            smsNormalise(item, none, sizeof none);
            if (none[0] != '\0') ++count;
            n = 0;
            if (*q == '\0') return count;
            continue;
        }
        if (n + 1 < sizeof item) item[n++] = *q;
    }
}

// The argument as a time: number-and-unit pieces (D H M S MS, upper case as the
// text is), spaces between them allowed, an optional 'T#'. A bare number is not one.
bool smsDuration(const char* s, int64_t* ns) {
    if (s[0] == 'T' && s[1] == '#') s += 2;
    double total = 0.0;
    int pieces = 0;
    while (*s != '\0') {
        if (*s == ' ' || *s == '_') { ++s; continue; }
        if (!((*s >= '0' && *s <= '9') || *s == '.')) return false;
        char* end = nullptr;
        const double v = strtod(s, &end);
        if (end == s || v < 0.0) return false;
        s = end;
        double unit;
        if (s[0] == 'M' && s[1] == 'S') { unit = 1e6; s += 2; }
        else if (*s == 'D') { unit = 86400e9; ++s; }
        else if (*s == 'H') { unit = 3600e9; ++s; }
        else if (*s == 'M') { unit = 60e9; ++s; }
        else if (*s == 'S') { unit = 1e9; ++s; }
        else return false;
        total += v * unit;
        ++pieces;
    }
    if (pieces == 0 || total > 9.2e18) return false;
    *ns = (int64_t)(total + 0.5);
    return true;
}

// Whether a sender can be texted back: a number, not a name ('PTT NZ' cannot).
bool smsCanAnswer(const char* sender) {
    bool digit = false;
    for (; *sender != '\0'; ++sender) {
        const char ch = *sender;
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')) return false;
        if (ch >= '0' && ch <= '9') digit = true;
    }
    return digit;
}

// The current message, if it is one of the record's commands. No lock: the
// message is the block's, and the reply is only asked for here.
void takeCommand(CommandRecord* r, const CommandSpec& spec, const Sms& message, uint32_t now) {
    if (spec.commands[0] == '\0' && spec.adminCommands[0] == '\0') return;

    char text[200];
    smsNormalise(message.text, text, sizeof text);

    // The PIN (admin or operator), then the command.
    const int32_t opPin = spec.pin;
    const int32_t adPin = spec.adminPin;
    const char* rest = text;
    bool pinOk = true;
    bool admin = false;
    size_t pl;
    if ((pl = smsPinAt(text, adPin)) > 0) {
        admin = true;
        rest = text + pl + (text[pl] == ' ' ? 1 : 0);
    } else if ((pl = smsPinAt(text, opPin)) > 0) {
        rest = text + pl + (text[pl] == ' ' ? 1 : 0);
    } else if (opPin > 0) {
        // A wrong or missing PIN still names the command after its first word.
        pinOk = false;
        const char* sp = strchr(text, ' ');
        rest = sp ? sp + 1 : text;
    }
    // The first of the commands, then of the admin commands, the message starts with.
    char command[40] = "";
    int which = smsFind(spec.commands, rest, command, sizeof command);
    bool adminCommand = false;
    if (which == 0 && !pinOk) {
        // No PIN at all: the whole text may be the command ('START').
        which = smsFind(spec.commands, text, command, sizeof command);
        if (which != 0) rest = text;
    }
    if (which == 0 && spec.adminCommands[0] != '\0') {
        int a = smsFind(spec.adminCommands, rest, command, sizeof command);
        if (a == 0 && !pinOk) {
            a = smsFind(spec.adminCommands, text, command, sizeof command);
            if (a != 0) rest = text;
        }
        if (a != 0) {
            which = smsCount(spec.commands) + a;
            adminCommand = true;
        }
    }
    if (which == 0) return;   // none of ours
    // An admin command needs the admin PIN (when there is one); an operator PIN is refused.
    const bool levelOk = !adminCommand || adPin <= 0 || admin;
    const size_t cl = strlen(command);
    const char* arg = rest + cl + (rest[cl] == ' ' ? 1 : 0);

    const char* sender = message.sender;
    const bool numberOk = smsAllowed(spec.allowed, sender);
    const bool rateOk = spec.maxPerHour == 0 || r->hourCount < spec.maxPerHour;

    if (!numberOk || !pinOk || !levelOk || !rateOk) {
        r->view.refused++;
        const char* why = !numberOk ? "not an allowed number" : !pinOk ? "wrong PIN"
                        : !levelOk ? "needs the admin PIN" : "too many this hour";
        snprintf(r->lastRefused, sizeof r->lastRefused, "%s: %s", why, sender);
        // Say why only to a number on the list: a stranger learns nothing.
        if (spec.reply >= 2 && numberOk && smsCanAnswer(sender)) {
            copyText(r->replyTo, sizeof r->replyTo, sender);
            snprintf(r->replyText, sizeof r->replyText, "REFUSED %s: %s", command, why);
            r->replyWanted = true;
        }
        return;
    }

    r->hourCount++;
    r->view.count++;
    copyText(r->sentBy, sizeof r->sentBy, sender);
    r->view.which = (int16_t)which;
    copyText(r->matched, sizeof r->matched, command);
    copyText(r->arg, sizeof r->arg, arg);
    char* end = nullptr;
    const double value = strtod(arg, &end);
    r->view.valueOk = *arg != '\0' && end != nullptr && *end == '\0';
    r->view.value = r->view.valueOk ? (float)value : 0.0f;
    int64_t ns = 0;
    r->view.durationOk = *arg != '\0' && smsDuration(arg, &ns);
    r->view.durationNs = r->view.durationOk ? ns : 0;
    r->view.admin = admin;
    r->view.active = true;
    r->activeAt = now;
    if (spec.reply >= 1 && smsCanAnswer(sender)) {   // a name cannot be answered
        copyText(r->replyTo, sizeof r->replyTo, sender);
        if (spec.replyText[0] != '\0') {
            snprintf(r->replyText, sizeof r->replyText, "%s", spec.replyText);
        } else if (*arg != '\0') {
            snprintf(r->replyText, sizeof r->replyText, "OK %s %s", command, arg);
        } else {
            snprintf(r->replyText, sizeof r->replyText, "OK %s", command);
        }
        r->replyWanted = true;
    }
}

} // namespace

int smsCommandCall(const Call& call, const CommandSpec& spec, CommandView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    CommandRecord* r = enter<CommandRecord>(call, kindCommand, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindCommand, call, refused); }
    if (c->smsTick == nullptr) { c->smsTick = &smsTickFn; }

    const uint32_t now = gsm_millis();
    if (!r->started) {
        r->started = true;
        r->hourAt = now;
        r->seen = c->seq;         // what was taken before this record existed is not new
    }
    if (now - r->hourAt >= 3600000u) {
        r->hourAt = now;
        r->hourCount = 0;
    }
    // Active: one call, or the pulse long.
    if (r->view.active && now - r->activeAt >= spec.pulseMs) { r->view.active = false; }

    // --- this scan's message: FIRST, every call, never waiting for the modem.
    // A message is the current one for one scan; a call that returned early
    // whenever another task held the modem missed it (0.1.4's fix). Only the
    // reply needs the modem, and it waits for it below.
    if (spec.enable) {
        c->smsAsked = true;
        if (r->seen != c->seq) {
            r->seen = c->seq;
            takeCommand(r, spec, c->current, now);
        }
    } else {
        c->smsOffAsked = true;
        r->seen = c->seq;
    }

    out = r->view;
    out.matched = r->matched;
    out.arg = r->arg;
    out.sentBy = r->sentBy;
    out.lastRefused = r->lastRefused;

    // --- the modem: a reply owed ---------------------------------------------
    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    if (!isOpen()) { return done(c, r, spec.enable ? kNotReady : kOk); }
    if (r->result == kNotReady) { r->result = kOk; }

    if (r->job != nullptr && r->job->done) {
        r->job->done = false;
        r->why = r->job->result;
        r->result = r->job->result.isOk() ? kOk : statusOf(r->job->result);
    }
    if (r->replyWanted && (r->job == nullptr || !r->job->busy)) {
        Job* job = jobOf(r->job);
        if (job == nullptr) {
            r->replyWanted = false;
            return done(c, r, kNotInitialised);
        }
        const GsmResult sent = sendSms(*job, r->replyTo, r->replyText);
        // Not taken yet (the SIM not accepted, the modem busy): asked again next call.
        if (sent.status() == GsmStatus::Queued) { r->replyWanted = false; }
    }
    return done(c, r, r->result);
}

// =============================================================================
// Socket
// =============================================================================

int socketCall(const Call& call, const SocketSpec& spec, SocketView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    SocketRecord* r = enter<SocketRecord>(call, kindSocket, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindSocket, call, refused); }

    // The edge is taken before the lock, so a call spent standing back for
    // another task cannot lose it.
    const bool rising = spec.send && !r->lastSend;
    r->lastSend = spec.send;
    if (rising) { r->sendAsked = true; }
    out.connected = r->socket != nullptr && r->socket->state() == GsmSocketState::Open;
    out.sent = false;
    out.received = false;
    out.rxLength = 0;

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }

    GsmSocket* socket = r->socket;
    auto closeIt = [&]() {
        if (socket != nullptr && hasDevice()) { device().close(socket); }
        socket = nullptr;
        r->socket = nullptr;
        r->txPending = false;
        r->txFlushing = false;
        out.connected = false;
    };

    if (!isOpen()) {
        closeIt();
        r->sendAsked = false;
        return done(c, r, spec.open ? kNotReady : kOk);
    }
    GsmDevice& gsm = device();

    if (!spec.open) {
        closeIt();
        r->retrying = false;
        if (r->sendAsked) {
            r->sendAsked = false;
            return done(c, r, kNotReady);    // bSend while bOpen is FALSE
        }
        return done(c, r, kOk);
    }

    // A different server while open: the connection moves to it.
    if (socket != nullptr &&
        (strcmp(r->host, spec.host) != 0 || r->port != spec.port || r->tls != spec.tls)) {
        closeIt();
        r->retrying = false;
    }

    const uint32_t now = gsm_millis();
    if (socket == nullptr) {
        if (r->sendAsked) {
            r->sendAsked = false;
            return done(c, r, kNotReady);    // bSend while not connected
        }
        if (!gsm.isReady()) {
            return done(c, r, r->retrying ? r->result : kNotReady);
        }
        if (r->retrying && gsm_isFuture(now, r->retryAt)) { return done(c, r, r->result); }
        r->retrying = false;
        if (spec.host == nullptr || spec.host[0] == '\0' || spec.port == 0) {
            return done(c, r, kInvalidArgument);
        }
        if (strlen(spec.host) >= sizeof r->host) { return done(c, r, kTooLarge); }
        const GsmSecurity security = spec.tls ? GsmSecurity::Module : GsmSecurity::Plain;
        socket = gsm.sockets().open(spec.host, spec.port, GsmSocketKind::Tcp, security);
        if (socket == nullptr) {
            r->retrying = true;
            r->retryAt = now + 5000u;
            r->why = GsmStatus::NoSocketAvailable;
            return done(c, r, kNoSocket);
        }
        if (!socket->begin()) {
            r->why = socket->lastError();
            socket->end();
            r->retrying = true;
            r->retryAt = now + 5000u;
            return done(c, r, statusOf(r->why));
        }
        r->socket = socket;
        copyText(r->host, sizeof r->host, spec.host);
        r->port = spec.port;
        r->tls = spec.tls;
        r->txPending = false;
        r->txFlushing = false;
    }

    // --- running -----------------------------------------------------------------
    const GsmSocketState state = socket->state();
    if (state == GsmSocketState::Failed || state == GsmSocketState::Closed) {
        r->why = socket->lastError();
        socket->end();
        r->socket = nullptr;
        out.connected = false;
        r->txPending = false;
        r->txFlushing = false;
        r->sendAsked = false;
        r->retrying = true;
        r->retryAt = now + 5000u;
        return done(c, r, r->why.isOk() ? kSocketClosed : statusOf(r->why));
    }
    if (state != GsmSocketState::Open) {
        out.connected = false;               // still opening
        if (r->sendAsked) {
            r->sendAsked = false;
            return done(c, r, kNotReady);
        }
        return done(c, r, kNotReady);
    }
    out.connected = true;
    r->why = GsmStatus::Ok;

    int result = kOk;
    if (r->sendAsked && !r->txPending && !r->txFlushing) {
        r->sendAsked = false;
        if (spec.txLength >= sizeof r->tx) {
            result = kTooLarge;
        } else {
            copyText(r->tx, sizeof r->tx, spec.tx, spec.txLength);
            r->txLength = strlen(r->tx);
            r->txAt = 0;
            r->txPending = r->txLength > 0;
        }
    }
    // Handed over as the socket's buffer takes it; the rest next call.
    if (r->txPending) {
        const size_t taken = socket->write((const uint8_t*)r->tx + r->txAt, r->txLength - r->txAt);
        r->txAt += taken;
        if (r->txAt >= r->txLength) {
            r->txPending = false;
            r->txFlushing = true;
        }
    }
    if (r->txFlushing && socket->pendingOut() == 0) {
        r->txFlushing = false;
        out.sent = true;
    }
    const size_t waiting = socket->readable();
    if (waiting > 0 && spec.rx != nullptr && spec.rxCapacity > 0) {
        const size_t want = waiting < spec.rxCapacity ? waiting : spec.rxCapacity;
        const size_t got = socket->read((uint8_t*)spec.rx, want);
        spec.rx[got] = '\0';
        out.received = got > 0;
        out.rxLength = got;
    }
    return done(c, r, result);
}

// =============================================================================
// Status, Time, Gnss
// =============================================================================

int statusCall(const Call& call, uint32_t refreshMs, const StatusView** out) {
    static const StatusView none;
    *out = &none;
    Calls* c = nullptr;
    int refused = kOk;
    Call single = call;
    single.name = nullptr;
    single.key = "";
    StatusRecord* r = enter<StatusRecord>(single, kindStatus, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindStatus, single, refused); }
    *out = &r->view;

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    if (!isOpen()) { return done(c, r, kNotReady); }
    GsmDevice& gsm = device();

    const uint32_t now = gsm_millis();
    if (refreshMs > 0 && gsm.isRegistered() &&
        (!r->asked || (uint32_t)(now - r->askedAt) >= refreshMs)) {
        gsm.refreshStatus();
        r->askedAt = now;
        r->asked = true;
    }

    StatusView& v = r->view;
    // -32768 is "never read", and it fits an INT exactly.
    v.rssi = (int16_t)gsm.rssiDbm();
    v.rsrp = (int16_t)gsm.rsrpDbm();
    v.rsrq = (int16_t)gsm.rsrqDb();
    v.quality = (int)gsm.signalQuality();
    v.registration = (int)gsm.registration();
    v.technology = (int)gsm.technology();
    copyText(v.operatorName, sizeof v.operatorName, gsm.operatorName());
    copyText(v.ipAddress, sizeof v.ipAddress, gsm.ipAddress());
    copyText(v.imei, sizeof v.imei, gsm.imei());
    copyText(v.iccid, sizeof v.iccid, gsm.iccid());
    copyText(v.module, sizeof v.module, gsm.module());
    copyText(v.firmware, sizeof v.firmware, gsm.firmware());
    v.socketsFree = (uint8_t)gsm.socketsAvailable();
    const GsmModem::Counters& counters = gsm.counters();
    v.bringUps = counters.bringUps;
    v.recoveries = counters.recoveries;
    v.bearerLosses = counters.bearerLosses;
    v.registrationLosses = counters.registrationLosses;
    return done(c, r, gsm.driver() != nullptr ? kOk : kNotReady);
}

int timeCall(const Call& call, uint32_t refreshMs, TimeView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    Call single = call;
    single.name = nullptr;
    single.key = "";
    TimeRecord* r = enter<TimeRecord>(single, kindTime, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindTime, single, refused); }
    out = r->view;

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    if (!isOpen()) {
        r->view.valid = false;
        out = r->view;
        return done(c, r, kNotReady);
    }
    GsmDevice& gsm = device();
    const uint32_t now = gsm_millis();
    int result = r->result == kNotSupported ? kNotSupported : kNotReady;

    // Asked once the network has had its chance to set the clock, again on
    // every tRefresh, and again after anything that restarted the module.
    if (gsm.isRegistered()) {
        const bool due = !r->asked || r->generation != generation() ||
                         (refreshMs > 0 && (uint32_t)(now - r->askedAt) >= refreshMs);
        if (due) {
            const GsmResult asked = gsm.refreshTime();
            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                r->asked = true;
                r->askedAt = now;
                r->generation = generation();
                result = kNotReady;
            } else if (asked.status() == GsmStatus::NotSupportedByModule) {
                result = kNotSupported;
            }
        }
    }

    TimeView& v = r->view;
    v.valid = false;
    if (gsm.hasNetworkTime()) {
        // A module whose clock nobody set reports its factory date - 1980,
        // 2000, 2070 depending on the family. Not a time, so not valid.
        const GsmParse::GsmDateTime& read = gsm.networkTime();
        if (read.year >= 2024 && read.year <= 2099 && read.month >= 1 && read.month <= 12 &&
            read.day >= 1 && read.day <= 31) {
            const uint32_t ageMs = gsm.networkTimeAgeMillis();
            const int64_t zoneMinutes = (int64_t)read.zoneMinutes();
            const int64_t localNs = unixSeconds(read) * 1000000000LL + nanosOf(ageMs);
            v.localNs = localNs;
            v.utcNs = localNs - zoneMinutes * 60LL * 1000000000LL;
            v.zoneMinutes = (int16_t)zoneMinutes;
            v.ageNs = nanosOf(ageMs);
            v.valid = true;
            result = kOk;
        }
    }
    out = v;
    return done(c, r, result);
}

int gnssCall(const Call& call, bool enable, uint32_t refreshMs, GnssView& out) {
    Calls* c = nullptr;
    int refused = kOk;
    Call single = call;
    single.name = nullptr;
    single.key = "";
    GnssRecord* r = enter<GnssRecord>(single, kindGnss, &c, &refused);
    if (r == nullptr) { return refusedCall(c, kindGnss, single, refused); }
    out = r->view;

    TryHold hold;
    if (!hold.owned()) { return done(c, r, r->result); }
    GnssView& v = r->view;
    if (!isOpen()) {
        v.fix = false;
        out = v;
        return done(c, r, enable ? kNotReady : kOk);
    }
    GsmDevice& gsm = device();
    const uint32_t now = gsm_millis();
    // Not until the module has said what it is: whether it has a receiver is
    // learned from its answers, not assumed.
    if (gsm.driver() == nullptr) {
        v.fix = false;
        out = v;
        return done(c, r, enable ? kNotReady : kOk);
    }

    int result = kOk;
    if (enable) {
        // Powered again after anything that may have restarted the module.
        if (!r->powered || r->generation != generation()) {
            const GsmResult asked = gsm.gnss(true);
            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                r->powered = true;
                r->generation = generation();
                r->askedAt = now;
            } else if (asked.status() == GsmStatus::NotSupportedByModule) {
                v.supported = false;
                v.fix = false;
                out = v;
                return done(c, r, kNotSupported);
            }
        }
        if (gsm.gnssLayer().isPowered() &&
            (uint32_t)(now - r->askedAt) >= (refreshMs > 0 ? refreshMs : 1000u)) {
            gsm.refreshFix();
            r->askedAt = now;
        }
    } else if (r->powered) {
        gsm.gnss(false);
        r->powered = false;
    }

    v.supported = gsm.hasGnssReceiver();
    if (enable && !v.supported && r->powered && !gsm.gnssLayer().isPowered()) {
        result = kNotSupported;    // the module answered the power request with a refusal
    }
    const GsmFix& fix = gsm.fix();
    v.fix = gsm.hasFix();
    if (fix.hasPosition) {
        v.latitude = fix.latitude;
        v.longitude = fix.longitude;
        v.satellites = fix.satellitesInView;
    }
    if (fix.hasAltitude) { v.altitude = (float)fix.altitudeMetres; }
    const uint32_t age = gsm.fixAgeMillis();
    v.ageNs = age == 0xFFFFFFFFu ? 0 : nanosOf(age);
    out = v;
    return done(c, r, result);
}

} // namespace gsmplc
