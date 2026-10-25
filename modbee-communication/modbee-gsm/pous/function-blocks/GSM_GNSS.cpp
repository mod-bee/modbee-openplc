(* Where the module is, from its own satellite receiver - where it has one.

MODEM       which modem. Must be wired.
ENABLE      TRUE powers the receiver and reads it. FALSE powers it down.
REFRESH     how often to read the fix. Default T#5s.

SUPPORTED   the module has a receiver and accepted the request. FALSE on a
            module without one, which is said here and on STATUS rather
            than by a fix that never comes.
FIX         a position is known and current.
LATITUDE    degrees, north positive.
LONGITUDE   degrees, east positive.
ALTITUDE    metres above sea level.
SATELLITES  satellites the receiver can see.
AGE         how long ago the fix was last confirmed. T#0s before the first.
ERROR       the module refused, or MODEM is not a running GSM_MODEM.
STATUS      why. GSM_OK when fine.

---

  where( MODEM := modem, ENABLE := TRUE );

AGE IS THE PIN TO ALARM ON, NOT FIX. A receiver that loses the sky keeps its
last position, and a position an hour old looks exactly like a current one.

A FIRST FIX TAKES TIME. From cold, with a clear view of the sky, expect a
minute or more; indoors, perhaps never. The receiver needs its own antenna on
the module's GNSS connector - the cellular antenna does not serve it.

Reading the receiver costs nothing on the SIM. Some modules share one radio
between the network and the receiver, and a fix there can interrupt data for
a moment while the receiver is powered.

If the module restarts - which the modem block may do on its own to recover -
the receiver is powered again by itself. *)

FUNCTION_BLOCK GSM_GNSS
  VAR_INPUT
    ENABLE : BOOL;
    REFRESH : TIME := T#5s;
  END_VAR
  VAR_OUTPUT
    SUPPORTED : BOOL;
    FIX : BOOL;
    LATITUDE : LREAL;
    LONGITUDE : LREAL;
    ALTITUDE : REAL;
    SATELLITES : USINT;
    AGE : TIME;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR
  VAR
    fbPowered : BOOL;
    fbGeneration : UDINT;
    fbAskedAt : UDINT;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    SUPPORTED = false;
    FIX = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    fbPowered = false;
    fbGeneration = 0;
}

void loop()
{
    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        FIX = false;
        ERROR = (bool)ENABLE;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        return;
    }

    GsmDevice& gsm = gsmplc::device();
    const uint32_t now = gsm_millis();

    // Not until the module has said what it is: whether it has a receiver is
    // learned from its answers, not assumed.
    if (gsm.driver() == nullptr) {
        FIX = false;
        ERROR = false;
        STATUS = GSM_RESULT::GSM_NOT_READY;
        return;
    }

    if ((bool)ENABLE) {
        // Powered again after anything that may have restarted the module.
        if (!(bool)fbPowered || (uint32_t)fbGeneration != gsmplc::generation()) {
            const GsmResult asked = gsm.gnss(true);
            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                fbPowered = true;
                fbGeneration = gsmplc::generation();
                fbAskedAt = now;
            } else if (asked.status() == GsmStatus::NotSupportedByModule) {
                SUPPORTED = false;
                FIX = false;
                ERROR = true;
                STATUS = GSM_RESULT::GSM_NOT_SUPPORTED_BY_MODULE;
                return;
            }
        }
        const uint32_t period = gsmplc::millisOf(REFRESH.get());
        if (gsm.gnssLayer().isPowered() &&
            (uint32_t)(now - (uint32_t)fbAskedAt) >= (period > 0 ? period : 1000u)) {
            gsm.refreshFix();
            fbAskedAt = now;
        }
    } else if ((bool)fbPowered) {
        gsm.gnss(false);
        fbPowered = false;
    }

    SUPPORTED = gsm.hasGnssReceiver();
    if ((bool)ENABLE && !(bool)SUPPORTED && (bool)fbPowered && !gsm.gnssLayer().isPowered()) {
        // The module answered the power request with a refusal.
        ERROR = true;
        STATUS = GSM_RESULT::GSM_NOT_SUPPORTED_BY_MODULE;
    } else {
        ERROR = false;
        STATUS = GSM_RESULT::GSM_OK;
    }

    const GsmFix& fix = gsm.fix();
    FIX = gsm.hasFix();
    if (fix.hasPosition) {
        LATITUDE = fix.latitude;
        LONGITUDE = fix.longitude;
        SATELLITES = fix.satellitesInView;
    }
    if (fix.hasAltitude) ALTITUDE = (float)fix.altitudeMetres;

    const uint32_t age = gsm.fixAgeMillis();
    AGE = age == 0xFFFFFFFFu ? (int64_t)0 : gsmplc::nanosOf(age);
}


END_FUNCTION_BLOCK