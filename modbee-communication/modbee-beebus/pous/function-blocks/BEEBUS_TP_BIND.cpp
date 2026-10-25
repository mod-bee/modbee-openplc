(* Binds a whole STRUCT to the one a PEER serves (BEEBUS_TP_SERVE): the members
hold the owner's values, and a member the program changes is asked of the
owner, which decides. Whatever it decides, the member ends with its value.

NODE        which node. Unwired = the only one. The node block must be called
            first.
VALUE       the STRUCT, or ARRAY, declared the same as the owner's: member for
            member, in the same order, of the same types.
PEER        the node that serves it.
TOPIC_ID    the owner's TOPIC_ID.
PREFIX      the owner's PREFIX. Empty for none.
RELIABLE    TRUE for setpoints, settings and configuration: every change
            arrives, and one a lost frame took is sent again, as the current
            value, within a rotation or two. FALSE (LIVE, the default): best
            effort, newest wins, for live values.
DEADBAND    LIVE only: the owner sends a member again once it has moved this
            far. 0 for every change.

COUNT       how many members.
STATE       the worst member: BEEBUS_BIND_OFFLINE (the owner is not in the
            ring), BEEBUS_BIND_SYNCING (its values not here yet, also after
            it restarted), BEEBUS_BIND_FAILED, BEEBUS_BIND_REFUSED,
            BEEBUS_BIND_PENDING, BEEBUS_BIND_IN_SYNC.
            BEEBUS_BIND_OFFLINE, BEEBUS_BIND_SYNCING, BEEBUS_BIND_IN_SYNC,
            BEEBUS_BIND_PENDING, BEEBUS_BIND_REFUSED, BEEBUS_BIND_FAILED
IN_SYNC     every member holds the owner's value.
PENDING     a change is with the owner, waiting for its decision.
REFUSED     the owner kept another value for a member: the member now holds
            it. Until that member next changes, or the owner sends a value.
REFUSED_NAME   the first member refused, e.g. 'set.hiMm' (held).
REFUSED_INDEX  its position, from 1 (held).
FAILED      no decision came back for a change: the member holds the owner's
            last value.
AGE         how long since the oldest member last had a value from the owner.
NEW_VALUE   a value arrived from the owner since the last scan.
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

ONE BLOCK, BOTH WAYS. There is no subscribe-and-write pair, no copy-back, no
timer and no retry in the program: change a member and the protocol takes it to
the owner, waits for its decision, and puts the owner's value back in the
member. The protocol paces, repairs and times out by itself.

  set( NODE := node, VALUE := SET, PEER := 1, TOPIC_ID := 300, RELIABLE := TRUE );

Call it once a scan. One instance is one STRUCT: VALUE, PEER, TOPIC_ID, PREFIX,
RELIABLE and DEADBAND are taken on the first scan. *)

FUNCTION_BLOCK BEEBUS_TP_BIND
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    VALUE : ANY;
    PEER : BYTE;
    TOPIC_ID : UINT;
    PREFIX : STRING(16);
    RELIABLE : BOOL;
    DEADBAND : REAL;
  END_VAR
  VAR_OUTPUT
    COUNT : UINT;
    STATE : BEEBUS_TP_BIND_STATE;
    IN_SYNC : BOOL;
    PENDING : BOOL;
    REFUSED : BOOL;
    REFUSED_NAME : STRING(64);
    REFUSED_INDEX : UINT;
    FAILED : BOOL;
    AGE : TIME;
    NEW_VALUE : BOOL;
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
bool bb_planLeafInfo(void*, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset);
bool bb_planBind(void*, BeeBusAPI* node, uint8_t peer, uint16_t topicId, const char* prefix,
                 bool reliable, float deadband, char* err, size_t errCap);
void bb_planBindSync(void*);
void bb_planBindStatus(void*, BeeBusAPI* node, uint8_t* worst, uint32_t* pending,
                       uint32_t* refused, uint32_t* failed, uint32_t* firstRefused,
                       bool* allInSync);
void bb_planReceive(void*, BeeBusAPI* node, uint32_t* newCount, uint32_t* firstNew,
                    uint32_t* missed, uint8_t* worst, bool* allSeen, int32_t* oldestAgeMs);
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  COUNT = 0;
  STATE = BEEBUS_TP_BIND_STATE::BEEBUS_BIND_OFFLINE;
  IN_SYNC = false;
  PENDING = false;
  REFUSED = false;
  REFUSED_NAME = "";
  REFUSED_INDEX = 0;
  FAILED = false;
  NEW_VALUE = false;
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
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  // Bound once. A refusal is final until the PLC restarts.
  if (!(bool)isBound) {
    if ((bool)ERROR && STATUS == BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT) return;
    char why[96] = "";
    void* made = bb_planBuild(VALUE, false, why, sizeof(why));
    if (!made || !bb_planBind(made, node, (uint8_t)PEER, (uint16_t)TOPIC_ID, PREFIX.c_str(),
                              (bool)RELIABLE, (float)DEADBAND, why, sizeof(why))) {
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

  // A TIME, a DT or a DATE member goes through a copy in its wire form, both
  // ways: the owner's value into the member, the program's change into the
  // copy for the bind to send.
  bb_planBindSync(plan);

  uint8_t worst = (uint8_t)BeeBusBindState::Offline;
  uint32_t pending = 0, refused = 0, failed = 0, firstRefused = 0;
  bool allInSync = false;
  bb_planBindStatus(plan, node, &worst, &pending, &refused, &failed, &firstRefused, &allInSync);
  STATE = (BEEBUS_TP_BIND_STATE)(int32_t)worst;
  IN_SYNC = allInSync;
  PENDING = pending > 0;
  FAILED = failed > 0;
  const bool wasRefused = (bool)REFUSED;
  REFUSED = refused > 0;
  if (refused > 0 && (!wasRefused || (uint16_t)REFUSED_INDEX != (uint16_t)(firstRefused + 1))) {
    char name[64] = "";
    bb_planLeafInfo(plan, firstRefused, name, sizeof(name), nullptr);
    REFUSED_NAME = name;
    REFUSED_INDEX = (uint16_t)(firstRefused + 1);
  }

  uint32_t fresh = 0, firstNew = 0, missed = 0;
  uint8_t quality = 0;
  bool allSeen = false;
  int32_t oldest = 0;
  bb_planReceive(plan, node, &fresh, &firstNew, &missed, &quality, &allSeen, &oldest);
  NEW_VALUE = fresh > 0;
  AGE = bb_timeOf(oldest);

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
}

END_FUNCTION_BLOCK