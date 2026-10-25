(* Sends one text message when you ask. Acted on the rising edge of REQ.

MODEM       which modem. Must be wired.
REQ         rising edge sends. Holding it TRUE does not send again.
NUMBER      who to, in international form: '+6400000000'. A national number
            is read by whichever network carries the message, which on a
            roaming IoT SIM may not be the country you meant.
TEXT        the message, up to 160 characters. Plain GSM characters - letters,
            digits, common punctuation - fit 160; anything else may not send.

BUSY        a level: the message is with the modem and not yet concluded.
DONE        one scan, when the network has accepted it.
ERROR       one scan, when it failed.
STATUS      why. GSM_OK when fine.
LAST_ERROR  the reason in words - the network's own where it gave one.

---

  alarmSms( MODEM := modem, REQ := highLevel, NUMBER := oncall,
            TEXT := 'Tank 3 high level' );

SMS NEEDS REGISTERED, NOT READY: a message goes over the network's signalling,
not the data connection, so it works on a SIM with no data plan and while the
data connection is down. A REQ before the network has accepted the SIM fails
at once with GSM_NOT_READY rather than waiting.

ONE AT A TIME. A rising edge while BUSY is not a second message; send it after
DONE or ERROR. Every message costs money on most plans, so a REQ wired to a
value that flickers is worth putting behind an R_TRIG and a timer.

DONE and ERROR are one scan wide, so latch them if a slower task has to see
one. BUSY is a level and is the pin to gate a sequence on. *)

FUNCTION_BLOCK GSM_SMS_SEND
  VAR_INPUT
    REQ : BOOL;
    NUMBER : STRING(20);
    TEXT : STRING(160);
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR
  VAR
    fbJob : __XWORD;
    fbLastReq : BOOL;
    fbAsked : BOOL;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    BUSY = false;
    DONE = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    LAST_ERROR = "";
    fbJob = 0;
    fbAsked = false;
}

void loop()
{
    DONE = false;
    ERROR = false;

    const bool rising = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = REQ;
    if (rising && !(bool)BUSY) fbAsked = true;

    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    gsmplc::Job* job = (gsmplc::Job*)(uintptr_t)(strucpp::XWORD_t)fbJob;
    if (job == nullptr) {
        job = gsmplc::newJob();
        fbJob = (strucpp::XWORD_t)(uintptr_t)job;
        if (job == nullptr) {
            ERROR = (bool)fbAsked;
            fbAsked = false;
            STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
            LAST_ERROR = "out of memory";
            return;
        }
    }

    // --- the conclusion of the one in flight ---------------------------------
    if (job->busy) {
        BUSY = true;
        return;
    }
    if (job->done) {
        job->done = false;
        BUSY = false;
        if (job->result.isOk()) {
            DONE = true;
            STATUS = GSM_RESULT::GSM_OK;
            LAST_ERROR = "";
        } else {
            ERROR = true;
            STATUS = (GSM_RESULT)(int)job->result.status();
            LAST_ERROR = gsmplc::describe(job->result);
        }
        return;
    }
    BUSY = false;

    if (!(bool)fbAsked) return;
    fbAsked = false;

    // --- a new one -------------------------------------------------------------
    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        LAST_ERROR = "MODEM is not a running GSM_MODEM";
        return;
    }
    if (NUMBER.length() == 0 || TEXT.length() == 0) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        LAST_ERROR = "set NUMBER and TEXT";
        return;
    }

    const GsmResult accepted = gsmplc::sendSms(*job, NUMBER.c_str(), TEXT.c_str());
    if (accepted.status() == GsmStatus::Queued) {
        BUSY = true;
        STATUS = GSM_RESULT::GSM_QUEUED;
        LAST_ERROR = "";
        return;
    }
    ERROR = true;
    STATUS = (GSM_RESULT)(int)accepted.status();
    LAST_ERROR = accepted.status() == GsmStatus::NotReady
        ? "the network has not accepted the SIM yet"
        : gsmplc::describe(accepted);
}


END_FUNCTION_BLOCK