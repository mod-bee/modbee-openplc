# FB_Report — Report by exception

Report by exception: decides when one value is worth sending (a change past a deadband, a heartbeat, a force), for a value sent by other means than modbee-mqtt.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value (BOOL / INT: convert to REAL) |
| in | `bInputGood` | `BOOL` | `TRUE` | its quality |
| in | `bReportNow` | `BOOL R_EDGE` |  | report now |
| in | `bEnable` | `BOOL` | `TRUE` | link up / born: on again = report First |
| in | `refData` | `REFERENCE TO ST_ReportData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bSendNow` | `BOOL` |  | one scan: send now |
| out | `fReportedValue` | `REAL` |  | held from the report |
| out | `bReportedGood` | `BOOL` |  | its quality |
| out | `eReportReason` | `E_ReportReason` |  | held from the report |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ReportData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReportNow` | `BOOL` |  | report now (cleared by the block; a held write acts once) |

**Settings `set`** (`ST_ReportSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDeadband` | `REAL` | `1.0` | a change larger than this reports (in the unit eDeadbandMode gives) |
| `eDeadbandMode` | `E_DeadbandMode` |  | Abs (value units), PctValue (% of the last value sent) or PctSpan (% of fSpan) |
| `fSpan` | `REAL` |  | PctSpan: the measuring span |
| `fRoundToStep` | `REAL` |  | round to this step first (0 = off) |
| `tMinInterval` | `TIME` |  | 0 = no rate cap |
| `tHeartbeatInterval` | `TIME` |  | 0 = off |
| `bReportOnStart` | `BOOL` | `TRUE` | report when the block starts or bEnable comes back |

**Status `sts`** (`ST_ReportSts`)

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

Report by exception: decides when one value is worth sending to SCADA / IoT. `bSendNow` pulses for one scan when:

```
  First      the block starts, or bEnable comes back (link up), with set.bReportOnStart
  Change     fIn moved more than the deadband from the last value sent, or bInputGood changed
  Heartbeat  set.tHeartbeatInterval passed since the last report (0 = off, the default)
  Forced     bReportNow / bCmdReportNow
```

`set.tMinInterval` (0 = none, the default: no rate cap) keeps two reports apart; a change or a force during it is sent when it ends, with the value then (`sts.nSuppressedCount` counts them). An `fIn` that is not a number is sent as not good with the last good value. The deadband is in the value's units (Abs), a % of the last value sent (PctValue), or a % of `set.fSpan` (PctSpan); `set.fRoundToStep` rounds the value first (0 = off).

## Example

Report a tank level when it moves more than 0.05 m.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTank.fValue` |
| `bInputGood` | `fbTank.bGood` |
| `refData` | `stRepLevel` |
| `bSendNow` | the send trigger |

**Back to** [the index](../README.md).
