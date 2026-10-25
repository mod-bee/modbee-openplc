# UT_TIME_SPLIT — TIME → days, hours, minutes, seconds

Shows a duration (run time, time left, time since) on an HMI as numbers or as text.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | TIME | T#0s | Any duration |
| out | `Days`, `Hours`, `Minutes`, `Seconds`, `Millis` | UDINT | | Parts: hours 0–23, minutes and seconds 0–59, millis 0–999; the rest is in days |
| out | `TotalHours` | REAL | | The whole duration in hours |
| out | `Text` | STRING(20) | | e.g. `'1d 02:03:04'` for HMIs |
| out | `Short` | STRING(16) | | The two largest units, as [UT_TIME_TEXT](UT_TIME_TEXT.md) writes a time: `'1 h 20 m'`, `'42 m 10 s'`, `'35 s'` |

## How it works
- `Text` is `HH:MM:SS` under a day, and `Nd HH:MM:SS` from one day up, zero padded:
  `'00:00:09'`, `'01:30:00'`, `'1d 02:03:04'`, `'365d 10:20:30'`.
- `Short` is [UT_TIME_TEXT](UT_TIME_TEXT.md)'s form: the two largest units, the
  smaller one rounded up (`T#34500ms` gives `'35 s'`), `'0 s'` for 0.
- A negative time is split by its size: the parts are those of the positive time,
  `TotalHours` is negative and `Text` and `Short` start with `-` (`'-01:01:01'`,
  `'-1 m 30 s'`).
- Anything below a millisecond is dropped.
- Works over the whole TIME range, up to `106751d 23:47:16`.
- For the reverse (numbers from an HMI → TIME) use [UT_TIME_BUILD](UT_TIME_BUILD.md).
