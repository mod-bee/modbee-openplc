#if defined(ARDUINO)

#include <driver/rtc_io.h>
#include "NodeUioBoard.h"

#include <Preferences.h>
#include <driver/gpio.h>
#include <esp_cpu.h>
#include <esp_rom_sys.h>
#include <esp_timer.h>
#include <soc/gpio_reg.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

#define UIO_LED_PIN        39
#define UIO_HAT_POWER_PIN   9
#define UIO_BUTTON_PIN     40
#define UIO_I2C_SDA        37
#define UIO_I2C_SCL        38
#define UIO_ADS_ADDRESS  0x49
#define UIO_DAC_ADDRESS  0x5F
#define UIO_ADC_POLL_MS     5
#define UIO_DAC_FULL_SCALE 32767

// The last RTC-capable pad on the S3. Above it a pin cannot hold through
// deep sleep.
#define UIO_LAST_RTC_GPIO  21

#define UIO_NVS_NAMESPACE "uio"
#define UIO_NVS_CAL_KEY   "cal"
#define UIO_CAL_VERSION    2

const uint8_t NodeUioBoard::_dinPins[UIO_DIGITAL_INPUTS] = {1, 2, 3, 4, 5, 6, 7, 8};
const uint8_t NodeUioBoard::_doutPins[UIO_DIGITAL_OUTPUTS] = {11, 12, 13, 14, 33, 34, 35, 36};

namespace {

/** What is written to NVS. Versioned so a layout change is refused, not read. */
struct CalBlob {
  uint8_t version;
  UioCalibration in[UIO_ANALOG_INPUTS];
  UioCalibration out[UIO_ANALOG_OUTPUTS];
};

/*
 * THE STATUS LED, SENT BY THE CPU. D10 on the schematic is a WS2812B: one
 * RGB LED with its own controller, on 3.3 V, data on GPIO 39. It takes one
 * 24-bit frame - green, red, blue, most significant bit first - and shows it
 * once the line has been low for a latch time.
 *
 * rgbLedWrite() sent that frame through the core's RMT driver, which is about
 * 19 kB of flash for 24 bits that change a few times a day. Here the CPU sends
 * it: each bit is timed off the cycle counter by a loop in IRAM, with this
 * core's interrupts masked for the 30 us the frame takes. That is necessary,
 * not cautious: many WS2812B parts take a low gap of several microseconds
 * inside a frame as its end, so an interrupt there would latch half a colour,
 * and a flash cache miss mid-frame could do the same (hence IRAM). The other
 * core and its interrupts carry on, and 30 us is a thirtieth of an RTOS tick.
 *
 * Bit timings are the ones rgbLedWrite() used: 0.4 us high for a 0, 0.8 us
 * for a 1, 1.25 us a bit - inside the WS2812B's +/-150 ns either way. The
 * latch is 300 us (the current WS2812B wants 280; older parts 50).
 */
const uint32_t kLedT0HighNs = 400;
const uint32_t kLedT1HighNs = 800;
const uint32_t kLedBitNs = 1250;
const int64_t kLedLatchUs = 300;

portMUX_TYPE s_ledLock = portMUX_INITIALIZER_UNLOCKED;

// The I2C bus lock: a FreeRTOS mutex made on first use - on a scan, never in a
// static initialiser - with the spinlock guarding only its creation.
portMUX_TYPE s_busMakeLock = portMUX_INITIALIZER_UNLOCKED;
SemaphoreHandle_t s_busLock = nullptr;
bool s_busUp = false;
bool s_ledReady = false;
int64_t s_ledLatchedAt = 0;   // esp_timer microseconds when the line last went low

/*
 * One frame, every bit timed from the start of the one before, so the loop's
 * own cost comes out of the low half rather than adding to the period. Times
 * are CPU cycles, worked out by the caller at the clock speed of the moment.
 */
IRAM_ATTR __attribute__((noinline)) void ledFrame(volatile uint32_t* setRegister,
                                                  volatile uint32_t* clearRegister,
                                                  uint32_t mask, const uint8_t* bytes,
                                                  uint32_t zeroHigh, uint32_t oneHigh,
                                                  uint32_t period) {
  uint32_t start = (uint32_t)esp_cpu_get_cycle_count() - period;
  for (int i = 0; i < 3; i++) {
    for (uint8_t bit = 0x80; bit != 0; bit >>= 1) {
      const uint32_t high = (bytes[i] & bit) ? oneHigh : zeroHigh;
      while ((uint32_t)esp_cpu_get_cycle_count() - start < period) {}
      start = (uint32_t)esp_cpu_get_cycle_count();
      *setRegister = mask;
      while ((uint32_t)esp_cpu_get_cycle_count() - start < high) {}
      *clearRegister = mask;
    }
  }
  while ((uint32_t)esp_cpu_get_cycle_count() - start < period) {}
}

} // namespace

