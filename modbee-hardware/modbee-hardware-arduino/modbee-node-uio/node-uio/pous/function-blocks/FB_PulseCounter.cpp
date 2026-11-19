(* Counts the pulses of a flow meter (or any pulse output) on a digital input,
in hardware, and turns them into a total and a rate.

fTotal      the running total, in your units. YOUR variable: the block adds to
            it, so make it RETAIN and it survives a power cut. Reset it by
            writing 0.
nInputNumber  the input, 1..8 (DI01..DI08).
fPulsesPerUnit  pulses per unit, from the meter's plate: 100.0 for 100 pulses a
            litre gives litres. 0 counts pulses as units.
tRateTimeBase  the rate's time base: T#1s gives units a second, T#1m a minute,
            T#1h an hour. T#1s if left at T#0s.
tMinPulseLength  pulses shorter than this are noise and ignored. The hardware's
            limit is about 12 us; longer is held there - see below for contact
            meters.
tRateWindow  the rate is measured over at least this long. T#1s if left at
            T#0s.
tRateZeroAfter  no pulse for this long and the rate reads 0. T#30s if left at
            T#0s. Set it above the slowest pulse gap you expect.
bEnable     counts while TRUE. TRUE unless you say otherwise.

fRate        units per tRateTimeBase.
nPulseCount  pulses since counting started.
bValid      the counter is running.
bError      the input could not be counted.
eErrorId    why. UIO_OK when fine.
              UIO_INVALID_ARGUMENT  nInputNumber is not 1..8
              UIO_TOO_LARGE         all four of the chip's counters are taken
              UIO_UNSUPPORTED       not on a ModBee Node (the Runtime)

---

  VAR RETAIN  flowTotal : LREAL;  END_VAR
  flow( fTotal := flowTotal, nInputNumber := 3, fPulsesPerUnit := 100.0, tRateTimeBase := T#1h );
  (\* flowTotal in litres, flow.fRate in litres an hour *\)

THE CHIP COUNTS, NOT THE SCAN. The ESP32-S3's pulse counter sees every rising
edge on the input, so a fast meter loses nothing however long the scan; the
block only reads the count. Four inputs can be counted at once - the chip has
four counters. The input still reads normally on FB_DigitalInputs.

THE fRate suits a fast meter and a slow one alike: pulses over at least tRateWindow
when they come fast, the time between them when they come slowly - one pulse
every ten seconds reads steadily, not 1 then 0. When the pulses stop it falls
away, and is 0 after tRateZeroAfter.

THE fTotal IS YOURS. The block adds each scan's new pulses (divided by
fPulsesPerUnit) to fTotal, so a retained fTotal carries over a power cut and a
restart, and nothing is counted twice. LREAL, because a REAL total of a
meter that has run for years loses its small increments. Pulses that arrive
while the PLC is off are not counted.

A CONTACT (REED) METER bounces for milliseconds, far beyond the filter. Use
a meter with a solid-state (open-collector) output, or an RC filter on the
input. *)

FUNCTION_BLOCK FB_PulseCounter
  VAR_IN_OUT
    fTotal : LREAL; (* the running total in your units; your RETAIN variable, the block adds to it; write 0 to reset *)
  END_VAR
  VAR_INPUT
    nInputNumber : USINT; (* which digital input counts, 1..8 (DI01..DI08) *)
    fPulsesPerUnit : REAL; (* pulses per unit from the meter's plate (K-factor); 0 = count pulses *)
    tRateTimeBase : TIME; (* the rate's time base: T#1s per second, T#1m per minute, T#1h per hour; T#0s = T#1s *)
    tMinPulseLength : TIME; (* pulses shorter than this are noise and ignored (hardware limit about 12 us) *)
    tRateWindow : TIME; (* the rate is measured over at least this long; T#0s = T#1s *)
    tRateZeroAfter : TIME; (* no pulse for this long and the rate reads 0; T#0s = T#30s *)
    bEnable : BOOL := TRUE; (* counts while TRUE *)
  END_VAR
  VAR_OUTPUT
    fRate : REAL; (* units per tRateTimeBase *)
    nPulseCount : UDINT; (* pulses since counting started *)
    bValid : BOOL; (* fRate and nPulseCount are valid: the hardware counter is running *)
    bError : BOOL; (* the input could not be counted *)
    eErrorId : E_UioResult; (* why: INVALID_ARGUMENT (input not 1..8), TOO_LARGE (all four counters taken), UNSUPPORTED (Runtime) *)
  END_VAR
  VAR
    fbState : __XWORD;
    fbChannel : USINT;
  END_VAR
#include <NodeUioAPI.h>
#include <NodeUioPulse.h>
#include <new>

E_UIORESULT uio_status(UioResult result);
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
  fRate = 0.0f;
  nPulseCount = 0;
  bValid = false;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
  fbState = (strucpp::XWORD_t)0;
  fbChannel = 0;
}

void loop()
{
  const uint8_t wanted = (bool)bEnable ? (uint8_t)nInputNumber : 0;
  if (wanted > UIO_DIGITAL_INPUTS) {
    bValid = false;
    fRate = 0.0f;
    bError = true;
    eErrorId = E_UIORESULT::UIO_INVALID_ARGUMENT;
    return;
  }

  UioPulseState* state = (UioPulseState*)(uintptr_t)(strucpp::XWORD_t)fbState;
  if (state == nullptr) {
    state = new (std::nothrow) UioPulseState();
    if (state == nullptr) {
      bError = true;
      eErrorId = E_UIORESULT::UIO_TOO_LARGE;
      return;
    }
    fbState = (strucpp::XWORD_t)(uintptr_t)state;
  }

  // Started, stopped, or moved to another input.
  if (wanted != (uint8_t)fbChannel) {
    if ((uint8_t)fbChannel != 0) uio().pulseStop((uint8_t)fbChannel - 1);
    fbChannel = 0;
    bValid = false;
    fRate = 0.0f;
    if (wanted == 0) {
      bError = false;
      eErrorId = E_UIORESULT::UIO_OK;
      return;
    }
    uint32_t glitchNs = 0;
    {
      const int64_t ns = tMinPulseLength.get();
      glitchNs = ns <= 0 ? 0u : (ns > 12000 ? 12000u : (uint32_t)ns);
    }
    const UioResult started = uio().pulseStart(wanted - 1, glitchNs);
    if (started != UIO_OK) {
      bError = true;
      eErrorId = uio_status(started);
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
    bError = true;
    eErrorId = uio_status(read);
    bValid = false;
    return;
  }

  // The new pulses since last scan go onto the total, in units.
  const float k = (float)fPulsesPerUnit;
  const int64_t fresh = count - state->added;
  if (fresh > 0) {
    fTotal = (double)fTotal + (k > 0.0f ? (double)fresh / (double)k : (double)fresh);
    state->pulses += (uint32_t)fresh;
    state->added = count;
  }

  const uint32_t windowMs = uio_millisOf(tRateWindow) ? uio_millisOf(tRateWindow) : 1000u;
  const uint32_t zeroMs = uio_millisOf(tRateZeroAfter) ? uio_millisOf(tRateZeroAfter) : 30000u;
  const float perSecond = state->rate.update(count, uio_nowMs(), windowMs, zeroMs);
  const uint32_t perMs = uio_millisOf(tRateTimeBase) ? uio_millisOf(tRateTimeBase) : 1000u;
  const float pulsesPer = perSecond * (float)perMs / 1000.0f;
  fRate = k > 0.0f ? pulsesPer / k : pulsesPer;
  nPulseCount = state->pulses;
  bValid = true;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
}

END_FUNCTION_BLOCK