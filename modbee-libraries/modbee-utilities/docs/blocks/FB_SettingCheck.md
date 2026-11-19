# FB_SettingCheck — Setting write gate

A write gate for one project value that belongs to no block: a new value from the HMI is checked against its limits before it is used.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fRequestedValue` | `REAL` |  | the value the master wrote |
| in | `bCheckNow` | `BOOL R_EDGE` |  | check fRequestedValue now, even if unchanged |
| in | `fLowestAllowed` | `REAL` | `REAL#-3.4E38` | lowest value allowed |
| in | `fHighestAllowed` | `REAL` | `REAL#3.4E38` | highest value allowed |
| in | `fMustBeAbove` | `REAL` | `REAL#-3.4E38` | must be above this related setting |
| in | `fMustBeBelow` | `REAL` | `REAL#3.4E38` | must be below this related setting |
| in | `refValueInUse` | `REFERENCE TO REAL` |  | the value in use (a project RETAIN variable) |
| out | `bRequestAccepted` | `BOOL` |  | one scan |
| out | `bRequestRefused` | `BOOL` |  | one scan |
| out | `eRefusedReason` | `E_UtError` |  | the last refused write (None after an accepted one) |
| out | `bError` | `BOOL` |  | the value in use fails the checks |
| out | `eErrorId` | `E_UtError` |  | which check it fails (None when all is well) |

## How it works

Write gate for one project value that belongs to no block. The HMI / SCADA writes its own variable (`fRequestedValue`); each time `fRequestedValue` changes, or on `bCheckNow`, `fRequestedValue` is checked: a number, `fLowestAllowed`..fHighestAllowed, above `fMustBeAbove` and below `fMustBeBelow` for related settings (e.g. high above low). Passed: `refValueInUse` := `fRequestedValue`, `bRequestAccepted` for one scan. Failed: `refValueInUse` keeps its old value, `bRequestRefused` for one scan, `eRefusedReason` says why (ValueBad, LimitsBad, BelowMin, AboveMax, NotAbove, NotBelow; None after an accepted write). `bError` / `eErrorId`: the value in use fails the checks now (written past this block, or a limit moved). Unwired limits are open. Nothing is checked on the first scan: a master variable that comes back 0 never overwrites a kept value (`refValueInUse` is the project's RETAIN variable). No `refValueInUse`: `bError`, NoRecord.

## Example

A high-level alarm setpoint the HMI writes.

| Pin | Wire |
| --- | --- |
| `fRequestedValue` | `fHmiHighLevel` |
| `fLowestAllowed` | 0.0 |
| `fHighestAllowed` | 5.0 |
| `refValueInUse` | `fHighLevel` (a RETAIN variable of your project) |

**Back to** [the index](../README.md).
