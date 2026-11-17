# FB_SettingCheck — Setting write gate

A write gate for one project value that belongs to no block: a new value from the HMI is checked against its limits before it is used.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fNew` | `REAL` |  | the value the master wrote |
| in | `bWritten` | `BOOL R_EDGE` |  | check fNew now, even if unchanged Acts on its rising edge. |
| in | `fMin` | `REAL` | `REAL#-3.4E38` | Lowest value allowed |
| in | `fMax` | `REAL` | `REAL#3.4E38` | Highest value allowed |
| in | `fAbove` | `REAL` | `REAL#-3.4E38` | must be above this related setting |
| in | `fBelow` | `REAL` | `REAL#3.4E38` | must be below this related setting |
| in | `refValue` | `REFERENCE TO REAL` |  | the value in use (a project RETAIN variable) |
| out | `bAccepted` | `BOOL` |  | one scan |
| out | `bRefused` | `BOOL` |  | one scan |
| out | `eRefusedId` | `E_UtError` |  | the last refused write (None after an accepted one) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well |

## How it works

Write gate for one project value that belongs to no block. The HMI / SCADA writes its own variable (`fNew`); each time `fNew` changes, or on `bWritten`, `fNew` is checked: a number, `fMin`..fMax, above `fAbove` and below `fBelow` for related settings (e.g. high above low). Passed: `refValue` := `fNew`, `bAccepted` for one scan. Failed: `refValue` keeps its old value, `bRefused` for one scan, `eRefusedId` says why (ValueBad, LimitsBad, BelowMin, AboveMax, NotAbove, NotBelow; None after an accepted write). `bError` / `eErrorId`: the value in use fails the checks now (written past this block, or a limit moved). Unwired limits are open. Nothing is checked on the first scan: a master variable that comes back 0 never overwrites a kept value (`refValue` is the project's RETAIN variable). No `refValue`: `bError`, NoRecord.

## Example

A high-level alarm setpoint the HMI writes.

| Pin | Wire |
| --- | --- |
| `fNew` | `fHmiHighLevel` |
| `fMin` | 0.0 |
| `fMax` | 5.0 |
| `refValue` | `fHighLevel` (a RETAIN variable of your project) |

**Back to** [the index](../README.md).
