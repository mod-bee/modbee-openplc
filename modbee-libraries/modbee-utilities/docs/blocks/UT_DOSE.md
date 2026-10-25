# UT_DOSE — Dosing and batching (batch, flow-paced, timed)

Doses chemical, fertiliser or product three ways:
- **Batch**: deliver a target quantity, with fast/slow (dribble) stages and in-flight
  compensation (stops early by the amount still flowing after the stop), which can be
  learned automatically. Used for tank filling, recipe ingredients and irrigation shots.
- **Flow-paced (proportional)**: dose in proportion to the water flow. Used for
  fertigation, chlorination, pH correction feed-forward and stock-water additives.
  It drives a dosing pump by speed (%) or by stroke pulses.
- **Timed**: X seconds on every Y minutes while enabled.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Start` | BOOL | FALSE | BATCH: rising edge starts a dose (or resumes a held one). FLOW/TIMED: dose while TRUE |
| in | `Target` | REAL | 0.0 | BATCH quantity (0 = use `Data.target`) |
| in | `Actual` | REAL | 0.0 | BATCH: delivered so far (meter total, `UT_TOTALISER.Batch`, scale weight) |
| in | `Flow` | REAL | 0.0 | FLOW: carrier water flow, per `flowPer` (e.g. m³/h, or L/s with `flowPer := UT_PER_SEC`) |
| in | `Hold` | BOOL | FALSE | Pause while TRUE |
| in | `Abort` | BOOL | FALSE | End the dose (no start while TRUE) |
| in | `Interlock` | BOOL | TRUE | FALSE pauses dosing (e.g. carrier pump not running, so no dosing into a dead line) |
| in | `Reset` | BOOL | FALSE | Rising edge: reset MANUAL protections |
| out | `Fast` | BOOL | | BATCH fast feed / main valve. FLOW/TIMED: dosing pump run |
| out | `Slow` | BOOL | | BATCH slow (dribble) feed. Never on with `Fast`: for a coarse + fine valve pair, open the fine valve on `Fast OR Slow` |
| out | `Rate` | REAL | | FLOW: dosing pump speed %. TIMED: `maxRate` while on |
| out | `RateRaw` | UINT | | `Rate` as 0..65535 for `%QW` |
| out | `PulseOut` | BOOL | | FLOW: stroke pulses for pulse-input dosing pumps |
| out | `Done` | BOOL | | BATCH complete (until the next start) |
| out | `Busy` | BOOL | | A dose is in progress (held or not) |
| out | `Fault` / `Warning` | BOOL | | |
| out | `Remaining` | REAL | | BATCH: target − delivered |
| inout | `Data` | UT_DOSE_DATA | | |

## Record `UT_DOSE_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `saveEvery` | TIME | T#12h | How often `doses` and `dosedTotal` are saved for a power cut (`T#0s` = not kept) |
| `doseMode` | UT_DOSE_MODE | UT_DOSE_BATCH | `UT_DOSE_BATCH` (0) · `UT_DOSE_FLOW` · `UT_DOSE_TIMED`. A change takes effect when idle |
| **Batch** | | | |
| `target` | REAL | 0.0 | Used when the `Target` pin is 0. No target: the start is refused with a `configBad` warning |
| `slowAt` | REAL | 0.0 | Change to slow when this much remains (0 = no slow stage) |
| `preact` | REAL | 0.0 | In-flight compensation: stop this much early (not a number = 0). The preact in use (`preactActive`) is never more than half the batch's target |
| `learnPreact` | BOOL | FALSE | Correct the preact in use (`preactActive`) by half of each dose's error. Doses more than 25 % off are not learned from; it stays between 0 and half the target. Changing `preact` restarts the learning from it |
| `tolerance` | REAL | 0.0 | ± allowed; outside it → `outOfTolerance` (0 = not checked) |
| `settleTime` | TIME | T#2s | Wait after stopping before the result is taken |
| `actualIsTotal` | BOOL | FALSE | `Actual` is a running total: the dose is `Actual` minus its value at the start |
| **Flow-paced** | | | |
| `flowPer` | UT_RATE_UNIT | UT_PER_HOUR | The time unit of `Flow`, `pumpCapacity` and `required`: `UT_PER_SEC`, `UT_PER_MIN`, `UT_PER_HOUR`, `UT_PER_DAY` |
| `ratio` | REAL | 0.0 | Dose units per flow unit (e.g. L of product per m³ of water). Required rate = `Flow` × `ratio` per `flowPer` |
| `pumpCapacity` | REAL | 0.0 | Dosing pump output at 100 %, units per `flowPer` (e.g. L/h). `Rate` = required / capacity. 0 with `pulseVolume` set: a pulse pump, dosed as required |
| `pulseVolume` | REAL | 0.0 | Dose per stroke pulse (`PulseOut`; 0 = not used) |
| `pulseWidth` | TIME | T#200ms | Pulse on time, and the least off time (each at least one scan) |
| `minFlow` | REAL | 0.0 | No dosing below this carrier flow |
| `maxRate` | REAL | 100.0 | % cap (below 0 or not a number = 0) |
| **Timed** | | | |
| `onTime` / `offTime` | TIME | T#10s / T#5m | Starts with the on part. A pause stops the clock. `offTime` 0 = always on |
| **Protections** | | | |
| `noFlow` (bit 1) | UT_PROTECTION | TRIP · 30 s · RETRY | BATCH: `Actual` not rising while feeding. TRIP holds the dose (quantity kept); RETRY feeds again after `recover` |
| `maxTime` (bit 2) | UT_PROTECTION | OFF | BATCH: whole dose (holds included) too long (`delay` = limit). TRIP ends the dose |
| `overCapacity` (bit 3) | UT_PROTECTION | WARN · AUTO | FLOW: the required rate is above the pump's capacity at `maxRate`. TRIP stops dosing until it clears |
| `outOfTolerance` (bit 4) | UT_PROTECTION | WARN · AUTO | BATCH result outside `tolerance`; shown until the next start or a reset. TRIP blocks the next start until it clears |
| `retryWindow` | TIME | T#1h | RETRY counts |
| **HMI** | | | |
| `cmdStart` | BOOL | | BATCH: start or resume. FLOW/TIMED: run until `Abort` / `cmdAbort`. Acts once, on its rising edge: one held TRUE doses one batch, never a second |
| `cmdAbort` | BOOL | | End the dose (wins over `cmdStart` in the same scan) |
| `cmdHold` | BOOL | | Hold until the next start |
| `cmdReset` | BOOL | | Reset MANUAL protections. After a MANUAL reset a held batch needs a start to carry on |

