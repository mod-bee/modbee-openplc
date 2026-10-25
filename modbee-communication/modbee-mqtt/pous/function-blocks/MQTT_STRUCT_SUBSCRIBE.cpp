(* A whole STRUCT, one block. Keeps every member up to date from the broker.

CLIENT           which client. Must be wired.
BASE             the topic every member hangs off. A member called SETPOINT
                 under a BASE of 'plant/intake/cmd' is subscribed as
                 'plant/intake/cmd/SETPOINT'.
DATA             the STRUCT to keep up to date. Arriving text is read as each
                 member's declared type and lands in it directly.
EXPECT           how often a value is expected. Drives QUALITY. T#0s means
                 nothing was promised. Set it to a little more than the
                 publisher's own PERIOD.
QOS              the most the broker may use to deliver.
ENABLE           FALSE unsubscribes without losing the bindings.

POINTS           how many members are subscribed.
SKIPPED          how many were not - a type the wire cannot carry.
SUBSCRIBED       every one of them is established at the broker.
QUALITY          the WORST quality across all members. One stale value makes
                 the set no better than that value.
SEEN             EVERY member has arrived at least once. It is what tells
                 an OLDEST of T#0s apart, and it is how a LADDER asks what
                 QUALITY answers - a rung cannot compare an enumeration.
OLDEST           the age of the least recently updated member. T#0s while any
                 member has never arrived - QUALITY is UNKNOWN there, which is
                 what says which of the two zeroes this is.
RECEIVED         running total of messages accepted across all members.
MALFORMED        running total that would not parse into their type.
NEW_VALUES       how many members changed on this scan.
ERROR            something failed.
STATUS           why. MQTT_OK when fine.

---

FIFTY SETPOINTS, ONE BLOCK, and the same argument as MQTT_STRUCT_PUBLISH: in
ladder there is no FOR loop, so the alternative is fifty rungs.

  subAll( CLIENT := mqtt, BASE := 'plant/intake/cmd', DATA := stSetpoints,
          EXPECT := T#0s, QOS := 2 );

QUALITY IS THE WORST ACROSS THE SET, deliberately. A recipe of twelve
setpoints where one is stale is not eleven-twelfths usable - it is a recipe
you should not run. Where a member needs to be judged on its own, give it an
MQTT_SUBSCRIBE of its own; the two blocks coexist happily on one client.

OLDEST READS T#0s WHILE ANY MEMBER HAS NEVER ARRIVED, for the same reason:
"partly commissioned" is not a state worth reporting as an age. QUALITY is
UNKNOWN throughout that, so the two zeroes are never confused.

A PAYLOAD THAT WILL NOT PARSE LEAVES ITS MEMBER ALONE and counts on
MALFORMED. A publisher sending '23,5' to a REAL is a real fault, and a block
that quietly wrote zero would hide it for a year.

EACH MEMBER COSTS A TOPIC HANDLE AND A SUBSCRIPTION on the client. Both
tables grow with the program, on a board and the Runtime alike, so the only
limit is memory. Past it, the block says so with MQTT_QUEUE_FULL - and
MQTT_CLIENT's LAST_ERROR says "out of memory" - rather than silently
subscribing to some members.

ANY NUMBER OF MEMBERS. What the block remembers per member (8 bytes) is
allocated once, when the STRUCT is first bound, sized to that STRUCT. If there
is no memory for it, ERROR with MQTT_QUEUE_FULL, tried again next scan. *)

FUNCTION_BLOCK MQTT_STRUCT_SUBSCRIBE
  VAR_INPUT
    BASE : STRING(128);
    DATA : ANY;
    EXPECT : TIME;
    QOS : BYTE;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    POINTS : INT;
    SKIPPED : INT;
    SUBSCRIBED : BOOL;
    QUALITY : MQTT_QUALITY;
    SEEN : BOOL;
    OLDEST : TIME;
    RECEIVED : DINT;
    MALFORMED : DINT;
    NEW_VALUES : INT;
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
    fbAsked : BOOL;
    fbSeenConnects : DINT;
    fbHandle : ARRAY [0..31] OF INT;
    fbEver : ARRAY [0..31] OF BOOL;
    fbArrivedAt : ARRAY [0..31] OF DINT;
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
bool mq_parseAny(const char* text, size_t length, const strucpp::IEC_ANY& any);
MQTT_QUALITY mq_qualityOf(bool everArrived, bool linkUp, int32_t ageMs,
                          int32_t maxIntervalMs);
bool mq_memberAsAny(const strucpp::MemberDesc& member, uint8_t* base,
                    strucpp::IEC_ANY* out);
bool mq_memberIsPublishable(const strucpp::MemberDesc& member);
bool mq_memberTopic(const char* base, const char* name, char* out, size_t cap);

// What the block remembers per member, one table per instance, sized to the
// STRUCT when it is bound - so a STRUCT has as many members as memory allows,
// not a fixed 32. Freed when the program is unloaded.
namespace {
struct MqStructSubMember {
    int16_t handle = -1;
    bool ever = false;
    int32_t arrivedAt = 0;
};
struct MqStructSubTables {
    std::vector<MqStructSubMember*> all;
    ~MqStructSubTables() {
        for (size_t i = 0; i < all.size(); i++) delete[] all[i];
    }
};
static MqStructSubTables mqStructSubTables;
}  // namespace

// A fresh table of `count` members in place of `old`, which is freed. Null
// when the memory is not there.
static MqStructSubMember* mq_structSubTable(MqStructSubMember* old, size_t count) {
    for (size_t i = 0; i < mqStructSubTables.all.size(); i++) {
        if (mqStructSubTables.all[i] != old) continue;
        delete[] old;
        mqStructSubTables.all.erase(mqStructSubTables.all.begin() + i);
        break;
    }
    MqStructSubMember* table = new (std::nothrow) MqStructSubMember[count ? count : 1];
    if (table) mqStructSubTables.all.push_back(table);
    return table;
}

void setup()
{
    POINTS = 0;
    SKIPPED = 0;
    SUBSCRIBED = false;
    QUALITY = MQTT_QUALITY::MQTT_QUALITY_UNKNOWN;
    OLDEST = mq_timeOf(0);
    SEEN = false;
    RECEIVED = 0;
    MALFORMED = 0;
    NEW_VALUES = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbBound = false;
    fbBase = "";
    fbType = "";
    fbAsked = false;
    fbSeenConnects = 0;
    // The member table is rebuilt when the block binds again (fbBound).
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    NEW_VALUES = 0;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client || !(bool)CLIENT.LINK_UP) {
        SUBSCRIBED = false;
        QUALITY = MQTT_QUALITY::MQTT_QUALITY_BAD;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    const strucpp::TypeDesc* layout = DATA.TYPEDESC;
    if (DATA.TYPECLASS != strucpp::TYPE_USERDEF || !layout || !DATA.PVALUE) {
        POINTS = 0;
        SUBSCRIBED = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // A different struct or a different base is a different set of topics.
    if (!(bool)fbBound ||
        strcmp(fbBase.c_str(), BASE.c_str()) != 0 ||
        strcmp(fbType.c_str(), layout->NAME) != 0 ||
        (strucpp::XWORD_t)fbMembers == 0) {
        MqStructSubMember* fresh = mq_structSubTable(
            (MqStructSubMember*)(uintptr_t)(strucpp::XWORD_t)fbMembers,
            layout->MEMBERCOUNT);
        fbMembers = (strucpp::XWORD_t)(uintptr_t)fresh;
        fbMemberCount = fresh ? (uint16_t)layout->MEMBERCOUNT : (uint16_t)0;
        if (!fresh) {
            // Out of memory: said, and tried again next scan.
            fbBound = false;
            SUBSCRIBED = false;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            return;
        }
        OLDEST = mq_timeOf(0);
        SEEN = false;
        QUALITY = MQTT_QUALITY::MQTT_QUALITY_UNKNOWN;
        fbBase = BASE;
        fbType = layout->NAME;
        fbAsked = false;
        fbBound = true;
    }

    // A fresh session means the broker kept nothing, so every subscription has
    // to be asked for again. Running totals mean this cannot be missed.
    const int32_t connects = (int32_t)client->status().connects;
    if (connects != (int32_t)fbSeenConnects) {
        fbSeenConnects = connects;
        fbAsked = false;
    }

    uint8_t* base = DATA.PVALUE;
    const mq_time_t now = mq_millis();
    MqStructSubMember* table =
        (MqStructSubMember*)(uintptr_t)(strucpp::XWORD_t)fbMembers;
    const uint16_t count = layout->MEMBERCOUNT < (uint16_t)fbMemberCount
        ? layout->MEMBERCOUNT : (uint16_t)fbMemberCount;

    int bound = 0, refused = 0;
    bool allAsked = true;
    MqttResult worst = MqttResult::Ok;

    // The worst quality and the oldest age across the set, because a recipe
    // with one stale member is a recipe you should not run.
    MQTT_QUALITY worstQuality = MQTT_QUALITY::MQTT_QUALITY_GOOD;
    int32_t oldest = 0;
    bool anyNever = false;

    for (uint16_t i = 0; i < count; i++) {
        const strucpp::MemberDesc& member = layout->MEMBERS[i];

        if (!mq_memberIsPublishable(member)) {
            refused++;
            if (worst == MqttResult::Ok) worst = MqttResult::InvalidArgument;
            continue;
        }

        strucpp::IEC_ANY any;
        if (!mq_memberAsAny(member, base, &any)) { refused++; continue; }

        char topic[256];
        if (!mq_memberTopic(BASE.c_str(), member.NAME, topic, sizeof topic)) {
            refused++;
            if (worst == MqttResult::Ok) worst = MqttResult::InvalidTopic;
            continue;
        }

        MqttTopicHandle handle = (MqttTopicHandle)table[i].handle;
        if (handle < 0) {
            handle = client->registerTopic(topic);
            if (handle == MQTT_TOPIC_HANDLE_NONE) {
                // Out of handles. Said by name, because the fix is a build
                // flag and a block that subscribed to the first sixteen
                // members and not the rest would be far worse.
                refused++;
                allAsked = false;
                if (worst == MqttResult::Ok) worst = MqttResult::QueueFull;
                continue;
            }
            table[i].handle = (int16_t)handle;
        }
        bound++;

        if (!(bool)ENABLE) {
            client->unsubscribe(topic);
            allAsked = false;
            continue;
        }

        if (!(bool)fbAsked && client->isConnected()) {
            const MqttResult asked = client->subscribeTo(handle, (uint8_t)QOS);
            if (!mq_tolerated(asked)) {
                allAsked = false;
                if (worst == MqttResult::Ok) worst = asked;
            }
        }

        // Every message since the last scan, not just the last one: a fast
        // publisher and a slow task must not silently lose values.
        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            if (mq_parseAny((const char*)buffer, length, any)) {
                RECEIVED = (int32_t)RECEIVED + 1;
                table[i].arrivedAt = (int32_t)(uint32_t)now;
                table[i].ever = true;
                NEW_VALUES = (int16_t)NEW_VALUES + 1;
            } else {
                MALFORMED = (int32_t)MALFORMED + 1;
            }
        }

        const int32_t age = table[i].ever
            ? (int32_t)mq_elapsed((mq_time_t)(uint32_t)table[i].arrivedAt, now)
            : 0;
        if (!table[i].ever) anyNever = true;
        else if (age > oldest) oldest = age;

        const MQTT_QUALITY q = mq_qualityOf(table[i].ever,
                                            client->isConnected(), age,
                                            mq_millisOf(EXPECT));
        if ((int)q < (int)worstQuality) worstQuality = q;
    }

    if ((bool)ENABLE && allAsked && client->isConnected()) fbAsked = true;

    POINTS = (int16_t)bound;
    SKIPPED = (int16_t)refused;
    SUBSCRIBED = (bool)ENABLE && (bool)fbAsked && client->isConnected();
    OLDEST = mq_timeOf(anyNever ? 0 : oldest);
    SEEN = bound > 0 && !anyNever;
    QUALITY = bound == 0 ? MQTT_QUALITY::MQTT_QUALITY_UNKNOWN : worstQuality;

    if (worst != MqttResult::Ok) {
        ERROR = true;
        STATUS = (MQTT_RESULT)(int32_t)(int)worst;
    } else {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
    }
}

END_FUNCTION_BLOCK