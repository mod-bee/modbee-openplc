(* Puts TCP clients in front of a serial segment, routed by unit id.

      SCADA -+
        HMI -+- TCP --> [ bridge ] --RS-485--> unit 1  unit 2  unit 17 ...
     laptop -+

Several clients on the network share one serial bus, which carries one
conversation at a time: the bridge turns the second into the first. Without
it, two SCADA packages polling one RS-485 segment talk over each other.

stSerialConfig  ST_ModbusSerialConfig, the segment behind. sDevice on the
           Runtime ('/dev/ttyUSB0'); nUart, nRxPin, nTxPin, nDriverEnablePin and tDriverEnableHold
           on a board; nBaudRate (0 = 19200) and eParity (Even, the Modbus
           default) on both. nServerUnitId is a node's and must stay 0 here: the
           bridge routes nFirstUnitId..nLastUnitId.
nLocalPort   the TCP port clients connect to. 0 for 502.
nFirstUnitId the lowest unit id out on the segment, 1..247.
nLastUnitId  the highest. Equal to nFirstUnitId routes one device.
nMaxClients  clients held at once. 0 = 8 on the Runtime, 2 on a board. A
           board that cannot hold that many says so on sLastError.
nMaxPendingOperations  transactions outstanding on the serial side at once. 0 = 8.
bForwardUnroutedUnits  forward a unit id not routed instead of answering "no such
           path". Off by default: with it on, a mistyped unit id becomes a
           timeout several hundred milliseconds long that blocks the whole
           segment. For a bus whose devices you do not know.
bConnect     TRUE (default) runs the bridge.

bLinkOpen    both ends are open.
nClientsConnected  clients connected.
nForwardedRequestCount  requests sent to the segment.
nGatewayPathUnavailableCount  requests refused with exception 0x0A: no route, or no room for
           another transaction. OUR problem - a range typed wrong, or
           nMaxPendingOperations too small.
nGatewayTargetFailedCount  requests answered with exception 0x0B: the route exists and the
           device did not answer. ITS problem - off, unplugged, another
           address. Two numbers worth two alarms: a plain timeout cannot say
           which end of the plant to walk to.
sFramingReason  how the segment finds frames, and why.
bError       it did not open, or has since failed.
eErrorId     why. E_ModbusResult.Ok when fine.
sLastError   in words: the operating system's own.

  segment : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);

  bridge(stSerialConfig := segment, nLocalPort := 502, nFirstUnitId := 1, nLastUnitId := 32);

IT STANDS ALONE: no FB_ModbusNode, because a bridge is both ends of a wire.
Put it in the network task; it services both ends once per call. It does not
decode what it carries: a function code this library has never heard of
passes through byte for byte. On a board the TCP front is Wi-Fi, already
joined (by an FB_ModbusNode on ArduinoWiFi, or the board's own network
block). *)

FUNCTION_BLOCK FB_ModbusBridge
  VAR_INPUT
    stSerialConfig : ST_ModbusSerialConfig;      (* the segment behind: device or UART, baud, parity *)
    nLocalPort : UINT; (* the TCP port clients connect to; 0 = 502 *)
    nFirstUnitId : BYTE; (* the lowest unit id on the segment, 1..247 *)
    nLastUnitId : BYTE; (* the highest *)
    nMaxClients : BYTE; (* clients held at once; 0 = 8 on the Runtime, 2 on a board *)
    nMaxPendingOperations : BYTE; (* transactions outstanding on the segment; 0 = 8 *)
    bForwardUnroutedUnits : BOOL; (* forward a unit id not routed instead of refusing it *)
    bConnect : BOOL := TRUE; (* TRUE runs the bridge *)
  END_VAR
  VAR_OUTPUT
    bLinkOpen : BOOL; (* both ends are open *)
    nClientsConnected : INT; (* clients connected *)
    nForwardedRequestCount : DINT; (* requests sent to the segment *)
    nGatewayPathUnavailableCount : DINT; (* refused: no route (exception 0x0A) *)
    nGatewayTargetFailedCount : DINT; (* the device did not answer (exception 0x0B) *)
    sFramingReason : STRING(160); (* how the segment finds frames, and why *)
    bError : BOOL; (* it did not open, or has since failed *)
    eErrorId : E_ModbusResult; (* why; Ok when fine *)
    sLastError : STRING(64); (* why, in words *)
  END_VAR
  VAR
    nApi           : __XWORD;
    bTried         : BOOL;
    nRetryAt       : DINT;
  END_VAR
