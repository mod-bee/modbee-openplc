(* How one peer is doing, from this node's point of view.

NODE          which node.
PEER          the peer to report on.

ALIVE         the peer is in the ring.
SEEN          anything has been heard from it at least ONCE since the
              program started. SEEN FALSE is a peer never fitted or given
              the wrong id; SEEN TRUE with ALIVE FALSE is one that has
              dropped off the ring.
SILENT        how long since anything was heard from it. T#0s until anything
              ever is, which ALIVE reading FALSE is what distinguishes.
HOP           how long it takes to accept the token, measured.
HOP_TIMEOUT   how long it is allowed before the token is presumed lost.
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

HOP is how quick that peer is to take the token; HOP_TIMEOUT is what it is
allowed before the token is presumed lost. The two together are what separates
a link that is slow from one that is going bad — a hop time creeping towards
its limit is a link about to drop a node, and it says so before it does. *)

FUNCTION_BLOCK BEEBUS_NODE_PEER_STATUS
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    PEER : BYTE;
  END_VAR
  VAR_OUTPUT
    ALIVE : BOOL;
    SEEN : BOOL;
    SILENT : TIME;
    HOP : TIME;
    HOP_TIMEOUT : TIME;
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

strucpp::XWORD_t bb_currentTask();
bool bb_inTask(strucpp::XWORD_t owner);

void setup()
{
  ALIVE = false;
  SEEN = false;
  SILENT = bb_timeOf(0);
  HOP = bb_timeOf(0);
  HOP_TIMEOUT = bb_timeOf(0);
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
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
    ALIVE = false;
    return;
  }

  const uint8_t peer = (uint8_t)PEER;
  ALIVE = node->isAlive(peer);

  const bb_time_t silence = node->silenceFor(peer);
  SILENT = bb_timeOf((silence == BEEBUS_SILENCE_NEVER) ? 0 : (int32_t)silence);
  SEEN = (silence != BEEBUS_SILENCE_NEVER);

  HOP = bb_timeOf((int32_t)node->getHopTime(peer));
  HOP_TIMEOUT = bb_timeOf((int32_t)node->getHopTimeout(peer));

  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
}

END_FUNCTION_BLOCK