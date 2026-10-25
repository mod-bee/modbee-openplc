(* I2C expansion modules on the Node's I2C bus: which are fitted, which answer,
and their channels in two images an IO map reads.

MODULES      the module table: ARRAY OF UIO_XMOD, one row a module, up to 8.
             Settings (retain them): kind, address, fitted, first.
             Status (every scan): count, present, ok, state, errors.
XD           the digital image, ARRAY OF BOOL: a DI module writes its inputs
             to XD[first..], a DO module drives its outputs from XD[first..].
XA           the analog image, ARRAY OF REAL: AI, AO and temperature modules,
             the same way.

ALL_OK         every fitted module is present and working.
FITTED_COUNT   rows fitted (kind not NONE, fitted TRUE).
MISSING_COUNT  fitted rows that are not ok.
FIRST_BAD      the first such row (its index in MODULES), 0 when none.
ERROR          MISSING_COUNT > 0, or a row's settings cannot work.
STATUS         UIO_OK; UIO_UNSUPPORTED on the Runtime (no I2C bus there).
STATUS_TEXT    that row in a few words: 'mod 2 0x21 missing',
               'mod 1 0x20 no driver', 'mod 3 0x49 in use', 'mod 4 bad address',
               'mod 5 no room'.

---

  VAR_GLOBAL RETAIN
    XMODS : ARRAY[1..4] OF UIO_XMOD;      (\* the site's modules: settings *\)
  END_VAR
  VAR_GLOBAL
    XDI : ARRAY[1..32] OF BOOL;
    XAI : ARRAY[1..8] OF REAL;
  END_VAR

  expansion(MODULES := XMODS, XD := XDI, XA := XAI);
  (\* then, in the IO map's module table: src I2C, module = the row,
     first/count from the row, ok := XMODS[row].ok *\)

THE KINDS: UIO_XK_MCP23017_DI / _DO (16 channels), UIO_XK_PCF8574_DI / _DO
(8), UIO_XK_PCA9555_DI / _DO (16), UIO_XK_ADS1115_AI (4, raw counts),
UIO_XK_MCP4728_AO (4), UIO_XK_GP8413_AO (2), UIO_XK_TMP117_T and
UIO_XK_MCP9808_T (1, degC), UIO_XK_SHT4X_TH (degC, %RH).

NO CHIP DRIVERS ARE BUILT IN YET. A fitted module is found by its address
answering (present TRUE) and reads state UIO_XS_NO_DRIVER with ok FALSE, so a
function mapped to it takes its fail-safe until this firmware can read it.
Drivers come one family at a time (docs/07-expansion.md).

A MODULE THAT IS NOT THERE IS NEVER READ AS OFF. A fitted module that does not
answer is UIO_XS_MISSING and not ok; one that stops answering is MISSING after
three failed transactions; its channels keep their last values but ok says
not to trust them. Missing modules are asked again every five seconds, so one
plugged back in is found by itself.

ONE BUS TRANSACTION PER CALL, round the table, so the scan time stays flat
however many modules there are. The bus is shared with the board's own ADC
and DAC (0x49, 0x5F) under one lock, whatever task each runs in.

I2C IS A CABINET BUS: keep modules within about a metre of the Node. Field
devices belong on RS485 (modbee-modbus). *)

FUNCTION_BLOCK UIO_EXPANSION
  VAR_IN_OUT
    MODULES : ARRAY [*] OF UIO_XMOD;
    XD : ARRAY [*] OF BOOL;
    XA : ARRAY [*] OF REAL;
  END_VAR
  VAR_OUTPUT
    ALL_OK : BOOL;
    FITTED_COUNT : USINT;
    MISSING_COUNT : USINT;
    FIRST_BAD : INT;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
    STATUS_TEXT : STRING(30);
  END_VAR
  VAR
    fbEngine : __XWORD;
  END_VAR
#include <NodeUioAPI.h>
#include <cstdio>
#include <new>

UIO_RESULT uio_status(UioResult result);
uint32_t uio_nowMs();

void setup()
{
  ALL_OK = false;
  FITTED_COUNT = 0;
  MISSING_COUNT = 0;
  FIRST_BAD = 0;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  STATUS_TEXT = "";
  fbEngine = (strucpp::XWORD_t)0;
}

void loop()
{
  UioXEngine* engine = (UioXEngine*)(uintptr_t)(strucpp::XWORD_t)fbEngine;
  if (engine == nullptr) {
    // On the heap - PSRAM first - on the first scan: a kilobyte the instance
    // need not carry.
    void* raw = uioAllocLarge(sizeof(UioXEngine));
    engine = raw != nullptr ? new (raw) UioXEngine() : nullptr;
    if (engine == nullptr) {
      ERROR = true;
      STATUS = UIO_RESULT::UIO_TOO_LARGE;
      STATUS_TEXT = "out of memory";
      return;
    }
    fbEngine = (strucpp::XWORD_t)(uintptr_t)engine;
  }

  const int64_t lo = MODULES->lower_bound();
  int64_t rows = MODULES->upper_bound() - lo + 1;
  if (rows < 0) rows = 0;
  if (rows > UIO_X_MAX_MODULES) rows = UIO_X_MAX_MODULES;
  engine->setRows((size_t)rows);

  const int64_t dLo = XD->lower_bound(), dHi = XD->upper_bound();
  const int64_t aLo = XA->lower_bound(), aHi = XA->upper_bound();

  // --- Settings in, outputs to the modules ---
  for (int64_t k = 0; k < rows; k++) {
    auto& row = (*MODULES)[lo + k];
    const uint8_t kind = (uint8_t)(int32_t)(strucpp::UIO_XKIND)row.KIND;
    const uint8_t count = uioXChannels(kind);
    const UioXImage image = uioXImage(kind);
    const bool digital = image == UIO_XI_DIGITAL_IN || image == UIO_XI_DIGITAL_OUT;
    const int64_t first = (int64_t)(int16_t)row.FIRST;
    const bool fits = count == 0 ||
        (digital ? (first >= dLo && first + count - 1 <= dHi)
                 : (first >= aLo && first + count - 1 <= aHi));
    engine->configure((size_t)k, kind, (uint8_t)row.ADDRESS, (bool)row.FITTED, fits);
    row.COUNT = count;

    if (fits && (image == UIO_XI_DIGITAL_OUT || image == UIO_XI_ANALOG_OUT)) {
      UioXChannels out = engine->at((size_t)k).out;
      for (uint8_t c = 0; c < count; c++) {
        if (digital) out.bits[c] = (bool)(*XD)[first + c];
        else out.values[c] = (float)(*XA)[first + c];
      }
      engine->setOutputs((size_t)k, out);
    }
  }

  // --- One bus transaction ---
  UioXBus* bus = uio().expansionBus();
  if (bus != nullptr) engine->service(*bus, uio_nowMs(), 5000u);
  STATUS = bus != nullptr ? UIO_RESULT::UIO_OK : uio_status(UIO_UNSUPPORTED);

  // --- Status out, inputs to the images ---
  uint8_t fitted = 0, missing = 0;
  int64_t firstBad = -1;
  for (int64_t k = 0; k < rows; k++) {
    auto& row = (*MODULES)[lo + k];
    const UioXModule& m = engine->at((size_t)k);
    row.PRESENT = m.present;
    row.OK = m.ok;
    row.STATE = (strucpp::UIO_XSTATE)(uint8_t)m.state;
    row.ERRORS = m.errors;

    const UioXImage image = uioXImage(m.kind);
    if (m.ok && m.fits && (image == UIO_XI_DIGITAL_IN || image == UIO_XI_ANALOG_IN)) {
      const int64_t first = (int64_t)(int16_t)row.FIRST;
      const uint8_t count = uioXChannels(m.kind);
      for (uint8_t c = 0; c < count; c++) {
        if (image == UIO_XI_DIGITAL_IN) (*XD)[first + c] = m.in.bits[c];
        else (*XA)[first + c] = m.in.values[c];
      }
    }

    if (m.kind == UIO_XK_NONE || !m.fitted) continue;
    fitted++;
    if (!m.ok) {
      missing++;
      if (firstBad < 0) firstBad = k;
    }
  }

  FITTED_COUNT = fitted;
  MISSING_COUNT = missing;
  FIRST_BAD = firstBad >= 0 ? (int16_t)(lo + firstBad) : 0;
  ALL_OK = fitted > 0 && missing == 0;
  ERROR = missing > 0;

  char text[31];
  text[0] = '\0';
  if (MODULES->upper_bound() - lo + 1 > UIO_X_MAX_MODULES) {
    std::snprintf(text, sizeof text, "only %d modules", UIO_X_MAX_MODULES);
  }
  if (firstBad >= 0) {
    const UioXModule& m = engine->at((size_t)firstBad);
    const int row = (int)(lo + firstBad);
    const char* why = "not ok";
    switch (m.state) {
      case UIO_XS_MISSING:     why = "missing"; break;
      case UIO_XS_NO_DRIVER:   why = "no driver"; break;
      case UIO_XS_FAILING:     why = "failing"; break;
      case UIO_XS_IN_USE:      why = "in use"; break;
      case UIO_XS_BAD_ADDRESS: why = "bad address"; break;
      case UIO_XS_NO_ROOM:     why = "no room"; break;
      default: break;
    }
    if (bus == nullptr) {
      std::snprintf(text, sizeof text, "no I2C bus here");
    } else if (m.state == UIO_XS_BAD_ADDRESS || m.state == UIO_XS_NO_ROOM) {
      std::snprintf(text, sizeof text, "mod %d %s", row, why);
    } else {
      std::snprintf(text, sizeof text, "mod %d 0x%02X %s", row, (unsigned)m.address, why);
    }
  }
  STATUS_TEXT = text;
}

END_FUNCTION_BLOCK