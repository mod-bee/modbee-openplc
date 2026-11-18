# FB_Watchdog — Heartbeat watchdog

Watches a heartbeat or counter from the other end of a link, and makes one for it to watch.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bBeat` | `BOOL` |  | heartbeat bit from the remote (any change counts) |
| in | `nCounter` | `DINT` |  | or a counter / register from the remote (any change counts) |
| in | `bEnable` | `BOOL` | `TRUE` | Works only while TRUE |
| in | `bReset` | `BOOL R_EDGE` |  | reset a held failure (Manual) Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_WatchdogData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bOk` | `BOOL` |  | remote alive |
| out | `bCommsFail` | `BOOL` |  | no change for tTimeout |
| out | `bHeartbeatOut` | `BOOL` |  | toggles every tBeatPeriod; send this to the remote |
| out | `nHeartbeatCount` | `DINT` |  | counts up every tBeatPeriod |
| out | `bNewBeat` | `BOOL` |  | one scan: the remote's beat changed |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_WatchdogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a held failure (cleared by the block; a held write acts once) |
| `bCmdResetCount` | `BOOL` |  | clear the failure count and down time (as bCmdReset) |

**Settings `set`** (`ST_WatchdogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tTimeout` | `TIME` | `T#90s` | no change for this long = link dead |
| `tRecover` | `TIME` |  | alive this long before bOk returns (and Auto clears bCommsFail) |
| `tBeatPeriod` | `TIME` | `T#30s` | bHeartbeatOut toggles every tBeatPeriod (T#0s = off) |
| `eFailReset` | `E_ResetMode` | `E_ResetMode.Auto` |  |

**Status `sts`** (`ST_WatchdogSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bOk` | `BOOL` |  | remote alive |
| `bCommsFail` | `BOOL` |  |  |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stFail` | `ST_ProtectionSts` |  | nCount: failures since bCmdResetCount; a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_WatchdogDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tLastChange` | `TIME` |  | time since the remote last changed |
| `tDownTime` | `TIME` |  | total time the link was dead |

## How it works

Comms / heartbeat monitor and generator.

Watches a value that should keep changing (a remote PLC's heartbeat, a Modbus register, an MQTT message counter). When neither `bBeat` nor `nCounter` has changed for `set.tTimeout` the link is dead: `bCommsFail`, `bError`, LinkLost. The failure is a protection trip ([`F_Protect`](F_Protect.md)) with `set.eFailReset`:

```
  Auto    clears once the link has been alive set.tRecover
  Retry   as Auto, three times an hour, then as Manual
  Manual  stays until a reset (bReset, bCmdReset) with the link alive; a reset while it is dead is refused
```

`bOk` is on while the link is alive and has been for `tRecover` (so it is off at start until the first change). `bHeartbeatOut` toggles and `nHeartbeatCount` counts up every `set.tBeatPeriod`, for the other side to watch; they keep going when `bEnable` is off. `sts.stFail.nCount` (failures) and `det.tDownTime` (time dead, from the timeout to the next change) are not kept over a power cut; `bCmdResetCount` clears both. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. `bNewBeat` is TRUE for one scan at each change of the remote's beat.

## Example

Watch the SCADA heartbeat register.

| Pin | Wire |
| --- | --- |
| `nCounter` | `nScadaHeartbeat` |
| `bEnable` | TRUE |
| `refData` | `stWd` |
| `bCommsFail` | a lamp |
| `bHeartbeatOut` | the bit SCADA watches |

**Back to** [the index](../README.md).
