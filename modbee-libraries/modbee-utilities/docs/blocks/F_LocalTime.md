# F_LocalTime — Local time

Local time from a UTC clock: the offset plus daylight saving.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dtClockUtc` | `DT` | `DT#1970-01-01-00:00:00` | the controller clock (UTC), e.g. CURRENT_DT |
| in | `nUtcOffsetMinutes` | `INT` | `720` | standard offset, minutes east of UTC (NZ 720) |
| in | `eDaylightSavingRule` | `E_DstRule` | `E_DstRule.Nz` | the daylight saving rule |
| out | *(result)* | `DT` |  | the local time |

## Lists

- `E_DstRule`: `None`, `Nz`, `AuSe`, `Eu`, `Us` (default `E_DstRule.None`)

## How it works

Local time: `dtClockUtc` + `nUtcOffsetMinutes`, plus an hour while daylight saving is in force

## Example

New Zealand local time from a UTC clock.

| Pin | Wire |
| --- | --- |
| `dtClockUtc` | `dtUtcClock` |
| `nUtcOffsetMinutes` | 720 |
| `eDaylightSavingRule` | `E_DstRule.Nz` |

**Back to** [the index](../README.md).
