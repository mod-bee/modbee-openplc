# DEV_SOIL_7IN1 — 7-in-1 RS485 soil sensor

Reads a 7-in-1 soil probe on Modbus RTU: moisture, temperature, conductivity
(EC), pH, nitrogen, phosphorus and potassium.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in-out | `Node` | MODBUS_NODE | | The RS485 line's node, as a client |
| in-out | `Data` | DEV_SOIL_DATA | | Settings and status (below) |
| in | `Enable` | BOOL | TRUE | Read the sensor |
| out | `Good` | BOOL | | Answering, every value plausible |
| out | `Moisture` | REAL | | % (as the sensor reports it) |
| out | `Temperature` | REAL | | °C, negative below zero |
| out | `Ec` | REAL | | µS/cm |
| out | `Ph` | REAL | | pH |
| out | `Nitrogen` | REAL | | mg/kg |
| out | `Phosphorus` | REAL | | mg/kg |
| out | `Potassium` | REAL | | mg/kg |

### `Data` (DEV_SOIL_DATA)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `unit` | USINT | 1 | The sensor's Modbus address, 1..247 (factory 1) |
| `map` | DEV_SOIL_MAP | `DEV_SOIL_JXCT` | Its register map (below) |
| `every` | TIME | T#10s | Read it this often (at least 1 s) |
| `status` | DEV_STATUS | | Status code (see the [README](../README.md)) |
| `statusText` | STRING(30) | | Status in words |
| `age` | TIME | | Time since the last good reading |

## Wiring and line settings
- RS485 A/B to the line; the probe's supply as its label says (usually 5–30 V DC).
- The common sensor: **9600 baud, 8N1** (`SERIAL_PARITY := MODBUS_PARITY_NONE_8N1`),
  factory address **1**. Several probes share one line at different addresses.

## Register maps (`Data.map`)
Makers differ, so the map is a setting.

| Map | Registers (holding, FC03) | Scaling |
| --- | --- | --- |
| `DEV_SOIL_JXCT` (default) — JXCT JXBS-3001 and most generic units | pH 0x0006; moisture 0x0012, temperature 0x0013; EC 0x0015; N P K 0x001E–0x0020 | pH ÷100, moisture and temperature ÷10 |
| `DEV_SOIL_LINEAR` | moisture, temperature, EC, pH, N, P, K at 0x0000–0x0006 | pH ÷10, moisture and temperature ÷10 |

**Check the map against your sensor's sheet before installing.** A wrong map
never shows plausible numbers: the sensor refuses the addresses (`No reply`) or
the values are impossible (`Bad data`).

## How it works
- Plausible: moisture 0–100 %, temperature −40–80 °C, pH 0–14, EC 0–20000 µS/cm,
  N P K 0–2000 mg/kg. Anything outside is `Bad data` and `Good` drops.
- The outputs hold the last good reading while `Good` is FALSE; `Data.age` says how old it is.
- A sensor that stops answering backs off (up to 16 × `every`) before it is asked
  again, so after a cable is fixed it can take that long to show OK.
- **Power cut**: nothing is kept; the outputs are 0 until the first good reading.
