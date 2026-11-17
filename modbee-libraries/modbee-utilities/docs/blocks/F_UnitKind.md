# F_UnitKind — Unit table

The unit table behind F_UnitConv: a unit's kind and how to reach its base unit.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eUnit` | `E_Unit` |  | The unit |
| out | `fK` | `LREAL` |  | scale to the base unit (1 when unknown) |
| out | `fO` | `LREAL` |  | offset to the base unit |
| out | *(result)* | `E_UnitKind` | | The unit's kind |

## How it works

The unit table: a unit's kind (0 none or unknown, 1 pressure, 2 flow, 3 volume, 4 temperature, 5 length, 6 percent, 7 current, 8 frequency, 9 power) and how to reach the kind's base unit: base = value * `fK` + `fO`

## Example

| Pin | Wire |
| --- | --- |
| `eUnit` | `E_Unit.Bar` |

**Back to** [the index](../README.md).
