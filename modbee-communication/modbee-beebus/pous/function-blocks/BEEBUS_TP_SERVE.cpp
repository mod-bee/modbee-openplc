(* Serves a whole STRUCT: one topic per member, owned by this node, which decides
every change a peer asks for. The owner side of a bind (BEEBUS_TP_BIND).

NODE        which node. Unwired = the only one. The node block must be called
            first.
VALUE       the STRUCT, or an ARRAY of STRUCTs or of simple values. Every
            member becomes a topic, as BEEBUS_TP_STRUCT does.
TOPIC_ID    the first member's id; each member after it the next, in
            declaration order. 1..32767.
PREFIX      put before every member's name. Empty for none.
WRITABLE    peers may change the members (settings, commands). FALSE: they
            are served read-only and a change is refused READ_ONLY.
COMMAND     every member is a command: each write is one event for the
            program, taken once and answered DONE (ACCEPTED). FALSE: a value
            the program keeps.
PULSE       a BOOL member written TRUE goes back to FALSE this long after (a
            momentary command). T#0s: kept as written.
SETTLE      a change is answered after the program has run one scan with it,
            plus this long. T#0s: one scan.
DEPTH       each member held in a ring of this many while the network is
            away, sent oldest first when it is back. 0 for none. 0..127.

BOUND       every member is served.
COUNT       how many members (topics).
CHANGED     one scan, when peers' changes were taken into the STRUCT.
CHANGED_COUNT  how many members that scan (held).
CHANGED_NAME   the first of them (held), e.g. 'set.hiMm'.
CHANGED_INDEX  its position, from 1, in declaration order (held).
CHANGED_BY  the node that changed it (held).
REFUSED_COUNT  changes the program did not keep as asked (answered CHANGED),
            running total.
LOST        changes dropped, running total: a member changed more than 4
            times between two scans keeps the 4 newest.
ERROR       no such node, or the STRUCT was refused.
STATUS      why. BEEBUS_OK when fine.
            BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
            BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
            BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
            BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
            BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
            BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL
LAST_ERROR  which member, and what is wrong with it.

---

THE PROGRAM DECIDES, the blocks hold the logic. A change a peer asks for is put
into the member at the start of this block's scan; the program runs with it;
after that scan (and SETTLE) the member is read back. Still holding what was
asked: ACCEPTED. Holding something else, because a block refused it and put
its own value back, or clamped it: CHANGED, with the value kept, which the
asking panel shows. No refusal logic or copy-back is written for it.

Every bind of these members (BEEBUS_TP_BIND, a panel's bind in C++) ends with
the value this STRUCT holds, whatever was decided. Settings and setpoints are
bound RELIABLE by the binder, so no lost frame can leave one wrong.

  set( NODE := node, VALUE := SET, TOPIC_ID := 300, WRITABLE := TRUE );
  cmd( NODE := node, VALUE := CMD, TOPIC_ID := 400, WRITABLE := TRUE,
       COMMAND := TRUE, PULSE := T#500ms );

Call it once a scan, before the blocks that use the STRUCT. One instance is one
STRUCT: VALUE, TOPIC_ID, PREFIX, WRITABLE, COMMAND and DEPTH are taken on the
first scan; PULSE and SETTLE may change. *)

FUNCTION_BLOCK BEEBUS_TP_SERVE
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    VALUE : ANY;
    TOPIC_ID : UINT;
    PREFIX : STRING(16);
    WRITABLE : BOOL;
    COMMAND : BOOL;
    PULSE : TIME;
    SETTLE : TIME;
    DEPTH : USINT;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    COUNT : UINT;
    CHANGED : BOOL;
    CHANGED_COUNT : UINT;
    CHANGED_NAME : STRING(64);
    CHANGED_INDEX : UINT;
    CHANGED_BY : BYTE;
    REFUSED_COUNT : UDINT;
    LOST : UDINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    LAST_ERROR : STRING(80);
  END_VAR
  VAR
    isBound : BOOL;
    fbPlan : __XWORD;
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has.
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
uint32_t bb_planLeaves(void*);
bool bb_planMoved(void*, const strucpp::IEC_ANY& v);
bool bb_planBindTopicsEx(void*, BeeBusAPI* node, bool remote, uint8_t peer,
                         uint16_t topicId, const char* prefix, bool writable,
                         char* err, size_t errCap);
bool bb_planQueueWrites(void*, BeeBusAPI* node, char* err, size_t errCap);
uint32_t bb_planTakeWrites(void*, uint32_t pulseMs, uint32_t* firstLeaf, uint8_t* by,
                           uint32_t* lost);
bool bb_planLeafInfo(void*, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset);
int32_t bb_millisOf(const strucpp::IEC_TIME& t);
void bb_planPublishSync(void*);
void bb_planServeTerms(void*, uint32_t settleMs, bool command);
uint32_t bb_planTakeRefused(void*);
bool bb_planBuffer(void*, BeeBusAPI* node, uint8_t depth, char* err, size_t errCap);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  BOUND = false;
  COUNT = 0;
  CHANGED = false;
  CHANGED_COUNT = 0;
  CHANGED_NAME = "";
  CHANGED_INDEX = 0;
  CHANGED_BY = 0;
  REFUSED_COUNT = 0;
  LOST = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
  isBound = false;
  fbPlan = (strucpp::XWORD_t)0;
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
    BOUND = false;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  // Served once. A refusal is final until the PLC restarts, and LAST_ERROR
  // names the member.
  if (!(bool)isBound) {
    if ((bool)ERROR && STATUS == BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT) return;
    char why[96] = "";
    void* made = bb_planBuild(VALUE, false, why, sizeof(why));
    const bool writable = (bool)WRITABLE;
    const uint8_t depth = (uint8_t)DEPTH;
    if (!made || !bb_planBindTopicsEx(made, node, false, 0, (uint16_t)TOPIC_ID,
                                      PREFIX.c_str(), writable, why, sizeof(why)) ||
        (writable && !bb_planQueueWrites(made, node, why, sizeof(why))) ||
        !bb_planBuffer(made, node, depth > 127 ? 127 : depth, why, sizeof(why))) {
      BOUND = false;
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
  BOUND = true;

  if (bb_planMoved(plan, VALUE)) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    LAST_ERROR = "VALUE moved: wire the same variable every scan";
    return;
  }

  // Peers' changes waiting in the node's queue: one per member, oldest first,
  // into the variable. Each is answered once the program has run with it.
  CHANGED = false;
  uint32_t first = 0, lost = 0;
  uint8_t by = 0;
  const int32_t pulse = bb_millisOf(PULSE);
  const int32_t settle = bb_millisOf(SETTLE);
  bb_planServeTerms(plan, (uint32_t)(settle > 0 ? settle : 0), (bool)COMMAND);
  const uint32_t taken = bb_planTakeWrites(plan, (uint32_t)(pulse > 0 ? pulse : 0), &first, &by, &lost);
  if (lost > 0) LOST = (uint32_t)LOST + lost;
  if (taken > 0) {
    char name[64] = "";
    bb_planLeafInfo(plan, first, name, sizeof(name), nullptr);
    CHANGED = true;
    CHANGED_COUNT = (uint16_t)taken;
    CHANGED_NAME = name;
    CHANGED_INDEX = (uint16_t)(first + 1);
    CHANGED_BY = by;
  }
  const uint32_t refused = bb_planTakeRefused(plan);
  if (refused > 0) REFUSED_COUNT = (uint32_t)REFUSED_COUNT + refused;

  // A TIME, a DT or a STRING goes through a copy in its wire form, brought up
  // to date here, so the node serves what the program holds as of this scan.
  bb_planPublishSync(plan);

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
}

END_FUNCTION_BLOCK