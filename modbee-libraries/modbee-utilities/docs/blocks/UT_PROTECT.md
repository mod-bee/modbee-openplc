# UT_PROTECT — One protection: delay, response and reset

The protection every device block uses for its faults, and usable on its own for
any condition that should warn or stop something. You work out the condition;
the record decides what happens. See [conventions](../conventions.md#protections--every-fault-works-the-same-way).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Cause` | BOOL | FALSE | The condition is present now (overload, no feedback, high pressure…) |
| in | `ResetReq` | BOOL | FALSE | Reset request this scan (a pushbutton edge, an HMI command) |
| in | `RetryWindow` | TIME | T#1h | RETRY counts trips within this window. `T#0s` = no window: the count is cleared only by a reset (or a power cycle), so trip number `maxRetries + 1` always latches |
| out | `Trip` | BOOL | | Hold the device off |
| out | `Warn` | BOOL | | Warning in effect |
| out | `Event` | BOOL | | One scan: the condition has just become active (after the delay) |
| out | `Reset` | BOOL | | One scan: a latched trip or warning was reset |
| out | `BadSetting` | BOOL | | A setting is invalid: a negative `delay`, `recover` or `RetryWindow`, or a negative `maxRetries` with RETRY. It acts as 0 (see below). FALSE while the response is OFF |
| inout | `Prot` | UT_PROTECTION | | Settings and status |

## Record `UT_PROTECTION`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `response` | UT_RESPONSE | UT_RESP_OFF | `UT_RESP_OFF` ignore · `UT_RESP_WARN` warn only · `UT_RESP_TRIP` stop |
| `delay` | TIME | T#0s | The condition must last this long |
| `reset` | UT_RESET_MODE | UT_RST_AUTO | `UT_RST_AUTO` · `UT_RST_RETRY` · `UT_RST_MANUAL` |
| `recover` | TIME | T#10s | AUTO / RETRY: the condition must be gone this long before the trip clears |
| `maxRetries` | INT | 3 | RETRY: trips allowed in `RetryWindow`; the next one latches (0 = the first trip latches) |
| `active`, `tripped`, `retries`, `count` | | | Status: condition present, held, retries used, total events |
| `timeLeft` | TIME | | Status: the countdown in progress: the `delay` still to run while the condition is present, or the `recover` / retry wait still to go while an AUTO or RETRY trip holds and its condition has gone. `T#0s` when nothing counts (no condition, the condition still holding a trip, a MANUAL trip or used-up RETRY waiting for a reset, a warning) |

## How it works
| Response | AUTO | RETRY | MANUAL |
| --- | --- | --- | --- |
| WARN | `Warn` while the condition is present | as AUTO | `Warn` until reset |
| TRIP | `Trip` until the condition has been gone `recover` | as AUTO, but trip number `maxRetries + 1` within the window latches | `Trip` until a reset with the condition gone |

- A reset while the condition is still present is refused.
- A reset also clears the retry count; a quiet window clears it by itself (not with
  `RetryWindow` `T#0s`: then only a reset or a power cycle clears it).
- Invalid settings act as 0, the safe side: a negative `delay` or `recover` acts
  at once, a negative `RetryWindow` is no window, a negative `maxRetries` latches on
  the first trip. `BadSetting` tells the device block, which raises a config warning.
- Setting `response` to OFF clears everything at once.
- `timeLeft` is the countdown an HMI shows next to the fault. For a simple
  display, [UT_RESET_TEXT](UT_RESET_TEXT.md) turns it into ", auto reset in 25 s"
  or ", retrying 2 of 3 in 25 s".

## Using it
```iecst
HighTemp(Cause := Temp > 85.0, ResetReq := ResetPB, Prot := HighTempCfg);
Heater := HeatCmd AND NOT HighTemp.Trip;
```

## For block builders: UT_PROT_RUN
The same logic as a function, `UT_PROT_RUN`, which the device blocks use inside. A
function has no instance of its own, so the protection record is not copied: the
block that owns the protection keeps its working state in a `UT_PROT_ST` and passes
both in every scan.

| | Pin | Type | What to wire |
| --- | --- | --- | --- |
| in | `TNow` | TIME | `TIME()` of this scan |
| in | `Cause`, `ResetReq`, `RetryWindow` | | As the block's pins above |
| inout | `Prot` | UT_PROTECTION | Settings and status |
| inout | `St` | UT_PROT_ST | The working state, one per protection. Its `trip`, `warn`, `event`, `reset` and `badSetting` are the block's `Trip`, `Warn`, `Event`, `Reset` and `BadSetting`. Not for HMIs |
| returns | | BOOL | `Trip` |

```iecst
x := UT_PROT_RUN(TNow := TIME(), Cause := Temp > 85.0, ResetReq := ResetPB,
                 RetryWindow := T#1h, Prot := HighTempCfg, St := HighTempSt);
```
