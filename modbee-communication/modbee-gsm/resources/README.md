# Resources

The C/C++ libraries the blocks compile against, one folder each:

```
resources/
  modbee-gsm/          the ModBee GSM library, vendored as it is
    library.properties
    src/
  modbee-gsm-plc/      this library's OpenPLC layer
    library.properties
    src/ModBeeGsmPlc.h
    src/ModBeeGsmPlc.cpp
    src/GsmPlcMethods.h     the modem blocks' methods
    src/GsmPlcMethods.cpp
```

That is the ordinary Arduino library layout. Everything here is packaged into
the `.stlib` when you build, so a project that installs this library gets these
sources unpacked into its own build and compiled for its own target. There is
nothing for the user to install separately, and the sources cannot fall out of
step with the blocks built against them.

## `modbee-gsm/` is the modem library, unchanged

A copy of the ModBee GSM C++ library: `library.properties` and `src/`. It has
no global, no serial port and no pin of its own, by design - which is why the
folder below exists.

## `modbee-gsm-plc/` is the one modem a PLC has

WiFi and Ethernet are globals their Arduino libraries provide. This is the same
thing for cellular, kept out of the modem library so that library never learns
that a PLC exists:

- **the one device**, made by the modem block that runs it with
  `GsmDeviceWith<>` holding only that module's driver (`FB_GsmModemA7670`:
  A76XX, `FB_GsmModemSim7070`: SIM707x), its serial link and its power lines;
- **one lock** around every touch of it, because OpenPLC runs tasks in
  parallel - on the Runtime, and on an ESP32 in RTOS mode - and the modem
  library is single-threaded by design. The block and its methods *try* the
  lock and skip a scan when another task holds it, so nothing waits on the
  modem;
- **the SMS inbox**, which keeps each message's storage index so it can be
  deleted from the SIM once read;
- **`GsmPlcClient`**, an Arduino `Client` over the modem's sockets that takes
  the lock around each call. It is what `FB_MqttClient` uses for
  `eTransport := E_MqttTransport.Cellular`: `modbee-mqtt` includes
  `<ModBeeGsmPlc.h>` when it is on the include path, which it is whenever
  modbee-gsm is in the project. It makes its `GsmClient` at its first
  connect, so it may be made before the modem block has made the device;
- **the methods** (`GsmPlcMethods`): what `SendSms`, `Inbox`, `SmsCommand`,
  `AtCommand`, `Power`, `Socket`, `Status`, `NetworkTime` and `Gnss` do, in
  plain C++ shared by both modem blocks. A method a program does not call is
  not linked.

Every C++ block of a project is compiled in one translation unit, with each
block's pins as `#define`s (`bError`, `sHost`), so these headers use no
all-capitals name and no name of a block's pin; `internal/tools/check-names.py`
checks it against every modbee-gsm and modbee-mqtt block.
