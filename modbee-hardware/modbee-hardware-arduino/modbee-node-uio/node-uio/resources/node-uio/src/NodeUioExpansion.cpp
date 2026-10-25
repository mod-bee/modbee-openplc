#include "NodeUioExpansion.h"

// Board-independent: compiled on the board and in the host tests alike.

namespace {

struct KindInfo {
  uint8_t channels;
  UioXImage image;
  const char* name;
};

// Indexed by UioXKind. Append with the enum, never reorder.
const KindInfo kKinds[UIO_XK_COUNT] = {
  {0,  UIO_XI_NONE,        "none"},
  {16, UIO_XI_DIGITAL_IN,  "MCP23017 DI"},
  {16, UIO_XI_DIGITAL_OUT, "MCP23017 DO"},
  {8,  UIO_XI_DIGITAL_IN,  "PCF8574 DI"},
  {8,  UIO_XI_DIGITAL_OUT, "PCF8574 DO"},
  {16, UIO_XI_DIGITAL_IN,  "PCA9555 DI"},
  {16, UIO_XI_DIGITAL_OUT, "PCA9555 DO"},
  {4,  UIO_XI_ANALOG_IN,   "ADS1115 AI"},
  {4,  UIO_XI_ANALOG_OUT,  "MCP4728 AO"},
  {2,  UIO_XI_ANALOG_OUT,  "GP8413 AO"},
  {1,  UIO_XI_ANALOG_IN,   "TMP117 T"},
  {1,  UIO_XI_ANALOG_IN,   "MCP9808 T"},
  {2,  UIO_XI_ANALOG_IN,   "SHT4x T/RH"},
};

// THE DRIVERS. None yet: every kind is detected by its address answering and
// reported UIO_XS_NO_DRIVER, so its channels are never trusted. A driver is a
// UioXDriver appended here (see docs/07-expansion.md); nothing else changes.
const UioXDriver* const kDrivers[] = {
  nullptr,
};

const uint8_t kFailuresBeforeMissing = 3;

// Drivers registered at run time (uioXRegisterDriver): a driver that lives in
// another library, or a test's simulated chip. Zero-initialised, so nothing
// runs before main.
const UioXDriver* sRegistered[8];

}  // namespace

uint8_t uioXChannels(uint8_t kind) {
  return kind < UIO_XK_COUNT ? kKinds[kind].channels : 0;
}

UioXImage uioXImage(uint8_t kind) {
  return kind < UIO_XK_COUNT ? kKinds[kind].image : UIO_XI_NONE;
}

const char* uioXName(uint8_t kind) {
  return kind < UIO_XK_COUNT ? kKinds[kind].name : "?";
}

bool uioXRegisterDriver(const UioXDriver* driver) {
  if (driver == nullptr || driver->kind == UIO_XK_NONE || driver->kind >= UIO_XK_COUNT) return false;
  for (size_t i = 0; i < sizeof sRegistered / sizeof sRegistered[0]; i++) {
    if (sRegistered[i] == nullptr || sRegistered[i]->kind == driver->kind) {
      sRegistered[i] = driver;
      return true;
    }
  }
  return false;
}

const UioXDriver* uioXDriver(uint8_t kind) {
  for (size_t i = 0; i < sizeof sRegistered / sizeof sRegistered[0]; i++) {
    if (sRegistered[i] != nullptr && sRegistered[i]->kind == kind) return sRegistered[i];
  }
  for (size_t i = 0; i < sizeof kDrivers / sizeof kDrivers[0]; i++) {
    if (kDrivers[i] != nullptr && kDrivers[i]->kind == kind) return kDrivers[i];
  }
  return nullptr;
}

bool uioXReserved(uint8_t address) {
  return address == 0x49 || address == 0x5F;   // the board's ADS1115 and GP8413
}

void UioXEngine::configure(size_t index, uint8_t kind, uint8_t address, bool fitted,
                           bool fits) {
  if (index >= UIO_X_MAX_MODULES) return;
  UioXModule& row = _rows[index];
  if (row.kind != kind || row.address != address) {
    // A different module: nothing known about the old one carries over.
    row = UioXModule();
    row.kind = kind;
    row.address = address;
  }
  row.fitted = fitted;
  row.fits = fits;
  const UioXState fixed = settle(index);
  if (fixed != UIO_XS_OK) {
    row.state = fixed;
    row.present = false;
    row.ok = false;
    row.started = false;
    row.probed = false;
  }
}

