# F_UnitOk — Units can be converted

TRUE when F_UnitConv can convert between two units.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eFromUnit` | `E_Unit` |  | From this unit |
| in | `eToUnit` | `E_Unit` |  | To this unit |
| out | *(result)* | `BOOL` | | TRUE when the pair can be converted |

## How it works

TRUE when [`F_UnitConv`](F_UnitConv.md) can convert `eFromUnit` to `eToUnit`: both units are of the same kind and neither is NONE

## Example

| Pin | Wire |
| --- | --- |
| `eFromUnit` | `E_Unit.Bar` |
| `eToUnit` | `E_Unit.Psi` |

**Back to** [the index](../README.md).
