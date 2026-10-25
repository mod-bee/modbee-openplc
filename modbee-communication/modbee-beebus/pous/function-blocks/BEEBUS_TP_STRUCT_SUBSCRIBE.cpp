(* A peer's STRUCT of topics, into a STRUCT of yours. One block, every member.

NODE        which node. Unwired = the only one.
VALUE       your STRUCT (or ARRAY), of the SAME TYPE as the one the peer
            publishes with BEEBUS_TP_STRUCT. Each member's value lands in the
            same member here. An ARRAY's own name need not match the peer's:
            PREFIX names it.
PEER        the node that owns the topics.
TOPIC_ID    the TOPIC_ID the peer gave its BEEBUS_TP_STRUCT.
PREFIX      the PREFIX the peer gave it. Empty for none.
DEADBAND    send a member again only once it has moved this far. 0 for every
            change, which is right for a STRUCT of mixed members: a BOOL counts
            as 1, so a deadband of 1 or more would hold back every BOOL.
PERIOD      ask for every member at least this often, moved or not. T#0s for
            never.
RELIABLE    FALSE (LIVE, the default): best effort, newest wins - for
            levels, flows and speeds. TRUE for setpoints, settings and
            configuration: every change of every member arrives, and one a
            lost frame took is sent again, as the current value, within a
            rotation or two. DEADBAND does not apply. Changing it re-asks.

COUNT       how many members (topics) the STRUCT holds.
QUALITY     the worst member: BEEBUS_TP_BAD if any is bad, then
            BEEBUS_TP_UNCERTAIN, then BEEBUS_TP_UNKNOWN if any has never
            arrived, and BEEBUS_TP_GOOD only when every member is good.
            BEEBUS_TP_UNKNOWN, BEEBUS_TP_GOOD, BEEBUS_TP_UNCERTAIN, BEEBUS_TP_BAD
SEEN        every member has arrived at least once.
AGE         how long since the OLDEST member's last value arrived.
NEW_VALUE   one scan: a value arrived since the last scan.
NEW_COUNT   how many members arrived on that scan.
NEW_NAME    which member, e.g. 'hmi.systemMode'. The first one when several
            arrived together. Held until the next arrival.
NEW_INDEX   its position, from 1, every array element and nested member one
            position. Held until the next arrival.
MISSED      publishes the sequence says never arrived, across every member,
            since the program started.
ERROR       no such node, the STRUCT was refused, or a subscription was.
STATUS      why. BEEBUS_OK when fine.
            BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
            BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
            BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
            BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
            BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
            BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL
LAST_ERROR  which member, and what is wrong with it.

---

The other half of BEEBUS_TP_STRUCT. The peer publishes its STRUCT; this block
binds every member to the same member of yours and asks for a stream of each:

  // on the PLC, node 1
  sts( NODE := node, VALUE := STS, TOPIC_ID := 100 );

  // on the display, node 2, with the same TYPE
  sts( NODE := node, VALUE := STS, PEER := 1, TOPIC_ID := 100 );

USE THE SAME TYPE ON BOTH SIDES. Topics travel by id, and the ids come from
the order of the members, so a member added on one side and not the other
shifts every member after it. Keep the TYPE in one place - a shared library,
or one .st file both projects import.

MEMBERS ARRIVE ONE BY ONE. Several members the peer changed on one scan may
land over two or three scans here; NEW_COUNT says how many came this scan.
Act on the values, not on the arrival of one of them.

THIS IS ALSO HOW A COMMAND IS TAKEN. Nothing writes into another node's
storage: the commanding node owns a STRUCT of commands and publishes it, this
node subscribes and acts on what arrives. NEW_NAME says which command moved.

Each member is subscribed on its own, as many a scan as the node's queue
takes, and re-subscribed by the protocol whenever the peer rejoins the ring,
so a peer that was absent at start-up or has rebooted needs nothing from the
program. A STRING member arrives whole, cut to the length your member holds.

Names, ids and types follow BEEBUS_TP_STRUCT exactly; see it for the table. *)

FUNCTION_BLOCK BEEBUS_TP_STRUCT_SUBSCRIBE
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    VALUE : ANY;
    PEER : BYTE;
    TOPIC_ID : UINT;
    PREFIX : STRING(16);
    DEADBAND : REAL;
    PERIOD : TIME;
    RELIABLE : BOOL;
  END_VAR
  VAR_OUTPUT
    COUNT : UINT;
    QUALITY : BEEBUS_TP_QUALITY;
    SEEN : BOOL;
    AGE : TIME;
    NEW_VALUE : BOOL;
    NEW_COUNT : UINT;
    NEW_NAME : STRING(64);
    NEW_INDEX : UINT;
    MISSED : UDINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    LAST_ERROR : STRING(80);
  END_VAR
  VAR
    isBound : BOOL;
    fbPlan : __XWORD;
    fbAll : BOOL;
    askedDeadband : REAL;
    askedInterval : DINT;
    askedReliable : BOOL;
  END_VAR
