# UT_SIGNAL_SELECT — Redundant sensors (2 or 3 transmitters)

Combines two or three transmitters measuring the same thing into one trusted
value, and alarms when they disagree. Bad sensors are dropped automatically.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In1` / `In2` / `In3` | REAL | 0.0 | The transmitters |
| in | `Good1` / `Good2` / `Good3` | BOOL | TRUE / TRUE / FALSE | Each input's health (e.g. `UT_ANALOG_IN.Good`). Leave `Good3` FALSE when only two are fitted. |
| out | `Out` | REAL | | Selected value |
| out | `Spread` | REAL | | Largest difference between good inputs (0 with fewer than two) |
| out | `Deviation` | BOOL | | `Spread` > `warnSpread` for `warnDelay` |
| out | `Fault` | BOOL | | `Spread` > `faultSpread` for `faultDelay`, or no good input (at once) |
| out | `GoodCount` | INT | | |
| inout | `Data` | UT_SELECT_DATA | | |

## Record `UT_SELECT_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `selectMode` | UT_SELECT_METHOD | UT_SEL_AVERAGE | `UT_SEL_AVERAGE`, `UT_SEL_MIN`, `UT_SEL_MAX`, `UT_SEL_MEDIAN` (2oo3: middle of three, mean of two), `UT_SEL_PRIMARY` (In1, then In2, then In3) |
| `warnSpread` / `faultSpread` | REAL | 1.0 / 2.0 | |
| `warnDelay` / `faultDelay` | TIME | T#5s / T#10s | |
| `filterTime` | TIME | T#0s | Low-pass on `Out` ([UT_FILTER](UT_FILTER.md)), 0 = off |
| `noGoodAction` | UT_AI_FAULT | UT_AI_HOLD | When no input is good: `UT_AI_HOLD` last output, `UT_AI_SUBST` `substValue`, `UT_AI_MIN` / `UT_AI_MAX` lowest / highest input as it is, `UT_AI_PASS` `selectMode` over all inputs ignoring health |
| `substValue` | REAL | 0.0 | For `UT_AI_SUBST` |
| `out`, `spread`, `goodCount`, `deviation`, `fault` | | | Status, as the pins |
| `selected` | INT | | The input used (1..3); 0 = a mean of several, or none |

## How it works
- An input is good when its `GoodN` is TRUE **and** its value is a number (NaN and
  infinity are dropped even with `GoodN` TRUE).
- When an input goes bad it is simply left out, so `Out` moves by no more than the
  spread there was between the inputs (use `filterTime` to smooth even that).
- `Deviation` and the spread `Fault` are [UT_PROTECT](UT_PROTECT.md)s with the
  delays above; they clear as soon as the spread is back below the limit.
- With no good input, `Fault` is on at once and `noGoodAction` gives `Out`
  (MIN, MAX and PASS leave out NaN / infinity; with nothing usable `Out` holds).

## Using it
```iecst
Press(In1 := PT1.Value, In2 := PT2.Value, In3 := PT3.Value,
      Good1 := PT1.Good, Good2 := PT2.Good, Good3 := PT3.Good, Data := PressSelCfg);
```
