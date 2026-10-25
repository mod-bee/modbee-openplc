# UT_RESET_TEXT — How a trip will clear, as text (function)

The end of a fault line: how the protection clears and, while it is counting, how
long that takes. The device blocks don't use it: their status says how a trip clears
by its prefix (`Fault:`, `Retrying:`, `Latched:`, `Locked:`, see
[UT_STATUS_TEXT](UT_STATUS_TEXT.md)) and keeps the time in `timeLeft`. Use it for a
simple display, or a fault line of your own.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Mode` | UT_RESET_MODE | UT_RST_AUTO | The protection's `reset` |
| in | `Retries` | INT | 0 | Its `retries` |
| in | `MaxRetries` | INT | 0 | Its `maxRetries` |
| in | `TimeLeft` | TIME | T#0s | Its `timeLeft` |
| returns | | STRING(48) | | The text, starting with `, ` |

```iecst
OverloadLine := CONCAT('Fault: overload', UT_RESET_TEXT(Motor1.overload.reset,
    Motor1.overload.retries, Motor1.overload.maxRetries, Motor1.overload.timeLeft));
(* 'Fault: overload, auto reset in 25 s' (OverloadLine : STRING(64)) *)
```

## How it works
| Reset mode | Text |
| --- | --- |
| `UT_RST_MANUAL` | `, reset needed` |
| `UT_RST_RETRY`, `Retries` above `MaxRetries` | `, retries used up, reset needed` |
| `UT_RST_RETRY` | `, retrying 2 of 3 in 25 s` |
| `UT_RST_AUTO` | `, auto reset in 25 s` |

The time ([UT_TIME_TEXT](UT_TIME_TEXT.md)) is added only while `TimeLeft` is above
0, that is while the recover or retry wait runs. While the cause is still there
nothing counts, and the text stops at `, auto reset` or `, retrying 2 of 3`.
