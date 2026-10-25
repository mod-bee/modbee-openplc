# UT_COUNTDOWN — Remaining time (function)

Works with any timer: the standard `TON`/`TOF`/`TP`, or `UT_TONR`. Typical use is
showing "time left" on an HMI.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `PT` | TIME | T#0s | Timer preset (`MyTon.PT`) |
| in | `ET` | TIME | T#0s | Timer elapsed (`MyTon.ET`) |
| returns | | TIME | | `PT − ET`, never negative |

```iecst
Remaining := UT_COUNTDOWN(PT := Delay.PT, ET := Delay.ET);
```

## How it works
- `ET` at or past `PT` gives 0.
- A `PT` of 0 or less gives 0. A negative `ET` counts as 0, so the result is never more than `PT`.
- Show it on an HMI with [UT_TIME_SPLIT](UT_TIME_SPLIT.md) for days, hours, minutes and seconds.
