# FB_Soil7in1 — 7-in-1 RS485 soil sensor

Reads a 7-in-1 soil probe on Modbus RTU: moisture, temperature, conductivity
(EC), pH, nitrogen, phosphorus and potassium.

```iecst
VAR
  line  : FB_ModbusNode;            (* the RS485 line, a client *)
  soil1 : FB_Soil7in1;
  soil1Data : ST_SoilData := (nUnitId := 1);
END_VAR

soil1(fbNode := line, stData := soil1Data);
IF soil1.bGood THEN
  moisture := soil1.fMoisture;
END_IF;
```

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in-out | `fbNode` | FB_ModbusNode | | The RS485 line's node, as a client |
| in-out | `stData` | ST_SoilData | | Settings and status (below) |
| in | `bEnable` | BOOL | TRUE | Read the sensor |
| out | `bGood` | BOOL | | Answering, every value plausible |
| out | `fMoisture` | REAL | | % (as the sensor reports it) |
| out | `fTemperature` | REAL | | °C, negative below zero |
| out | `fEc` | REAL | | µS/cm |
| out | `fPh` | REAL | | pH |
| out | `fNitrogen` | REAL | | mg/kg |
| out | `fPhosphorus` | REAL | | mg/kg |
| out | `fPotassium` | REAL | | mg/kg |

### `stData` (ST_SoilData)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nUnitId` | USINT | 1 | The sensor's Modbus address, 1..247 (factory 1) |
| `eMap` | E_SoilMap | `E_SoilMap.Jxct` | Its register map (below) |
| `tPeriod` | TIME | T#10s | Read it this often (at least 1 s) |
| `eStatus` | E_DeviceStatus | | Status code (see the [README](../README.md)) |
| `sStatus` | STRING(30) | | Status in words |
| `tAge` | TIME | | Time since the last good reading |

## Wiring and line settings
- RS485 A/B to the line; the probe's supply as its label says (usually 5–30 V DC).
- The common sensor: **9600 baud, 8N1** (set in the node's `stSerialConfig`),
  factory address **1**. Several probes share one line at different addresses,
  one `FB_Soil7in1` each.

## Register maps (`stData.eMap`)
Makers differ, so the map is a setting.

| Map | Registers (holding, FC03) | Scaling |
| --- | --- | --- |
| `E_SoilMap.Jxct` (default) — JXCT JXBS-3001 and most generic units | pH 0x0006; moisture 0x0012, temperature 0x0013; EC 0x0015; N P K 0x001E–0x0020 | pH ÷100, moisture and temperature ÷10 |
| `E_SoilMap.Linear` | moisture, temperature, EC, pH, N, P, K at 0x0000–0x0006 | pH ÷10, moisture and temperature ÷10 |

**Check the map against your sensor's sheet before installing.** A wrong map
never shows plausible numbers: the sensor refuses the addresses (`No reply`) or
the values are impossible (`Bad data`).

## How it works
- Each reading is a standing `Watch` on the node, so the node schedules the line.
- Plausible: moisture 0–100 %, temperature −40–80 °C, pH 0–14, EC 0–20000 µS/cm,
  N P K 0–2000 mg/kg. Anything outside is `Bad data` and `bGood` drops.
- The outputs hold the last good reading while `bGood` is FALSE; `stData.tAge` says how old it is.
- A sensor that stops answering backs off before it is asked again, so after a
  cable is fixed it can take a little while to show OK.
- **Power cut**: nothing is kept; the outputs are 0 until the first good reading.
