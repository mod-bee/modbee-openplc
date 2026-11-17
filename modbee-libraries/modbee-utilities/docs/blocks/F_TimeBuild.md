# F_TimeBuild — Numbers to a TIME

Days, hours, minutes, seconds and milliseconds to a TIME (an HMI enters a delay as numbers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nDays` | `UDINT` | `0` | Days |
| in | `nHours` | `UDINT` | `0` | Hours |
| in | `nMinutes` | `UDINT` | `0` | Minutes |
| in | `nSeconds` | `UDINT` | `0` | Seconds |
| in | `nMillis` | `UDINT` | `0` | Milliseconds |
| out | *(result)* | `TIME` | | The TIME |

## How it works

Days, hours, minutes, seconds and milliseconds to a TIME (function).

Lets an HMI enter a delay as separate numbers (e.g. 2 h 30 min) and gives a TIME. The parts are simply added, so they may exceed their natural range (90 minutes is fine). A total beyond the largest TIME (T#106751d23h47m16s854ms775us807ns) gives the largest TIME.

## Example

An HMI enters a delay in hours and minutes.

| Pin | Wire |
| --- | --- |
| `nHours` | `nHmiHours` |
| `nMinutes` | `nHmiMinutes` |

**Back to** [the index](../README.md).
