(* Lists the I2C addresses that answer on the Node's I2C bus - for
commissioning expansion modules.

FOUND   the addresses that answered, lowest first: ARRAY OF BYTE. The rest of
        the array is set to 0.
START   a rising edge starts a scan of 16#08..16#77.

BUSY    scanning.
DONE    the last scan has finished (stays TRUE until the next START).
COUNT   addresses found, including the board's own ADC (16#49) and DAC (16#5F).
ERROR   the bus is not up, or FOUND was too short for them all.
STATUS  UIO_OK; UIO_NOT_READY before UIO has started the board;
        UIO_TOO_LARGE when FOUND was too short; UIO_UNSUPPORTED on the Runtime.

---

  scan(START := HMI.scanI2c, FOUND := i2cFound);

A healthy board always shows 16#49 and 16#5F. A module that does not show is
not wired, not powered, or set to another address (most have address
jumpers). Four addresses are asked each call, sharing the bus lock with the
board's converters and UIO_EXPANSION, so a scan takes about 30 scans and never
holds the bus for long. *)

FUNCTION_BLOCK UIO_I2C_SCAN
  VAR_IN_OUT
    FOUND : ARRAY [*] OF BYTE;
  END_VAR
  VAR_INPUT
    START : BOOL;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    COUNT : USINT;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    fbLast : BOOL;
    fbNext : USINT;
    fbFound : USINT;
    fbShort : BOOL;
  END_VAR
#include <NodeUioAPI.h>

UIO_RESULT uio_status(UioResult result);

void setup()
{
  BUSY = false;
  DONE = false;
  COUNT = 0;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  fbLast = true;   // a START already TRUE at start-up is not an edge
  fbNext = 0;
  fbFound = 0;
  fbShort = false;
}

void loop()
{
  const int64_t lo = FOUND->lower_bound();
  const int64_t hi = FOUND->upper_bound();

  const bool start = (bool)START;
  if (start && !(bool)fbLast) {
    for (int64_t i = lo; i <= hi; i++) (*FOUND)[i] = (uint8_t)0;
    fbNext = UIO_X_FIRST_ADDRESS;
    fbFound = 0;
    fbShort = false;
    BUSY = true;
    DONE = false;
    ERROR = false;
    STATUS = UIO_RESULT::UIO_OK;
  }
  fbLast = start;
  if (!(bool)BUSY) return;

  for (int asked = 0; asked < 4 && (uint8_t)fbNext <= UIO_X_LAST_ADDRESS; asked++) {
    bool present = false;
    const UioResult result = uio().i2cProbe((uint8_t)fbNext, present);
    if (result == UIO_NOT_READY) return;   // bus busy or not up yet: next scan
    if (result != UIO_OK) {
      BUSY = false;
      DONE = true;
      ERROR = true;
      STATUS = uio_status(result);
      return;
    }
    if (present) {
      const int64_t at = lo + (int64_t)(uint8_t)fbFound;
      if (at <= hi) {
        (*FOUND)[at] = (uint8_t)fbNext;
      } else {
        fbShort = true;
      }
      fbFound = (uint8_t)fbFound + 1;
    }
    fbNext = (uint8_t)fbNext + 1;
  }
  COUNT = fbFound;

  if ((uint8_t)fbNext > UIO_X_LAST_ADDRESS) {
    BUSY = false;
    DONE = true;
    ERROR = (bool)fbShort;
    STATUS = (bool)fbShort ? UIO_RESULT::UIO_TOO_LARGE : UIO_RESULT::UIO_OK;
  }
}

END_FUNCTION_BLOCK