# FB_ReportArray — Report by exception for a list

FB_Report for a list of values, one row each.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | link up / born: every item reports First |
| in | `bForce` | `BOOL R_EDGE` |  | every item reports now Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_ReportArrayData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aItemSet` | `ARRAY[*] OF ST_ReportSet` |  | each value's settings, ST_ReportSet, at most 16 kept |
| in-out | `aItem` | `ARRAY[*] OF ST_ReportItem` |  | each value's live row: the project writes aItem[i].fIn and aItem[i].bInGood; the block writes bReport (one scan: send now), fValue, bGood, eReason in aItem[i].stMem, and aItem[i].sts |
| out | `bAnyReport` | `BOOL` |  | An item reports this scan |
| out | `nReportCount` | `INT` |  | items reporting this scan |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ReportArrayData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdForce` | `BOOL` |  | every item reports now (cleared by the block) |

**Settings `set`** (`ST_ReportArraySet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tHeartbeat` | `TIME` |  | for items whose own is 0 (0 = off) |
| `bReportOnStart` | `BOOL` | `TRUE` | Report when the block starts or `bEnable` comes back |

**Status `sts`** (`ST_ReportArraySts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nReports` | `UDINT` |  | Reports sent |
| `nBadItem` | `INT` |  | the first item with a bad setting (0 none) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Rows `ST_ReportSet` (pin `aItemSet`)

`aItemSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_ReportSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDeadband` | `REAL` | `1.0` | Hysteresis / deadband, in the value's unit |
| `eDeadbandMode` | `E_DeadbandMode` |  | `Abs` (value units), `PctValue` (% of the last value sent) or `PctSpan` (% of `fSpan`) |
| `fSpan` | `REAL` |  | PctSpan: the measuring span |
| `fResolution` | `REAL` |  | round to this step first (0 = off) |
| `tMinInterval` | `TIME` |  | 0 = no rate cap |
| `tHeartbeat` | `TIME` |  | 0 = off |
| `bReportOnStart` | `BOOL` | `TRUE` | Report when the block starts or `bEnable` comes back |

## Rows `ST_ReportItem` (pin `aItem`)

`aItem` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_ReportItem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fIn` | `REAL` |  | the value (the project's; BOOL / INT: convert to REAL) |
| `bInGood` | `BOOL` | `TRUE` | its quality (the project's) |
| `bCmdForce` | `BOOL` |  | report this one now (cleared by the block) |
| `stMem` | `ST_ReportMem` |  | stMem.bReport, fValue, bGood, eReason: the results; fields below |
| `sts` | `ST_ReportSts` |  | fields below |
| `bCmdSeen` | `BOOL` |  |  |

**`stMem`** (`ST_ReportMem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bReport` | `BOOL` |  | one scan: send now |
| `fValue` | `REAL` |  | held from the report |
| `bGood` | `BOOL` |  | The value can be trusted |
| `eReason` | `E_ReportReason` |  | Why (status) |
| `bStarted` | `BOOL` |  |  |
| `fGoodV` | `REAL` |  | the last fIn that was a number |
| `tLastAt` | `TIME` |  |  |
| `bForcePend` | `BOOL` |  | a force waiting for tMinInterval |
| `bChange` | `BOOL` |  |  |
| `bHeld` | `BOOL` |  | the wait is counted in nSuppressed |

**`sts`** (`ST_ReportSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fLastValue` | `REAL` |  | The value last reported |
| `bLastGood` | `BOOL` |  | The quality last reported |
| `eReason` | `E_ReportReason` |  | Why (status) |
| `nReports` | `UDINT` |  | Reports sent |
| `nSuppressed` | `UDINT` |  | held back by tMinInterval |
| `tSinceLast` | `TIME` |  | Time since the last report |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Lists

- `E_DeadbandMode`: `Abs`, `PctValue`, `PctSpan` (default `Abs`)
- `E_ReportReason`: `None`, `Change`, `Heartbeat`, `Forced`, `First` (default `None`)

## How it works

[`FB_Report`](FB_Report.md) for a list of values. Tables the project declares (VAR_IN_OUT, the same size): `aItemSet` (each value's settings, `ST_ReportSet`, at most 16 kept) and `aItem` (each value's live row: the project writes `aItem`[i].fIn and `aItem`[i].bInGood; the block writes `bReport` (one scan: send now), `fValue`, `bGood`, `eReason` in `aItem`[i].stMem, and `aItem`[i].sts). Each row runs the [`FB_Report`](FB_Report.md) decision (`F_ReportRun`). `bEnable` FALSE holds every item; `bEnable` back (link up / born) = every item reports First (with its and `set.bReportOnStart`); `bForce` / `bCmdForce` = every item reports now, `aItem`[i].bCmdForce that item. `set.tHeartbeat` applies to items whose own is 0.

Tables of different sizes: error BadSetting.

## Example

Report four values. Declare `aRepSet : ARRAY[1..4] OF ST_ReportSet` and `aRep : ARRAY[1..4] OF ST_ReportItem`.

| Pin | Wire |
| --- | --- |
| `bEnable` | `bLinkUp` |
| `aItemSet` | `aRepSet` |
| `aItem` | `aRep` |
| `refData` | `stRep` |

Write `aRep[i].fIn` and `aRep[i].bInGood` on their own rungs.

**Back to** [the index](../README.md).
