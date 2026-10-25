(* Starts the board and services it. Every project needs one, called first.

READY   the ADC and the DAC both answered.
ERROR   they did not.
STATUS  why.
          UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT, UIO_IO_ERROR,
          UIO_NO_DATA, UIO_TOO_LARGE, UIO_UNSUPPORTED

---

Put it in the fast task, ahead of the blocks that read and drive I/O. It reads
the inputs and writes the outputs once per call, so the rest of the program sees
one consistent picture of them for the whole scan.

Nothing here is configured. Pins, addresses and ranges belong to the board, and
the blocks that follow set what can be set. *)

FUNCTION_BLOCK UIO
  VAR_OUTPUT
    READY : BOOL;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    started : BOOL;
  END_VAR
#include <NodeUioAPI.h>

// The library and the ST enumeration share member order, so the ordinal
// carries across. Defined here because every project has this block.
// --- reading and writing a TIME pin --------------------------------------
//
// Every duration on every block is a TIME, so that T#30ms on one of these
// reads the same as T#30ms on a TON beside it. TIME is signed nanoseconds
// here and unsigned milliseconds in CODESYS, so nothing relies on a negative:
// below zero is treated as none at all. Rounded UP, so a duration somebody
// set never arrives as nothing.
uint32_t uio_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = t.get();
    if (ns <= 0) return 0u;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 4294967295LL ? 4294967295u : (uint32_t)ms;
}

// Seconds, for the two settings the board itself keeps in whole seconds.
uint32_t uio_secondsOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = t.get();
    if (ns <= 0) return 0u;
    const int64_t s = (ns + 999999999LL) / 1000000000LL;
    return s > 4294967295LL ? 4294967295u : (uint32_t)s;
}

// And the way back, for a duration reported on a pin.
strucpp::IEC_TIME uio_timeOfMs(uint32_t milliseconds)
{
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

strucpp::IEC_TIME uio_timeOfS(uint32_t seconds)
{
    return strucpp::IEC_TIME((strucpp::TIME_t)seconds * strucpp::NS_PER_S);
}

UIO_RESULT uio_status(UioResult result)
{
  return (UIO_RESULT)(uint8_t)result;
}

void setup()
{
  READY = false;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  started = false;
}

void loop()
{
  if (!(bool)started) {
    started = true;
    const UioResult opened = uio().begin();
    if (opened != UIO_OK) {
      READY = false;
      ERROR = true;
      STATUS = uio_status(opened);
      return;
    }
  }

  uio().update();

  READY = uio().ready();
  ERROR = !(bool)READY;
  STATUS = uio_status((bool)READY ? UIO_OK : UIO_NOT_READY);
}

END_FUNCTION_BLOCK