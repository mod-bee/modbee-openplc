(* Owns a topic, and sends it when you say so.

NODE       which node. Unwired = the only one. The node block must be called
           first. One instance is one topic: NAME, TOPIC_ID and VALUE are
           taken on the first scan the node is there, and changing them later
           does nothing. A second topic is a second instance.
REQ        rising edge sends.
NAME       up to 253 characters, and the identity. Longer is
           BEEBUS_INVALID_ARGUMENT rather than truncated. A node with an
           older BeeBus refuses a name over 31 characters.
TOPIC_ID   1..32767, unique on this node. Under 128 costs one byte on the wire.
MODE       who gets it, as above.
           BEEBUS_TP_PUBLISH_ALL, BEEBUS_TP_PUBLISH_TO
PEER       the node to send to, when MODE is BEEBUS_TP_PUBLISH_TO.
CONFIRMED  retry until acknowledged, so DONE means the peer has it. Only with
           BEEBUS_TP_PUBLISH_TO. Off, the frame goes once and DONE means it reached the
           wire.
           CONFIRMED is RELIABLE for a one-off publish.
VALUE      the variable itself, of whatever type you declared it. Its declared
           type is the type on the wire: BOOL, SINT, USINT, BYTE, INT, UINT,
           WORD, DINT, UDINT, DWORD, LINT, ULINT, LWORD, REAL, LREAL, LTIME
           (LINT nanoseconds) or STRING. WSTRING and the other time and date
           types are BEEBUS_INVALID_ARGUMENT.

BOUND      the topic is registered on the node.
BUSY       waiting on the acknowledgement. Always FALSE unconfirmed.
DONE       one scan, when it went.
ERROR      it did not.
STATUS     why. BEEBUS_OK when fine.
           BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
           BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
           BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
           BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
           BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
           BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

BEEBUS_TP_TOPIC publishes on its own, whenever a subscriber's deadband says to. This
one publishes on a rising edge of REQ instead, which is what an event wants: a
value that must go the moment something happened rather than when it has moved
far enough.

The block is complete on its own — it binds VALUE and it sends it. Put BEEBUS_TP_TOPIC
beside it, with the same NAME and TOPIC_ID, when the topic should ALSO go out on
the subscribers' own terms. The two are separate pipelines and do not disturb
each other: a subscription is a counted stream, so a lost sample shows up as
MISSED, while a broadcast takes no part in that counting and is simply applied
on arrival.

MODE says who gets it, and is named for the protocol call it makes:

  BEEBUS_TP_PUBLISH_ALL  publishAll — every node at once, one frame however many are
                  listening. Every node holding the topic takes it, subscribed
                  or not, and it is applied whatever else that topic has been
                  carrying. Nothing acknowledges a broadcast, so CONFIRMED is
                  refused with BEEBUS_INVALID_ARGUMENT — and nothing counts one
                  either, so a broadcast that goes missing is not reported.

  BEEBUS_TP_PUBLISH_TO   publishTo — the node named by PEER, subscribed or not. One
                  frame, on that node's own counted stream, and the only mode
                  that can be CONFIRMED: only a named node can answer for
                  itself.

BEEBUS_TP_PUBLISH_ALL is what a node that wakes, reports and sleeps again wants: one
turn on the bus and every listener has the value. The bus is shared, so a copy
per listener would cost a copy and buy no delivery — every node's receiver
already has the bytes whatever the frame is addressed to. *)

FUNCTION_BLOCK BEEBUS_TP_PUBLISH
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    NAME : STRING(254);
    TOPIC_ID : UINT;
    MODE : BEEBUS_TP_SEND;
    PEER : BYTE;
    CONFIRMED : BOOL;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
    isBound : BOOL;
    wireType : BYTE;
    storage : __XWORD;
    text : __XWORD;
    lastReq : BOOL;
    pending : BOOL;
  END_VAR
#include <BeeBusAPI.h>
#include <string>

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
  BUSY = false;
  DONE = false;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  isBound = false;
  wireType = BEEBUS_T_COUNT;
  storage = (strucpp::XWORD_t)0;
  lastReq = false;
  pending = false;
  // A string topic is bound to a std::string, which the pin is not.
  text = (strucpp::XWORD_t)(uintptr_t)(new std::string());
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
    BUSY = false;
    DONE = false;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  std::string* held = (std::string*)(uintptr_t)(strucpp::XWORD_t)text;

  if (!(bool)isBound) {
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

    void* where = ((uint8_t)wireType == BEEBUS_T_STRING) ? (void*)held
                                                         : (void*)VALUE.PVALUE;
    // BEEBUS_TP_TOPIC may already own this one, which is not an error: this block then
    // only publishes it.
    if (!node->addTopicRaw((uint16_t)TOPIC_ID, (uint8_t)wireType, where, false,
                           NAME.c_str()) &&
        node->topicIdOf(NAME.c_str()) != (uint16_t)TOPIC_ID) {
      BOUND = false;
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
    storage = (strucpp::XWORD_t)(uintptr_t)where;
    isBound = true;
  }

  BOUND = true;

  // A pin that moved would leave the protocol reading storage nothing writes.
  if ((uint8_t)wireType != BEEBUS_T_STRING &&
      (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE != (strucpp::XWORD_t)storage) {
    storage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
    if (!node->rebindTopic((uint16_t)TOPIC_ID, (void*)VALUE.PVALUE)) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
  }

  // This node owns the topic, so the pin is the truth and the binding follows.
  if ((uint8_t)wireType == BEEBUS_T_STRING && held) {
    const char* buffer = (const char*)VALUE.PVALUE;
    if (buffer) held->assign(buffer);
  }

  // Which peer the operation waits on, so the two modes on one topic keep their
  // own outstanding operation rather than clearing each other's.
  const uint8_t target =
      (MODE == BEEBUS_TP_SEND::BEEBUS_TP_PUBLISH_TO) ? (uint8_t)PEER : BEEBUS_NODE_BROADCAST;

  if ((bool)pending) {
    BeeBusResult outcome = BeeBusResult::Immediate;
    const BeeBusRequestState state = node->requestState(target, (uint16_t)TOPIC_ID, outcome);
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

  const BeeBusDelivery delivery =
      (bool)CONFIRMED ? BeeBusDelivery::Confirmed : BeeBusDelivery::Unconfirmed;

  const BeeBusResult result =
      (MODE == BEEBUS_TP_SEND::BEEBUS_TP_PUBLISH_TO)
          ? node->publishTo((uint8_t)PEER, (uint16_t)TOPIC_ID, delivery)
          : node->publishAll((uint16_t)TOPIC_ID, delivery);

  if (!bb_accepted(result) && result != BeeBusResult::Duplicate) {
    ERROR = true;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }

  // An unconfirmed publish has nothing to wait for, so it is done at the call.
  // A confirmed one finishes when the peer answers.
  if (delivery == BeeBusDelivery::Confirmed) {
    pending = true;
    BUSY = true;
  } else {
    DONE = true;
  }
  ERROR = false;
  STATUS = (BEEBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK