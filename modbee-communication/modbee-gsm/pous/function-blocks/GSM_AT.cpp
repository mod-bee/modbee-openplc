(* Sends one AT command of your own and hands back the reply. The escape hatch
for the module command nothing else here covers.

MODEM       which modem. Must be wired.
REQ         rising edge sends COMMAND.
COMMAND     the command, without the line ending: 'AT+CSQ'. Up to 127
            characters.
TIMEOUT     how long the module has to answer. Default T#5s; the module's
            manual gives each command's own limit, up to minutes for a
            network scan. At most T#180s.

BUSY        a level: the command is queued or with the module.
DONE        one scan, when the module answered OK.
ERROR       one scan, when it answered ERROR, gave no answer in time, or
            could not be sent.
REPLY       every line the module answered before its OK or ERROR, one line
            to a line, up to 254 characters.
STATUS      why. GSM_OK when fine.
LAST_ERROR  the reason in words - '+CME ERROR: 10, SIM not inserted' rather
            than a number.

---

  ask( MODEM := modem, REQ := askNow, COMMAND := 'AT+CPSI?' );
  IF ask.DONE THEN servingCell := ask.REPLY; END_IF;

THE COMMAND JOINS THE MODEM'S OWN QUEUE. It waits its turn behind whatever
the library is doing, is timed like everything else, and concludes exactly
once. Nothing blocks.

IT CAN UNDO THE LIBRARY. A command that turns the radio off, changes the
serial speed or closes the data connection does exactly that, and the modem
block then recovers from it as from any other fault. Reading is safe; writing
settings is your responsibility.

A command the library sends itself works too, and costs nothing extra. *)

FUNCTION_BLOCK GSM_AT
  VAR_INPUT
    REQ : BOOL;
    COMMAND : STRING(127);
    TIMEOUT : TIME := T#5s;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    ERROR : BOOL;
    REPLY : STRING(254);
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

    if (job->busy) {
        BUSY = true;
        return;
    }
    if (job->done) {
        job->done = false;
        BUSY = false;
        REPLY = job->reply;
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

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        LAST_ERROR = "MODEM is not a running GSM_MODEM";
        return;
    }
    if (COMMAND.length() == 0) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        LAST_ERROR = "set COMMAND";
        return;
    }
    if (gsmplc::device().driver() == nullptr) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_READY;
        LAST_ERROR = "the module has not answered yet";
        return;
    }

    uint32_t limit = gsmplc::millisOf(TIMEOUT.get());
    if (limit == 0) limit = 5000u;
    if (limit > 180000u) limit = 180000u;

    const GsmResult accepted = gsmplc::sendAt(*job, COMMAND.c_str(), limit);
    if (accepted.status() == GsmStatus::Queued) {
        BUSY = true;
        REPLY = "";
        STATUS = GSM_RESULT::GSM_QUEUED;
        LAST_ERROR = "";
        return;
    }
    ERROR = true;
    STATUS = (GSM_RESULT)(int)accepted.status();
    LAST_ERROR = gsmplc::describe(accepted);
}


END_FUNCTION_BLOCK