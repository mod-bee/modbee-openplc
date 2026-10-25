(* Writes one value into a topic a PEER owns, on a rising edge of REQ. The
peer must have bound the topic writable (BEEBUS_TP_STRUCT WRITABLE, or a
writable topic in C++): a read-only topic refuses the write.

NODE        which node. Unwired = the only one. The node block must be called
            first.
REQ         rising edge: write VALUE now.
PEER        the node that owns the topic.
TOPIC_ID    the topic's id on that node, as the owner gave it (its STRUCT's
            TOPIC_ID plus the member's position).
CONFIRMED   retry until the peer acknowledges. DONE then means the peer has it,
            and it is applied once however often it was sent (RELIABLE for a
            one-off write).
WANT_RESULT ask the owner what it did with the value: DONE then waits for
            its decision, and RESULT, ACCEPTED, REFUSED and KEPT_VALUE say it.
            Makes the write CONFIRMED.
VALUE       the value to write: one variable of the member's type (BOOL,
            SINT..ULINT, BYTE..LWORD, REAL, LREAL, LTIME, STRING or an
            enumeration).

BUSY        waiting for the acknowledgement (and the decision, with
            WANT_RESULT). Always FALSE unconfirmed.
DONE        one scan, when the write went (unconfirmed), was acknowledged, or
            (WANT_RESULT) the owner decided.
ERROR       one scan, when it was refused, not acknowledged, or no decision
            came back (STATUS BEEBUS_TIMEOUT).
STATUS      why. BEEBUS_OK when fine; BEEBUS_REFUSED when the peer's topic is
            read only; BEEBUS_TYPE_MISMATCH when VALUE's type differs from the
            member's.
RESULT      WANT_RESULT: the owner's decision, held until the next write.
            BEEBUS_TP_ACCEPTED kept as written; BEEBUS_TP_CHANGED kept another
            value (clamped, rounded, put back); BEEBUS_TP_REFUSED not taken;
            BEEBUS_TP_NO_ANSWER before one came, or none did.
            BEEBUS_TP_ACCEPTED, BEEBUS_TP_CHANGED, BEEBUS_TP_REFUSED,
            BEEBUS_TP_READ_ONLY, BEEBUS_TP_NO_TOPIC, BEEBUS_TP_WRONG_TYPE,
            BEEBUS_TP_BUSY, BEEBUS_TP_NO_ANSWER
ACCEPTED    the decision was ACCEPTED, for a Ladder rung (held).
REFUSED     the owner kept another value: CHANGED or REFUSED (held).
KEPT_VALUE  the owner's value with the decision, as a number (held).

A writable STRUCT takes the write in its own scan (one per member a scan), so
the value may show on the peer's subscribers a scan or two after DONE. Fire REQ
once per change: it is an edge, and every rising edge is one write. *)

FUNCTION_BLOCK BEEBUS_TP_WRITE
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    PEER : BYTE;
    TOPIC_ID : UINT;
    CONFIRMED : BOOL;
    VALUE : ANY;
    WANT_RESULT : BOOL;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
    RESULT : BEEBUS_TP_OUTCOME;
    ACCEPTED : BOOL;
    REFUSED : BOOL;
    KEPT_VALUE : LREAL;
  END_VAR
  VAR
    lastReq : BOOL;
    pending : BOOL;
    waitingResult : BOOL;
    resultCount : UINT;
  END_VAR
#include <BeeBusAPI.h>

// Defined by the BEEBUS_NODE block, which every project has.
uint8_t bb_wireTypeOfClass(uint32_t typeClass);

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
  waitingResult = false;
  resultCount = 0;
  RESULT = BEEBUS_TP_OUTCOME::BEEBUS_TP_NO_ANSWER;
  ACCEPTED = false;
  REFUSED = false;
  KEPT_VALUE = 0.0;
}

// The owner's decision, as the outputs show it.
struct BbShownResult {
  int32_t result;
  bool accepted;
  bool refused;
  double kept;
};

