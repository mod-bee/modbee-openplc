(* Keeps the radio off to save power, and brings it back when asked.

ENABLE        keep the radio off except when woken.
WAKE          rising edge, bring it back now.
AWAKE         how long it stays up once woken.
WAKE_EVERY    also bring it back this often. T#0s for only on WAKE.

RADIO_ON      the radio should be powered. Wire this to NETWORK's ENABLE.
AWAKE_LEFT    how long before it powers down again.

---

The radio is the biggest steady draw on the board, and a machine that only needs
to be reachable now and then does not need it running all day. With ENABLE set
the radio is meant to be off; a rising edge on WAKE brings it back for AWAKE
seconds, and it goes again when that runs out.

Wire it to the button and the network:

  btn();
  wifiSleep(ENABLE := TRUE, WAKE := btn.SHORT_PRESS, AWAKE := T#5m);
  net(ENABLE := wifiSleep.RADIO_ON, SSID := 'plant', PASSWORD := 'secret');

Press the button, the network comes up for five minutes, then powers down.

RADIO_ON is what decides it, so you can drive NETWORK from anything else as
well: a shift starting, a fault, a level switch. WAKE takes any signal, not just
the button.

WAKE_EVERY brings the radio back on its own that often, for boards that should
phone home whether or not anyone is there.

Clearing ENABLE hands the radio back: RADIO_ON stays true and the network stops
being duty-cycled. *)

FUNCTION_BLOCK WIFI_SLEEP
  VAR_INPUT
    ENABLE : BOOL;
    WAKE : BOOL;
    AWAKE : TIME := T#5m;
    WAKE_EVERY : TIME;
  END_VAR
  VAR_OUTPUT
    RADIO_ON : BOOL;
    AWAKE_LEFT : TIME;
  END_VAR
  VAR
    lastWake : BOOL;
  END_VAR
#include <NodeUioAPI.h>

// Defined in UIO.cpp. Every C++ POU lands in ONE translation unit in
// filename order, so the declaration is written rather than assumed.
uint32_t uio_millisOf(const strucpp::IEC_TIME& t);
uint32_t uio_secondsOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME uio_timeOfMs(uint32_t milliseconds);
strucpp::IEC_TIME uio_timeOfS(uint32_t seconds);

void setup()
{
  RADIO_ON = true;
  AWAKE_LEFT = uio_timeOfS(0);
  lastWake = false;
}

void loop()
{
  uio().setRadioPolicy((bool)ENABLE, uio_secondsOf(AWAKE), uio_secondsOf(WAKE_EVERY));

  if ((bool)WAKE && !(bool)lastWake) uio().requestRadio();
  lastWake = (bool)WAKE;

  RADIO_ON = uio().radioWanted();
  AWAKE_LEFT = uio_timeOfS(uio().radioAwakeLeft());
}

END_FUNCTION_BLOCK