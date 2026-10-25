# UT_LINEARISE — Lookup table / curve

Converts a value using a table of points with straight lines between them. Used
for tank strapping tables (level → volume for odd shapes), non-linear sensors,
V-notch weirs and flumes, valve characteristics and pump curves.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Value to look up |
| in | `Points` | INT | 0 | Use only the first N points (0 = whole array) |
| in | `Extrapolate` | BOOL | FALSE | Beyond the ends: FALSE = clamp to the end value, TRUE = extend the end segment |
| out | `Out` | REAL | | Interpolated result |
| out | `OutOfRange` | BOOL | | `In` beyond the first/last point |
| out | `TableOk` | BOOL | | Table valid (X strictly increasing, all numbers, lengths agree) |
| out | `BadInput` | BOOL | | `In` is NaN or infinite: `Out` is held |
| inout | `X` | ARRAY[*] OF REAL | | Input points, increasing |
| inout | `Y` | ARRAY[*] OF REAL | | Output points |

Declare the arrays once (e.g. `ARRAY[1..20] OF REAL`) and fill them from your
strapping table. They can be `RETAIN` so an HMI can edit them; an edit takes
effect on the next scan.

## How it works
- Any size and any lower bound: `ARRAY[1..20]`, `ARRAY[0..9]`, `ARRAY[-2..2]`.
  Point 1 is the first element of each array, so `X` and `Y` may even start at
  different indexes.
- `Points = 0` uses the whole arrays, which must then be the same length.
  `Points = N` uses the first N of each (both must have at least N).
- The table is checked every scan. It is **not OK** if an X is not bigger than
  the one before (unsorted or a duplicate), any X or Y is NaN or infinite,
  `Points` is negative or longer than an array, or there are no points. Then
  `TableOk` is FALSE and `Out` and `OutOfRange` hold their last values.
- Exactly on a point gives exactly that point's Y. Y need not increase.
- A one-point table gives its Y everywhere.
- A NaN or infinite `In` holds `Out` and `OutOfRange` and sets `BadInput`.
- The maths runs in LREAL, so tables with values near the REAL limits work.
  Extrapolating far beyond a steep end segment can still exceed the REAL range.
- Cost: one pass over the points each scan (500 points is fine).

## Using it
```iecst
Strapping(In := LevelM, X := LevelTable, Y := VolumeTable);
VolumeM3 := Strapping.Out;
```
