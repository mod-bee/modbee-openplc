(* Powers the module off, on again, or restarts it - each an operation that
concludes once.

MODEM      which modem. Must be wired.
POWER_OFF  rising edge: shut the module down properly - its own power-down
           command first, then its supply, if the board switches one - and
           keep it off.
POWER_ON   rising edge: let it run again. GSM_MODEM brings it back up,
           pressing the power key if it does not answer.
RESTART    rising edge: restart the module with its own reset command, then
           bring it back up.

POWERED    FALSE from POWER_OFF until POWER_ON. Kept across nothing: a PLC
           restart powers the module up again.
BUSY       a level: an operation is under way.
DONE       one scan, when it has finished.
ERROR      one scan, when it could not.
STATUS     why. GSM_OK when fine.
LAST_ERROR the reason in words.

---

  power( MODEM := modem, POWER_OFF := quietHours, POWER_ON := NOT quietHours );

The library already restarts and power-cycles the module by itself when it
stops answering, so this is not needed to keep a site connected. It is for
the program's own reasons: saving power on a solar site, or a scheduled
restart.

POWER_OFF NEVER CUTS A RUNNING MODULE. The supply goes only after the module
has acknowledged its own power-down command or had its manual's time to
settle: cutting power while it writes to its flash can damage it.

POWER_ON concludes when the module answers - not when it has a data
connection, which GSM_MODEM.READY says. If CONNECT is FALSE on GSM_MODEM the
module stays down and POWER_ON says so. *)

FUNCTION_BLOCK GSM_POWER
  VAR_INPUT
    POWER_OFF : BOOL;
    POWER_ON : BOOL;
    RESTART : BOOL;
  END_VAR
  VAR_OUTPUT
    POWERED : BOOL := TRUE;
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
    fbLastOff : BOOL;
    fbLastOn : BOOL;
    fbLastRestart : BOOL;
    fbAsked : SINT; (* 0 nothing, 1 on, 2 off, 3 reset *)
    fbOp : SINT;
    fbPhase : SINT;
    fbUntil : UDINT;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    POWERED = true;
    BUSY = false;
    DONE = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    LAST_ERROR = "";
    fbJob = 0;
    fbAsked = 0;
    fbOp = 0;
}

