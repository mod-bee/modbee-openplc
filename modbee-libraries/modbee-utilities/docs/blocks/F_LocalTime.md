# F_LocalTime — Local time

Local time from a UTC clock: the offset plus daylight saving.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dtUtc` | `DT` | `DT#1970-01-01-00:00:00` | the controller clock (UTC), e.g. CURRENT_DT |
| in | `nOffsetMin` | `INT` | `720` | standard offset, minutes east of UTC (NZ 720) |
| in | `eDst` | `E_DstRule` | `E_DstRule.Nz` | the daylight saving rule |
| out | *(result)* | `DT` | | Local time |

## Lists

- `E_DstRule`: `None`, `Nz`, `AuSe`, `Eu`, `Us` (default `E_DstRule.None`)

## How it works

Local time: `dtUtc` + `nOffsetMin`, plus an hour while daylight saving is in force

## Example

New Zealand local time from a UTC clock.

| Pin | Wire |
| --- | --- |
| `dtUtc` | `dtUtcClock` |
| `nOffsetMin` | 720 |
| `eDst` | `E_DstRule.Nz` |

**Back to** [the index](../README.md).
