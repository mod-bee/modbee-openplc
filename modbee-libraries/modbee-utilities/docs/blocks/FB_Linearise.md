# FB_Linearise — Lookup table / curve

A lookup table / curve: tank strapping tables, non-linear sensors, weirs and flumes, pump curves.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | value to look up |
| in | `bInGood` | `BOOL` | `TRUE` | its health; FALSE: fOut held |
| in | `nPoints` | `INT` |  | use only the first N points (0 = whole array) |
| in | `bExtrapolate` | `BOOL` |  | beyond the ends: FALSE = end value, TRUE = extend the end segment |
| in-out | `aX` | `ARRAY[*] OF REAL` |  | input points, increasing |
| in-out | `aY` | `ARRAY[*] OF REAL` |  | output points |
| out | `bGood` | `BOOL` |  | bInGood, bTableOk, fIn a number |
| out | `fOut` | `REAL` |  | interpolated result |
| out | `fSlope` | `REAL` |  | dY / dX of the segment in use |
| out | `bOutOfRange` | `BOOL` |  | fIn is beyond the first or last point |
| out | `bTableOk` | `BOOL` |  | table valid: aX strictly increasing, all numbers, lengths agree |
| out | `bBadInput` | `BOOL` |  | fIn is NaN or infinite: fOut is held |

## How it works

Lookup table / curve.

Converts `fIn` using a table of points (`aX`[i], `aY`[i]) with straight lines between them: tank strapping tables, non-linear sensors, weirs and flumes, valve characteristics, pump curves.

`aX` and `aY` are arrays of any size and any lower bound (ARRAY[1..20], ARRAY[0..9] ...). Point 1 is the first element of each, so `aX` and `aY` may even have different lower bounds. `nPoints` = N uses only the first N points; 0 uses the whole arrays, which must then be the same length.

The table is checked every scan (an HMI may edit it): `aX` must be strictly increasing, and every `aX` and `aY` a number. A table that fails holds `fOut` and `bOutOfRange` where they were and sets `bTableOk` FALSE.

Beyond the first or last point: `bExtrapolate` FALSE gives that end's `aY`, TRUE carries the end segment on. A one-point table gives its `aY` everywhere.

A NaN or infinite `fIn` holds `fOut` and `bOutOfRange` and sets `bBadInput`; `bInGood` FALSE holds them too. `bGood`: `bInGood`, `bTableOk` and `fIn` a number. `fSlope` is `dY` / `dX` of the segment in use (the end segment beyond the ends; 0 for a one-point table): a vessel's TABLE area.

## Example

A tank strapping table: level (m) to volume (m3).

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTankLevel.fValue` |
| `aX` | `aLevels` |
| `aY` | `aVolumes` |
| `fOut` | the volume |

**Back to** [the index](../README.md).
