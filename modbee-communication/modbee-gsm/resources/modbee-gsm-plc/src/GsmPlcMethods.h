// ModBee GSM for OpenPLC - the modem block's methods.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see the modbee-gsm LICENSE. Commercial use requires a
// separate licence.

#pragma once

// =============================================================================
// ONE PLACE FOR WHAT BOTH MODEM BLOCKS DO
// =============================================================================
//
// FB_GsmModemA7670 and FB_GsmModemSim7070 differ only in the driver they make
// the device with. Everything their methods do is here, in plain C++, and each
// block's method body only moves its parameters in and its outputs out. Every
// C++ POU shares one translation unit, so two copies of these definitions in
// the blocks would not even compile.
//
// A function here is linked only when a method that calls it is: a method a
// program does not call is dropped from the build, and with it its code here.
//
// --- RECORDS ---
//
// Each call is found again by what it is about: an ANY's declared name and
// type, or for a literal (which has no name) the text in Call::key. The record
// keeps the request's edge, its inputs as they were at the edge, its job and
// its outputs, so they are frozen between calls. Up to GSM_PLC_MAX_RECORDS
// (64); past that a method returns QueueFull.
//
// --- TASKS ---
//
// A method runs in the task the block's own call runs in, and returns
// kWrongTask in any other: the records are not locked, the modem is.
//
// --- ONE-SCAN EVENTS ---
//
// An arriving SMS is taken by the block's own call, one a scan, and kept as
// the current message under a sequence number. Inbox and SmsCommand look at it
// without the lock, so a command is never lost to a scan in which another
// task held the modem; only the reply waits for the lock.
//
// Same naming rule as ModBeeGsmPlc.h: no all-capitals identifier, no lower-case
// type prefix before a capital.

#include "ModBeeGsmPlc.h"

