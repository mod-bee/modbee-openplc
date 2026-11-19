# FB_Tonr — Retentive on-delay timer

A retentive (accumulating) on-delay timer: the time adds up over several on periods.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | gathers time while TRUE |
| in | `tPresetTime` | `TIME` | `T#10s` | preset |
| in | `bReset` | `BOOL` |  | clears tElapsedTime (wins) |
| out | `bQ` | `BOOL` |  | tElapsedTime has reached tPresetTime |
| out | `tElapsedTime` | `TIME` |  | time gathered (stops at tPresetTime) |
| out | `tTimeLeft` | `TIME` |  | time remaining |
| out | `bTiming` | `BOOL` |  | gathering time now |

## How it works

Retentive (accumulating) on-delay timer. Like a TON, but the elapsed time is kept when `bIn` goes off and timing carries on from there the next time `bIn` is on. `bQ` once `bIn` has been on for `tPresetTime` in total. `bReset` clears the time (wins while held). As Siemens TONR / Rockwell RTO, the time lives only while powered (nothing retained). `tElapsedTime` stops at `tPresetTime`; `tPresetTime` lowered below the time gathered: `bQ` at once; `tPresetTime` <= 0: `bQ` as soon as `bIn` is on. Each scan interval counts if `bIn` was on at its start.

## Example

A filter that needs a backwash after 24 h of running in total. Declare `fbFilterHours : FB_Tonr` and
`fbBackwash : FB_StepSeq` (the backwash recipe).

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_FilterRunning` |
| `tPresetTime` | `T#24h` |
| `bReset` | `fbBackwash.bDone` |
| `bQ` | `fbBackwash.bStart` (the backwash request) |

**Back to** [the index](../README.md).
