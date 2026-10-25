(* The button built into the board, beside the antenna.

DEBOUNCE     ignore anything shorter than this. T#30ms suits most buttons.
LONG         hold this long and it is a long press.

PRESSED      held down right now.
SHORT_PRESS  one scan, on release before LONG.
LONG_PRESS   one scan, the moment the hold passes LONG.
HELD         how long it has been held. T#0s when released.

---

Also wired to the HAT header, so a HAT can press it too. There is one, so use one
instance of this block: the presses are consumed as they are read, and a second
instance would take the ones the first never saw.

The silkscreen calls it the WiFi button, and waking the radio is what it is there
for. Tie SHORT_PRESS to the WAKE pin of WIFI_SLEEP and that is the whole job.
Nothing enforces it though; the presses are reported and your program decides.

Both durations are yours. DEBOUNCE keeps contact bounce from looking like a
press; LONG is where a short press becomes a long one. *)

FUNCTION_BLOCK BUILTIN_BUTTON
  VAR_INPUT
    DEBOUNCE : TIME := T#30ms;
    LONG : TIME := T#2s;
  END_VAR
  VAR_OUTPUT
    PRESSED : BOOL;
    SHORT_PRESS : BOOL;
    LONG_PRESS : BOOL;
    HELD : TIME;
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
  PRESSED = false;
  SHORT_PRESS = false;
  LONG_PRESS = false;
  HELD = uio_timeOfMs(0);
}

void loop()
{
  uio().setButtonDebounceMs(uio_millisOf(DEBOUNCE));
  uio().setButtonLongMs(uio_millisOf(LONG));

  PRESSED = uio().button();
  HELD = uio_timeOfMs(uio().buttonHeldMs());
  SHORT_PRESS = uio().takeShortPress();
  LONG_PRESS = uio().takeLongPress();
}

END_FUNCTION_BLOCK