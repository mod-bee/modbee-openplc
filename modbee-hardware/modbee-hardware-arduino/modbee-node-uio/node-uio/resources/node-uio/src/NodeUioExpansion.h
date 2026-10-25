#pragma once

// No Arduino headers: this is the board-independent half of the I2C expansion
// layer, so the host tests drive it against a simulated bus.
#include <stddef.h>
#include <stdint.h>

/*
 * I2C EXPANSION MODULES
 *
 * The Node's I2C bus (Wire1, GPIO 37/38) already carries the board's own
 * ADS1115 (0x49) and GP8413 (0x5F), and the Grove connectors and the HAT header
 * bring it out. Expansion modules sit on the same bus: more digital inputs and
 * outputs, analog inputs and outputs, temperature. This layer is what turns a
 * row of settings - kind, address, fitted - into a module that is known to be
 * present and working, with its channels in an image the IO map reads.
 *
 * It is split in three so that a chip driver is the only thing a new module
 * needs:
 *
 *   UioXKind      what a module is: its channel count and which image its
 *                 channels go to. A table, below; new kinds are appended.
 *   UioXDriver    how to talk to one kind: start, read, write. NONE ARE
 *                 BUILT IN YET - every kind is detected (it answers at its
 *                 address) and reported UIO_XS_NO_DRIVER, so its channels are
 *                 never trusted. See docs/07-expansion.md for adding one.
 *   UioXEngine    the rows: presence, retries, state, the channel values, one
 *                 bus transaction per service() so the scan never stalls.
 *
 * The bus itself is an interface (UioXBus): Wire1 behind the board's bus lock
 * on the Node, a simulation on the host.
 */

// Ordinals match the ST enumeration UIO_XKIND. Append only.
enum UioXKind : uint8_t {
  UIO_XK_NONE = 0,
  UIO_XK_MCP23017_DI,   // 16 digital inputs
  UIO_XK_MCP23017_DO,   // 16 digital outputs
  UIO_XK_PCF8574_DI,    // 8 digital inputs
  UIO_XK_PCF8574_DO,    // 8 digital outputs
  UIO_XK_PCA9555_DI,    // 16 digital inputs
  UIO_XK_PCA9555_DO,    // 16 digital outputs
  UIO_XK_ADS1115_AI,    // 4 analog inputs (raw counts)
  UIO_XK_MCP4728_AO,    // 4 analog outputs
  UIO_XK_GP8413_AO,     // 2 analog outputs
  UIO_XK_TMP117_T,      // 1 temperature, degC
  UIO_XK_MCP9808_T,     // 1 temperature, degC
  UIO_XK_SHT4X_TH,      // temperature degC, relative humidity %
  UIO_XK_COUNT
};

// Ordinals match the ST enumeration UIO_XSTATE. Append only.
enum UioXState : uint8_t {
  UIO_XS_UNUSED = 0,    // an empty row (kind NONE)
  UIO_XS_OK,            // present, and its driver reads/writes it
  UIO_XS_NOT_FITTED,    // fitted = FALSE: not on this site
  UIO_XS_MISSING,       // fitted, and nothing answers at its address
  UIO_XS_NO_DRIVER,     // answers, but this firmware has no driver for the kind
  UIO_XS_FAILING,       // its driver's transactions fail
  UIO_XS_BAD_ADDRESS,   // not a 7-bit device address (0x08..0x77)
  UIO_XS_IN_USE,        // the board's own part, or another row, has that address
  UIO_XS_NO_ROOM,       // its channels do not fit the image at `first`
};

// Which image a kind's channels go to.
enum UioXImage : uint8_t {
  UIO_XI_NONE = 0,
  UIO_XI_DIGITAL_IN,
  UIO_XI_DIGITAL_OUT,
  UIO_XI_ANALOG_IN,
  UIO_XI_ANALOG_OUT,
};

#define UIO_X_MAX_MODULES   8
#define UIO_X_MAX_DIGITAL  16
#define UIO_X_MAX_ANALOG    4
#define UIO_X_FIRST_ADDRESS 0x08
#define UIO_X_LAST_ADDRESS  0x77

/** One module's channels: bits for a digital kind, values for an analog one. */
struct UioXChannels {
  bool bits[UIO_X_MAX_DIGITAL];
  float values[UIO_X_MAX_ANALOG];
};

