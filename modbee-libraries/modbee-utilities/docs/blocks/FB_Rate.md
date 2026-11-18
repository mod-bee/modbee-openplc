# FB_Rate — Rate of change

The rate of change of a value (a least-squares trend), with rising-fast and falling-fast warnings.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fIn` | `REAL` |  | the value |
| in | `bInGood` | `BOOL` | `TRUE` | its health; FALSE: fRate held |
| in | `bReset` | `BOOL` |  | restart the measurement |
| in | `refData` | `REFERENCE TO ST_RateData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fRate` | `REAL` |  | change per set.eUnit |
| out | `bGood` | `BOOL` |  | a full window of good readings, settings valid |
| out | `bRisingFast` | `BOOL` |  | fRate > fRiseLimit (after tAlarmDelay) |
| out | `bFallingFast` | `BOOL` |  | fRate < -fFallLimit (after tAlarmDelay) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RateData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | restart the measurement, clear bRefused (cleared by the block) |

**Settings `set`** (`ST_RateSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eUnit` | `E_RateUnit` | `E_RateUnit.PerMin` | fRate is change per second, minute, hour or day |
| `tWindow` | `TIME` | `T#10s` | rate measured over this window (0 = off) |
| `tFilter` | `TIME` |  | smooths fRate (low-pass time constant), 0 = none |
| `fRiseLimit` | `REAL` |  | bRisingFast above this rate (0 = off) |
| `fFallLimit` | `REAL` |  | bFallingFast when falling faster than this (0 = off) |
| `tAlarmDelay` | `TIME` | `T#5s` | the rate must stay past a limit this long |

**Status `sts`** (`ST_RateSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRate` | `REAL` |  | the rate, per unit |
| `bRisingFast` | `BOOL` |  |  |
| `bFallingFast` | `BOOL` |  |  |
| `bReady` | `BOOL` |  | a full window of good readings has been measured |
| `bBadInput` | `BOOL` |  | fIn not usable now: fRate held |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## How it works

Rate of change, with rising-fast and falling-fast warnings.

`fRate` is the slope of the best straight line through the readings of the last `set.tWindow` (a least-squares trend), so noise largely cancels. To keep the memory small at any task interval, the window is kept as ten slices of `tWindow` / 10: each slice holds the average reading and the average time of its readings, and the line is fitted through the last nine whole slices and the one being filled. A steady ramp gives exactly its rate at any task interval, even with only a few scans in the window. `fRate` is updated every scan and is 0 until a full window has been measured after a start, a reset or a change of window (`sts.bReady`). A step of S shows as a bump (peak about 1.7 x S / window) lasting about one window. `set.tFilter` smooths `fRate` further (a low-pass, 63 % in `tFilter`). `tWindow` 0 = off.

`bRisingFast`: `fRate` above `set.fRiseLimit` for `set.tAlarmDelay`; `bFallingFast`: `fRate` below -`set.fFallLimit` for `tAlarmDelay`; a limit of 0 is off. Both clear as soon as the rate is back within the limit; both are warnings (RateHigh / RateLow).

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to the next scan. A NaN or infinite `fIn`, or `bInGood` FALSE, is ignored: `fRate` holds, a warning (SensorBad), and the time it lasted does not count. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

Warn when the reservoir level falls faster than 0.2 m/h.

| Pin | Wire |
| --- | --- |
| `fIn` | `fbResLevel.fValue` |
| `bInGood` | `fbResLevel.bGood` |
| `refData` | `stRate` |
| `bFallingFast` | a lamp |

**Back to** [the index](../README.md).
