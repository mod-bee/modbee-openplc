# 08 - I2C expansion

More digital inputs and outputs, analog channels and temperature, on small I2C
modules beside the Node: the same bus as the board's own ADC (16#49) and DAC
(16#5F), brought out on the Grove connectors and the HAT header.

**No chip drivers are built in yet.** Everything here works today - the module
table, detection, the images, the not-present handling - and a fitted module is
found by its address answering. Until this firmware has a driver for its kind
it reads `UIO_XS_NO_DRIVER` and is **not ok**, so nothing trusts its channels.
The drivers come one family at a time, each with a bench test (below).

## Pins first

### `UIO_EXPANSION`

| Pin | | |
| --- | --- | --- |
| `MODULES` | in-out, ARRAY OF UIO_XMOD | the module table, up to 8 rows |
| `XD` | in-out, ARRAY OF BOOL | the digital image |
| `XA` | in-out, ARRAY OF REAL | the analog image |
| `ALL_OK` | out, BOOL | every fitted module is present and working |
| `FITTED_COUNT`, `MISSING_COUNT` | out, USINT | rows fitted; of those, not ok |
| `FIRST_BAD` | out, INT | the first row that is not ok, 0 when none |
| `ERROR` | out, BOOL | a fitted module is not ok |
| `STATUS` | out, UIO_RESULT | `UIO_UNSUPPORTED` on the Runtime |
| `STATUS_TEXT` | out, STRING(30) | the first problem in words |

### A row: `UIO_XMOD`

| Member | | |
| --- | --- | --- |
| `kind` | setting, UIO_XKIND | what the module is; `UIO_XK_NONE` = an empty row |
| `address` | setting, BYTE | its I2C address, 16#08..16#77 |
| `fitted` | setting, BOOL | installed on this site (default TRUE) |
| `first` | setting, INT | the image row of its channel 1: in `XD` for a digital kind, `XA` for an analog one |
| `count` | status, USINT | its channels |
| `present` | status, BOOL | answers at its address |
| `ok` | status, BOOL | present and read/written: its channels can be trusted |
| `state` | status, UIO_XSTATE | `UIO_XS_OK`, or why not |
| `errors` | status, UINT | failed transactions since start |

### The kinds

| Kind | Channels | Image |
| --- | --- | --- |
| `UIO_XK_MCP23017_DI` / `_DO` | 16 | `XD` |
| `UIO_XK_PCF8574_DI` / `_DO` | 8 | `XD` |
| `UIO_XK_PCA9555_DI` / `_DO` | 16 | `XD` |
| `UIO_XK_ADS1115_AI` | 4 (raw counts) | `XA` |
| `UIO_XK_MCP4728_AO` | 4 | `XA` |
| `UIO_XK_GP8413_AO` | 2 | `XA` |
| `UIO_XK_TMP117_T`, `UIO_XK_MCP9808_T` | 1 (°C) | `XA` |
| `UIO_XK_SHT4X_TH` | 2 (°C, %RH) | `XA` |

A second ADS1115 must use 16#48, 16#4A or 16#4B: 16#49 is the board's.

### The states

| `state` | Means |
| --- | --- |
| `UIO_XS_UNUSED` | an empty row |
| `UIO_XS_OK` | present and working |
| `UIO_XS_NOT_FITTED` | `fitted` FALSE: not on this site |
| `UIO_XS_MISSING` | nothing answers at the address |
| `UIO_XS_NO_DRIVER` | answers, but this firmware cannot read that kind yet |
| `UIO_XS_FAILING` | answers, and its transactions fail |
| `UIO_XS_BAD_ADDRESS` | not 16#08..16#77 |
| `UIO_XS_IN_USE` | the board's own part (16#49, 16#5F), or another row's address |
| `UIO_XS_NO_ROOM` | its channels do not fit the image from `first` |

### `UIO_I2C_SCAN`

| Pin | | |
| --- | --- | --- |
| `FOUND` | in-out, ARRAY OF BYTE | the addresses that answered, lowest first |
| `START` | in, BOOL | rising edge: scan 16#08..16#77 |
| `BUSY`, `DONE` | out, BOOL | scanning; finished |
| `COUNT` | out, USINT | addresses found |
| `ERROR`, `STATUS` | out | the bus is not up, or `FOUND` was too short |

A healthy board always shows 16#49 and 16#5F.

## Wiring it into the IO map

The module table is a settings table like any other: retain it, let the HMI
edit it. The images are plain arrays the project's IO code copies into the
IO map's image, with the module's `ok` as each channel's quality:

```
VAR_GLOBAL RETAIN
  XMODS : ARRAY[1..4] OF UIO_XMOD;
END_VAR
VAR_GLOBAL
  XDI : ARRAY[1..32] OF BOOL;
  XAI : ARRAY[1..8] OF REAL;
END_VAR

expansion(MODULES := XMODS, XD := XDI, XA := XAI);

(* One row of the IO map's module table per expansion row (UT_IO_MAP):
   src I2C, module = the row, first / count into the IO map's image. *)
FOR m := 1 TO 4 DO
  mods[I2C_ROW0 + m].ok := XMODS[m].ok;
  FOR c := 0 TO XMODS[m].count - 1 DO
    di[I2C_FIRST + XMODS[m].first + c].q := XDI[XMODS[m].first + c];
    di[I2C_FIRST + XMODS[m].first + c].bad := NOT XMODS[m].ok;
  END_FOR;
END_FOR;
```

A function mapped to a module that is not ok takes its fail-safe, and the IO
map says why. **A module that is not there is never read as OFF.**

## What it does on the bus

- **One transaction per call,** round the table, so the scan time stays flat
  however many modules there are.
- **Missing modules are asked again every five seconds,** so one plugged back
  in is found by itself. A working module that fails three transactions in a
  row is treated as missing and found again.
- **One lock for the bus.** The board's own ADC and DAC, `UIO_EXPANSION` and
  `UIO_I2C_SCAN` share Wire1 under one lock, whatever PLC task each runs in. A
  block that cannot have the bus within a few milliseconds tries again next
  scan rather than stalling its task.
- **I2C is a cabinet bus.** Keep modules within about a metre of the Node.
  Anything in the field belongs on RS485 (modbee-modbus), or behind a
  differential I2C extender.

## Adding a chip driver

A driver is three small functions and one table entry - nothing else in the
library changes. The interface is in `resources/node-uio/src/NodeUioExpansion.h`:

```cpp
struct UioXDriver {
  uint8_t kind;                                                    // UIO_XK_...
  bool (*start)(UioXBus& bus, uint8_t address);                    // identify + configure
  bool (*read)(UioXBus& bus, uint8_t address, UioXChannels& in);   // input kinds
  bool (*write)(UioXBus& bus, uint8_t address, const UioXChannels& out);  // output kinds
};
```

`UioXBus` gives `probe`, `write`, `read` and `writeRead` (a register write then
a read with a repeated start), each one complete transaction under the bus
lock. A driver never touches `Wire1` itself.

1. Write the driver in a new file beside `NodeUioExpansion.cpp`, e.g.
   `NodeUioDrvMcp23017.cpp`:
   - **start**: check the chip's identity where it has one (an ID register,
     register defaults after reset) and configure it (port directions, pull-ups,
     gain, conversion rate). Return false if it is not that chip or does not
     configure.
   - **read** (input kinds): fill `in.bits[0..count-1]` or
     `in.values[0..count-1]` in channel order. For a slow converter (ADS1115,
     temperature) start a conversion on one call and read it on a later one
     rather than waiting: the scan must never stall.
   - **write** (output kinds): send `out.bits` or `out.values`. Writing only
     what changed is the driver's choice.
   - Every function returns false on a failed transaction; the engine counts
     them, and three in a row make the module missing until it answers again.
2. Append it to `kDrivers[]` in `NodeUioExpansion.cpp`.
3. Add a simulated chip to the expansion host test (the test has a PCF8574 example)
   and run it before going to the bench.
4. Bench test on a real Node with the module: present / unplugged / plugged
   back, every channel, and the scan time with all eight rows fitted.

A driver can also live in another library and be added at run time with
`uioXRegisterDriver(&driver)` (up to eight).

Families planned, in order: MCP23017 / PCA9555 (16-bit DI/DO), PCF8574 (8-bit
DI/DO), ADS1115 (AI), MCP4728 / GP8413 (AO), TMP117 / MCP9808 / SHT4x
(temperature). Each costs about 1-3 KB of flash; only the families in a
project's table are polled.