NodeUioBoard::NodeUioBoard()
  : _hatPower(false),
    _button(false),
    _buttonSince(0),
    _buttonHeldMs(0),
    _buttonLongMs(2000),
    _buttonDebounceMs(30),
    _buttonLongFired(false),
    _shortPending(false),
    _longPending(false),
    _ledShown(-1),
    _ads(UIO_ADS_ADDRESS, &Wire1),
    _dac(RESOLUTION_15_BIT, UIO_DAC_ADDRESS, &Wire1),
    _adcUp(false),
    _dacUp(false),
    _adcChannel(0),
    _adcLastPoll(0) {
  for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) _din[i] = false;
  for (uint8_t i = 0; i < UIO_DIGITAL_OUTPUTS; i++) _dout[i] = false;
  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) {
    _ain[i] = 0.0f;
    _ainRaw[i] = 0;
    _inRange[i] = UIO_VOLTAGE;
  }
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) {
    _aout[i] = 0.0f;
    _aoutRaw[i] = 0;
    _outRange[i] = UIO_VOLTAGE;
  }
  resetCal();
}

bool NodeUioBoard::begin() {
  // Drop any latch a deep sleep left behind, FIRST. The hold survives the wake
  // and the reset that follows it -- that is what makes an output keep its
  // level while the board is asleep -- and a held pad ignores pinMode and
  // digitalWrite alike. Without this the program comes back up, runs, and
  // cannot move DO01-DO04 or the HAT pin ever again: the board looks like it
  // never woke. Harmless when nothing is held, so it needs no wake-cause test.
  releaseOutputs();

  // Outputs first, before anything that can be slow. Until a pin is driven it
  // is an input, and the driver behind it is in an undefined state.
  for (uint8_t i = 0; i < UIO_DIGITAL_OUTPUTS; i++) {
    pinMode(_doutPins[i], OUTPUT);
    digitalWrite(_doutPins[i], LOW);
  }
  pinMode(UIO_HAT_POWER_PIN, OUTPUT);
  digitalWrite(UIO_HAT_POWER_PIN, LOW);

  // An ext1 sleep left these pads as RTC IOs, and a pad in RTC mode does not
  // answer digitalRead. Hand them back to the GPIO matrix before configuring
  // them, or every input reads as whatever the RTC pad happens to hold.
  for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) rtc_gpio_deinit((gpio_num_t)_dinPins[i]);

  for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) pinMode(_dinPins[i], INPUT);

  // Held low by a 10k pulldown, driven high by the button.
  pinMode(UIO_BUTTON_PIN, INPUT);

  Wire1.begin(UIO_I2C_SDA, UIO_I2C_SCL);
  s_busUp = true;

  // Gain 2 is +/-2.048 V; mode 1 is single shot, so a conversion can be polled
  // rather than waited on; rate 5 is 250 SPS.
  if (_ads.begin()) {
    _ads.setGain(2);
    _ads.setMode(1);
    _ads.setDataRate(5);
    _adcUp = true;
    _ads.requestADC(_adcChannel);
  }

  if (_dac.begin() == 0) {
    _dac.setDACOutRange(_dac.eOutputRange10V);
    _dacUp = true;
  }

  loadCal();

  const bool ok = _adcUp && _dacUp;
  showHealth(ok);
  return ok;
}

void NodeUioBoard::update() {
  for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) _din[i] = digitalRead(_dinPins[i]);
  for (uint8_t i = 0; i < UIO_DIGITAL_OUTPUTS; i++) digitalWrite(_doutPins[i], _dout[i]);

  serviceButton();

  // The converters share Wire1 with any expansion module. Not had within a
  // couple of milliseconds, they are serviced next scan instead.
  if (lockBus(2)) {
    serviceAdc();
    serviceDac();
    unlockBus();
  }
  showHealth(_adcUp && _dacUp);
}

bool NodeUioBoard::lockBus(uint32_t waitMs) {
  if (s_busLock == nullptr) {
    SemaphoreHandle_t made = xSemaphoreCreateMutex();
    portENTER_CRITICAL(&s_busMakeLock);
    if (s_busLock == nullptr) {
      s_busLock = made;
      made = nullptr;
    }
    portEXIT_CRITICAL(&s_busMakeLock);
    if (made != nullptr) vSemaphoreDelete(made);   // another task made it first
    if (s_busLock == nullptr) return false;        // no memory: nothing to lock with
  }
  return xSemaphoreTake(s_busLock, pdMS_TO_TICKS(waitMs)) == pdTRUE;
}

