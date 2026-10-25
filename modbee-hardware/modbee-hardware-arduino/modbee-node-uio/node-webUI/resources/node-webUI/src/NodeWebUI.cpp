#include "NodeWebUI.h"

#if defined(ARDUINO)

#include <ArduinoJson.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <LittleFS.h>
#include <WiFi.h>

#include <NodeUioAPI.h>

/** How often the socket pushes a state update, in milliseconds. */
#define NODE_WEBUI_PUSH_MS 1000

struct NodeWebUI::Impl {
  explicit Impl(uint16_t port) : server(port), ws("/ws"), lastPush(0), running(false) {}

  bool begin();
  void update();
  void sendState();
  void onSocketEvent(AsyncWebSocket* server, AsyncWebSocketClient* client, AwsEventType type,
                     void* arg, uint8_t* data, size_t len);
  void applyCalibration(const JsonObject& calibration);

  AsyncWebServer server;
  AsyncWebSocket ws;
  JsonDocument json;
  uint32_t lastPush;
  bool running;
};

bool NodeWebUI::Impl::begin() {
  if (running) return true;

  // The page lives in the filesystem image, which is uploaded separately. A
  // missing one serves 404s rather than failing to start, so the socket still
  // works and the board is still reachable.
  if (!LittleFS.begin(true)) {
    Serial.println("web ui: no filesystem");
  }

  // Nothing here brings a network up. Whoever owns the radio does that.
  if (WiFi.status() != WL_CONNECTED) return false;

  server.serveStatic("/", LittleFS, "/www/").setDefaultFile("index.html");

  ws.onEvent([this](AsyncWebSocket* server, AsyncWebSocketClient* client, AwsEventType type,
                     void* arg, uint8_t* data, size_t len) {
    onSocketEvent(server, client, type, arg, data, len);
  });
  server.addHandler(&ws);

  server.onNotFound([](AsyncWebServerRequest* request) {
    request->send(404, "text/plain", "Not found");
  });

  server.begin();
  running = true;
  return true;
}

void NodeWebUI::Impl::update() {
  if (!running) {
    begin();
    return;
  }

  ws.cleanupClients();
  if (millis() - lastPush < NODE_WEBUI_PUSH_MS) return;
  lastPush = millis();
  sendState();
}

void NodeWebUI::Impl::sendState() {
  json.clear();

  JsonObject io = json["io"].to<JsonObject>();
  JsonArray di = io["di"].to<JsonArray>();
  JsonArray dout = io["do"].to<JsonArray>();
  JsonArray ai = io["ai_scaled"].to<JsonArray>();
  JsonArray ao = io["ao_scaled"].to<JsonArray>();

  for (uint8_t i = 0; i < UIO_DIGITAL_INPUTS; i++) {
    bool on = false;
    uio().digitalIn(i, on);
    di.add(on);
  }
  for (uint8_t i = 0; i < UIO_DIGITAL_OUTPUTS; i++) {
    bool on = false;
    uio().digitalOut(i, on);
    dout.add(on);
  }
  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) {
    float value = 0.0f;
    uio().analogIn(i, value);
    ai.add(value);
  }
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) {
    int16_t raw = 0;
    uio().analogOutRaw(i, raw);
    ao.add(raw);
  }

  JsonObject cal = json["calibration"].to<JsonObject>();
  JsonArray adcZero = cal["adc_zero_offsets"].to<JsonArray>();
  JsonArray adcLow = cal["adc_low"].to<JsonArray>();
  JsonArray adcHigh = cal["adc_high"].to<JsonArray>();
  JsonArray dacZero = cal["dac_zero_offsets"].to<JsonArray>();
  JsonArray dacLow = cal["dac_low"].to<JsonArray>();
  JsonArray dacHigh = cal["dac_high"].to<JsonArray>();

  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) {
    UioCalibration c = {0.0f, 0, 0};
    uio().inputCalibration(i, c);
    adcZero.add(c.offset);
    adcLow.add(c.low);
    adcHigh.add(c.high);
  }
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) {
    UioCalibration c = {0.0f, 0, 0};
    uio().outputCalibration(i, c);
    dacZero.add(c.offset);
    dacLow.add(c.low);
    dacHigh.add(c.high);
  }

  // Reported, not configured: the page shows the connection rather than
  // offering to change it.
  JsonObject network = json["network"].to<JsonObject>();
  const bool ap = WiFi.getMode() == WIFI_AP;
  network["mode"] = ap ? "AP" : "STA";
  network["ssid"] = ap ? WiFi.softAPSSID() : WiFi.SSID();
  network["ip"] = ap ? WiFi.softAPIP().toString() : WiFi.localIP().toString();

  String out;
  serializeJson(json, out);
  ws.textAll(out);
}

void NodeWebUI::Impl::onSocketEvent(AsyncWebSocket*, AsyncWebSocketClient*, AwsEventType type,
                              void* arg, uint8_t* data, size_t len) {
  if (type == WS_EVT_CONNECT) {
    sendState();
    return;
  }
  if (type != WS_EVT_DATA) return;

  AwsFrameInfo* info = (AwsFrameInfo*)arg;
  if (!info->final || info->index != 0 || info->len != len || info->opcode != WS_TEXT) return;

  json.clear();
  if (deserializeJson(json, data, len)) return;
  if (!json["calibration"].is<JsonObject>()) return;

  applyCalibration(json["calibration"]);
}

void NodeWebUI::Impl::applyCalibration(const JsonObject& calibration) {
  for (uint8_t i = 0; i < UIO_ANALOG_INPUTS; i++) {
    UioCalibration c = {0.0f, 0, 0};
    if (uio().inputCalibration(i, c) != UIO_OK) continue;
    if (calibration["adc_zero_offsets"][i].is<float>()) c.offset = calibration["adc_zero_offsets"][i];
    if (calibration["adc_low"][i].is<int16_t>()) c.low = calibration["adc_low"][i];
    if (calibration["adc_high"][i].is<int16_t>()) c.high = calibration["adc_high"][i];
    uio().setInputCalibration(i, c);
  }
  for (uint8_t i = 0; i < UIO_ANALOG_OUTPUTS; i++) {
    UioCalibration c = {0.0f, 0, 0};
    if (uio().outputCalibration(i, c) != UIO_OK) continue;
    if (calibration["dac_zero_offsets"][i].is<float>()) c.offset = calibration["dac_zero_offsets"][i];
    if (calibration["dac_low"][i].is<int16_t>()) c.low = calibration["dac_low"][i];
    if (calibration["dac_high"][i].is<int16_t>()) c.high = calibration["dac_high"][i];
    uio().setOutputCalibration(i, c);
  }

  uio().saveCalibration();
}

NodeWebUI::NodeWebUI(uint16_t port) : _impl(new Impl(port)) {}
NodeWebUI::~NodeWebUI() { delete _impl; }
bool NodeWebUI::begin() { return _impl->begin(); }
void NodeWebUI::update() { _impl->update(); }
bool NodeWebUI::running() const { return _impl->running; }
uint32_t NodeWebUI::clients() const { return _impl->ws.count(); }

#else // !ARDUINO

// Off the board there is nothing to serve. The block still compiles, which is
// what a host build of the generated block file needs.
struct NodeWebUI::Impl {};

NodeWebUI::NodeWebUI(uint16_t) : _impl(nullptr) {}
NodeWebUI::~NodeWebUI() {}
bool NodeWebUI::begin() { return false; }
void NodeWebUI::update() {}
bool NodeWebUI::running() const { return false; }
uint32_t NodeWebUI::clients() const { return 0; }

#endif // ARDUINO
