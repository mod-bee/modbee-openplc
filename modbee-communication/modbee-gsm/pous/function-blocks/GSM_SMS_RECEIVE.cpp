(* Text messages arriving at the SIM, one at a time.

MODEM       which modem. Must be wired.
ENABLE      TRUE takes messages as they arrive. FALSE leaves them on the SIM.

RECEIVED    one scan, when SENDER, TEXT, INDEX and SENT_AT describe a message
            that has just arrived.
SENDER      who sent it, as the network gives it: '+6400000000'.
TEXT        what it says, up to 160 characters.
INDEX       where the SIM had stored it. Informational: the message has
            already been deleted from the SIM.
SENT_AT     when the network's message centre took it, in UTC. DT#1970-01-01
            when the network gave no time.
COUNT       messages received since the PLC started.
ERROR       MODEM is not a running GSM_MODEM.
STATUS      why. GSM_OK when fine; GSM_NOT_READY until the network has
            accepted the SIM.

---

  inbox( MODEM := modem );
  IF inbox.RECEIVED AND inbox.SENDER = oncall AND inbox.TEXT = 'RESET' THEN
      resetAlarms := TRUE;
  END_IF;

EVERY MESSAGE IS DELETED FROM THE SIM once it has been read. A SIM holds a few
dozen; one that is full is refused new messages by the network, silently, and
on a remote site nobody notices until a command does not arrive. A message the
library cannot decode is deleted too, so it cannot hold a slot for ever.

RECEIVED IS ONE SCAN WIDE, and each scan hands over at most one message, so
several arriving together come out on successive scans. Act on the message in
the same scan, or copy it.

CHECK SENDER. Anybody who knows the number can send to it, and SENDER is the
only thing that says who did. A message carrying a command should be checked
against a list, and SENT_AT against the clock if an old message must not act.

Use ONE of these per PLC. A long message the sender's phone split into parts
arrives as its parts, each with its own RECEIVED.

Messages that arrive while ENABLE is FALSE stay on the SIM, unread. *)

FUNCTION_BLOCK GSM_SMS_RECEIVE
  VAR_INPUT
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    RECEIVED : BOOL;
    SENDER : STRING(23);
    TEXT : STRING(160);
    INDEX : UINT;
    SENT_AT : DT;
    COUNT : UDINT;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    RECEIVED = false;
    COUNT = 0;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
}

void loop()
{
    RECEIVED = false;

    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        ERROR = (bool)ENABLE;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        return;
    }

    gsmplc::smsReceive((bool)ENABLE);
    ERROR = false;
    if (!(bool)ENABLE) {
        STATUS = GSM_RESULT::GSM_OK;
        return;
    }
    STATUS = gsmplc::device().isRegistered() ? GSM_RESULT::GSM_OK : GSM_RESULT::GSM_NOT_READY;

    gsmplc::Sms message;
    if (!gsmplc::smsTake(message)) return;

    SENDER = message.sender;
    TEXT = message.text;
    INDEX = message.index;

    int64_t seconds = 0;
    if (message.hasTimestamp) {
        // The centre writes its local time and its offset from GMT.
        seconds = gsmplc::unixSeconds(message.timestamp) -
                  (int64_t)message.timestamp.zoneMinutes() * 60;
    }
    SENT_AT = (int64_t)(seconds * 1000000000LL);

    COUNT = (uint32_t)COUNT + 1u;
    RECEIVED = true;
}


END_FUNCTION_BLOCK