# UT_ANALOG_IN — Analog input (scale, NAMUR NE43, filter, quality, simulate)

Turns a raw analog reading into engineering units. It detects a failed transmitter
or a wire break (NAMUR NE43 bands for 4–20 mA), filters noise, reports quality,
and decides what value to give when the signal is bad.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Raw value (`INT_TO_REAL(%IW0)`), counts or mA |
| out | `Value` | REAL | | Engineering value |
| out | `Percent` | REAL | | 0–100 % of the range |
| out | `Good` | BOOL | | Quality is GOOD (or SIM) |
| out | `Fault` | BOOL | | Signal failed (BAD) |
| out | `Quality` | UT_QUALITY | | GOOD / UNCERTAIN / BAD / SIM |
| inout | `Data` | UT_ANALOG_DATA | | |

## Record `UT_ANALOG_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `signal` | UT_AI_SIGNAL | UT_AI_4_20MA | `UT_AI_4_20MA` (NE43 checks), `UT_AI_0_20MA`, `UT_AI_0_10V`, `UT_AI_CUSTOM` |
| `rawMin` / `rawMax` | REAL | 0.0 / 65535.0 | Raw value at the **bottom and top of the signal** (4 mA and 20 mA for 4–20). For a reading already in mA use 4.0 / 20.0 |
| `engMin` / `engMax` | REAL | 0.0 / 100.0 | Engineering range (`engMin > engMax` works) |
| `filterTime` | TIME | T#0s | First-order low-pass time constant (0 = off) |
| `clamp` | BOOL | TRUE | Clamp `Value` to the engineering range |
| `lowCutoff` | REAL | 0.0 | Values below this read as `engMin` (flow meters near zero). 0 = off |
| `faultDelay` | TIME | T#2s | A failure must last this long to become a `Fault` |
| `faultAction` | UT_AI_FAULT | UT_AI_HOLD | Value while failed: `UT_AI_HOLD` last good, `UT_AI_MIN` engMin, `UT_AI_MAX` engMax, `UT_AI_SUBST` substValue, `UT_AI_PASS` keep the reading |
| `substValue` | REAL | 0.0 | |
| `customLowFail` / `customHighFail` | REAL | -5.0 / 105.0 | `UT_AI_CUSTOM`: fail at or beyond these % of the span |
| `simulate`, `simValue` | BOOL, REAL | FALSE, 0.0 | `simValue` is in engineering units |
| `faultReset` | UT_RESET_MODE | UT_RST_AUTO | AUTO: `Fault` clears when the signal has been good for `recover`; MANUAL: holds until reset |
| `recover` | TIME | T#2s | |
| `cmdReset` | BOOL | | HMI: reset a MANUAL fault (acts once, cleared by the block) |
| `raw`, `value`, `percent`, `quality`, `fault` | | | Status, as the pins (`raw` = `In`) |
| `underRange`, `overRange` | BOOL | | Status: UNCERTAIN, outside the range |
| `failLow`, `failHigh` | BOOL | | Status: in a fail band now |
| `wrnConfig` | BOOL | | Status: zero or invalid span (BAD at once), or a `trimOffset` / `altFactor` / `altOffset` that is not a number |
| `faults` | UDINT | | Count of failure events |
| `trimOffset` | REAL | 0.0 | Field zero trim, engineering units, added to the reading (before the filter and the clamp) |
| `altFactor` | REAL | 1.0 | Second unit: `valueAlt = value × altFactor + altOffset` (bar → psi: 14.5038; °C → °F: 1.8) |
| `altOffset` | REAL | 0.0 | (°C → °F: 32) |
| `valueAlt` | REAL | | Status: the value in the second unit |

**NE43 bands** (`UT_AI_4_20MA`):
| Signal | Meaning | Quality |
| --- | --- | --- |
| ≤ 3.6 mA | fail low (sensor fault / wire break) | BAD |
| 3.6 – 3.8 mA | under range | UNCERTAIN |
| 3.8 – 20.5 mA | measurement (3.8 and 20.5 included) | GOOD |
| 20.5 – 21 mA | over range | UNCERTAIN |
| ≥ 21 mA | fail high | BAD |

The mA thresholds are computed from `rawMin`/`rawMax`, so any card scaling works
(0–27648 for 4–20 mA: fail low at −691.2 counts, fail high at 29376).
`UT_AI_0_20MA` and `UT_AI_0_10V` have no fail bands (a wire break reads as 0): below
0 % or above 100 % is UNCERTAIN. `UT_AI_CUSTOM` is the same plus fail bands at
`customLowFail` / `customHighFail`.

## How it works
- A failure (a fail band, or a NaN / infinite reading) must last `faultDelay`.
  Meanwhile the value is held at the last good one and the quality is UNCERTAIN,
  so a short spike does nothing. After the delay it is a `Fault` (a
  [UT_PROTECT](UT_PROTECT.md) trip with `faultReset` / `recover`), quality BAD, and
  `faultAction` gives the value. Each fault is counted in `faults`.
- The filter is exact at any scan rate and stops while the signal has failed, so
  HOLD gives the last good filtered value.
- A zero or invalid span is BAD at once with `wrnConfig`; it is not counted as a
  signal failure. `Value` and `Percent` are never NaN or infinity.
- Simulate: `Value` = `simValue`, quality SIM, failures are not checked.
- **Zero trim**: `trimOffset` corrects a transmitter that reads a little off in the
  field (e.g. −0.02 m on a level that shows 0.02 m with the well empty). It is added
  to the scaled reading, so the clamp still holds `Value` inside the range.
- **Second unit**: `valueAlt` follows `Value` (also while held or simulated). Unset
  (`altFactor` 1, `altOffset` 0) it equals `Value`. A trim, factor or offset that is
  not a number or infinite sets `wrnConfig` and is not used (trim 0, `valueAlt` 0);
  the quality is not affected.
- **Power cut**: nothing is kept. `faults` starts at 0, a MANUAL fault is forgotten,
  and a signal that is still failed faults again after `faultDelay`.

## Using it
```iecst
LevelCfg.rawMax := 27648.0;  LevelCfg.engMax := 5.0;   (* 0..5 m: the HMI shows the unit *)
Level(In := INT_TO_REAL(%IW0), Data := LevelCfg);
```
