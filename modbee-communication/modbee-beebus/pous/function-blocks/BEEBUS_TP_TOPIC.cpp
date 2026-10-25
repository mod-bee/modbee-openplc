(* A topic this node owns, bound to one of your variables.

NODE      which node. Unwired = the only one. The node block must be called
          first. One instance is one topic: NAME, TOPIC_ID and VALUE are taken
          on the first scan the node is there, and changing them later does
          nothing. A second topic is a second instance - or put the values in
          a STRUCT and use BEEBUS_TP_STRUCT, one block for all of them.
NAME      up to 253 characters, and the identity: every other block addresses
          this topic by it. Longer is BEEBUS_INVALID_ARGUMENT rather than truncated,
          because two long names cut to the same length become one topic across
          the whole network, in silence. A node with an older BeeBus refuses a name
          over 31 characters.
TOPIC_ID  1..32767, unique on this node. Under 128 costs one byte on the wire.
          Stated here and nowhere else.
VALUE     the variable itself, of whatever type you declared it. Its declared
          type is the type on the wire: BOOL, SINT, USINT, BYTE, INT, UINT,
          WORD, DINT, UDINT, DWORD, LINT, ULINT, LWORD, REAL, LREAL, LTIME
          (LINT nanoseconds) or STRING. WSTRING and the other time and date
          types are BEEBUS_INVALID_ARGUMENT.

BOUND     registered on the node.
ERROR     no such node, a type the wire cannot carry, or an ID already bound.
STATUS    why. BEEBUS_OK when fine.
          BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
          BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
          BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
          BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
          BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
          BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

There is no request pin. Once bound the node publishes on its own, to every
subscriber, on the deadband and interval each of them asked for. Move VALUE and
it goes out.

Peers may read this topic; they may not write it. To take a command from
somewhere else, subscribe to a topic that node owns — see BEEBUS_TP_SUBSCRIBE. *)

FUNCTION_BLOCK BEEBUS_TP_TOPIC
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    NAME : STRING(254);
    TOPIC_ID : UINT;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
    isBound : BOOL;
    wireType : BYTE;
    storage : __XWORD;
  END_VAR
#include <BeeBusAPI.h>


// Defined by the BEEBUS_NODE block, which every project has.
uint8_t bb_wireTypeOfClass(uint32_t typeClass);

// NAME is STRING(254), the longest STRING the editor declares. A name that
// fills it may have been cut to fit, and two names cut alike would be one
// topic: names are 253 characters at most here, and a full NAME is refused.
// (Every block lands in one translation unit, hence the guard.)
#ifndef BB_NAME_PIN
#define BB_NAME_PIN 254u
#endif

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  BOUND = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  isBound = false;
  wireType = BEEBUS_T_COUNT;
  storage = (strucpp::XWORD_t)0;
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

  if (!(bool)isBound) {
    // A name the wire cannot carry whole is refused rather than cut down.
    if (NAME.length() == 0 || NAME.length() >= BB_NAME_PIN) {
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }

    wireType = bb_wireTypeOfClass((uint32_t)VALUE.ELEMCLASS);
    if ((uint8_t)wireType == BEEBUS_T_COUNT) {
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }

    // Every type binds the caller's own variable, straight off the pin. A
    // STRING is its buffer: n characters and the terminator (DISIZE bytes).
    void* where = (void*)VALUE.PVALUE;
    const uint16_t textCap = ((uint8_t)wireType == BEEBUS_T_STRING && VALUE.DISIZE > 1)
                                 ? (uint16_t)VALUE.DISIZE : 0;
    if (!node->addTopicRaw((uint16_t)TOPIC_ID, (uint8_t)wireType, where, false,
                           NAME.c_str(), textCap)) {
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
    storage = (strucpp::XWORD_t)(uintptr_t)where;
    isBound = true;
  }

  BOUND = true;

  // The descriptor is rebuilt at every call. For a program or function block
  // variable it addresses the same instance member every scan — checked rather
  // than assumed, because a pin that moved would leave the protocol writing
  // into storage nothing reads.
  if ((strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE != (strucpp::XWORD_t)storage) {
    storage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
    if (!node->rebindTopic((uint16_t)TOPIC_ID, (void*)VALUE.PVALUE)) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
  }

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
}

END_FUNCTION_BLOCK