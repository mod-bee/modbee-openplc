(* Lists the I2C addresses that answer on the Node's expansion bus (the Grove
connectors and the HAT header) - for
commissioning expansion modules.

aFoundAddresses  the addresses that answered, lowest first: ARRAY OF BYTE. The rest of
        the array is set to 0.
bExecute  a rising edge starts a scan of 16#08..16#77.

bBusy   scanning.
bDone    the last scan has finished (stays TRUE until the next bExecute).
nAddressesFound  addresses found. The board's own ADC and DAC are on a bus of their
        own and never show.
bError   the bus is not up, or aFoundAddresses was too short for them all.
eErrorId  UIO_OK; UIO_NOT_READY before FB_NodeUio has started the board;
        UIO_TOO_LARGE when aFoundAddresses was too short; UIO_UNSUPPORTED on the Runtime.

---

  scan(bExecute := HMI.scanI2c, aFoundAddresses := i2cFound);

An empty list is a healthy board with nothing fitted. A module that does not show is
not wired, not powered, or set to another address (most have address
jumpers). Four addresses are asked each call, sharing the I2C lock with the
board's converters and FB_ExpansionModules, so a scan takes about 30 scans and never
holds the bus for long. *)

FUNCTION_BLOCK FB_I2cScan
  VAR_IN_OUT
    aFoundAddresses : ARRAY [*] OF BYTE; (* the addresses that answered, lowest first; the rest set to 0 *)
  END_VAR
  VAR_INPUT
    bExecute : BOOL; (* rising edge starts a scan of 16#08..16#77 *)
  END_VAR
  VAR_OUTPUT
    bBusy : BOOL; (* scanning *)
    bDone : BOOL; (* the last scan has finished; TRUE until the next start *)
    nAddressesFound : USINT; (* addresses found on the expansion bus (the board's own ADC and DAC are on their own bus) *)
    bError : BOOL; (* the bus is not up, or aFoundAddresses was too short *)
    eErrorId : E_UioResult; (* UIO_OK, NOT_READY before FB_NodeUio started, TOO_LARGE, UNSUPPORTED on the Runtime *)
  END_VAR
  VAR
    fbLast : BOOL;
    fbNext : USINT;
    fbFound : USINT;
    fbShort : BOOL;
  END_VAR
#include <NodeUioAPI.h>

E_UIORESULT uio_status(UioResult result);

void setup()
{
  bBusy = false;
  bDone = false;
  nAddressesFound = 0;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
  fbLast = true;   // a bExecute already TRUE at start-up is not an edge
  fbNext = 0;
  fbFound = 0;
  fbShort = false;
}

void loop()
{
  const int64_t lo = aFoundAddresses->lower_bound();
  const int64_t hi = aFoundAddresses->upper_bound();

  const bool start = (bool)bExecute;
  if (start && !(bool)fbLast) {
    for (int64_t i = lo; i <= hi; i++) (*aFoundAddresses)[i] = (uint8_t)0;
    fbNext = UIO_X_FIRST_ADDRESS;
    fbFound = 0;
    fbShort = false;
    bBusy = true;
    bDone = false;
    bError = false;
    eErrorId = E_UIORESULT::UIO_OK;
  }
  fbLast = start;
  if (!(bool)bBusy) return;

  for (int asked = 0; asked < 4 && (uint8_t)fbNext <= UIO_X_LAST_ADDRESS; asked++) {
    bool present = false;
    const UioResult result = uio().i2cProbe((uint8_t)fbNext, present);
    if (result == UIO_NOT_READY) return;   // bus busy or not up yet: next scan
    if (result != UIO_OK) {
      bBusy = false;
      bDone = true;
      bError = true;
      eErrorId = uio_status(result);
      return;
    }
    if (present) {
      const int64_t at = lo + (int64_t)(uint8_t)fbFound;
      if (at <= hi) {
        (*aFoundAddresses)[at] = (uint8_t)fbNext;
      } else {
        fbShort = true;
      }
      fbFound = (uint8_t)fbFound + 1;
    }
    fbNext = (uint8_t)fbNext + 1;
  }
  nAddressesFound = fbFound;

  if ((uint8_t)fbNext > UIO_X_LAST_ADDRESS) {
    bBusy = false;
    bDone = true;
    bError = (bool)fbShort;
    eErrorId = (bool)fbShort ? E_UIORESULT::UIO_TOO_LARGE : E_UIORESULT::UIO_OK;
  }
}

END_FUNCTION_BLOCK