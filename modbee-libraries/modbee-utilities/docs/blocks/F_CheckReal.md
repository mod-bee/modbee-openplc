# F_CheckReal — REAL setting check

The settings-check rule for a REAL: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fValue` | `REAL` |  | the value to check |
| in | `fLowestAllowed` | `REAL` | `REAL#-3.4E38` | lowest value allowed |
| in | `fHighestAllowed` | `REAL` | `REAL#3.4E38` | highest value allowed |
| in | `bCheckAbove` | `BOOL` |  | also check it is above fMustBeAbove |
| in | `fMustBeAbove` | `REAL` |  | must be above this related setting (bCheckAbove) |
| in | `bCheckBelow` | `BOOL` |  | also check it is below fMustBeBelow |
| in | `fMustBeBelow` | `REAL` |  | must be below this related setting (bCheckBelow) |
| out | *(result)* | `E_UtError` |  | the first problem, None when the value is good |

## How it works

The settings-check rule every block uses for a REAL: why `fValue` is refused, or `E_UtError.None`. Not a number: `ValueBad`; limits not usable: `LimitsBad`; below `fLowestAllowed`: `BelowMin`; above `fHighestAllowed`: `AboveMax`; with `bCheckAbove` not above `fMustBeAbove`: `NotAbove`; with `bCheckBelow` not below `fMustBeBelow`: `NotBelow`.

## Example

| Pin | Wire |
| --- | --- |
| `fValue` | `fNewSetpoint` |
| `fLowestAllowed` | 0.0 |
| `fHighestAllowed` | 10.0 |

**Back to** [the index](../README.md).
