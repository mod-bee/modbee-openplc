(* Puts your variables at Modbus addresses, so peers can reach them. A single
value, an array, or a whole STRUCT.

NODE            which node. Unwired = the only one.
TABLE           which list.
                BEEBUS_MB_COIL, BEEBUS_MB_HOLDING_REG, BEEBUS_MB_DISCRETE_INPUT, BEEBUS_MB_INPUT_REG
ADDRESS         the first address.
ON_LOSS         what happens to a writable address when the peer that was
                driving it goes quiet. Only a single number has a safe state
                to set.
                BEEBUS_MB_HOLD_LAST_VALUE, BEEBUS_MB_RESET_TO_VALUE
SAFE_VALUE      the value BEEBUS_MB_RESET_TO_VALUE goes to, in the variable's
                own type: 5 on a REAL is 5.0.
VALUE           the variable to bind: a single value, a fixed-bounds array or
                a STRUCT.

BOUND           the addresses are live.
COUNT           how many addresses were taken (registers, or coils).
WRITTEN         one scan, when a peer wrote any of them.
WRITTEN_NAME    which member, e.g. 'levelHiMm' or 'spare[3]'. The first one
                when a write covered several. Held until the next write.
WRITTEN_INDEX   its position, from 1, in declaration order: every array
                element and nested member one position. Held.
WRITTEN_ADDRESS its first address. Held.
WRITTEN_COUNT   how many members that write covered. Held.
SAFE_APPLIED    one scan, when the safe state was applied.
ERROR           why not.
STATUS          why. BEEBUS_OK when fine.
                BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
                BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
                BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED,
                BEEBUS_DUPLICATE, BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT,
                BEEBUS_NODE_LOST, BEEBUS_SUPERSEDED, BEEBUS_CANCELLED,
                BEEBUS_REFUSED, BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED,
                BEEBUS_BUFFER_FULL
LAST_ERROR      which member, and what is wrong with it.

---

One block for a single value, a range, or a whole STRUCT, and for bits or
registers. Pass the variable itself; TABLE says which list it goes in:

  BEEBUS_MB_MAP( NODE := h, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
          VALUE := mySpeed );

  BEEBUS_MB_MAP( NODE := h, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 100,
          VALUE := aTrend );

  BEEBUS_MB_MAP( NODE := h, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 0,
          VALUE := CFG );

There is no request pin. Once bound the variable IS the register: a peer
reading gets what it holds now, and a peer writing changes it.

HOW A VALUE IS LAID OUT, from ADDRESS, one member after the other in
declaration order:

  BOOL                          1 register, 0 or 1 (a write of any other
                                number is TRUE)
  SINT, USINT, BYTE             1 register. A write the type cannot hold
                                (300 into a USINT) is refused, not cut.
  INT, UINT, WORD               1 register
  DINT, UDINT, DWORD            2 registers, HIGH word first
  LINT, ULINT, LWORD            4 registers, high word first
  REAL                          2 registers, high word first, IEEE-754
  LREAL                         4 registers, high word first, IEEE-754
  TIME, TOD                     2 registers: DINT milliseconds
  LTIME                         4 registers: LINT nanoseconds
  DT, DATE                      2 registers: UDINT seconds since 1970-01-01
  STRING(n)                     n/2 + 1 registers: two characters to a
                                register, first one in the high byte, then
                                the terminator. STRING(64) takes 33.
  a nested STRUCT               its members, in place
  an array                      its elements, in place, first one first

High word first is what a Modbus master calls "ABCD", "big-endian" or "high
word first". A 32-bit value takes both its registers in one write (function
16), a 64-bit one all four; a write of fewer changes only those words.

In a coil or discrete-input table every member must be a BOOL, one address
each. WSTRING is refused: a value quietly cut down would be wrong.

A REFUSED VARIABLE IS REFUSED WHOLE, never skipped, because a missing member
would move every address after it. LAST_ERROR names the member.

