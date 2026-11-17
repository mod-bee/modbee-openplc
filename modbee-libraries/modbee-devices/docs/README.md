# ModBee Devices

One block per field device. Each block knows its device's registers, scaling
and plausible ranges, so a project never deals with Modbus addresses.

Built on **modbee-modbus** 0.2.0: wire the block's `fbNode` to the `FB_ModbusNode`
of the device's line (RS485 client, or TCP). Moving from 0.1.x: see
[migrating-from-0.1](migrating-from-0.1.md).

| Block | Device |
| --- | --- |
| [FB_Soil7in1](blocks/FB_Soil7in1.md) | 7-in-1 RS485 soil sensor: moisture, temperature, EC, pH, N, P, K |

## Common to every block
- Settings and status sit in one struct (`ST_<device>Data`), so an HMI or SCADA
  reaches them in one place.
- `bGood` is TRUE only while the device answers and every value is plausible.
  The outputs hold the last good reading while `bGood` is FALSE.
- `eStatus` (`E_DeviceStatus`) and `sStatus` say why, in words:

| Code | Status | Text | Meaning |
| --- | --- | --- | --- |
| 0 | `E_DeviceStatus.Off` | Off | `bEnable` is FALSE |
| 1 | `E_DeviceStatus.Ok` | OK | answering, values plausible |
| 2 | `E_DeviceStatus.Setup` | Setup: … | a setting that cannot work (the unit address) |
| 3 | `E_DeviceStatus.NoReply` | No reply: address/baud/map | never answered: address, baud rate, wiring or register map |
| 4 | `E_DeviceStatus.Lost` | Comms lost | answered before, not any more: cable, power, the device |
| 5 | `E_DeviceStatus.BadData` | Bad data: check the map | answers, but the values are impossible |

New codes are added at the end, so a code number never changes. Values are
always written with their type (`E_DeviceStatus.Ok`), never bare (`Ok`).

Several of the same block may share one node, one per device: each keeps its
own readings.
