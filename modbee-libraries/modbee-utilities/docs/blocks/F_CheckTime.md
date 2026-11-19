# F_CheckTime — TIME setting check

The settings-check rule for a TIME: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tValue` | `TIME` |  | the value to check |
| in | `tLowestAllowed` | `TIME` |  | lowest value allowed |
| in | `tHighestAllowed` | `TIME` |  | highest value allowed |
| out | *(result)* | `E_UtError` |  | the first problem, None when the value is good |

## How it works

The settings-check rule for a TIME: why `tValue` is refused (`LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `tValue` | `tNewDelay` |
| `tLowestAllowed` | `T#0s` |
| `tHighestAllowed` | `T#1h` |

**Back to** [the index](../README.md).