namespace gsmplc {

// E_GsmResult is GsmStatus's values in order, then these of the PLC's own.
const int kWrongTask = (int)GsmStatus::RegistrationDenied + 1;
const int kRateLimited = kWrongTask + 1;

// The task calling, as the block keeps it in its nTask.
uintptr_t currentTask();

// What every method call says about itself.
struct Call {
    uint32_t block = 0;          // the modem block's number (its nId)
    uintptr_t task = 0;          // the task its own call runs in; 0 before the first
    const char* name = nullptr;  // the record's declared name (an ANY's NAME); empty for a literal
    const char* type = nullptr;  // its declared type
    const char* key = nullptr;   // what finds it when it has no name
};

// --- The block's own call ------------------------------------------------------

// stSmsConfig: the outbox SendSms queues into.
struct SmsConfig {
    int32_t queueDepth = 8;       // number x text entries, 1 to 64
    int32_t maxPerHour = 10;      // messages queued an hour, every number counted; 0 no limit
    int32_t retries = 1;          // a failed send is tried again this many times, then dropped
    uint32_t retryMs = 60000;
};

// Every scan, holding the lock, after service(): takes this scan's SMS for
// Inbox and SmsCommand, sends the outbox's next message, and moves a Power
// operation along.
void tickCalls(uint32_t block, const SmsConfig& sms);

// The outbox's counters, for the block's outputs; null before the first SendSms.
struct OutboxView {
    uint32_t sent = 0;            // messages the network took
    uint32_t failed = 0;          // sends that failed (each try)
    uint32_t dropped = 0;         // queue full, the hour's limit, or retries spent
    int16_t queued = 0;           // messages waiting, the one being sent included
    const char* lastError = "";   // 'send +6421000001: <why>'
};
const OutboxView* outboxView();

// The last method call that failed, in words ("SendSms sAlarm: NotReady"),
// with its result; null when none is failing.
const char* callError(int* result);

// --- The outbox: every call queues -------------------------------------------

// One message to each number of `to` (',' or ';' between them, spaces
// ignored), all queued or none. Ok, InvalidArgument (`why` says what),
// QueueFull, kRateLimited. Needs no lock: the block's own call sends them.
int queueSmsCall(const Call& call, const char* to, size_t toLength,
                 const char* text, size_t textLength);

// --- Request methods: a rising edge starts one --------------------------------

int sendSmsCall(const Call& call, const char* text, size_t textLength,
                const char* number, bool execute);

// `reply` is the module's lines before its OK or ERROR, held until the next
// edge.
int atCall(const Call& call, const char* command, size_t commandLength,
           uint32_t timeoutMs, bool execute, const char** reply);

struct PowerView {
    bool powered = true;    // FALSE from SwitchOff until SwitchOn
    bool busy = false;      // an operation is under way
};
// command: 0 switch off, 1 switch on, 2 restart (E_GsmPower).
int powerCall(const Call& call, int command, bool execute, PowerView& out);

// --- Standing methods: called every scan while wanted ---------------------------

struct InboxView {
    bool received = false;   // this call took a message
    const char* sender = "";
    const char* text = "";
    uint16_t index = 0;
    int64_t sentAtNs = 0;    // UTC, nanoseconds since 1970; 0 when the network gave none
    uint32_t count = 0;      // messages taken by this record
};
int inboxCall(const Call& call, bool enable, InboxView& out);

struct CommandSpec {
    const char* commands = "";
    const char* allowed = "";
    int32_t pin = 0;
    const char* adminCommands = "";
    int32_t adminPin = 0;
    uint32_t pulseMs = 0;
    uint8_t reply = 1;
    const char* replyText = "";
    uint16_t maxPerHour = 10;
    bool enable = true;
};
struct CommandView {
    bool active = false;     // TRUE for the pulse after an accepted command
    int16_t which = 0;
    const char* matched = "";
    const char* arg = "";
    float value = 0.0f;
    bool valueOk = false;
    int64_t durationNs = 0;
    bool durationOk = false;
    bool admin = false;
    const char* sentBy = "";
    uint32_t count = 0;
    uint32_t refused = 0;
    const char* lastRefused = "";
};
int smsCommandCall(const Call& call, const CommandSpec& spec, CommandView& out);

struct SocketSpec {
    const char* host = "";
    uint16_t port = 0;
    bool tls = false;
    bool open = false;
    const char* tx = "";      // sent on a rising edge of send
    size_t txLength = 0;
    bool send = false;
    char* rx = nullptr;       // what arrived is written here, NUL-terminated
    size_t rxCapacity = 0;    // characters it holds, the NUL not counted
};
struct SocketView {
    bool connected = false;
    bool sent = false;        // this call: all of the text left for the server
    bool received = false;    // this call: rx holds bytes that just arrived
    size_t rxLength = 0;
};
int socketCall(const Call& call, const SocketSpec& spec, SocketView& out);

struct StatusView {
    int16_t rssi = -32768, rsrp = -32768, rsrq = -32768;
    int quality = 0, registration = 0, technology = 0;
    char operatorName[33] = {0};
    char ipAddress[47] = {0};
    char imei[21] = {0};
    char iccid[25] = {0};
    char module[17] = {0};
    char firmware[49] = {0};
    uint8_t socketsFree = 0;
    uint32_t bringUps = 0, recoveries = 0, bearerLosses = 0, registrationLosses = 0;
};
int statusCall(const Call& call, uint32_t refreshMs, const StatusView** out);

struct TimeView {
    bool valid = false;
    int64_t utcNs = 0, localNs = 0;
    int16_t zoneMinutes = 0;
    int64_t ageNs = 0;
};
int timeCall(const Call& call, uint32_t refreshMs, TimeView& out);

struct GnssView {
    bool supported = false, fix = false;
    double latitude = 0.0, longitude = 0.0;
    float altitude = 0.0f;
    uint8_t satellites = 0;
    int64_t ageNs = 0;
};
int gnssCall(const Call& call, bool enable, uint32_t refreshMs, GnssView& out);

} // namespace gsmplc
