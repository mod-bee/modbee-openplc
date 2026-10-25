# UT_TIME_TEXT — A duration as short text (function)

Turns a TIME into short text: "1 h 20 m", "42 m", "35 s". Use it to show a
`timeLeft` beside a status on a simple display, in your own texts and HMI labels,
instead of a raw seconds count.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | TIME | T#0s | Any duration: a time left, a run time |
| returns | | STRING(16) | | The text |

```iecst
Pump1Text := CONCAT('Next run in ', UT_TIME_TEXT(Pump1Data.timeLeft));
```

## How it works
Two units at most, the larger first. The smaller unit is dropped when it is 0.

| Duration | Text | Examples |
| --- | --- | --- |
| under 1 minute | seconds | `35 s` |
| under 1 hour | minutes and seconds | `42 m 10 s`, `42 m` |
| under 1 day | hours and minutes | `1 h 20 m`, `1 h` |
| 1 day and more | days and hours | `2 d 3 h`, `2 d` |

- The smallest unit shown is **rounded up**, so a countdown never shows 0 while
  time is still left: 0.3 s left shows `1 s`, 1 h 19 m 30 s shows `1 h 20 m`.
- 0, a negative TIME and anything under a millisecond give `0 s`.
- For a clock-style `02:03:04` use [UT_TIME_SPLIT](UT_TIME_SPLIT.md).
