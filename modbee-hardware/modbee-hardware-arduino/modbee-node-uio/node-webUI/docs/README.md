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

Place one `WEB_SERVER` block. It needs a network, which it does not create:

```
PROGRAM main
  VAR
    board : UIO;
    net : NETWORK;
    web : WEB_SERVER;
  END_VAR

  board();
  net(ENABLE := TRUE, SSID := 'plant', PASSWORD := 'secret');
  web(ENABLE := net.CONNECTED);
END_PROGRAM
```

`RUNNING` goes true once it is listening. Browse to the address `NETWORK`
reports.

| Pin | | |
| --- | --- | --- |
| `ENABLE` | in, BOOL | serve |
| `PORT` | in, UINT | which port, default 80 |
| `RUNNING` | out, BOOL | up and listening |
| `CLIENTS` | out, UDINT | browsers on the live feed |
| `ERROR` | out, BOOL | enabled and not running |

## What it does not do

**It does not bring a network up.** The radio is shared — the firmware claims
it when Modbus TCP is built in, a protocol library may claim it first, and the
`NETWORK` block holds the credentials. This block binds a port on whatever is
already there, so two things cannot fight over one radio.

That is why the page shows the connection rather than offering to change it.
Wi-Fi is configured in the program, not the browser.

## Calibration from the page

The page writes calibration straight through to the board and saves it, the
same way the `ANALOG_CAL` block does. Both end up in the same place, so a value
set in the browser is what the program reads.

## Cost

The server and its dependencies are large: the firmware goes from roughly a
third of the flash to around three quarters. Worth checking you have room
before adding it to a program that is already big.