#include <ModBeeModbus.h>

#include <new>
#include <vector>

#if defined(MODBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// The TCP front on a board is Wi-Fi: the Arduino network classes share no
// base, so the library binds to a concrete one by template. Detected as the
// node does, so a board without it still builds and says so (MBX-003).
#if !defined(MODBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define MBB_BRIDGE_WIFI 1
#include <WiFi.h>
#endif
#endif

// Defined in FB_ModbusNode.cpp. Every C++ POU lands in one translation unit in
// filename order, and this one sorts first.
uint32_t mbb_serialConfig(uint8_t parity);
HardwareSerial* mbb_serialPort(uint8_t port);
#if defined(ARDUINO_ARCH_ESP32)
int mbb_serialBegin(HardwareSerial* port, uint32_t baud, uint32_t cfg,
                    int rxPin, int txPin, int dePin);
#endif

#if defined(MBB_BRIDGE_WIFI)
static WiFiServer* mbbBridgeServer = nullptr;
#endif
static ModbusListener* mbbBridgeListener = nullptr;
#endif

int32_t mbb_microsOf(const strucpp::IEC_LTIME& t);

#define MBB_BRIDGE_REOPEN_MS 2000

namespace {
// Every bridge this program made, closed when it is unloaded: the Runtime swaps
// a program into the same process, and a listening socket outlives it unless
// somebody closes it. Made on first use, so a program without a bridge links
// none of the gateway.
struct MbbBridgesOwned {
    std::vector<ModbusBridge*> all;
    ~MbbBridgesOwned() {
        for (size_t i = 0; i < all.size(); i++) { all[i]->end(); delete all[i]; }
    }
};
MbbBridgesOwned& mbbBridgesOwned() {
    static MbbBridgesOwned owned;
    return owned;
}
}  // namespace

void setup()
{
    bLinkOpen = false;
    nClientsConnected = 0;
    nForwardedRequestCount = 0;
    nGatewayPathUnavailableCount = 0;
    nGatewayTargetFailedCount = 0;
    sFramingReason = "";
    bError = false;
    eErrorId = strucpp::E_MODBUSRESULT::OK;
    sLastError = "";
    nApi = (strucpp::XWORD_t)0;
    bTried = false;
    nRetryAt = 0;
}

void loop()
{
    ModbusBridge* bridge = (ModbusBridge*)(uintptr_t)(strucpp::XWORD_t)nApi;

    if (!(bool)bConnect) {
        if (bridge && (bool)bLinkOpen) bridge->end();
        bLinkOpen = false;
        nClientsConnected = 0;
        bTried = false;
        return;
    }

    auto fail = [&](strucpp::E_MODBUSRESULT why, const char* text) {
        bError = true;
        eErrorId = why;
        sLastError = text;
    };

    if (!(bool)bLinkOpen) {
        const mb_time_t now = mb_millis();
        if ((bool)bTried &&
            (int32_t)(now - (mb_time_t)(uint32_t)(int32_t)nRetryAt) < 0) {
            return;
        }
        bTried = true;
        nRetryAt = (int32_t)(uint32_t)(now + MBB_BRIDGE_REOPEN_MS);

        if ((uint8_t)nFirstUnitId < 1 || (uint8_t)nLastUnitId < (uint8_t)nFirstUnitId ||
            (uint8_t)nLastUnitId > 247) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "nFirstUnitId..nLastUnitId name the devices out there, 1..247");
            return;
        }
        if ((uint8_t)stSerialConfig.NSERVERUNITID != 0) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "stSerialConfig.nServerUnitId is a node's; a bridge routes nFirstUnitId..nLastUnitId");
            return;
        }

        if (!bridge) {
            bridge = new (std::nothrow) ModbusBridge();
            if (!bridge) {
                fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, "out of memory");
                return;
            }
            nApi = (strucpp::XWORD_t)(uintptr_t)bridge;
            mbbBridgesOwned().all.push_back(bridge);
        }

        const uint32_t baud = ((int32_t)stSerialConfig.NBAUDRATE > 0)
            ? (uint32_t)(int32_t)stSerialConfig.NBAUDRATE : 19200u;
        const uint16_t tcpPort = ((uint16_t)nLocalPort != 0) ? (uint16_t)nLocalPort : MODBUS_TCP_PORT;

        if ((uint8_t)nMaxClients > 0) bridge->maxClients((size_t)(uint8_t)nMaxClients);
        if ((uint8_t)nMaxPendingOperations > 0) bridge->maxOutstanding((size_t)(uint8_t)nMaxPendingOperations);
        bridge->route((uint8_t)nFirstUnitId, (uint8_t)nLastUnitId);
        bridge->routeEverythingElse((bool)bForwardUnroutedUnits);

