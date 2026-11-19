# F_Scale — Linear scaling

Linear scaling from one range onto another.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value |
| in | `fInputLow` | `REAL` | `0.0` | input range, low |
| in | `fInputHigh` | `REAL` | `65535.0` | input range, high |
| in | `fOutputLow` | `REAL` | `0.0` | output range, low |
| in | `fOutputHigh` | `REAL` | `100.0` | output range, high (either range may run backwards) |
| in | `bClampToOutput` | `BOOL` | `TRUE` | stay within the output range |
| out | `bInputSpanBad` | `BOOL` |  | the input span is zero or not a number |
| out | *(result)* | `REAL` |  | the scaled value |

## How it works

Linear scaling: `fIn` from `fInputLow`..fInputHigh onto `fOutputLow`..fOutputHigh (either may run backwards). `bClampToOutput`: stay within the output range. A zero / NaN / infinite span returns `fOutputLow` and sets `bInputSpanBad`; a NaN `fIn` gives NaN. The maths runs in LREAL.

## Example

A raw 0..27648 value to 0..10 bar.

| Pin | Wire |
| --- | --- |
| `fIn` | `fRawValue` |
| `fInputLow` | 0.0 |
| `fInputHigh` | 27648.0 |
| `fOutputLow` | 0.0 |
| `fOutputHigh` | 10.0 |
| `bClampToOutput` | TRUE |

**Back to** [the index](../README.md).
