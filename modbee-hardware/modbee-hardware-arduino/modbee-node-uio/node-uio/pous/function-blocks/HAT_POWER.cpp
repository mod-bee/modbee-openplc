(* Switches the HAT power line.

ENABLE   power the HATs.

POWERED  what the line was last set to.

---

GPIO 9 is the enable each HAT uses to switch its own supply, through its own
MOSFET. The rail itself is fused and always live, so this asks a HAT to turn on
rather than turning a rail on here.

It takes effect immediately rather than at the next UIO call. There is no sense
line back, so POWERED reports what was asked for, not what the HAT did with it. *)

FUNCTION_BLOCK HAT_POWER
  VAR_INPUT
    ENABLE : BOOL;
  END_VAR
  VAR_OUTPUT
    POWERED : BOOL;
  END_VAR
#include <NodeUioAPI.h>

void setup()
{
  POWERED = false;
}

void loop()
{
  uio().setHatPower((bool)ENABLE);
  POWERED = uio().hatPower();
}

END_FUNCTION_BLOCK