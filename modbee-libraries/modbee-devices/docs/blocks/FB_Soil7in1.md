# FB_Soil7in1 — 7-in-1 RS485 soil sensor

Reads a 7-in-1 soil probe on Modbus RTU: moisture, temperature, conductivity
(EC), pH, nitrogen, phosphorus and potassium.

```iecst
VAR
  line  : FB_ModbusNode;            (* the RS485 line, a client *)
  soil1 : FB_Soil7in1;
  soil1Data : ST_SoilData := (set := (nUnitId := 1));
END_VAR

soil1(fbNode := line, refData := soil1Data);
IF soil1.bGood THEN
  moisture := soil1.fMoisturePct;
END_IF;
```

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | read the sensor |
| in | `refData` | `REFERENCE TO ST_SoilData` |  | the sensor's record: settings set and status sts |
| in-out | `fbNode` | `FB_ModbusNode` |  | the RS485 line's FB_ModbusNode (a client) |
| out | `bGood` | `BOOL` |  | answering, every value plausible |
| out | `fMoisturePct` | `REAL` |  | soil moisture, % (as the sensor reports it) |
| out | `fTemperatureDegC` | `REAL` |  | soil temperature, degC (negative below zero) |
| out | `fConductivity` | `REAL` |  | electrical conductivity (EC), uS/cm |
| out | `fPh` | `REAL` |  | pH, 0-14 |
| out | `fNitrogen` | `REAL` |  | nitrogen, mg/kg |
| out | `fPhosphorus` | `REAL` |  | phosphorus, mg/kg |
| out | `fPotassium` | `REAL` |  | potassium, mg/kg |
| out | `bError` | `BOOL` |  | enabled and not Ok (Setup, NoReply, Lost or BadData) |
| out | `eErrorId` | `E_DeviceError` |  | which error: None while all is well |

## Record `ST_SoilData` (pin `refData`)

**Settings `set`** (`ST_SoilSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nUnitId` | `BYTE` | `1` | the sensor's Modbus address, 1..247 (factory 1) |
| `eRegisterMap` | `E_SoilMap` | `E_SoilMap.Jxct` | its register map: Jxct (most units) unless the maker's sheet says otherwise |
| `tReadInterval` | `TIME` | `T#10s` | read it this often (at least 1 s: the sensor answers within 1 s) |

**Status `sts`** (`ST_SoilSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStatus` | `E_DeviceStatus` |  | Off, Ok, Setup (address not 1..247), NoReply, Lost or BadData |
| `sStatusText` | `STRING(30)` |  | the status in words, for a panel |
| `tValueAge` | `TIME` |  | time since the last good reading |
| `bGood` | `BOOL` |  | answering, every value plausible (as the bGood pin) |
| `bError` | `BOOL` |  | as the bError pin |
| `eErrorId` | `E_DeviceError` |  | as the eErrorId pin |
| `fMoisturePct` | `REAL` |  | soil moisture, % |
| `fTemperatureDegC` | `REAL` |  | soil temperature, degC |
| `fConductivity` | `REAL` |  | electrical conductivity (EC), uS/cm |
| `fPh` | `REAL` |  | pH, 0-14 |
| `fNitrogen` | `REAL` |  | nitrogen, mg/kg |
| `fPhosphorus` | `REAL` |  | phosphorus, mg/kg |
| `fPotassium` | `REAL` |  | potassium, mg/kg |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a good write) |

## Lists

- `E_DeviceError`: `None`, `AddressBad`, `NoReply`, `Lost`, `BadData`, `NoRecord` (default `None`)
- `E_DeviceStatus`: `Off`, `Ok`, `Setup`, `NoReply`, `Lost`, `BadData` (default `Off`)
- `E_SoilMap`: `Jxct`, `Linear` (default `Jxct`)

## Wiring and line settings
- RS485 A/B to the line; the probe's supply as its label says (usually 5–30 V DC).
- The common sensor: **9600 baud, 8N1** (set in the node's `stSerialConfig`),
  factory address **1**. Several probes share one line at different addresses,
  one `FB_Soil7in1` each.

## Register maps (`refData.set.eRegisterMap`)
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
- The outputs hold the last good reading while `bGood` is FALSE; `refData.sts.tValueAge` says how old it is.
- A sensor that stops answering backs off before it is asked again, so after a
  cable is fixed it can take a little while to show OK.
- **Power cut**: the settings (`set`: `nUnitId`, `eRegisterMap`, `tReadInterval`) are kept by the block
  (a retained last-good copy, restored at power-up); a write that cannot work is refused and the last good
  value put back (`sts.bSettingRefused`). The readings are not kept: the outputs are 0 until the first good reading.
