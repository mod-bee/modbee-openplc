# F_Scale — Linear scaling

Linear scaling from one range onto another.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | The value |
| in | `fInMin` | `REAL` | `0.0` | Input range, low |
| in | `fInMax` | `REAL` | `65535.0` | Input range, high |
| in | `fOutMin` | `REAL` | `0.0` | Output range, low |
| in | `fOutMax` | `REAL` | `100.0` | either may run backwards |
| in | `bClamp` | `BOOL` | `TRUE` | Stay within the output range |
| out | `bSpanBad` | `BOOL` |  | The input span is zero or not a number |
| out | *(result)* | `REAL` | | The scaled value |

## How it works

Linear scaling: `fIn` from `fInMin`..fInMax onto `fOutMin`..fOutMax (either may run backwards). `bClamp`: stay within the output range. A zero / NaN / infinite span returns `fOutMin` and sets `bSpanBad`; a NaN `fIn` gives NaN. The maths runs in LREAL.

## Example

A raw 0..27648 value to 0..10 bar.

| Pin | Wire |
| --- | --- |
| `fIn` | `fRaw` |
| `fInMin` | 0.0 |
| `fInMax` | 27648.0 |
| `fOutMin` | 0.0 |
| `fOutMax` | 10.0 |
| `bClamp` | TRUE |

**Back to** [the index](../README.md).
