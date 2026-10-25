# UT_LOCAL_TIME — UTC to local time, with daylight saving (function)

The controller clock (`CURRENT_DT`) is UTC. This gives the time a person on site
reads: the standard offset plus an hour while daylight saving is in force.

## Pins
| | Pin | Type | Default |
| --- | --- | --- | --- |
| in | `Utc` | DT | `DT#1970-01-01-00:00:00`. The clock, e.g. `CURRENT_DT` |
| in | `OffsetMin` | INT | 720. Standard (winter) offset, minutes east of UTC |
| in | `Dst` | UT_DST_RULE | `UT_DST_NZ`. The daylight saving rule |
| returns | | DT | Local time |

```iecst
Local := UT_LOCAL_TIME(Utc := CURRENT_DT);                                   (* New Zealand *)
Local := UT_LOCAL_TIME(Utc := CURRENT_DT, OffsetMin := 600, Dst := UT_DST_AU_SE);   (* Sydney *)
Summer := UT_DST_ACTIVE(Utc := CURRENT_DT, OffsetMin := 720, Dst := UT_DST_NZ);
```

Two helper functions come with it:

| Function | Returns |
| --- | --- |
| `UT_DST_ACTIVE(Utc, OffsetMin, Dst)` | BOOL: daylight saving is in force |
| `UT_DATE_DAYS(Year, Month, Day)` | DINT: days since 1970-01-01 (a month outside 1..12 rolls into the year before or after) |

## Rules (`UT_DST_RULE`)
| Value | Where | Starts | Ends |
| --- | --- | --- | --- |
| `UT_DST_NONE` | no daylight saving | | |
| `UT_DST_NZ` | New Zealand | last Sunday in September, 02:00 standard | first Sunday in April, 03:00 daylight |
| `UT_DST_AU_SE` | NSW, ACT, VIC, TAS, SA | first Sunday in October, 02:00 standard | first Sunday in April, 03:00 daylight |
| `UT_DST_EU` | European Union, UK | last Sunday in March, 01:00 UTC | last Sunday in October, 01:00 UTC |
| `UT_DST_US` | United States, Canada | second Sunday in March, 02:00 standard | first Sunday in November, 02:00 daylight |

Common offsets: NZ 720, AU east 600, AU central 570, UK 0, central Europe 60,
US Eastern -300, US Pacific -480.

## How it works
- Local time = `Utc` + `OffsetMin` minutes, plus 60 minutes while `UT_DST_ACTIVE`.
- At the change to daylight saving the local clock jumps an hour forward; at the
  change back the hour after it repeats. Schedules that use local time see that.
- An unknown rule acts as `UT_DST_NONE`. A result before 1970 gives
  `DT#1970-01-01-00:00:00`. Valid for 1970 to 2099.
- Tested against the IANA time zone data a second either side of every change.
