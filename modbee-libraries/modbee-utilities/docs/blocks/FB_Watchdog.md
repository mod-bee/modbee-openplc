# FB_Watchdog — Heartbeat watchdog

Watches a heartbeat or counter from the other end of a link, and makes one for it to watch.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bHeartbeatIn` | `BOOL` |  | heartbeat bit from the remote (any change counts) |
| in | `nCounterIn` | `DINT` |  | or a counter / register from the remote (any change counts) |
| in | `bEnable` | `BOOL` | `TRUE` | works only while TRUE |
| in | `bResetFaults` | `BOOL R_EDGE` |  | reset a held failure (Manual) |
| in | `refData` | `REFERENCE TO ST_WatchdogData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bAlive` | `BOOL` |  | remote alive |
| out | `bCommsFail` | `BOOL` |  | no change for tHeartbeatTimeout |
| out | `bHeartbeatOut` | `BOOL` |  | toggles every tHeartbeatInterval; send this to the remote |
| out | `nHeartbeatCount` | `DINT` |  | counts up every tHeartbeatInterval |
| out | `bHeartbeatReceived` | `BOOL` |  | one scan: the remote's beat changed |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_WatchdogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a held failure (cleared by the block; a held write acts once) |
| `bCmdResetCounters` | `BOOL` |  | clear the failure count and down time (as bCmdResetFaults) |

**Settings `set`** (`ST_WatchdogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tHeartbeatTimeout` | `TIME` | `T#90s` | no change for this long = link dead |
| `tHeartbeatInterval` | `TIME` | `T#30s` | bHeartbeatOut toggles every tHeartbeatInterval (T#0s = off) |
| `stCommsFailFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#0s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 3)` | the link-lost protection (default Trip, Auto reset, no delay); tAutoRecoverAfter = alive this long before bAlive returns; a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_WatchdogSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bAlive` | `BOOL` |  | the remote is alive |
| `bCommsFail` | `BOOL` |  | no change for tHeartbeatTimeout |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stCommsFailFault` | `ST_ProtectionSts` |  | nTripCount: failures since bCmdResetCounters; a protection's status ([protections](../conventions.md#protections)) |

**Details `det`** (`ST_WatchdogDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tSinceLastHeard` | `TIME` |  | time since the remote last changed |
| `tTotalOutageTime` | `TIME` |  | total time the link was dead |

## How it works

Comms / heartbeat monitor and generator.

Watches a value that should keep changing (a remote PLC's heartbeat, a Modbus register, an MQTT message counter). When neither `bHeartbeatIn` nor `nCounterIn` has changed for `set.tHeartbeatTimeout` the link is dead: `bCommsFail`, `bError`, LinkLost. The failure is a protection trip ([`F_Protect`](F_Protect.md)) with `set.stCommsFailFault.eResetMode`:

```
  Auto    clears once the link has been alive set.stCommsFailFault.tAutoRecoverAfter
  Retry   as Auto, three times an hour, then as Manual
  Manual  stays until a reset (bResetFaults, bCmdResetFaults) with the link alive; a reset while it is dead is refused
```

`bAlive` is on while the link is alive and has been for `set.stCommsFailFault.tAutoRecoverAfter` (so it is off at start until the first change). `bHeartbeatOut` toggles and `nHeartbeatCount` counts up every `set.tHeartbeatInterval`, for the other side to watch; they keep going when `bEnable` is off. `sts.stCommsFailFault.nTripCount` (failures) and `det.tTotalOutageTime` (time dead, from the timeout to the next change) are not kept over a power cut; `bCmdResetCounters` clears both. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. `bHeartbeatReceived` is TRUE for one scan at each change of the remote's beat.

## Example

Watch the SCADA heartbeat register.

| Pin | Wire |
| --- | --- |
| `nCounterIn` | `nScadaHeartbeat` |
| `bEnable` | TRUE |
| `refData` | `stWd` |
| `bCommsFail` | a lamp |
| `bHeartbeatOut` | the bit SCADA watches |

**Back to** [the index](../README.md).
