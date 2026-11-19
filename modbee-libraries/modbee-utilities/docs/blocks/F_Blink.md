# F_Blink — Flashing lamp in step

A flashing lamp from the PLC clock: every lamp using it flashes in step.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tOnTime` | `TIME` | `T#500ms` | on time |
| in | `tOffTime` | `TIME` | `T#500ms` | off time |
| out | *(result)* | `BOOL` |  | the flashing lamp: TRUE in the on time |

## How it works

A flashing lamp from the PLC clock: TRUE for `tOnTime`, FALSE for `tOffTime`; all lamps using it flash in step. No memory.

## Example

A lamp flashing in step with every other lamp.

| Pin | Wire |
| --- | --- |
| `tOnTime` | `T#500ms` |
| `tOffTime` | `T#500ms` |

**Back to** [the index](../README.md).
