# FB_TwoPoint — On / off controller

An on / off (hysteresis) controller, thermostat style, with delays and anti-short-cycle times.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | measured value |
| in | `bEnable` | `BOOL` | `TRUE` | FALSE = output off |
| in | `eDirection` | `E_TwoPointDir` |  | ByOrder (the points decide), OnBelow (fill / heat), OnAbove (empty / cool) |
| in | `fOnPoint` | `REAL` | `20.0` | the value at which bOutputOn comes on |
| in | `fOffPoint` | `REAL` | `80.0` | the value at which bOutputOn goes off |
| in | `tOnDelay` | `TIME` |  | value must stay past fOnPoint this long |
| in | `tOffDelay` | `TIME` |  | value must stay past fOffPoint this long |
| in | `tMinOnTime` | `TIME` |  | shortest time on |
| in | `tMinOffTime` | `TIME` |  | shortest time off before coming on again |
| out | `bOutputOn` | `BOOL` |  | the output |
| out | `bInputNotANumber` | `BOOL` |  | fIn or a point is NaN or infinite: bOutputOn is held |
| out | `bPointsWrongWay` | `BOOL` |  | the points are the wrong way round for eDirection (or eDirection is not a direction): bOutputOn off |
| out | `tTimeLeft` | `TIME` |  | time left before bOutputOn changes (delay, tMinOnTime / tMinOffTime) |
| out | `bHeldByMinTime` | `BOOL` |  | past the point, delay over, but tMinOnTime / tMinOffTime holds bOutputOn |

## Lists

- `E_TwoPointDir`: `ByOrder`, `OnBelow`, `OnAbove` (default `E_TwoPointDir.ByOrder`)

## How it works

On/off (hysteresis) controller, thermostat style.

With `eDirection` `ByOrder` (the default) the order of the points decides the direction:

```
  fOnPoint < fOffPoint   fill / heat:   on below fOnPoint, off above fOffPoint
  fOnPoint > fOffPoint   empty / cool:  on above fOnPoint, off below fOffPoint
  fOnPoint = fOffPoint   a plain comparator with no hysteresis, in the
                       fill / heat direction (on below, off above)
```

A value exactly on a point is not past it, so nothing changes there.

`tOnDelay` / `tOffDelay`: the value must stay past the point this long. `tMinOnTime` / `tMinOffTime`: anti-short-cycle. `bOutputOn` stays on at least `tMinOnTime`, and stays off at least `tMinOffTime` before it may come on again. `tMinOffTime` is not applied at start-up. The points are re-evaluated every scan, so changing or swapping them while running takes effect cleanly (through the delays).

`bEnable` FALSE turns `bOutputOn` off at once, even inside `tMinOnTime`; `tMinOffTime` then counts from that moment.

A value that is not a number (`fIn` or a point NaN or infinite) holds `bOutputOn` as it is and sets `bInputNotANumber`; the delays start again once it is good.

`tTimeLeft` is the time left before `bOutputOn` changes: the delay and the `tMinOnTime` / `tMinOffTime` still to run while the value is past the point that changes it (T#0s otherwise). `bHeldByMinTime` is TRUE while the value is past that point and its delay is over, but `tMinOnTime` / `tMinOffTime` still holds `bOutputOn` as it is.

`eDirection` `OnBelow` or `OnAbove` fixes the direction instead; points the wrong way round for it set `bPointsWrongWay` and keep `bOutputOn` off.

## Example

A heater on below 5 °C, off above 8 °C.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTemp.fValue` |
| `bEnable` | TRUE |
| `fOnPoint` | 5.0 |
| `fOffPoint` | 8.0 |
| `tMinOffTime` | `T#2m` |
| `bOutputOn` | `DO_Heater` |

**Back to** [the index](../README.md).
