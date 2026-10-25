# UT_UNIT_CONV — Engineering unit conversion (function)

Converts a pressure, flow, volume, temperature or length from one unit to
another: bar to psi, L/s to m³/h, °C to °F. **UT_UNIT_OK** tells you whether two
units can be converted.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | The value, in `FromUnit` |
| in | `FromUnit` | UT_UNIT | UT_UNIT_NONE | Its unit |
| in | `ToUnit` | UT_UNIT | UT_UNIT_NONE | The unit wanted |
| returns | | REAL | | The value in `ToUnit` |

```iecst
SuctionPsi := UT_UNIT_CONV(In := SuctionBar, FromUnit := UT_UNIT_BAR, ToUnit := UT_UNIT_PSI);
FlowM3h := UT_UNIT_CONV(In := FlowLps, FromUnit := UT_UNIT_LPS, ToUnit := UT_UNIT_M3H);
```

### UT_UNIT_OK
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `FromUnit` | UT_UNIT | UT_UNIT_NONE | |
| in | `ToUnit` | UT_UNIT | UT_UNIT_NONE | |
| returns | | BOOL | | TRUE: both are the same kind and neither is NONE |

## Units (`UT_UNIT`)
| Kind | Units |
| --- | --- |
| Pressure | `UT_UNIT_BAR` · `UT_UNIT_KPA` · `UT_UNIT_PSI` · `UT_UNIT_MH2O` (metres of water, 9.80665 kPa) |
| Flow | `UT_UNIT_LPS` (L/s) · `UT_UNIT_LPM` (L/min) · `UT_UNIT_M3H` (m³/h) · `UT_UNIT_GPM` (US gal/min) |
| Volume | `UT_UNIT_L` · `UT_UNIT_M3` · `UT_UNIT_ML` (**megalitre**, as `UT_VOL_ML`) · `UT_UNIT_GAL` (US gallon) |
| Temperature | `UT_UNIT_DEGC` · `UT_UNIT_DEGF` · `UT_UNIT_K` |
| Length | `UT_UNIT_MM` · `UT_UNIT_CM` · `UT_UNIT_M` · `UT_UNIT_IN` · `UT_UNIT_FT` |

`UT_UNIT_NONE` (the default) is "no unit".

## How it works
- **Different kinds can't be converted** (bar to L/s), and neither can NONE. The
  value then comes back **unchanged**. The function never returns NaN for a wrong
  pair: a NaN makes every comparison downstream FALSE, so a high-level alarm fed
  from it would never trip, and nothing would show why. An unchanged value is
  wrong in a way you see at commissioning. Where the units are chosen at run
  time (from an HMI), check the pair with `UT_UNIT_OK` and raise your own
  warning.
- The same unit on both sides gives `In` back exactly.
- Worked in LREAL, so converting there and back loses nothing a REAL can show.
- NaN in gives NaN out; a result beyond the REAL range (about 3.4E38) is infinite.
- US gallons (3.785411784 L). Imperial gallons are not offered.
