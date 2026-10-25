(* Reads the eight digital inputs.

DI01..DI08  the input. TRUE while it is driven.

---

The inputs are sampled once per scan by the UIO block, so calling this more than
once in a scan gives the same answer each time. An input that cannot be read
reads FALSE.

There is no debounce and no inversion here. R_TRIG, F_TRIG and TON do that in
your own program, where you can see the timing you chose. *)

FUNCTION_BLOCK DIGITAL_IN
  VAR_OUTPUT
    DI01 : BOOL;
    DI02 : BOOL;
    DI03 : BOOL;
    DI04 : BOOL;
    DI05 : BOOL;
    DI06 : BOOL;
    DI07 : BOOL;
    DI08 : BOOL;
  END_VAR
#include <NodeUioAPI.h>

static bool uio_din(uint8_t channel)
{
  bool value = false;
  return uio().digitalIn(channel, value) == UIO_OK && value;
}

void setup()
{
  DI01 = false;
  DI02 = false;
  DI03 = false;
  DI04 = false;
  DI05 = false;
  DI06 = false;
  DI07 = false;
  DI08 = false;
}

void loop()
{
  DI01 = uio_din(0);
  DI02 = uio_din(1);
  DI03 = uio_din(2);
  DI04 = uio_din(3);
  DI05 = uio_din(4);
  DI06 = uio_din(5);
  DI07 = uio_din(6);
  DI08 = uio_din(7);
}

END_FUNCTION_BLOCK