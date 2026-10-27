# ModBee boards package (`com.modbee.node`)

The OpenPLC Editor board package for the ModBee Node UIO. Install the `.vpp`
from `dist/` in the editor's packages screen (Add from file…), then pick
**ModBee Node UIO** as the target.

| | |
| --- | --- |
| Chip | ESP32-S3FH4R2: 4 MB flash, 2 MB quad PSRAM |
| Arduino board | `esp32:esp32:esp32s3:CDCOnBoot=cdc,USBMode=hwcdc,PSRAM=enabled,PartitionScheme=min_spiffs` |
| Partitions | `package/partitions/modbee-node.csv`: two 1.875 MB program slots (the running program and the OTA update), 128 KB NVS for retained values and settings, 64 KB crash log, no file system |
| Default I/O pins | None. The Node's I/O is read and written by the `node-uio` library blocks, so the board claims no GPIO (GPIO 9, 39 and 40 are the HAT power, LED and button). |
| Serial screen | Baud rate only. The Node's RS485 transceivers have DE and RE tied high, so there is no driver-enable pin to set. |
| Specs and preview | The Node's own I/O and ratings, from `docs/HARDWARE.md` in [modbee-node-uio](https://github.com/mod-bee/modbee-node-uio). The preview is that repo's `node-uio-br-assem-1` render, cropped and saved as PNG (the editor shows previews as PNG). |
| Compiler flags | `-DESP32_ARDUINO_NO_RGB_BUILTIN`, see below |

## The boot record (otadata) is at 0xe000

The ESP32 core's upload writes three things at fixed addresses: the partition
table at 0x8000, `boot_app0.bin` - an empty boot record - at 0xe000, and the
program at 0x10000, which is `app0`. The boot record says which program slot
to start, so it has to be where the core writes the empty one: then every USB
upload also resets it, and the board starts the program just uploaded.

Package 1.0.0 had it at 0x9000. After an OTA update had switched the board to
`app1`, a USB upload went to `app0` while the record still said `app1`, and the
board went on running the old program. From 1.1.0 the record is at 0xe000
(0x9000-0xdfff is unused) and that cannot happen; an OTA update still writes
the record wherever the partition table says, so OTA is unaffected. The NVS
partition did not move, so retained values and settings survive the change. A
Node still on the 1.0.0 layout changes over at its first USB upload with 1.1.0.

## No DevKit RGB LED

The board package builds on the core's generic `esp32s3` board, whose pin
file is Espressif's DevKitC: it declares an RGB LED on GPIO 48
(`RGB_BUILTIN`), and with that declared the core's `digitalWrite()` carries a
branch to the RMT LED driver, about 20 kB of flash, whether or not anything
lights an LED. `-DESP32_ARDUINO_NO_RGB_BUILTIN` (in the C flags, which the core
is compiled with) is the core's own switch that removes that branch. The
Node's LED - a WS2812B on GPIO 39 - is driven by the `node-uio` library, which
sends the frame itself and needs no RMT.

A pin file of the Node's own (a `variants/` folder, `build.variant`) would be
the cleaner answer, but a board package cannot carry one: the manifest can
name a core, FQBN options, a partition table and compiler flags, not a variant
folder. So the DevKit's other pin names (`LED_BUILTIN`, `RGB_BUILTIN`, `SDA` 8,
`SCL` 9, `SS` 10 and so on) are still defined in C++ and are not the Node's -
the Node's own pins are in the `node-uio` blocks.

## PSRAM

