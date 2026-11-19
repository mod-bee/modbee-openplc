# 02 - Block reference

Sixteen blocks. `FB_NodeUio` is the one every project needs; the rest are there when
you want what they do.

Nothing takes a bitmask or a bare channel number: where a block picks something,
it picks it by name.

## `FB_NodeUio`

Brings the board up and services it. First in the program, once per scan.

| Pin | | |
| --- | --- | --- |
| `bBoardReady` | out, BOOL | the ADC and the DAC both answered |
| `bError` | out, BOOL | they did not |
| `eErrorId` | out, E_UioResult | why |

## `FB_DigitalInputs`

| Pin | | |
| --- | --- | --- |
| `bDI01`..`bDI08` | out, BOOL | the input, true while driven |

Sampled by `FB_NodeUio`, so the value does not change during a scan. An input that
cannot be read reads false. No debounce and no inversion — `R_TRIG`, `F_TRIG`
and `TON` do that in your own program.

## `FB_DigitalOutputs`

| Pin | | |
| --- | --- | --- |
| `bDO01`..`bDO08` | in, BOOL | drive the output |

Driven on the next `FB_NodeUio` call. No fault feedback exists: the board has no
readback, so a shorted output looks exactly like a working one.

## `FB_AnalogInputs`

| Pin | | |
| --- | --- | --- |
| `eAI01Mode`..`eAI04Mode` | in, E_AnalogMode | what the channel is wired for |
| `fAI01`..`fAI04` | out, REAL | the reading: volts on `UIO_VOLTAGE`, milliamps on `UIO_CURRENT`. A saturated input reads 11 V / 22 mA (see [03 Analog](03-analog.md)) |
| `nAI01RawCount`..`nAI04RawCount` | out, INT | the converter count behind it |

## `FB_AnalogOutputs`

| Pin | | |
| --- | --- | --- |
| `eAO01Mode`, `eAO02Mode` | in, E_AnalogMode | what the channel is wired for |
| `fAO01`, `fAO02` | in, REAL | the value to output: volts or milliamps |
| `nAO01RawCount`, `nAO02RawCount` | out, INT | the converter count it became |

## `FB_AnalogCalibration`

One channel at a time, named rather than numbered.

| Pin | | |
| --- | --- | --- |
| `eChannel` | in, E_AnalogChannel | which channel |
| `fOffset` | in, REAL | added to the reading after scaling, in volts or milliamps |
| `nZeroCount` | in, INT | converter count that reads 0 V or 0 mA |
| `nFullScaleCount` | in, INT | converter count that reads full scale, 10 V or 20 mA |
| `bApplyCalibration` | in, BOOL | one shot, use these three now |
| `bSaveToFlash` | in, BOOL | one shot, write every channel to flash |
| `bResetAllToDefaults` | in, BOOL | one shot, defaults everywhere, and save |
| `fOffsetInUse` | out, REAL | the offset `eChannel` currently holds |
| `nZeroCountInUse`, `nFullScaleCountInUse` | out, INT | the counts `eChannel` currently holds |
| `bSaveDone` | out, BOOL | one scan, a write succeeded |
| `bError` | out, BOOL | the last request failed |
| `eErrorId` | out, E_UioResult | why |

## `FB_HatPower`

| Pin | | |
| --- | --- | --- |
| `bHatPowerOn` | in, BOOL | power the expansion headers |
| `bEnableLineOn` | out, BOOL | what the line was last set to |

This drives the HAT power enable, which each HAT uses to switch its own supply
through its own MOSFET — the base board has no switch of its own. Takes effect
immediately, not at the next `FB_NodeUio` call. There is no sense line, so `bEnableLineOn`
reports the request, not what the HAT did with it.

## `FB_WiFiNetwork`

| Pin | | |
| --- | --- | --- |
| `bEnable` | in, BOOL | ask for the network; clear it to power the radio down |
| `sSsid` | in, STRING(32) | the network to join |
| `sWiFiPassword` | in, STRING(64) | its key, empty for an open network |
| `bNetworkUp` | out, BOOL | a network is up, whoever brought it up |
| `nIpAddress` | out, DWORD | the address, 0 while down |
| `nSignalStrengthDbm` | out, INT | signal strength in dBm, 0 while down |
| `bError` | out, BOOL | `bEnable` is set and there is still no network |
| `eErrorId` | out, E_UioResult | why |

The radio is shared. If something else brought the network up first — Modbus
TCP in the firmware, or a protocol library — this block reports it and changes
nothing, so the credentials here are only applied to a radio that is down, or
to one this block brought up itself. By the same rule, clearing `bEnable` will
not switch off a radio this block did not start.

`sSsid` and `sWiFiPassword` may change while connected (a settings page): on a radio
this block brought up, it leaves the network and joins again with the new ones.
`bNetworkUp` drops while it joins; MQTT and Sparkplug come back by themselves.

Clearing `bEnable` powers the radio down rather than merely disconnecting it,
which is the saving worth having on a battery. `FB_WiFiSleep` drives this pin to
duty-cycle it.

## `FB_BuiltInButton`

The button built into the board, beside the antenna, also on the HAT header.

| Pin | | |
| --- | --- | --- |
| `tDebounceTime` | in, TIME | ignore anything shorter, default `T#30ms` |
| `tLongPressDelay` | in, TIME | hold this long and it is a long press, default `T#2s` |
| `bPressed` | out, BOOL | held down right now |
| `bShortPress` | out, BOOL | one scan, on release before `tLongPressDelay` |
| `bLongPress` | out, BOOL | one scan, as soon as the hold passes `tLongPressDelay` |
| `tHeldTime` | out, TIME | how long it has been held, `T#0s` when released |

Use one instance. `bShortPress` and `bLongPress` are consumed as they are read,
so a second instance would take presses the first never saw.

## `FB_WiFiSleep`

Duty-cycles the radio, for a board on a battery.

| Pin | | |
| --- | --- | --- |
| `bEnable` | in, BOOL | keep the radio off except when woken |
| `bWakeNow` | in, BOOL | rising edge, bring it back now |
| `tStayAwakeTime` | in, TIME | how long it stays up once woken, default `T#5m` |
| `tWakeInterval` | in, TIME | also bring it back this often, `T#0s` for only on `bWakeNow` |
| `bRadioOn` | out, BOOL | the radio should be powered — wire to `FB_WiFiNetwork.bEnable` |
| `tAwakeTimeLeft` | out, TIME | time before it powers down again |

```
btn();
wifiSleep(bEnable := TRUE, bWakeNow := btn.bShortPress, tStayAwakeTime := T#5m);
net(bEnable := wifiSleep.bRadioOn, sSsid := 'plant', sWiFiPassword := 'secret');
```

`bWakeNow` takes any signal, not only the button — a shift starting, a fault, a
level switch. Clearing `bEnable` hands the radio back and stops duty-cycling it.

## `FB_Sleep`

| Pin | | |
| --- | --- | --- |
| `bExecute` | in, BOOL | one shot, sleep now |
| `eSleepMode` | in, E_SleepMode | light or deep |
| `nWakeAfterSeconds` | in, UDINT | wake after this long, 0 for no timer |
| `bWakeOnDI01`..`bWakeOnDI08` | in, BOOL | use this input as a wake source |
| `bDO01DuringSleep`..`bDO04DuringSleep` | in, BOOL | the level DO01..DO04 hold while asleep |
| `bHatPoweredDuringSleep` | in, BOOL | keep the HAT powered while asleep |
| `bLedOnDuringSleep` | in, BOOL | keep the status LED lit (dim blue) while asleep |
| `eWakeCause` | out, E_WakeCause | what ended the last sleep |
| `bError` | out, BOOL | the request was refused |
| `eErrorId` | out, E_UioResult | why |

Deep sleep saves the retained values first, so the board goes to sleep about
10 to 50 ms after `bExecute`; light sleep does not need to. See
[04 Sleep](04-sleep.md), particularly about DO05 to DO08.

## `FB_Restart`

| Pin | | |
| --- | --- | --- |
| `bExecute` | in, BOOL | rising edge, restart the controller now |
| `nResetReasonCode` | out, USINT | why this run started (ESP-IDF reset reason): 1 power-on, 3 a software restart, 4 a crash, 5 to 7 a watchdog, 8 deep sleep wake, 9 brownout |
| `bStartedBySoftwareRestart` | out, BOOL | this run started from a software restart |

For a site that has to recover by itself: a link supervisor that has tried the
modem and the HAT power asks for one controlled restart, and this does it. It
saves the retained values first, so nothing the store was still holding is lost;
the restart waits for that save, about 10 to 50 ms. A `bExecute` already TRUE at
start-up is not an edge.

```
sup( LinkOk := sp.BORN, RebootAllowed := NOT pumpRunning, Data := supCfg );
reboot( bExecute := sup.RebootReq );
```

## `FB_PulseCounter`

A flow meter, or any pulse output, on a digital input — counted in hardware.

| Pin | | |
| --- | --- | --- |
| `fTotal` | in-out, LREAL | the running total in your units: your own variable, `RETAIN` it |
| `nInputNumber` | in, USINT | the input, 1..8 |
| `fPulsesPerUnit` | in, REAL | pulses per unit (100 pulses a litre: `100.0`); 0 counts pulses |
| `tRateTimeBase` | in, TIME | the rate's time base: `T#1s`, `T#1m`, `T#1h`; `T#1s` if `T#0s` |
| `tMinPulseLength` | in, TIME | shorter pulses are noise (up to about 12 µs) |
| `tRateWindow` | in, TIME | the rate is measured over at least this, `T#1s` if `T#0s` |
| `tRateZeroAfter` | in, TIME | no pulse this long and the rate is 0, `T#30s` if `T#0s` |
| `bEnable` | in, BOOL | count while TRUE, default TRUE |
| `fRate` | out, REAL | units per `tRateTimeBase` |
| `nPulseCount` | out, UDINT | pulses since counting started |
| `bValid` | out, BOOL | the counter is running |
| `bError` | out, BOOL | the input could not be counted |
| `eErrorId` | out, E_UioResult | `UIO_TOO_LARGE` when all four counters are taken |

```
VAR RETAIN flowTotal : LREAL; END_VAR
flow( fTotal := flowTotal, nInputNumber := 3, fPulsesPerUnit := 100.0, tRateTimeBase := T#1h );
```

See [07 Pulses and diagnostics](07-pulses-and-diagnostics.md).

## `FB_SystemInfo`

How the controller itself is doing. No inputs; refreshed once a second.

| Pin | | |
| --- | --- | --- |
| `nHeapFreeBytes` | out, UDINT | internal RAM free now, bytes |
| `nHeapLowestBytes` | out, UDINT | the least it has been since start |
| `nHeapLargestBlockBytes` | out, UDINT | the largest block that could be allocated |
| `nPsramFreeBytes`, `nPsramSizeBytes` | out, UDINT | external RAM free, and fitted |
| `nStackLowestMarginBytes` | out, UDINT | the smallest stack margin among the PLC's tasks, bytes |
| `sStackLowestTask` | out, STRING(16) | which task |
| `tUptime` | out, TIME | since the board started |
| `eResetReason` | out, E_ResetReason | why it last started |
| `sProgramId` | out, STRING(32) | the program's identity (its MD5) |
| `sFirmwareVersion` | out, STRING(30) | firmware and ESP-IDF version |
| `eErrorId` | out, E_UioResult | `UIO_UNSUPPORTED` on the Runtime |

## `FB_ExpansionModules`

I2C expansion modules on the board's I2C bus: which are fitted, which answer,
and their channels in two images.

| Pin | | |
| --- | --- | --- |
| `aModules` | in-out, ARRAY OF ST_ExpansionModule | the module table, up to 8 rows (below) |
| `aDigitalImage` | in-out, ARRAY OF BOOL | the digital image: DI modules write, DO modules read |
| `aAnalogImage` | in-out, ARRAY OF REAL | the analog image: AI, AO and temperature modules |
| `bAllModulesGood` | out, BOOL | every fitted module is present and working |
| `nModulesFitted` | out, USINT | rows fitted |
| `nFaultyModules` | out, USINT | fitted rows that are not ok |
| `nFirstFaultyModule` | out, INT | the first such row, 0 when none |
| `bError` | out, BOOL | a fitted module is not ok |
| `eErrorId` | out, E_UioResult | `UIO_UNSUPPORTED` on the Runtime |
| `sStatusText` | out, STRING(30) | the first problem: `mod 2 0x21 missing` |

`ST_ExpansionModule`: `eModuleType` (E_ExpansionModuleType), `nI2cAddress` (BYTE), `bFitted` (BOOL, default
TRUE) and `nFirstImageIndex` (INT, the image row of channel 1) are settings; `nChannels`,
`bAnswering`, `bGood`, `eModuleState` (E_ExpansionModuleState) and `nFailedTransactionCount` are status.

No chip drivers are built in yet: a fitted module that answers reads
`UIO_XS_NO_DRIVER` and is not ok. See [08 I2C expansion](08-expansion.md).

## `FB_I2cScan`

The I2C addresses that answer, for commissioning.

| Pin | | |
| --- | --- | --- |
| `aFoundAddresses` | in-out, ARRAY OF BYTE | the addresses found, lowest first, the rest 0 |
| `bExecute` | in, BOOL | rising edge: scan 16#08..16#77 |
| `bBusy` | out, BOOL | scanning (about 30 scans) |
| `bDone` | out, BOOL | the last scan finished |
| `nAddressesFound` | out, USINT | addresses found, the board's 16#49 and 16#5F included |
| `bError` | out, BOOL | the bus is not up, or `aFoundAddresses` was too short |
| `eErrorId` | out, E_UioResult | why |

## The enumerations

`E_AnalogMode` — `UIO_VOLTAGE`, `UIO_CURRENT`.

`E_AnalogChannel` — `UIO_AI01`..`UIO_AI04`, `UIO_AO01`, `UIO_AO02`.

`E_SleepMode` — `UIO_LIGHT_SLEEP`, `UIO_DEEP_SLEEP`.

`E_WakeCause` — `UIO_WAKE_NONE`, `UIO_WAKE_TIMER`, `UIO_WAKE_INPUT`, `UIO_WAKE_RESET`.

`E_UioResult` — `UIO_OK`, `UIO_NOT_READY`, `UIO_INVALID_ARGUMENT`, `UIO_IO_ERROR`,
`UIO_NO_DATA`, `UIO_TOO_LARGE`, `UIO_UNSUPPORTED`.

`E_ResetReason` — `UIO_RST_UNKNOWN`, `UIO_RST_POWER_ON`, `UIO_RST_EXTERNAL`,
`UIO_RST_SOFTWARE`, `UIO_RST_PANIC`, `UIO_RST_INT_WDT`, `UIO_RST_TASK_WDT`,
`UIO_RST_OTHER_WDT`, `UIO_RST_DEEP_SLEEP`, `UIO_RST_BROWNOUT`, `UIO_RST_SDIO`,
`UIO_RST_USB`, `UIO_RST_JTAG`, `UIO_RST_EFUSE`, `UIO_RST_PWR_GLITCH`,
`UIO_RST_CPU_LOCKUP` (the ESP-IDF reset reasons, in order).

`E_ExpansionModuleType` — `UIO_XK_NONE`, `UIO_XK_MCP23017_DI`, `UIO_XK_MCP23017_DO`,
`UIO_XK_PCF8574_DI`, `UIO_XK_PCF8574_DO`, `UIO_XK_PCA9555_DI`,
`UIO_XK_PCA9555_DO`, `UIO_XK_ADS1115_AI`, `UIO_XK_MCP4728_AO`,
`UIO_XK_GP8413_AO`, `UIO_XK_TMP117_T`, `UIO_XK_MCP9808_T`, `UIO_XK_SHT4X_TH`.

`E_ExpansionModuleState` — `UIO_XS_UNUSED`, `UIO_XS_OK`, `UIO_XS_NOT_FITTED`,
`UIO_XS_MISSING`, `UIO_XS_NO_DRIVER`, `UIO_XS_FAILING`, `UIO_XS_BAD_ADDRESS`,
`UIO_XS_IN_USE`, `UIO_XS_NO_ROOM`.
