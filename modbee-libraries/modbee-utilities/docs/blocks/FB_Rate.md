# FB_Rate — Rate of change

The rate of change of a value (a least-squares trend), with rising-fast and falling-fast warnings.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value |
| in | `bInputGood` | `BOOL` | `TRUE` | its health; FALSE: fRate held |
| in | `bRestartMeasurement` | `BOOL` |  | restart the measurement |
| in | `refData` | `REFERENCE TO ST_RateData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fRate` | `REAL` |  | change per set.eRateUnit |
| out | `bGood` | `BOOL` |  | a full window of good readings, settings valid |
| out | `bRisingFast` | `BOOL` |  | fRate > fRisingFastAbove (after tAlarmDelay) |
| out | `bFallingFast` | `BOOL` |  | fRate < -fFallingFastAbove (after tAlarmDelay) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RateData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdRestartMeasurement` | `BOOL` |  | restart the measurement, clear bSettingRefused (cleared by the block) |

**Settings `set`** (`ST_RateSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eRateUnit` | `E_RateUnit` | `E_RateUnit.PerMin` | fRate is change per second, minute, hour or day |
| `tRateWindow` | `TIME` | `T#10s` | rate measured over this window (0 = off) |
| `tFilterTime` | `TIME` |  | smooths fRate (low-pass time constant), 0 = none |
| `fRisingFastAbove` | `REAL` |  | bRisingFast above this rate (0 = off) |
| `fFallingFastAbove` | `REAL` |  | bFallingFast when falling faster than this (0 = off) |
| `tAlarmDelay` | `TIME` | `T#5s` | the rate must stay past a limit this long |

**Status `sts`** (`ST_RateSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRate` | `REAL` |  | the rate, per unit |
| `bRisingFast` | `BOOL` |  | rising faster than fRisingFastAbove |
| `bFallingFast` | `BOOL` |  | falling faster than fFallingFastAbove |
| `bWindowFull` | `BOOL` |  | a full window of good readings has been measured |
| `bInputNotGood` | `BOOL` |  | fIn not usable now: fRate held |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

Rate of change, with rising-fast and falling-fast warnings.

`fRate` is the slope of the best straight line through the readings of the last `set.tRateWindow` (a least-squares trend), so noise largely cancels. To keep the memory small at any task interval, the window is kept as ten slices of `tRateWindow` / 10: each slice holds the average reading and the average time of its readings, and the line is fitted through the last nine whole slices and the one being filled. A steady ramp gives exactly its rate at any task interval, even with only a few scans in the window. `fRate` is updated every scan and is 0 until a full window has been measured after a start, a reset or a change of window (`sts.bWindowFull`). A step of S shows as a bump (peak about 1.7 x S / window) lasting about one window. `set.tFilterTime` smooths `fRate` further (a low-pass, 63 % in `tFilterTime`). `tRateWindow` 0 = off.

`bRisingFast`: `fRate` above `set.fRisingFastAbove` for `set.tAlarmDelay`; `bFallingFast`: `fRate` below -`set.fFallingFastAbove` for `tAlarmDelay`; a limit of 0 is off. Both clear as soon as the rate is back within the limit; both are warnings (RateHigh / RateLow).

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to the next scan. A NaN or infinite `fIn`, or `bInputGood` FALSE, is ignored: `fRate` holds, a warning (SensorBad), and the time it lasted does not count. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Warn when the reservoir level falls faster than 0.2 m/h.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbResLevel.fValue` |
| `bInputGood` | `fbResLevel.bGood` |
| `refData` | `stRate` |
| `bFallingFast` | a lamp |

**Back to** [the index](../README.md).
