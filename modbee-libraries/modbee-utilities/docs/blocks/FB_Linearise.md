# FB_Linearise — Lookup table / curve

A lookup table / curve: tank strapping tables, non-linear sensors, weirs and flumes, pump curves.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | value to look up |
| in | `bInputGood` | `BOOL` | `TRUE` | its health; FALSE: fOut held |
| in | `nPointsUsed` | `INT` |  | use only the first N points (0 = whole array) |
| in | `bExtrapolate` | `BOOL` |  | beyond the ends: FALSE = end value, TRUE = extend the end segment |
| in-out | `aInputPoints` | `ARRAY[*] OF REAL` |  | input points, increasing |
| in-out | `aOutputPoints` | `ARRAY[*] OF REAL` |  | output points |
| out | `fOut` | `REAL` |  | interpolated result |
| out | `bGood` | `BOOL` |  | bInputGood, bTableGood, fIn a number |
| out | `fSlope` | `REAL` |  | dY / dX of the segment in use |
| out | `bOutOfRange` | `BOOL` |  | fIn is beyond the first or last point |
| out | `bTableGood` | `BOOL` |  | table valid: aInputPoints strictly increasing, all numbers, lengths agree |
| out | `bInputNotANumber` | `BOOL` |  | fIn is NaN or infinite: fOut is held |

## How it works

Lookup table / curve.

Converts `fIn` using a table of points (`aInputPoints`[i], `aOutputPoints`[i]) with straight lines between them: tank strapping tables, non-linear sensors, weirs and flumes, valve characteristics, pump curves.

`aInputPoints` and `aOutputPoints` are arrays of any size and any lower bound (ARRAY[1..20], ARRAY[0..9] ...). Point 1 is the first element of each, so `aInputPoints` and `aOutputPoints` may even have different lower bounds. `nPointsUsed` = N uses only the first N points; 0 uses the whole arrays, which must then be the same length.

The table is checked every scan (an HMI may edit it): `aInputPoints` must be strictly increasing, and every `aInputPoints` and `aOutputPoints` a number. A table that fails holds `fOut` and `bOutOfRange` where they were and sets `bTableGood` FALSE.

Beyond the first or last point: `bExtrapolate` FALSE gives that end's `aOutputPoints`, TRUE carries the end segment on. A one-point table gives its `aOutputPoints` everywhere.

A NaN or infinite `fIn` holds `fOut` and `bOutOfRange` and sets `bInputNotANumber`; `bInputGood` FALSE holds them too. `bGood`: `bInputGood`, `bTableGood` and `fIn` a number. `fSlope` is `dY` / `dX` of the segment in use (the end segment beyond the ends; 0 for a one-point table): a vessel's TABLE area.

## Example

A tank strapping table: level (m) to volume (m3).

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTankLevel.fValue` |
| `aInputPoints` | `aLevels` |
| `aOutputPoints` | `aVolumes` |
| `fOut` | the volume |

**Back to** [the index](../README.md).
