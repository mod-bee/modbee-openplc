# FB_Report — Report by exception

Report by exception: decides when one value is worth sending (a change past a deadband, a heartbeat, a force), for a value sent by other means than modbee-mqtt.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | The value (BOOL / INT: convert to REAL) |
| in | `bInGood` | `BOOL` | `TRUE` | Its quality |
| in | `bForce` | `BOOL R_EDGE` |  | report now Acts on its rising edge. |
| in | `bEnable` | `BOOL` | `TRUE` | link up / born: on again = report First |
| in | `refData` | `REFERENCE TO ST_ReportData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bReport` | `BOOL` |  | one scan: send now |
| out | `fValue` | `REAL` |  | held from the report |
| out | `bGood` | `BOOL` |  | its quality |
| out | `eReason` | `E_ReportReason` |  | held from the report |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ReportData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdForce` | `BOOL` |  | report now (cleared by the block; a held write acts once) |

**Settings `set`** (`ST_ReportSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDeadband` | `REAL` | `1.0` | Hysteresis / deadband, in the value's unit |
| `eDeadbandMode` | `E_DeadbandMode` |  | `Abs` (value units), `PctValue` (% of the last value sent) or `PctSpan` (% of `fSpan`) |
| `fSpan` | `REAL` |  | PctSpan: the measuring span |
| `fResolution` | `REAL` |  | round to this step first (0 = off) |
| `tMinInterval` | `TIME` |  | 0 = no rate cap |
| `tHeartbeat` | `TIME` |  | 0 = off |
| `bReportOnStart` | `BOOL` | `TRUE` | Report when the block starts or `bEnable` comes back |

**Status `sts`** (`ST_ReportSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fLastValue` | `REAL` |  | The value last reported |
| `bLastGood` | `BOOL` |  | The quality last reported |
| `eReason` | `E_ReportReason` |  | Why (status) |
| `nReports` | `UDINT` |  | Reports sent |
| `nSuppressed` | `UDINT` |  | held back by tMinInterval |
| `tSinceLast` | `TIME` |  | Time since the last report |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Lists

- `E_DeadbandMode`: `Abs`, `PctValue`, `PctSpan` (default `Abs`)
- `E_ReportReason`: `None`, `Change`, `Heartbeat`, `Forced`, `First` (default `None`)

## How it works

Report by exception: decides when one value is worth sending to SCADA / IoT. `bReport` pulses for one scan when:

```
  First      the block starts, or bEnable comes back (link up), with set.bReportOnStart
  Change     fIn moved more than the deadband from the last value sent, or bInGood changed
  Heartbeat  set.tHeartbeat passed since the last report (0 = off, the default)
  Forced     bForce / bCmdForce
```

`set.tMinInterval` (0 = none, the default: no rate cap) keeps two reports apart; a change or a force during it is sent when it ends, with the value then (`sts.nSuppressed` counts them). An `fIn` that is not a number is sent as not good with the last good value. The deadband is in the value's units (Abs), a % of the last value sent (PctValue), or a % of `set.fSpan` (PctSpan); `set.fResolution` rounds the value first (0 = off).

## Example

Report a tank level when it moves more than 0.05 m.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbTank.fValue` |
| `bInGood` | `fbTank.bGood` |
| `refData` | `stRepLevel` |
| `bReport` | the send trigger |

**Back to** [the index](../README.md).
