# F_DstActive — Daylight saving in force

TRUE while daylight saving is in force under a rule (NZ, AU south-east, EU, US).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dtClockUtc` | `DT` | `DT#1970-01-01-00:00:00` | the controller clock (UTC) |
| in | `nUtcOffsetMinutes` | `INT` | `720` | standard offset, minutes east of UTC (NZ 720) |
| in | `eDaylightSavingRule` | `E_DstRule` | `E_DstRule.Nz` | None, Nz, AuSe, Eu or Us |
| out | *(result)* | `BOOL` |  | TRUE while daylight saving is in force |

## Lists

- `E_DstRule`: `None`, `Nz`, `AuSe`, `Eu`, `Us` (default `E_DstRule.None`)

## How it works

TRUE while daylight saving is in force under the rule

## Example

| Pin | Wire |
| --- | --- |
| `dtClockUtc` | `dtUtcClock` |
| `nUtcOffsetMinutes` | 720 |
| `eDaylightSavingRule` | `E_DstRule.Nz` |

**Back to** [the index](../README.md).
