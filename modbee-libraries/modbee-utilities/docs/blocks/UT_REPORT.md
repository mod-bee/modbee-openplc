# UT_REPORT — Report by exception (IoT / SCADA)

Decides **when a value is worth sending**: it has changed by more than a deadband,
its quality has changed, a heartbeat time has passed with no change, or you force it.
It also enforces a minimum interval so a noisy signal can't flood a cellular link.
Use `Report` to trigger an MQTT/BeeBus publish. For a whole list of values in one
block, use [UT_REPORT_ARRAY](UT_REPORT_ARRAY.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Value to watch. A BOOL or INT is converted first: `BOOL_TO_REAL(x)`, `INT_TO_REAL(x)` (deadband 0.5 reports every change) |
| in | `Force` | BOOL | FALSE | Rising edge: report now (or when `minInterval` allows) |
| in | `Enable` | BOOL | TRUE | FALSE: no reports; on again reports as at start |
| in | `Quality` | UT_QUALITY | UT_Q_GOOD | Quality of `In` (e.g. from the analog input); a change is reported |
| out | `Report` | BOOL | | One-scan pulse: send now |
| out | `Value` | REAL | | Value to send (held from the report) |
| out | `Reason` | UT_REPORT_REASON | | `UT_RPT_NONE` (0, nothing sent yet), `UT_RPT_CHANGE`, `UT_RPT_HEARTBEAT`, `UT_RPT_FORCED`, `UT_RPT_FIRST` (held from the report) |
| inout | `Data` | UT_REPORT_DATA | | |

## Record `UT_REPORT_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `deadband` | REAL | 1.0 | Report when `In` moves **more** than this from the last value sent (negative or NaN: any change) |
| `deadbandPct` | BOOL | FALSE | Older form of `deadbandMode := UT_DB_PCT_VALUE` (TRUE acts as PCT_VALUE while `deadbandMode` is ABS) |
| `minInterval` | TIME | T#1s | Never two reports closer than this |
| `heartbeat` | TIME | T#15m | Report anyway after this long without one (0 = off) |
| `reportOnStart` | BOOL | TRUE | Report once at start (FALSE: the value at start is the starting point) |
| `lastValue` | REAL | | Status: the value last sent |
| `quality` | UT_QUALITY | | Status: the quality last sent (send it with `Value`) |
| `sinceLast` | TIME | | Status: time since the last report |
| `reports` | UDINT | | Status: reports sent |
| `suppressed` | UDINT | | Status: reports held back by `minInterval` |
| `deadbandMode` | UT_DEADBAND_MODE | UT_DB_ABS | What `deadband` is measured in: `UT_DB_ABS` (0, the value's own units), `UT_DB_PCT_VALUE` (% of the last value sent; near 0 any change reports), `UT_DB_PCT_SPAN` (% of `span`: the same size everywhere, also near 0) |
| `span` | REAL | 0.0 | PCT_SPAN: the measuring span, e.g. 5000 for a 0–5000 mm transmitter (0, negative or not a number: any change reports) |
| `resolution` | REAL | 0.0 | Round the value to this step before it is compared and sent: level to 10 mm, pressure to 0.1 bar (0, negative or not a number = off) |
| `cmdForce` | BOOL | | HMI / SCADA: report now (on its rising edge; set back to FALSE) |
| `inQuality` | UT_QUALITY | UT_Q_GOOD | [UT_REPORT_ARRAY](UT_REPORT_ARRAY.md) only: the quality of this item's value |
| `report` | BOOL | | Status: TRUE for the scan it reports (the array's per-item `Report`) |
| `reason` | UT_REPORT_REASON | | Status: why it last reported |
| `memStarted` … `memCmd` | | | Block memory: don't write them |

## How it works
- A change or `Force` that arrives during `minInterval` isn't lost: it's reported as soon
  as the interval ends, with the value at that moment, so the final value is always sent.
  A held-back `Force` wins over a change (`Reason` FORCED).
- `In` that is not a number (NaN, infinity) is sent once as quality `UT_Q_BAD` with the
  last good value; the next real number is sent with `Quality` again.
- A held `Force` reports once; a `Force` held through `Enable` off doesn't report.
- Nothing is kept over a power cut; after one the block reports FIRST again. The
  block's memory is in the record (the `mem` fields), but it starts fresh on the
  block's first scan, so a record declared `RETAIN` (to keep its settings) reports
  FIRST after a power cut too.
- `resolution` rounds to the nearest step (2.26 → 2.3 at 0.1; 1234.4 → 1230 at 10).
  A value of more than 10¹⁵ steps is sent as it is.
- Send the value with `Data.quality`, and bind the SCADA metric to `Value` (or
  `lastValue`), the value held from the report, not to `In`.

## Using it
```iecst
LevelRpt(In := WetWell.Value, Quality := WetWell.Quality, Data := LevelRptCfg);
IF LevelRpt.Report THEN
  (* publish LevelRpt.Value with LevelRptCfg.quality *)
END_IF;
```
