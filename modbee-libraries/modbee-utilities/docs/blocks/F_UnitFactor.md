# F_UnitFactor — Volume unit factor

The factor from one volume unit to another (litre, m3, megalitre, gallon), used by the meters' input and output units.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eFromUnit` | `E_Unit` |  |  |
| in | `eToUnit` | `E_Unit` |  | litre, m3, megalitre, gallon; E_Unit |
| out | `bOk` | `BOOL` |  | The value came from a good channel (or a force) |
| out | *(result)* | `LREAL` | | The function’s value |

## How it works

The factor that turns a quantity in volume unit `eFromUnit` into volume unit `eToUnit` (litre, m3, megalitre, gallon; `E_Unit`), for the meters' input and output units. Both None: factor 1 (no conversion), `bOk` TRUE. One None, or a unit that is not a volume, or two units of different kinds: factor 1, `bOk` FALSE (the caller refuses the setting). Worked in LREAL from [`F_UnitKind`](F_UnitKind.md)'s table.

## Example

| Pin | Wire |
| --- | --- |
| `eFromUnit` | `E_Unit.Litre` |
| `eToUnit` | `E_Unit.M3` |

**Back to** [the index](../README.md).
