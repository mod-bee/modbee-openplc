# FB_ReportArray — Report by exception for a list

FB_Report for a list of values, one row each.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | link up / born: every item reports First |
| in | `bReportNow` | `BOOL R_EDGE` |  | every item reports now |
| in | `refData` | `REFERENCE TO ST_ReportArrayData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aItemSettings` | `ARRAY[*] OF ST_ReportSet` |  | each value's settings (at most 16 kept) |
| in-out | `aItems` | `ARRAY[*] OF ST_ReportItem` |  | each value's live row: the project writes fIn and bInputGood; the block writes the result |
| out | `bAnyReport` | `BOOL` |  | an item reports this scan |
| out | `nItemsReporting` | `INT` |  | items reporting this scan |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ReportArrayData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReportNow` | `BOOL` |  | every item reports now (cleared by the block) |

**Settings `set`** (`ST_ReportArraySet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tDefaultHeartbeatInterval` | `TIME` |  | for items whose own is 0 (0 = off) |
| `bReportOnStart` | `BOOL` | `TRUE` | report when the block starts or bEnable comes back |

**Status `sts`** (`ST_ReportArraySts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nSentCount` | `UDINT` |  | reports sent |
| `nBadSettingItem` | `INT` |  | the first item with a bad setting (0 none) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_ReportSet` (pin `aItemSettings`)

`aItemSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_ReportSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDeadband` | `REAL` | `1.0` | a change larger than this reports (in the unit eDeadbandMode gives) |
| `eDeadbandMode` | `E_DeadbandMode` |  | Abs (value units), PctValue (% of the last value sent) or PctSpan (% of fSpan) |
| `fSpan` | `REAL` |  | PctSpan: the measuring span |
| `fRoundToStep` | `REAL` |  | round to this step first (0 = off) |
| `tMinInterval` | `TIME` |  | 0 = no rate cap |
| `tHeartbeatInterval` | `TIME` |  | 0 = off |
| `bReportOnStart` | `BOOL` | `TRUE` | report when the block starts or bEnable comes back |

## Rows `ST_ReportItem` (pin `aItems`)

`aItems` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_ReportItem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fIn` | `REAL` |  | the value (the project's; BOOL / INT: convert to REAL) |
| `bInputGood` | `BOOL` | `TRUE` | its quality (the project's) |
| `bCmdReportNow` | `BOOL` |  | report this one now (cleared by the block) |
| `stResult` | `ST_ReportMem` |  | stResult.bSendNow, fValue, bGood, eReportReason: the results; fields below |
| `sts` | `ST_ReportSts` |  | status; fields below |
| `bCmdReportNowTaken` | `BOOL` |  | engine memory: the command was taken |

**`stResult`** (`ST_ReportMem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSendNow` | `BOOL` |  | one scan: send now |
| `fReportedValue` | `REAL` |  | held from the report |
| `bReportedGood` | `BOOL` |  | the quality held from the report |
| `eReportReason` | `E_ReportReason` |  | why it reported: Change, Heartbeat, Forced or First |
| `bStarted` | `BOOL` |  | engine memory: the first report has been made |
| `fLastNumber` | `REAL` |  | the last fIn that was a number |
| `tLastReportAt` | `TIME` |  | engine memory: when it last reported (TIME()) |
| `bForcePending` | `BOOL` |  | a force waiting for tMinInterval |
| `bChangePending` | `BOOL` |  | engine memory: a change is waiting to be reported |
| `bHeldByMinInterval` | `BOOL` |  | the wait is counted in nSuppressedCount |

**`sts`** (`ST_ReportSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fReportedValue` | `REAL` |  | the value last reported |
| `bReportedGood` | `BOOL` |  | the quality last reported |
| `eReportReason` | `E_ReportReason` |  | why it last reported |
| `nSentCount` | `UDINT` |  | reports sent |
| `nSuppressedCount` | `UDINT` |  | held back by tMinInterval |
| `tSinceLastReport` | `TIME` |  | time since the last report |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_DeadbandMode`: `Abs`, `PctValue`, `PctSpan` (default `Abs`)
- `E_ReportReason`: `None`, `Change`, `Heartbeat`, `Forced`, `First` (default `None`)

## How it works

[`FB_Report`](FB_Report.md) for a list of values. Tables the project declares (VAR_IN_OUT, the same size): `aItemSettings` (each value's settings, `ST_ReportSet`, at most 16 kept) and `aItems` (each value's live row: the project writes `aItems`[i].fIn and `aItems`[i].bInputGood; the block writes `bSendNow` (one scan: send now), `fReportedValue`, `bReportedGood`, `eReportReason` in `aItems`[i].stResult, and `aItems`[i].sts). Each row runs the [`FB_Report`](FB_Report.md) decision (`F_ReportRun`). `bEnable` FALSE holds every item; `bEnable` back (link up / born) = every item reports First (with its and `set.bReportOnStart`); `bReportNow` / `bCmdReportNow` = every item reports now, `aItems`[i].bCmdReportNow that item. `set.tDefaultHeartbeatInterval` applies to items whose own is 0.

Tables of different sizes: error BadSetting.

## Example

Report four values. Declare `aRepSet : ARRAY[1..4] OF ST_ReportSet` and `aRep : ARRAY[1..4] OF ST_ReportItem`.

| Pin | Wire |
| --- | --- |
| `bEnable` | `bLinkUp` |
| `aItemSettings` | `aRepSet` |
| `aItems` | `aRep` |
| `refData` | `stRep` |

Write `aRep[i].fIn` and `aRep[i].bInputGood` on their own rungs.

**Back to** [the index](../README.md).
