#include "NodeUioAPI.h"

#if defined(ARDUINO)

#include <Arduino.h>
#include <WiFi.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include <driver/rtc_io.h>

#include "NodeUioBoard.h"

#include <Wire.h>
#include <driver/pulse_cnt.h>
#include <esp_heap_caps.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <string.h>

/*
 * The firmware's task list (the editor's Arduino glue, arduino_runtime_glue.h),
 * for SYS_INFO's stack margin: in RTOS mode every IEC task is a FreeRTOS task
 * of that name. Weak, so a firmware without them links, and the margin is then
 * the calling task's.
 */
extern "C" uint32_t runtime_rtos_worker_count(void) __attribute__((weak));
extern "C" const char* runtime_rtos_worker_name(uint32_t worker) __attribute__((weak));

/*
 * The firmware's "save the retained values now" (the editor's Arduino glue,
 * arduino_runtime_glue.h): packs them and commits them through the board's
 * retain store before returning. 0 when committed, else the store's status;
 * 2 when nothing is retained or the board stores nothing.
 *
 * Weak, so the library still links against firmware older than it, where the
 * symbol is then NULL.
 */
extern "C" uint8_t runtime_retain_flush_now(void) __attribute__((weak));

namespace {

NodeUioBoard s_board;
bool s_begun = false;
bool s_asked = false;
UioWakeCause s_wakeCause = UIO_WAKE_NONE;

bool s_radioPolicy = false;
uint32_t s_radioAwakeMs = 300000;
uint32_t s_radioEveryMs = 0;
uint32_t s_radioUntil = 0;
uint32_t s_radioNext = 0;

bool inRange(uint8_t channel, uint8_t count) { return channel < count; }

// The credentials connect() joined with, so a change can be noticed. A copy
// of a few dozen bytes; the radio's own copy is not readable back.
char s_ssid[33];
char s_password[65];

// THE RADIO TASK. Starting the Wi-Fi driver (WiFi.mode(WIFI_STA): its memory and the RF calibration) takes
// seconds, stopping it hundreds of milliseconds. Called from a PLC scan that is a stuck task: the runtime
// stops the PLC (seen 2026-10-14: 2.5 s, safe mode, when Wi-Fi was switched on while the PLC ran). So the
// scan only states what it wants and returns; one small task, made the first time Wi-Fi is wanted, makes
// every driver call, on core 0 (the IEC tasks run on core 1). Each request has a number; the task applies
// the newest and skips the ones it overtook.
struct RadioWant {
  bool on;
  uint32_t number;
  char ssid[33];
  char password[65];
};
portMUX_TYPE s_radioLock = portMUX_INITIALIZER_UNLOCKED;
RadioWant s_radioWant = {};          // under s_radioLock
TaskHandle_t s_radioTask = nullptr;
volatile bool s_driverUp = false;    // the driver is started (set and cleared by the radio task only)
volatile uint32_t s_drops = 0;       // the radio dropped off its network (counted by the event below)
volatile uint8_t s_dropReason = 0;   // the ESP32's reason for the last drop (wifi_err_reason_t)
bool s_eventsOn = false;

// Every drop off the network, with the ESP32's reason: what tells a router kick from a lost beacon or a
// wrong password. Registered once, before the radio first starts.
// A lost IP address counts too (reason 255): the radio stays joined, but nothing can be sent.
void onRadioEvent(arduino_event_id_t event, arduino_event_info_t info) {
  if (event == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) {
    s_dropReason = (uint8_t)info.wifi_sta_disconnected.reason;
  } else if (event == ARDUINO_EVENT_WIFI_STA_LOST_IP) {
    s_dropReason = 255;
  } else {
    return;
  }
  s_drops = s_drops + 1;
}

void radioTask(void*) {
  uint32_t applied = 0;
  bool up = false;
  for (;;) {
    ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    for (;;) {
      RadioWant want;
      portENTER_CRITICAL(&s_radioLock);
      want = s_radioWant;
      portEXIT_CRITICAL(&s_radioLock);
      if (want.number == applied) break;
      applied = want.number;
      if (want.on) {
        if (!s_eventsOn) {
          WiFi.onEvent(onRadioEvent);
          s_eventsOn = true;
        }
        if (!up) {
          WiFi.mode(WIFI_STA);
          up = true;
          s_driverUp = true;
        } else {
          WiFi.disconnect(false);    // new credentials: leave, then join with them
        }
        WiFi.begin(want.ssid, want.password[0] != '\0' ? want.password : nullptr);
      } else if (up) {
        s_driverUp = false;
        up = false;
        WiFi.disconnect(true);
        WiFi.mode(WIFI_OFF);
      }
    }
  }
}

// Asks the radio task for the radio on (with these credentials) or off. Never waits. FALSE when the task
// could not be made (out of memory).
bool radioAsk(bool on, const char* ssid, const char* password) {
  if (s_radioTask == nullptr &&
      xTaskCreatePinnedToCore(radioTask, "uio-radio", 6144, nullptr, 1, &s_radioTask, 0) != pdPASS) {
    s_radioTask = nullptr;
    return false;
  }
  portENTER_CRITICAL(&s_radioLock);
  s_radioWant.on = on;
  strncpy(s_radioWant.ssid, ssid ? ssid : "", sizeof s_radioWant.ssid - 1);
  s_radioWant.ssid[sizeof s_radioWant.ssid - 1] = '\0';
  strncpy(s_radioWant.password, password ? password : "", sizeof s_radioWant.password - 1);
  s_radioWant.password[sizeof s_radioWant.password - 1] = '\0';
  s_radioWant.number++;
  portEXIT_CRITICAL(&s_radioLock);
  xTaskNotifyGive(s_radioTask);
  return true;
}

// The radio's status, read in the scan: while the radio task is starting the driver, it is not up yet.
bool radioJoined() {
  if (s_radioTask != nullptr && !s_driverUp) return false;
  return WiFi.status() == WL_CONNECTED;
}

// One pulse counter per digital input at most; the chip has four.
pcnt_unit_handle_t s_pulseUnit[UIO_DIGITAL_INPUTS];
pcnt_channel_handle_t s_pulseChannel[UIO_DIGITAL_INPUTS];

// Wire1 as an expansion driver sees it: every transaction under the bus lock.
class WireBus : public UioXBus {
public:
  bool probe(uint8_t address) override {
    if (!NodeUioBoard::busUp() || !NodeUioBoard::lockBus(20)) return false;
    Wire1.beginTransmission(address);
    const bool ack = Wire1.endTransmission() == 0;
    NodeUioBoard::unlockBus();
    return ack;
  }
  bool write(uint8_t address, const uint8_t* data, size_t length) override {
    if (!NodeUioBoard::busUp() || !NodeUioBoard::lockBus(20)) return false;
    Wire1.beginTransmission(address);
    Wire1.write(data, length);
    const bool done = Wire1.endTransmission() == 0;
    NodeUioBoard::unlockBus();
    return done;
  }
  bool read(uint8_t address, uint8_t* data, size_t length) override {
    if (!NodeUioBoard::busUp() || !NodeUioBoard::lockBus(20)) return false;
    const size_t got = Wire1.requestFrom(address, length);
    for (size_t i = 0; i < got && i < length; i++) data[i] = (uint8_t)Wire1.read();
    NodeUioBoard::unlockBus();
    return got == length;
  }
  bool writeRead(uint8_t address, const uint8_t* out, size_t outLength,
                 uint8_t* in, size_t inLength) override {
    if (!NodeUioBoard::busUp() || !NodeUioBoard::lockBus(20)) return false;
    Wire1.beginTransmission(address);
    Wire1.write(out, outLength);
    bool done = Wire1.endTransmission(false) == 0;   // repeated start
    if (done) {
      const size_t got = Wire1.requestFrom(address, inLength);
      for (size_t i = 0; i < got && i < inLength; i++) in[i] = (uint8_t)Wire1.read();
      done = got == inLength;
    }
    NodeUioBoard::unlockBus();
    return done;
  }
};

WireBus s_wireBus;

// The smallest stack margin among the named tasks; false when none was found.
bool smallestStack(const char* name, uint32_t& least, char* who) {
  TaskHandle_t task = xTaskGetHandle(name);
  if (task == nullptr) return false;
  const uint32_t margin = (uint32_t)uxTaskGetStackHighWaterMark(task);   // bytes on ESP-IDF
  if (margin < least) {
    least = margin;
    strncpy(who, name, 16);
    who[16] = '\0';
  }
  return true;
}

/*
 * A restart or a deep sleep ends the program without the STOP that would
 * commit what the store is still holding (a change within its save period),
 * so it is saved first. Blocks for the commit: an NVS write of a few KB takes
 * about 10-50 ms. The board goes down whatever the result: a controlled
 * restart that waited on a failing flash would never happen.
 */
uint8_t saveRetainedNow() {
  if (runtime_retain_flush_now == nullptr) return 2;  // older firmware: nothing to call
  return runtime_retain_flush_now();
}

UioWakeCause causeFromEsp() {
  switch (esp_sleep_get_wakeup_cause()) {
    case ESP_SLEEP_WAKEUP_TIMER: return UIO_WAKE_TIMER;
    case ESP_SLEEP_WAKEUP_EXT1:
    case ESP_SLEEP_WAKEUP_GPIO: return UIO_WAKE_INPUT;
    case ESP_SLEEP_WAKEUP_UNDEFINED: return UIO_WAKE_RESET;
    default: return UIO_WAKE_NONE;
  }
}

} // namespace

