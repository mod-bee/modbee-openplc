# F_CheckInt — INT setting check

The settings-check rule for an INT: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nValue` | `DINT` |  | the value to check |
| in | `nLowestAllowed` | `DINT` |  | lowest value allowed |
| in | `nHighestAllowed` | `DINT` |  | highest value allowed |
| out | *(result)* | `E_UtError` |  | the first problem, None when the value is good |

## How it works

The settings-check rule for an INT: why `nValue` is refused (`LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `nValue` | `nNewCount` |
| `nLowestAllowed` | 0 |
| `nHighestAllowed` | 100 |

**Back to** [the index](../README.md).
