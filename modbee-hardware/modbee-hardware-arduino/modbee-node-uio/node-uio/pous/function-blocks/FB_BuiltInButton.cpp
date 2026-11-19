(* The button built into the board, beside the antenna.

tDebounceTime  ignore anything shorter than this. T#30ms suits most buttons.
tLongPressDelay  hold this long and it is a long press.

bPressed     held down right now.
bShortPress  one scan, on release before tLongPressDelay.
bLongPress   one scan, the moment the hold passes tLongPressDelay.
tHeldTime    how long it has been held. T#0s when released.

---

Also wired to the HAT header, so a HAT can press it too. There is one, so use one
instance of this block: the presses are consumed as they are read, and a second
instance would take the ones the first never saw.

The silkscreen calls it the WiFi button, and waking the radio is what it is there
for. Tie bShortPress to the bWakeNow pin of FB_WiFiSleep and that is the whole job.
Nothing enforces it though; the presses are reported and your program decides.

Both durations are yours. tDebounceTime keeps contact bounce from looking like a
press; tLongPressDelay is where a short press becomes a long one. *)

FUNCTION_BLOCK FB_BuiltInButton
  VAR_INPUT
    tDebounceTime : TIME := T#30ms; (* ignore anything shorter than this; T#30ms suits most buttons *)
    tLongPressDelay : TIME := T#2s; (* held this long it is a long press *)
  END_VAR
  VAR_OUTPUT
    bPressed : BOOL; (* held down right now *)
    bShortPress : BOOL; (* one scan, on release before tLongPressDelay *)
    bLongPress : BOOL; (* one scan, the moment the hold passes tLongPressDelay *)
    tHeldTime : TIME; (* how long it has been held; T#0s when released *)
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
  bPressed = false;
  bShortPress = false;
  bLongPress = false;
  tHeldTime = uio_timeOfMs(0);
}

void loop()
{
  uio().setButtonDebounceMs(uio_millisOf(tDebounceTime));
  uio().setButtonLongMs(uio_millisOf(tLongPressDelay));

  bPressed = uio().button();
  tHeldTime = uio_timeOfMs(uio().buttonHeldMs());
  bShortPress = uio().takeShortPress();
  bLongPress = uio().takeLongPress();
}

END_FUNCTION_BLOCK