NodeUioAPI::NodeUioAPI() {}

NodeUioAPI& NodeUioAPI::instance() {
  static NodeUioAPI api;
  return api;
}

UioResult NodeUioAPI::begin() {
  if (s_begun) return UIO_OK;
  s_wakeCause = causeFromEsp();
  s_begun = true;
  return s_board.begin() ? UIO_OK : UIO_NOT_READY;
}

void NodeUioAPI::update() {
  if (s_begun) s_board.update();

  if (!s_radioPolicy) return;
  const uint32_t now = millis();
  // A periodic wake is due, so start another awake window.
  if (s_radioEveryMs != 0 && (int32_t)(now - s_radioNext) >= 0) {
    s_radioNext = now + s_radioEveryMs;
    s_radioUntil = now + s_radioAwakeMs;
  }
}

void NodeUioAPI::setRadioPolicy(bool enabled, uint32_t awakeSeconds, uint32_t wakeEverySeconds) {
  if (enabled && !s_radioPolicy) {
    // Taking over from always-on: nothing is wanted until something asks.
    s_radioUntil = millis();
    s_radioNext = millis() + wakeEverySeconds * 1000UL;
  }
  s_radioPolicy = enabled;
  s_radioAwakeMs = (awakeSeconds ? awakeSeconds : 1) * 1000UL;
  s_radioEveryMs = wakeEverySeconds * 1000UL;
}

