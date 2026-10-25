#pragma once

// ESP32-S3 only. A host compile sees an empty translation unit.
#if defined(ARDUINO)

#include <Arduino.h>
#include <Wire.h>

#include <lib/ADS1X15/ADS1X15.h>
#include <lib/GP8XXX/ModbeeGP8XXX.h>

#include "NodeUioTypes.h"

/**
 * The board: 8 digital in, 8 digital out, 4 analog in, 2 analog out, the HAT
 * power switch and the status LED.
 *
 * Private to NodeUioAPI. Callers go through the facade, which validates
 * channels and reports a result; this class assumes both.
 */
class NodeUioBoard {
public:
  NodeUioBoard();

  bool begin();
  void update();
  bool adcReady() const { return _adcUp; }
  bool dacReady() const { return _dacUp; }

  bool digitalIn(uint8_t ch) const { return _din[ch]; }
  bool digitalOut(uint8_t ch) const { return _dout[ch]; }
  void setDigitalOut(uint8_t ch, bool on) { _dout[ch] = on; }

  float analogIn(uint8_t ch) const { return _ain[ch]; }
  int16_t analogInRaw(uint8_t ch) const { return _ainRaw[ch]; }
  UioRange inputRange(uint8_t ch) const { return _inRange[ch]; }
  void setInputRange(uint8_t ch, UioRange r) { _inRange[ch] = r; }

  float analogOut(uint8_t ch) const { return _aout[ch]; }
  int16_t analogOutRaw(uint8_t ch) const { return _aoutRaw[ch]; }
  UioRange outputRange(uint8_t ch) const { return _outRange[ch]; }
  void setOutputRange(uint8_t ch, UioRange r) { _outRange[ch] = r; }
  void setAnalogOut(uint8_t ch, float scaled) { _aout[ch] = scaled; }

  bool hatPower() const { return _hatPower; }
  void setHatPower(bool on);

  /** The WiFi button, true while held. */
  bool button() const { return _button; }
  /** Milliseconds it has been held, 0 when released. */
  uint32_t buttonHeldMs() const { return _buttonHeldMs; }
  /** True once per press, and clears. */
  bool takeShortPress();
  bool takeLongPress();
  void setButtonLongMs(uint32_t ms) { _buttonLongMs = ms ? ms : 1; }
  void setButtonDebounceMs(uint32_t ms) { _buttonDebounceMs = ms; }

  void setLed(uint8_t r, uint8_t g, uint8_t b);

  /** Green when the board is up, red when it is not. Overridden by setLed. */
  void showHealth(bool ok);

  UioCalibration inputCal(uint8_t ch) const { return _inCal[ch]; }
  void setInputCal(uint8_t ch, const UioCalibration& c) { _inCal[ch] = c; }
  UioCalibration outputCal(uint8_t ch) const { return _outCal[ch]; }
  void setOutputCal(uint8_t ch, const UioCalibration& c) { _outCal[ch] = c; }
  bool saveCal();
  bool loadCal();
  void resetCal();

  /**
   * Sets the four holdable outputs to `states` and latches them, so they keep
   * that level through deep sleep. DO05-DO08 are outside the RTC domain and
   * drop regardless.
   */
  void holdOutputs(const bool* states, bool hatInSleep);
  void releaseOutputs();

  /** The GPIO behind digital input `ch` (0 based). */
  static uint8_t inputPin(uint8_t ch) { return _dinPins[ch]; }

  /**
   * THE I2C BUS LOCK. Wire1 carries the board's converters and any expansion
   * module, and the blocks that use it may run in different PLC tasks. Every
   * transaction on it is made holding this. Waits at most `waitMs`; false
   * when it could not be had, and the caller tries again next scan rather
   * than stalling its task.
   */
  static bool lockBus(uint32_t waitMs);
  static void unlockBus();
  /** Wire1 has been begun (begin() ran). */
  static bool busUp();

private:
  float scaleInput(uint8_t ch, int16_t raw) const;
  int16_t scaleOutput(uint8_t ch, float scaled) const;
  void serviceAdc();
  void serviceDac();
  void serviceButton();

  bool _din[UIO_DIGITAL_INPUTS];
  bool _dout[UIO_DIGITAL_OUTPUTS];
  float _ain[UIO_ANALOG_INPUTS];
  int16_t _ainRaw[UIO_ANALOG_INPUTS];
  float _aout[UIO_ANALOG_OUTPUTS];
  int16_t _aoutRaw[UIO_ANALOG_OUTPUTS];
  bool _hatPower;
  bool _button;
  uint32_t _buttonSince;
  uint32_t _buttonHeldMs;
  uint32_t _buttonLongMs;
  uint32_t _buttonDebounceMs;
  bool _buttonLongFired;
  bool _shortPending;
  bool _longPending;
  int16_t _ledShown;

  UioRange _inRange[UIO_ANALOG_INPUTS];
  UioRange _outRange[UIO_ANALOG_OUTPUTS];
  UioCalibration _inCal[UIO_ANALOG_INPUTS];
  UioCalibration _outCal[UIO_ANALOG_OUTPUTS];

  ADS1115 _ads;
  ModbeeGP8413 _dac;
  bool _adcUp;
  bool _dacUp;
  uint8_t _adcChannel;
  uint32_t _adcLastPoll;

  static const uint8_t _dinPins[UIO_DIGITAL_INPUTS];
  static const uint8_t _doutPins[UIO_DIGITAL_OUTPUTS];
};

#endif // ARDUINO
