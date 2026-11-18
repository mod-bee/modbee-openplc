# FB_Interlock — Interlock conditions

All the conditions that must be healthy before a device may run, as one `bOk`, with first-out and maintenance bypasses.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bBypassEnable` | `BOOL` | `FALSE` | key switch / HMI permission for bypasses |
| in | `bReset` | `BOOL R_EDGE` |  | clear the first-out and the held conditions Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_IntlkData` |  | set, sts |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aCondSet` | `ARRAY[*] OF ST_IntlkCondSet` |  | each condition's settings |
| in-out | `aCond` | `ARRAY[*] OF ST_IntlkCond` |  | each condition's live row: the project writes aCond[i].bOk on the condition's own rung, the HMI aCond[i].bBypass |
| out | `bOk` | `BOOL` |  | all OK or bypassed -> the device's bInterlock / bPermissive |
| out | `nFirstOut` | `INT` |  | the first condition out since the reset (1-based; 0 = none) |
| out | `nNotOk` | `INT` |  | Conditions not OK now |
| out | `bBypassed` | `BOOL` |  | a bypass in effect (show it!) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IntlkData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | as bReset (cleared by the block; a held write acts once) |

**Settings `set`** (`ST_IntlkSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tBypassTimeout` | `TIME` | `T#8h` | 0 = never drops out |
| `nMaxRetries` | `INT` | `3` | Retry conditions |
| `tRetryWindow` | `TIME` | `T#1h` | Retry protections count their trips within this window |

**Status `sts`** (`ST_IntlkSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bOk` | `BOOL` |  | all healthy or bypassed |
| `nFirstOut` | `INT` |  | the first condition to stop the device since the last reset, 1-based; 0 = none |
| `bBypassed` | `BOOL` |  | a bypass in effect: show it |
| `nNotOk` | `INT` |  |  |
| `nTrips` | `UDINT` |  | times bOk went FALSE (not kept) |
| `tTimeLeft` | `TIME` |  | the shortest delay left of a condition about to count (0 = none) |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Rows `ST_IntlkCondSet` (pin `aCondSet`)

`aCondSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IntlkCondSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tDelay` | `TIME` |  | must be not OK this long to count |
| `eReset` | `E_ResetMode` | `E_ResetMode.Auto` | Auto, Manual (held until reset) or Retry |
| `bBypassAllowed` | `BOOL` |  | a bypass may be asked for this condition |

## Rows `ST_IntlkCond` (pin `aCond`)

`aCond` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IntlkCond`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bOk` | `BOOL` | `TRUE` | the live condition (the project's rung) |
| `bBypass` | `BOOL` |  | the bypass request (HMI; never kept) |
| `bBad` | `BOOL` |  | not OK now (before the delay) |
| `bTripped` | `BOOL` |  | counts against bOk |
| `bLatched` | `BOOL` |  | held until a reset |
| `bBypassed` | `BOOL` |  | a bypass in effect: show it |
| `nRetries` | `INT` |  | Trips counted in the retry window |
| `tBadSince` | `TIME` |  |  |
| `tBypassAt` | `TIME` |  |  |
| `tWindowAt` | `TIME` |  |  |
| `bBypassOn` | `BOOL` |  |  |
| `bWentBad` | `BOOL` |  | went out this scan |
| `tDelayLeft` | `TIME` |  | not OK, before tDelay: the time left until it counts (0 otherwise) |
| `tBypassFor` | `TIME` |  | bypassed so far (0 when not) |
| `tBypassLeft` | `TIME` |  | bypassed: the time left before it drops out (0: none, or no timeout) |

## How it works

The conditions that must all be healthy before a device may run, as one `bOk` signal (-> the device's `bInterlock` or `bPermissive`), with first-out and maintenance bypasses.

Each condition: `tDelay` (must be not OK this long to count); `eReset` Auto (OK again as soon as healthy), Manual (held until a reset while healthy: pull cords, e-stops) or Retry (by itself while healthy, at most `set.nMaxRetries` times in `set.tRetryWindow`, then held); a bypass (its `bBypass`, only when `bBypassAllowed`, while `bBypassEnable`, for at most `set.tBypassTimeout`, 0 = never drops out; once timed out it stays off until the request or `bBypassEnable` goes). `nFirstOut`: the condition that went out first (same scan: the lowest); after a reset with conditions still out, the lowest of those. A reset acts in the same scan.

Errors: `bError` for no rows, tables of different sizes or more than 16 rows, or settings that were never good (BadSetting); `bWarning` for a bypass (Bypassed) or a refused write (SettingRefused). Not OK is the block's job, not an error: `eState` Held, `eErrorId` ConditionOut.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bRefused` / `eRefusedWhy`): set, and each condition row packed into one DWORD: bits 0..1 `eReset`, 2 `bBypassAllowed`, 3..31 `tDelay` in 10 ms steps (0 .. about 62 days; kept rounded down to 10 ms).

Times: each row shows `tDelayLeft` (not OK, until it counts), `tBypassFor` / `tBypassLeft` (a bypass so far / until it drops out); `sts.tTimeLeft` is the shortest delay left.

## Example

A conveyor's pull cords and guard. Declare `aIlkSet : ARRAY[1..3] OF ST_IntlkCondSet` and `aIlk : ARRAY[1..3] OF ST_IntlkCond`.

| Pin | Wire |
| --- | --- |
| `bBypassEnable` | `DI_BypassKey` |
| `bReset` | `DI_ResetPB` |
| `aCondSet` | `aIlkSet` |
| `aCond` | `aIlk` |
| `refData` | `stIlk` |
| `bOk` | the conveyor motor's `bInterlock` |

Each condition on its own rung: a coil on `aIlk[1].bOk` from `DI_PullCord1`.

**Back to** [the index](../README.md).
