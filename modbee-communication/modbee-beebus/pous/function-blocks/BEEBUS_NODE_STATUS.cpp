(* How this node and its segment are doing.

NODE          which node.
DEBUG_ENABLE  print the protocol's own debug lines to the console.

CONNECTED     this node is in a ring.
NODE_ID       its own address.
MEMBERS       how many nodes are in the ring, including this one.
ROTATION      how long the token takes to come round, measured. T#0s until it has
              been.
PENDING_OPS   operations queued and not yet finished.
CRC_ERRORS    frames that arrived corrupt. Rising on a quiet bus is the number
              to judge a link by.
NOISE_BYTES   bytes discarded while hunting for a frame start. Climbing
              steadily means a floating bus, a missing termination, or a baud
              rate mismatch.
ERROR         no such node.
STATUS        why. BEEBUS_OK when fine.
              BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
              BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
              BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED,
              BEEBUS_DUPLICATE, BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT,
              BEEBUS_NODE_LOST, BEEBUS_SUPERSEDED, BEEBUS_CANCELLED,
              BEEBUS_REFUSED, BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED,
              BEEBUS_BUFFER_FULL

---

Nothing here is a setting. Every number is measured, and the ones worth
watching are the two error counters: on an otherwise quiet bus they are what
separates a link that is slow from one that is going bad. *)

FUNCTION_BLOCK BEEBUS_NODE_STATUS
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    DEBUG_ENABLE : BOOL;
  END_VAR
  VAR_OUTPUT
    CONNECTED : BOOL;
    NODE_ID : BYTE;
    MEMBERS : BYTE;
    ROTATION : TIME;
    PENDING_OPS : INT;
    CRC_ERRORS : DINT;
    NOISE_BYTES : DINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
  END_VAR

#include <BeeBusAPI.h>

// Defined in BEEBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so the declaration is written not assumed.
int32_t bb_millisOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds);

#include <cstdio>

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  CONNECTED = false;
  NODE_ID = 0;
  MEMBERS = 0;
  ROTATION = bb_timeOf(0);
  PENDING_OPS = 0;
  CRC_ERRORS = 0;
  NOISE_BYTES = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;

  // Installed once, from the value wired at start-up. The protocol carries one
  // debug handler per node, so a block that reinstalled it every scan would be
  // replacing the same handler with itself for the life of the program.
  if ((bool)DEBUG_ENABLE) {
    BeeBusAPI* node = (BeeBusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.API;
    if (node) {
      node->onDebug([](const char* category, const char* message) {
        std::printf("[%s] %s\n", category, message);
      });
    }
  }
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
    CONNECTED = false;
    return;
  }

  CONNECTED = node->isConnected();
  NODE_ID = node->getNodeID();
  MEMBERS = node->getMemberCount();
  ROTATION = bb_timeOf((int32_t)node->getRotationTime());
  PENDING_OPS = (int16_t)node->getPendingOpCount();

  const BeeBusIOStats stats = node->getLinkStatistics();
  CRC_ERRORS = (int32_t)stats.crcErrors;
  NOISE_BYTES = (int32_t)stats.noiseBytesDiscarded;

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
}

END_FUNCTION_BLOCK