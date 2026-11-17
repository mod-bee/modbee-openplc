# F_ClockOk — Clock is set

TRUE when the site clock has been set (a date from 2020 up to 2100).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dtUtc` | `DT` |  | The clock |
| out | *(result)* | `BOOL` | | TRUE when the clock is set |

## How it works

The site clock is set: a date from 2020 up to 2100 (a board that has not had the time yet starts at 1970).

## Example

| Pin | Wire |
| --- | --- |
| `dtUtc` | `dtUtcClock` |

**Back to** [the index](../README.md).
