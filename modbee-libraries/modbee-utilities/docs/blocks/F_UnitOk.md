# F_UnitOk — Units can be converted

TRUE when F_UnitConv can convert between two units.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eFromUnit` | `E_Unit` |  | the unit it is in |
| in | `eToUnit` | `E_Unit` |  | the unit wanted |
| out | *(result)* | `BOOL` |  | TRUE when F_UnitConv can convert |

## How it works

TRUE when [`F_UnitConv`](F_UnitConv.md) can convert `eFromUnit` to `eToUnit`: both units are of the same kind and neither is None

## Example

| Pin | Wire |
| --- | --- |
| `eFromUnit` | `E_Unit.Bar` |
| `eToUnit` | `E_Unit.Psi` |

**Back to** [the index](../README.md).
