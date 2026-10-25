(*
Serves the board's web interface.

ENABLE   serve.
PORT     which port. 80 unless you have a reason.

RUNNING  the server is up and listening.
CLIENTS  browsers connected to the live feed right now.
ERROR    ENABLE is set and it is not running.

---

The page shows the digital and analog channels live, and lets you set the analog
calibration. It reads and writes through the same surface the hardware blocks
use, so what the page shows is what the program sees.

It does not bring a network up. Something else owns the radio, the NETWORK block
or Modbus TCP in the firmware, and this binds a port on whatever is there.
RUNNING stays false until a network exists, then goes true on its own.

The page is not part of the firmware. It lives in a filesystem image that
OpenPLC does not upload, so it has to be written once with PlatformIO's Upload
Filesystem Image from the node-webUI project. Until it is, the board answers but
every page is a 404. The partition scheme in Build Settings has to match the one
that image was built for, or it lands where the firmware will not look for it.
*)

FUNCTION_BLOCK WEB_SERVER
  VAR_INPUT
    ENABLE : BOOL;
    PORT : UINT := 80;
  END_VAR
  VAR_OUTPUT
    RUNNING : BOOL;
    CLIENTS : UDINT;
    ERROR : BOOL;
  END_VAR
  VAR
    storage : __XWORD;
  END_VAR

#include <NodeWebUI.h>

void setup()
{
  RUNNING = false;
  CLIENTS = 0;
  ERROR = false;
  storage = (strucpp::XWORD_t)0;
}

void loop()
{
  if (!(bool)ENABLE) {
    RUNNING = false;
    CLIENTS = 0;
    ERROR = false;
    return;
  }

  // Built on the first enabled scan, because the port is a pin and is not
  // known before then. Held across scans, since the server owns its sockets.
  NodeWebUI* server = (NodeWebUI*)(uintptr_t)(strucpp::XWORD_t)storage;
  if (!server) {
    server = new NodeWebUI((uint16_t)PORT);
    storage = (strucpp::XWORD_t)(uintptr_t)server;
  }

  server->update();

  RUNNING = server->running();
  CLIENTS = server->clients();
  ERROR = !(bool)RUNNING;
}

END_FUNCTION_BLOCK
