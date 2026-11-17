# F_CheckLreal — LREAL setting check

The settings-check rule for an LREAL: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fValue` | `LREAL` |  | The value |
| in | `fMin` | `LREAL` |  | Lowest value allowed |
| in | `fMax` | `LREAL` |  | Highest value allowed |
| out | *(result)* | `E_UtError` | | `None`, or why the value is refused |

## How it works

The settings-check rule for an LREAL: why `fValue` is refused (`ValueBad`, `LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `fValue` | `fNewTotal` |
| `fMin` | 0.0 |
| `fMax` | 1.0E9 |

**Back to** [the index](../README.md).
