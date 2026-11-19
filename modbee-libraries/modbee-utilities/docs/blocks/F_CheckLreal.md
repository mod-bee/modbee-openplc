# F_CheckLreal — LREAL setting check

The settings-check rule for an LREAL: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fValue` | `LREAL` |  | the value to check |
| in | `fLowestAllowed` | `LREAL` |  | lowest value allowed |
| in | `fHighestAllowed` | `LREAL` |  | highest value allowed |
| out | *(result)* | `E_UtError` |  | the first problem, None when the value is good |

## How it works

The settings-check rule for an LREAL: why `fValue` is refused (`ValueBad`, `LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `fValue` | `fNewTotal` |
| `fLowestAllowed` | 0.0 |
| `fHighestAllowed` | 1.0E9 |

**Back to** [the index](../README.md).
