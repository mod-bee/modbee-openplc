# FB_Stats — Minimum, maximum, average

Minimum, maximum and time-weighted average of a value, for the current period and the previous one.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | The value |
| in | `bInGood` | `BOOL` | `TRUE` | its health; FALSE: samples skipped |
| in | `bEnable` | `BOOL` | `TRUE` | collect while TRUE |
| in | `bRollover` | `BOOL R_EDGE` |  | close the period Acts on its rising edge. |
| in | `bReset` | `BOOL R_EDGE` |  | clear both periods Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_StatsData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fMinimum` | `REAL` |  | current period |
| out | `fMaximum` | `REAL` |  | Highest value |
| out | `fAverage` | `REAL` |  | the current period |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StatsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetStats` | `BOOL` |  | clear the current and previous period (cleared; a held write acts once) |

**Settings `set`** (`ST_StatsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fIgnoreBelow` | `REAL` |  | values below this are left out (0 = off) |
| `fIgnoreAbove` | `REAL` |  | values above this are left out (0 = off) |

**Status `sts`** (`ST_StatsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMinimum` | `REAL` |  | current period (0 while no samples) |
| `fMaximum` | `REAL` |  | Highest value |
| `fAverage` | `REAL` |  | time-weighted |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Totals `tot`** (`ST_StatsTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stCur` | `ST_StatsCur` |  | fields below |
| `stPrev` | `ST_StatsPrev` |  | fields below |

**`stCur`** (`ST_StatsCur`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMin` | `REAL` |  | Lowest value allowed |
| `fMax` | `REAL` |  | Highest value allowed |
| `fSum` | `LREAL` |  | value x milliseconds |
| `fComp` | `LREAL` |  | Kahan compensation |
| `nSamples` | `UDINT` |  | Samples counted |
| `tDuration` | `TIME` |  | time collected |
| `tMinAt` | `TIME` |  | time into the period of the minimum |
| `tMaxAt` | `TIME` |  |  |
| `tElapsed` | `TIME` |  | time since the period started |

**`stPrev`** (`ST_StatsPrev`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fMin` | `REAL` |  | Lowest value allowed |
| `fMax` | `REAL` |  | Highest value allowed |
| `fAverage` | `REAL` |  | the current period |
| `tDuration` | `TIME` |  |  |
| `nSamples` | `UDINT` |  | Samples counted |

## How it works

Minimum, maximum and time-weighted average of a value, for the current period and the previous one.

Each scan the value read now stands for the time since the previous scan (time-weighted: the same result at any scan rate). Only samples taken while `bEnable` and `bInGood`, that are numbers and not left out by `set.fIgnoreBelow` / `fIgnoreAbove`, count. `bRollover` closes the period: `tot.stCur` moves to `tot.stPrev`. `bReset` / `bCmdResetStats` clears both. tot is kept hourly and at each rollover / reset; the sum is LREAL with compensated (Kahan) summation; `nSamples` saturates at the UDINT maximum. The record's sts carries the live summary only; the previous period, sample count, duration and the times of the extremes are read from tot. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Daily minimum, maximum and average of a pressure (SCADA closes the period).

| Pin | Wire |
| --- | --- |
| `fIn` | `fbPressure.fValue` |
| `bInGood` | `fbPressure.bGood` |
| `bEnable` | TRUE |
| `bRollover` | a pulse from SCADA |
| `refData` | `stPressStats` |

**Back to** [the index](../README.md).
