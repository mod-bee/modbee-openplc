(* Counts the pulses of a flow meter (or any pulse output) on a digital input,
in hardware, and turns them into a total and a rate.

TOTAL       the running total, in your units. YOUR variable: the block adds to
            it, so make it RETAIN and it survives a power cut. Reset it by
            writing 0.
CHANNEL     the input, 1..8 (DI01..DI08).
K_FACTOR    pulses per unit, from the meter's plate: 100.0 for 100 pulses a
            litre gives litres. 0 counts pulses as units.
RATE_PER    the rate's time base: T#1s gives units a second, T#1m a minute,
            T#1h an hour. T#1s if left at T#0s.
FILTER      pulses shorter than this are noise and ignored. The hardware's
            limit is about 12 us; longer is held there - see below for contact
            meters.
WINDOW      the rate is measured over at least this long. T#1s if left at
            T#0s.
ZERO_AFTER  no pulse for this long and the rate reads 0. T#30s if left at
            T#0s. Set it above the slowest pulse gap you expect.
ENABLE      counts while TRUE. TRUE unless you say otherwise.

RATE        units per RATE_PER.
PULSES      pulses since counting started.
COUNTING    the counter is running.
ERROR       the input could not be counted.
STATUS      why. UIO_OK when fine.
              UIO_INVALID_ARGUMENT  CHANNEL is not 1..8
              UIO_TOO_LARGE         all four of the chip's counters are taken
              UIO_UNSUPPORTED       not on a ModBee Node (the Runtime)

---

  VAR RETAIN  flowTotal : LREAL;  END_VAR
  flow( TOTAL := flowTotal, CHANNEL := 3, K_FACTOR := 100.0, RATE_PER := T#1h );
  (\* flowTotal in litres, flow.RATE in litres an hour *\)

THE CHIP COUNTS, NOT THE SCAN. The ESP32-S3's pulse counter sees every rising
edge on the input, so a fast meter loses nothing however long the scan; the
block only reads the count. Four inputs can be counted at once - the chip has
four counters. The input still reads normally on DIGITAL_IN.

THE RATE suits a fast meter and a slow one alike: pulses over at least WINDOW
when they come fast, the time between them when they come slowly - one pulse
every ten seconds reads steadily, not 1 then 0. When the pulses stop it falls
away, and is 0 after ZERO_AFTER.

THE TOTAL IS YOURS. The block adds each scan's new pulses (divided by
K_FACTOR) to TOTAL, so a retained TOTAL carries over a power cut and a
restart, and nothing is counted twice. LREAL, because a REAL total of a
meter that has run for years loses its small increments. Pulses that arrive
while the PLC is off are not counted.

A CONTACT (REED) METER bounces for milliseconds, far beyond the filter. Use
a meter with a solid-state (open-collector) output, or an RC filter on the
input. *)

FUNCTION_BLOCK PULSE_COUNT
  VAR_IN_OUT
    TOTAL : LREAL;
  END_VAR
  VAR_INPUT
    CHANNEL : USINT;
    K_FACTOR : REAL;
    RATE_PER : TIME;
    FILTER : TIME;
    WINDOW : TIME;
    ZERO_AFTER : TIME;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    RATE : REAL;
    PULSES : UDINT;
    COUNTING : BOOL;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    fbState : __XWORD;
    fbChannel : USINT;
  END_VAR
#include <NodeUioAPI.h>
#include <NodeUioPulse.h>
#include <new>

UIO_RESULT uio_status(UioResult result);
uint32_t uio_millisOf(const strucpp::IEC_TIME& t);

// Milliseconds, wrapping. Shared with the node-uio blocks that sort after this
// file in the one translation unit every C++ POU lands in.
#if defined(ARDUINO)
#include <Arduino.h>
uint32_t uio_nowMs() { return millis(); }
#else
#include <chrono>
uint32_t uio_nowMs() {
  return (uint32_t)std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::steady_clock::now().time_since_epoch()).count();
}
#endif

namespace {
// Per instance, on the heap: the rate's state and the count already added.
struct UioPulseState {
  UioPulseRate rate;
  int64_t added = 0;
  uint32_t pulses = 0;
};
}  // namespace

void setup()
{
  RATE = 0.0f;
  PULSES = 0;
  COUNTING = false;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
  fbState = (strucpp::XWORD_t)0;
  fbChannel = 0;
}

void loop()
{
  const uint8_t wanted = (bool)ENABLE ? (uint8_t)CHANNEL : 0;
  if (wanted > UIO_DIGITAL_INPUTS) {
    COUNTING = false;
    RATE = 0.0f;
    ERROR = true;
    STATUS = UIO_RESULT::UIO_INVALID_ARGUMENT;
    return;
  }

  UioPulseState* state = (UioPulseState*)(uintptr_t)(strucpp::XWORD_t)fbState;
  if (state == nullptr) {
    state = new (std::nothrow) UioPulseState();
    if (state == nullptr) {
      ERROR = true;
      STATUS = UIO_RESULT::UIO_TOO_LARGE;
      return;
    }
    fbState = (strucpp::XWORD_t)(uintptr_t)state;
  }

  // Started, stopped, or moved to another input.
  if (wanted != (uint8_t)fbChannel) {
    if ((uint8_t)fbChannel != 0) uio().pulseStop((uint8_t)fbChannel - 1);
    fbChannel = 0;
    COUNTING = false;
    RATE = 0.0f;
    if (wanted == 0) {
      ERROR = false;
      STATUS = UIO_RESULT::UIO_OK;
      return;
    }
    uint32_t glitchNs = 0;
    {
      const int64_t ns = FILTER.get();
      glitchNs = ns <= 0 ? 0u : (ns > 12000 ? 12000u : (uint32_t)ns);
    }
    const UioResult started = uio().pulseStart(wanted - 1, glitchNs);
    if (started != UIO_OK) {
      ERROR = true;
      STATUS = uio_status(started);
      return;
    }
    fbChannel = wanted;
    int64_t now = 0;
    uio().pulseCount(wanted - 1, now);
    state->added = now;
    state->pulses = 0;
    state->rate.reset(now);
  }
  if ((uint8_t)fbChannel == 0) return;

  int64_t count = 0;
  const UioResult read = uio().pulseCount((uint8_t)fbChannel - 1, count);
  if (read != UIO_OK) {
    ERROR = true;
    STATUS = uio_status(read);
    COUNTING = false;
    return;
  }

  // The new pulses since last scan go onto the total, in units.
  const float k = (float)K_FACTOR;
  const int64_t fresh = count - state->added;
  if (fresh > 0) {
    TOTAL = (double)TOTAL + (k > 0.0f ? (double)fresh / (double)k : (double)fresh);
    state->pulses += (uint32_t)fresh;
    state->added = count;
  }

  const uint32_t windowMs = uio_millisOf(WINDOW) ? uio_millisOf(WINDOW) : 1000u;
  const uint32_t zeroMs = uio_millisOf(ZERO_AFTER) ? uio_millisOf(ZERO_AFTER) : 30000u;
  const float perSecond = state->rate.update(count, uio_nowMs(), windowMs, zeroMs);
  const uint32_t perMs = uio_millisOf(RATE_PER) ? uio_millisOf(RATE_PER) : 1000u;
  const float pulsesPer = perSecond * (float)perMs / 1000.0f;
  RATE = k > 0.0f ? pulsesPer / k : pulsesPer;
  PULSES = state->pulses;
  COUNTING = true;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
}

END_FUNCTION_BLOCK