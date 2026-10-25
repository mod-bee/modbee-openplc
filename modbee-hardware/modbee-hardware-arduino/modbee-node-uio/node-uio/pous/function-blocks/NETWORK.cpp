(* Joins a WiFi network, and holds the credentials for the board.

ENABLE     ask for the network. Clear it to power the radio down.
SSID       the network to join.
PASSWORD   its key. Leave empty for an open network.

CONNECTED  a network is up, whoever brought it up.
IP         the address as a 32-bit word. 0 while down.
RSSI       signal strength in dBm. 0 while down.
ERROR      ENABLE is set and there is still no network.
STATUS     why.
DROPS      how often the radio dropped off its network since power-up.
LAST_ERROR why it dropped the last time, in words (the ESP32's reason):
             e.g. lost the router's beacons, router sent it away, wrong password?
             UIO_OK, UIO_NOT_READY, UIO_INVALID_ARGUMENT, UIO_IO_ERROR,
             UIO_NO_DATA, UIO_TOO_LARGE, UIO_UNSUPPORTED

---

The radio is shared. The OpenPLC firmware claims it when Modbus TCP is built in,
and a protocol library may claim it before this block runs. Whoever gets there
first wins: if a network is already up this block reports it and changes
nothing, so two owners cannot fight over one radio.

That also means the credentials here are only used on a radio that is down, or
on one this block brought up itself. On a board where Modbus TCP brings the
network up, they are never applied and CONNECTED still goes true. By the same
rule, clearing ENABLE will not switch off a radio this block did not start.

SSID AND PASSWORD MAY CHANGE WHILE CONNECTED. On a radio this block brought
up, a new SSID or password leaves the network and joins again with the new
ones - a network changed on a settings page needs no restart. CONNECTED drops
while it joins, and anything riding on the network (MQTT, Sparkplug) comes
back by itself.

Clearing ENABLE powers the radio down rather than merely disconnecting, which is
the saving worth having on a battery. WIFI_SLEEP drives this pin to duty-cycle
it.

Connecting takes a few seconds and does not block the scan. *)

FUNCTION_BLOCK NETWORK
  VAR_INPUT
    ENABLE : BOOL;
    SSID : STRING(32);
    PASSWORD : STRING(64);
  END_VAR
  VAR_OUTPUT
    CONNECTED : BOOL;
    IP : DWORD;
    RSSI : INT;
    ERROR : BOOL;
    STATUS : UIO_RESULT;
    DROPS : UDINT;
    LAST_ERROR : STRING(48);
  END_VAR
#include <NodeUioAPI.h>

UIO_RESULT uio_status(UioResult result);

void setup()
{
  CONNECTED = false;
  IP = 0;
  RSSI = 0;
  ERROR = false;
  STATUS = UIO_RESULT::UIO_OK;
}

void loop()
{
  UioResult result = UIO_OK;

  if ((bool)ENABLE) {
    result = uio().connect(SSID.c_str(), PASSWORD.c_str());
  } else {
    result = uio().disconnect();
  }

  CONNECTED = uio().connected();
  IP = (uint32_t)uio().address();
  RSSI = (int16_t)uio().signalStrength();

  if ((bool)CONNECTED) result = UIO_OK;

  ERROR = (bool)ENABLE && !(bool)CONNECTED;
  STATUS = uio_status(result);
  DROPS = uio().radioDrops();
  LAST_ERROR = NodeUioAPI::radioDropText(uio().radioDropReason());
}

END_FUNCTION_BLOCK