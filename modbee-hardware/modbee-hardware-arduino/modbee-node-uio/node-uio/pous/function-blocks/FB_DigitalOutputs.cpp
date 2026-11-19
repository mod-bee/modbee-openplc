(* Drives the eight digital outputs.

bDO01..bDO08  drive the output.

---

What you set here reaches the pins on the next FB_NodeUio call, so the outputs change
once per scan rather than partway through your logic.

Each channel switches 5-24 V at 100 mA, or 500 mA with the group jumpers cut and
a separate supply wired to terminal 5. Nothing here reports a fault: the board
has no readback, so an output that is shorted or open looks exactly like one
that is working.

Deep sleep does not hold bDO05 to bDO08. They sit outside the part's RTC domain
and drop when it sleeps. See the FB_Sleep block. *)

FUNCTION_BLOCK FB_DigitalOutputs
  VAR_INPUT
    bDO01 : BOOL; (* digital output bDO01: TRUE switches it on (at the next FB_NodeUio call) *)
    bDO02 : BOOL; (* digital output bDO02 *)
    bDO03 : BOOL; (* digital output bDO03 *)
    bDO04 : BOOL; (* digital output bDO04 *)
    bDO05 : BOOL; (* digital output bDO05 (drops in deep sleep) *)
    bDO06 : BOOL; (* digital output bDO06 (drops in deep sleep) *)
    bDO07 : BOOL; (* digital output bDO07 (drops in deep sleep) *)
    bDO08 : BOOL; (* digital output bDO08 (drops in deep sleep) *)
  END_VAR
#include <NodeUioAPI.h>

void setup()
{
  // Driven from the first call rather than a scan later, so an output wired
  // true does not pulse off on start-up.
  uio().setDigitalOut(0, (bool)bDO01);
  uio().setDigitalOut(1, (bool)bDO02);
  uio().setDigitalOut(2, (bool)bDO03);
  uio().setDigitalOut(3, (bool)bDO04);
  uio().setDigitalOut(4, (bool)bDO05);
  uio().setDigitalOut(5, (bool)bDO06);
  uio().setDigitalOut(6, (bool)bDO07);
  uio().setDigitalOut(7, (bool)bDO08);
}

void loop()
{
  uio().setDigitalOut(0, (bool)bDO01);
  uio().setDigitalOut(1, (bool)bDO02);
  uio().setDigitalOut(2, (bool)bDO03);
  uio().setDigitalOut(3, (bool)bDO04);
  uio().setDigitalOut(4, (bool)bDO05);
  uio().setDigitalOut(5, (bool)bDO06);
  uio().setDigitalOut(6, (bool)bDO07);
  uio().setDigitalOut(7, (bool)bDO08);
}

END_FUNCTION_BLOCK