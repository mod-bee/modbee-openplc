# FB_Tonr — Retentive on-delay timer

A retentive (accumulating) on-delay timer: the time adds up over several on periods.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | gathers time while TRUE |
| in | `tPT` | `TIME` | `T#10s` | preset |
| in | `bReset` | `BOOL` |  | clears tET (wins) |
| out | `bQ` | `BOOL` |  | tET has reached tPT |
| out | `tET` | `TIME` |  | time gathered (stops at tPT) |
| out | `tRT` | `TIME` |  | time remaining |
| out | `bTiming` | `BOOL` |  | gathering time now |

## How it works

Retentive (accumulating) on-delay timer. Like a TON, but the elapsed time is kept when `bIn` goes off and timing carries on from there the next time `bIn` is on. `bQ` once `bIn` has been on for `tPT` in total. `bReset` clears the time (wins while held). As Siemens TONR / Rockwell RTO, the time lives only while powered (nothing retained). `tET` stops at `tPT`; `tPT` lowered below the time gathered: `bQ` at once; `tPT` <= 0: `bQ` as soon as `bIn` is on. Each scan interval counts if `bIn` was on at its start.

## Example

A filter that needs a backwash after 24 h of running in total.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_FilterRunning` |
| `tPT` | `T#24h` |
| `bReset` | `fbBackwash.bDone` |
| `bQ` | the backwash request |

**Back to** [the index](../README.md).
