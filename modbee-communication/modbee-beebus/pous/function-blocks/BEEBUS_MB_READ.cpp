(* Reads from a peer, on a rising edge of REQ.

NODE     which node. Unwired = the only one.
REQ      rising edge reads.
PEER     the node to read from.
TABLE    which of Modbus's four lists.
         BEEBUS_MB_COIL, BEEBUS_MB_HOLDING_REG, BEEBUS_MB_DISCRETE_INPUT, BEEBUS_MB_INPUT_REG
ADDRESS  the first address on that node.
LENGTH   how many values to move, counting array elements and STRUCT members
         one each. 0 uses all of them; a smaller figure fills the first that
         many. Larger is BEEBUS_INVALID_ARGUMENT rather than a read off the
         end. Ignored for a single value.
VALUE    the variable to read into: a single value, a fixed-bounds array or a
         STRUCT, laid out exactly as BEEBUS_MB_MAP lays it out.

BUSY   the request is outstanding.
DONE   one scan, when the answers arrived.
ERROR  they did not.
STATUS why. BEEBUS_OK when fine.
       BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
       BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
       BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
       BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
       BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
       BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

One block for a single value or a whole range, and for bits or registers. What
was passed decides which:

  BEEBUS_MB_READ( NODE := h, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
           VALUE := myWord );

  BEEBUS_MB_READ( NODE := h, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 100,
           VALUE := myArray );

  BEEBUS_MB_READ( NODE := h, PEER := 2, TABLE := BEEBUS_MB_COIL, ADDRESS := 0,
           VALUE := myCoils );

A range is one request rather than one per address, which is the difference
between a scan and a minute when there are a hundred of them. The answers land
together, on the scan DONE is set, never half a value at a time.

Each member takes its own width - a REAL two registers, high word first, a
STRING(n) n/2 + 1 - so a STRUCT read here from a peer that maps the same STRUCT
with BEEBUS_MB_MAP arrives member for member. A register holding a number its
member cannot (300 for a USINT) leaves that member as it was and ends the read
with BEEBUS_TYPE_MISMATCH. One request carries up to 125 registers.

A register is sixteen raw bits, so a register array is WORD rather than INT.
WORD is what a program can mask, shift and address a bit of — myWord.6 for bit
6, and AND / OR / SHL are all typed ANY_BIT, which INT is not. Use
WORD_TO_INT where you want it as a signed number. *)

FUNCTION_BLOCK BEEBUS_MB_READ
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    PEER : BYTE;
    TABLE : BEEBUS_MB_TABLE;
    ADDRESS : UINT;
    LENGTH : UINT;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
    lastReq : BOOL;
    pending : BOOL;
    fbPlan : __XWORD;
    fbBits : BOOL;
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has.
uint8_t bb_wireTypeOfClass(uint32_t typeClass);
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
bool bb_planMoved(void*, const strucpp::IEC_ANY& v);
void bb_planFree(void*);
BeeBusResult bb_planReadPeer(void*, BeeBusAPI* node, uint8_t peer, BeeBusRegisterType table,
                             uint16_t address, uint32_t leaves);
bool bb_planReadDone(void*, bool bits);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  BUSY = false;
  DONE = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  lastReq = false;
  pending = false;
  fbPlan = (strucpp::XWORD_t)0;
  fbBits = false;
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
    BUSY = false;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  void* plan = (void*)(uintptr_t)(strucpp::XWORD_t)fbPlan;

  if ((bool)pending) {
    BeeBusResult outcome = BeeBusResult::Immediate;
    const BeeBusRequestState state =
        node->requestState((uint8_t)PEER, (uint16_t)ADDRESS, outcome);
    if (state == BeeBusRequestState::Pending) {
      BUSY = true;
      DONE = false;
      ERROR = false;
      return;
    }
    pending = false;
    BUSY = false;
    DONE = (state == BeeBusRequestState::Done);
    ERROR = (state == BeeBusRequestState::Failed);
    STATUS = (BEEBUS_RESULT)(int32_t)outcome;
    // The answers arrive in the block's own buffer and are unpacked here, in
    // the scan, so the program never sees half a value. A register holding a
    // number its member cannot (300 for a USINT) leaves that member as it was.
    if ((bool)DONE && plan && !bb_planReadDone(plan, (bool)fbBits)) {
      DONE = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_TYPE_MISMATCH;
    }
    return;
  }

  // DONE and ERROR are one-scan edges: set on the scan the operation finished
  // and cleared on the next, so a caller counting them counts operations.
  BUSY = false;
  DONE = false;
  ERROR = false;

  const bool rose = (bool)REQ && !(bool)lastReq;
  lastReq = (bool)REQ;
  if (!rose) return;

  const BeeBusRegisterType table = (BeeBusRegisterType)(BEEBUS_MB_TABLE)TABLE;
  const uint8_t wire = bb_wireTypeOfClass((uint32_t)VALUE.ELEMCLASS);
  BeeBusResult result = BeeBusResult::InvalidArgument;

  if (wire == BEEBUS_T_STRING && VALUE.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING) {
    // A string on its own is one object rather than a range, and reads only
    // as much as the field holds.
    if (bb_tableIsBits(table)) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
    result = (table == MB_HOLDING_REGISTER)
        ? node->readString((uint8_t)PEER, (uint16_t)ADDRESS,
                           (char*)VALUE.PVALUE, (uint16_t)VALUE.DISIZE)
        : node->readInputString((uint8_t)PEER, (uint16_t)ADDRESS,
                                (char*)VALUE.PVALUE, (uint16_t)VALUE.DISIZE);
    if (plan) { bb_planFree(plan); fbPlan = (strucpp::XWORD_t)0; plan = nullptr; }
  } else {
    // Everything else - a value, an array, a STRUCT - is laid out by the same
    // rules BEEBUS_MB_MAP uses, so a STRUCT read here from a peer that mapped
    // the same STRUCT lands member for member.
    if (!plan || bb_planMoved(plan, VALUE) || (bool)fbBits != bb_tableIsBits(table)) {
      bb_planFree(plan);
      char why[96];
      plan = bb_planBuild(VALUE, bb_tableIsBits(table), why, sizeof(why));
      fbPlan = (strucpp::XWORD_t)(uintptr_t)plan;
      fbBits = bb_tableIsBits(table);
    }
    if (plan) {
      result = bb_planReadPeer(plan, node, (uint8_t)PEER, table, (uint16_t)ADDRESS,
                               (uint32_t)(uint16_t)LENGTH);
    }
  }

  if (!bb_accepted(result) && result != BeeBusResult::Duplicate) {
    ERROR = true;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }

  if (result == BeeBusResult::Immediate) {
    // A local address answers in place.
    DONE = true;
    if (plan && !bb_planReadDone(plan, (bool)fbBits)) {
      DONE = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_TYPE_MISMATCH;
      return;
    }
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }

  pending = true;
  BUSY = true;
  STATUS = (BEEBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK