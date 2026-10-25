# 02 - Block reference

Sixteen blocks. `UIO` is the one every project needs; the rest are there when
you want what they do.

Nothing takes a bitmask or a bare channel number: where a block picks something,
it picks it by name.

## `UIO`

Brings the board up and services it. First in the program, once per scan.

| Pin | | |
| --- | --- | --- |
| `READY` | out, BOOL | the ADC and the DAC both answered |
| `ERROR` | out, BOOL | they did not |
| `STATUS` | out, UIO_RESULT | why |

## `DIGITAL_IN`

| Pin | | |
| --- | --- | --- |
| `DI01`..`DI08` | out, BOOL | the input, true while driven |

Sampled by `UIO`, so the value does not change during a scan. An input that
cannot be read reads false. No debounce and no inversion — `R_TRIG`, `F_TRIG`
and `TON` do that in your own program.

## `DIGITAL_OUT`

| Pin | | |
| --- | --- | --- |
| `DO01`..`DO08` | in, BOOL | drive the output |

Driven on the next `UIO` call. No fault feedback exists: the board has no
readback, so a shorted output looks exactly like a working one.

## `ANALOG_IN`

| Pin | | |
| --- | --- | --- |
| `AI01_MODE`..`AI04_MODE` | in, UIO_MODE | what the channel is wired for |
| `AI01`..`AI04` | out, REAL | the reading: volts on `UIO_VOLTAGE`, milliamps on `UIO_CURRENT`. A saturated input reads 11 V / 22 mA (see [03 Analog](03-analog.md)) |
| `AI01_RAW`..`AI04_RAW` | out, INT | the converter count behind it |

## `ANALOG_OUT`

| Pin | | |
| --- | --- | --- |
| `AO01_MODE`, `AO02_MODE` | in, UIO_MODE | what the channel is wired for |
| `AO01`, `AO02` | in, REAL | the value to output: volts or milliamps |
| `AO01_RAW`, `AO02_RAW` | out, INT | the converter count it became |

## `ANALOG_CAL`

One channel at a time, named rather than numbered.

| Pin | | |
| --- | --- | --- |
| `CHANNEL` | in, UIO_CHANNEL | which channel |
| `OFFSET` | in, REAL | added to the reading after scaling, in volts or milliamps |
| `LOW_COUNT` | in, INT | converter count at the bottom of the range |
| `HIGH_COUNT` | in, INT | converter count at the top |
| `APPLY` | in, BOOL | one shot, use these three now |
| `SAVE` | in, BOOL | one shot, write every channel to flash |
| `RESET` | in, BOOL | one shot, defaults everywhere, and save |
| `OFFSET_NOW` | out, REAL | the offset `CHANNEL` currently holds |
| `LOW_NOW`, `HIGH_NOW` | out, INT | the counts `CHANNEL` currently holds |
| `SAVED` | out, BOOL | one scan, a write succeeded |
| `ERROR` | out, BOOL | the last request failed |
| `STATUS` | out, UIO_RESULT | why |

## `HAT_POWER`

| Pin | | |
| --- | --- | --- |
| `ENABLE` | in, BOOL | power the expansion headers |
| `POWERED` | out, BOOL | what the line was last set to |

This drives the HAT power enable, which each HAT uses to switch its own supply
through its own MOSFET — the base board has no switch of its own. Takes effect
immediately, not at the next `UIO` call. There is no sense line, so `POWERED`
reports the request, not what the HAT did with it.

## `NETWORK`

| Pin | | |
| --- | --- | --- |
| `ENABLE` | in, BOOL | ask for the network; clear it to power the radio down |
| `SSID` | in, STRING(32) | the network to join |
| `PASSWORD` | in, STRING(64) | its key, empty for an open network |
| `CONNECTED` | out, BOOL | a network is up, whoever brought it up |
| `IP` | out, DWORD | the address, 0 while down |
| `RSSI` | out, INT | signal strength in dBm, 0 while down |
| `ERROR` | out, BOOL | `ENABLE` is set and there is still no network |
| `STATUS` | out, UIO_RESULT | why |

The radio is shared. If something else brought the network up first — Modbus
TCP in the firmware, or a protocol library — this block reports it and changes
nothing, so the credentials here are only applied to a radio that is down, or
to one this block brought up itself. By the same rule, clearing `ENABLE` will
not switch off a radio this block did not start.

`SSID` and `PASSWORD` may change while connected (a settings page): on a radio
this block brought up, it leaves the network and joins again with the new ones.
`CONNECTED` drops while it joins; MQTT and Sparkplug come back by themselves.

Clearing `ENABLE` powers the radio down rather than merely disconnecting it,
which is the saving worth having on a battery. `WIFI_SLEEP` drives this pin to
duty-cycle it.

## `BUILTIN_BUTTON`

The button built into the board, beside the antenna, also on the HAT header.

| Pin | | |
| --- | --- | --- |
| `DEBOUNCE` | in, TIME | ignore anything shorter, default `T#30ms` |
| `LONG` | in, TIME | hold this long and it is a long press, default `T#2s` |
| `PRESSED` | out, BOOL | held down right now |
| `SHORT_PRESS` | out, BOOL | one scan, on release before `LONG` |
| `LONG_PRESS` | out, BOOL | one scan, as soon as the hold passes `LONG` |
| `HELD` | out, TIME | how long it has been held, `T#0s` when released |

Use one instance. `SHORT_PRESS` and `LONG_PRESS` are consumed as they are read,
so a second instance would take presses the first never saw.

## `WIFI_SLEEP`

Duty-cycles the radio, for a board on a battery.

| Pin | | |
| --- | --- | --- |
| `ENABLE` | in, BOOL | keep the radio off except when woken |
| `WAKE` | in, BOOL | rising edge, bring it back now |
| `AWAKE` | in, TIME | how long it stays up once woken, default `T#5m` |
| `WAKE_EVERY` | in, TIME | also bring it back this often, `T#0s` for only on `WAKE` |
| `RADIO_ON` | out, BOOL | the radio should be powered — wire to `NETWORK.ENABLE` |
| `AWAKE_LEFT` | out, TIME | time before it powers down again |

```
btn();
wifiSleep(ENABLE := TRUE, WAKE := btn.SHORT_PRESS, AWAKE := T#5m);
net(ENABLE := wifiSleep.RADIO_ON, SSID := 'plant', PASSWORD := 'secret');
```

`WAKE` takes any signal, not only the button — a shift starting, a fault, a
level switch. Clearing `ENABLE` hands the radio back and stops duty-cycling it.

## `SLEEP`

| Pin | | |
| --- | --- | --- |
| `TRIGGER` | in, BOOL | one shot, sleep now |
| `MODE` | in, UIO_SLEEP | light or deep |
| `SECONDS` | in, UDINT | wake after this long, 0 for no timer |
| `EN_WAKE_DI01`..`EN_WAKE_DI08` | in, BOOL | use this input as a wake source |
| `DO01_IN_SLEEP`..`DO04_IN_SLEEP` | in, BOOL | the level DO01..DO04 hold while asleep |
| `HAT_IN_SLEEP` | in, BOOL | keep the HAT powered while asleep |
| `LED_IN_SLEEP` | in, BOOL | keep the status LED lit (dim blue) while asleep |
| `WAKE_CAUSE` | out, UIO_WAKE | what ended the last sleep |
| `ERROR` | out, BOOL | the request was refused |
| `STATUS` | out, UIO_RESULT | why |

Deep sleep saves the retained values first, so the board goes to sleep about
10 to 50 ms after `TRIGGER`; light sleep does not need to. See
[04 Sleep](04-sleep.md), particularly about DO05 to DO08.

## `RESTART`

| Pin | | |
| --- | --- | --- |
| `REQ` | in, BOOL | rising edge, restart the controller now |
| `REASON` | out, USINT | why this run started (ESP-IDF reset reason): 1 power-on, 3 a software restart, 4 a crash, 5 to 7 a watchdog, 8 deep sleep wake, 9 brownout |
| `RESTARTED` | out, BOOL | this run started from a software restart |

For a site that has to recover by itself: a link supervisor that has tried the
modem and the HAT power asks for one controlled restart, and this does it. It
saves the retained values first, so nothing the store was still holding is lost;
the restart waits for that save, about 10 to 50 ms. A `REQ` already TRUE at
start-up is not an edge.

```
sup( LinkOk := sp.BORN, RebootAllowed := NOT pumpRunning, Data := supCfg );
reboot( REQ := sup.RebootReq );
```

## `PULSE_COUNT`

A flow meter, or any pulse output, on a digital input — counted in hardware.

| Pin | | |
| --- | --- | --- |
| `TOTAL` | in-out, LREAL | the running total in your units: your own variable, `RETAIN` it |
| `CHANNEL` | in, USINT | the input, 1..8 |
| `K_FACTOR` | in, REAL | pulses per unit (100 pulses a litre: `100.0`); 0 counts pulses |
| `RATE_PER` | in, TIME | the rate's time base: `T#1s`, `T#1m`, `T#1h`; `T#1s` if `T#0s` |
| `FILTER` | in, TIME | shorter pulses are noise (up to about 12 µs) |
| `WINDOW` | in, TIME | the rate is measured over at least this, `T#1s` if `T#0s` |
| `ZERO_AFTER` | in, TIME | no pulse this long and the rate is 0, `T#30s` if `T#0s` |
| `ENABLE` | in, BOOL | count while TRUE, default TRUE |
| `RATE` | out, REAL | units per `RATE_PER` |
| `PULSES` | out, UDINT | pulses since counting started |
| `COUNTING` | out, BOOL | the counter is running |
| `ERROR` | out, BOOL | the input could not be counted |
| `STATUS` | out, UIO_RESULT | `UIO_TOO_LARGE` when all four counters are taken |

```
VAR RETAIN flowTotal : LREAL; END_VAR
flow( TOTAL := flowTotal, CHANNEL := 3, K_FACTOR := 100.0, RATE_PER := T#1h );
```

See [07 Pulses and diagnostics](07-pulses-and-diagnostics.md).

## `SYS_INFO`

How the controller itself is doing. No inputs; refreshed once a second.

| Pin | | |
| --- | --- | --- |
| `HEAP_FREE` | out, UDINT | internal RAM free now, bytes |
| `HEAP_MIN` | out, UDINT | the least it has been since start |
| `HEAP_LARGEST` | out, UDINT | the largest block that could be allocated |
| `PSRAM_FREE`, `PSRAM_SIZE` | out, UDINT | external RAM free, and fitted |
| `STACK_MIN` | out, UDINT | the smallest stack margin among the PLC's tasks, bytes |
| `STACK_TASK` | out, STRING(16) | which task |
| `UPTIME` | out, TIME | since the board started |
| `RESET_REASON` | out, UIO_RESET | why it last started |
| `PROGRAM_ID` | out, STRING(32) | the program's identity (its MD5) |
| `FIRMWARE` | out, STRING(30) | firmware and ESP-IDF version |
| `STATUS` | out, UIO_RESULT | `UIO_UNSUPPORTED` on the Runtime |

## `UIO_EXPANSION`

I2C expansion modules on the board's I2C bus: which are fitted, which answer,
and their channels in two images.

| Pin | | |
| --- | --- | --- |
| `MODULES` | in-out, ARRAY OF UIO_XMOD | the module table, up to 8 rows (below) |
| `XD` | in-out, ARRAY OF BOOL | the digital image: DI modules write, DO modules read |
| `XA` | in-out, ARRAY OF REAL | the analog image: AI, AO and temperature modules |
| `ALL_OK` | out, BOOL | every fitted module is present and working |
| `FITTED_COUNT` | out, USINT | rows fitted |
| `MISSING_COUNT` | out, USINT | fitted rows that are not ok |
| `FIRST_BAD` | out, INT | the first such row, 0 when none |
| `ERROR` | out, BOOL | a fitted module is not ok |
| `STATUS` | out, UIO_RESULT | `UIO_UNSUPPORTED` on the Runtime |
| `STATUS_TEXT` | out, STRING(30) | the first problem: `mod 2 0x21 missing` |

`UIO_XMOD`: `kind` (UIO_XKIND), `address` (BYTE), `fitted` (BOOL, default
TRUE) and `first` (INT, the image row of channel 1) are settings; `count`,
`present`, `ok`, `state` (UIO_XSTATE) and `errors` are status.

No chip drivers are built in yet: a fitted module that answers reads
`UIO_XS_NO_DRIVER` and is not ok. See [08 I2C expansion](08-expansion.md).

## `UIO_I2C_SCAN`

The I2C addresses that answer, for commissioning.

| Pin | | |
| --- | --- | --- |
| `FOUND` | in-out, ARRAY OF BYTE | the addresses found, lowest first, the rest 0 |
| `START` | in, BOOL | rising edge: scan 16#08..16#77 |
| `BUSY` | out, BOOL | scanning (about 30 scans) |
| `DONE` | out, BOOL | the last scan finished |
| `COUNT` | out, USINT | addresses found, the board's 16#49 and 16#5F included |
| `ERROR` | out, BOOL | the bus is not up, or `FOUND` was too short |
| `STATUS` | out, UIO_RESULT | why |

## The enumerations

`UIO_MODE` — `UIO_VOLTAGE`, `UIO_CURRENT`.

`UIO_CHANNEL` — `UIO_AI01`..`UIO_AI04`, `UIO_AO01`, `UIO_AO02`.

`UIO_SLEEP` — `UIO_LIGHT_SLEEP`, `UIO_DEEP_SLEEP`.

`UIO_WAKE` — `UIO_WAKE_NONE`, `UIO_WAKE_TIMER`, `UIO_WAKE_INPUT`, `UIO_WAKE_RESET`.

`UIO_RESULT` — `UIO_OK`, `UIO_NOT_READY`, `UIO_INVALID_ARGUMENT`, `UIO_IO_ERROR`,
`UIO_NO_DATA`, `UIO_TOO_LARGE`, `UIO_UNSUPPORTED`.

`UIO_RESET` — `UIO_RST_UNKNOWN`, `UIO_RST_POWER_ON`, `UIO_RST_EXTERNAL`,
`UIO_RST_SOFTWARE`, `UIO_RST_PANIC`, `UIO_RST_INT_WDT`, `UIO_RST_TASK_WDT`,
`UIO_RST_OTHER_WDT`, `UIO_RST_DEEP_SLEEP`, `UIO_RST_BROWNOUT`, `UIO_RST_SDIO`,
`UIO_RST_USB`, `UIO_RST_JTAG`, `UIO_RST_EFUSE`, `UIO_RST_PWR_GLITCH`,
`UIO_RST_CPU_LOCKUP` (the ESP-IDF reset reasons, in order).

`UIO_XKIND` — `UIO_XK_NONE`, `UIO_XK_MCP23017_DI`, `UIO_XK_MCP23017_DO`,
`UIO_XK_PCF8574_DI`, `UIO_XK_PCF8574_DO`, `UIO_XK_PCA9555_DI`,
`UIO_XK_PCA9555_DO`, `UIO_XK_ADS1115_AI`, `UIO_XK_MCP4728_AO`,
`UIO_XK_GP8413_AO`, `UIO_XK_TMP117_T`, `UIO_XK_MCP9808_T`, `UIO_XK_SHT4X_TH`.

`UIO_XSTATE` — `UIO_XS_UNUSED`, `UIO_XS_OK`, `UIO_XS_NOT_FITTED`,
`UIO_XS_MISSING`, `UIO_XS_NO_DRIVER`, `UIO_XS_FAILING`, `UIO_XS_BAD_ADDRESS`,
`UIO_XS_IN_USE`, `UIO_XS_NO_ROOM`.
