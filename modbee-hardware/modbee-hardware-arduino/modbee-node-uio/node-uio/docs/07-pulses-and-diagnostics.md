# 07 - Pulses and diagnostics

Two blocks for the things a pump site always ends up needing: a flow meter's
pulses turned into a total and a rate, and a look at the controller itself when
something is odd on site.

## A flow meter: `PULSE_COUNT`

### Pins first

| Pin | | |
| --- | --- | --- |
| `TOTAL` | in-out, LREAL | the running total, in your units. Your own variable: `RETAIN` it |
| `CHANNEL` | in, USINT | the input, 1..8 (DI01..DI08) |
| `K_FACTOR` | in, REAL | pulses per unit, from the meter's plate. 0 counts pulses |
| `RATE_PER` | in, TIME | `T#1s` units a second, `T#1m` a minute, `T#1h` an hour |
| `FILTER` | in, TIME | pulses shorter than this are noise |
| `WINDOW` | in, TIME | the rate is measured over at least this long (`T#1s`) |
| `ZERO_AFTER` | in, TIME | no pulse this long: the rate is 0 (`T#30s`) |
| `ENABLE` | in, BOOL | count while TRUE |
| `RATE` | out, REAL | units per `RATE_PER` |
| `PULSES` | out, UDINT | pulses since counting started |
| `COUNTING` | out, BOOL | the counter is running |
| `ERROR`, `STATUS` | out | why it is not |

### Wiring it

```
VAR RETAIN
  flowTotalL : LREAL;          (* litres, kept over a power cut *)
END_VAR

flow( TOTAL := flowTotalL, CHANNEL := 3, K_FACTOR := 100.0, RATE_PER := T#1m );
(* flow.RATE: litres a minute *)
```

The meter's plate gives its **K-factor**: pulses per litre (or per m³, per
gallon). Put that in `K_FACTOR` and `TOTAL` and `RATE` come out in that unit.
A meter that gives one pulse per 10 litres has a K-factor of 0.1.

### What it does

- **The chip counts, not the scan.** The ESP32-S3's pulse counter sees every
  rising edge, so a fast meter loses nothing however long the scan is. Four
  inputs can be counted at once (the chip has four counters); a fifth reports
  `UIO_TOO_LARGE`. The input still reads normally on `DIGITAL_IN`.
- **The total is yours.** Each scan's new pulses (divided by `K_FACTOR`) are
  added to `TOTAL`. Make it `RETAIN` and it carries over a power cut; write 0
  to reset it. It is an LREAL because a REAL total of a meter that has run for
  years loses its small increments. Pulses that arrive while the PLC is off are
  not counted.
- **The rate suits fast and slow meters.** Fast pulses are counted over at
  least `WINDOW`, from one pulse to another, so the answer does not jitter
  with the scan. Slow pulses use the time between them: one pulse every ten
  seconds reads a steady 0.1 a second, not 1 then 0. When the pulses stop, the
  rate falls away (it can be no more than one pulse over the time since the
  last) and is 0 after `ZERO_AFTER`. Set `ZERO_AFTER` above the longest gap
  you expect at the lowest real flow.
- **Contact (reed) meters bounce** for milliseconds. The hardware filter tops
  out at about 12 µs, so it cannot remove that. Use a meter with an
  open-collector (solid-state) output, or an RC filter on the input.

## The controller: `SYS_INFO`

### Pins first

| Pin | | |
| --- | --- | --- |
| `HEAP_FREE` | out, UDINT | internal RAM free now |
| `HEAP_MIN` | out, UDINT | the least it has been since the board started |
| `HEAP_LARGEST` | out, UDINT | the largest block that could be allocated now |
| `PSRAM_FREE`, `PSRAM_SIZE` | out, UDINT | external RAM free, and fitted |
| `STACK_MIN` | out, UDINT | the smallest stack margin among the PLC's tasks, bytes |
| `STACK_TASK` | out, STRING(16) | which task that is |
| `UPTIME` | out, TIME | since the board started |
| `RESET_REASON` | out, UIO_RESET | why it last started |
| `PROGRAM_ID` | out, STRING(32) | the program's identity |
| `FIRMWARE` | out, STRING(30) | firmware and ESP-IDF version |
| `STATUS` | out, UIO_RESULT | `UIO_UNSUPPORTED` on the Runtime |

```
info();
STS.heapMin := info.HEAP_MIN;
STS.resetReason := info.RESET_REASON;
```

No inputs: call it once, anywhere. It reads the heap once a second (the
figures walk the heap, so not every scan).

### Reading it

| You see | It means |
| --- | --- |
| `RESET_REASON` = `UIO_RST_PANIC` | the firmware crashed |
| `UIO_RST_INT_WDT`, `UIO_RST_TASK_WDT`, `UIO_RST_OTHER_WDT` | a watchdog: a task hung or ran far too long |
| `UIO_RST_BROWNOUT` | the supply dipped - look at the power, not the program |
| `UIO_RST_SOFTWARE` | `RESTART`, or an update |
| `HEAP_MIN` falling day after day | a leak |
| `HEAP_LARGEST` far below `HEAP_FREE` | the heap is fragmented |
| `STACK_MIN` under about 512 | `STACK_TASK` is close to overflowing its stack |

`STACK_MIN` covers every IEC task (each is a FreeRTOS task of that name when
the board runs in RTOS mode) and the firmware's own service tasks
(`plc_dispatch`, `plc_modbus`, `plc_protocols`). Without RTOS mode it is the
task `SYS_INFO` runs in.

`PROGRAM_ID` is the MD5 the editor's debugger checks: it tells which program
is on a board.

Alarm on `RESET_REASON` being a panic or a watchdog: the board restarted by
itself, and nobody would otherwise know.
