# FB_TimeSplit — TIME into days, hours, minutes

Splits a TIME into days, hours, minutes, seconds and milliseconds, with texts for an HMI.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tIn` | `TIME` |  | any duration |
| out | `nDays` | `UDINT` |  | Whole days |
| out | `nHours` | `UDINT` |  | 0-23 |
| out | `nMinutes` | `UDINT` |  | 0-59 |
| out | `nSeconds` | `UDINT` |  | 0-59 |
| out | `nMillis` | `UDINT` |  | 0-999 |
| out | `fTotalHours` | `REAL` |  | the whole duration in hours |
| out | `sText` | `STRING(20)` |  | e.g. '1d 02:03:04' |
| out | `sShort` | `STRING(16)` |  | the two largest units, as status texts use: '1 h 20 m', '42 m 10 s', '35 s' |

## How it works

A TIME split into days, hours, minutes, seconds and milliseconds, plus the total in hours and a text for HMIs.

`nHours` are 0-23, minutes and seconds 0-59, milliseconds 0-999; whatever is left over is in `nDays`. `sText` is 'HH:MM:SS' under a day and 'Nd HH:MM:SS' from a day up, zero padded, e.g. '1d 02:03:04'.

`sShort` is [`F_TimeText`](F_TimeText.md)'s form ('2 d 3 h', '1 h 20 m', '42 m 10 s', '35 s', rounded up to the smaller unit), the one every status text uses.

A negative TIME is split by its size: the parts are the same as for the positive time, `fTotalHours` is negative and `sText` and `sShort` start with '-'.

Anything below a millisecond is dropped.

## Example

Show a run time on an HMI.

| Pin | Wire |
| --- | --- |
| `tIn` | `stMotor1.det.tRunTime` |
| `sText` | an HMI text |

**Back to** [the index](../README.md).