With PSRAM enabled, any heap allocation of 16 bytes or more (`malloc`, `new`,
`std::string`, buffers inside libraries) may go to PSRAM; smaller ones stay in
internal RAM. The core's own rule is 4 KB; the HAL lowers it at boot
(`MODBEE_PSRAM_FROM`: 256 B from 1.2.0, 16 B from 1.2.1) because a program's
comms blocks make many small allocations, and at 4 KB they filled the internal
RAM until the Wi-Fi driver could not start; at 256 B an MQTT client's start
still took ~20 KB of internal RAM and the Wi-Fi stack ran dry. An allocation that must be internal
(task stacks, DMA buffers, the Wi-Fi driver's own) asks for `MALLOC_CAP_INTERNAL`. Fixed-size globals stay in
internal RAM. A library can put a buffer in PSRAM explicitly with `ps_malloc()`
or `heap_caps_malloc(size, MALLOC_CAP_SPIRAM)`.

## PLC program data in PSRAM (1.2.4)

`target.plcDataMemory: "external"` makes the editor build the PLC program's data - every configuration
VAR_GLOBAL and every program and block instance, forcing copies included - as one block (STruC++'s PLC data
block) that the runtime takes at the start of `setup()`, from PSRAM, or from internal RAM if the board has no
PSRAM. On a two-pump controller program that is about 171 KB out of internal RAM. Debugger, forcing, retained values,
Modbus, BeeBus and MQTT work as before. `openplc-cli debug status` shows where the block is (`plc data`).
It needs an editor that knows the field (ModBee builds from 2026-10-16); an older editor ignores it and keeps
the data in internal RAM as before.

## IEC task stacks: 16 KB

In RTOS mode every IEC task gets its own stack in internal RAM (`OPENPLC_RTOS_WORK_STACK`, C and C++ flags).
Measured on the Node (2026-10-15, a two-pump controller program): one task running the logic, the panel link and
MQTT / Sparkplug had 48 bytes left of a 6 KB stack - it overflowed and stalled the PLC. A 6 KB stack only fits
a task without the comms (logic alone used ~2 KB). 16 KB, the runtime's own default, is set explicitly.
Check `debug stats` (stackFreeBytes) after any change.

## IEC tasks: keep them on core 1

Put every IEC task on core 1 (the task table's Core setting); core 0 carries the Wi-Fi driver. Measured on the Node
(2026-10-16, two-pump controller program, LOGIC 50 ms + COMMS 50 ms): with COMMS on core 0 the LOGIC task scanned 44 % slower
(17.6 -> 25.4 ms average; 20.0 -> 32.8 ms with the PLC data in PSRAM), COMMS only 3.6-6 ms faster. The cause is the
chip, not locking (lock waits < 0.1 ms a scan): both cores share the ESP32-S3's 16 KB instruction cache and the
flash / PSRAM bus, so a second task running at the same time evicts the first one's code. On one core the
lower-priority task runs in the gaps and the logic keeps its code cached.

## Building the package

```bash
node build-vpp.mjs        # writes dist/com.modbee.node-<version>.vpp
```

`package/` is the package content. The partition table needs an editor that
supports `target.partitions` (ModBee builds); `PartitionScheme=min_spiffs` keeps
arduino-cli's size check at the same 1,966,080 bytes. Raise `package.version` in
`package/manifest.json` for every release.

The package is signed with the ModBee key `modbee-2026`. The private key is at
`~/.config/modbee/vpp-signing/modbee-2026.pem` (or `$MODBEE_VPP_KEY`) and is never
committed: back it up somewhere safe, because packages signed with a new key
need a new editor build. The editor only installs the package when it trusts
the public key, `modbee-2026.pub.pem`, which is listed in the editor's
`src/backend/shared/utils/vpp/trusted-keys.ts` (ModBee editor builds only).

## Broker certificates (1.2.2)

The MQTT library checks a broker's certificate (`MQTT_TLS_VERIFY`) against `MQTT_CA_CERT_PEM`, a compiler
define this package sets: Let's Encrypt's two roots, ISRG Root X1 (RSA) and ISRG Root X2 (ECDSA), as Mozilla's
trust store has them. A broker on any Let's Encrypt certificate is trusted, and its renewals just work. To trust
another authority, add its root to that define in `manifest.json` (`cxx_flags`).

From 1.2.3 the define holds the ModBee root CA (2026, ECDSA P-384, for ModBee's own brokers) and ISRG Root X2;
ISRG Root X1 (RSA) was taken out. A broker on a Let's Encrypt ECDSA certificate is still trusted.
