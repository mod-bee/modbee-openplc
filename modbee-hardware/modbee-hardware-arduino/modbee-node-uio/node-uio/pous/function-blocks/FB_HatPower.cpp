(* Switches the HAT power line.

bHatPowerOn  power the HATs.

bEnableLineOn  what the line was last set to.

---

GPIO 9 is the enable each HAT uses to switch its own supply, through its own
MOSFET. The rail itself is fused and always live, so this asks a HAT to turn on
rather than turning a rail on here.

It takes effect immediately rather than at the next FB_NodeUio call. There is no sense
line back, so bEnableLineOn reports what was asked for, not what the HAT did with it. *)

FUNCTION_BLOCK FB_HatPower
  VAR_INPUT
    bHatPowerOn : BOOL; (* TRUE asks the HATs to power up (GPIO 9 high) *)
  END_VAR
  VAR_OUTPUT
    bEnableLineOn : BOOL; (* the HAT enable line (GPIO 9) is high now, as last set here or by FB_Sleep; there is no feedback from the HAT *)
  END_VAR
#include <NodeUioAPI.h>

void setup()
{
  bEnableLineOn = false;
}

void loop()
{
  uio().setHatPower((bool)bHatPowerOn);
  bEnableLineOn = uio().hatPower();
}

END_FUNCTION_BLOCK