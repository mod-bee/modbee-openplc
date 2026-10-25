(* A peer's topic: bind it to one of your variables, and ask for a stream of it.

NODE            which node. Unwired = the only one. One instance is one topic:
                PEER, NAME, TOPIC_ID and VALUE are taken on the first scan the
                node is there, and changing them later does nothing (DEADBAND
                and PERIOD may change; the subscription is re-asked). A second
                topic is a second instance - or, for a whole STRUCT, one
                BEEBUS_TP_STRUCT_SUBSCRIBE.
PEER            the node that owns the topic.
NAME            its name on that node, up to 253 characters.
TOPIC_ID        its id on that node. Stated here and nowhere else.
DEADBAND        send again only once it has moved this far. 0 for every change.
PERIOD          ask for it at least this often even when it has not moved.
                T#0s for never.
RELIABLE        FALSE (LIVE, the default): best effort, newest wins - for
                levels, flows and speeds. TRUE for a setpoint, a setting or
                configuration: every change arrives, and one a lost frame took
                is sent again, as the current value, within a rotation or two.
                DEADBAND does not apply. Changing it re-asks the subscription.
VALUE           the variable the arriving value lands in. Its declared type must
                be the type the owner bound, or the values are wrong rather than
                refused.

QUALITY   BEEBUS_TP_GOOD, BEEBUS_TP_UNCERTAIN or BEEBUS_TP_BAD as the value ages, BEEBUS_TP_UNKNOWN before
          anything has arrived.
          BEEBUS_TP_UNKNOWN, BEEBUS_TP_GOOD, BEEBUS_TP_UNCERTAIN, BEEBUS_TP_BAD
SEEN      a value has arrived at least ONCE since the program started. It
          is what tells an AGE of T#0s apart, and it is how a LADDER asks
          what QUALITY answers - a rung cannot compare an enumeration.
AGE       how long since the last value. T#0s until one ever arrives, which
          QUALITY reading BEEBUS_TP_UNKNOWN is what distinguishes.
NEW_VALUE a value arrived since the last scan. The only honest way to tell an
          arrived value from one that has not changed.
MISSED    publishes the sequence says never reached us, since the program
          started. A running total, so a `debug read` sees it — zeroed every
          scan it was almost always 0 whatever had happened.
ERROR     no such node, or the subscription was refused.
STATUS    why. BEEBUS_OK when fine, BEEBUS_NOT_SUBSCRIBED before the peer is in the ring.
          BEEBUS_QUEUED, BEEBUS_OK, BEEBUS_NOT_INITIALISED,
          BEEBUS_INVALID_ARGUMENT, BEEBUS_UNKNOWN_NODE,
          BEEBUS_DUPLICATE_NODE_ID, BEEBUS_NOT_MAPPED, BEEBUS_DUPLICATE,
          BEEBUS_QUEUE_FULL, BEEBUS_TIMEOUT, BEEBUS_NODE_LOST,
          BEEBUS_SUPERSEDED, BEEBUS_CANCELLED, BEEBUS_REFUSED,
          BEEBUS_TYPE_MISMATCH, BEEBUS_NOT_SUBSCRIBED, BEEBUS_BUFFER_FULL

---

Binding and subscribing were two blocks, and were never useful apart — a
binding with no subscription receives only what someone else asked for, and a
subscription with no binding has nowhere to put the value. This is both.

The value lands in VALUE. There is no separate text output: the variable you
wired is the value, in front of you, and a string topic binds a STRING.

The subscription is re-issued whenever the peer rejoins the ring, so a peer that
was absent at start-up or has rebooted needs nothing from the program.

This is also how a command is taken. Nothing writes into another node's
storage: the commanding node owns the topic and publishes it, this node
subscribes and acts on what arrives. *)

FUNCTION_BLOCK BEEBUS_TP_SUBSCRIBE
  VAR_IN_OUT
    NODE : BEEBUS_NODE;
  END_VAR
  VAR_INPUT
    PEER : BYTE;
    NAME : STRING(254);
    TOPIC_ID : UINT;
    DEADBAND : REAL;
    PERIOD : TIME;
    VALUE : ANY;
    RELIABLE : BOOL;
  END_VAR
  VAR_OUTPUT
    QUALITY : BEEBUS_TP_QUALITY;
    SEEN : BOOL;
    AGE : TIME;
    NEW_VALUE : BOOL;
    MISSED : UDINT;
    ERROR : BOOL;
    STATUS : BEEBUS_RESULT;
  END_VAR
  VAR
    isBound : BOOL;
    wireType : BYTE;
    storage : __XWORD;
    issued : BOOL;
    askedDeadband : REAL;
    askedInterval : DINT;
    seenReceived : UINT;
    seenMissed : UINT;
    askedReliable : BOOL;
  END_VAR