void NodeUioBoard::unlockBus() {
  if (s_busLock != nullptr) xSemaphoreGive(s_busLock);
}

bool NodeUioBoard::busUp() { return s_busUp; }

/*
 * The board's own indicator, per the silkscreen: green means the MCU is up,
 * red means it is not. Written only when it changes, because each write is a
 * 30 us frame with interrupts masked, and the scan pays for it.
 */
void NodeUioBoard::showHealth(bool ok) {
  const int16_t want = ok ? 1 : 0;
  if (_ledShown == want) return;
  _ledShown = want;
  if (ok) setLed(0, 54, 0);
  else setLed(54, 0, 0);
}

/*
 * Edge detection lives here rather than in a block: a block is called once per
 * scan and cannot see a press shorter than that, and there is one button, so
 * two blocks watching it would each consume presses the other never saw.
 */
void NodeUioBoard::serviceButton() {
  const bool down = digitalRead(UIO_BUTTON_PIN);
  const uint32_t now = millis();

  if (down && !_button) {
    _buttonSince = now;
    _buttonLongFired = false;
  }

  if (down) {
    _buttonHeldMs = now - _buttonSince;
    // Contact bounce looks like a press this short, so it is not one yet.
    if (_buttonHeldMs < _buttonDebounceMs) {
      _button = down;
      return;
    }
    if (!_buttonLongFired && _buttonHeldMs >= _buttonLongMs) {
      _buttonLongFired = true;
      _longPending = true;
    }
  } else {
    // A release that never reached the long threshold is a short press, so
    // long as it outlasted the bounce.
    if (_button && !_buttonLongFired && (now - _buttonSince) >= _buttonDebounceMs) {
      _shortPending = true;
    }
    _buttonHeldMs = 0;
  }

  _button = down;
}

bool NodeUioBoard::takeShortPress() {
  const bool pending = _shortPending;
  _shortPending = false;
  return pending;
}

bool NodeUioBoard::takeLongPress() {
  const bool pending = _longPending;
  _longPending = false;
  return pending;
}

void NodeUioBoard::serviceAdc() {
  if (!_adcUp) return;
  if (millis() - _adcLastPoll < UIO_ADC_POLL_MS) return;
  _adcLastPoll = millis();

  if (!_ads.isReady()) return;

  int16_t raw = _ads.getValue();
  _ainRaw[_adcChannel] = raw;
  _ain[_adcChannel] = scaleInput(_adcChannel, raw);  // a negative count reads 0

  _adcChannel = (uint8_t)((_adcChannel + 1) % UIO_ANALOG_INPUTS);
  _ads.requestADC(_adcChannel);
}

void NodeUioBoard::serviceDac() {
  if (!_dacUp) return;
  for (uint8_t ch = 0; ch < UIO_ANALOG_OUTPUTS; ch++) {
    const int16_t raw = scaleOutput(ch, _aout[ch]);
    if (raw == _aoutRaw[ch]) continue;
    _aoutRaw[ch] = raw;
    _dac.setDACOutVoltage(raw, ch);
  }
}

void NodeUioBoard::setHatPower(bool on) {
  _hatPower = on;
  digitalWrite(UIO_HAT_POWER_PIN, on ? HIGH : LOW);
}

void NodeUioBoard::setLed(uint8_t r, uint8_t g, uint8_t b) {
  // A caller taking the LED means health no longer owns it.
  _ledShown = -1;

  if (!s_ledReady) {
    // Low from here on, which is also the first latch: a WS2812B powers up
    // waiting for a frame, and the wait below gives it a clean start.
    pinMode(UIO_LED_PIN, OUTPUT);
    digitalWrite(UIO_LED_PIN, LOW);
    s_ledLatchedAt = esp_timer_get_time();
    s_ledReady = true;
  }

  const uint8_t grb[3] = {g, r, b};
  const uint32_t mask = 1u << (UIO_LED_PIN % 32);
  volatile uint32_t* const setRegister =
      (volatile uint32_t*)(UIO_LED_PIN < 32 ? GPIO_OUT_W1TS_REG : GPIO_OUT1_W1TS_REG);
  volatile uint32_t* const clearRegister =
      (volatile uint32_t*)(UIO_LED_PIN < 32 ? GPIO_OUT_W1TC_REG : GPIO_OUT1_W1TC_REG);

  // The previous frame must have latched before this one starts, or the LED
  // takes this one as more of that one and passes it on to an LED that is not
  // there. Checked inside the lock, so two tasks writing at once queue up
  // rather than run their frames together; waited out OUTSIDE it, so the
  // interrupts are never masked for the wait.
  for (;;) {
    portENTER_CRITICAL(&s_ledLock);
    const int64_t quiet = esp_timer_get_time() - s_ledLatchedAt;
    if (quiet >= kLedLatchUs) {
      const uint32_t cyclesPerUs = esp_rom_get_cpu_ticks_per_us();
      ledFrame(setRegister, clearRegister, mask, grb,
               kLedT0HighNs * cyclesPerUs / 1000, kLedT1HighNs * cyclesPerUs / 1000,
               kLedBitNs * cyclesPerUs / 1000);
      s_ledLatchedAt = esp_timer_get_time();
      portEXIT_CRITICAL(&s_ledLock);
      return;
    }
    portEXIT_CRITICAL(&s_ledLock);
    delayMicroseconds((uint32_t)(kLedLatchUs - quiet));
  }
}

