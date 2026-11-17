# F_UnitConv — Unit conversion

Converts a value from one engineering unit to another (bar to psi, L/s to m3/h ...).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value, in unit eFromUnit |
| in | `eFromUnit` | `E_Unit` |  | its unit |
| in | `eToUnit` | `E_Unit` |  | the unit wanted |
| out | *(result)* | `REAL` | | The converted value (unchanged when the units cannot be converted) |

## How it works

Converts `fIn` from `eFromUnit` to `eToUnit`. [`F_UnitOk`](F_UnitOk.md) says whether two units can be converted; [`F_UnitKind`](F_UnitKind.md) is the table both read.

Kinds and units (`E_Unit`):

```
  pressure     Bar, KPa, Psi, MetreH2O (metres of water, 9.80665 kPa)
  flow         LitrePerSec, LitrePerMin, M3PerHour, GalPerMin (US gal/min), M3PerDay, MegaLitrePerDay
  volume       Litre, M3, MegaLitre, Gallon (US gallon)
  temperature  DegC, DegF, Kelvin
  length       Mm, Cm, Metre, Inch, Foot
  percent      Percent        current  Amp
  frequency    Hertz          power    KW
```

Units of different kinds (bar to L/s), or `E_Unit.None` on either side, can't be converted: the value comes back unchanged (never NaN, which would silently defeat every comparison downstream). Check a pair you build at run time with [`F_UnitOk`](F_UnitOk.md). The same unit on both sides also gives `fIn` back unchanged.

Worked in LREAL, so a round trip loses nothing a REAL can show. NaN in gives NaN out; a result beyond the REAL range is infinite.

## Example

A pressure in bar shown in psi.

| Pin | Wire |
| --- | --- |
| `fIn` | `fPressureBar` |
| `eFromUnit` | `E_Unit.Bar` |
| `eToUnit` | `E_Unit.Psi` |

**Back to** [the index](../README.md).
