(* I2C expansion modules on the Node's I2C bus: which are fitted, which answer,
and their channels in two images an IO map reads.

aModules      the module table: ARRAY OF ST_ExpansionModule, one row a module, up to 8.
             Settings (retain them): eModuleType, nI2cAddress, bFitted,
             nFirstImageIndex.
             Status (every scan): nChannels, bAnswering, bGood, eModuleState,
             nFailedTransactionCount.
aDigitalImage  the digital image, ARRAY OF BOOL: a DI module writes its inputs
             to aDigitalImage[nFirstImageIndex..], a DO module drives its outputs from aDigitalImage[nFirstImageIndex..].
aAnalogImage  the analog image, ARRAY OF REAL: AI, AO and temperature modules,
             the same way.

bAllModulesGood  every fitted module is present and working.
nModulesFitted  rows fitted (eModuleType not NONE, bFitted TRUE).
nFaultyModules  fitted rows that are not good.
nFirstFaultyModule      the first such row (its index in aModules), 0 when none.
bError          nFaultyModules > 0, or a row's settings cannot work.
eErrorId       UIO_OK; UIO_UNSUPPORTED on the Runtime (no I2C bus there).
sStatusText    that row in a few words: 'module 2 0x21 missing',
               'module 1 0x20 no driver', 'module 3 0x20 in use',
               'module 4 bad address', 'module 5 no room'.

---

  VAR_GLOBAL RETAIN
    XMODS : ARRAY[1..4] OF ST_ExpansionModule;      (\* the site's modules: settings *\)
  END_VAR
  VAR_GLOBAL
    XDI : ARRAY[1..32] OF BOOL;
    XAI : ARRAY[1..8] OF REAL;
  END_VAR

  expansion(aModules := XMODS, aDigitalImage := XDI, aAnalogImage := XAI);
  (\* then, in the IO map's module table: src I2C, module = the row,
     nFirstImageIndex / nChannels from the row, trusted while XMODS[row].bGood *\)

THE KINDS: UIO_XK_MCP23017_DI / _DO (16 channels), UIO_XK_PCF8574_DI / _DO
(8), UIO_XK_PCA9555_DI / _DO (16), UIO_XK_ADS1115_AI (4, raw counts),
UIO_XK_MCP4728_AO (4), UIO_XK_GP8413_AO (2), UIO_XK_TMP117_T and
UIO_XK_MCP9808_T (1, degC), UIO_XK_SHT4X_TH (degC, %RH).

NO CHIP DRIVERS ARE BUILT IN YET. A fitted module is found by its address
answering (bAnswering TRUE) and reads eModuleState UIO_XS_NO_DRIVER with bGood FALSE, so a
function mapped to it takes its fail-safe until this firmware can read it.
Drivers come one family at a time (docs/08-expansion.md).

A MODULE THAT IS NOT THERE IS NEVER READ AS OFF. A fitted module that does not
answer is UIO_XS_MISSING and not good; one that stops answering is MISSING after
three failed transactions; its channels keep their last values but bGood says
not to trust them. Missing modules are asked again every five seconds, so one
plugged back in is found by itself.

ONE BUS TRANSACTION PER CALL, round the table, so the scan time stays flat
however many modules there are. The board's own ADC and DAC (0x49, 0x5F) are
on a bus of their own, so those addresses are free here; both buses take one
lock, whatever task each runs in.

I2C IS A CABINET BUS: keep modules within about a metre of the Node. Field
devices belong on RS485 (modbee-modbus). *)

FUNCTION_BLOCK FB_ExpansionModules
  VAR_IN_OUT
    aModules : ARRAY [*] OF ST_EXPANSIONMODULE; (* the module table, one row a module, up to 8 *)
    aDigitalImage : ARRAY [*] OF BOOL; (* the digital image: DI modules write into it, DO modules drive from it *)
    aAnalogImage : ARRAY [*] OF REAL; (* the analog image: AI, AO and temperature modules *)
  END_VAR
  VAR_OUTPUT
    bAllModulesGood : BOOL; (* every fitted module is present and working *)
    nModulesFitted : USINT; (* rows fitted (eModuleType not NONE, bFitted TRUE) *)
    nFaultyModules : USINT; (* fitted rows that are not good (missing, no driver, failing ...) *)
    nFirstFaultyModule : INT; (* the first such row, its index in aModules; 0 = none *)
    bError : BOOL; (* a fitted module is not ok, or a row's settings cannot work *)
    eErrorId : E_UioResult; (* UIO_OK; UIO_UNSUPPORTED on the Runtime *)
    sStatusText : STRING(30); (* that row in a few words: 'module 2 0x21 missing' *)
  END_VAR
  VAR
    fbEngine : __XWORD;
  END_VAR
#include <NodeUioAPI.h>
#include <cstdio>
#include <new>

E_UIORESULT uio_status(UioResult result);
uint32_t uio_nowMs();

void setup()
{
  bAllModulesGood = false;
  nModulesFitted = 0;
  nFaultyModules = 0;
  nFirstFaultyModule = 0;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
  sStatusText = "";
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
      bError = true;
      eErrorId = E_UIORESULT::UIO_TOO_LARGE;
      sStatusText = "out of memory";
      return;
    }
    fbEngine = (strucpp::XWORD_t)(uintptr_t)engine;
  }

  const int64_t lo = aModules->lower_bound();
  int64_t rows = aModules->upper_bound() - lo + 1;
  if (rows < 0) rows = 0;
  if (rows > UIO_X_MAX_MODULES) rows = UIO_X_MAX_MODULES;
  engine->setRows((size_t)rows);

  const int64_t dLo = aDigitalImage->lower_bound(), dHi = aDigitalImage->upper_bound();
  const int64_t aLo = aAnalogImage->lower_bound(), aHi = aAnalogImage->upper_bound();

  // --- Settings in, outputs to the modules ---
  for (int64_t k = 0; k < rows; k++) {
    auto& row = (*aModules)[lo + k];
    const uint8_t kind = (uint8_t)(int32_t)(strucpp::E_EXPANSIONMODULETYPE)row.EMODULETYPE;
    const uint8_t count = uioXChannels(kind);
    const UioXImage image = uioXImage(kind);
    const bool digital = image == UIO_XI_DIGITAL_IN || image == UIO_XI_DIGITAL_OUT;
    const int64_t first = (int64_t)(int16_t)row.NFIRSTIMAGEINDEX;
    const bool fits = count == 0 ||
        (digital ? (first >= dLo && first + count - 1 <= dHi)
                 : (first >= aLo && first + count - 1 <= aHi));
    engine->configure((size_t)k, kind, (uint8_t)row.NI2CADDRESS, (bool)row.BFITTED, fits);
    row.NCHANNELS = count;

    if (fits && (image == UIO_XI_DIGITAL_OUT || image == UIO_XI_ANALOG_OUT)) {
      UioXChannels out = engine->at((size_t)k).out;
      for (uint8_t c = 0; c < count; c++) {
        if (digital) out.bits[c] = (bool)(*aDigitalImage)[first + c];
        else out.values[c] = (float)(*aAnalogImage)[first + c];
      }
      engine->setOutputs((size_t)k, out);
    }
  }

  // --- One bus transaction ---
  UioXBus* bus = uio().expansionBus();
  if (bus != nullptr) engine->service(*bus, uio_nowMs(), 5000u);
  eErrorId = bus != nullptr ? E_UIORESULT::UIO_OK : uio_status(UIO_UNSUPPORTED);

  // --- Status out, inputs to the images ---
  uint8_t fitted = 0, missing = 0;
  int64_t firstBad = -1;
  for (int64_t k = 0; k < rows; k++) {
    auto& row = (*aModules)[lo + k];
    const UioXModule& m = engine->at((size_t)k);
    row.BANSWERING = m.present;
    row.BGOOD = m.ok;
    row.EMODULESTATE = (strucpp::E_EXPANSIONMODULESTATE)(uint8_t)m.state;
    row.NFAILEDTRANSACTIONCOUNT = m.errors;

    const UioXImage image = uioXImage(m.kind);
    if (m.ok && m.fits && (image == UIO_XI_DIGITAL_IN || image == UIO_XI_ANALOG_IN)) {
      const int64_t first = (int64_t)(int16_t)row.NFIRSTIMAGEINDEX;
      const uint8_t count = uioXChannels(m.kind);
      for (uint8_t c = 0; c < count; c++) {
        if (image == UIO_XI_DIGITAL_IN) (*aDigitalImage)[first + c] = m.in.bits[c];
        else (*aAnalogImage)[first + c] = m.in.values[c];
      }
    }

    if (m.kind == UIO_XK_NONE || !m.fitted) continue;
    fitted++;
    if (!m.ok) {
      missing++;
      if (firstBad < 0) firstBad = k;
    }
  }

  nModulesFitted = fitted;
  nFaultyModules = missing;
  nFirstFaultyModule = firstBad >= 0 ? (int16_t)(lo + firstBad) : 0;
  bAllModulesGood = fitted > 0 && missing == 0;
  bError = missing > 0;

  char text[31];
  text[0] = '\0';
  if (aModules->upper_bound() - lo + 1 > UIO_X_MAX_MODULES) {
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
      std::snprintf(text, sizeof text, "module %d %s", row, why);
    } else {
      std::snprintf(text, sizeof text, "module %d 0x%02X %s", row, (unsigned)m.address, why);
    }
  }
  sStatusText = text;
}

END_FUNCTION_BLOCK