Every `cmdXxx` acts once, on its rising edge, and is cleared by the block. A SCADA
master that rewrites `cmdStart` every poll would start a new batch after each one
finishes (an overdose): put [UT_CMD](UT_CMD.md) in front of it.
| **Status** | | | |
| `phase` | UT_DOSE_PHASE | | `UT_DP_IDLE`, `UT_DP_FAST`, `UT_DP_SLOW`, `UT_DP_SETTLE`, `UT_DP_HELD`, `UT_DP_DONE`, `UT_DP_ABORTED`, `UT_DP_DOSING`, `UT_DP_WAITING` (FLOW below `minFlow` or paused, TIMED off part) |
| `modeActive`, `targetActive` | | | The dose in progress |
| `delivered`, `lastDelivered`, `lastError` | REAL | | This dose; the last one; last batch delivered − target |
| `preactActive` | REAL | | Preact in use (learned) |
| `required`, `rate` | REAL | | FLOW: product rate needed (units per `flowPer`); Rate % |
| `pulses` | UDINT | | Stroke pulses given |
| `doses` | UDINT | | Batch doses completed (aborted ones are not counted) |
| `dosedTotal` | REAL | | Everything dosed (batch, flow and timed), kept as of the last save |
| `held` | BOOL | | Paused (Hold, `cmdHold`, Interlock, a trip) |
| `configBad`, `fault`, `warning`, `faultCode : DWORD` | | | Bit 0 = `configBad` |
| `statusCode` | UT_STATUS | | What it is doing, or what holds it back (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | The fault, warning or setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | `statusCode` and `faultId` in words, e.g. `Dosing fast`. The quantities are in `delivered` / `targetActive`, the speed in `rate` |
| `doseTime` | TIME | | How long the dose in progress has run, holds included (the last dose's once it ends) |
| `timeLeft` | TIME | | The countdown the status shows: TIMED on / off time left, the settle time left, the `maxTime` left while a batch doses (`maxTime` in use), a fault's recover / retry wait |
| `stopReason` | UT_STOP | | Why the last dose ended (see below; `UT_STOP_NONE` = none since power-up), kept until the next one ends |
| `lastFaultCode` | DWORD | | The `faultCode` bits of the last trip, kept after it clears, until the next trip |
| `lastFault` | UT_FAULT | | The last trip, e.g. `UT_F_DOSE_NO_FLOW`, kept the same way |
| `trips` | UDINT | | Trips since power-up (not kept over a power cut) |

**Why the dose ended** (`stopReason`, a `UT_STOP`; an HMI reads its number):
| `stopReason` | When |
| --- | --- |
| `UT_STOP_DEMAND_ENDED` | FLOW / TIMED: `Start` dropped |
| `UT_STOP_MAX_RUN` | BATCH: `maxTime` (TRIP) ended it |
| `UT_STOP_DONE` | BATCH: the target was delivered and the result taken |
| `UT_STOP_ABORTED` | The `Abort` pin |
| `UT_STOP_ABORT_CMD` | `cmdAbort` |

An interlock, `Hold` or a trip (no flow) pauses a dose; they do not end it.

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes. The one main
thing, in the order config, fault, held, warning, normal, idle. The quantities are in
`delivered` and `targetActive`, the pump speed in `rate`, the countdown in `timeLeft`.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_IDLE` | | `Idle` | No dose |
| `UT_ST_DONE` | | `Idle: done` | After the last batch completed |
| `UT_ST_ABORTED` | | `Idle: aborted` | After the last batch was aborted |
| `UT_ST_DOSE_FAST` | | `Dosing fast` | BATCH fast stage |
| `UT_ST_DOSE_SLOW` | | `Dosing slow` | BATCH slow (dribble) stage |
| `UT_ST_SETTLING` | | `Settling` | BATCH stopped, waiting `settleTime` for the result |
| `UT_ST_DOSE_FLOW` | | `Dosing: flow-paced` | FLOW dosing (`rate`; 0 with a pulse pump) |
| `UT_ST_DOSE_TIMED` | | `Dosing: timed` | TIMED on part |
| `UT_ST_DOSE_NEXT` | | `Timed: waiting next dose` | TIMED off part |
| `UT_ST_INTERLOCK` | | `Blocked: interlock` | `Interlock` FALSE during a dose |
| `UT_ST_PAUSED_HOLD` | | `Paused: Hold input` | `Hold` during a dose |
| `UT_ST_PAUSED_START` | | `Paused: press Start` | `cmdHold`, or a MANUAL reset, during a dose |
| `UT_ST_LOW_CARRIER` | | `Waiting: carrier flow low` | FLOW: `Flow` 0 or below `minFlow` |
| `UT_ST_WARNING` | `UT_F_ACTUAL_NAN` | `Warning: Actual not a number` | BATCH: the last value is held |
| `UT_ST_WARNING` | `UT_F_FLOW_NAN` | `Warning: Flow not a number` | FLOW: not dosing |
| `UT_ST_WARN_SETTING` | `UT_F_SETTING` | `Setting: a setting` | See [Bad settings](#bad-settings): a safe value is used |
| `UT_ST_WARNING` | the protection | `Warning: no dose flow` | A protection set to WARN |
| `UT_ST_FAULT` | the protection | `Fault: no dose flow` | A protection set to TRIP with AUTO reset (`timeLeft`: the recover once the cause has gone) |
| `UT_ST_FAULT_RESET` | the protection | `Latched: no dose flow` | TRIP with MANUAL reset |
| `UT_ST_FAULT_RETRY` | the protection | `Retrying: no dose flow` | TRIP with RETRY (the protection's `retries`; `timeLeft`) |
| `UT_ST_FAULT_LOCKED` | the protection | `Locked: no dose flow` | RETRY, `maxRetries` used up: reset needed |
| `UT_ST_CONFIG` | `UT_F_NO_TARGET` | `Config: no target set` | BATCH start refused: no target |
| `UT_ST_CONFIG` | `UT_F_NO_CAPACITY` | `Config: no capacity / ratio` | FLOW started without a capacity or pulse volume, or a bad ratio |
| `UT_ST_CONFIG` | `UT_F_TIMED_ON_OFF` | `Config: timed on / off time` | TIMED started with a negative time |
| `UT_ST_CONFIG` | `UT_F_DOSE_MODE` | `Config: dose mode` | `doseMode` not one of the three |

The protection is `UT_F_DOSE_NO_FLOW` (no dose flow), `UT_F_DOSE_TOO_LONG` (dose too long),
`UT_F_PUMP_TOO_SMALL` (pump too small) or `UT_F_TOLERANCE` (out of tolerance), the first
tripped in that order.

## Power cut
Kept: `doses` and `dosedTotal`, as of the last save (`saveEvery`). Not kept: a dose
in progress and the learned preact. After a power-up a **batch** doser is **idle and nothing
starts by itself**, even with `Start` still on: a new `Start` edge (or `cmdStart`)
starts a new dose of the full target; a batch is never resumed. The preact in use
starts again from the `preact` setting. **FLOW and TIMED are different:** `Start` is a
level (dose while TRUE), so if `Start` is still on at power-up the flow-paced or timed
dosing carries on at once (from the start of a fresh on-time). A `cmdStart` latch is not
kept: after a power cut it needs `Start` or a new `cmdStart`.

## Bad settings
- **Nothing doses:** an unknown `doseMode` (taken only when idle); TIMED with a negative
  `onTime` or `offTime` (a negative off time would never stop). `configBad`, status `UT_ST_CONFIG`.
- **Warning, safe values** (`configBad`, bit 0, status `Setting: a setting`): `preact` negative or not a
  number (0: stops at the target); `slowAt`, `tolerance`, `ratio`, `pumpCapacity`,
  `pulseVolume`, `minFlow` negative or not a number; `maxRate` outside 0..100 or not a
  number (clamped, NaN = 0); a negative `settleTime`, `pulseWidth` (0) or `saveEvery`
  (nothing kept); a negative `retryWindow` (the default 1 h); an unknown `flowPer` (per
  hour).
- A `pulseVolume` so small that more than a million stroke pulses would be owed: the
  extra pulses are dropped (the pulse count never overflows).
