# FB_Filter — Smoothing filter

A smoothing filter: low-pass, moving average or block average.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | noisy value |
| in | `bInGood` | `BOOL` | `TRUE` | FALSE: fOut held, the time not counted |
| in | `tTc` | `TIME` | `T#1s` | time constant (low-pass) or window length (averages) |
| in | `eMode` | `E_FilterMode` |  | E_FilterMode.Lowpass, E_FilterMode.Average, E_FilterMode.BlockAvg |
| in | `bReset` | `BOOL` |  | fOut jumps straight to fIn |
| out | `bGood` | `BOOL` |  | bInGood, a value taken, fIn a number |
| out | `fOut` | `REAL` |  | The filtered value |
| out | `bBadInput` | `BOOL` |  | fIn is NaN or infinite: fOut is held |

## Lists

- `E_FilterMode`: `Lowpass`, `Average`, `BlockAvg` (default `E_FilterMode.Lowpass`)

## How it works

Smoothing filter.

```
  eMode  E_FilterMode.Lowpass    first order low-pass: after a step, fOut has moved
                             63 % of the way after tTc, 95 % after 3 x tTc
        E_FilterMode.Average    moving average of the last tTc, updated every scan:
                             the window being filled plus the share of the
                             last whole window still inside tTc (two sums,
                             no history)
        E_FilterMode.BlockAvg  average of each tTc window, updated once at the
                             end of each window
```

The first scan, `bReset`, and `tTc` = 0 (or less than 1 ms) pass `fIn` straight through. Changing `eMode` or `tTc` carries on from the present `fOut` without a jump.

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to the next scan, so nothing drifts and the result is the same at any task interval.

A value that is not a number (NaN, infinity), or `bInGood` FALSE, is ignored: `fOut` holds, `bBadInput` is set (a number only), and the time it lasted does not count. `bGood`: a value has been taken and the input is usable now. Filtering carries on from the held value when the input is good again.

## Example

Smooth a pressure reading over 5 s.

| Pin | Wire |
| --- | --- |
| `fIn` | `fPressure` |
| `tTc` | `T#5s` |
| `fOut` | the smooth value |

**Back to** [the index](../README.md).
