(* What the modem knows about itself and its network, for a diagnostic page.

MODEM          which modem. Must be wired.
REFRESH        how often to ask the module for its signal and registration.
               T#0s never asks; the values then change only when the module
               reports something by itself. Default T#30s.

RSSI           received signal strength, dBm. -113 is nothing, -51 is
               excellent. -32768 until the first reading.
RSRP           LTE reference signal power, dBm (-140 to -44), or -32768 when
               the module does not report it.
RSRQ           LTE reference signal quality, dB (-20 to -3), or -32768.
QUALITY        the signal judged: GSM_QUALITY_GOOD above -95 dBm,
               GSM_QUALITY_UNCERTAIN down to -105, GSM_QUALITY_BAD below.
REGISTRATION   what the network says about the SIM: home, roaming, searching,
               denied.
TECHNOLOGY     the radio in use: GSM_TECH_LTE, GSM_TECH_CAT_M and the rest.
OPERATOR       the network's name as the module reports it.
IP             the address the network gave this modem.
IMEI           the module's serial number.
ICCID          the SIM's serial number - the one printed on the card.
MODULE         the module family the library recognised, e.g. 'A76XX'.
FIRMWARE       the module's firmware revision.
SOCKETS_FREE   sockets still free for GSM_SOCKET and MQTT.
BRING_UPS      times the modem has been brought up since the PLC started.
RECOVERIES     times the library has had to recover it.
BEARER_LOSSES  times the data connection dropped.
REGISTRATION_LOSSES  times the network dropped the SIM.

---

  status( MODEM := modem );

Reading this block costs nothing: the values are the ones the modem block
already holds. Only REFRESH sends anything to the module - three short
queries, and a query still waiting is replaced rather than repeated, so a
short REFRESH cannot build a backlog. Nothing here uses data on the SIM.

A COUNTER THAT KEEPS CLIMBING IS THE THING TO WATCH. One bring-up and no
recoveries is a healthy site. RECOVERIES or BEARER_LOSSES rising by the hour
is an antenna, a marginal signal or a network that is moving the SIM about -
usually visible as RSSI near -105 and QUALITY GSM_QUALITY_BAD. *)

FUNCTION_BLOCK GSM_STATUS
  VAR_INPUT
    REFRESH : TIME := T#30s;
  END_VAR
  VAR_OUTPUT
    RSSI : INT := -32768;
    RSRP : INT := -32768;
    RSRQ : INT := -32768;
    QUALITY : GSM_QUALITY;
    REGISTRATION : GSM_REGISTRATION;
    TECHNOLOGY : GSM_TECHNOLOGY;
    OPERATOR : STRING(32);
    IP : STRING(46);
    IMEI : STRING(20);
    ICCID : STRING(24);
    MODULE : STRING(16);
    FIRMWARE : STRING(48);
    SOCKETS_FREE : USINT;
    BRING_UPS : UDINT;
    RECOVERIES : UDINT;
    BEARER_LOSSES : UDINT;
    REGISTRATION_LOSSES : UDINT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR
  VAR
    fbAskedAt : UDINT;
    fbAsked : BOOL;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    fbAsked = false;
}

void loop()
{
    gsmplc::TryHold hold;
    if (!hold.owned()) return;
    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) return;

    GsmDevice& gsm = gsmplc::device();

    const uint32_t period = gsmplc::millisOf(REFRESH.get());
    const uint32_t now = gsm_millis();
    if (period > 0 && gsm.isRegistered() &&
        (!(bool)fbAsked || (uint32_t)(now - (uint32_t)fbAskedAt) >= period)) {
        gsm.refreshStatus();
        fbAskedAt = now;
        fbAsked = true;
    }

    // -32768 is "never read", and it fits an INT exactly.
    RSSI = (int16_t)gsm.rssiDbm();
    RSRP = (int16_t)gsm.rsrpDbm();
    RSRQ = (int16_t)gsm.rsrqDb();
    QUALITY = (GSM_QUALITY)(int)gsm.signalQuality();
    REGISTRATION = (GSM_REGISTRATION)(int)gsm.registration();
    TECHNOLOGY = (GSM_TECHNOLOGY)(int)gsm.technology();
    OPERATOR = gsm.operatorName();
    IP = gsm.ipAddress();
    IMEI = gsm.imei();
    ICCID = gsm.iccid();
    MODULE = gsm.module();
    FIRMWARE = gsm.firmware();
    SOCKETS_FREE = (uint8_t)gsm.socketsAvailable();

    const GsmModem::Counters& counters = gsm.counters();
    BRING_UPS = counters.bringUps;
    RECOVERIES = counters.recoveries;
    BEARER_LOSSES = counters.bearerLosses;
    REGISTRATION_LOSSES = counters.registrationLosses;
}


END_FUNCTION_BLOCK