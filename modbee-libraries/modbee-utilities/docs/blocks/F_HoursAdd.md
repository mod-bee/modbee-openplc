# F_HoursAdd — Exact running time

Whole milliseconds of running to add this scan, exact over years (for your own run-hour counts).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunning` | `BOOL` |  | It runs (status) |
| in | `tNow` | `TIME` |  | `TIME()` |
| in-out | `stAcc` | `ST_HoursAcc` |  | Your accumulator (one per counter) |
| out | *(result)* | `LINT` | | Milliseconds to add this scan |

## How it works

Whole milliseconds of running since the last call, exact: the scan time is added only when the equipment was running over it, and the part of a millisecond left is carried, so years of short scans lose nothing.

## Example

Used in ST for your own run-hour count: `nMs := F_HoursAdd(bRunning := bBlowerRun, tNow := TIME(), stAcc := stBlowerAcc);`

**Back to** [the index](../README.md).