/** What a driver may do on the bus. Every call is one complete transaction. */
class UioXBus {
public:
  virtual ~UioXBus() {}
  /** An address acknowledges. */
  virtual bool probe(uint8_t address) = 0;
  virtual bool write(uint8_t address, const uint8_t* data, size_t length) = 0;
  virtual bool read(uint8_t address, uint8_t* data, size_t length) = 0;
  /** A register write then a read, as one transaction (repeated start). */
  virtual bool writeRead(uint8_t address, const uint8_t* out, size_t outLength,
                         uint8_t* in, size_t inLength) = 0;
};

/**
 * How to talk to one kind of chip. All three may be null where a kind has no
 * such step. Each returns false on a failed transaction, which the engine
 * counts; three in a row and the module is re-probed as if new.
 *
 *   start   after the module (re)appears: check its identity where the chip
 *           has one (an ID register, register defaults) and configure it
 *           (directions, gain, rate). False = not this chip, or not working.
 *   read    an input kind: fill `in` (bits or values, in the kind's order).
 *   write   an output kind: send `out`.
 */
struct UioXDriver {
  uint8_t kind;
  bool (*start)(UioXBus& bus, uint8_t address);
  bool (*read)(UioXBus& bus, uint8_t address, UioXChannels& in);
  bool (*write)(UioXBus& bus, uint8_t address, const UioXChannels& out);
};

/** Channels of a kind, 0 for NONE or an unknown kind. */
uint8_t uioXChannels(uint8_t kind);
/** The image a kind's channels go to. */
UioXImage uioXImage(uint8_t kind);
/** A short name, 'MCP23017 DI', for a status line. */
const char* uioXName(uint8_t kind);

/**
 * The driver for a kind, or null when this firmware has none. Every kind is
 * null today: the drivers come one family at a time, each with a bench test.
 * A driver is added by appending it to the table in NodeUioExpansion.cpp.
 */
const UioXDriver* uioXDriver(uint8_t kind);

/**
 * Adds a driver at run time - from another library, or a test's simulated
 * chip. One per kind (a second replaces the first); up to eight. False when
 * the table is full or the kind is not one this layer knows.
 */
bool uioXRegisterDriver(const UioXDriver* driver);

/** Addresses the board itself uses on this bus: the ADS1115 and the GP8413. */
bool uioXReserved(uint8_t address);

struct UioXModule {
  // Settings, applied by configure().
  uint8_t kind = UIO_XK_NONE;
  uint8_t address = 0;
  bool fitted = true;
  bool fits = true;          // the caller's image has room for its channels

  // What the engine knows.
  UioXState state = UIO_XS_UNUSED;
  bool present = false;      // answered at its address
  bool ok = false;           // present, started, and its last transaction worked
  bool started = false;
  uint8_t failures = 0;      // in a row
  uint16_t errors = 0;       // ever, saturating
  uint32_t probedAt = 0;
  bool probed = false;

  UioXChannels in = {};      // read from an input module
  UioXChannels out = {};     // to write to an output module
};

class UioXEngine {
public:
  /**
   * The settings of row `index` as they are now. Cheap when nothing changed;
   * a different kind or address is a different module and starts over.
   */
  void configure(size_t index, uint8_t kind, uint8_t address, bool fitted, bool fits);

  /** The values an output row should drive. */
  void setOutputs(size_t index, const UioXChannels& out);

  /**
   * One step: at most ONE bus transaction, for the next row that needs one,
   * so the scan time stays flat however many modules there are. Rows whose
   * module is missing are probed again every `retryMs`; present rows are read
   * or written every call that reaches them.
   */
  void service(UioXBus& bus, uint32_t nowMs, uint32_t retryMs);

  const UioXModule& at(size_t index) const { return _rows[index < UIO_X_MAX_MODULES ? index : 0]; }
  size_t rows() const { return _count; }
  void setRows(size_t count) { _count = count > UIO_X_MAX_MODULES ? UIO_X_MAX_MODULES : count; }

private:
  UioXState settle(size_t index) const;   // the state settings alone decide, or OK to go on
  void fail(UioXModule& row);

  UioXModule _rows[UIO_X_MAX_MODULES];
  size_t _count = 0;
  size_t _cursor = 0;
};