void UioXEngine::setOutputs(size_t index, const UioXChannels& out) {
  if (index < UIO_X_MAX_MODULES) _rows[index].out = out;
}

UioXState UioXEngine::settle(size_t index) const {
  const UioXModule& row = _rows[index];
  if (row.kind == UIO_XK_NONE || row.kind >= UIO_XK_COUNT) return UIO_XS_UNUSED;
  if (!row.fitted) return UIO_XS_NOT_FITTED;
  if (row.address < UIO_X_FIRST_ADDRESS || row.address > UIO_X_LAST_ADDRESS) {
    return UIO_XS_BAD_ADDRESS;
  }
  if (uioXReserved(row.address)) return UIO_XS_IN_USE;
  for (size_t other = 0; other < _count; other++) {
    if (other == index) continue;
    const UioXModule& o = _rows[other];
    if (o.kind != UIO_XK_NONE && o.fitted && o.address == row.address) return UIO_XS_IN_USE;
  }
  if (!row.fits) return UIO_XS_NO_ROOM;
  return UIO_XS_OK;
}

void UioXEngine::fail(UioXModule& row) {
  if (row.errors < 0xFFFF) row.errors++;
  row.ok = false;
  if (++row.failures >= kFailuresBeforeMissing) {
    // Gone, or wedged: probed and started again as if new.
    row.present = false;
    row.started = false;
    row.failures = 0;
    row.state = UIO_XS_MISSING;
  } else if (row.state == UIO_XS_OK) {
    row.state = UIO_XS_FAILING;
  }
}

void UioXEngine::service(UioXBus& bus, uint32_t nowMs, uint32_t retryMs) {
  if (_count == 0) return;
  for (size_t step = 0; step < _count; step++) {
    const size_t index = (_cursor + step) % _count;
    UioXModule& row = _rows[index];
    if (settle(index) != UIO_XS_OK) continue;

    if (!row.present) {
      // Probed when first seen, then every retryMs while it does not answer.
      if (row.probed && (uint32_t)(nowMs - row.probedAt) < retryMs) continue;
      row.probed = true;
      row.probedAt = nowMs;
      _cursor = (index + 1) % _count;
      row.present = bus.probe(row.address);
      row.ok = false;
      row.started = false;
      if (!row.present) {
        row.state = UIO_XS_MISSING;
        return;
      }
      row.failures = 0;
      row.state = uioXDriver(row.kind) ? UIO_XS_FAILING : UIO_XS_NO_DRIVER;
      return;   // one transaction per call
    }

    const UioXDriver* driver = uioXDriver(row.kind);
    if (driver == nullptr) {
      // Answers, and this firmware cannot read it. Its presence is checked
      // again now and then, so a module unplugged still reads MISSING.
      row.ok = false;
      row.state = UIO_XS_NO_DRIVER;
      if ((uint32_t)(nowMs - row.probedAt) < retryMs) continue;
      row.probedAt = nowMs;
      _cursor = (index + 1) % _count;
      if (!bus.probe(row.address)) {
        row.present = false;
        row.state = UIO_XS_MISSING;
      }
      return;
    }

    _cursor = (index + 1) % _count;
    if (!row.started) {
      row.started = driver->start == nullptr || driver->start(bus, row.address);
      if (!row.started) fail(row);
      return;
    }

    bool done = true;
    const UioXImage image = uioXImage(row.kind);
    if ((image == UIO_XI_DIGITAL_IN || image == UIO_XI_ANALOG_IN) && driver->read) {
      done = driver->read(bus, row.address, row.in);
    } else if ((image == UIO_XI_DIGITAL_OUT || image == UIO_XI_ANALOG_OUT) && driver->write) {
      done = driver->write(bus, row.address, row.out);
    }
    if (done) {
      row.failures = 0;
      row.ok = true;
      row.state = UIO_XS_OK;
    } else {
      fail(row);
    }
    return;
  }
}
