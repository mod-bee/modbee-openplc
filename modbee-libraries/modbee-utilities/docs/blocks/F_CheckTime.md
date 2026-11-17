# F_CheckTime — TIME setting check

The settings-check rule for a TIME: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tValue` | `TIME` |  | The value |
| in | `tMin` | `TIME` |  | Lowest allowed |
| in | `tMax` | `TIME` |  | Highest allowed |
| out | *(result)* | `E_UtError` | | `None`, or why the value is refused |

## How it works

The settings-check rule for a TIME: why `tValue` is refused (`LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `tValue` | `tNewDelay` |
| `tMin` | `T#0s` |
| `tMax` | `T#1h` |

**Back to** [the index](../README.md).
