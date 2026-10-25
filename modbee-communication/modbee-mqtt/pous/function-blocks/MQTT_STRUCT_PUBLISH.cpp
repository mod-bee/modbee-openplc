(* A whole STRUCT, one block. MODE says what makes it go.

CLIENT     which client. Must be wired.
BASE       the topic every member hangs off. A member called LEVEL under a
           BASE of 'plant/intake' is published as 'plant/intake/LEVEL'.
DATA       the STRUCT itself. Every member becomes its own topic.
MODE       what triggers a message:
             MQTT_ON_CHANGE    each member when that member changes, and
                               anyway every PERIOD so silence stays
                               meaningful.
             MQTT_ON_INTERVAL  all of them together, every PERIOD.
             MQTT_ON_REQUEST   all of them together when REQ goes TRUE, and
                               never otherwise.
PERIOD     MQTT_ON_CHANGE: send a member anyway after this long, unchanged.
           T#0s never does. MQTT_ON_INTERVAL: how often. Required there.
REQ        MQTT_ON_REQUEST: a rising edge sends the set. Ignored otherwise.
           (MQTT_CHANGED_EVERY is SPARKPLUG_STRUCT's: refused here.)
QOS        0, 1 or 2 for all of them.
RETAINED   TRUE keeps each on the broker.
ENABLE     FALSE stops publishing without losing the bindings.

POINTS     how many members are being published.
SKIPPED    how many were not - a type the wire cannot carry. Named on STATUS
           the first time, and counted here.
SENT       running total of messages sent across all members.
CHANGED    how many went out on this scan.
ERROR      something failed.
STATUS     why. MQTT_OK when fine.

---

FIFTY SETPOINTS, ONE BLOCK. That is the whole point, and the alternative is
fifty MQTT_REPORT instances or - in ladder, which has no FOR loop - fifty
rungs.

  TYPE S_INTAKE : STRUCT
    LEVEL    : REAL;
    FLOW     : REAL;
    RUNNING  : BOOL;
    PUMP_ID  : STRING(16);
  END_STRUCT END_TYPE

  pubAll( CLIENT := mqtt, BASE := 'plant/intake', DATA := stIntake,
          MODE := MQTT_ON_CHANGE, PERIOD := T#60s, RETAINED := TRUE );

publishes plant/intake/LEVEL, plant/intake/FLOW, plant/intake/RUNNING and
plant/intake/PUMP_ID, each only when it moves, and each at least once a
minute whether it moved or not.

THE MEMBER NAME IS THE TOPIC, so the STRUCT declaration IS the topic scheme.
Rename a member and you rename a topic - which is a real consequence and worth
knowing before the third device is commissioned.

THERE IS NO DEADBAND HERE, deliberately. One number covering fifty members of
mixed types is a trap: a BOOL counts as 1.0, so a deadband above that would
freeze every bit in the struct - including a FAULT - until the heartbeat
rescued it, and a counter moving by one would go the same way. Where a member
needs a deadband it gets an MQTT_REPORT of its own, which is one point, one
unit and one declared type, all visible on the rung. The two blocks coexist
happily on one client.

MQTT_ON_CHANGE COMPARES EACH MEMBER AGAINST WHAT WAS LAST PUBLISHED, not
against the last scan, so a slow drift accumulates and eventually goes rather
than creeping past unnoticed.

MQTT_ON_INTERVAL WITH NO PERIOD IS REFUSED, not turned into "every scan".
STATUS says MQTT_INVALID_ARGUMENT and nothing is published: fifty topics at
the task rate is how a broker falls over.

MQTT_ON_REQUEST SENDS THE WHOLE SET, changed or not. That is what a recipe
download wants - the receiving end gets a complete set it can act on, rather
than the three values that happened to differ.

A MEMBER THE WIRE CANNOT CARRY IS REFUSED, NOT SKIPPED QUIETLY. An array, a
nested STRUCT, a TIME: the first one found is named on STATUS as
MQTT_INVALID_ARGUMENT and counted on SKIPPED. A member silently missing from a
payload is the kind of fault that survives commissioning and turns up months
later in an argument about whose data is wrong.

ANY NUMBER OF MEMBERS. What the block remembers per member (24 bytes) is
allocated once, when the STRUCT is first bound, sized to that STRUCT; only
memory limits it. If there is none, ERROR with MQTT_QUEUE_FULL and nothing
is published until there is. *)

FUNCTION_BLOCK MQTT_STRUCT_PUBLISH
  VAR_INPUT
    BASE : STRING(128);
    DATA : ANY;
    MODE : MQTT_TRIGGER;
    PERIOD : TIME;
    REQ : BOOL;
    QOS : BYTE;
    RETAINED : BOOL;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    POINTS : INT;
    SKIPPED : INT;
    SENT : DINT;
    CHANGED : INT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbBound : BOOL;
    fbBase : STRING(128);
    fbType : STRING(64);
    fbHasLast : ARRAY [0..31] OF BOOL;
    fbLast : ARRAY [0..31] OF LREAL;
    fbHash : ARRAY [0..31] OF DWORD;
    fbSentAt : ARRAY [0..31] OF DINT;
    fbLastReq : BOOL;
    fbEverSent : BOOL;
    fbSetSentAt : DINT;
    fbMembers : __XWORD;
    fbMemberCount : UINT;
  END_VAR
#include <ModBeeMqtt.h>
#include <vector>

MqttClient* mq_clientOf(strucpp::XWORD_t handle);
bool mq_tolerated(MqttResult result);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
int32_t mq_secondsOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME mq_timeOf(int32_t milliseconds);
size_t mq_formatAny(const strucpp::IEC_ANY& any, char* out, size_t capacity);
bool mq_numberOf(const strucpp::IEC_ANY& any, double* out);
bool mq_memberAsAny(const strucpp::MemberDesc& member, uint8_t* base,
                    strucpp::IEC_ANY* out);
bool mq_memberIsPublishable(const strucpp::MemberDesc& member);
uint32_t mq_fingerprint(const char* text, size_t length);
bool mq_memberTopic(const char* base, const char* name, char* out, size_t cap);

// What the block remembers per member, one table per instance, sized to the
// STRUCT when it is bound - so a STRUCT has as many members as memory allows,
// not a fixed 32. Freed when the program is unloaded.
namespace {
struct MqStructPubMember {
    bool hasLast = false;
    double last = 0.0;
    uint32_t hash = 0;
    int32_t sentAt = 0;
};
struct MqStructPubTables {
    std::vector<MqStructPubMember*> all;
    ~MqStructPubTables() {
        for (size_t i = 0; i < all.size(); i++) delete[] all[i];
    }
};
static MqStructPubTables mqStructPubTables;
}  // namespace

// A fresh table of `count` members in place of `old`, which is freed. Null
// when the memory is not there.
static MqStructPubMember* mq_structPubTable(MqStructPubMember* old, size_t count) {
    for (size_t i = 0; i < mqStructPubTables.all.size(); i++) {
        if (mqStructPubTables.all[i] != old) continue;
        delete[] old;
        mqStructPubTables.all.erase(mqStructPubTables.all.begin() + i);
        break;
    }
    MqStructPubMember* table = new (std::nothrow) MqStructPubMember[count ? count : 1];
    if (table) mqStructPubTables.all.push_back(table);
    return table;
}

void setup()
{
    POINTS = 0;
    SKIPPED = 0;
    SENT = 0;
    CHANGED = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbBound = false;
    fbBase = "";
    fbType = "";
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    CHANGED = 0;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    // A STRUCT arrives as TYPE_USERDEF with its layout beside it. Anything
    // else on this pin is a program that wired the wrong variable, and saying
    // so is more use than publishing something shaped like a guess.
    const strucpp::TypeDesc* layout = DATA.TYPEDESC;
    if (DATA.TYPECLASS != strucpp::TYPE_USERDEF || !layout || !DATA.PVALUE) {
        POINTS = 0;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // A different struct, or a different base, is a different set of topics -
    // so nothing about the last one carries over. Without this the first scan
    // after a change would compare a new member against an old member's value
    // and stay silent about a difference that matters.
    if (!(bool)fbBound ||
        strcmp(fbBase.c_str(), BASE.c_str()) != 0 ||
        strcmp(fbType.c_str(), layout->NAME) != 0 ||
        (strucpp::XWORD_t)fbMembers == 0) {
        MqStructPubMember* fresh = mq_structPubTable(
            (MqStructPubMember*)(uintptr_t)(strucpp::XWORD_t)fbMembers,
            layout->MEMBERCOUNT);
        fbMembers = (strucpp::XWORD_t)(uintptr_t)fresh;
        fbMemberCount = fresh ? (uint16_t)layout->MEMBERCOUNT : (uint16_t)0;
        if (!fresh) {
            // Out of memory: said, and tried again next scan.
            fbBound = false;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            return;
        }
        fbBase = BASE;
        fbType = layout->NAME;
        fbBound = true;
    }

    // The edge is taken every scan, ENABLE or not: a REQ raised while the
    // block was disabled must not fire the moment it is enabled again.
    const bool asked = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;

    if (!(bool)ENABLE) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    const int32_t intervalMs = mq_millisOf(PERIOD);
    const MQTT_TRIGGER mode = MODE;

    // An interval of nothing is a misconfiguration, not "as fast as the task
    // runs". Refused rather than obeyed: fifty topics at the task rate is how
    // a broker falls over.
    // MQTT_CHANGED_EVERY is SPARKPLUG_STRUCT's: refused, never taken for
    // MQTT_ON_CHANGE.
    if ((mode == MQTT_TRIGGER::MQTT_ON_INTERVAL && intervalMs <= 0) ||
        mode == MQTT_TRIGGER::MQTT_CHANGED_EVERY) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    uint8_t* base = DATA.PVALUE;
    const mq_time_t now = mq_millis();

    // Whether the WHOLE SET goes this scan. Both of these send every member
    // together, which is what makes a recipe usable at the other end: the
    // receiver gets a complete set rather than the three that happened to
    // differ.
    const bool sendAll =
        mode == MQTT_TRIGGER::MQTT_ON_REQUEST
            ? asked
            : (mode == MQTT_TRIGGER::MQTT_ON_INTERVAL &&
               (!(bool)fbEverSent ||
                (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetSentAt,
                                    now) >= intervalMs));

    int published = 0, refused = 0;
    MqttResult worst = MqttResult::Ok;

    MqStructPubMember* table =
        (MqStructPubMember*)(uintptr_t)(strucpp::XWORD_t)fbMembers;
    const uint16_t count = layout->MEMBERCOUNT < (uint16_t)fbMemberCount
        ? layout->MEMBERCOUNT : (uint16_t)fbMemberCount;

    for (uint16_t i = 0; i < count; i++) {
        const strucpp::MemberDesc& member = layout->MEMBERS[i];

        if (!mq_memberIsPublishable(member)) {
            refused++;
            if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
            continue;
        }

        strucpp::IEC_ANY any;
        if (!mq_memberAsAny(member, base, &any)) { refused++; continue; }

        char payload[512];
        const size_t length = mq_formatAny(any, payload, sizeof payload);
        if (length == 0) {
            refused++;
            if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
            continue;
        }

        published++;

        double number = 0.0;
        const bool numeric = mq_numberOf(any, &number);
        const uint32_t hash = mq_fingerprint(payload, length);

        bool due;
        if (mode == MQTT_TRIGGER::MQTT_ON_CHANGE) {
            due = !table[i].hasLast;
            if (!due) {
                if (numeric) {
                    // Against what was last PUBLISHED, not the last scan, so a
                    // slow drift accumulates rather than creeping past.
                    due = number != table[i].last;
                } else {
                    // Compared by fingerprint rather than by keeping the
                    // characters: thirty-two STRING(254) members would be
                    // eight kilobytes of shadow on every instance.
                    due = hash != table[i].hash;
                }
            }
            // The heartbeat, per member. Without it a value that never moves
            // is indistinguishable from a device that has died.
            if (!due && intervalMs > 0 && table[i].hasLast) {
                due = (int32_t)mq_elapsed(
                          (mq_time_t)(uint32_t)table[i].sentAt, now)
                      >= intervalMs;
            }
        } else {
            due = sendAll;
        }

        if (!due) continue;

        char topic[256];
        if (!mq_memberTopic(BASE.c_str(), member.NAME, topic, sizeof topic)) {
            refused++;
            if (worst == MqttResult::Ok) worst = MqttResult::InvalidTopic;
            continue;
        }

        const MqttResult asked = client->publish(
            topic, (const uint8_t*)payload, length, (uint8_t)QOS,
            (bool)RETAINED);

        if (!mq_tolerated(asked)) {
            if (worst == MqttResult::Ok) worst = asked;
            continue;
        }

        table[i].hasLast = true;
        table[i].last = number;
        table[i].hash = hash;
        table[i].sentAt = (int32_t)(uint32_t)now;
        fbEverSent = true;
        SENT = (int32_t)SENT + 1;
        CHANGED = (int16_t)CHANGED + 1;
    }

    if (sendAll) fbSetSentAt = (int32_t)(uint32_t)now;

    POINTS = (int16_t)published;
    SKIPPED = (int16_t)refused;

    if (worst != MqttResult::Ok) {
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)worst;
    } else {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
    }
}

END_FUNCTION_BLOCK