A STRUCT OF SETTINGS is what this is for. The HMI writes straight into it;
WRITTEN says a write happened and WRITTEN_NAME says which setting, so the
program can check it and put the old value back if it is out of range:

  cfgMap( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 0,
          VALUE := CFG );
  IF cfgMap.WRITTEN AND CFG.levelLoMm >= CFG.levelHiMm THEN
    CFG.levelLoMm := levelLoInUse;      // refused: keep the old one
  END_IF;

Add new members at the END of the STRUCT: a member added in the middle moves
the address of every member after it, and the HMI has to be told.
The whole address table can be generated from the .st file that declares the
STRUCT, as Markdown and as JSON for an HMI's firmware.

An array must be declared with fixed bounds. A generic pin takes a variable,
and ARRAY [*] is not one. `aTrend : ARRAY[0..99] OF WORD` at ADDRESS 100
becomes addresses 100..199, whatever the lower bound. Members are named by
position from 1: aTrend[1] is the first element.

ONE INSTANCE IS ONE MAPPING. TABLE, ADDRESS and VALUE are taken on the first
scan the node is there; changing them later does nothing. Two separate ranges
are two instances. Wire the same variable every scan.

TABLE says which of Modbus's four lists the variables go in. They are separate
numbered lists, so address 40 in one is a different thing from address 40 in
another:

  BEEBUS_MB_COIL            on/off,  a peer may write it     FC 1, 5, 15
  BEEBUS_MB_DISCRETE_INPUT  on/off,  read only               FC 2
  BEEBUS_MB_HOLDING_REG     16 bits, a peer may write it     FC 3, 6, 16
  BEEBUS_MB_INPUT_REG       16 bits, read only               FC 4 *)

FUNCTION_BLOCK BEEBUS_MB_MAP
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    TABLE : BEEBUS_MB_TABLE;
    ADDRESS : UINT;
    ON_LOSS : BEEBUS_MB_FAILSAFE;
    SAFE_VALUE : DINT;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    COUNT : UINT;
    WRITTEN : BOOL;
    SAFE_APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    WRITTEN_NAME : STRING(64);
    WRITTEN_INDEX : UINT;
    WRITTEN_ADDRESS : UINT;
    WRITTEN_COUNT : UINT;
    LAST_ERROR : STRING(80);
  END_VAR
  VAR
    isBound : BOOL;
    wireType : BYTE;
    storage : __XWORD;
    seenWrites : UINT;
    seenFailsafe : UINT;
    fbPlan : __XWORD;
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has. Every C++ POU
// lands in one translation unit in filename order, and this one sorts first,
// so the engine is reached through declarations.
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap);
uint32_t bb_planLeaves(void*);
uint32_t bb_planRegisters(void*);
bool bb_planMoved(void*, const strucpp::IEC_ANY& v);
bool bb_planLeafInfo(void*, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset);
bool bb_planSingle(void*, uint8_t* wire);
bool bb_planBindRegisters(void*, BeeBusAPI* node, BeeBusRegisterType table,
                          uint16_t address, char* err, size_t errCap);
