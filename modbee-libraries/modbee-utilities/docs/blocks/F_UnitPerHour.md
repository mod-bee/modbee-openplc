# F_UnitPerHour — Volume unit to its flow per hour

The flow unit per hour of a volume unit (litre: L/h, m3: m3/h, megalitre: ML/h, gallon: gal/h): the unit of a meter's rate.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eUnit` | `E_Unit` |  | a volume unit |
| out | *(result)* | `E_Unit` |  | the volume unit's flow unit per hour (None: not a volume unit) |

## How it works

The flow unit of a volume unit per hour (Litre: LitrePerHour, M3: M3PerHour, MegaLitre: MegaLitrePerHour, Gallon: GalPerHour): a meter's rate unit. Any other unit: None.

## Example

| Pin | Wire |
| --- | --- |
| `eUnit` | `E_Unit.M3` |

Gives `E_Unit.M3PerHour`.

**Back to** [the index](../README.md).
