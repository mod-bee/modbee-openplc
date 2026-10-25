#pragma once

// No Arduino headers here. The OpenPLC blocks include this and are compiled on
// a host as well as for the board; the implementation is what is guarded.
//
// The platform libraries the sources need are declared in library.properties
// under `depends`, which is what gets them linked — see the note there.
#include "NodeUioTypes.h"
#include "NodeUioExpansion.h"

#include <stddef.h>

/**
 * Everything the Node UIO can do, in one place.
 *
 * The blocks and the web UI are both callers, so behaviour decided here cannot
 * differ between them. Channels are zero based and validated; a call naming one
 * that does not exist returns UIO_INVALID_ARGUMENT rather than reading past an
 * array.
 *
 * Off the board every call answers UIO_UNSUPPORTED, so a host build links and
 * runs without the hardware present.
 */
class NodeUioAPI {
public:
  static NodeUioAPI& instance();

  /** Brings the board up. Safe to call more than once. */
  UioResult begin();

  /** Reads the inputs and drives the outputs. Once per scan. */
  void update();

  /** Both I2C parts answered at begin(). */
  bool ready() const;

  UioResult digitalIn(uint8_t channel, bool& value) const;
  UioResult digitalOut(uint8_t channel, bool& value) const;
  UioResult setDigitalOut(uint8_t channel, bool on);

  /** The reading in the channel's unit: volts, or milliamps. */
  UioResult analogIn(uint8_t channel, float& value) const;
  UioResult analogInRaw(uint8_t channel, int16_t& raw) const;
  UioResult setInputRange(uint8_t channel, UioRange range);
  UioResult inputRange(uint8_t channel, UioRange& range) const;

  /** The value to output, in the channel's unit: volts, or milliamps. */
  UioResult setAnalogOut(uint8_t channel, float value);
  UioResult analogOutRaw(uint8_t channel, int16_t& raw) const;
  UioResult setOutputRange(uint8_t channel, UioRange range);
  UioResult outputRange(uint8_t channel, UioRange& range) const;

  UioResult inputCalibration(uint8_t channel, UioCalibration& cal) const;
  UioResult setInputCalibration(uint8_t channel, const UioCalibration& cal);
  UioResult outputCalibration(uint8_t channel, UioCalibration& cal) const;
  UioResult setOutputCalibration(uint8_t channel, const UioCalibration& cal);
  UioResult saveCalibration();
  UioResult resetCalibration();

  UioResult setHatPower(bool on);
  bool hatPower() const;

  /**
   * Restarts the controller, as the reset button would, after saving the
   * program's retained values through the firmware's retain store
   * (runtime_retain_flush_now, when the firmware has it), so nothing the store
   * was still holding is lost. The restart waits for that commit, about
   * 10-50 ms, and happens whatever its result.
   */
  UioResult restart();

  /**
   * Why the controller last started: the ESP-IDF esp_reset_reason_t code
   * (1 power-on, 3 software restart, 4 panic, 5..7 watchdogs, 8 deep sleep,
   * 9 brownout, ...). 0 where it cannot be known.
   */
  uint8_t resetReason() const;

  /**
   * Takes the status LED over.
   *
   * Until this is called the board owns it: green once the converters answer,
   * red when they do not.
   */
  UioResult setLed(uint8_t red, uint8_t green, uint8_t blue);

  /**
   * The button beside the antenna, brought out to the HAT header.
   *
   * On the silkscreen it is the WiFi button: the intended use is to bring the
   * radio back for a while on a board that keeps it off to save power. Nothing
   * here assumes that — the presses are reported and the program decides.
   */
  bool button() const;
  /** Milliseconds it has been held, 0 when released. */
  uint32_t buttonHeldMs() const;
  /** True once per press, then clears. Read them once per cycle. */
  bool takeShortPress();
  bool takeLongPress();
  /** How long a hold has to last to count as long. Default 2000 ms. */
  void setButtonLongMs(uint32_t milliseconds);
  /** How long a press must last before it counts at all. Default 30 ms. */
  void setButtonDebounceMs(uint32_t milliseconds);

  /**
   * Duty-cycles the radio, for a board running on a battery.
   *
   * With this enabled the radio is meant to be off, and requestRadio() brings
   * it back for `awakeSeconds`. `wakeEverySeconds` also brings it back on its
   * own that often; 0 means only on request.
   *
   * This decides only whether the radio is wanted. Powering it is still
   * connect() and disconnect(), so one place owns the radio.
   */
  void setRadioPolicy(bool enabled, uint32_t awakeSeconds, uint32_t wakeEverySeconds);
  /** Wake the radio now and restart its awake time. */
  void requestRadio();
  /** Whether the radio should be powered at this moment. */
  bool radioWanted() const;
  /** Seconds until it is no longer wanted. 0 when it is already unwanted. */
  uint32_t radioAwakeLeft() const;

