(* Serves the board's web interface.

bEnable            serve.
nLocalPort         which port. 80 unless you have a reason.

bListening         the server is up and listening.
nClientsConnected  browsers connected to the live feed right now.
bError             bEnable is set and it is not listening.

---

The page shows the digital and analog channels live, and lets you set the analog
calibration. It reads and writes through the same surface the hardware blocks
use, so what the page shows is what the program sees.

It does not bring a network up. Something else owns the radio, the FB_WiFiNetwork
block or Modbus TCP in the firmware, and this binds a port on whatever is there.
bListening stays false until a network exists, then goes true on its own.

The page is not part of the firmware. It lives in a filesystem image that
OpenPLC does not upload, so it has to be written once with PlatformIO's Upload
Filesystem Image from the node-webUI project. Until it is, the board answers but
every page is a 404. The partition scheme in Build Settings has to match the one
that image was built for, or it lands where the firmware will not look for it. *)

FUNCTION_BLOCK FB_WebServer
  VAR_INPUT
    bEnable : BOOL; (* serve the web interface; FALSE clears the outputs *)
    nLocalPort : UINT := 80; (* the TCP port to listen on, taken on the first enabled call; 80 unless you have a reason *)
  END_VAR
  VAR_OUTPUT
    bListening : BOOL; (* the server is up and listening on nLocalPort *)
    nClientsConnected : UDINT; (* browsers connected to the live feed now *)
    bError : BOOL; (* bEnable is set and the server is not listening yet (no network) *)
  END_VAR
  VAR
    nServer : __XWORD; (* the web server, built on the first enabled call and kept *)
  END_VAR
#include <NodeWebUI.h>

void setup()
{
  bListening = false;
  nClientsConnected = 0;
  bError = false;
  nServer = (strucpp::XWORD_t)0;
}

void loop()
{
  if (!(bool)bEnable) {
    bListening = false;
    nClientsConnected = 0;
    bError = false;
    return;
  }

  // Built on the first enabled scan, because the port is a pin and is not
  // known before then. Held across scans, since the server owns its sockets.
  NodeWebUI* server = (NodeWebUI*)(uintptr_t)(strucpp::XWORD_t)nServer;
  if (!server) {
    server = new NodeWebUI((uint16_t)nLocalPort);
    nServer = (strucpp::XWORD_t)(uintptr_t)server;
  }

  server->update();

  bListening = server->running();
  nClientsConnected = server->clients();
  bError = !(bool)bListening;
}

END_FUNCTION_BLOCK