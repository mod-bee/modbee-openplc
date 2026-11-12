# Migrating from modbee-devices 0.1.x

0.2.0 follows modbee-modbus 0.2.0: the device blocks take an `FB_ModbusNode`,
and every name follows the same conventions (FB_ / ST_ / E_ types, pins with a
type prefix, enumeration values written with their type). The readings, the
register maps, the plausible ranges and the status codes are unchanged.

| 0.1.x | 0.2.0 |
| --- | --- |
| `DEV_SOIL_7IN1` | `FB_Soil7in1` |
| `Node : MODBUS_NODE` | `fbNode : FB_ModbusNode` |
| `Data : DEV_SOIL_DATA` | `stData : ST_SoilData` |
| `Enable`, `Good` | `bEnable`, `bGood` |
| `Moisture`, `Temperature`, `Ec`, `Ph`, `Nitrogen`, `Phosphorus`, `Potassium` | `fMoisture`, `fTemperature`, `fEc`, `fPh`, `fNitrogen`, `fPhosphorus`, `fPotassium` |
| `Data.unit`, `Data.map`, `Data.every` | `stData.nUnitId`, `stData.eMap`, `stData.tPeriod` |
| `Data.status`, `Data.statusText`, `Data.age` | `stData.eStatus`, `stData.sStatus`, `stData.tAge` |
| `DEV_SOIL_MAP`: `DEV_SOIL_JXCT`, `DEV_SOIL_LINEAR` | `E_SoilMap`: `E_SoilMap.Jxct`, `E_SoilMap.Linear` |
| `DEV_STATUS`: `DEV_ST_OFF` … `DEV_ST_BAD_DATA` | `E_DeviceStatus`: `Off`, `Ok`, `Setup`, `NoReply`, `Lost`, `BadData` (same codes) |