  /**
   * Joins the network, and brings it up only when nothing else has.
   *
   * The radio is shared: the OpenPLC firmware claims it when Modbus TCP is
   * built in, and a protocol library may claim it first. Whoever is first wins
   * and the rest use what is there, so credentials given here are only applied
   * to a radio that is down - or to one this call brought up itself: when the
   * SSID or password differ from the ones it joined with, it leaves and joins
   * again with the new ones (a network changed on a settings page).
   *
   * Never waits: starting the radio takes seconds, so a small task ("uio-radio",
   * core 0) makes the driver calls and this returns UIO_NOT_READY until joined.
   * UIO_IO_ERROR when that task could not be made.
   */
  UioResult connect(const char* ssid, const char* password);

  /**
   * Powers the radio down.
   *
   * The real saving on a battery: WiFi off, not merely disconnected. A later
   * connect() brings it back. Only turns off what this owns — if the firmware
   * brought the radio up for Modbus TCP, that is not ours to switch off.
   */
  UioResult disconnect();
  bool connected() const;
  /** How often the radio has dropped off its network since power-up, and the ESP32's reason for the
   *  last drop (wifi_err_reason_t, 0 none) - in words with radioDropText(). */
  uint32_t radioDrops() const;
  uint8_t radioDropReason() const;
  static const char* radioDropText(uint8_t reason);
  /** IPv4 address as a host-order word, 0 while down. */
  uint32_t address() const;
  /** dBm, 0 while down. */
  int32_t signalStrength() const;

  /**
   * Sleeps. Deep sleep does not return; the board restarts and wakeCause()
   * reports why. Deep sleep saves the program's retained values first, like
   * restart(); light sleep keeps RAM and does not.
   *
   * `wakeInputMask` is one bit per digital input. `safeOutputs` drives every
   * output low first. DO05-DO08 are GPIO 33-36, outside the S3 RTC domain, and
   * drop through deep sleep whatever is asked.
   */
  /**
   * `outputsInSleep` is the level DO01..DO04 hold while asleep, four entries,
   * or null for all off. DO05..DO08 are outside the RTC domain and drop
   * whatever is asked.
   */
  UioResult sleep(UioSleepMode mode, uint32_t seconds, uint8_t wakeInputMask,
                  bool hatInSleep, bool ledInSleep,
                  const bool* outputsInSleep);
  UioWakeCause wakeCause() const;

  // --- Pulse counting on a digital input ---------------------------------
  //
  // The ESP32-S3's pulse counter (PCNT) counts rising edges of DI01..DI08 in
  // hardware, so no pulse is missed however long the scan. Four at a time -
  // the chip has four counters. The input still reads as an ordinary input.

  /**
   * Starts counting `channel` (0 based). `glitchNs` is the hardware glitch
   * filter: pulses shorter are ignored (the chip's limit is about 12.7 us;
   * longer is held there). UIO_TOO_LARGE when all four counters are in use.
   * Safe to call again; a running channel carries on.
   */
  UioResult pulseStart(uint8_t channel, uint32_t glitchNs);
  UioResult pulseStop(uint8_t channel);
  /** Rising edges since pulseStart(), cumulative. */
  UioResult pulseCount(uint8_t channel, int64_t& count) const;

  // --- The I2C expansion bus ----------------------------------------------
  //
  // Wire1 (GPIO 37/38), which also carries the board's ADS1115 (0x49) and
  // GP8413 (0x5F). Every transaction takes the board's bus lock, so the
  // board's own converters and the modules never interleave on the wire.

  /** Whether `address` acknowledges. UIO_NOT_READY before begin(). */
  UioResult i2cProbe(uint8_t address, bool& present);
  /** The bus as an expansion driver sees it; null off the board. */
  UioXBus* expansionBus();

  // --- The controller itself ------------------------------------------------

  /** Heap, PSRAM, the PLC tasks' stack margin, uptime and reset reason. */
  UioResult systemInfo(UioSysInfo& info) const;

private:
  NodeUioAPI();
  NodeUioAPI(const NodeUioAPI&) = delete;
  NodeUioAPI& operator=(const NodeUioAPI&) = delete;
};

/**
 * Memory for a block's larger state, on the heap: external RAM (PSRAM) first
 * on a board that has it, the internal heap otherwise or when PSRAM is full.
 * Called on a scan, so PSRAM has long since joined the heap. Null when there
 * is none. Release with uioFreeLarge().
 */
void* uioAllocLarge(size_t bytes);
void uioFreeLarge(void* pointer);

/** The board. There is only one. */
inline NodeUioAPI& uio() { return NodeUioAPI::instance(); }
