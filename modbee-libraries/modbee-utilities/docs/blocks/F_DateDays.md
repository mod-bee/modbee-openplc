# F_DateDays — Days since 1970

Days from 1970-01-01 to a date.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nYear` | `INT` | `1970` | The year |
| in | `nMonth` | `INT` | `1` | 1..12 |
| in | `nDay` | `INT` | `1` | 1..31 |
| out | *(result)* | `DINT` | | Days since 1970-01-01 |

## How it works

Days from 1970-01-01 to a date (Gregorian calendar). A month outside 1..12 rolls into the year before or after (month 13 = January next year)

## Example

| Pin | Wire |
| --- | --- |
| `nYear` | 2026 |
| `nMonth` | 11 |
| `nDay` | 17 |

**Back to** [the index](../README.md).
