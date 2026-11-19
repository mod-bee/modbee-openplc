(* Joins a WiFi network, and holds the credentials for the board.

bEnable    ask for the network. Clear it to power the radio down.
sSsid      the network to join.
sWiFiPassword  its key. Leave empty for an open network.

bNetworkUp  a network is up, whoever brought it up.
nIpAddress  the address as a 32-bit word. 0 while down.
nSignalStrengthDbm  signal strength in dBm. 0 while down.
bError      bEnable is set and there is still no network.
eErrorId    why.
             UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT, UIO_IO_ERROR,
             UIO_NO_DATA, UIO_TOO_LARGE, UIO_UNSUPPORTED
nNetworkDropCount  how often the radio dropped off its network since power-up.
sLastDropReason    why it dropped the last time, in words (the ESP32's reason):
             e.g. lost the router's beacons, router sent it away, wrong password?

---

The radio is shared. The OpenPLC firmware claims it when Modbus TCP is built in,
and a protocol library may claim it before this block runs. Whoever gets there
first wins: if a network is already up this block reports it and changes
nothing, so two owners cannot fight over one radio.

That also means the credentials here are only used on a radio that is down, or
on one this block brought up itself. On a board where Modbus TCP brings the
network up, they are never applied and bNetworkUp still goes true. By the same
rule, clearing bEnable will not switch off a radio this block did not start.

sSsid AND sWiFiPassword MAY CHANGE WHILE bNetworkUp. On a radio this block brought
up, a new sSsid or password leaves the network and joins again with the new
ones - a network changed on a settings page needs no restart. bNetworkUp drops
while it joins, and anything riding on the network (MQTT, Sparkplug) comes
back by itself.

Clearing bEnable powers the radio down rather than merely disconnecting, which is
the saving worth having on a battery. FB_WiFiSleep drives this pin to duty-cycle
it.

Connecting takes a few seconds and does not block the scan. *)

FUNCTION_BLOCK FB_WiFiNetwork
  VAR_INPUT
    bEnable : BOOL; (* ask for the network; FALSE powers the radio down (if this block started it) *)
    sSsid : STRING(32); (* the Wi-Fi network to join *)
    sWiFiPassword : STRING(64); (* its key; empty for an open network *)
  END_VAR
  VAR_OUTPUT
    bNetworkUp : BOOL; (* a Wi-Fi network is up, whoever brought it up *)
    nIpAddress : DWORD; (* the address as a 32-bit word; 0 while down *)
    nSignalStrengthDbm : INT; (* Wi-Fi signal strength, dBm; 0 while down *)
    bError : BOOL; (* bEnable is set and there is still no network *)
    eErrorId : E_UioResult; (* why; UIO_OK when fine *)
    nNetworkDropCount : UDINT; (* times the radio dropped off its network since power-up *)
    sLastDropReason : STRING(48); (* why it dropped the last time, in words (the ESP32's reason) *)
  END_VAR
#include <NodeUioAPI.h>

E_UIORESULT uio_status(UioResult result);

void setup()
{
  bNetworkUp = false;
  nIpAddress = 0;
  nSignalStrengthDbm = 0;
  bError = false;
  eErrorId = E_UIORESULT::UIO_OK;
}

void loop()
{
  UioResult result = UIO_OK;

  if ((bool)bEnable) {
    result = uio().connect(sSsid.c_str(), sWiFiPassword.c_str());
  } else {
    result = uio().disconnect();
  }

  bNetworkUp = uio().connected();
  nIpAddress = (uint32_t)uio().address();
  nSignalStrengthDbm = (int16_t)uio().signalStrength();

  if ((bool)bNetworkUp) result = UIO_OK;

  bError = (bool)bEnable && !(bool)bNetworkUp;
  eErrorId = uio_status(result);
  nNetworkDropCount = uio().radioDrops();
  sLastDropReason = NodeUioAPI::radioDropText(uio().radioDropReason());
}

END_FUNCTION_BLOCK