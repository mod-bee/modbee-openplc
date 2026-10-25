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

- **the one `GsmDevice`**, its serial link and its power lines;
- **one lock** around every touch of it, because OpenPLC runs tasks in
  parallel - on the Runtime, and on an ESP32 in RTOS mode - and the modem
  library is single-threaded by design. The blocks *try* the lock and skip a
  scan when another task holds it, so no block waits on the modem;
- **the SMS inbox**, which keeps each message's storage index so it can be
  deleted from the SIM once read;
- **`GsmPlcClient`**, a `GsmClient` that takes the lock around each call. It
  is what `MQTT_CLIENT` uses for `TRANSPORT := MQTT_CELLULAR`: `modbee-mqtt`
  includes `<ModBeeGsmPlc.h>` when it is on the include path, which it is
  whenever a modbee-gsm block is in the project.

Every C++ block of a project is compiled in one translation unit, with each
block's pins as `#define`s, so `ModBeeGsmPlc.h` uses no all-capitals name and
nothing beginning with `fb`.