#include <BeeBusAPI.h>

// Defined in BEEBUS_NODE, which every project has and which sorts before this
// block: every C++ POU lands in one translation unit in filename order.
int32_t bb_millisOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds);
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
uint32_t bb_planLeaves(void*);
bool bb_planMoved(void*, const strucpp::IEC_ANY& v);
bool bb_planLeafInfo(void*, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset);
bool bb_planBindTopics(void*, BeeBusAPI* node, bool remote, uint8_t peer,
                       uint16_t topicId, const char* prefix, char* err, size_t errCap);
uint32_t bb_planSubscribe(void*, BeeBusAPI* node, float deadband, int32_t intervalMs,
                          bool again, BeeBusResult* last, bool reliable);
void bb_planReceive(void*, BeeBusAPI* node, uint32_t* newCount, uint32_t* firstNew,
                    uint32_t* missed, uint8_t* worst, bool* allSeen, int32_t* oldestAgeMs);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  COUNT = 0;
  QUALITY = BEEBUS_TP_QUALITY::BEEBUS_TP_UNKNOWN;
  SEEN = false;
  AGE = bb_timeOf(0);
  NEW_VALUE = false;
  NEW_COUNT = 0;
  NEW_NAME = "";
  NEW_INDEX = 0;
  MISSED = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
  isBound = false;
  fbPlan = (strucpp::XWORD_t)0;
  fbAll = false;
  askedDeadband = 0.0f;
  askedInterval = 0;
  askedReliable = false;
}

void loop()
{
    if (!bb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see BEEBUS_ARDUINO
        ERROR = true;
        STATUS = BEEBUS_RESULT::BEEBUS_WRONG_TASK;
        return;
    }
  BeeBusAPI* node = (BeeBusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.API;
  if (!node) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  if (!(bool)isBound) {
    if ((bool)ERROR && STATUS == BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT) return;
    char why[96] = "";
    void* made = bb_planBuild(VALUE, false, why, sizeof(why));
    if (!made || !bb_planBindTopics(made, node, true, (uint8_t)PEER, (uint16_t)TOPIC_ID,
                                    PREFIX.c_str(), why, sizeof(why))) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      LAST_ERROR = why;
      return;
    }
    fbPlan = (strucpp::XWORD_t)(uintptr_t)made;
    COUNT = (uint16_t)bb_planLeaves(made);
    isBound = true;
  }

  void* plan = (void*)(uintptr_t)(strucpp::XWORD_t)fbPlan;

  if (bb_planMoved(plan, VALUE)) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    LAST_ERROR = "VALUE moved: wire the same variable every scan";
    return;
  }

  // Asked for member by member until all are, a queue's worth a scan, and
  // again for every member when the terms on the pins change. The protocol
  // holds each subscription until the peer is in the ring and re-issues it
  // when the peer restarts.
  const float deadband = (float)DEADBAND;
  const int32_t interval = bb_millisOf(PERIOD);
  const bool reliable = (bool)RELIABLE;
  const bool again = (bool)fbAll && ((float)askedDeadband != deadband ||
                                     (int32_t)askedInterval != interval ||
                                     (bool)askedReliable != reliable);
  if (!(bool)fbAll || again) {
    BeeBusResult last = BeeBusResult::Immediate;
    const uint32_t pending =
        bb_planSubscribe(plan, node, deadband, interval, again, &last, reliable);
    askedDeadband = deadband;
    askedInterval = interval;
    askedReliable = reliable;
    fbAll = (pending == 0);
    if (pending != 0 && last != BeeBusResult::QueueFull) {
      ERROR = true;
      STATUS = (BEEBUS_RESULT)(int32_t)last;
      LAST_ERROR = "a subscription was refused";
    } else {
      ERROR = false;
      STATUS = BEEBUS_RESULT::BEEBUS_OK;
      LAST_ERROR = "";
    }
  }

  uint32_t fresh = 0, first = 0, gaps = 0;
  uint8_t worst = 0;
  bool all = false;
  int32_t oldest = 0;
  bb_planReceive(plan, node, &fresh, &first, &gaps, &worst, &all, &oldest);

  QUALITY = (BEEBUS_TP_QUALITY)worst;
  SEEN = all;
  AGE = bb_timeOf(oldest);
  NEW_VALUE = (fresh != 0);
  NEW_COUNT = (uint16_t)fresh;
  if (fresh != 0) {
    char name[65] = "";
    bb_planLeafInfo(plan, first, name, sizeof(name), nullptr);
    NEW_NAME = name;
    NEW_INDEX = (uint16_t)(first + 1);
  }
  // A running total, so a gap three scans ago is still the useful number.
  MISSED = (uint32_t)MISSED + gaps;
}

END_FUNCTION_BLOCK