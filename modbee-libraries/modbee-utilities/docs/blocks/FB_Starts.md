# FB_Starts — Starts limit, anti-cycling (a part)

Anti-cycling for a motor or pump: a maximum number of starts per window and a minimum time between starts. A start that would break a limit waits; a running motor is never stopped.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the motor or pump. The owner's instance |
| in | `bStartFailed` | `BOOL` |  | a start attempt failed (its rising edge starts the wait set.tFailWait) |
| in | `refData` | `REFERENCE TO ST_StartsData` |  | Its record (a variable of this type) |
| in | `stConfig` | `ST_StartsConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bHolding` | `BOOL` |  | A start is held back by a limit |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StartsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_StartsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nMaxPerHour` | `INT` |  | starts per window (0 = no limit, 1..60) |
| `tMinBetween` | `TIME` |  | shortest time from one start to the next |
| `tFailWait` | `TIME` |  | wait after a failed start (0 = none) |

**Status `sts`** (`ST_StartsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStartsInHour` | `INT` |  | the load in starts, rounded up |
| `tWait` | `TIME` |  | until a start is allowed |
| `bHolding` | `BOOL` |  | a start is waiting |
| `bFailWaiting` | `BOOL` |  | the wait after a failed start is running |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |

## Constants `ST_StartsConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_StartsConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tWindow` | `TIME` | `T#1h` | the sliding window (0 < tWindow <= 8 h) |

## How it works

Anti-cycling for a motor or pump, as a part of its owner ([`FB_Motor`](FB_Motor.md), [`FB_Pump`](FB_Pump.md) ...).

- Starts per window (`set.nMaxPerHour`, 0 = no limit, 1..60) and a minimum time between starts (`set.tMinBetween`, 0 = none). A start is the owner's run command coming on (Evaluate's `bRunning`); a command already on at power-up is not a start.
- After a failed start (`bStartFailed` rises) the next start waits `set.tFailWait` (0 = no wait) so a fault is not retried at once; it counts from the failure. A failed start is not a start in the window. `bCmdReset` ends the wait.
- A start that would break a limit waits (`E_PartAction.HoldStart`: the owner makes no new start, never a trip); a running owner is never stopped by it.
- The sliding window without a history: every start adds one window's worth to a load that drains at `nMaxPerHour` windows per window; a start is allowed while the load leaves room for one more. The load is not retained (only the settings are): after a power cut the count starts again.
- Status: `sts.nStartsInHour` (the load in starts, rounded up), `sts.tWait` (until a start is allowed).

Its rung stopping while it holds a start is PartLost on its owner.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

At most 6 starts an hour for pump 1.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbPump1` |
| `refData` | `stStarts1` |
| `bHolding` | a lamp |

Set `stStarts1.set.nMaxPerHour := 6`.

**Back to** [the index](../README.md).
