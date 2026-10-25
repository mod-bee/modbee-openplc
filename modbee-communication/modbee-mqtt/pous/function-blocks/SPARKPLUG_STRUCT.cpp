(* A WHOLE STRUCT AS A SPARKPLUG METRIC SET. One block.

NODE       which node. Must be wired.
DATA       the STRUCT. Every value in it becomes one metric - nested STRUCTs
           and arrays included, named by path: level, pump.hours, spare[3].
DEVICE     a device under the node, or empty for the node's own metrics.
PREFIX     put before every metric name: 'Cmd/' makes systemMode the metric
           Cmd/systemMode. Empty by default. The same rule as BeeBus topics.
MODE       what triggers a message:
             MQTT_ON_CHANGE    only the members that moved, and all of them
                               anyway every PERIOD so silence stays
                               meaningful.
             MQTT_ON_INTERVAL  all of them, every PERIOD - and only then.
             MQTT_ON_REQUEST   all of them when REQ goes TRUE, never otherwise.
             MQTT_CHANGED_EVERY  the members that moved past their
                               deadband since they were last sent, together,
                               every PERIOD - and nothing when none moved. For
                               a metered link: a slow log of what changed. The
                               looks fall on the node's clock (whole PERIODs),
                               so every set with the same PERIOD goes in ONE
                               message.
           "All of them" is this block's members, never the rest of the
           node. In every mode but MQTT_ON_CHANGE the members are HELD: they
           do not ride along in other blocks' reports when they move, so a
           set of timers that changes every scan really goes every PERIOD.
PERIOD     MQTT_ON_CHANGE: send anyway after this long. T#0s never does.
           MQTT_ON_INTERVAL: how often. Required there.
           MQTT_CHANGED_EVERY: how often it looks for what moved. Required.
REQ        MQTT_ON_REQUEST: a rising edge sends the set.
WRITABLE   TRUE lets a Host Application COMMAND these members, each one by
           itself. Under a DEVICE the commands are DCMDs, and land the same way.
           Every write is seen, one a scan, oldest first: SCADA writing 1 and
           then 0 in one go leaves the member 1 for a scan and then 0.
           Declared writable once; while WRITABLE is FALSE after that, a write
           is dropped at once and counted on REFUSED, and the next message
           reports the member unchanged. It is never kept for later.
DEADBAND   REAL and LREAL members with no SETTINGS entry: a move of this much
           or less, from the value last SENT, is not reported. In the members'
           own units.
DEADBAND_PCT  the same, as a percentage of the value last sent. With both set
           a move must clear both. 0 (the default) reports every change.
SETTINGS   optional: an ARRAY OF SPARKPLUG_MEMBER, one entry per member that
           needs its own - see below.
ENABLE     FALSE stops publishing without losing the declarations. The set
           is held while FALSE and keeps its values current in the node, so a
           birth carries them as they are.

POINTS     how many values are declared as metrics.
SKIPPED    how many were not - a type the wire cannot carry, or a name already
           taken. Counted here, and ERROR is set.
SENT       running total of the messages that carried these members: one for
           each scan with something to send, not one per member. Counted when
           SPARKPLUG_NODE has sent it - on the scan after the one that asked.
           The members of every block that moved in one scan go in ONE
           message, and each of those blocks counts it.
CHANGED    how many members this scan handed to the node to send because they
           moved - past their deadband - or, when PERIOD or REQ sends them
           all, how many of them changed. They go on SPARKPLUG_NODE's next
           scan.
WRITTEN    how many commands have been applied to these members.
REFUSED    how many were refused - a value of the wrong type, or a write
           while WRITABLE is FALSE.
LOST       writes dropped because four were already waiting on one member:
           the oldest goes, the newest is kept. 0 in any sane system.
BAD_SETTING  the first SETTINGS entry that could not be used, counting from 1:
           a NAME that covers no member, a negative deadband or PULSE, a
           deadband on a BOOL or STRING. The other entries still apply. -1: SETTINGS is not an ARRAY OF
           SPARKPLUG_MEMBER, or DEADBAND is negative. 0 when all is well.
ERROR      something failed - including BAD_SETTING, until it is fixed.
STATUS     MQTT_OK when fine.

---

SPARKPLUG_MEMBER, one entry per member that needs its own settings:

  NAME          the member's path: 'levelMm', 'pump.hours', 'spare[3]'.
                Without PREFIX. Case does not matter. A whole array or nested
                STRUCT ('spare', 'pump') covers every value in it; entries
                apply in order, so a later one for spare[2] wins for it.
  UNITS         engineering units, sent in the birth as engUnit: 'mm', 'bar'.
  DEADBAND      its own deadband, in its units. 0 = every change.
  DEADBAND_PCT  its own deadband as a percentage of the value last sent.
                An entry's deadband replaces the block's for that member.
  LOW, HIGH     the range a SCADA gauge or trend should show, sent in the
                birth as engLow and engHigh. LOW = HIGH (both 0) for none.
  PULSE         a writable command the PLC clears by itself: this long after
                a write lands, the member goes back to 0 (FALSE, ''). T#0s,
                the default, keeps what was written.
  SKIP          TRUE leaves the member out: not a metric at all. FALSE puts
                back one an earlier entry left out, with this entry's
                numbers: [(NAME := 'sts', SKIP := TRUE),
                (NAME := 'sts.mode', SKIP := FALSE)] leaves out all of sts
                but sts.mode. Read once, when the metrics are declared.

  VAR
    sp      : SPARKPLUG_NODE;
    core    : SPARKPLUG_STRUCT;
    coreSet : ARRAY[1..3] OF SPARKPLUG_MEMBER := [
                (NAME := 'levelMm', UNITS := 'mm', DEADBAND := 10.0,
                 LOW := 0.0, HIGH := 3000.0),
                (NAME := 'pressureBar', UNITS := 'bar', DEADBAND := 0.02),
                (NAME := 'pumpHours', UNITS := 'h', DEADBAND := 0.1)];
  END_VAR

  coreSet[1].DEADBAND := CFG.levelDeadband;
  core(NODE := sp, DATA := CORE, SETTINGS := coreSet);

The settings are read again whenever they change - a deadband may follow a
setting from CFG every scan. Units and ranges go out in the birth, so a change
to them shows at the next birth.

A COMMAND STRUCT. Commands from SCADA are members of a WRITABLE struct like
any setpoint, each its own metric, written one at a time:

  cmds(NODE := sp, DATA := CMD.remote, PREFIX := 'Cmd/', WRITABLE := TRUE,
       SETTINGS := cmdSet);

A held signal - a run request, a mode - stays as written. A momentary command
needs the bit to go back to 0 before the next one. Either SCADA writes the
bit and then 0 - every write is queued and taken in order, so even a 1 and a
0 sent together are both seen - or the member gets PULSE in SETTINGS
(T#500ms, longer than the slowest task that reads it) and the PLC clears it,
so SCADA writes once per command.

---

THE STRUCT DECLARATION IS THE METRIC SET, and under Sparkplug that buys three
things at once rather than one.

  1. THE MEMBER PATH IS THE METRIC NAME, after PREFIX. Rename a member and you
     rename a metric, which is a real consequence and worth knowing before the
     third device is commissioned.
  2. THE DECLARED IEC TYPE IS THE METRIC DATATYPE. REAL becomes Float, UDINT
     becomes UInt32, and the birth certificate carries it - so the receiving
     end is TOLD the type rather than guessing it from the first value.
  3. THE MEMBER SET IS THE BIRTH CERTIFICATE. Sparkplug requires the birth to
     carry every metric the node will ever publish; a STRUCT is a closed,
     declared set, so that is satisfied by construction.

ONE MESSAGE, NOT N. The node sends ONE message carrying every metric that
moved - this block's, and every other block's on the node. That is the whole
bandwidth argument for Sparkplug, and on a metered link it is most of the
saving. This block marks what is to go and asks; SPARKPLUG_NODE sends one
NDATA, and one DDATA for each online device with something to say, on its
next scan, with that moment's timestamp. A message the node could not queue
shows here as ERROR with MQTT_QUEUE_FULL, on the scan after, and is asked for
again.

WRITABLE MAKES IT BIDIRECTIONAL ON ONE NAME. The host commands SETPOINT, this
block publishes SETPOINT, one struct member. A command lands in the STRUCT and
the next publish reports it back - always, even inside a deadband, because the
host watches for that echo to know the write took. Put readings and setpoints
in separate structs: WRITABLE declares every member writable.

THERE IS NO QOS OR RETAINED PIN. Sparkplug fixes both: data at QoS 0 and never
retained.

THE BLOCK'S DEADBAND IS FOR THE ANALOGS. One number covering members of mixed
types is a trap - a BOOL counts as 1, so a deadband above that would freeze
every bit in the struct including a FAULT - so DEADBAND and DEADBAND_PCT apply
to the REAL and LREAL members without a SETTINGS entry. BOOLs, integers and
STRINGs report every change unless an entry gives an integer its own. Measured
from the value last SENT, never the last scan, so a slow drift still adds up
and goes; the PERIOD heartbeat and a birth always carry every value as it is.

A TIME GOES AS AN Int64 OF MILLISECONDS, both ways, with units ms in the
birth: T#10s is 10000, and a host writing 90000 sets T#90s. Negative writes are
refused.

WHEN IT GOES, IN EACH MODE. The birth carries every member, whatever the mode:
a device that comes online (SPARKPLUG_DEVICE's ONLINE going TRUE) sends the
whole set in its DBIRTH, and MQTT_ON_INTERVAL counts PERIOD from that birth.
ENABLE going TRUE sends an MQTT_ON_INTERVAL set at once, then every PERIOD;
an MQTT_CHANGED_EVERY set sends what moved at once (not when its device was
born that scan: the birth carried it), then looks every PERIOD.
Nothing goes for a device that is offline.

AN ENUMERATION GOES AS THE UNSIGNED INTEGER IT IS STORED AS (UInt8, UInt16 or
UInt32 by its size), both ways: the value's code, as the library documents it.
A written code the type does not have is the program's to refuse, as for any
setting.

A VALUE THE WIRE CANNOT CARRY IS REFUSED, NOT SKIPPED QUIETLY. A DATE,
TIME_OF_DAY, or an ARRAY OF STRING outside a STRUCT: counted on SKIPPED.

HOW MANY MEMBERS: as many as the node takes - as many as memory holds, on a
board (in PSRAM where there is some) and the Runtime alike. A member past that
is refused and counted on SKIPPED, and SPARKPLUG_NODE's LAST_ERROR says "out
of memory for metrics or devices". *)

FUNCTION_BLOCK SPARKPLUG_STRUCT
  VAR_INPUT
    (* PIN ORDER IS A DESIGN DECISION, not a listing.
       The first input is read - by an engineer and by `check --lint` - as the
       one that makes the block do something: "block-primary-input-unassigned"
       fires when it is left unwired. DEVICE was first and is OPTIONAL, so
       every node-level use of this block was reported as doing nothing. DATA
       is what it operates on, so DATA is first.
       NO DEFAULT ON AN ENUM PIN, and that is the parser's rule rather than a
       preference: the block-header parser refuses a qualified enum literal in
       an initial value - "unexpected character: ->#<-". No MQTT_* block gives
       an enum pin a default either, for the same reason.

       Nothing is lost by it. Each enum TYPE carries its own default -
       MQTT_SECURITY is MQTT_PLAIN, MQTT_TRIGGER is MQTT_ON_CHANGE,
       MQTT_PROTOCOL is MQTT_V5_THEN_V311 - so an unwired pin behaves exactly
       as the prose above says. *)
    DATA : ANY;
    DEVICE : STRING(47);
    MODE : MQTT_TRIGGER;
    PERIOD : TIME;
    REQ : BOOL;
    WRITABLE : BOOL;
    ENABLE : BOOL := TRUE;
    DEADBAND : REAL;
    DEADBAND_PCT : REAL;
    PREFIX : STRING(32);
    SETTINGS : ANY;
  END_VAR
  VAR_OUTPUT
    POINTS : INT;
    SKIPPED : INT;
    SENT : DINT;
    CHANGED : INT;
    WRITTEN : DINT;
    REFUSED : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    BAD_SETTING : INT;
    LOST : DINT;
  END_VAR
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
  END_VAR
  VAR
    fbDeclared : BOOL;
    fbLastReq : BOOL;
    fbSetSentAt : DINT;
    fbEverSent : BOOL;
    fbCount : INT;
    fbDeadband : REAL;
    fbDeadbandPct : REAL;
    fbPlan : __XWORD;
    fbSettingsSum : UDINT;
    fbHeld : BOOL;
    fbWasOnline : BOOL;
    fbBirths : UDINT;
    fbWasEnabled : BOOL;
    fbAskedAt : UDINT;
    fbAsking : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <new>
#include <string>
#include <vector>
#include <string.h>
#include <strings.h>

// Defined by SPARKPLUG_NODE and MQTT_CLIENT, which sort before this file - and
// every C++ POU in a project lands in one translation unit in filename order.
MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
bool mq_spTypeOfClass(int typeClass, MqttSparkplugDataType* out);
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out);
bool mq_spWriteAny(const strucpp::IEC_ANY& any,
                   const MqttSparkplugValue& value);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

// =============================================================================
// THE MEMBER PLAN: the DECLARED values of the STRUCT, found once
// =============================================================================
//
// The STRUCT is walked when its metrics are declared: every value, nested
// STRUCTs and arrays included, each named by its PATH the way BeeBus names
// them - `level`, `pump.hours`, `spare[3]`, `zone[2].temp` (array elements
// from 1, whatever the declared bounds). The metric name is PREFIX + path.
//
// WHAT A SCAN WALKS IS ONLY WHAT WAS DECLARED. The plan keeps one small entry
// per metric - where the value is, its type, the node's index for it - and
// nothing for a value a SETTINGS entry left out (SKIP) or the node refused. A
// record of three hundred values with twenty published used to be walked whole,
// several times a scan, through 64-byte entries carrying each one's name; a
// two-pump controller program walked 3132 of them to publish 995. The entries are 12
// bytes, small enough to sit in internal RAM on a board.
//
// THE NAMES ARE NOT KEPT. They are needed only when SETTINGS are applied - to
// match an entry's NAME, and to say BAD_SETTING when it names nothing - and
// then the STRUCT's own layout is walked again, which costs nothing between
// changes. A bit per walked value says which ones were declared.
//
// Owned per block instance on the heap - a local __XWORD holds it, as
// SPARKPLUG_NODE holds the node - and freed when the program is unloaded.
namespace {

struct MqSpStructLeaf {
    uint32_t offset = 0;         // from DATA's first byte
    uint32_t point = 0;          // the node's index
    uint16_t size = 0;           // bytes, or a STRING's capacity
    uint8_t cls = 0;             // strucpp::TYPE_CLASS; an ENUM as its integer
    uint8_t spare = 0;
};

// PULSE, only for a block whose SETTINGS give one: by leaf, beside `leaves`.
struct MqSpStructPulse {
    int64_t pulseNs = 0;         // PULSE from the SETTINGS entry, 0 none
    mq_time_t writtenAt = 0;     // when a command landed
    bool pulsing = false;
};

// SETTINGS: an ARRAY OF SPARKPLUG_MEMBER, read through its layout - by the
// member names of the type, not offsets baked in here, so the block reads
// exactly what the project's copy of the type says and refuses anything that
// is not that type.
struct MqSpMemberLayout {
    int32_t name = -1, units = -1, deadband = -1, deadbandPct = -1;
    int32_t low = -1, high = -1, pulse = -1, skip = -1;
    uint32_t nameCap = 0, unitsCap = 0;    // the STRINGs' capacities
};

struct MqSpStructPlan {
    std::vector<MqSpStructLeaf> leaves;    // declared values, in walk order
    std::vector<MqSpStructPulse> pulses;   // empty until a PULSE is set
    std::vector<uint8_t> declared;         // a bit per walked value
    const strucpp::TypeDesc* type = nullptr;
    int pulsing = 0;                       // leaves pulsing now
    int skipped = 0;
    // SETTINGS' layout, looked up when its type is first seen rather than by
    // name every scan.
    const strucpp::TypeDesc* settingsType = nullptr;
    MqSpMemberLayout settingsLayout;
    bool settingsLooked = false;
    bool settingsLayoutOk = false;
    bool settingsApplied = false;
    // WRITES: whether the members were declared writable, the node's count of
    // accepted writes when this block last looked at all of them, and whether
    // any were still waiting then. A scan with no new write and none left has
    // nothing to look for.
    bool writable = false;
    uint32_t writesSeen = 0;
    bool writesLeft = false;
};

struct MqSpStructPlans {
    std::vector<MqSpStructPlan*> all;
    ~MqSpStructPlans() {
        for (size_t i = 0; i < all.size(); i++) delete all[i];
        all.clear();
    }
};
static MqSpStructPlans mqSpStructPlans;

}  // namespace

template <typename Visit>
static void mq_spStructValue(const std::string& path, uint32_t offset,
                             strucpp::TYPE_CLASS cls, uint32_t bytes,
                             uint32_t cap, int& skipped, Visit& visit) {
    MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
    const bool text = (cls == strucpp::TYPE_STRING);
    // An enumeration travels as the unsigned integer it is stored as (its
    // value's position: the codes a library documents), both ways, so a mode
    // or a protection's response is visible and writable from the host.
    if (cls == strucpp::TYPE_ENUM) {
        if (bytes == 1) cls = strucpp::TYPE_USINT;
        else if (bytes == 2) cls = strucpp::TYPE_UINT;
        else if (bytes == 4) cls = strucpp::TYPE_UDINT;
    }
    // A type the wire has no datatype for (DATE, TOD), and an ARRAY OF
    // STRING, whose capacity the layout does not carry: counted on SKIPPED,
    // never left out quietly.
    if (!mq_spTypeOfClass((int)cls, &type) || (text && cap == 0)) {
        skipped++;
        return;
    }
    visit(path, offset, cls, (uint32_t)(text ? cap : (bytes > 0 ? bytes : 1)));
}

// Every value of a STRUCT, in order, handed to `visit(path, offset, class,
// size)`: the path without PREFIX, the class an ENUM travels as, the size in
// bytes or a STRING's capacity. A value the wire has no datatype for is
// counted on `skipped` instead. The same walk declares and applies SETTINGS,
// so the two always agree on which value is which.
template <typename Visit>
static void mq_spStructWalk(const strucpp::TypeDesc* d, uint32_t base,
                            std::string& path, int depth, int& skipped,
                            Visit& visit) {
    if (d == nullptr || depth > 8) {
        skipped++;
        return;
    }
    for (uint16_t i = 0; i < d->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& m = d->MEMBERS[i];
        const size_t mark = path.size();
        path += (m.NAME ? m.NAME : "?");
        const uint32_t at = base + m.BYTEOFFSET;
        if (m.TYPECLASS == strucpp::TYPE_USERDEF) {
            path += '.';
            mq_spStructWalk(m.NESTED, at, path, depth + 1, skipped, visit);
        } else if (m.TYPECLASS == strucpp::TYPE_ARRAY) {
            const size_t name = path.size();
            for (uint32_t e = 0; e < m.NUMELEMENTS; e++) {
                path.resize(name);
                path += '[';
                path += std::to_string((unsigned long)(e + 1));
                path += ']';
                const uint32_t where = at + e * m.STRIDE;
                if (m.BASETYPECLASS == strucpp::TYPE_USERDEF) {
                    path += '.';
                    mq_spStructWalk(m.NESTED, where, path, depth + 1, skipped,
                                    visit);
                } else {
                    mq_spStructValue(path, where, m.BASETYPECLASS,
                                     m.ELEMBITSIZE / 8, m.CAP, skipped, visit);
                }
            }
        } else {
            mq_spStructValue(path, at, m.TYPECLASS, m.BITSIZE / 8, m.CAP,
                             skipped, visit);
        }
        path.resize(mark);
    }
}

static strucpp::IEC_ANY mq_spStructAny(const MqSpStructLeaf& leaf,
                                       uint8_t* base) {
    strucpp::IEC_ANY any;
    any.TYPECLASS = (strucpp::TYPE_CLASS)leaf.cls;
    any.ELEMCLASS = (strucpp::TYPE_CLASS)leaf.cls;
    any.PVALUE = base + leaf.offset;
    any.DISIZE = leaf.size;
    any.DICOUNT = 1;
    return any;
}

static bool mq_spMemberLayout(const strucpp::TypeDesc* d,
                              MqSpMemberLayout& out) {
    if (d == nullptr || d->NAME == nullptr ||
        strcasecmp(d->NAME, "SPARKPLUG_MEMBER") != 0) {
        return false;
    }
    for (uint16_t i = 0; i < d->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& m = d->MEMBERS[i];
        if (m.NAME == nullptr) continue;
        const int32_t at = (int32_t)m.BYTEOFFSET;
        if (strcasecmp(m.NAME, "NAME") == 0) {
            out.name = at;
            out.nameCap = m.CAP;
        } else if (strcasecmp(m.NAME, "UNITS") == 0) {
            out.units = at;
            out.unitsCap = m.CAP;
        }
        else if (strcasecmp(m.NAME, "DEADBAND") == 0) out.deadband = at;
        else if (strcasecmp(m.NAME, "DEADBAND_PCT") == 0) out.deadbandPct = at;
        else if (strcasecmp(m.NAME, "LOW") == 0) out.low = at;
        else if (strcasecmp(m.NAME, "HIGH") == 0) out.high = at;
        else if (strcasecmp(m.NAME, "PULSE") == 0) out.pulse = at;
        else if (strcasecmp(m.NAME, "SKIP") == 0) out.skip = at;
    }
    return out.name >= 0 && out.units >= 0 && out.deadband >= 0 &&
           out.deadbandPct >= 0 && out.low >= 0 && out.high >= 0 &&
           out.pulse >= 0 && out.skip >= 0;
}

// Whether a SETTINGS NAME covers a value's path: the value itself, or an
// array or nested STRUCT it is inside - 'spare' covers spare[1] and spare[2],
// 'pump' covers pump.hours. Case does not matter, as in ST.
static bool mq_spPathCovers(const char* path, const char* name) {
    const size_t n = strlen(name);
    if (strncasecmp(path, name, n) != 0) return false;
    return path[n] == '\0' || path[n] == '.' || path[n] == '[';
}

// Apply the whole-struct deadband and every SETTINGS entry. Returns the
// position (from 1) of the first entry that names no member or holds a value
// that cannot be used, or 0. Called once after the declarations and again
// whenever the settings or the deadband pins change.
//
// Value by value rather than entry by entry - one walk of the STRUCT, each
// value tried against the entries in order - which ends the same: entries
// apply in order and the later one wins for a value either way.
static int mq_spStructApply(MqttSparkplugNode* node, MqSpStructPlan& plan,
                            const strucpp::IEC_ANY& settings,
                            const MqSpMemberLayout& layout, bool haveLayout,
                            double band, double pct) {
    // The defaults first: the struct's deadband on its REAL and LREAL members
    // and none on anything else; units only where the type implies them.
    for (size_t i = 0; i < plan.leaves.size(); i++) {
        const MqSpStructLeaf& leaf = plan.leaves[i];
        if (!plan.pulses.empty()) plan.pulses[i].pulseNs = 0;
        const bool analog = leaf.cls == strucpp::TYPE_REAL ||
                            leaf.cls == strucpp::TYPE_LREAL;
        node->deadbandAt(leaf.point, analog ? band : 0.0, analog ? pct : 0.0);
        // A TIME travels as milliseconds; saying so is what makes the number
        // mean something at the far end.
        node->unitsAt(leaf.point, leaf.cls == strucpp::TYPE_TIME ? "ms" : "");
        node->rangeAt(leaf.point, 0.0, 0.0);
    }
    if (!haveLayout || !settings.wired()) return 0;

    const bool array = settings.TYPECLASS == strucpp::TYPE_ARRAY;
    const int32_t count = array ? settings.count() : 1;
    if (count <= 0) return 0;
    // Per entry: 0 unused, 1 in use, 2 in use and matched; and whether it
    // could not be used. BAD_SETTING is the first entry with a fault.
    std::vector<uint8_t> state((size_t)count, 0);
    std::vector<uint8_t> fault((size_t)count, 0);
    for (int32_t k = 0; k < count; k++) {
        uint8_t* entry = array ? settings.at(k) : settings.PVALUE;
        const char* path = (const char*)(entry + layout.name);
        if (path[0] == '\0') continue;             // an unused entry
        const float ownBand = *(const float*)(entry + layout.deadband);
        const float ownPct = *(const float*)(entry + layout.deadbandPct);
        const int64_t pulse = *(const int64_t*)(entry + layout.pulse);
        if (!(ownBand >= 0.0f) || !(ownPct >= 0.0f) || pulse < 0) {
            fault[(size_t)k] = 1;                  // its numbers cannot be used
            continue;
        }
        state[(size_t)k] = 1;
    }

    // Every value the NAME covers - the member itself, or every value of an
    // array or nested STRUCT it names - ignoring case as ST does: `Pump.Hours`
    // is `pump.hours`. PREFIX is not part of it.
    size_t ordinal = 0;   // the value's place in the walk
    size_t next = 0;      // the next declared one's place in `leaves`
    auto visit = [&](const std::string& valuePath, uint32_t, strucpp::TYPE_CLASS,
                     uint32_t) {
        const size_t at = ordinal++;
        const bool declared = at / 8 < plan.declared.size() &&
                              (plan.declared[at / 8] >> (at % 8)) & 1u;
        const size_t index = declared ? next++ : 0;
        for (int32_t k = 0; k < count; k++) {
            if (state[(size_t)k] == 0) continue;
            uint8_t* entry = array ? settings.at(k) : settings.PVALUE;
            const char* path = (const char*)(entry + layout.name);
            if (!mq_spPathCovers(valuePath.c_str(), path)) continue;
            state[(size_t)k] = 2;
            // An entry that leaves its members out has no numbers to give
            // them: a member in after all is in by a LATER entry, and takes
            // that one's. A value left out or refused takes nothing.
            const bool skip = *(const bool*)(entry + layout.skip);
            if (!declared || skip) continue;
            const char* units = (const char*)(entry + layout.units);
            const float ownBand = *(const float*)(entry + layout.deadband);
            const float ownPct = *(const float*)(entry + layout.deadbandPct);
            const float low = *(const float*)(entry + layout.low);
            const float high = *(const float*)(entry + layout.high);
            const int64_t pulse = *(const int64_t*)(entry + layout.pulse);
            const size_t point = plan.leaves[index].point;
            if (pulse > 0 && plan.pulses.empty()) {
                plan.pulses.resize(plan.leaves.size());
            }
            if (!plan.pulses.empty()) plan.pulses[index].pulseNs = pulse;
            // ITS OWN NUMBERS: a member listed here takes this entry's
            // deadband, not the struct's - 0 means every change. A deadband on
            // a BOOL or a STRING is refused, as SPARKPLUG_METRIC refuses it: it
            // would freeze the value.
            if (!node->deadbandAt(point, (double)ownBand, (double)ownPct)) {
                // Named by itself, that is a mistake to report. Covered as
                // part of an array or STRUCT, the BOOLs and STRINGs in it just
                // keep reporting every change.
                if (strcasecmp(valuePath.c_str(), path) == 0) {
                    fault[(size_t)k] = 1;
                } else {
                    node->deadbandAt(point, 0.0, 0.0);
                }
            }
            if (units[0] != '\0') node->unitsAt(point, units);
            node->rangeAt(point, (double)low, (double)high);
        }
    };
    std::string path;
    int skipped = 0;
    mq_spStructWalk(plan.type, 0, path, 0, skipped, visit);

    for (int32_t k = 0; k < count; k++) {
        if (fault[(size_t)k] || state[(size_t)k] == 1) return (int)k + 1;
    }
    return 0;
}

// A FINGERPRINT OF WHAT mq_spStructApply() READS, and nothing else: each
// entry's NAME and UNITS up to their end, its four numbers, PULSE and SKIP -
// a word at a time for the numbers. It was every byte of the array, the
// forcing wrappers around each value included: about two hundred bytes an
// entry, one at a time, on every scan - in a two-pump controller program 42 kB a
// scan, most of the blocks' whole cost. Each step is a one-to-one mix of the
// running value with the next word, so a change to any one field always
// changes the result.
static inline uint32_t mq_spMix(uint32_t h, uint32_t word) {
    return (h ^ word) * 16777619u;
}

static uint32_t mq_spMixText(uint32_t h, const char* text, uint32_t cap) {
    const uint32_t limit = cap != 0 ? cap : 254u;
    for (uint32_t i = 0; i < limit && text[i] != '\0'; i++) {
        h = mq_spMix(h, (uint8_t)text[i]);
    }
    return mq_spMix(h, 0x100u);   // the end, so 'ab'+'c' is not 'a'+'bc'
}

static uint32_t mq_spMixReal(uint32_t h, const uint8_t* at) {
    const float value = *(const float*)at;
    uint32_t bits;
    memcpy(&bits, &value, sizeof bits);
    return mq_spMix(h, bits);
}

static uint32_t mq_spStructSettingsSum(const strucpp::IEC_ANY& settings,
                                       const MqSpMemberLayout& layout,
                                       bool haveLayout) {
    // Not SPARKPLUG_MEMBER, or not wired: nothing in it is read.
    if (!settings.wired() || !haveLayout) return 0;
    const bool array = settings.TYPECLASS == strucpp::TYPE_ARRAY;
    const int32_t count = array ? settings.count() : 1;
    uint32_t h = 2166136261u;
    for (int32_t k = 0; k < count; k++) {
        const uint8_t* entry = array ? settings.at(k) : settings.PVALUE;
        const char* name = (const char*)(entry + layout.name);
        h = mq_spMixText(h, name, layout.nameCap);
        if (name[0] == '\0') continue;            // an unused entry
        h = mq_spMixText(h, (const char*)(entry + layout.units),
                         layout.unitsCap);
        h = mq_spMixReal(h, entry + layout.deadband);
        h = mq_spMixReal(h, entry + layout.deadbandPct);
        h = mq_spMixReal(h, entry + layout.low);
        h = mq_spMixReal(h, entry + layout.high);
        const uint64_t pulse = (uint64_t)*(const int64_t*)(entry + layout.pulse);
        h = mq_spMix(h, (uint32_t)pulse);
        h = mq_spMix(h, (uint32_t)(pulse >> 32));
        h = mq_spMix(h, *(const uint8_t*)(entry + layout.skip));
    }
    return h;
}

void setup()
{
    POINTS = 0;
    SKIPPED = 0;
    SENT = 0;
    CHANGED = 0;
    WRITTEN = 0;
    REFUSED = 0;
    BAD_SETTING = 0;
    LOST = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbDeclared = false;
    fbLastReq = false;
    fbSetSentAt = 0;
    fbEverSent = false;
    fbCount = 0;
    fbDeadband = 0.0f;
    fbDeadbandPct = 0.0f;
    fbPlan = (strucpp::XWORD_t)0;
    fbSettingsSum = 0;
    fbHeld = false;
    fbWasOnline = false;
    fbBirths = 0;
    fbWasEnabled = false;
    fbAsking = false;
    fbAskedAt = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    CHANGED = 0;

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)NODE.FBAPI);
    if (!node) {
        // The node has not been built yet. Not an error on the first scan -
        // SPARKPLUG_NODE allocates on its own first enabled scan and this
        // block runs after it.
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    const strucpp::TypeDesc* layout = DATA.TYPEDESC;
    uint8_t* base = DATA.PVALUE;
    if (!layout || !base || DATA.TYPECLASS != strucpp::TYPE_USERDEF) {
        // DATA must be one STRUCT. An array of them would publish its first
        // element and nothing else - refused rather than half done.
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const char* device = DEVICE.length() != 0 ? DEVICE.c_str() : nullptr;

    MqSpStructPlan* plan = (MqSpStructPlan*)(uintptr_t)(strucpp::XWORD_t)fbPlan;

    // --- Declare, once, before the node births ---
    //
    // This is the one thing that cannot be deferred. Sparkplug requires the
    // birth certificate to carry every metric the node will ever publish, so
    // the whole set has to exist before the node connects - which is why
    // SPARKPLUG_NODE waits a scan before connecting.
    if (!fbDeclared) {
        fbDeclared = true;

        plan = new (std::nothrow) MqSpStructPlan();
        if (plan == nullptr) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_INITIALISED;
            return;
        }
        mqSpStructPlans.all.push_back(plan);
        fbPlan = (strucpp::XWORD_t)(uintptr_t)plan;
        plan->type = layout;
        plan->writable = (bool)WRITABLE;

        // Every value, by path, for this scan only: what is declared is kept,
        // the names are not.
        struct Value {
            std::string path;
            uint32_t offset;
            uint16_t size;
            uint8_t cls;
            bool excluded;
        };
        std::vector<Value> values;
        {
            auto collect = [&](const std::string& path, uint32_t offset,
                               strucpp::TYPE_CLASS cls, uint32_t size) {
                values.push_back(Value{path, offset, (uint16_t)size,
                                       (uint8_t)cls, false});
            };
            std::string path;
            mq_spStructWalk(layout, 0, path, 0, plan->skipped, collect);
        }

        // Adding a device twice is refused by the node, which is correct and
        // not an error here: two SPARKPLUG_STRUCT blocks may share one device,
        // one for readings and one for setpoints.
        //
        // ONLY THE BLOCK THAT ADDS THE DEVICE BRINGS IT ONLINE. A device a
        // SPARKPLUG_DEVICE block added first is that block's to bring up and
        // down - its ONLINE pin is the program's decision - and this used to
        // owe its birth regardless, so a device held offline with ONLINE :=
        // FALSE birthed with its node anyway. Found in field testing, with
        // a link's on-request detail device.
        const bool addedHere = device != nullptr && node->addDevice(device);

        // SKIP, read now because it decides what is declared: a value an
        // entry leaves out is not a metric at all - an internal counter, a
        // spare - and is not counted as refused. The birth is closed after
        // this, so a SKIP changed later does nothing.
        //
        // EVERY ENTRY SAYS IN OR OUT, in order, and the later one wins, as
        // for the numbers: [('sts', SKIP TRUE), ('sts.mode', SKIP FALSE)]
        // leaves out all of sts but sts.mode. Entries with SKIP FALSE used
        // to be passed over here, so a member an earlier entry left out could
        // never be brought back, and its own entry's deadband and units were
        // lost with it.
        {
            MqSpMemberLayout memberLayout;
            if (SETTINGS.wired() &&
                mq_spMemberLayout(SETTINGS.TYPEDESC, memberLayout)) {
                const bool array = SETTINGS.TYPECLASS == strucpp::TYPE_ARRAY;
                const int32_t entries = array ? SETTINGS.count() : 1;
                for (int32_t k = 0; k < entries; k++) {
                    uint8_t* entry = array ? SETTINGS.at(k) : SETTINGS.PVALUE;
                    const char* path = (const char*)(entry + memberLayout.name);
                    if (path[0] == '\0') continue;   // an unused entry
                    const bool skip = *(const bool*)(entry + memberLayout.skip);
                    for (size_t i = 0; i < values.size(); i++) {
                        if (mq_spPathCovers(values[i].path.c_str(), path)) {
                            values[i].excluded = skip;
                        }
                    }
                }
            }
        }

        size_t wanted = 0;
        for (size_t i = 0; i < values.size(); i++) {
            if (!values[i].excluded) wanted++;
        }
        plan->leaves.reserve(wanted);
        plan->declared.assign((values.size() + 7) / 8, 0);

        const std::string prefix(PREFIX.c_str(), PREFIX.length());
        std::string name;
        int refused = plan->skipped;
        for (size_t i = 0; i < values.size(); i++) {
            const Value& value = values[i];
            if (value.excluded) continue;
            MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
            mq_spTypeOfClass((int)value.cls, &type);
            // THE PATH, EXACTLY AS DECLARED, after PREFIX. Not folded:
            // Sparkplug metric names are case sensitive, and rewriting one
            // would merge two tags into one at the far end.
            name.assign(prefix);
            name += value.path;
            uint64_t alias = 0;
            if (device != nullptr) {
                alias = (bool)WRITABLE
                    ? node->declareWritableFor(device, name.c_str(), type)
                    : node->declareFor(device, name.c_str(), type);
            } else {
                alias = (bool)WRITABLE
                    ? node->declareWritable(name.c_str(), type)
                    : node->declare(name.c_str(), type);
            }
            const int point = alias != 0 ? node->indexOf(device, name.c_str())
                                         : -1;
            if (point < 0) {
                // A name already taken on this node (or device), or past the
                // node's metric limit.
                refused++;
                continue;
            }
            MqSpStructLeaf leaf;
            leaf.offset = value.offset;
            leaf.point = (uint32_t)point;
            leaf.size = value.size;
            leaf.cls = value.cls;
            plan->leaves.push_back(leaf);
            plan->declared[i / 8] |= (uint8_t)(1u << (i % 8));
        }
        const int declared = (int)plan->leaves.size();
        fbCount = (int16_t)declared;
        POINTS = (int16_t)declared;
        SKIPPED = (int16_t)refused;

        if (addedHere) {
            // The DBIRTH is owed rather than sent: the node has not birthed
            // yet, and a device birth must follow the node's.
            node->deviceOnline(device);
        }
        // The settings are applied on the next scan, below, like any later
        // change to them.
        fbSettingsSum = 0;
        fbDeadband = -1.0f;
        ERROR = refused > 0;
        STATUS = refused > 0 ? MQTT_RESULT::MQTT_INVALID_ARGUMENT
                             : MQTT_RESULT::MQTT_OK;
        return;
    }
    if (plan == nullptr) return;
    MqSpStructLeaf* const leaves = plan->leaves.data();
    const size_t count = plan->leaves.size();

    // --- Deadbands, units and ranges, whenever SETTINGS or the pins change ---
    //
    // A fingerprint of what SETTINGS says, and the two deadband pins, every
    // scan; the work is done only when one moves, so a program may copy its
    // deadbands from CFG into SETTINGS on every scan at no cost.
    {
        if (!plan->settingsLooked || SETTINGS.TYPEDESC != plan->settingsType) {
            plan->settingsLooked = true;
            plan->settingsType = SETTINGS.TYPEDESC;
            plan->settingsLayout = MqSpMemberLayout();
            plan->settingsLayoutOk =
                mq_spMemberLayout(SETTINGS.TYPEDESC, plan->settingsLayout);
            plan->settingsApplied = false;
        }
        const MqSpMemberLayout& memberLayout = plan->settingsLayout;
        const bool haveLayout = SETTINGS.wired() && plan->settingsLayoutOk;
        const float band = (float)DEADBAND;
        const float pct = (float)DEADBAND_PCT;
        const uint32_t sum =
            mq_spStructSettingsSum(SETTINGS, memberLayout, haveLayout);
        if (!plan->settingsApplied || sum != (uint32_t)fbSettingsSum ||
            band != (float)fbDeadband || pct != (float)fbDeadbandPct) {
            plan->settingsApplied = true;
            fbSettingsSum = sum;
            fbDeadband = band;
            fbDeadbandPct = pct;
            int bad = 0;
            if (SETTINGS.wired() && !haveLayout) {
                // Something that is not SPARKPLUG_MEMBER.
                bad = -1;
                mq_spStructApply(node, *plan, SETTINGS, memberLayout, false,
                                 band < 0.0f ? 0.0 : (double)band,
                                 pct < 0.0f ? 0.0 : (double)pct);
            } else {
                bad = mq_spStructApply(node, *plan, SETTINGS, memberLayout,
                                       haveLayout,
                                       band < 0.0f ? 0.0 : (double)band,
                                       pct < 0.0f ? 0.0 : (double)pct);
            }
            if ((band < 0.0f || pct < 0.0f) && bad == 0) bad = -1;
            BAD_SETTING = (int16_t)bad;
        }
    }
    // Fine - unless SETTINGS could not be used, which stays an alarm until it
    // is fixed, whatever the publishing does.
    const bool settingsBad = (int16_t)BAD_SETTING != 0;

    // --- HELD: a set on its own clock goes on its own clock ---
    //
    // MQTT_ON_INTERVAL and MQTT_ON_REQUEST members are held by the node: left
    // out of every other block's report-by-exception message, so a record of
    // timers that moves every scan goes every PERIOD (or on REQ) and not with
    // each status change. MQTT_ON_CHANGE members go when they move, as ever.
    //
    // A SET SWITCHED OFF IS HELD TOO, whatever its mode: it keeps its values
    // current in the node (below) so a birth carries them as they are, and a
    // held member never rides along in another block's report.
    {
        const bool hold = MODE != MQTT_TRIGGER::MQTT_ON_CHANGE || !(bool)ENABLE;
        if (hold != (bool)fbHeld) {
            fbHeld = hold;
            for (size_t i = 0; i < count; i++) node->holdAt(leaves[i].point, hold);
        }
    }

    // --- A BIRTH IS A SEND ---
    //
    // The NBIRTH, or this device's DBIRTH, carried every member as it was, so
    // PERIOD runs from it: a device brought online for someone viewing it
    // sends the set once in its birth and then every PERIOD - not again at
    // once, and not after a PERIOD left over from before. Watched whether
    // enabled or not, so ENABLE going TRUE below still sends at once.
    const bool born = node->isBorn();
    const mq_time_t now = mq_millis();
    const bool online = born &&
        (device == nullptr || node->deviceIsOnline(device));
    //
    // MQTT_CHANGED_EVERY looks on the node's clock, birth or not: a birth only
    // sets what was last sent, which its look compares against, so a birth -
    // this set's, or any other device's - never brings a look forward. (It
    // did: every settings device born for a viewer sent the live set again.)
    // bornNow: THIS set came online this scan - its node's birth, or its own
    // device's - so that birth carried its members.
    const bool bornNow = online && !(bool)fbWasOnline;
    {
        const uint32_t births = node->birthCount();
        if (online && (!(bool)fbWasOnline || births != (uint32_t)fbBirths)) {
            if (MODE != MQTT_TRIGGER::MQTT_CHANGED_EVERY) {
                fbEverSent = true;
                fbSetSentAt = (int32_t)now;
            }
        }
        fbWasOnline = online;
        fbBirths = births;
    }

    // --- WHAT BECAME OF THE MESSAGE ASKED FOR ---
    //
    // THIS BLOCK DOES NOT SEND. It marks its members and asks the node, and
    // SPARKPLUG_NODE sends ONE NDATA, and one DDATA a device, carrying
    // everything on the node that moved, on its next scan. Every
    // block with a change used to send its own message, and every one of them
    // walked every metric of the node and of each online device.
    //
    // So SENT counts a message once the node has made it - the scan after
    // this block asked. One the node could not queue is this block's ERROR
    // now and is asked for again below; one that did not go because the node
    // is no longer born is nothing to report - its next birth carries the
    // values.
    bool askFailed = false;
    if ((bool)fbAsking && node->pollPublishes() != (uint32_t)fbAskedAt) {
        fbAsking = false;
        if (node->pollPublishSent()) {
            SENT = SENT + 1;
        } else if (online) {
            askFailed = true;
        }
    }
    auto finish = [&]() {
        if (askFailed) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
        } else {
            ERROR = settingsBad;
            STATUS = settingsBad ? MQTT_RESULT::MQTT_INVALID_ARGUMENT
                                 : MQTT_RESULT::MQTT_OK;
        }
    };

    // --- NOT WRITABLE: a write is dropped at once, never kept ---
    //
    // WRITABLE decides the declaration, once, so after it goes FALSE the node
    // still takes writes for members declared writable. They waited in its
    // queue until WRITABLE was TRUE again, and then the old command acted by
    // itself - a site whose remote control was off changed mode on its own
    // when it came back on. Each one is taken and dropped, counted
    // on REFUSED, and the member's own value put back into the node, so the
    // next message reports it unchanged: the host sees the write did not take.
    // Before ENABLE, so a block switched off keeps nothing either.
    //
    // ONLY WHEN THERE CAN BE ONE. Members declared read-only never take a
    // write - the node refuses it - and a write the node accepts moves its
    // commandsApplied() count, so with the count where this block last
    // emptied its members there is nothing waiting. It looked at every member
    // of every non-writable block, every scan.
    const uint32_t applied = node->commandsApplied();
    if (!(bool)WRITABLE && plan->writable &&
        (applied != plan->writesSeen || plan->writesLeft)) {
        plan->writesSeen = applied;
        plan->writesLeft = false;
        for (size_t i = 0; i < count; i++) {
            const MqSpStructLeaf& leaf = leaves[i];
            MqttSparkplugValue value;
            bool dropped = false;
            while (node->commandPendingAt(leaf.point) &&
                   node->takeAt(leaf.point, value)) {
                REFUSED = REFUSED + 1;
                dropped = true;
            }
            if (dropped &&
                mq_spValueOfAny(mq_spStructAny(leaf, base), &value)) {
                node->setAt(leaf.point, value);
            }
        }
    }

    const bool changedEvery = MODE == MQTT_TRIGGER::MQTT_CHANGED_EVERY;
    if (!(bool)ENABLE) {
        fbWasEnabled = false;
        // A set switched off is held (above) and still puts its values into
        // the node: a birth carries every member as it is, and nothing goes
        // because of it. It returned before the values went in, so a set
        // switched off - a device's values while nobody views it - went into
        // every birth as it was when it was switched off, and the scan it was
        // switched on sent everything again in a DDATA straight after the
        // device's DBIRTH.
        for (size_t i = 0; i < count; i++) {
            MqttSparkplugValue value;
            if (mq_spValueOfAny(mq_spStructAny(leaves[i], base), &value)) {
                node->setAt(leaves[i].point, value);
            }
        }
        finish();
        return;
    }
    if (!(bool)fbWasEnabled) {
        fbWasEnabled = true;
        // Enabled: an interval set goes at once, then every PERIOD; a
        // changed-every set sends what moved at once, then looks every PERIOD.
        // Not when it was born this scan: the birth carried every member.
        if (MODE == MQTT_TRIGGER::MQTT_ON_INTERVAL) fbEverSent = false;
        if (changedEvery && !bornNow) fbEverSent = false;
    }

    // --- ONE PASS: commands in, PULSE, values out, what will go ---
    //
    // Each member's own steps, in this order, and all of them in one walk of
    // the declared members - a member's steps touch only that member, so one
    // pass ends as the four separate passes did.
    //
    // COMMANDS BEFORE VALUES, so a command applied this scan is reported back
    // in the same publish rather than the next one - which is what makes a
    // setpoint look responsive at the far end. On THIS block's device: a DCMD
    // is held on the device's metric. ONE WRITE A MEMBER A SCAN, THE OLDEST
    // FIRST. SPARKPLUG_NODE queues every write (four a metric), so a host
    // writing 1 and then 0 inside one scan leaves the member 1 for a scan and
    // then 0 - the program sees both.
    //
    // PULSE: a command the PLC takes back itself. A momentary button: SCADA
    // writes the bits once, the program sees them for PULSE, and this block
    // puts the member back to 0 (FALSE, '') - which the next message reports.
    // Writing the same command again then acts again, and SCADA never has to
    // send the clearing write a momentary button otherwise needs.
    //
    // VALUES INTO THE NODE from the first scan, born or not: THE BIRTH CARRIES
    // THEM [tck-id-operational-behavior-data-publish-nbirth-values]. The node
    // holds what was last PUBLISHED, so a slow drift adds up and eventually
    // goes. And for MQTT_ON_CHANGE, WHAT WILL ACTUALLY GO - past its deadband
    // since it was last sent, or a host's own write coming back - counted
    // before it goes.
    //
    // Writes are looked for only when one can be waiting: a new write on the
    // node since the last look, or one left over from it (one a scan).
    const bool takeWrites = born && (bool)WRITABLE && plan->writable &&
        (applied != plan->writesSeen || plan->writesLeft);
    if (takeWrites) {
        plan->writesSeen = applied;
        plan->writesLeft = false;
    }
    const bool watch = online && MODE == MQTT_TRIGGER::MQTT_ON_CHANGE;
    int32_t lost = 0;
    int moved = 0;
    int going = 0;
    for (size_t i = 0; i < count; i++) {
        MqSpStructLeaf& leaf = leaves[i];
        if (takeWrites) {
            lost += (int32_t)node->writesLostAt(leaf.point);
            MqttSparkplugValue value;
            if (node->commandPendingAt(leaf.point) &&
                node->takeAt(leaf.point, value)) {
                if (mq_spWriteAny(mq_spStructAny(leaf, base), value)) {
                    WRITTEN = WRITTEN + 1;
                    if (!plan->pulses.empty() && plan->pulses[i].pulseNs > 0) {
                        MqSpStructPulse& pulse = plan->pulses[i];
                        if (!pulse.pulsing) plan->pulsing++;
                        pulse.pulsing = true;
                        pulse.writtenAt = now;
                    }
                } else {
                    // The value did not fit the declared type. Counted, not
                    // applied - and the node has already counted its own
                    // refusals for names it never declared.
                    REFUSED = REFUSED + 1;
                }
            }
            if (node->commandPendingAt(leaf.point)) plan->writesLeft = true;
        }
        if (plan->pulsing > 0 && plan->pulses[i].pulsing) {
            MqSpStructPulse& pulse = plan->pulses[i];
            const int64_t heldNs =
                (int64_t)mq_elapsed(pulse.writtenAt, now) * 1000000LL;
            if (heldNs >= pulse.pulseNs) {
                pulse.pulsing = false;
                plan->pulsing--;
                uint8_t* at = base + leaf.offset;
                if (leaf.cls == strucpp::TYPE_STRING) {
                    at[0] = '\0';
                } else if (leaf.cls == strucpp::TYPE_BOOL) {
                    *(bool*)at = false;
                } else {
                    memset(at, 0, (size_t)leaf.size);
                }
            }
        }
        MqttSparkplugValue value;
        if (mq_spValueOfAny(mq_spStructAny(leaf, base), &value) &&
            node->setAt(leaf.point, value)) {
            moved++;
        }
        if (watch && node->changePendingAt(leaf.point)) going++;
    }
    if (takeWrites) LOST = lost;

    if (!online || count == 0) {
        // Nothing to SAY until the node has birthed - with a primary host
        // configured that can be a while, and it is not an error. Nor for a
        // device that is offline: its next birth carries the values.
        //
        // Not "nothing moved": that was the test here, and it never held -
        // setAt() said every value changed - which hid that it is the wrong
        // test. A PERIOD, a heartbeat or REQ sends members that did not move,
        // and a host's write of the value already there still goes back to
        // it. What will go is `going`, counted in the pass above.
        finish();
        return;
    }

    // --- Values out ---
    const int32_t intervalMs = mq_millisOf(PERIOD);
    const bool asked = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;

    if ((MODE == MQTT_TRIGGER::MQTT_ON_INTERVAL || changedEvery) && intervalMs <= 0) {
        // Refused rather than turned into "every scan": thirty metrics at the
        // task rate is how a broker falls over.
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const bool sendAll =
        MODE == MQTT_TRIGGER::MQTT_ON_REQUEST
            ? asked
            : (MODE == MQTT_TRIGGER::MQTT_ON_INTERVAL &&
               (!(bool)fbEverSent ||
                (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetSentAt,
                                    now) >= intervalMs));

    // The heartbeat for MQTT_ON_CHANGE. Without it a value that never moves is
    // indistinguishable from a device that has died.
    const bool heartbeat =
        MODE == MQTT_TRIGGER::MQTT_ON_CHANGE && intervalMs > 0 &&
        (bool)fbEverSent &&
        (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetSentAt, now)
            >= intervalMs;

    // A set the node could not queue is asked for again at once. (Changes
    // need nothing: they stay pending until they go, so `going` asks again.)
    const bool retry = askFailed && MODE != MQTT_TRIGGER::MQTT_ON_CHANGE && !changedEvery;

    bool ask = false;
    if (sendAll || heartbeat || retry) {
        // THIS BLOCK'S MEMBERS, marked to go with whatever else moved. It
        // was publishAll() - every metric of the node and of every online
        // device, each time - which on a metered link turned one record's
        // PERIOD into the whole node's.
        for (size_t i = 0; i < count; i++) node->reportAt(leaves[i].point);
        // The members that moved, not all of them: setAt() now says which.
        CHANGED = (int16_t)moved;
        ask = true;
    } else if (MODE == MQTT_TRIGGER::MQTT_ON_CHANGE) {
        CHANGED = (int16_t)going;
        ask = going > 0;
    } else if (changedEvery) {
        // EVERY PERIOD, WHAT MOVED: each member past its deadband since it was
        // last sent (or a host's write coming back) - the node's own test,
        // which says no for a held member, so the hold is lifted for the
        // question and put back at once - is marked to go. Nothing moved,
        // nothing goes. The members that were marked stay marked until they
        // have gone, so a message the node could not queue is only asked for
        // again.
        //
        // ON ONE CLOCK: a look falls on a whole multiple of PERIOD of the
        // node's time, not a PERIOD after this set's own last look - so every
        // set with the same PERIOD looks in the same scan and their changes
        // go in ONE message. Each on its own clock, a 30 s live interval went
        // as three or four messages a scan apart, each paying its own headers
        // on the link. fbSetSentAt holds the slot last looked at.
        const uint32_t slot = (uint32_t)now / (uint32_t)intervalMs;
        if (askFailed) {
            ask = true;
        } else if (!(bool)fbEverSent || slot != (uint32_t)(int32_t)fbSetSentAt) {
            int marked = 0;
            for (size_t i = 0; i < count; i++) {
                const size_t point = leaves[i].point;
                node->holdAt(point, false);
                const bool movedPast = node->changePendingAt(point);
                node->holdAt(point, true);
                if (movedPast) {
                    node->reportAt(point);
                    marked++;
                }
            }
            CHANGED = (int16_t)marked;
            ask = marked > 0;
            // The next look is at the next slot, sent or not.
            fbEverSent = true;
            fbSetSentAt = (int32_t)slot;
        }
    }

    if (ask) {
        // One message for everything on the node that moved, made by
        // SPARKPLUG_NODE on its next scan. PERIOD runs from now.
        node->publishAtPoll();
        if (!(bool)fbAsking) {
            fbAsking = true;
            fbAskedAt = node->pollPublishes();
        }
        fbEverSent = true;
        if (!changedEvery) fbSetSentAt = (int32_t)now;   // changed-every keeps its slot
    }
    finish();
}

END_FUNCTION_BLOCK