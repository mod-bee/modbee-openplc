# UT_VESSEL — Level → volume, percent, mass

Converts a level into contents for common tank and silo shapes. For odd shapes
use a strapping table with [UT_LINEARISE](UT_LINEARISE.md). Replaces
SiloVolumeCalculator, DividedSiloVolumeCalculator and volumeToWeight.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Level` | REAL | 0.0 | Level from the sensor, in `levelUnit` (m by default; mm, cm or % of the full height) |
| out | `Volume` | REAL | | In `volumeUnit` (m³ by default; L or ML) |
| out | `Percent` | REAL | | Of total volume |
| out | `Mass` | REAL | | Volume × density, in `massUnit` (kg by default; t) |
| out | `Free` | REAL | | Space left, in `volumeUnit` |
| inout | `Data` | UT_VESSEL_DATA | | |

## Record `UT_VESSEL_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `shape` | UT_VESSEL_SHAPE | UT_SHAPE_VERTICAL | `UT_SHAPE_VERTICAL` (flat-bottom vertical cylinder), `UT_SHAPE_CONE` (silo: cylinder over a cone/hopper), `UT_SHAPE_HORIZONTAL` (horizontal cylinder, flat ends), `UT_SHAPE_RECT` (rectangular), `UT_SHAPE_SPHERE` |
| `diameter` | REAL | 1.0 | In `levelUnit` (m by default) |
| `height` | REAL | 1.0 | Straight-section height, in `levelUnit` (CONE: the cylinder above the hopper; 0 = hopper only) |
| `length` / `width` | REAL | 1.0 / 1.0 | Horizontal / rectangular, in `levelUnit` |
| `coneHeight` | REAL | 0.0 | Hopper height, in `levelUnit` |
| `outletDiameter` | REAL | 0.0 | Hopper outlet, in `levelUnit` |
| `levelUnit` | UT_LEVEL_UNIT | UT_LEVEL_M | Unit of `Level`, `levelOffset` **and the dimensions**: `UT_LEVEL_M` (0), `UT_LEVEL_MM`, `UT_LEVEL_CM`; or `UT_LEVEL_PCT` (`Level` and `levelOffset` in % of the full level height: the height, the hopper plus the cylinder, or the diameter of a horizontal tank or sphere; **the dimensions are then in metres**) |
| `volumeUnit` | UT_VOL_UNIT | UT_VOL_NONE | Unit of `Volume`, `Free`, `volume`, `totalVolume`, `free` and `deadVolume`: `UT_VOL_NONE` (0) and `UT_VOL_M3` = m³, `UT_VOL_L` = litres, `UT_VOL_ML` = megalitres |
| `massUnit` | UT_MASS_UNIT | UT_MASS_KG | Unit of `Mass`, `mass` and `totalMass`: `UT_MASS_KG` (0) or `UT_MASS_T` (tonnes) |
| `levelOffset` | REAL | 0.0 | Added to `Level` (sensor zero above or below the vessel bottom), in `levelUnit` |
| `fraction` | REAL | 1.0 | Share of the vessel (0.5 = your divided silo) |
| `density` | REAL | 1000.0 | kg/m³ (water 1000; for a specific gravity, SG × 1000) |
| `deadVolume` | REAL | 0.0 | Unusable volume below the outlet, in `volumeUnit`, taken off your share's contents and total |
| `volume`, `totalVolume`, `percent`, `mass`, `totalMass`, `free` | REAL | | Status, in the units above |
| `overfull` | BOOL | | Status: level above the top (the outputs show full) |
| `wrnConfig` | BOOL | | The settings don't make a vessel; every output is 0 |
| `wrnLevel` | BOOL | | `Level` is not a number or infinite; the outputs hold their last values |
| `statusCode` | UT_STATUS | | Status: OK, or what is wrong (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | Status: the warning or the setting the status is about (`UT_F_NONE` when OK) |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Config: diameter`. The contents are in `percent` / `levelPct` |
| `pctLow` | REAL | 0.0 | `levelPct` is 0 % at this level (empty, or the stop level L), in `levelUnit`, like `Level` |
| `pctHigh` | REAL | 0.0 | `levelPct` is 100 % at this level (the overflow level). `pctLow` and `pctHigh` both 0 = the whole height |
| `levelPct` | REAL | | Status: the level as a % of `pctLow` … `pctHigh`, the easy number for an operator. Never below 0; above 100 between `pctHigh` and the top |

## How it works
- The level is measured up from the bottom (CONE: from the hopper outlet) and
  clamped: below 0 is empty, above the top is full with `overfull` set.
- The partial cone volume is computed at the actual fill height. This fixes the
  overestimate in the original.
- **Units.** The dimensions are in the same unit as the level, so the tank
  drawing and the transmitter can be typed in as they are: with
  `levelUnit := UT_LEVEL_MM` a 2.4 m tank is `diameter := 2400.0`. With
  `UT_LEVEL_PCT` the level is a share of the full height and the dimensions are
  in metres (the % needs the real size to give a volume). The volumes and the
  mass each have their own unit setting, so an HMI showing litres or tonnes
  needs no maths in the program. Density is always kg/m³ (SG × 1000).
- Example: a 2400 mm × 3000 mm vertical water tank, radar in mm, HMI in litres:
  `levelUnit := UT_LEVEL_MM, diameter := 2400.0, height := 3000.0,
  volumeUnit := UT_VOL_L`. A level of 1500 mm gives 6786 L (50 %). The same tank
  with the radar scaled 0–100 %: `levelUnit := UT_LEVEL_PCT, diameter := 2.4,
  height := 3.0`, and 50 % gives the same 6786 L.
- `wrnConfig` is set, and every output is 0 (nothing divides by zero), when a
  needed dimension is 0, negative, not a number or over 10 km (10 000 000 mm), `fraction` is not
  above 0 and up to 1, `density` is negative, an outlet is wider than the
  silo, the dead volume fills the whole vessel, or a unit is unknown.
- **Level %** (`levelPct`) is not the same as `percent`: `percent` is the share
  of the volume, `levelPct` the level within a working range, e.g. an effluent
  sump with `pctLow := 500.0` (L, mm) and `pctHigh := 1800.0` (overflow) shows
  0 % at the stop level and 100 % at overflow. `levelOffset` is added to both,
  as to `Level`. A range that is not a number or not rising uses the whole
  height and shows `Setting: level % range`; the volumes are not affected.

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OK` | | `OK` | Normal: the contents are in `percent`, `volume`, `levelPct` … |
| `UT_ST_WARNING` | `UT_F_LEVEL_BAD` | `Warning: level signal bad` | `Level` is not a number or infinite (`wrnLevel`): the last values are held |
| `UT_ST_WARNING` | `UT_F_LEVEL_ABOVE_FULL` | `Warning: level above full` | `overfull` |
| `UT_ST_WARN_SETTING` | `UT_F_LEVEL_RANGE` | `Setting: level % range` | `pctLow` / `pctHigh` not a number or `pctHigh` not above `pctLow`: the whole height is used |
| `UT_ST_CONFIG` | `UT_F_DIAMETER` | `Config: diameter` | `wrnConfig`, by the first problem found: diameter 0 or not a number |
| `UT_ST_CONFIG` | `UT_F_TANK_HEIGHT` | `Config: tank height` | Height 0 or not a number |
| `UT_ST_CONFIG` | `UT_F_LENGTH_WIDTH` | `Config: length / width` | Length or width 0 or not a number |
| `UT_ST_CONFIG` | `UT_F_CONE` | `Config: cone / outlet` | Cone height or outlet negative, an outlet wider than the silo, or no height at all |
| `UT_ST_CONFIG` | `UT_F_FRACTION` | `Config: fraction` | `fraction` not above 0 and up to 1 |
| `UT_ST_CONFIG` | `UT_F_DENSITY` | `Config: density` | Negative or not a number |
| `UT_ST_CONFIG` | `UT_F_DEAD_VOLUME` | `Config: dead volume` | Negative, not a number, or it fills the tank |
| `UT_ST_CONFIG` | `UT_F_LEVEL_OFFSET` | `Config: level offset` | Not a number or too big |
| `UT_ST_CONFIG` | `UT_F_UNIT` | `Config: unit unknown` | `levelUnit`, `volumeUnit` or `massUnit` |
