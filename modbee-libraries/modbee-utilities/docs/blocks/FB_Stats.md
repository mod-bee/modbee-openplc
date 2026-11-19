# FB_Stats — Minimum, maximum, average

Minimum, maximum and time-weighted average of a value, for the current period and the previous one.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value |
| in | `bInputGood` | `BOOL` | `TRUE` | its health; FALSE: samples skipped |
| in | `bEnable` | `BOOL` | `TRUE` | collect while TRUE |
| in | `bClosePeriod` | `BOOL R_EDGE` |  | close the period |
| in | `bClearPeriods` | `BOOL R_EDGE` |  | clear both periods |
| in | `refData` | `REFERENCE TO ST_StatsData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fMinimum` | `REAL` |  | current period |
| out | `fMaximum` | `REAL` |  | the current period's highest value |
| out | `fAverage` | `REAL` |  | the current period's time-weighted average |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StatsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearPeriods` | `BOOL` |  | clear the current and previous period (cleared; a held write acts once) |

**Settings `set`** (`ST_StatsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fIgnoreBelow` | `REAL` |  | values below this are left out (0 = off) |
| `fIgnoreAbove` | `REAL` |  | values above this are left out (0 = off) |

**Status `sts`** (`ST_StatsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinimum` | `REAL` |  | current period (0 while no samples) |
| `fMaximum` | `REAL` |  | the current period's highest value |
| `fAverage` | `REAL` |  | time-weighted |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Totals `tot`** (`ST_StatsTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stCurrentPeriod` | `ST_StatsCur` |  | the current period (kept); fields below |
| `stPreviousPeriod` | `ST_StatsPrev` |  | the previous period (kept); fields below |

**`stCurrentPeriod`** (`ST_StatsCur`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinimum` | `REAL` |  | the period's lowest value so far |
| `fMaximum` | `REAL` |  | the period's highest value so far |
| `fValueTimesMs` | `LREAL` |  | value x milliseconds |
| `fSumCompensation` | `LREAL` |  | Kahan compensation |
| `nSampleCount` | `UDINT` |  | samples counted |
| `tTimeCollected` | `TIME` |  | time collected |
| `tMinimumAt` | `TIME` |  | time into the period of the minimum |
| `tMaximumAt` | `TIME` |  | time into the period of the maximum |
| `tElapsedTime` | `TIME` |  | time since the period started |

**`stPreviousPeriod`** (`ST_StatsPrev`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinimum` | `REAL` |  | the previous period's lowest value |
| `fMaximum` | `REAL` |  | the previous period's highest value |
| `fAverage` | `REAL` |  | the previous period's time-weighted average |
| `tTimeCollected` | `TIME` |  | time collected in the previous period |
| `nSampleCount` | `UDINT` |  | samples counted in the previous period |

## How it works

Minimum, maximum and time-weighted average of a value, for the current period and the previous one.

Each scan the value read now stands for the time since the previous scan (time-weighted: the same result at any scan rate). Only samples taken while `bEnable` and `bInputGood`, that are numbers and not left out by `set.fIgnoreBelow` / `fIgnoreAbove`, count. `bClosePeriod` closes the period: `tot.stCurrentPeriod` moves to `tot.stPreviousPeriod`. `bClearPeriods` / `bCmdClearPeriods` clears both. tot is kept hourly and at each rollover / reset; the sum is LREAL with compensated (Kahan) summation; `nSampleCount` saturates at the UDINT maximum. The record's sts carries the live summary only; the previous period, sample count, duration and the times of the extremes are read from tot. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Daily minimum, maximum and average of a pressure (SCADA closes the period).

| Pin | Wire |
| --- | --- |
| `fIn` | `fbPressure.fValue` |
| `bInputGood` | `fbPressure.bGood` |
| `bEnable` | TRUE |
| `bClosePeriod` | a pulse from SCADA |
| `refData` | `stPressStats` |

**Back to** [the index](../README.md).
