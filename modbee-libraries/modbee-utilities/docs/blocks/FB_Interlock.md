# FB_Interlock — Interlock conditions

All the conditions that must be healthy before a device may run, as one `bPermissive`, with first-out and maintenance bypasses.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bBypassKeyOn` | `BOOL` | `FALSE` | key switch / HMI permission for bypasses |
| in | `bResetFaults` | `BOOL R_EDGE` |  | clear the first-out and the held conditions |
| in | `refData` | `REFERENCE TO ST_IntlkData` |  | the interlock's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aConditionSettings` | `ARRAY[*] OF ST_IntlkCondSet` |  | each condition's settings (same size as aCondition) |
| in-out | `aConditions` | `ARRAY[*] OF ST_IntlkCond` |  | each condition's live row; the project writes aConditions[i].bConditionMet |
| out | `bPermissive` | `BOOL` |  | all OK or bypassed -> the device's bInterlock / bPermissive |
| out | `nFirstOutCondition` | `INT` |  | the first condition out since the reset (1-based; 0 = none) |
| out | `nConditionsNotMet` | `INT` |  | conditions not OK now |
| out | `bBypassInEffect` | `BOOL` |  | a bypass in effect (show it!) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IntlkData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | as bResetFaults (cleared by the block; a held write acts once) |

**Settings `set`** (`ST_IntlkSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tBypassEndsAfter` | `TIME` | `T#8h` | 0 = never drops out |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | Retry conditions |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry counts trips within this window (0 = until a reset) |

**Status `sts`** (`ST_IntlkSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bPermissive` | `BOOL` |  | all conditions OK or bypassed |
| `nFirstOutCondition` | `INT` |  | the first condition out since the reset (1-based; 0 = none) |
| `bBypassInEffect` | `BOOL` |  | a bypass is in effect |
| `nConditionsNotMet` | `INT` |  | conditions not OK now |
| `nTripCount` | `UDINT` |  | times bPermissive went FALSE (not kept) |
| `tTimeLeft` | `TIME` |  | the shortest delay left of a condition about to count (0 = none) |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_IntlkCondSet` (pin `aConditionSettings`)

`aConditionSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IntlkCondSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTripDelay` | `TIME` |  | must be not OK this long to count |
| `eResetMode` | `E_ResetMode` | `E_ResetMode.Auto` | Auto, Manual (held until reset) or Retry |
| `bBypassAllowed` | `BOOL` |  | a bypass may be asked for this condition |

## Rows `ST_IntlkCond` (pin `aConditions`)

`aConditions` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IntlkCond`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bConditionMet` | `BOOL` | `TRUE` | the live condition (the project's rung) |
| `bBypassRequest` | `BOOL` |  | the bypass request (HMI; never kept) |
| `bNotMetNow` | `BOOL` |  | not OK now (before the delay) |
| `bTripped` | `BOOL` |  | counts against bConditionMet |
| `bLatched` | `BOOL` |  | held until a reset |
| `bBypassInEffect` | `BOOL` |  | the bypass is in effect |
| `nRetriesUsed` | `INT` |  | trips counted in the current retry window |
| `tWentNotMetAt` | `TIME` |  | engine memory: when it went not OK (TIME()) |
| `tBypassStartedAt` | `TIME` |  | engine memory: when the bypass started |
| `tRetryWindowStartedAt` | `TIME` |  | engine memory: when the retry window started |
| `bBypassLastScan` | `BOOL` |  | engine memory: the bypass request on the last scan |
| `bWentNotMetThisScan` | `BOOL` |  | went out this scan |
| `tTripDelayTimeLeft` | `TIME` |  | not OK, before tTripDelay: the time left until it counts (0 otherwise) |
| `tBypassedFor` | `TIME` |  | bypassed so far (0 when not) |
| `tBypassTimeLeft` | `TIME` |  | bypassed: the time left before it drops out (0: none, or no timeout) |

## How it works

The conditions that must all be healthy before a device may run, as one `bPermissive` signal (-> the device's `bInterlock` or `bPermissive`), with first-out and maintenance bypasses.

Each condition: `tTripDelay` (must be not OK this long to count); `eResetMode` Auto (OK again as soon as healthy), Manual (held until a reset while healthy: pull cords, e-stops) or Retry (by itself while healthy, at most `set.nMaxRetriesBeforeLockout` times in `set.tRetryCountWindow`, then held); a bypass (its `bBypassRequest`, only when `bBypassAllowed`, while `bBypassKeyOn`, for at most `set.tBypassEndsAfter`, 0 = never drops out; once timed out it stays off until the request or `bBypassKeyOn` goes). `nFirstOutCondition`: the condition that went out first (same scan: the lowest); after a reset with conditions still out, the lowest of those. A reset acts in the same scan.

Errors: `bError` for no rows, tables of different sizes or more than 16 rows, or settings that were never good (BadSetting); `bWarning` for a bypass (Bypassed) or a refused write (SettingRefused). Not OK is the block's job, not an error: `eState` Held, `eErrorId` ConditionOut.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bSettingRefused` / `eSettingRefusedErrorId`): set, and each condition row packed into one DWORD: bits 0..1 `eResetMode`, 2 `bBypassAllowed`, 3..31 `tTripDelay` in 10 ms steps (0 .. about 62 days; kept rounded down to 10 ms).

Times: each row shows `tTripDelayTimeLeft` (not OK, until it counts), `tBypassedFor` / `tBypassTimeLeft` (a bypass so far / until it drops out); `sts.tTimeLeft` is the shortest delay left.

## Example

A conveyor's pull cords and guard. Declare `aIlkSet : ARRAY[1..3] OF ST_IntlkCondSet` and `aIlk : ARRAY[1..3] OF ST_IntlkCond`.

| Pin | Wire |
| --- | --- |
| `bBypassKeyOn` | `DI_BypassKey` |
| `bResetFaults` | `DI_ResetPB` |
| `aConditionSettings` | `aIlkSet` |
| `aConditions` | `aIlk` |
| `refData` | `stIlk` |
| `bPermissive` | the conveyor motor's `bInterlock` |

Each condition on its own rung: a coil on `aIlk[1].bPermissive` from `DI_PullCord1`.

**Back to** [the index](../README.md).
