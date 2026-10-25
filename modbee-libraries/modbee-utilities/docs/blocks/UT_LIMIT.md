# UT_LIMIT — Four independent alarm levels (HH / H / L / LL)

Checks a value against up to four levels. **Each level is fully independent**: its
own setpoint, deadband, delay, response (off / warning / trip) and reset mode
(auto-recover, retry or latch). Each has its own output, so you can use HH alone,
treat L as a warning only, or latch LL but let HH recover by itself. Each level
works as a [UT_LEVEL_CHECK](UT_LEVEL_CHECK.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | The value (e.g. `UT_ANALOG_IN.Value`) |
| in | `Inhibit` | BOOL | FALSE | Suppress all levels (start-up, maintenance) |
| in | `Reset` | BOOL | FALSE | Rising edge: clear MANUAL levels whose condition has gone |
| out | `HiHi` | BOOL | | High-high in effect |
| out | `Hi` | BOOL | | High in effect |
| out | `Lo` | BOOL | | Low in effect |
| out | `LoLo` | BOOL | | Low-low in effect |
| out | `Trip` | BOOL | | Any level whose response is TRIP is in effect |
| out | `Warning` | BOOL | | Any level whose response is WARN is in effect, or `wrnConfig` |
| inout | `Data` | UT_LIMIT_DATA | | |

## Record `UT_LIMIT_DATA`
Four [`UT_LEVEL`](UT_LEVEL_CHECK.md#record-ut_level)s: `hiHi`, `hi`, `lo`, `loLo`.

| Default | `hiHi` | `hi` | `lo` | `loLo` |
| --- | --- | --- | --- | --- |
| `sp` | 90 | 80 | 20 | 10 |
| `response` | TRIP | WARN | WARN | TRIP |
| `reset` | AUTO | AUTO | AUTO | AUTO |
| `delay` | 2 s | 2 s | 2 s | 2 s |
| `deadband` | 1.0 | 1.0 | 1.0 | 1.0 |
| `recover` / `maxRetries` | 10 s / 3 | 10 s / 3 | 10 s / 3 | 10 s / 3 |

Each level's status: `active`, `tripped`, `retries`, `count`, `timeLeft`.

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `retryWindow` | TIME | T#1h | RETRY counts trips within this window |
| `cmdReset` | BOOL | | HMI: as the `Reset` pin (acts once, on its rising edge; cleared by the block) |
| `value` | REAL | | Status: the value checked |
| `inhibited` | BOOL | | Status: `Inhibit` is on |
| `wrnBadInput` | BOOL | | Status: the value is NaN or infinite; every level holds its state |
| `orderCheck` | BOOL | TRUE | Check the setpoint order HH > H > L > LL among the levels in use |
| `wrnConfig` | BOOL | | Status: setpoints out of order, or a level's setting invalid |
| `activeLevel` | INT | | Status: the most severe level in effect: 0 none, 1 HH, 2 H, 3 L, 4 LL |
| `timeLeft` | TIME | | Status: the countdown the status shows (a level's delay, or a recover / retry wait) |
| `statusCode` | UT_STATUS | | Status: what it is doing (codes below) |
| `faultId` | UT_FAULT | | Status: the level the status is about (`UT_F_HIGH_HIGH`, `UT_F_HIGH`, `UT_F_LOW`, `UT_F_LOW_LOW`), the bad value or the setting; `UT_F_NONE` when none |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Latched: high-high` |

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers); `statusText` is the two in words.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OK` | `UT_F_NONE` | `OK` | No level in effect, nothing counting |
| `UT_ST_OK` | the level | `OK` | A level's delay is counting (the most severe one: HH, LL, H, L); `timeLeft` shows it |
| `UT_ST_INHIBITED` | | `Blocked: inhibit` | `Inhibit` is on |
| `UT_ST_WARNING` | `UT_F_VALUE_BAD` | `Warning: value not a number` | `wrnBadInput`: every level holds its state |
| `UT_ST_WARNING` | the level | `Warning: high` | A level set to WARN is in effect |
| `UT_ST_WARN_SETTING` | `UT_F_SP_ORDER` | `Setting: setpoint order` | `orderCheck` found the setpoints out of order |
| `UT_ST_WARN_SETTING` | `UT_F_LEVEL_SETTING` | `Setting: a level` | A level's setpoint, deadband or times are invalid, or a negative `retryWindow` |
| `UT_ST_FAULT` | the level | `Fault: high-high` | A TRIP level in effect, AUTO reset (`timeLeft`: the recover still to go) |
| `UT_ST_FAULT_RETRY` | the level | `Retrying: high-high` | RETRY, retries left (the level's `retries`; `timeLeft`: the wait) |
| `UT_ST_FAULT_LOCKED` | the level | `Locked: high-high` | RETRY, retries used up: reset needed |
| `UT_ST_FAULT_RESET` | the level | `Latched: high-high` | MANUAL: reset needed |

A trip comes first, then inhibited, a warning, a bad value, the settings, a delay
counting, OK.

## How it works
- High levels are beyond above `sp` and clear below `sp - deadband`; low levels are
  beyond below `sp` and clear above `sp + deadband`. Exactly at `sp` is not beyond.
- Response and reset work as [UT_PROTECT](UT_PROTECT.md): a WARN follows the
  condition (MANUAL: until reset), a TRIP clears `recover` after the condition has
  gone (AUTO / RETRY) or on a reset once it has gone (MANUAL). A reset while the
  condition is still present is refused.
- `Inhibit` treats every condition as absent: AUTO levels clear after `recover`, a
  latched MANUAL level stays latched but can now be reset.
- **Setpoint order** (`orderCheck`, on by default): of the levels in use (response
  not OFF), HH must be above H, H above L and L above LL, and any high level above
  any low level. Out of order sets `wrnConfig` and `Warning` (`UT_ST_WARN_SETTING`); the levels
  still act as set, each only looking at its own setpoint. `orderCheck` FALSE turns
  the check off for a deliberate odd order.
- `activeLevel` is the most severe level in effect (HH, then LL, H, L), for an HMI
  colour or a SCADA alarm class.
- `count` lives in your record: declare the record `RETAIN` to keep it.

## Using it
HH as a latched trip, L as a warning, nothing else:
```iecst
PressLimCfg.hi.response := UT_RESP_OFF;   PressLimCfg.loLo.response := UT_RESP_OFF;
PressLimCfg.hiHi.reset  := UT_RST_MANUAL;              (* set once, or from the HMI *)
PressLim(In := Press.Value, Data := PressLimCfg);
```
