# F_UnitFactor — Volume unit factor

The factor from one volume unit to another (litre, m3, megalitre, gallon), used by the meters' input and output units.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eFromUnit` | `E_Unit` |  | the unit it is in |
| in | `eToUnit` | `E_Unit` |  | the unit wanted |
| out | `bUnitsMatch` | `BOOL` |  | both units are known and of the same kind |
| out | *(result)* | `LREAL` |  | the factor from eFromUnit to eToUnit |

## How it works

The factor that turns a quantity in volume unit `eFromUnit` into volume unit `eToUnit` (litre, m3, megalitre, gallon; `E_Unit`), for the meters' input and output units. Both None: factor 1 (no conversion), `bUnitsMatch` TRUE. One None, or a unit that is not a volume, or two units of different kinds: factor 1, `bUnitsMatch` FALSE (the caller refuses the setting). Worked in LREAL from [`F_UnitKind`](F_UnitKind.md)'s table.

## Example

| Pin | Wire |
| --- | --- |
| `eFromUnit` | `E_Unit.Litre` |
| `eToUnit` | `E_Unit.M3` |

**Back to** [the index](../README.md).
