# F_Countdown — Time remaining

Time remaining on any timer: preset minus elapsed, never negative.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tPresetTime` | `TIME` | `T#0s` | the timer's preset (MyTon.PT) |
| in | `tElapsedTime` | `TIME` | `T#0s` | its elapsed time (MyTon.ET) |
| out | *(result)* | `TIME` |  | the time left on the timer, never negative |

## How it works

Time remaining on any timer (TON / TOF / TP / [`FB_Tonr`](FB_Tonr.md)): `tPresetTime` - `tElapsedTime`, never negative, never more than `tPresetTime`.

## Example

Time left on a TON.

| Pin | Wire |
| --- | --- |
| `tPresetTime` | `tonDelay.PT` |
| `tElapsedTime` | `tonDelay.ET` |

**Back to** [the index](../README.md).
