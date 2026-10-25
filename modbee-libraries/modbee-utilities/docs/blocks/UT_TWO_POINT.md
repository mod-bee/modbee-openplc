# UT_TWO_POINT — On/off (hysteresis) controller

A thermostat-style controller. The setpoint order decides the direction, so there's no mode to set:
- `OnPoint < OffPoint` → **fill / heat**: on when low, off when high.
- `OnPoint > OffPoint` → **empty / cool**: on when high, off when low.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Measured value |
| in | `Enable` | BOOL | TRUE | FALSE = output off |
| in | `OnPoint` | REAL | 20.0 | |
| in | `OffPoint` | REAL | 80.0 | |
| in | `OnDelay` / `OffDelay` | TIME | T#0s | Value must stay past the point this long |
| in | `MinOn` / `MinOff` | TIME | T#0s | Anti-short-cycle |
| out | `Q` | BOOL | | The output |
| out | `BadInput` | BOOL | | `In` or a point is NaN or infinite: `Q` is held |
| out | `Remaining` | TIME | | Time left before `Q` changes: the delay and `MinOn` / `MinOff` still to run while the value is past the point that changes it (`T#0s` otherwise) |
| out | `Waiting` | BOOL | | The value is past the point and its delay is over, but `MinOn` / `MinOff` still holds `Q` |

## How it works
- A value exactly on a point is not past it, so nothing changes there.
- Equal points act as a simple comparator with no hysteresis, in the fill / heat
  direction: on below the point, off above it (documented, not an error).
- `OnDelay` / `OffDelay`: the value must stay past the point the whole time; a blip
  back starts the delay again.
- `MinOn`: once on, `Q` stays on at least this long. `MinOff`: once off, `Q` stays
  off at least this long. `MinOff` is not applied at start-up.
- The points are re-evaluated every scan, so changing or swapping them while
  running takes effect cleanly (through the delays).
- `Enable` FALSE turns `Q` off at once, even inside `MinOn`. `MinOff` counts from
  that moment.
- A NaN or infinite `In`, `OnPoint` or `OffPoint` holds `Q` as it is and sets
  `BadInput`; the delays start again once the value is good. `Enable` still
  turns `Q` off. Use `BadInput` to decide what the plant should do.
- `Remaining` is the longer of the delay and the minimum time still to run, so
  an HMI can show "starts in 1 m 20 s" ([UT_TIME_TEXT](UT_TIME_TEXT.md)).
  `Waiting` says the minimum time is the only thing holding `Q` ("Waiting:
  minimum off time").

## Using it
```iecst
SumpCtl(In := SumpLevel, OnPoint := 70.0, OffPoint := 25.0, OnDelay := T#5s, MinOff := T#2m);
SumpPumpAuto := SumpCtl.Q;    (* empty: on above 70 %, off below 25 % *)
```
