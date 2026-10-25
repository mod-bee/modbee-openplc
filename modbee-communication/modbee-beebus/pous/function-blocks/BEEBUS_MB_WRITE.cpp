(* Writes to a peer, on a rising edge of REQ.

NODE       which node. Unwired = the only one.
REQ        rising edge writes.
PEER       the node to write to.
TABLE      which of the peer's lists. BEEBUS_MB_COIL or BEEBUS_MB_HOLDING_REG.
           BEEBUS_MB_COIL, BEEBUS_MB_HOLDING_REG, BEEBUS_MB_DISCRETE_INPUT, BEEBUS_MB_INPUT_REG
ADDRESS    the first address on that node.
CONFIRMED  wait for the peer to acknowledge. Unconfirmed is one message and no
           answer, which is what a fast cyclic write wants.
LENGTH     how many values to move, counting array elements and STRUCT members
           one each. 0 uses all of them. Ignored for a single value.
VALUE      the variable to send: a single value, a fixed-bounds array or a
           STRUCT, laid out exactly as BEEBUS_MB_MAP lays it out.

BUSY   the request is outstanding.
DONE   one scan, when it landed.
ERROR  it did not.
STATUS why. BEEBUS_OK when fine.
       BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
       BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
       BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
       BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
       BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
       BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

One block for a single value or a whole range, and for bits or registers.
Pass the variable itself; TABLE says which list on the peer to write:

  BEEBUS_MB_WRITE( NODE := h, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
            VALUE := mySetpoint );

  BEEBUS_MB_WRITE( NODE := h, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 100,
            VALUE := myArray );

  BEEBUS_MB_WRITE( NODE := h, PEER := 2, TABLE := BEEBUS_MB_COIL, ADDRESS := 0,
            VALUE := myCoils );

A range is one request rather than one per address. Each member takes its own
width - a REAL two registers, high word first, a BOOL one register (0 or 1), a
STRING(n) n/2 + 1 - so writing one setting of a peer's STRUCT means writing a
variable of that member's type at that member's address, and writing the whole
STRUCT is one request. The values are taken when REQ rises. One request carries
up to 123 registers. A STRING on its own costs the length of its text, not the
size of the field it lands in.

A peer refuses a value its member cannot hold (300 into a USINT): the write
ends in ERROR, and a write of several values is refused whole.

An array must be declared with fixed bounds. A generic pin takes a variable,
and ARRAY [*] is not one — it is a view, and views ride in-out pins only.

Only two of Modbus's four lists can be written: BEEBUS_MB_COIL and BEEBUS_MB_HOLDING_REG.
Naming BEEBUS_MB_DISCRETE_INPUT or BEEBUS_MB_INPUT_REG is BEEBUS_INVALID_ARGUMENT — there is
no function code for it — and so is a value that does not suit the list: in
BEEBUS_MB_COIL every member must be a BOOL. *)

FUNCTION_BLOCK BEEBUS_MB_WRITE
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    PEER : BYTE;
    TABLE : BEEBUS_MB_TABLE;
    ADDRESS : UINT;
    CONFIRMED : BOOL;
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
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has.
uint8_t bb_wireTypeOfClass(uint32_t typeClass);
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
void bb_planFree(void*);
BeeBusResult bb_planWritePeer(void*, BeeBusAPI* node, uint8_t peer, BeeBusRegisterType table,
                              uint16_t address, uint32_t leaves, BeeBusDelivery delivery);

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
  const uint16_t address = (uint16_t)ADDRESS;

  // Only two of the four tables have a write function code.
  if (!bb_tableIsWritable(table)) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    return;
  }

  const BeeBusDelivery delivery =
      (bool)CONFIRMED ? BeeBusDelivery::Confirmed : BeeBusDelivery::Unconfirmed;
  const uint8_t wire = bb_wireTypeOfClass((uint32_t)VALUE.ELEMCLASS);
  BeeBusResult result = BeeBusResult::InvalidArgument;

  if (wire == BEEBUS_T_STRING && VALUE.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING) {
    // A string on its own is one object rather than a range, and costs the
    // length of the text rather than the size of the field it lands in.
    if (table == MB_HOLDING_REGISTER) {
      result = node->writeString((uint8_t)PEER, address, (const char*)VALUE.PVALUE, delivery);
    }
  } else {
    // Everything else - a value, an array, a STRUCT - is laid out by the same
    // rules BEEBUS_MB_MAP uses: a REAL is two registers high word first, a
    // BOOL in a register is 0 or 1, a STRING(n) is n/2 + 1 registers. The
    // values are packed when REQ rises, so what goes is what VALUE held then.
    // Laid out afresh on each request: requests are edges, not scans, and the
    // table (a coil list takes only BOOLs) or the variable may have changed.
    void* plan = (void*)(uintptr_t)(strucpp::XWORD_t)fbPlan;
    bb_planFree(plan);
    char why[96];
    plan = bb_planBuild(VALUE, bb_tableIsBits(table), why, sizeof(why));
    fbPlan = (strucpp::XWORD_t)(uintptr_t)plan;
    if (plan) {
      result = bb_planWritePeer(plan, node, (uint8_t)PEER, table, address,
                                (uint32_t)(uint16_t)LENGTH, delivery);
    }
  }

  if (!bb_accepted(result) && result != BeeBusResult::Duplicate) {
    ERROR = true;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }

  if (result == BeeBusResult::Immediate) {
    DONE = true;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }

  pending = true;
  BUSY = true;
  STATUS = (BEEBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK