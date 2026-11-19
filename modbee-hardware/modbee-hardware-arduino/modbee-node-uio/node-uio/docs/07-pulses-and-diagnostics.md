# 07 - Pulses and diagnostics

Two blocks for the things a pump site always ends up needing: a flow meter's
pulses turned into a total and a rate, and a look at the controller itself when
something is odd on site.

## A flow meter: `FB_PulseCounter`

### Pins first

| Pin | | |
| --- | --- | --- |
| `fTotal` | in-out, LREAL | the running total, in your units. Your own variable: `RETAIN` it |
| `nInputNumber` | in, USINT | the input, 1..8 (DI01..DI08) |
| `fPulsesPerUnit` | in, REAL | pulses per unit, from the meter's plate. 0 counts pulses |
| `tRateTimeBase` | in, TIME | `T#1s` units a second, `T#1m` a minute, `T#1h` an hour |
| `tMinPulseLength` | in, TIME | pulses shorter than this are noise |
| `tRateWindow` | in, TIME | the rate is measured over at least this long (`T#1s`) |
| `tRateZeroAfter` | in, TIME | no pulse this long: the rate is 0 (`T#30s`) |
| `bEnable` | in, BOOL | count while TRUE |
| `fRate` | out, REAL | units per `tRateTimeBase` |
| `nPulseCount` | out, UDINT | pulses since counting started |
| `bValid` | out, BOOL | the counter is running |
| `bError`, `eErrorId` | out | why it is not |

### Wiring it

```
VAR RETAIN
  flowTotalL : LREAL;          (* litres, kept over a power cut *)
END_VAR

flow( fTotal := flowTotalL, nInputNumber := 3, fPulsesPerUnit := 100.0, tRateTimeBase := T#1m );
(* flow.fRate: litres a minute *)
```

The meter's plate gives its **K-factor**: pulses per litre (or per m³, per
gallon). Put that in `fPulsesPerUnit` and `fTotal` and `fRate` come out in that unit.
A meter that gives one pulse per 10 litres has a K-factor of 0.1.

### What it does

- **The chip counts, not the scan.** The ESP32-S3's pulse counter sees every
  rising edge, so a fast meter loses nothing however long the scan is. Four
  inputs can be counted at once (the chip has four counters); a fifth reports
  `UIO_TOO_LARGE`. The input still reads normally on `FB_DigitalInputs`.
- **The total is yours.** Each scan's new pulses (divided by `fPulsesPerUnit`) are
  added to `fTotal`. Make it `RETAIN` and it carries over a power cut; write 0
  to reset it. It is an LREAL because a REAL total of a meter that has run for
  years loses its small increments. Pulses that arrive while the PLC is off are
  not counted.
- **The rate suits fast and slow meters.** Fast pulses are counted over at
  least `tRateWindow`, from one pulse to another, so the answer does not jitter
  with the scan. Slow pulses use the time between them: one pulse every ten
  seconds reads a steady 0.1 a second, not 1 then 0. When the pulses stop, the
  rate falls away (it can be no more than one pulse over the time since the
  last) and is 0 after `tRateZeroAfter`. Set `tRateZeroAfter` above the longest gap
  you expect at the lowest real flow.
- **Contact (reed) meters bounce** for milliseconds. The hardware filter tops
  out at about 12 µs, so it cannot remove that. Use a meter with an
  open-collector (solid-state) output, or an RC filter on the input.

## The controller: `FB_SystemInfo`

### Pins first

| Pin | | |
| --- | --- | --- |
| `nHeapFreeBytes` | out, UDINT | internal RAM free now |
| `nHeapLowestBytes` | out, UDINT | the least it has been since the board started |
| `nHeapLargestBlockBytes` | out, UDINT | the largest block that could be allocated now |
| `nPsramFreeBytes`, `nPsramSizeBytes` | out, UDINT | external RAM free, and fitted |
| `nStackLowestMarginBytes` | out, UDINT | the smallest stack margin among the PLC's tasks, bytes |
| `sStackLowestTask` | out, STRING(16) | which task that is |
| `tUptime` | out, TIME | since the board started |
| `eResetReason` | out, E_ResetReason | why it last started |
| `sProgramId` | out, STRING(32) | the program's identity |
| `sFirmwareVersion` | out, STRING(30) | firmware and ESP-IDF version |
| `eErrorId` | out, E_UioResult | `UIO_UNSUPPORTED` on the Runtime |

```
info();
STS.heapMin := info.nHeapLowestBytes;
STS.resetReason := info.eResetReason;
```

No inputs: call it once, anywhere. It reads the heap once a second (the
figures walk the heap, so not every scan).

### Reading it

| You see | It means |
| --- | --- |
| `eResetReason` = `UIO_RST_PANIC` | the firmware crashed |
| `UIO_RST_INT_WDT`, `UIO_RST_TASK_WDT`, `UIO_RST_OTHER_WDT` | a watchdog: a task hung or ran far too long |
| `UIO_RST_BROWNOUT` | the supply dipped - look at the power, not the program |
| `UIO_RST_SOFTWARE` | `FB_Restart`, or an update |
| `nHeapLowestBytes` falling day after day | a leak |
| `nHeapLargestBlockBytes` far below `nHeapFreeBytes` | the heap is fragmented |
| `nStackLowestMarginBytes` under about 512 | `sStackLowestTask` is close to overflowing its stack |

`nStackLowestMarginBytes` covers every IEC task (each is a FreeRTOS task of that name when
the board runs in RTOS mode) and the firmware's own service tasks
(`plc_dispatch`, `plc_modbus`, `plc_protocols`). Without RTOS mode it is the
task `FB_SystemInfo` runs in.

`sProgramId` is the MD5 the editor's debugger checks: it tells which program
is on a board.

Alarm on `eResetReason` being a panic or a watchdog: the board restarted by
itself, and nobody would otherwise know.
