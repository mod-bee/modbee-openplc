(* Puts the board to sleep, and says what woke it.

bExecute           one shot, sleep now.
eSleepMode         which kind of sleep.
                     UIO_LIGHT_SLEEP  returns where it left off
                     UIO_DEEP_SLEEP   restarts the program
nWakeAfterSeconds  wake after this long. 0 for no timer.
bWakeOnDI01..08   use this input as a wake source.
bDO01DuringSleep..04  the level DO01 to DO04 hold while asleep.
bHatPoweredDuringSleep  whether the HAT stays powered while asleep.
bLedOnDuringSleep  whether the status LED stays lit while asleep.

eWakeCause         what ended the last sleep, or what started this run.
                     UIO_WAKE_NONE, UIO_WAKE_TIMER, UIO_WAKE_INPUT,
                     UIO_WAKE_RESET
bError             the request was refused.
eErrorId           why.
                     UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT,
                     UIO_IO_ERROR, UIO_NO_DATA, UIO_TOO_LARGE,
                     UIO_UNSUPPORTED

---

Light sleep returns where it left off, so the program carries on with its
variables intact and every output stays as it was. Deep sleep does not return:
the board restarts from the top, and eWakeCause is what tells you it had been
asleep rather than freshly powered.

RETAINED VALUES. Deep sleep restarts the program, so the block has the firmware
save the retained values first (OpenPLC's built-in store), as a PLC stop would;
the sleep starts once that save is done, about 10 to 50 ms later. Light sleep
keeps every variable in RAM and saves nothing extra: a change the store is
holding is saved after the board wakes, so a power cut during a long light
sleep can lose it.

nWakeAfterSeconds sets a timer. Each EN_WAKE_DInn arms one input as a wake source, and any
armed input going high wakes the board. Use as many as you like, with the timer
or instead of it, but set at least one or there would be no way back and the
request is refused.

WHAT THE OUTPUTS DO WHILE ASLEEP

DO01 to DO04 can hold a level through deep sleep, and bDO01DuringSleep to
bDO04DuringSleep say which level each one holds. They are driven to that state just
before sleeping, so a valve can stay open or a heater stay off, whichever the
machine needs.

DO05 to DO08 cannot. They are GPIO 33-36, outside the part's RTC domain, and
drop when it sleeps whatever they were set to. That is the silicon, not a
setting, so plan for those four going off. If something must stay energised
through a sleep, wire it to DO01 to DO04.

On light sleep every pin keeps its level anyway; the four DO0n_IN_SLEEP pins are
still applied, so the same wiring behaves the same way in both modes.

bHatPoweredDuringSleep holds the HAT rail the same way, so a sensor that has to keep its
state through the sleep can stay powered. It costs whatever the HAT draws for
the whole sleep, so leave it off unless something needs it.

bLedOnDuringSleep lights the status LED dim blue for the sleep, so a board that is
asleep can be told from one that is dead. It is off by default, like the other
IN_SLEEP pins: the LED draws for the whole sleep. Either way the LED returns to
green on waking without being asked. The part latches its colour on its own
supply, so it holds through a deep sleep with no pin held for it.

Dimming it only takes the current the die draws. The driver behind it draws its
own regardless, so the saving between a dim LED and a dark one is smaller than
the saving between either and cutting its supply. *)

FUNCTION_BLOCK FB_Sleep
  VAR_INPUT
    bExecute : BOOL; (* rising edge: go to sleep now *)
    eSleepMode : E_SleepMode; (* UIO_LIGHT_SLEEP returns where it left off; UIO_DEEP_SLEEP restarts the program *)
    nWakeAfterSeconds : UDINT; (* wake after this many seconds; 0 = no timer *)
    bWakeOnDI01 : BOOL; (* DI01 going high wakes the board *)
    bWakeOnDI02 : BOOL; (* DI02 going high wakes the board *)
    bWakeOnDI03 : BOOL; (* DI03 going high wakes the board *)
    bWakeOnDI04 : BOOL; (* DI04 going high wakes the board *)
    bWakeOnDI05 : BOOL; (* DI05 going high wakes the board *)
    bWakeOnDI06 : BOOL; (* DI06 going high wakes the board *)
    bWakeOnDI07 : BOOL; (* DI07 going high wakes the board *)
    bWakeOnDI08 : BOOL; (* DI08 going high wakes the board *)
    bDO01DuringSleep : BOOL; (* the level DO01 holds while asleep *)
    bDO02DuringSleep : BOOL; (* the level DO02 holds while asleep *)
    bDO03DuringSleep : BOOL; (* the level DO03 holds while asleep *)
    bDO04DuringSleep : BOOL; (* the level DO04 holds while asleep *)
    bHatPoweredDuringSleep : BOOL; (* keep the HAT powered while asleep *)
    bLedOnDuringSleep : BOOL; (* light the status LED dim blue while asleep *)
  END_VAR
  VAR_OUTPUT
    eWakeCause : E_WakeCause; (* what ended the last sleep, or what started this run *)
    bError : BOOL; (* the sleep request was refused *)
    eErrorId : E_UioResult; (* why; UIO_OK when fine *)
  END_VAR
  VAR
    lastTrigger : BOOL;
  END_VAR
#include <NodeUioAPI.h>

E_UIORESULT uio_status(UioResult result);

void setup()
{
  eWakeCause = E_WAKECAUSE::UIO_WAKE_NONE;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
  lastTrigger = false;
}

void loop()
{
  eWakeCause = (E_WAKECAUSE)(uint8_t)uio().wakeCause();

  if ((bool)bExecute && !(bool)lastTrigger) {
    // The pins are the user's surface; the mask is the library's.
    uint8_t wake = 0;
    if ((bool)bWakeOnDI01) wake |= 1 << 0;
    if ((bool)bWakeOnDI02) wake |= 1 << 1;
    if ((bool)bWakeOnDI03) wake |= 1 << 2;
    if ((bool)bWakeOnDI04) wake |= 1 << 3;
    if ((bool)bWakeOnDI05) wake |= 1 << 4;
    if ((bool)bWakeOnDI06) wake |= 1 << 5;
    if ((bool)bWakeOnDI07) wake |= 1 << 6;
    if ((bool)bWakeOnDI08) wake |= 1 << 7;

    const bool held[UIO_HOLDABLE_OUTPUTS] = {
      (bool)bDO01DuringSleep, (bool)bDO02DuringSleep,
      (bool)bDO03DuringSleep, (bool)bDO04DuringSleep,
    };

    const UioResult result = uio().sleep((UioSleepMode)(E_SLEEPMODE)eSleepMode,
                                         (uint32_t)nWakeAfterSeconds, wake,
                                         (bool)bHatPoweredDuringSleep, (bool)bLedOnDuringSleep,
                                         held);
    bError = (result != UIO_OK);
    eErrorId = uio_status(result);
    eWakeCause = (E_WAKECAUSE)(uint8_t)uio().wakeCause();
  }
  lastTrigger = (bool)bExecute;
}

END_FUNCTION_BLOCK