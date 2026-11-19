# FB_Starts — Starts limit, anti-cycling (a part)

Anti-cycling for a motor or pump: a maximum number of starts per window and a minimum time between starts. A start that would break a limit waits; a running motor is never stopped.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipOwner` | `I_PartOwner` |  | required: the motor or pump. An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `bStartFailed` | `BOOL` |  | a start attempt failed (its rising edge starts the wait set.tWaitAfterFailedStart) |
| in | `refData` | `REFERENCE TO ST_StartsData` |  | the block's record |
| in | `stConfig` | `ST_StartsConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bStartHeld` | `BOOL` |  | a start is held back by a limit |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_StartsData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearRefused` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_StartsSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nMaxStartsPerWindow` | `INT` |  | starts per window (0 = no limit, 1..60) |
| `tMinTimeBetweenStarts` | `TIME` |  | shortest time from one start to the next |
| `tWaitAfterFailedStart` | `TIME` |  | wait after a failed start (0 = none) |

**Status `sts`** (`ST_StartsSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStartCountInWindow` | `INT` |  | starts counted in the window, rounded up |
| `tStartHeldTimeLeft` | `TIME` |  | until a start is allowed |
| `bStartHeld` | `BOOL` |  | a start is waiting |
| `bWaitingAfterFailedStart` | `BOOL` |  | the wait after a failed start is running |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Constants `ST_StartsConfig` (pin `stConfig`)

**Fields** (`ST_StartsConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tStartsWindow` | `TIME` | `T#1h` | the sliding window (0 < tStartsWindow <= 8 h) |

Set once, at the variable's declaration (engineering constants, not changed while running).

## How it works

Anti-cycling for a motor or pump, as a part of its owner ([`FB_Motor`](FB_Motor.md), [`FB_Pump`](FB_Pump.md) ...).

- Starts per window (`set.nMaxStartsPerWindow`, 0 = no limit, 1..60) and a minimum time between starts (`set.tMinTimeBetweenStarts`, 0 = none). A start is the owner's run command coming on (Evaluate's `bOwnerRunCommand`); a command already on at power-up is not a start.
- After a failed start (`bStartFailed` rises) the next start waits `set.tWaitAfterFailedStart` (0 = no wait) so a fault is not retried at once; it counts from the failure. A failed start is not a start in the window. `bCmdClearRefused` ends the wait.
- A start that would break a limit waits (`E_PartAction.HoldStart`: the owner makes no new start, never a trip); a running owner is never stopped by it.
- The sliding window without a history: every start adds one window's worth to a load that drains at `nMaxStartsPerWindow` windows per window; a start is allowed while the load leaves room for one more. The load is not retained (only the settings are): after a power cut the count starts again.
- Status: `sts.nStartCountInWindow` (the load in starts, rounded up), `sts.tStartHeldTimeLeft` (until a start is allowed).

Its rung stopping while it holds a start is PartLost on its owner.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

At most 6 starts an hour for pump 1.

| Pin | Wire |
| --- | --- |
| `ipOwner` | `fbPump1` |
| `refData` | `stStarts1` |
| `bStartHeld` | a lamp |

Set `stStarts1.set.nMaxStartsPerWindow := 6`.

**Back to** [the index](../README.md).
