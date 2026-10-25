# Resources

The C/C++ libraries the blocks compile against, one folder each:

```
resources/
  modbee-mqtt/
    library.properties
    src/
  wolfssl/
    library.properties
    user_settings.h        <- ours; everything else is upstream's
    src/
```

That is the ordinary Arduino library layout. Everything here is packaged into
the `.stlib` when you build, so a project that installs this library gets these
sources unpacked into its own build and compiled for its own target. There is
nothing for the user to install separately, and the sources cannot fall out of
step with the blocks built against them.

## `wolfssl/` is the TLS engine, and it is vendored for the same reason

`MQTT_CLIENT` and `MQTT_BROKER` speak TLS through wolfSSL, and `MQTT_BROKER`
generates a certificate of its own so it can serve TLS with nothing issued to
it. Carrying the engine here means a project needs nothing installed and the
blocks can never be built against a different wolfSSL.

It is refreshed from the pinned tag and checked for drift by the maintainers'
own tooling.

The tree is produced by wolfSSL's OWN Arduino packaging
(`IDE/ARDUINO/wolfssl-arduino.sh`), not by a selection somebody made, so a
version bump is a re-run rather than a merge. **`user_settings.h` is the one
file that is a decision**, and it is commented at length - in particular
`WOLFSSL_ERROR_CODE_OPENSSL`, without which wolfSSL's compatibility functions
keep return conventions that are INVERTED from OpenSSL's for at least one call
this library depends on.

### Why five files are left out

`sp_arm64.c`, `sp_armthumb.c`, `sp_x86_64.c`, `sp_arm32.c` and
`sp_cortexm.c` - 23.4 MB of the package's 48.4 MB. They are assembly-
accelerated big-integer routines for particular CPUs, each wrapped in
`#if defined(WOLFSSL_HAVE_SP_RSA) || ... || defined(WOLFSSL_HAVE_SP_ECC)`, and
wolfSSL's own Arduino `user_settings.h` leaves `SP_MATH` commented out - so
upstream already ships them compiling to nothing in this configuration. The
portable implementations stay, so nothing loses a capability; EC key generation
on an ARM board takes a few seconds rather than about one, once, at first start.

**It is not a preference.** The runtime refuses an uploaded program over 10 MB
in any one file or 50 MB uncompressed in total
(`webserver/plcapp_management.py`), and it refuses the WHOLE upload as unsafe
rather than skipping a file. A real pump-station bundle is 1.4 MB today. With
the full package it is 49.8 MB against that 50 MB cap; without those five files
it is 26.4 MB.

## Do not edit anything under `modbee-mqtt/` by hand

It is a copy of the `modbee-mqtt` C++ repository's `src/` folder and must not be
edited by hand; changes are made in that repository and copied across. The copy
is checked for drift before every release. That check exists because the sibling library went seven files and
one version number out of step without anything noticing.
