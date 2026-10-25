# UT_REPORT_ARRAY — Report by exception for a whole list of values

One block for all the values a site sends to SCADA or the IoT platform (60 to 80
metrics need one block, not 80). Each value has its own
[UT_REPORT](UT_REPORT.md) record, with its own deadband, mode, span, resolution,
minimum interval and heartbeat, and behaves exactly as a UT_REPORT.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | TRUE | FALSE: no reports; on again every item reports as at start (wire the link-up signal, or leave TRUE) |
| in | `Force` | BOOL | FALSE | Rising edge: report every item now (each when its `minInterval` allows) |
| out | `AnyReport` | BOOL | | One scan: at least one item reports |
| out | `ReportCount` | INT | | Items reporting this scan |
| out | `SizeMismatch` | BOOL | | `In` and `Items` differ in length: only the common part is handled |
| inout | `In` | ARRAY[*] OF REAL | | The values to watch (a BOOL or INT converted to REAL first) |
| inout | `Items` | ARRAY[*] OF UT_REPORT_DATA | | One record per value, in the same order |

Values and records are matched by position: the first `In` goes with the first item,
whatever the arrays' lower bounds.

## Each item (`UT_REPORT_DATA`)
Every field as in [UT_REPORT](UT_REPORT.md#record-ut_report_data): the settings
(`deadband`, `deadbandMode`, `span`, `resolution`, `minInterval`, `heartbeat`,
`reportOnStart`) and the status. Three fields are for the array form:

| Field | Type | Meaning |
| --- | --- | --- |
| `inQuality` | UT_QUALITY | The quality of this item's value (default `UT_Q_GOOD`); a change is reported |
| `report` | BOOL | Status: TRUE for the scan this item reports. Send `lastValue` with `quality` |
| `reason` | UT_REPORT_REASON | Status: why it last reported (FIRST, CHANGE, HEARTBEAT, FORCED) |

`cmdForce` reports one item (on its rising edge).

## How it works
- Each scan every item is checked as a UT_REPORT would: a change past its deadband, a
  quality change, its heartbeat, a force. A change held back by `minInterval` is sent
  when the interval ends, with the final value.
- If `In` and `Items` differ in length, only the common part is handled and
  `SizeMismatch` is set; the extra items never report.
- Nothing is kept over a power cut: after one every item reports FIRST again, even
  with the item list declared `RETAIN` (to keep its settings).

## Using it
```iecst
VAR
  Vals : ARRAY[1..3] OF REAL;
  Rpt : ARRAY[1..3] OF UT_REPORT_DATA;
END_VAR
Vals[1] := WetWell.Value;
Vals[2] := FlowAI.Value;
Vals[3] := BOOL_TO_REAL(P1.Running);
RptAll(Enable := NOT ScadaWd.CommsFail, In := Vals, Items := Rpt);
IF RptAll.AnyReport THEN
  (* publish every item with Rpt[i].report: Rpt[i].lastValue, Rpt[i].quality *)
END_IF;
```
