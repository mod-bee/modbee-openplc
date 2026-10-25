(* The time, from the mobile network. Costs no data: the network sets the
module's clock when it registers.

MODEM      which modem. Must be wired.
REFRESH    how often to read the module's clock. Default T#1h; between reads
           the time is carried forward on the PLC's own clock.

VALID      the network has set the clock, and it has been read.
UTC        the time now, in UTC.
LOCAL      the time now, as the network's time zone has it.
ZONE       the network's offset from UTC, in minutes: 780 is New Zealand
           summer time, 720 its winter.
AGE        how long ago the module's clock was last read.
ERROR      the module could not be asked, or MODEM is not a running
           GSM_MODEM.
STATUS     why. GSM_OK when fine.

---

  clock( MODEM := modem );
  IF clock.VALID THEN stamp := clock.UTC; END_IF;

NOT EVERY NETWORK SENDS THE TIME. The module learns it only from a network
that broadcasts it, and some never do - on those VALID stays FALSE, because a
clock still at the module's factory date is not a time. It is read again on
every REFRESH, so a SIM that roams onto a network that does send it becomes
VALID by itself.

It is accurate to about a second: good for timestamps, schedules and a
time-of-day interlock, not for anything that needs better. *)

FUNCTION_BLOCK GSM_TIME
  VAR_INPUT
    REFRESH : TIME := T#1h;
  END_VAR
  VAR_OUTPUT
    VALID : BOOL;
    UTC : DT;
    LOCAL : DT;
    ZONE : INT;
    AGE : TIME;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR
  VAR
    fbAskedAt : UDINT;
    fbAsked : BOOL;
    fbGeneration : UDINT;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    VALID = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    fbAsked = false;
}

void loop()
{
    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        VALID = false;
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        return;
    }

    GsmDevice& gsm = gsmplc::device();
    const uint32_t now = gsm_millis();

    // Asked once the network has had its chance to set the clock, again on
    // every REFRESH, and again after anything that restarted the module.
    if (gsm.isRegistered()) {
        const uint32_t period = gsmplc::millisOf(REFRESH.get());
        const bool due = !(bool)fbAsked ||
                         (uint32_t)fbGeneration != gsmplc::generation() ||
                         (period > 0 && (uint32_t)(now - (uint32_t)fbAskedAt) >= period);
        if (due) {
            const GsmResult asked = gsm.refreshTime();
            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                fbAsked = true;
                fbAskedAt = now;
                fbGeneration = gsmplc::generation();
                ERROR = false;
                STATUS = GSM_RESULT::GSM_OK;
            } else if (asked.status() == GsmStatus::NotSupportedByModule) {
                ERROR = true;
                STATUS = GSM_RESULT::GSM_NOT_SUPPORTED_BY_MODULE;
            }
        }
    } else if (!(bool)VALID) {
        STATUS = GSM_RESULT::GSM_NOT_READY;
    }

    if (!gsm.hasNetworkTime()) {
        VALID = false;
        return;
    }

    // A module whose clock nobody set reports its factory date - 1980, 2000,
    // 2070 depending on the family. Not a time, so not VALID.
    const GsmParse::GsmDateTime& read = gsm.networkTime();
    if (read.year < 2024 || read.year > 2099 || read.month < 1 || read.month > 12 ||
        read.day < 1 || read.day > 31) {
        VALID = false;
        return;
    }

    const uint32_t ageMs = gsm.networkTimeAgeMillis();
    const int64_t zoneMinutes = (int64_t)read.zoneMinutes();
    const int64_t localNs = gsmplc::unixSeconds(read) * 1000000000LL + gsmplc::nanosOf(ageMs);
    LOCAL = localNs;
    UTC = localNs - zoneMinutes * 60LL * 1000000000LL;
    ZONE = (int16_t)zoneMinutes;
    AGE = gsmplc::nanosOf(ageMs);
    VALID = true;
}


END_FUNCTION_BLOCK