#pragma once

// No Arduino headers: the rate arithmetic behind PULSE_COUNT, tested on a host.
#include <stdint.h>

/*
 * A RATE FROM A PULSE COUNT
 *
 * The hardware counter (the ESP32-S3's PCNT) counts every edge; this turns the
 * count into a rate that suits a flow meter, which may give a hundred pulses
 * a second at full flow or one every ten seconds at a trickle.
 *
 *   - Fast: the pulses over at least `windowMs`, measured from one pulse to
 *     another, so the answer is exact whatever the scan time.
 *   - Slow: from the time between pulses, so one pulse every ten seconds
 *     reads 0.1 /s instead of jumping between 0 and 1.
 *   - Stopping: with no new pulse, the rate can be no more than one pulse over
 *     the time since the last one, so it falls away smoothly rather than
 *     holding its last value; and it is 0 once nothing has come for `zeroMs`.
 *
 * Times are the caller's milliseconds (millis() on the board); counts are
 * cumulative and may only grow.
 */
struct UioPulseRate {
  bool havePulse = false;
  int64_t lastCount = 0;
  uint32_t lastPulseMs = 0;
  int64_t refCount = 0;
  uint32_t refMs = 0;
  float rate = 0.0f;   // pulses per second

  void reset(int64_t count) {
    havePulse = false;
    lastCount = count;
    rate = 0.0f;
  }

  float update(int64_t count, uint32_t nowMs, uint32_t windowMs, uint32_t zeroMs) {
    if (windowMs == 0) windowMs = 1000;
    if (count != lastCount) {
      lastCount = count;
      lastPulseMs = nowMs;
      if (!havePulse) {
        // The first pulse after a stop starts the measurement; the rate needs
        // a second one.
        havePulse = true;
        refCount = count;
        refMs = nowMs;
      } else if ((uint32_t)(nowMs - refMs) >= windowMs && count > refCount &&
                 nowMs != refMs) {
        rate = (float)((double)(count - refCount) * 1000.0 / (double)(uint32_t)(nowMs - refMs));
        refCount = count;
        refMs = nowMs;
      }
    }
    if (!havePulse) {
      rate = 0.0f;
      return rate;
    }
    const uint32_t since = nowMs - lastPulseMs;
    if (zeroMs != 0 && since >= zeroMs) {
      // Stopped.
      havePulse = false;
      rate = 0.0f;
      return rate;
    }
    if (since > 0) {
      const float bound = 1000.0f / (float)since;
      if (rate > bound) rate = bound;   // slower than it was: falls away
    }
    return rate;
  }
};
