(* Drives the eight digital outputs.

DO01..DO08  drive the output.

---

What you set here reaches the pins on the next UIO call, so the outputs change
once per scan rather than partway through your logic.

Each channel switches 5-24 V at 100 mA, or 500 mA with the group jumpers cut and
a separate supply wired to terminal 5. Nothing here reports a fault: the board
has no readback, so an output that is shorted or open looks exactly like one
that is working.

Deep sleep does not hold DO05 to DO08. They sit outside the part's RTC domain
and drop when it sleeps. See the SLEEP block. *)

FUNCTION_BLOCK DIGITAL_OUT
  VAR_INPUT
    DO01 : BOOL;
    DO02 : BOOL;
    DO03 : BOOL;
    DO04 : BOOL;
    DO05 : BOOL;
    DO06 : BOOL;
    DO07 : BOOL;
    DO08 : BOOL;
  END_VAR
#include <NodeUioAPI.h>

void setup()
{
  // Driven from the first call rather than a scan later, so an output wired
  // true does not pulse off on start-up.
  uio().setDigitalOut(0, (bool)DO01);
  uio().setDigitalOut(1, (bool)DO02);
  uio().setDigitalOut(2, (bool)DO03);
  uio().setDigitalOut(3, (bool)DO04);
  uio().setDigitalOut(4, (bool)DO05);
  uio().setDigitalOut(5, (bool)DO06);
  uio().setDigitalOut(6, (bool)DO07);
  uio().setDigitalOut(7, (bool)DO08);
}

void loop()
{
  uio().setDigitalOut(0, (bool)DO01);
  uio().setDigitalOut(1, (bool)DO02);
  uio().setDigitalOut(2, (bool)DO03);
  uio().setDigitalOut(3, (bool)DO04);
  uio().setDigitalOut(4, (bool)DO05);
  uio().setDigitalOut(5, (bool)DO06);
  uio().setDigitalOut(6, (bool)DO07);
  uio().setDigitalOut(7, (bool)DO08);
}

END_FUNCTION_BLOCK