uint16_t bb_planServe(void*, BeeBusAPI* node, uint32_t* firstLeaf);

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  BOUND = false;
  COUNT = 0;
  WRITTEN = false;
  WRITTEN_NAME = "";
  WRITTEN_INDEX = 0;
  WRITTEN_ADDRESS = 0;
  WRITTEN_COUNT = 0;
  SAFE_APPLIED = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
  isBound = false;
  storage = (strucpp::XWORD_t)0;
  fbPlan = (strucpp::XWORD_t)0;
  seenFailsafe = 0;
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

  const BeeBusRegisterType table = (BeeBusRegisterType)(BEEBUS_MB_TABLE)TABLE;

  // Bound once, on the first scan the node is there; a refusal is final, and
  // LAST_ERROR says which member and why.
  if (!(bool)isBound) {
    if ((bool)ERROR && STATUS == BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT) return;

    char why[96] = "";
    void* made = bb_planBuild(VALUE, bb_tableIsBits(table), why, sizeof(why));
    if (!made || !bb_planBindRegisters(made, node, table, (uint16_t)ADDRESS, why, sizeof(why))) {
      // A plan that would not bind is not freed: an instance binds once, and
      // the refusal stands until the PLC restarts.
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      LAST_ERROR = why;
      return;
    }

    // The safe state is per address, and only a writable table has one to set.
    // Only a single number has one value to go to: a STRUCT, an array or a
    // string is left holding what it held.
    uint8_t wire = 0;
    const bool resetOnLoss = ((BEEBUS_MB_FAILSAFE)ON_LOSS == BEEBUS_MB_FAILSAFE::BEEBUS_MB_RESET_TO_VALUE);
    if (resetOnLoss && bb_tableIsWritable(table) && bb_planSingle(made, &wire)) {
      const int32_t safe = (int32_t)SAFE_VALUE;
      if (bb_tableIsBits(table)) {
        node->setCoilFailsafe((uint16_t)ADDRESS, BeeBusFailsafe::ResetToValue, safe != 0);
      } else {
        // The safe value in the member's own type, then its register image:
        // SAFE_VALUE := 5 on a REAL is 5.0, not the bit pattern of 5.
        uint8_t image[8] = {0, 0, 0, 0, 0, 0, 0, 0};
        switch (wire) {
          case BEEBUS_T_F64: { const double f = (double)safe; memcpy(image, &f, 8); break; }
          case BEEBUS_T_I64:
          case BEEBUS_T_U64: { const int64_t s = (int64_t)safe; memcpy(image, &s, 8); break; }
          case BEEBUS_T_F32: { const float f = (float)safe; memcpy(image, &f, 4); break; }
          case BEEBUS_T_I32:
          case BEEBUS_T_U32: memcpy(image, &safe, 4); break;
          case BEEBUS_T_I16:
          case BEEBUS_T_U16: { const int16_t s = (int16_t)safe; memcpy(image, &s, 2); break; }
          default: { const int8_t s = (int8_t)safe; memcpy(image, &s, 1); break; }
        }
        const uint8_t words = bb_registersOf(wire);
        for (uint8_t w = 0; w < words; w++) {
          node->setHregFailsafe((uint16_t)(ADDRESS + w), BeeBusFailsafe::ResetToValue,
                                (int16_t)bb_valueRegister(image, wire, w));
        }
      }
    }

    fbPlan = (strucpp::XWORD_t)(uintptr_t)made;
    storage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
    seenFailsafe = node->failsafeCount(table, (uint16_t)ADDRESS);
    COUNT = (uint16_t)bb_planRegisters(made);
    isBound = true;
  }

  void* plan = (void*)(uintptr_t)(strucpp::XWORD_t)fbPlan;
  BOUND = true;

  // The descriptor is rebuilt at every call, and a pin that moved would leave
  // the protocol writing where nothing reads.
  if (bb_planMoved(plan, VALUE)) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    LAST_ERROR = "VALUE moved: wire the same variable every scan";
    return;
  }

  // What peers wrote since the last scan. WRITTEN_* hold until the next write.
  uint32_t first = 0;
  const uint16_t written = bb_planServe(plan, node, &first);
  WRITTEN = (written != 0);
  if (written != 0) {
    char name[65] = "";
    uint32_t offset = 0;
    bb_planLeafInfo(plan, first, name, sizeof(name), &offset);
    WRITTEN_NAME = name;
    WRITTEN_INDEX = (uint16_t)(first + 1);
    WRITTEN_ADDRESS = (uint16_t)((uint16_t)ADDRESS + offset);
    WRITTEN_COUNT = written;
  }

  const uint16_t safed = node->failsafeCount(table, (uint16_t)ADDRESS);
  SAFE_APPLIED = (safed != (uint16_t)seenFailsafe);
  seenFailsafe = safed;

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  LAST_ERROR = "";
}

END_FUNCTION_BLOCK