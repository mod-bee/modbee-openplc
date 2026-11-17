# F_CheckReal — REAL setting check

The settings-check rule for a REAL: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fValue` | `REAL` |  | The value |
| in | `fMin` | `REAL` | `REAL#-3.4E38` | Lowest value allowed |
| in | `fMax` | `REAL` | `REAL#3.4E38` | Highest value allowed |
| in | `bUseAbove` | `BOOL` |  | Also check it is above `fAbove` |
| in | `fAbove` | `REAL` |  | must be above this related setting (bUseAbove) |
| in | `bUseBelow` | `BOOL` |  | Also check it is below `fBelow` |
| in | `fBelow` | `REAL` |  | must be below this related setting (bUseBelow) |
| out | *(result)* | `E_UtError` | | `None`, or why the value is refused |

## How it works

The settings-check rule every block uses for a REAL: why `fValue` is refused, or `E_UtError.None`. Not a number: `ValueBad`; limits not usable: `LimitsBad`; below `fMin`: `BelowMin`; above `fMax`: `AboveMax`; with `bUseAbove` not above `fAbove`: `NotAbove`; with `bUseBelow` not below `fBelow`: `NotBelow`.

## Example

| Pin | Wire |
| --- | --- |
| `fValue` | `fNewSetpoint` |
| `fMin` | 0.0 |
| `fMax` | 10.0 |

**Back to** [the index](../README.md).
