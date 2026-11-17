# F_DstActive — Daylight saving in force

TRUE while daylight saving is in force under a rule (NZ, AU south-east, EU, US).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dtUtc` | `DT` | `DT#1970-01-01-00:00:00` | the controller clock (UTC) |
| in | `nOffsetMin` | `INT` | `720` | standard offset, minutes east of UTC (NZ 720) |
| in | `eDst` | `E_DstRule` | `E_DstRule.Nz` | The daylight-saving rule: `None`, `Nz`, `AuSe`, `Eu`, `Us` |
| out | *(result)* | `BOOL` | | TRUE while daylight saving is in force |

## Lists

- `E_DstRule`: `None`, `Nz`, `AuSe`, `Eu`, `Us` (default `E_DstRule.None`)

## How it works

TRUE while daylight saving is in force under the rule

## Example

| Pin | Wire |
| --- | --- |
| `dtUtc` | `dtUtcClock` |
| `nOffsetMin` | 720 |
| `eDst` | `E_DstRule.Nz` |

**Back to** [the index](../README.md).
