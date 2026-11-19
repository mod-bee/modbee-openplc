# F_HoursAdd — Exact running time

Whole milliseconds of running to add this scan, exact over years (for your own run-hour counts).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunning` | `BOOL` |  | it runs |
| in | `tNow` | `TIME` |  | TIME() of this scan |
| in-out | `stAccumulator` | `ST_HoursAcc` |  | your accumulator (one per counter) |
| out | *(result)* | `LINT` |  | whole milliseconds of running since the last call |

## How it works

Whole milliseconds of running since the last call, exact: the scan time is added only when the equipment was running over it, and the part of a millisecond left is carried, so years of short scans lose nothing.

## Example

Used in ST for your own run-hour count: `nMs := F_HoursAdd(bRunning := bBlowerRun, tNow := TIME(), stAccumulator := stBlowerAcc);`

**Back to** [the index](../README.md).
