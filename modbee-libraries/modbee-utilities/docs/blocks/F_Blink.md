# F_Blink — Flashing lamp in step

A flashing lamp from the PLC clock: every lamp using it flashes in step.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tOnTime` | `TIME` | `T#500ms` | On time |
| in | `tOffTime` | `TIME` | `T#500ms` | Off time |
| out | *(result)* | `BOOL` | | TRUE in the on part of the flash |

## How it works

A flashing lamp from the PLC clock: TRUE for `tOnTime`, FALSE for `tOffTime`; all lamps using it flash in step. No memory.

## Example

A lamp flashing in step with every other lamp.

| Pin | Wire |
| --- | --- |
| `tOnTime` | `T#500ms` |
| `tOffTime` | `T#500ms` |

**Back to** [the index](../README.md).
