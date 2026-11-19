(* Reads the eight digital inputs.

bDI01..bDI08  the input. TRUE while it is driven.

---

The inputs are sampled once per scan by the FB_NodeUio block, so calling this more than
once in a scan gives the same answer each time. An input that cannot be read
reads FALSE.

There is no debounce and no inversion here. R_TRIG, F_TRIG and TON do that in
your own program, where you can see the timing you chose. *)

FUNCTION_BLOCK FB_DigitalInputs
  VAR_OUTPUT
    bDI01 : BOOL; (* digital input bDI01: TRUE while driven *)
    bDI02 : BOOL; (* digital input bDI02: TRUE while driven *)
    bDI03 : BOOL; (* digital input bDI03: TRUE while driven *)
    bDI04 : BOOL; (* digital input bDI04: TRUE while driven *)
    bDI05 : BOOL; (* digital input bDI05: TRUE while driven *)
    bDI06 : BOOL; (* digital input bDI06: TRUE while driven *)
    bDI07 : BOOL; (* digital input bDI07: TRUE while driven *)
    bDI08 : BOOL; (* digital input bDI08: TRUE while driven *)
  END_VAR
#include <NodeUioAPI.h>

static bool uio_din(uint8_t channel)
{
  bool value = false;
  return uio().digitalIn(channel, value) == UIO_OK && value;
}

void setup()
{
  bDI01 = false;
  bDI02 = false;
  bDI03 = false;
  bDI04 = false;
  bDI05 = false;
  bDI06 = false;
  bDI07 = false;
  bDI08 = false;
}

void loop()
{
  bDI01 = uio_din(0);
  bDI02 = uio_din(1);
  bDI03 = uio_din(2);
  bDI04 = uio_din(3);
  bDI05 = uio_din(4);
  bDI06 = uio_din(5);
  bDI07 = uio_din(6);
  bDI08 = uio_din(7);
}

END_FUNCTION_BLOCK