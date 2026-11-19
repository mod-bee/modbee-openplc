# Node UIO Web UI for OpenPLC

A web page showing the board's digital and analog channels live, and letting
you set the analog calibration. One block starts it.

It needs the `node-uio` library, which is where the board itself lives.

## The one thing that will catch you out

**The page is not part of the firmware.** It is a LittleFS filesystem image,
and OpenPLC does not upload one — the editor builds and uploads a sketch binary
and nothing else. Until the image is written, the board answers on port 80 and
serves a 404 for every page, which looks like a broken server rather than a
missing file.

Write it once, from the `node-webUI` PlatformIO project:

```bash
pio run -t buildfs
pio run -t uploadfs
```

It survives firmware uploads afterwards, so this is a one-off per board — with
one condition.

**The partition scheme has to match.** The filesystem sits at an offset the
partition table decides. PlatformIO built the image for the scheme in
`platformio.ini`; OpenPLC builds the firmware for whatever Build Settings says.
If those differ, the firmware looks for the filesystem where it is not, and you
get the same 404s. Set them the same, and re-upload the image if you change
either.

## Using it

Place one `FB_WebServer` block. It needs a network, which it does not create:

```
PROGRAM main
  VAR
    board : FB_NodeUio;
    net : FB_WiFiNetwork;
    web : FB_WebServer;
  END_VAR

  board();
  net(bEnable := TRUE, sSsid := 'plant', sWiFiPassword := 'secret');
  web(bEnable := net.bNetworkUp);
END_PROGRAM
```

`bListening` goes true once it is listening. Browse to the address
`FB_WiFiNetwork` reports.

| Pin | | |
| --- | --- | --- |
| `bEnable` | in, BOOL | serve the web interface; FALSE clears the outputs |
| `nLocalPort` | in, UINT | the TCP port to listen on, taken on the first enabled call; default 80 |
| `bListening` | out, BOOL | the server is up and listening on `nLocalPort` |
| `nClientsConnected` | out, UDINT | browsers connected to the live feed now |
| `bError` | out, BOOL | `bEnable` is set and the server is not listening yet (no network) |

## What it does not do

**It does not bring a network up.** The radio is shared — the firmware claims
it when Modbus TCP is built in, a protocol library may claim it first, and the
`FB_WiFiNetwork` block holds the credentials. This block binds a port on whatever is
already there, so two things cannot fight over one radio.

That is why the page shows the connection rather than offering to change it.
Wi-Fi is configured in the program, not the browser.

## Calibration from the page

The page writes calibration straight through to the board and saves it, the
same way the `FB_AnalogCalibration` block does. Both end up in the same place, so a value
set in the browser is what the program reads.

## Cost

The server and its dependencies are large: the firmware goes from roughly a
third of the flash to around three quarters. Worth checking you have room
before adding it to a program that is already big.
