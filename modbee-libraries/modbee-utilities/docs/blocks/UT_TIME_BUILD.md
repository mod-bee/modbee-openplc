# UT_TIME_BUILD — Days/hours/minutes/seconds → TIME (function)

Lets an HMI enter a delay as separate numbers (e.g. 2 h 30 min) and gives a TIME.

## Pins
| | Pin | Type | Default |
| --- | --- | --- | --- |
| in | `Days`, `Hours`, `Minutes`, `Seconds`, `Millis` | UDINT | 0 |
| returns | | TIME | Sum. Parts may exceed their natural range (90 minutes is fine) |

```iecst
Delay := UT_TIME_BUILD(Hours := HmiHours, Minutes := HmiMinutes);
```

## How it works
- The parts are simply added. Leave out any part you don't need.
- A total beyond the largest TIME (`T#106751d23h47m16s854ms775us807ns`) gives the
  largest TIME. It never wraps round to a negative time, even with every part at its
  largest UDINT value.
- For the reverse (a TIME shown as parts or text) use [UT_TIME_SPLIT](UT_TIME_SPLIT.md).
