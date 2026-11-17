# F_Countdown — Time remaining

Time remaining on any timer: preset minus elapsed, never negative.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tPT` | `TIME` | `T#0s` | the timer's preset (MyTon.PT) |
| in | `tET` | `TIME` | `T#0s` | its elapsed time (MyTon.ET) |
| out | *(result)* | `TIME` | | `tPT - tET`, never negative, never more than `tPT` |

## How it works

Time remaining on any timer (TON / TOF / TP / [`FB_Tonr`](FB_Tonr.md)): `tPT` - `tET`, never negative, never more than `tPT`.

## Example

Time left on a TON.

| Pin | Wire |
| --- | --- |
| `tPT` | `tonDelay.PT` |
| `tET` | `tonDelay.ET` |

**Back to** [the index](../README.md).