void NodeUioBoard::holdOutputs(const bool* states, bool hatInSleep) {
  // Driven before the latch, because a hold freezes whatever the pin is at.
  for (uint8_t i = 0; i < UIO_HOLDABLE_OUTPUTS; i++) {
    const bool on = states ? states[i] : false;
    _dout[i] = on;
    digitalWrite(_doutPins[i], on);
  }
  for (uint8_t i = UIO_HOLDABLE_OUTPUTS; i < UIO_DIGITAL_OUTPUTS; i++) {
    _dout[i] = false;
    digitalWrite(_doutPins[i], LOW);
  }

  // Same rule as the outputs: drive it, then freeze it. Without this the HAT
  // keeps whatever it happened to be at, so a sensor that has to stay powered
  // through the sleep could not be asked to.
  setHatPower(hatInSleep);

  for (uint8_t i = 0; i < UIO_HOLDABLE_OUTPUTS; i++) {
    gpio_hold_en((gpio_num_t)_doutPins[i]);
  }
  gpio_hold_en((gpio_num_t)UIO_HAT_POWER_PIN);
  gpio_deep_sleep_hold_en();
}

void NodeUioBoard::releaseOutputs() {
  for (uint8_t i = 0; i < UIO_HOLDABLE_OUTPUTS; i++) {
    gpio_hold_dis((gpio_num_t)_doutPins[i]);
  }
  gpio_hold_dis((gpio_num_t)UIO_HAT_POWER_PIN);
  gpio_deep_sleep_hold_dis();
}

float NodeUioBoard::scaleInput(uint8_t ch, int16_t raw) const {
  // A saturated converter reads over range (22 mA / 11 V), see uioScaleInput.
  return uioScaleInput(_inRange[ch], raw, _inCal[ch]);
}

int16_t NodeUioBoard::scaleOutput(uint8_t ch, float value) const {
  const float full = uioFullScale(_outRange[ch]);
  const int32_t low = _outCal[ch].low;
  const int32_t high = _outCal[ch].high;

  float adjusted = value + _outCal[ch].offset;
  if (adjusted < 0.0f) adjusted = 0.0f;
  if (adjusted > full) adjusted = full;

  float raw;
  if (high == low) raw = adjusted * (float)UIO_DAC_FULL_SCALE / full;
  else raw = (float)low + adjusted * (float)(high - low) / full;

  if (raw < 0.0f) raw = 0.0f;
  if (raw > (float)UIO_DAC_FULL_SCALE) raw = (float)UIO_DAC_FULL_SCALE;
  return (int16_t)(raw + 0.5f);
}

void NodeUioBoard::resetCal() {
  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) {
    _inCal[i] = {0.0f, 0, UIO_DAC_FULL_SCALE};
  }
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) {
    _outCal[i] = {0.0f, 0, UIO_DAC_FULL_SCALE};
  }
}

bool NodeUioBoard::saveCal() {
  CalBlob blob;
  blob.version = UIO_CAL_VERSION;
  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) blob.in[i] = _inCal[i];
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) blob.out[i] = _outCal[i];

  Preferences prefs;
  if (!prefs.begin(UIO_NVS_NAMESPACE, false)) return false;
  const size_t written = prefs.putBytes(UIO_NVS_CAL_KEY, &blob, sizeof(blob));
  prefs.end();
  return written == sizeof(blob);
}

bool NodeUioBoard::loadCal() {
  Preferences prefs;
  if (!prefs.begin(UIO_NVS_NAMESPACE, true)) return false;

  CalBlob blob;
  const size_t read = prefs.getBytes(UIO_NVS_CAL_KEY, &blob, sizeof(blob));
  prefs.end();

  // Nothing stored, or stored by a different layout. Either way the declared
  // defaults stand rather than values that would land in the wrong channels.
  if (read != sizeof(blob) || blob.version != UIO_CAL_VERSION) return false;

  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) _inCal[i] = blob.in[i];
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) _outCal[i] = blob.out[i];
  return true;
}

#endif // ARDUINO
