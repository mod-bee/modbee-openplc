# F_CheckInt — INT setting check

The settings-check rule for an INT: why a value is refused, or `None`.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nValue` | `DINT` |  | The value |
| in | `nMin` | `DINT` |  | Lowest allowed |
| in | `nMax` | `DINT` |  | Highest allowed |
| out | *(result)* | `E_UtError` | | `None`, or why the value is refused |

## How it works

The settings-check rule for an INT: why `nValue` is refused (`LimitsBad`, `BelowMin`, `AboveMax`), or `E_UtError.None`.

## Example

| Pin | Wire |
| --- | --- |
| `nValue` | `nNewCount` |
| `nMin` | 0 |
| `nMax` | 100 |

**Back to** [the index](../README.md).
