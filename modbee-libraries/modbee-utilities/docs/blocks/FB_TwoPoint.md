# FB_TwoPoint — On / off controller

An on / off (hysteresis) controller, thermostat style, with delays and anti-short-cycle times.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | measured value |
| in | `bEnable` | `BOOL` | `TRUE` | FALSE = output off |
| in | `eDir` | `E_TwoPointDir` |  | `ByOrder` (the default: the order of the points decides), `OnBelow` (fill / heat), `OnAbove` (empty / cool) |
| in | `fOnPoint` | `REAL` | `20.0` | The value at which bQ comes on |
| in | `fOffPoint` | `REAL` | `80.0` | The value at which bQ goes off |
| in | `tOnDelay` | `TIME` |  | value must stay past fOnPoint this long |
| in | `tOffDelay` | `TIME` |  | value must stay past fOffPoint this long |
| in | `tMinOn` | `TIME` |  | shortest time on |
| in | `tMinOff` | `TIME` |  | shortest time off before coming on again |
| out | `bQ` | `BOOL` |  | The output |
| out | `bBadInput` | `BOOL` |  | fIn or a point is NaN or infinite: bQ is held |
| out | `bBadOrder` | `BOOL` |  | the points are the wrong way round for eDir (or eDir is not a direction): bQ off |
| out | `tRemaining` | `TIME` |  | time left before bQ changes (delay, tMinOn / tMinOff) |
| out | `bWaiting` | `BOOL` |  | past the point, delay over, but tMinOn / tMinOff holds bQ |

## Lists

- `E_TwoPointDir`: `ByOrder`, `OnBelow`, `OnAbove` (default `E_TwoPointDir.ByOrder`)

## How it works

On/off (hysteresis) controller, thermostat style.

With `eDir` `ByOrder` (the default) the order of the points decides the direction:

```
  fOnPoint < fOffPoint   fill / heat:   on below fOnPoint, off above fOffPoint
  fOnPoint > fOffPoint   empty / cool:  on above fOnPoint, off below fOffPoint
  fOnPoint = fOffPoint   a plain comparator with no hysteresis, in the
                       fill / heat direction (on below, off above)
```

A value exactly on a point is not past it, so nothing changes there.

`tOnDelay` / `tOffDelay`: the value must stay past the point this long. `tMinOn` / `tMinOff`: anti-short-cycle. `bQ` stays on at least `tMinOn`, and stays off at least `tMinOff` before it may come on again. `tMinOff` is not applied at start-up. The points are re-evaluated every scan, so changing or swapping them while running takes effect cleanly (through the delays).

`bEnable` FALSE turns `bQ` off at once, even inside `tMinOn`; `tMinOff` then counts from that moment.

A value that is not a number (`fIn` or a point NaN or infinite) holds `bQ` as it is and sets `bBadInput`; the delays start again once it is good.

`tRemaining` is the time left before `bQ` changes: the delay and the `tMinOn` / `tMinOff` still to run while the value is past the point that changes it (T#0s otherwise). `bWaiting` is TRUE while the value is past that point and its delay is over, but `tMinOn` / `tMinOff` still holds `bQ` as it is.

`eDir` `OnBelow` or `OnAbove` fixes the direction instead; points the wrong way round for it set `bBadOrder` and keep `bQ` off.

## Example

A heater on below 5 °C, off above 8 °C.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTemp.fValue` |
| `bEnable` | TRUE |
| `fOnPoint` | 5.0 |
| `fOffPoint` | 8.0 |
| `tMinOff` | `T#2m` |
| `bQ` | `DO_Heater` |

**Back to** [the index](../README.md).