void NodeUioAPI::requestRadio() {
  s_radioUntil = millis() + s_radioAwakeMs;
}

bool NodeUioAPI::radioWanted() const {
  if (!s_radioPolicy) return true;   // no policy, no restriction
  return (int32_t)(s_radioUntil - millis()) > 0;
}

uint32_t NodeUioAPI::radioAwakeLeft() const {
  if (!s_radioPolicy) return 0;
  const int32_t left = (int32_t)(s_radioUntil - millis());
  return left > 0 ? (uint32_t)left / 1000UL : 0;
}

bool NodeUioAPI::ready() const { return s_begun && s_board.adcReady() && s_board.dacReady(); }

UioResult NodeUioAPI::digitalIn(uint8_t channel, bool& value) const {
  if (!inRange(channel, UIO_DIGITAL_INPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_begun) return UIO_NOT_READY;
  value = s_board.digitalIn(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::digitalOut(uint8_t channel, bool& value) const {
  if (!inRange(channel, UIO_DIGITAL_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_begun) return UIO_NOT_READY;
  value = s_board.digitalOut(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setDigitalOut(uint8_t channel, bool on) {
  if (!inRange(channel, UIO_DIGITAL_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_begun) return UIO_NOT_READY;
  s_board.setDigitalOut(channel, on);
  return UIO_OK;
}

UioResult NodeUioAPI::analogIn(uint8_t channel, float& value) const {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_board.adcReady()) return UIO_NOT_READY;
  value = s_board.analogIn(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::analogInRaw(uint8_t channel, int16_t& raw) const {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_board.adcReady()) return UIO_NOT_READY;
  raw = s_board.analogInRaw(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setInputRange(uint8_t channel, UioRange range) {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  s_board.setInputRange(channel, range);
  return UIO_OK;
}

UioResult NodeUioAPI::inputRange(uint8_t channel, UioRange& range) const {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  range = s_board.inputRange(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setAnalogOut(uint8_t channel, float value) {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_board.dacReady()) return UIO_NOT_READY;
  s_board.setAnalogOut(channel, value);
  return UIO_OK;
}

UioResult NodeUioAPI::analogOutRaw(uint8_t channel, int16_t& raw) const {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  if (!s_board.dacReady()) return UIO_NOT_READY;
  raw = s_board.analogOutRaw(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setOutputRange(uint8_t channel, UioRange range) {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  s_board.setOutputRange(channel, range);
  return UIO_OK;
}

UioResult NodeUioAPI::outputRange(uint8_t channel, UioRange& range) const {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  range = s_board.outputRange(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::inputCalibration(uint8_t channel, UioCalibration& cal) const {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  cal = s_board.inputCal(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setInputCalibration(uint8_t channel, const UioCalibration& cal) {
  if (!inRange(channel, UIO_ANALOG_INPUTS)) return UIO_INVALID_ARGUMENT;
  s_board.setInputCal(channel, cal);
  return UIO_OK;
}

UioResult NodeUioAPI::outputCalibration(uint8_t channel, UioCalibration& cal) const {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  cal = s_board.outputCal(channel);
  return UIO_OK;
}

UioResult NodeUioAPI::setOutputCalibration(uint8_t channel, const UioCalibration& cal) {
  if (!inRange(channel, UIO_ANALOG_OUTPUTS)) return UIO_INVALID_ARGUMENT;
  s_board.setOutputCal(channel, cal);
  return UIO_OK;
}

UioResult NodeUioAPI::saveCalibration() { return s_board.saveCal() ? UIO_OK : UIO_IO_ERROR; }

UioResult NodeUioAPI::resetCalibration() {
  s_board.resetCal();
  return s_board.saveCal() ? UIO_OK : UIO_IO_ERROR;
}

UioResult NodeUioAPI::setHatPower(bool on) {
  if (!s_begun) return UIO_NOT_READY;
  s_board.setHatPower(on);
  return UIO_OK;
}

bool NodeUioAPI::hatPower() const { return s_board.hatPower(); }

UioResult NodeUioAPI::restart() {
  saveRetainedNow();
  ESP.restart();
  return UIO_OK;  // not reached
}

uint8_t NodeUioAPI::resetReason() const { return (uint8_t)esp_reset_reason(); }

UioResult NodeUioAPI::setLed(uint8_t red, uint8_t green, uint8_t blue) {
  s_board.setLed(red, green, blue);
  return UIO_OK;
}

bool NodeUioAPI::button() const { return s_board.button(); }
uint32_t NodeUioAPI::buttonHeldMs() const { return s_board.buttonHeldMs(); }
bool NodeUioAPI::takeShortPress() { return s_board.takeShortPress(); }
bool NodeUioAPI::takeLongPress() { return s_board.takeLongPress(); }
void NodeUioAPI::setButtonLongMs(uint32_t milliseconds) { s_board.setButtonLongMs(milliseconds); }
void NodeUioAPI::setButtonDebounceMs(uint32_t milliseconds) { s_board.setButtonDebounceMs(milliseconds); }

UioResult NodeUioAPI::connect(const char* ssid, const char* password) {
  if (password == nullptr) password = "";
  // NEW SETTINGS ON A RADIO THIS BROUGHT UP: leave and join again with them.
  // Without this a network changed on a settings page was ignored until the
  // next restart, because a radio already up was simply reported as up. Only
  // our own: a radio the firmware or a protocol library brought up is theirs.
  if (s_asked && ssid != nullptr && ssid[0] != '\0' &&
      (strncmp(ssid, s_ssid, sizeof s_ssid) != 0 ||
       strncmp(password, s_password, sizeof s_password) != 0)) {
    // Joined again at once with the new ones - not merely left, or the
    // core's auto-reconnect would take the radio straight back to the old
    // network before this got another look. By the radio task: never in the scan.
    if (!radioAsk(true, ssid, password)) return UIO_IO_ERROR;
    strncpy(s_ssid, ssid, sizeof s_ssid - 1);
    s_ssid[sizeof s_ssid - 1] = '\0';
    strncpy(s_password, password, sizeof s_password - 1);
    s_password[sizeof s_password - 1] = '\0';
    return UIO_NOT_READY;
  }
  if (radioJoined()) return UIO_OK;
  if (ssid == nullptr || ssid[0] == '\0') return UIO_INVALID_ARGUMENT;

  // Asked once. WiFi.begin() restarts association every call, so repeating it
  // every scan would keep the radio from ever settling. disconnect() clears
  // this, so the pair can be used to duty-cycle the radio.
  if (!s_asked) {
    // The driver start takes seconds: the radio task does it (see radioTask).
    if (!radioAsk(true, ssid, password)) return UIO_IO_ERROR;
    strncpy(s_ssid, ssid, sizeof s_ssid - 1);
    s_ssid[sizeof s_ssid - 1] = '\0';
    strncpy(s_password, password, sizeof s_password - 1);
    s_password[sizeof s_password - 1] = '\0';
    s_asked = true;
  }
  return UIO_NOT_READY;
}

UioResult NodeUioAPI::disconnect() {
  if (!s_asked) return UIO_OK;   // not ours to turn off
  s_asked = false;
  if (!radioAsk(false, nullptr, nullptr)) return UIO_IO_ERROR;   // the driver stop: by the radio task
  return UIO_OK;
}

bool NodeUioAPI::connected() const { return radioJoined(); }

uint32_t NodeUioAPI::radioDrops() const { return s_drops; }
uint8_t NodeUioAPI::radioDropReason() const { return s_dropReason; }

const char* NodeUioAPI::radioDropText(uint8_t reason) {
  switch (reason) {
    case 0: return "";
    case WIFI_REASON_AUTH_EXPIRE: return "auth expired (router)";
    case WIFI_REASON_AUTH_LEAVE: return "router sent it away (auth leave)";
    case WIFI_REASON_ASSOC_EXPIRE: return "association expired (router)";
    case WIFI_REASON_ASSOC_TOOMANY: return "router full (too many clients)";
    case WIFI_REASON_NOT_AUTHED: return "not authenticated";
    case WIFI_REASON_NOT_ASSOCED: return "not associated";
    case WIFI_REASON_ASSOC_LEAVE: return "left the network";
    case WIFI_REASON_DISASSOC_PWRCAP_BAD: return "router: power capability";
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT: return "wrong password? (handshake timeout)";
    case WIFI_REASON_BEACON_TIMEOUT: return "lost the router's beacons";
    case WIFI_REASON_NO_AP_FOUND: return "network not found";
    case WIFI_REASON_AUTH_FAIL: return "login failed (password?)";
    case WIFI_REASON_ASSOC_FAIL: return "association failed";
    case WIFI_REASON_HANDSHAKE_TIMEOUT: return "wrong password? (handshake)";
    case WIFI_REASON_CONNECTION_FAIL: return "connection failed";
    case 255: return "lost its IP address (DHCP)";
    default: return "dropped (see the reason code)";
  }
}

uint32_t NodeUioAPI::address() const {
  if (!radioJoined()) return 0;
  return (uint32_t)WiFi.localIP();
}

int32_t NodeUioAPI::signalStrength() const {
  if (!radioJoined()) return 0;
  return WiFi.RSSI();
}

UioResult NodeUioAPI::sleep(UioSleepMode mode, uint32_t seconds, uint8_t wakeInputMask,
                            bool hatInSleep, bool ledInSleep,
                            const bool* outputsInSleep) {
  if (seconds == 0 && wakeInputMask == 0) return UIO_INVALID_ARGUMENT;

  // Start from nothing. Both enables ACCUMULATE -- the ext1 mask appends to
  // whatever was armed before, and a timer stays armed until it is replaced --
  // so a second light sleep would otherwise inherit the first one's sources
  // and wake on an input this call never asked for.
  esp_sleep_disable_wakeup_source(ESP_SLEEP_WAKEUP_ALL);

  if (seconds > 0) esp_sleep_enable_timer_wakeup((uint64_t)seconds * 1000000ULL);

  if (wakeInputMask != 0) {
    uint64_t pins = 0;
    for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) {
      if (wakeInputMask & (1 << i)) pins |= (1ULL << (i + 1));  // DI01..DI08 are GPIO 1..8
    }
    // ext1 switches each pad to RTC IO, and an RTC IO brings its OWN pulls --
    // the pad does not inherit what pinMode() set. On this part they come up
    // pulled UP, which fights the board's pulldown and can leave the pin high
    // enough to satisfy ANY_HIGH before the sleep even starts. State them.
    for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) {
      if ((wakeInputMask & (1 << i)) == 0) continue;
      const gpio_num_t pad = (gpio_num_t)(i + 1);
      rtc_gpio_pullup_dis(pad);
      rtc_gpio_pulldown_en(pad);
    }
    if (esp_sleep_enable_ext1_wakeup(pins, ESP_EXT1_WAKEUP_ANY_HIGH) != ESP_OK) {
      return UIO_INVALID_ARGUMENT;
    }
  }

  if (mode == UIO_DEEP_SLEEP) {
    // Deep sleep restarts the program: save the retained values first. Light
    // sleep keeps RAM and carries on, so the store saves on its own schedule.
    saveRetainedNow();
    // The RGB part latches its colour and keeps it on its own supply, so this
    // survives the sleep with no pin hold. Blue because green and red already
    // mean up and not-up; dark when the caller would rather not pay for it.
    s_board.setLed(0, 0, ledInSleep ? UIO_LED_SLEEP_LEVEL : 0);
    s_board.holdOutputs(outputsInSleep, hatInSleep);
    // Normally never returns. It does return when the request is REJECTED --
    // a wake source already satisfied when the sleep is asked for. The latch
    // has to come back off in that case or the program keeps running with its
    // outputs frozen at their sleep levels, which is the failure this whole
    // path exists to avoid.
    const esp_err_t rejected = esp_deep_sleep_try_to_start();
    s_board.releaseOutputs();
    s_board.update();
    s_wakeCause = causeFromEsp();
    return rejected == ESP_ERR_SLEEP_REJECT ? UIO_NOT_READY : UIO_IO_ERROR;
  }

  // Light sleep keeps every pin as it is, so the four holdable ones are set
  // but not latched, and the rest carry on.
  if (outputsInSleep != nullptr) {
    for (uint8_t i = 0; i < UIO_HOLDABLE_OUTPUTS; i++) {
      s_board.setDigitalOut(i, outputsInSleep[i]);
    }
  }
  s_board.setHatPower(hatInSleep);
  s_board.update();
  // After update(), or the health repaint would put green straight back.
  s_board.setLed(0, 0, ledInSleep ? UIO_LED_SLEEP_LEVEL : 0);

  // Rejected for the same reason deep sleep is, and the return is the only
  // way to tell: a rejected light sleep leaves the wake cause UNDEFINED, which
  // reads as UIO_WAKE_RESET and is indistinguishable from a normal boot.
  const esp_err_t slept = esp_light_sleep_start();
  s_wakeCause = causeFromEsp();
  return slept == ESP_OK ? UIO_OK : UIO_NOT_READY;
}

UioWakeCause NodeUioAPI::wakeCause() const { return s_wakeCause; }

// --- Pulse counting -----------------------------------------------------------

UioResult NodeUioAPI::pulseStart(uint8_t channel, uint32_t glitchNs) {
  if (!inRange(channel, UIO_DIGITAL_INPUTS)) return UIO_INVALID_ARGUMENT;
  if (s_pulseUnit[channel] != nullptr) return UIO_OK;

  // Counts to the 16-bit limit and is accumulated past it by the driver
  // (accum_count with a watch point at the limit), so pulseCount() is
  // cumulative whatever the rate.
  pcnt_unit_config_t unitConfig = {};
  unitConfig.low_limit = -1;
  unitConfig.high_limit = 32767;
  unitConfig.flags.accum_count = 1;
  pcnt_unit_handle_t unit = nullptr;
  const esp_err_t made = pcnt_new_unit(&unitConfig, &unit);
  if (made == ESP_ERR_NOT_FOUND) return UIO_TOO_LARGE;   // all four in use
  if (made != ESP_OK) return UIO_IO_ERROR;

  if (glitchNs > 0) {
    pcnt_glitch_filter_config_t filter = {};
    filter.max_glitch_ns = glitchNs > 12000 ? 12000 : glitchNs;
    pcnt_unit_set_glitch_filter(unit, &filter);
  }

  pcnt_chan_config_t channelConfig = {};
  channelConfig.edge_gpio_num = NodeUioBoard::inputPin(channel);
  channelConfig.level_gpio_num = -1;
  pcnt_channel_handle_t pcntChannel = nullptr;
  if (pcnt_new_channel(unit, &channelConfig, &pcntChannel) != ESP_OK) {
    pcnt_del_unit(unit);
    return UIO_IO_ERROR;
  }
  // Rising edges count; falling edges do nothing.
  pcnt_channel_set_edge_action(pcntChannel, PCNT_CHANNEL_EDGE_ACTION_INCREASE,
                               PCNT_CHANNEL_EDGE_ACTION_HOLD);
  pcnt_unit_add_watch_point(unit, unitConfig.high_limit);
  if (pcnt_unit_enable(unit) != ESP_OK || pcnt_unit_clear_count(unit) != ESP_OK ||
      pcnt_unit_start(unit) != ESP_OK) {
    pcnt_del_channel(pcntChannel);
    pcnt_del_unit(unit);
    return UIO_IO_ERROR;
  }
  s_pulseUnit[channel] = unit;
  s_pulseChannel[channel] = pcntChannel;
  return UIO_OK;
}

UioResult NodeUioAPI::pulseStop(uint8_t channel) {
  if (!inRange(channel, UIO_DIGITAL_INPUTS)) return UIO_INVALID_ARGUMENT;
  pcnt_unit_handle_t unit = s_pulseUnit[channel];
  if (unit == nullptr) return UIO_OK;
  pcnt_unit_stop(unit);
  pcnt_unit_disable(unit);
  pcnt_del_channel(s_pulseChannel[channel]);
  pcnt_del_unit(unit);
  s_pulseUnit[channel] = nullptr;
  s_pulseChannel[channel] = nullptr;
  return UIO_OK;
}

UioResult NodeUioAPI::pulseCount(uint8_t channel, int64_t& count) const {
  if (!inRange(channel, UIO_DIGITAL_INPUTS)) return UIO_INVALID_ARGUMENT;
  if (s_pulseUnit[channel] == nullptr) return UIO_NOT_READY;
  int value = 0;
  if (pcnt_unit_get_count(s_pulseUnit[channel], &value) != ESP_OK) return UIO_IO_ERROR;
  count = (int64_t)value;
  return UIO_OK;
}

// --- The I2C expansion bus ------------------------------------------------------

UioResult NodeUioAPI::i2cProbe(uint8_t address, bool& present) {
  present = false;
  if (!NodeUioBoard::busUp()) return UIO_NOT_READY;
  if (address < UIO_X_FIRST_ADDRESS || address > UIO_X_LAST_ADDRESS) return UIO_INVALID_ARGUMENT;
  if (!NodeUioBoard::lockBus(20)) return UIO_NOT_READY;
  Wire1.beginTransmission(address);
  present = Wire1.endTransmission() == 0;
  NodeUioBoard::unlockBus();
  return UIO_OK;
}

UioXBus* NodeUioAPI::expansionBus() {
  return NodeUioBoard::busUp() ? &s_wireBus : nullptr;
}

// --- The controller ---------------------------------------------------------------

UioResult NodeUioAPI::systemInfo(UioSysInfo& info) const {
  memset(&info, 0, sizeof info);
  const uint32_t internal = MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT;
  info.heapFree = (uint32_t)heap_caps_get_free_size(internal);
  info.heapMin = (uint32_t)heap_caps_get_minimum_free_size(internal);
  info.heapLargest = (uint32_t)heap_caps_get_largest_free_block(internal);
  info.psramFree = (uint32_t)heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
  info.psramSize = (uint32_t)heap_caps_get_total_size(MALLOC_CAP_SPIRAM);
  info.uptimeMs = (uint64_t)(esp_timer_get_time() / 1000);
  info.resetReason = (uint8_t)esp_reset_reason();

  // The PLC's tasks: one per IEC task in RTOS mode, and the firmware's three
  // service tasks. Without them (a firmware with no RTOS), the calling task.
  uint32_t least = 0xFFFFFFFFu;
  bool found = false;
  if (runtime_rtos_worker_count != nullptr && runtime_rtos_worker_name != nullptr) {
    const uint32_t workers = runtime_rtos_worker_count();
    for (uint32_t w = 0; w < workers; w++) {
      const char* name = runtime_rtos_worker_name(w);
      if (name != nullptr) found = smallestStack(name, least, info.stackTask) || found;
    }
  }
  static const char* const services[] = {"plc_dispatch", "plc_modbus", "plc_protocols"};
  for (size_t i = 0; i < sizeof services / sizeof services[0]; i++) {
    found = smallestStack(services[i], least, info.stackTask) || found;
  }
  if (!found) {
    least = (uint32_t)uxTaskGetStackHighWaterMark(nullptr);
    const char* name = pcTaskGetName(nullptr);
    strncpy(info.stackTask, name != nullptr ? name : "", 16);
    info.stackTask[16] = '\0';
  }
  info.stackMin = least;
  return UIO_OK;
}

void* uioAllocLarge(size_t bytes) {
  if (bytes == 0) return nullptr;
  return heap_caps_malloc_prefer(bytes, 2, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT,
                                 MALLOC_CAP_DEFAULT);
}

void uioFreeLarge(void* pointer) {
  if (pointer != nullptr) heap_caps_free(pointer);
}

#else // !ARDUINO

#include <stdlib.h>

void* uioAllocLarge(size_t bytes) { return bytes ? malloc(bytes) : nullptr; }
void uioFreeLarge(void* pointer) { free(pointer); }

NodeUioAPI::NodeUioAPI() {}

NodeUioAPI& NodeUioAPI::instance() {
  static NodeUioAPI api;
  return api;
}

UioResult NodeUioAPI::begin() { return UIO_UNSUPPORTED; }
void NodeUioAPI::update() {}
bool NodeUioAPI::ready() const { return false; }

UioResult NodeUioAPI::digitalIn(uint8_t, bool&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::digitalOut(uint8_t, bool&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::setDigitalOut(uint8_t, bool) { return UIO_UNSUPPORTED; }

UioResult NodeUioAPI::analogIn(uint8_t, float&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::analogInRaw(uint8_t, int16_t&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::setInputRange(uint8_t, UioRange) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::inputRange(uint8_t, UioRange&) const { return UIO_UNSUPPORTED; }

UioResult NodeUioAPI::setAnalogOut(uint8_t, float) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::analogOutRaw(uint8_t, int16_t&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::setOutputRange(uint8_t, UioRange) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::outputRange(uint8_t, UioRange&) const { return UIO_UNSUPPORTED; }

UioResult NodeUioAPI::inputCalibration(uint8_t, UioCalibration&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::setInputCalibration(uint8_t, const UioCalibration&) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::outputCalibration(uint8_t, UioCalibration&) const { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::setOutputCalibration(uint8_t, const UioCalibration&) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::saveCalibration() { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::resetCalibration() { return UIO_UNSUPPORTED; }

UioResult NodeUioAPI::setHatPower(bool) { return UIO_UNSUPPORTED; }
bool NodeUioAPI::hatPower() const { return false; }
UioResult NodeUioAPI::restart() { return UIO_UNSUPPORTED; }
uint8_t NodeUioAPI::resetReason() const { return 0; }
UioResult NodeUioAPI::setLed(uint8_t, uint8_t, uint8_t) { return UIO_UNSUPPORTED; }
bool NodeUioAPI::button() const { return false; }
uint32_t NodeUioAPI::buttonHeldMs() const { return 0; }
bool NodeUioAPI::takeShortPress() { return false; }
bool NodeUioAPI::takeLongPress() { return false; }
void NodeUioAPI::setButtonLongMs(uint32_t) {}
void NodeUioAPI::setButtonDebounceMs(uint32_t) {}

UioResult NodeUioAPI::connect(const char*, const char*) { return UIO_UNSUPPORTED; }
uint32_t NodeUioAPI::radioDrops() const { return 0; }
uint8_t NodeUioAPI::radioDropReason() const { return 0; }
const char* NodeUioAPI::radioDropText(uint8_t) { return ""; }
UioResult NodeUioAPI::disconnect() { return UIO_UNSUPPORTED; }
bool NodeUioAPI::connected() const { return false; }
uint32_t NodeUioAPI::address() const { return 0; }
int32_t NodeUioAPI::signalStrength() const { return 0; }

UioResult NodeUioAPI::sleep(UioSleepMode, uint32_t, uint8_t, bool, bool, const bool*) { return UIO_UNSUPPORTED; }
void NodeUioAPI::setRadioPolicy(bool, uint32_t, uint32_t) {}
void NodeUioAPI::requestRadio() {}
bool NodeUioAPI::radioWanted() const { return false; }
uint32_t NodeUioAPI::radioAwakeLeft() const { return 0; }
UioWakeCause NodeUioAPI::wakeCause() const { return UIO_WAKE_NONE; }

UioResult NodeUioAPI::pulseStart(uint8_t, uint32_t) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::pulseStop(uint8_t) { return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::pulseCount(uint8_t, int64_t& count) const { count = 0; return UIO_UNSUPPORTED; }
UioResult NodeUioAPI::i2cProbe(uint8_t, bool& present) { present = false; return UIO_UNSUPPORTED; }
UioXBus* NodeUioAPI::expansionBus() { return nullptr; }
UioResult NodeUioAPI::systemInfo(UioSysInfo& info) const {
  info = UioSysInfo();
  return UIO_UNSUPPORTED;
}

#endif // ARDUINO