void loop()
{
    DONE = false;
    ERROR = false;

    // Edges first, outside the lock. Off wins over a restart, a restart over
    // on, when two arrive together.
    const bool off = (bool)POWER_OFF && !(bool)fbLastOff;
    const bool on = (bool)POWER_ON && !(bool)fbLastOn;
    const bool restart = (bool)RESTART && !(bool)fbLastRestart;
    fbLastOff = POWER_OFF;
    fbLastOn = POWER_ON;
    fbLastRestart = RESTART;
    if ((int8_t)fbOp == 0) {
        if (off) fbAsked = 2;
        else if (restart) fbAsked = 3;
        else if (on) fbAsked = 1;
    }

    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    gsmplc::Job* job = (gsmplc::Job*)(uintptr_t)(strucpp::XWORD_t)fbJob;
    if (job == nullptr) {
        job = gsmplc::newJob();
        fbJob = (strucpp::XWORD_t)(uintptr_t)job;
    }

    GsmDevice& gsm = gsmplc::device();
    const uint32_t now = gsm_millis();
    POWERED = !gsmplc::heldOff();

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || job == nullptr) {
        if ((int8_t)fbAsked != 0) {
            fbAsked = 0;
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
            LAST_ERROR = job == nullptr ? "out of memory" : "MODEM is not a running GSM_MODEM";
        }
        return;
    }

    // --- an operation under way ------------------------------------------------
    const int8_t op = (int8_t)fbOp;
    if (op != 0) {
        BUSY = true;

        if (op == 2) {
            if (job->busy) return;
            // Acknowledged, refused or unanswered: the module has had its
            // command and its time, so the supply may go now.
            const bool answered = job->done && job->result.isOk();
            job->done = false;
            if (gsmplc::hasRail()) gsmplc::railOff();
            fbOp = 0;
            BUSY = false;
            if (answered || gsmplc::hasRail()) {
                DONE = true;
                STATUS = GSM_RESULT::GSM_OK;
                LAST_ERROR = "";
            } else {
                ERROR = true;
                STATUS = (GSM_RESULT)(int)job->result.status();
                LAST_ERROR = "the module did not confirm it powered down";
            }
            return;
        }

        if (op == 1) {
            const GsmState state = gsm.state();
            if (!(bool)MODEM.CONNECT) {
                fbOp = 0;
                BUSY = false;
                ERROR = true;
                STATUS = GSM_RESULT::GSM_NOT_READY;
                LAST_ERROR = "CONNECT is FALSE on GSM_MODEM";
            } else if (state == GsmState::Failed) {
                fbOp = 0;
                BUSY = false;
                ERROR = true;
                STATUS = (GSM_RESULT)(int)gsm.lastError().status();
                LAST_ERROR = gsmplc::describe(gsm.lastError());
            } else if ((int)state >= (int)GsmState::Identifying && state != GsmState::Recovering) {
                fbOp = 0;
                BUSY = false;
                DONE = true;
                STATUS = GSM_RESULT::GSM_OK;
                LAST_ERROR = "";
            } else if (!gsm_isFuture(now, (uint32_t)fbUntil)) {
                fbOp = 0;
                BUSY = false;
                ERROR = true;
                STATUS = GSM_RESULT::GSM_TIMEOUT;
                LAST_ERROR = "the module did not answer after power on";
            }
            return;
        }

        // op == 3, a restart: the command, then the module's reboot time.
        if ((int8_t)fbPhase == 0) {
            if (job->busy) return;
            job->done = false;
            if (!job->result.isOk()) {
                // A module that does not answer its reset is the one a restart
                // is for: start the bring-up again, which powers it up afresh.
                gsm.stop();
                if ((bool)MODEM.CONNECT && !gsmplc::heldOff()) gsm.start();
                fbOp = 0;
                BUSY = false;
                ERROR = true;
                STATUS = (GSM_RESULT)(int)job->result.status();
                LAST_ERROR = gsmplc::describe(job->result);
                return;
            }
            // Left alone while it reboots: talking to it, or pressing its key,
            // in the middle of a boot is how a module ends up off.
            gsm.stop();
            const GsmProfile* profile = gsm.profile();
            const uint32_t settle = profile != nullptr && profile->resetSettleMs > 0
                ? profile->resetSettleMs : 3000u;
            fbUntil = now + settle;
            fbPhase = 1;
            return;
        }
        if (gsm_isFuture(now, (uint32_t)fbUntil)) return;
        if ((bool)MODEM.CONNECT && !gsmplc::heldOff()) gsm.start();
        fbOp = 0;
        BUSY = false;
        DONE = true;
        STATUS = GSM_RESULT::GSM_OK;
        LAST_ERROR = "";
        return;
    }

    BUSY = false;
    const int8_t asked = (int8_t)fbAsked;
    fbAsked = 0;
    if (asked == 0) return;

    // --- a new operation -------------------------------------------------------
    if (asked == 2) {
        gsmplc::holdOff(true);
        POWERED = false;
        if (!gsmplc::isOpen() || gsm.driver() == nullptr) {
            // It never answered, so there is nothing to tell it; the supply,
            // where there is one, is all there is.
            gsm.stop();
            if (gsmplc::hasRail()) gsmplc::railOff();
            DONE = true;
            STATUS = GSM_RESULT::GSM_OK;
            LAST_ERROR = "";
            return;
        }
        gsm.stop();
        GsmCmdBuf command;
        gsm.driver()->powerDownCommand(command);
        const GsmProfile* profile = gsm.profile();
        const uint32_t settle = profile != nullptr ? profile->powerOffSettleMs : 3000u;
        if (command.isEmpty() || command.overflowed() ||
            gsmplc::sendAt(*job, command.text(), 9000u + settle).status() != GsmStatus::Queued) {
            job->busy = false;
            job->done = false;
            job->result = GsmStatus::NotSupportedByModule;
        }
        fbOp = 2;
        BUSY = true;
        return;
    }

    if (asked == 1) {
        gsmplc::holdOff(false);
        POWERED = true;
        fbOp = 1;
        fbUntil = now + 90000u;
        BUSY = true;
        return;
    }

    // asked == 3
    if (!gsmplc::isOpen() || gsm.driver() == nullptr) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_READY;
        LAST_ERROR = "the module has not answered yet";
        return;
    }
    GsmCmdBuf command;
    gsm.driver()->resetCommand(command);
    const GsmResult accepted = command.isEmpty() || command.overflowed()
        ? GsmResult(GsmStatus::NotSupportedByModule)
        : gsmplc::sendAt(*job, command.text(), 9000u);
    if (accepted.status() != GsmStatus::Queued) {
        ERROR = true;
        STATUS = (GSM_RESULT)(int)accepted.status();
        LAST_ERROR = gsmplc::describe(accepted);
        return;
    }
    fbOp = 3;
    fbPhase = 0;
    BUSY = true;
}


END_FUNCTION_BLOCK