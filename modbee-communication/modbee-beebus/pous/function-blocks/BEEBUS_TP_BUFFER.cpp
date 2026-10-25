(* Holds samples of one of our topics while there is nowhere to send them.

NODE   which node. Unwired = the only one.
NAME   the topic, as bound by BEEBUS_TP_TOPIC or BEEBUS_TP_PUBLISH on this node.
DEPTH  samples to hold. 0 turns buffering off again.

HELD   samples waiting to go out.
ERROR  no such node, or no such topic on it.
STATUS why. BEEBUS_OK when fine.
       BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
       BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
       BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
       BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
       BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
       BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

Off TOPIC because on almost every topic it is not wanted, and two pins dead on
every instance is two pins a reader has to decide about.

Each held sample carries the age it was taken at, so a subscriber that comes
back gets the history rather than only the latest value. That is what makes
this different from simply publishing again: the shape of what happened while
the link was down survives. *)

FUNCTION_BLOCK BEEBUS_TP_BUFFER
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    NAME : STRING(254);
    DEPTH : BYTE;
  END_VAR
  VAR_OUTPUT
    HELD : UINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
  END_VAR
#include <BeeBusAPI.h>

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  HELD = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;

  BeeBusAPI* node = (BeeBusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.API;
  if (!node) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

#if BEEBUS_TOPIC_NAMES
  // BEEBUS_TP_TOPIC or BEEBUS_TP_PUBLISH binds; this only asks for depth, so it runs after and
  // reports BEEBUS_NOT_MAPPED when the topic is not there.
  if (node->topicIdOf(NAME.c_str()) == BEEBUS_TOPIC_NONE) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_NOT_MAPPED;
    return;
  }
  node->bufferTopic(NAME.c_str(), (uint8_t)DEPTH);
#else
  ERROR = true;
  STATUS = BEEBUS_RESULT::BEEBUS_NOT_MAPPED;
#endif
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
    HELD = 0;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

#if BEEBUS_TOPIC_NAMES
  const uint16_t topicID = node->topicIdOf(NAME.c_str());
  if (topicID == BEEBUS_TOPIC_NONE) {
    HELD = 0;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_NOT_MAPPED;
    return;
  }

  HELD = (uint16_t)node->bufferedCount(topicID);
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
#else
  HELD = 0;
#endif
}

END_FUNCTION_BLOCK