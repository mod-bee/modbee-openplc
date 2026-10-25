#pragma once

// No Arduino headers: the blocks include this on a host compile too.
#include <stdint.h>

// Type names differ from the ST enumerations they mirror (UIO_RESULT, UIO_MODE,
// UIO_SLEEP, UIO_WAKE). A generated block file aliases each ST name into scope,
// and an equally named type here would collide with that alias.
// Members and their order do match, so the two sides cast cleanly.

#define UIO_DIGITAL_INPUTS  8
/** Outputs inside the RTC domain, so able to hold a state through deep sleep.
 *  DO01..DO04 are GPIO 11-14; DO05..DO08 are GPIO 33-36 and cannot. */
#define UIO_HOLDABLE_OUTPUTS 4

/** Blue level the status LED holds while asleep, when it is left on at all.
 *  Health uses 54. This is low enough to read as a glow in the dark rather
 *  than an indicator, because it burns for the whole sleep. */
#define UIO_LED_SLEEP_LEVEL 3
#define UIO_DIGITAL_OUTPUTS 8
#define UIO_ANALOG_INPUTS   4
#define UIO_ANALOG_OUTPUTS  2

/** What a channel is wired for. Ordinals match the ST enumeration. */
enum UioRange : uint8_t {
  UIO_VOLTAGE = 0,  // 0-10 V
  UIO_CURRENT = 1,  // 0-20 mA
};

/** Full scale of a range, in the unit values are read and written in. */
inline float uioFullScale(UioRange range) {
  return range == UIO_CURRENT ? 20.0f : 10.0f;  // mA : V
}

enum UioResult : uint8_t {
  UIO_OK = 0,
  UIO_NOT_READY,
  UIO_INVALID_ARGUMENT,
  UIO_IO_ERROR,
  UIO_NO_DATA,
  UIO_TOO_LARGE,
  UIO_UNSUPPORTED,
};

enum UioSleepMode : uint8_t {
  UIO_LIGHT_SLEEP = 0,
  UIO_DEEP_SLEEP,
};

enum UioWakeCause : uint8_t {
  UIO_WAKE_NONE = 0,
  UIO_WAKE_TIMER,
  UIO_WAKE_INPUT,
  UIO_WAKE_RESET,
};

/**
 * Two-point calibration for one channel.
 *
 * `low` and `high` are converter counts, which is what the hardware deals in.
 * `offset` is in the channel's engineering unit and is added after scaling.
 */
struct UioCalibration {
  float offset;
  int16_t low;
  int16_t high;
};

/** The converter's full count. Uncalibrated, it is the range's full scale. */
#define UIO_RAW_FULL_SCALE 32767

/** A count at or above this means the converter is at its limit (saturated):
 *  the input is beyond what the range can measure, by an unknown amount. */
#define UIO_RAW_SATURATED  (UIO_RAW_FULL_SCALE - 2)

/**
 * What a saturated input reads: 22 mA on a current channel, 11 V on a voltage
 * one. Clearly over range, so a transmitter that has failed high (NAMUR NE43:
 * above 21 mA) is detected rather than reading a plausible full scale. It is
 * also the most a calibrated reading can show.
 */
inline float uioOverRange(UioRange range) {
  return range == UIO_CURRENT ? 22.0f : 11.0f;  // mA : V
}

/**
 * A converter count to the channel's engineering unit (mA or V).
 *
 * - Saturated (raw >= UIO_RAW_SATURATED, judged on the converter count before
 *   calibration): uioOverRange().
 * - Otherwise the two-point calibration (or the straight ratio when low ==
 *   high), plus the offset, held between 0 and uioOverRange(): a calibration
 *   that puts full scale below the converter's limit can read a little above
 *   it (20.5 mA, an NE43 over-range), never below 0.
 */
inline float uioScaleInput(UioRange range, int16_t raw, const UioCalibration& cal) {
  const float over = uioOverRange(range);
  if (raw >= UIO_RAW_SATURATED) return over;
  if (raw < 0) raw = 0;
  const float full = uioFullScale(range);
  float scaled;
  if (cal.high == cal.low) scaled = (float)raw * full / (float)UIO_RAW_FULL_SCALE;
  else scaled = (float)((int32_t)raw - cal.low) * full / (float)((int32_t)cal.high - cal.low);
  scaled += cal.offset;
  if (scaled < 0.0f) scaled = 0.0f;
  if (scaled > over) scaled = over;
  return scaled;
}

/**
 * What SYS_INFO reports. Bytes, seconds and the ESP-IDF reset reason.
 * stackMin is the smallest stack margin (high-water mark, bytes) among the
 * PLC's tasks, and stackTask names that task.
 */
struct UioSysInfo {
  uint32_t heapFree;      // internal RAM free now
  uint32_t heapMin;       // the least it has been since boot
  uint32_t heapLargest;   // the largest block that could be allocated now
  uint32_t psramFree;
  uint32_t psramSize;
  uint32_t stackMin;
  char stackTask[17];
  uint64_t uptimeMs;
  uint8_t resetReason;    // esp_reset_reason_t: 1 power-on, 3 software, 4 panic, ...
};