#if defined(MODBUS_PLATFORM_HOST)
        if (stSerialConfig.SDEVICE.length() == 0) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "no stSerialConfig.sDevice named");
            return;
        }
        // A member of this instance, so its text outlives the scan.
        bridge->serial(stSerialConfig.SDEVICE.c_str(), baud,
                       (ModbusParity)(int)(strucpp::E_MODBUSPARITY)stSerialConfig.EPARITY);
        bridge->listen(tcpPort);
#endif

#if defined(MODBUS_PLATFORM_ARDUINO)
        HardwareSerial* port = mbb_serialPort((uint8_t)stSerialConfig.NUART);
        if (port == nullptr) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "stSerialConfig.nUart is not a hardware serial on this board");
            return;
        }
        const uint32_t cfg = mbb_serialConfig((uint8_t)(int)(strucpp::E_MODBUSPARITY)stSerialConfig.EPARITY);
#if defined(ARDUINO_ARCH_ESP32)
        // The UART drives DE here: see mbb_serialBegin() in FB_ModbusNode.
        const int de = mbb_serialBegin(port, baud, cfg, (int)(int16_t)stSerialConfig.NRXPIN,
                                       (int)(int16_t)stSerialConfig.NTXPIN,
                                       (int)(int16_t)stSerialConfig.NDRIVERENABLEPIN);
#else
        port->begin(baud, cfg);
        const int de = (int)(int16_t)stSerialConfig.NDRIVERENABLEPIN;
#endif
        bridge->serial(port, baud);
        if (de >= 0) {
            const int32_t holdUs = mbb_microsOf(stSerialConfig.TDRIVERENABLEHOLD);
            bridge->directionPin(de, true, holdUs > 0 ? (uint32_t)holdUs : 2000u);
        }
#if defined(MBB_BRIDGE_WIFI)
        bool roomForClients = true;
        if (!mbbBridgeListener) {
            // 0 is the listener's own default (two); any other figure is held
            // in full or refused out loud, never quietly fewer.
            const size_t limit = (uint8_t)nMaxClients;
            mbbBridgeServer = new (std::nothrow) WiFiServer(tcpPort);
            if (mbbBridgeServer) {
                ModbusArduinoServer<WiFiServer, WiFiClient>* server =
                    new (std::nothrow) ModbusArduinoServer<WiFiServer, WiFiClient>(*mbbBridgeServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbbBridgeListener = server;
            }
        }
        if (!mbbBridgeListener) {
            fail(strucpp::E_MODBUSRESULT::NOTINITIALISED,
                 roomForClients ? "out of memory" : "out of memory for nMaxClients connections");
            return;
        }
        bridge->listen(*mbbBridgeListener);
#else
        fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "this board has no WiFi; a bridge needs a TCP front");
        return;
#endif
#endif

        if (!bridge->begin()) {
            fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, "the serial device or the TCP port would not open");
            return;
        }
        bLinkOpen = true;
        bError = false;
        eErrorId = strucpp::E_MODBUSRESULT::OK;
        sLastError = "";
        sFramingReason = bridge->framingReason();
    }

    if (!bridge) return;

    // Both ends, once per call.
    bridge->poll();

    nClientsConnected = (int16_t)bridge->clients();
    nForwardedRequestCount = (int32_t)bridge->forwarded();
    nGatewayPathUnavailableCount = (int32_t)bridge->noPath();
    nGatewayTargetFailedCount = (int32_t)bridge->deviceAbsent();
}

END_FUNCTION_BLOCK