#include <BeeBusAPI.h>

// Defined in BEEBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so the declaration is written not assumed.
int32_t bb_millisOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds);

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
  QUALITY = BEEBUS_TP_QUALITY::BEEBUS_TP_UNKNOWN;
  AGE = bb_timeOf(0);
  SEEN = false;
  NEW_VALUE = false;
  MISSED = 0;
  ERROR = false;
  STATUS = BEEBUS_RESULT::BEEBUS_OK;
  isBound = false;
  wireType = BEEBUS_T_COUNT;
  storage = (strucpp::XWORD_t)0;
  issued = false;
  askedDeadband = 0.0f;
  askedReliable = false;
  askedInterval = 0;
  seenReceived = 0;
  seenMissed = 0;
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

  if (!(bool)isBound) {
    if (NAME.length() == 0 || NAME.length() >= BB_NAME_PIN) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }

    wireType = bb_wireTypeOfClass((uint32_t)VALUE.ELEMCLASS);
    if ((uint8_t)wireType == BEEBUS_T_COUNT) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }

    // Every type binds the caller's own variable, straight off the pin, and
    // a peer's value arrives in it. A STRING is its buffer: n characters and
    // the terminator (DISIZE bytes); longer text is cut to fit.
    void* where = (void*)VALUE.PVALUE;
    const uint16_t textCap = ((uint8_t)wireType == BEEBUS_T_STRING && VALUE.DISIZE > 1)
                                 ? (uint16_t)VALUE.DISIZE : 0;
    if (!node->registerTopicRaw((uint8_t)PEER, (uint16_t)TOPIC_ID, (uint8_t)wireType,
                                where, NAME.c_str(), textCap)) {
      ERROR = true;
      STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
      return;
    }
    storage = (strucpp::XWORD_t)(uintptr_t)where;
    isBound = true;
  }

  // A pin that moved would leave the protocol writing into storage nothing
  // reads.
  if ((strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE != (strucpp::XWORD_t)storage) {
    storage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
    node->rebindRemoteTopic((uint8_t)PEER, (uint16_t)TOPIC_ID, (void*)VALUE.PVALUE);
  }

#if BEEBUS_TOPIC_NAMES
  // Asked for once, and again only when the terms on the pins change. A
  // subscription is a standing intent: the protocol holds it until the peer is
  // on the network and re-establishes it if the peer restarts.
  const float deadband = (float)DEADBAND;
  const int32_t interval = bb_millisOf(PERIOD);

  const bool reliable = (bool)RELIABLE;

  if (!(bool)issued || (float)askedDeadband != deadband ||
      (int32_t)askedInterval != interval || (bool)askedReliable != reliable) {
    const BeeBusResult result =
        node->subscribe((uint8_t)PEER, (uint16_t)TOPIC_ID, deadband, (bb_time_t)interval,
                        reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live);
    issued = bb_accepted(result) || result == BeeBusResult::Duplicate;
    askedDeadband = deadband;
    askedInterval = interval;
    askedReliable = reliable;
    ERROR = !(bool)issued;
    STATUS = (BEEBUS_RESULT)(int32_t)result;
  } else {
    ERROR = false;
    STATUS = BEEBUS_RESULT::BEEBUS_OK;
  }

  QUALITY = (BEEBUS_TP_QUALITY)node->topicQuality((uint8_t)PEER, (uint16_t)TOPIC_ID);
  const bb_time_t age = node->topicAge((uint8_t)PEER, (uint16_t)TOPIC_ID);
  AGE = bb_timeOf((age == BEEBUS_SILENCE_NEVER) ? 0 : (int32_t)age);
  SEEN = (age != BEEBUS_SILENCE_NEVER);
#else
  ERROR = true;
  STATUS = BEEBUS_RESULT::BEEBUS_INVALID_ARGUMENT;
#endif

  // The node counts publishes and gaps; this keeps what it last saw, so two
  // blocks watching one topic do not take each other's edges.
  BeeBusTopicStream stream;
  if (node->topicStream((uint8_t)PEER, (uint16_t)TOPIC_ID, stream)) {
    NEW_VALUE = (stream.received != (uint16_t)seenReceived);
    // A running total, so a gap three scans ago is still the useful number.
    MISSED = (uint32_t)MISSED + (uint16_t)(stream.missed - (uint16_t)seenMissed);
    seenReceived = stream.received;
    seenMissed = stream.missed;
  } else {
    NEW_VALUE = false;
  }
}

END_FUNCTION_BLOCK