# ModBee Devices

One block per field device. Each block knows its device's registers, scaling
and plausible ranges, so a project never deals with Modbus addresses.

Built on **modbee-modbus**: wire the block's `Node` to the `MODBUS_NODE` of the
device's line (RS485 client, or TCP).

| Block | Device |
| --- | --- |
| [DEV_SOIL_7IN1](blocks/DEV_SOIL_7IN1.md) | 7-in-1 RS485 soil sensor: moisture, temperature, EC, pH, N, P, K |

## Common to every block
- Settings and status sit in one `Data` struct (`DEV_<device>_DATA`), so an HMI
  or SCADA reaches them in one place.
- `Good` is TRUE only while the device answers and every value is plausible.
  The outputs hold the last good reading while `Good` is FALSE.
- `Data.status` (`DEV_STATUS`) and `Data.statusText` say why, in words:

| Code | Status | Text | Meaning |
| --- | --- | --- | --- |
| 0 | `DEV_ST_OFF` | Off | `Enable` is FALSE |
| 1 | `DEV_ST_OK` | OK | answering, values plausible |
| 2 | `DEV_ST_SETUP` | Setup: … | a setting that cannot work (the unit address) |
| 3 | `DEV_ST_NO_REPLY` | No reply: address/baud/map | never answered: address, baud rate, wiring or register map |
| 4 | `DEV_ST_LOST` | Comms lost | answered before, not any more: cable, power, the device |
| 5 | `DEV_ST_BAD_DATA` | Bad data: check the map | answers, but the values are impossible |

New codes are added at the end, so a code number never changes.
