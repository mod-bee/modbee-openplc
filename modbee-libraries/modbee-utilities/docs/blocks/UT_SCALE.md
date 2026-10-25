# UT_SCALE — Linear scaling (function)

Quick scaling with no record. For a full analog input with fault handling, use [UT_ANALOG_IN](UT_ANALOG_IN.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | The value to scale (a raw count, mA, ...) |
| in | `InMin` / `InMax` | REAL | 0.0 / 65535.0 | Input values that give `OutMin` / `OutMax` |
| in | `OutMin` / `OutMax` | REAL | 0.0 / 100.0 | Engineering range. Swap them to invert |
| in | `Clamp` | BOOL | TRUE | TRUE: stay within `OutMin`..`OutMax`. FALSE: the line carries on past the ends |
| returns | | REAL | | Scaled value |

## How it works
A straight line from (`InMin`, `OutMin`) to (`InMax`, `OutMax`). Either range can
run backwards (for example `InMin := 20.0, InMax := 4.0`).

| Case | Result |
| --- | --- |
| `InMin = InMax` (zero span) | `OutMin`, whatever `In` is |
| `OutMin = OutMax` | That value |
| `In` is NaN, or any setting is NaN | NaN (a not-a-number in gives a not-a-number out) |
| `In` is infinite | The end value when clamped; infinity when not |

The maths runs in LREAL, so even ranges near the REAL limits do not overflow.

## Using it
```iecst
Pressure := UT_SCALE(In := INT_TO_REAL(%IW0), InMin := 0.0, InMax := 27648.0,
                     OutMin := 0.0, OutMax := 10.0);   (* 0-10 bar *)
```