static BbShownResult bbShowResult(uint8_t outcome, const BeeBusScalar& kept)
{
  BbShownResult shown;
  shown.result = outcome < (uint8_t)BEEBUS_OUTCOME_COUNT ? outcome : (int32_t)BEEBUS_OUTCOME_COUNT;
  shown.accepted = outcome == BEEBUS_OUTCOME_ACCEPTED;
  shown.refused = outcome == BEEBUS_OUTCOME_CHANGED || outcome == BEEBUS_OUTCOME_REFUSED;
  shown.kept = bb_topicTypeIsString(kept.type) ? 0.0 : bb_scalarToDouble(kept);
  return shown;
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
    BUSY = false;
    DONE = false;
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_UNKNOWN_NODE;
    return;
  }

  if ((bool)pending) {
    BeeBusResult outcome = BeeBusResult::Immediate;
    const BeeBusRequestState state =
        node->requestState((uint8_t)PEER, (uint16_t)TOPIC_ID, outcome);
    // With a result asked for, DONE waits for the owner's decision, which
    // follows the acknowledgement; the protocol gives up on it by itself.
    if ((bool)waitingResult && state != BeeBusRequestState::Failed) {
      uint8_t decided = BEEBUS_OUTCOME_NONE;
      BeeBusScalar kept;
      uint16_t count = 0;
      if (!node->topicResult((uint8_t)PEER, (uint16_t)TOPIC_ID, decided, kept, count) ||
          count == (uint16_t)resultCount) {
        BUSY = true;
        DONE = false;
        ERROR = false;
        return;
      }
      pending = false;
      waitingResult = false;
      BUSY = false;
      const BbShownResult shown = bbShowResult(decided, kept);
      RESULT = (BEEBUS_TP_OUTCOME)shown.result;
      ACCEPTED = shown.accepted;
      REFUSED = shown.refused;
      KEPT_VALUE = shown.kept;
      const bool decision = decided == BEEBUS_OUTCOME_ACCEPTED ||
                            decided == BEEBUS_OUTCOME_CHANGED ||
                            decided == BEEBUS_OUTCOME_REFUSED;
      DONE = decision;
      ERROR = !decision;
      STATUS = decision ? BEEBUS_RESULT::BEEBUS_OK : BEEBUS_RESULT::BEEBUS_TIMEOUT;
      return;
    }
    if (state == BeeBusRequestState::Pending) {
      BUSY = true;
      DONE = false;
      ERROR = false;
      return;
    }
    pending = false;
    waitingResult = false;
    BUSY = false;
    DONE = (state == BeeBusRequestState::Done);
    ERROR = (state == BeeBusRequestState::Failed);
    STATUS = (BEEBUS_RESULT)(int32_t)outcome;
    return;
  }

  // DONE and ERROR are one-scan edges.
  BUSY = false;
  DONE = false;
  ERROR = false;

  const bool rose = (bool)REQ && !(bool)lastReq;
  lastReq = (bool)REQ;
  if (!rose) return;

  const uint8_t wire = bb_wireTypeOfClass((uint32_t)VALUE.ELEMCLASS);
  if (wire == BEEBUS_T_COUNT || (uint16_t)TOPIC_ID == 0 || !VALUE.PVALUE) {
    ERROR = true;
    STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
    return;
  }

  // A result is asked for only of a confirmed write: the decision answers a
  // request that arrived.
  const bool wantResult = (bool)WANT_RESULT;
  const BeeBusDelivery delivery = ((bool)CONFIRMED || wantResult) ? BeeBusDelivery::Confirmed
                                                                  : BeeBusDelivery::Unconfirmed;
  if (wantResult) {
    uint8_t decided = 0;
    BeeBusScalar kept;
    uint16_t count = 0;
    node->topicResult((uint8_t)PEER, (uint16_t)TOPIC_ID, decided, kept, count);
    resultCount = count;
  }
  const BeeBusResult result =
      (wire == BEEBUS_T_STRING)
          ? node->writeTopic((uint8_t)PEER, (uint16_t)TOPIC_ID, (const char*)VALUE.PVALUE,
                             delivery, wantResult)
          : node->writeTopicRaw((uint8_t)PEER, (uint16_t)TOPIC_ID,
                                bb_scalarLoad(wire, (const void*)VALUE.PVALUE), delivery,
                                wantResult);

  if (!bb_accepted(result) && result != BeeBusResult::Duplicate) {
    ERROR = true;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
    return;
  }
  RESULT = BEEBUS_TP_OUTCOME::BEEBUS_TP_NO_ANSWER;
  ACCEPTED = false;
  REFUSED = false;
  if (delivery == BeeBusDelivery::Confirmed) {
    pending = true;
    waitingResult = wantResult;
    BUSY = true;
  } else {
    DONE = true;
  }
  STATUS = (BEEBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK