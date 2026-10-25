# UT_TONR — Retentive accumulating timer

Like a `TON`, except the elapsed time is **kept** when `In` goes off, and timing
continues from there. Like Siemens TONR and Rockwell RTO, it lives for as long as
the PLC is powered: after a power cycle `ET` starts at 0. Typical uses: time a
condition has existed, accumulated treatment time within a run.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | BOOL | FALSE | Accumulates while TRUE |
| in | `PT` | TIME | T#10s | Preset |
| in | `Reset` | BOOL | FALSE | Clears `ET` (and `Q`); wins while held |
| out | `Q` | BOOL | | `ET` ≥ `PT`. Stays on when `In` goes off, until `Reset` |
| out | `ET` | TIME | | Accumulated (stops at `PT`) |
| out | `RT` | TIME | | Remaining, `PT − ET` (never negative) |
| out | `Timing` | BOOL | | Accumulating now: `In` AND NOT `Q` AND NOT `Reset` |

## How it works
- While `In` is on, time adds up; while it is off, `ET` holds. `Q` comes on when the
  total reaches `PT` and stays on until `Reset`.
- `Reset` clears the time. Held with `In` on, nothing is gathered; timing starts from 0
  when `Reset` releases.
- `PT` lowered below the time already gathered: `Q` comes on at once (`ET` shows `PT`).
  `PT` raised again: `Q` goes off and timing carries on from the time gathered.
- `PT` of 0 (or negative): `Q` comes on as soon as `In` is on, not before.
- Nothing is retained. After a power cycle or a PLC restart, `ET` is 0 and `Q` is off.
- Accuracy: each period `In` is on is counted to within one scan.

## TOFR (retentive off-delay)
An output that stays on until `x` has been **off** for `PT` in total:

```iecst
OffTimer(In := NOT x, PT := T#10m, Reset := ResetPB);
Out := NOT OffTimer.Q;
```
