# UT_TOTALISER — Totals from any source (flow, energy, production, runtime)

Accumulates a quantity from whatever the field gives you. Choose the **method** for
the meter you have; everything else (periods, interval records, batch target, rate
output, units, retention) works the same for every method.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Value` | REAL | 0.0 | Flow rate (RATE), meter register (REGISTER/CHANGE), sampled value (SAMPLE/SNAPSHOT). The editor wants it wired: with PULSE or COUNT, wire 0.0 |
| in | `Pulse` | BOOL | FALSE | Pulse input (PULSE method) |
| in | `Count` | UDINT | 0 | The counter's reading (COUNT method), e.g. a hardware library's pulse count |
| in | `Active` | BOOL | TRUE | Only totalise while TRUE (e.g. pump running). In RUNTIME mode, it's the running signal |
| in | `Clock` | DT | DT#1970-01-01-00:00:00 | Local real-time clock for the hour and day totals and the interval end times (leave unwired to switch the hour and day totals off) |
| in | `Rollover` | BOOL | FALSE | Rising edge: close the user period (shift change, batch end). SNAPSHOT: take a reading |
| in | `ResetBatch` | BOOL | FALSE | Rising edge: zero the batch total |
| out | `Total` | REAL | | Lifetime total |
| out | `Batch` | REAL | | Resettable batch/trip total |
| out | `Rate` | REAL | | Measured rate in `outUnit` per `rateUnit` (from pulses, counts or register changes too) |
| out | `BatchDone` | BOOL | | `Batch` ≥ `batchTarget` |
| out | `IntervalDone` | BOOL | | TRUE for one scan when an interval record has just been written |
| inout | `Data` | UT_TOTAL_DATA | | |

## Which meter, which method
| Meter | `countMethod` | How to wire it |
| --- | --- | --- |
| Pulse meter counted by the PLC scan (reed switch, pulse output) | `UT_TM_PULSE` | Pulse signal to `Pulse`. Set `pulseValue` (quantity per pulse) and `inUnit`. Up to one pulse per two scans. |
| Fast pulse meter counted outside the scan (the hardware library's pulse count) | `UT_TM_COUNT` | The hardware library's count (UDINT) to `Count`. Set `pulseValue` and `inUnit`; `rolloverAt` only if the counter wraps below 4 294 967 296 (a 16-bit counter: 65536); `maxStep` (counts). |
| 4–20 mA or RS485 flow-rate transmitter | `UT_TM_RATE` | The scaled rate to `Value`. Set `rateUnit` (per second, minute, hour or day), `inUnit` and `lowCutoff`. |
| RS485 meter's own volume register | `UT_TM_REGISTER` | The register to `Value`. Set `inUnit`, `rolloverAt` (if the register wraps) and `maxStep`. |

## Methods — `countMethod : UT_TOTAL_METHOD`
| Value | Use for | How it counts |
| --- | --- | --- |
| `UT_TM_RATE` (0, default) | 4–20 mA flow meter, power transducer | Integrates `Value` over real time, in `rateUnit`. Values below `lowCutoff` (and negative ones) count as 0. |
| `UT_TM_PULSE` | Pulse/reed-switch meters, kWh pulse outputs, product counters | Each rising edge adds `pulseValue` (K-factor). Rate from the pulse period. |
| `UT_TM_REGISTER` | A meter's own running total read over Modbus/MQTT (m³, kWh) | Adds each **increase** of `Value`. Handles register rollover at `rolloverAt` (a wrap of less than half the range). A drop (meter reset, swap, comms glitch reading 0) counts nothing, and when the value comes back above where it was only the part above it counts. Steps bigger than `maxStep` are rejected. Each rejected step or drop counts in `rejectedSteps`. |
| `UT_TM_CHANGE` | Any value whose change you want to total in both directions (tank volume in/out, stock level) | Adds rises to `totalIn` and falls to `totalOut`, once the value has moved `deadband` from the last counted value. Total, batch, periods and `Rate` add the rises, or the falls with `changeCountFalls` |
| `UT_TM_RUNTIME` | No meter: estimate from run time | While `Active`, adds `nominalRate` × time (e.g. pump rated 12 m³/h). |
| `UT_TM_SAMPLE` | Slow or noisy signals, or fixed-interval accounting | Every `sampleTime`, adds `Value × sampleTime` (rate) or `Value` (if `sampleAsQuantity`) |
| `UT_TM_SNAPSHOT` | Readings to log at fixed times (meter reads, levels) | Every `sampleTime` (or `Rollover` edge), stores `Value` as `snapshot`/`prevSnapshot` and their difference as `period`. Nothing is totalised |
| `UT_TM_COUNT` (7) | A pulse count kept outside the scan, on `Count` | Each count adds `pulseValue`. The step is worked out in UDINT, so every count is exact at any reading, and the 32-bit wrap (4 294 967 295 → 0) is counted exactly. `rolloverAt` sets a lower wrap. A drop of less than half the range is a wrap; any other drop means the counter restarted (for example its hardware rebooted): it counted up again from 0, so `Count` itself is counted, not a huge step. Steps, and restarts, bigger than `maxStep` counts are rejected and counted in `rejectedSteps`. The first reading is the starting point. `Value` is not used |

COUNT or REGISTER? A counter that starts again from 0 when its device restarts is
COUNT. A meter that keeps its own total through a power cut is REGISTER (a drop
there is a glitch or a meter swap, never a restart from 0).

## Units
`inUnit` is the unit of `pulseValue`, of the register or count quantity, of the
rate on `Value` and of `nominalRate`. `outUnit` is the unit of every total, of the
interval record and of `Rate`. When both are set, every addition and the rate are
converted; when either is `UT_VOL_NONE` (the default) nothing is converted.

| `UT_VOL_UNIT` | Unit |
| --- | --- |
| `UT_VOL_NONE` (0, default) | No conversion |
| `UT_VOL_L` | litre |
| `UT_VOL_M3` | cubic metre (1 000 L) |
| `UT_VOL_ML` | **megalitre** (1 000 000 L), not millilitre |

Example: a meter giving 1 pulse per 10 L, totals in m³: `pulseValue := 10.0`,
`inUnit := UT_VOL_L`, `outUnit := UT_VOL_M3`. Each pulse adds 0.01 m³.
A 4–20 mA transmitter scaled in L/s, totals in m³: `rateUnit := UT_PER_SEC`,
`inUnit := UT_VOL_L`, `outUnit := UT_VOL_M3`; `Rate` is then in m³/s.
`scale` still multiplies on top (meter calibration). `lowCutoff`, `maxStep` and
`rolloverAt` stay in the units of `Value`.

## Interval records
Every `interval` (default 15 minutes) the block writes one record for the IoT
platform and sets `IntervalDone` for one scan:

| Field | Type | Meaning |
| --- | --- | --- |
| `intervalVolume` | REAL | The quantity counted in that interval, in `outUnit` |
| `intervalEnd` | DT | When the interval ended (from `Clock`) |
| `intervalTotal` | REAL | The lifetime total at that moment |
| `intervalSeq` | UDINT | +1 every interval: a gap in the numbers is a missed record |

The fields hold until the next record; only `IntervalDone` is one scan.
- **With `Clock`**: intervals end on whole multiples of `interval` since midnight
  (15 min: :00, :15, :30, :45), and `intervalEnd` is that boundary time. The first
  interval after power-up is a part interval (it starts at power-up). A clock jump
  forward closes one record covering the gap; a clock set back closes nothing.
- **Without `Clock`**: intervals are counted from power-up, every `interval` of
  running time, and `intervalEnd` stays at DT#1970-01-01-00:00:00. Let the platform
  time-stamp the records.
- `interval := T#0s` switches the records off. Changing `interval` starts again.
- The records are **not** kept over a power cut: `intervalSeq` starts at 0 again.
  The platform stores the history and works out monthly figures.

