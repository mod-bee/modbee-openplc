(* Keeps the radio off to save power, and brings it back when asked.

bEnable       keep the radio off except when woken.
bWakeNow      rising edge, bring it back now.
tStayAwakeTime  how long it stays up once woken.
tWakeInterval    also bring it back this often. T#0s for only on bWakeNow.

bRadioOn      the radio should be powered. Wire this to FB_WiFiNetwork's bEnable.
tAwakeTimeLeft  how long before it powers down again.

---

The radio is the biggest steady draw on the board, and a machine that only needs
to be reachable now and then does not need it running all day. With bEnable set
the radio is meant to be off; a rising edge on bWakeNow brings it back for tStayAwakeTime
seconds, and it goes again when that runs out.

Wire it to the button and the network:

  btn();
  wifiSleep(bEnable := TRUE, bWakeNow := btn.bShortPress, tStayAwakeTime := T#5m);
  net(bEnable := wifiSleep.bRadioOn, sSsid := 'plant', sWiFiPassword := 'secret');

Press the button, the network comes up for five minutes, then powers down.

bRadioOn is what decides it, so you can drive FB_WiFiNetwork from anything else as
well: a shift starting, a fault, a level switch. bWakeNow takes any signal, not just
the button.

tWakeInterval brings the radio back on its own that often, for boards that should
phone home whether or not anyone is there.

Clearing bEnable hands the radio back: bRadioOn stays true and the network stops
being duty-cycled. *)

FUNCTION_BLOCK FB_WiFiSleep
  VAR_INPUT
    bEnable : BOOL; (* keep the radio off except when woken *)
    bWakeNow : BOOL; (* rising edge: bring the radio back now *)
    tStayAwakeTime : TIME := T#5m; (* how long it stays up once woken *)
    tWakeInterval : TIME; (* also bring it back this often; T#0s = only on bWakeNow *)
  END_VAR
  VAR_OUTPUT
    bRadioOn : BOOL; (* the radio should be powered: wire to FB_WiFiNetwork's bEnable *)
    tAwakeTimeLeft : TIME; (* time before it powers down again *)
  END_VAR
  VAR
    lastWake : BOOL;
  END_VAR
#include <NodeUioAPI.h>

// Defined in FB_NodeUio.cpp. Every C++ POU lands in ONE translation unit in
// filename order, so the declaration is written rather than assumed.
uint32_t uio_millisOf(const strucpp::IEC_TIME& t);
uint32_t uio_secondsOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME uio_timeOfMs(uint32_t milliseconds);
strucpp::IEC_TIME uio_timeOfS(uint32_t seconds);

void setup()
{
  bRadioOn = true;
  tAwakeTimeLeft = uio_timeOfS(0);
  lastWake = false;
}

void loop()
{
  uio().setRadioPolicy((bool)bEnable, uio_secondsOf(tStayAwakeTime), uio_secondsOf(tWakeInterval));

  if ((bool)bWakeNow && !(bool)lastWake) uio().requestRadio();
  lastWake = (bool)bWakeNow;

  bRadioOn = uio().radioWanted();
  tAwakeTimeLeft = uio_timeOfS(uio().radioAwakeLeft());
}

END_FUNCTION_BLOCK