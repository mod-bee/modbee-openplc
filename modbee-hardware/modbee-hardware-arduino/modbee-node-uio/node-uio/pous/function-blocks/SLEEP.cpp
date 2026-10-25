(* Puts the board to sleep, and says what woke it.

TRIGGER            one shot, sleep now.
MODE               which kind of sleep.
                     UIO_LIGHT_SLEEP  returns where it left off
                     UIO_DEEP_SLEEP   restarts the program
SECONDS            wake after this long. 0 for no timer.
EN_WAKE_DI01..08   use this input as a wake source.
DO01_IN_SLEEP..04  the level DO01 to DO04 hold while asleep.
HAT_IN_SLEEP       whether the HAT stays powered while asleep.
LED_IN_SLEEP       whether the status LED stays lit while asleep.

WAKE_CAUSE         what ended the last sleep, or what started this run.
                     UIO_WAKE_NONE, UIO_WAKE_TIMER, UIO_WAKE_INPUT,
                     UIO_WAKE_RESET
ERROR              the request was refused.
STATUS             why.
                     UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT,
                     UIO_IO_ERROR, UIO_NO_DATA, UIO_TOO_LARGE,
                     UIO_UNSUPPORTED

---

Light sleep returns where it left off, so the program carries on with its
variables intact and every output stays as it was. Deep sleep does not return:
the board restarts from the top, and WAKE_CAUSE is what tells you it had been
asleep rather than freshly powered.

RETAINED VALUES. Deep sleep restarts the program, so the block has the firmware
save the retained values first (OpenPLC's built-in store), as a PLC stop would;
the sleep starts once that save is done, about 10 to 50 ms later. Light sleep
keeps every variable in RAM and saves nothing extra: a change the store is
holding is saved after the board wakes, so a power cut during a long light
sleep can lose it.

SECONDS sets a timer. Each EN_WAKE_DInn arms one input as a wake source, and any
armed input going high wakes the board. Use as many as you like, with the timer
or instead of it, but set at least one or there would be no way back and the
request is refused.

WHAT THE OUTPUTS DO WHILE ASLEEP

DO01 to DO04 can hold a level through deep sleep, and DO01_IN_SLEEP to
DO04_IN_SLEEP say which level each one holds. They are driven to that state just
before sleeping, so a valve can stay open or a heater stay off, whichever the
machine needs.

DO05 to DO08 cannot. They are GPIO 33-36, outside the part's RTC domain, and
drop when it sleeps whatever they were set to. That is the silicon, not a
setting, so plan for those four going off. If something must stay energised
through a sleep, wire it to DO01 to DO04.

On light sleep every pin keeps its level anyway; the four DO0n_IN_SLEEP pins are
still applied, so the same wiring behaves the same way in both modes.

HAT_IN_SLEEP holds the HAT rail the same way, so a sensor that has to keep its
state through the sleep can stay powered. It costs whatever the HAT draws for
the whole sleep, so leave it off unless something needs it.

LED_IN_SLEEP lights the status LED dim blue for the sleep, so a board that is
asleep can be told from one that is dead. It is off by default, like the other
IN_SLEEP pins: the LED draws for the whole sleep. Either way the LED returns to
green on waking without being asked. The part latches its colour on its own
supply, so it holds through a deep sleep with no pin held for it.

Dimming it only takes the current the die draws. The driver behind it draws its
own regardless, so the saving between a dim LED and a dark one is smaller than
the saving between either and cutting its supply. *)

FUNCTION_BLOCK SLEEP
  VAR_INPUT
    TRIGGER : BOOL;
    MODE : UIO_SLEEP;
    SECONDS : UDINT;
    EN_WAKE_DI01 : BOOL;
    EN_WAKE_DI02 : BOOL;
    EN_WAKE_DI03 : BOOL;
    EN_WAKE_DI04 : BOOL;
    EN_WAKE_DI05 : BOOL;
    EN_WAKE_DI06 : BOOL;
    EN_WAKE_DI07 : BOOL;
    EN_WAKE_DI08 : BOOL;
    DO01_IN_SLEEP : BOOL;
    DO02_IN_SLEEP : BOOL;
    DO03_IN_SLEEP : BOOL;
    DO04_IN_SLEEP : BOOL;
    HAT_IN_SLEEP : BOOL;
    LED_IN_SLEEP : BOOL;
  END_VAR
  VAR_OUTPUT
    WAKE_CAUSE : UIO_WAKE;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    lastTrigger : BOOL;
  END_VAR
#include <NodeUioAPI.h>

UIO_RESULT uio_status(UioResult result);

void setup()
{
  WAKE_CAUSE = UIO_WAKE::UIO_WAKE_NONE;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  lastTrigger = false;
}

void loop()
{
  WAKE_CAUSE = (UIO_WAKE)(uint8_t)uio().wakeCause();

  if ((bool)TRIGGER && !(bool)lastTrigger) {
    // The pins are the user's surface; the mask is the library's.
    uint8_t wake = 0;
    if ((bool)EN_WAKE_DI01) wake |= 1 << 0;
    if ((bool)EN_WAKE_DI02) wake |= 1 << 1;
    if ((bool)EN_WAKE_DI03) wake |= 1 << 2;
    if ((bool)EN_WAKE_DI04) wake |= 1 << 3;
    if ((bool)EN_WAKE_DI05) wake |= 1 << 4;
    if ((bool)EN_WAKE_DI06) wake |= 1 << 5;
    if ((bool)EN_WAKE_DI07) wake |= 1 << 6;
    if ((bool)EN_WAKE_DI08) wake |= 1 << 7;

    const bool held[UIO_HOLDABLE_OUTPUTS] = {
      (bool)DO01_IN_SLEEP, (bool)DO02_IN_SLEEP,
      (bool)DO03_IN_SLEEP, (bool)DO04_IN_SLEEP,
    };

    const UioResult result = uio().sleep((UioSleepMode)(UIO_SLEEP)MODE,
                                         (uint32_t)SECONDS, wake,
                                         (bool)HAT_IN_SLEEP, (bool)LED_IN_SLEEP,
                                         held);
    ERROR = (result != UIO_OK);
    STATUS = uio_status(result);
    WAKE_CAUSE = (UIO_WAKE)(uint8_t)uio().wakeCause();
  }
  lastTrigger = (bool)TRIGGER;
}

END_FUNCTION_BLOCK