## Record `UT_TOTAL_DATA`

### Settings
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `saveEvery` | TIME | T#12h | How often the totals are saved for a power cut (`T#0s` = not kept). Resets, presets, user rollovers and the end of a run (`Running` falls, once per stop) are saved at once |
| `countMethod` | UT_TOTAL_METHOD | UT_TM_RATE | How to count (`method` is a reserved word) |
| `rateUnit` | UT_RATE_UNIT | UT_PER_HOUR | Time unit of `Value` (RATE/SAMPLE), of `nominalRate` and of `Rate` |
| `inUnit` | UT_VOL_UNIT | UT_VOL_NONE | Unit of `pulseValue`, the register or count and the rate on `Value` (see [Units](#units)) |
| `outUnit` | UT_VOL_UNIT | UT_VOL_NONE | Unit of every total and of `Rate` |
| `pulseValue` | REAL | 1.0 | PULSE / COUNT: quantity per pulse, in `inUnit` |
| `nominalRate` | REAL | 0.0 | RUNTIME method |
| `lowCutoff` | REAL | 0.0 | RATE: ignore values below this (meter noise at zero flow), in the units of `Value`; `Rate` below it shows 0 |
| `rolloverAt` | REAL | 0.0 | REGISTER: the register wraps at this value (0 = never). COUNT: the counter wraps at this value, 2 .. 4 294 967 296 (0 = the full 32 bits) |
| `maxStep` | REAL | 0.0 | REGISTER / COUNT: reject single steps bigger than this, in the units of `Value` (COUNT: counts) (0 = off) |
| `deadband` | REAL | 0.0 | CHANGE: ignore smaller changes |
| `changeCountFalls` | BOOL | FALSE | CHANGE: the total, batch, periods (today, yesterday…), `BatchDone` and `Rate` count the **falls** instead of the rises. A sump's volume with `Active := pump running` then totals the pumped volume (net of any inflow during the run) |
| `sampleTime` | TIME | T#1m | SAMPLE / SNAPSHOT |
| `sampleAsQuantity` | BOOL | FALSE | SAMPLE: each sample is a quantity, not a rate |
| `batchTarget` | REAL | 0.0 | `BatchDone` threshold (0 = off) |
| `scale` | REAL | 1.0 | Multiplier on every addition (meter calibration) |
| `interval` | TIME | T#15m | Interval records (`T#0s` = off) |

### Commands
- HMI: `cmdResetBatch`, `cmdRollover`.
- **Admin or technician only, through the platform; never on an operator HMI:**
  `cmdResetTotal` (resets `total`, `totalIn`, `totalOut`; needs `cmdConfirm` in the
  same write), `cmdConfirm`, `cmdPreset` + `presetTotal` (0 to 1E12; anything else
  is ignored). The block cannot check who wrote them: keep them out of operator
  screens.

Each command acts once and is cleared.

### Status
| Field | Type | Meaning |
| --- | --- | --- |
| `total`, `batch`, `rate` | REAL | |
| `totalIn` / `totalOut` | REAL | CHANGE method |
| `period` / `prevPeriod` | REAL | User period (Rollover). SNAPSHOT: the last two differences |
| `thisHour` / `lastHour` | REAL | With `Clock` wired |
| `today` / `yesterday` | REAL | With `Clock` wired |
| `snapshot` / `prevSnapshot` | REAL | SNAPSHOT method |
| `intervalVolume`, `intervalEnd`, `intervalTotal`, `intervalSeq` | REAL, DT, REAL, UDINT | The last [interval record](#interval-records) |
| `pulses`, `rejectedSteps` | UDINT | Diagnostics (not kept over a power cut) |
| `wrnRegisterJump` | BOOL | A register or count step was rejected, or the register fell (until the next good step) |
| `wrnPulseTooFast` | BOOL | Pulses at the scan-rate limit (held 5 s) |
| `wrnBadValue` | BOOL | `Value` is not a number or infinite (not checked for PULSE, RUNTIME, COUNT), or would add over 1E9 in one scan: ignored |
| `wrnConfig` | BOOL | A setting is invalid: an unknown method or unit; `pulseValue` not above 0; `nominalRate`, `lowCutoff`, `rolloverAt`, `maxStep`, `deadband`, `batchTarget` or `scale` negative, not a number or infinite; COUNT `rolloverAt` outside 2 .. 4 294 967 296; a negative `sampleTime`, `interval` or `saveEvery`. Nothing else changes (the totals stay safe: a NaN addition is ignored) |

## Compliance metering
- Counting in the PLC (PULSE or COUNT): the total lives in the PLC, so set a short
  `saveEvery`, for example `T#1m`. A power cut then loses at most that much counting.
- REGISTER reads the meter's own total, so the meter keeps counting while the PLC is
  off and nothing is lost.
- The platform logs the interval records.
- NZ regulations require 15-minute records, sent daily, for takes of 5 L/s or more.

## Notes
- **Power cut**: kept as of the last save (`saveEvery`; resets, presets and user
  rollovers at once): every total and period total in the status table, with the
  hour and day they belong to, the snapshots and the register or count reading, so
  nothing is counted twice. After the restart REGISTER counts what the meter recorded
  while the PLC was off; COUNT counts a counter that restarted from 0 (or kept
  counting). Not kept: the interval records, `pulses` and `rejectedSteps` (start at
  0), the warnings.
- Totals are kept in millionths of a unit in 64-bit integers, plus the part of a
  millionth left over, so they stay exact on every board (LREAL is only 32-bit on some small boards).
  A total of 10 000 000 still counts single units.
- Pulses are seen once per scan: the maximum is one pulse per two scans (half the
  task rate, e.g. 50 Hz at 10 ms). `wrnPulseTooFast` is raised at that limit. Count
  faster meters outside the scan and use COUNT.
- COUNT: the count is a UDINT on `Count`, exact at any reading (a REAL would lose
  single counts past 16 777 216). Leave `rolloverAt` at 0 for a 32-bit counter.
- A counter that restarts close to `rolloverAt` looks like a wrap. `maxStep` limits
  what such a step can add.
- Hour and day totals follow the clock's hour and day changes, also after a power
  cut that spanned midnight or a month end (the day before the cut becomes
  `yesterday`). A jump of more than one hour or day leaves the skipped period at 0;
  a clock set back closes nothing and never makes a negative period. Wire a
  **local** clock: the runtime's `CURRENT_DT` is UTC.
- After a restart, REGISTER counts what the meter recorded while the PLC was off,
  also when the reading is 0 for a while (comms down) before or after the cut.
