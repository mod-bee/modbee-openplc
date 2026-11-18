# FB_Annunciator — Alarm horn and lamp

The horn, alarm lamp and first-out for a group of FB_Alarm blocks.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bAck` | `BOOL R_EDGE` |  | acknowledge all (panel button) Acts on its rising edge. |
| in | `bSilence` | `BOOL R_EDGE` |  | silence the horn without acknowledging Acts on its rising edge. |
| in | `bLampTest` | `BOOL` |  | lamp and horn on while held |
| in | `refData` | `REFERENCE TO ST_AnnunciatorData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aAlarm` | `ARRAY[*] OF ST_AlarmData` |  | The group's FB_Alarm records (one element per FB_Alarm, its `refData`) |
| out | `bHorn` | `BOOL` |  | The horn |
| out | `bLamp` | `BOOL` |  | The alarm lamp (fast flash new, slow flash returned, steady acknowledged) |
| out | `bAnyActive` | `BOOL` |  | An alarm is present |
| out | `bAnyUnacked` | `BOOL` |  | An alarm waits for acknowledgement |
| out | `nFirstOut` | `INT` |  | the alarm that started this event, 1 = the first element; 0 none |
| out | `eHighest` | `E_AlarmPriority` |  | the highest priority present |
| out | `nActive` | `INT` |  | Alarms present |
| out | `bHealthy` | `BOOL` |  | fail-safe relay: no Trip alarm present |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnnunciatorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdAck` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdSilence` | `BOOL` |  |  |

**Settings `set`** (`ST_AnnunciatorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eHornPriority` | `E_AlarmPriority` | `E_AlarmPriority.Low` | only alarms at or above this sound the horn |
| `tHornTimeout` | `TIME` |  | the horn stops by itself after this (0 = never) |
| `tReHorn` | `TIME` |  | sound again after this while still unacknowledged (0 = off) |
| `tFastFlash` | `TIME` | `T#250ms` |  |
| `tSlowFlash` | `TIME` | `T#1s` |  |
| `bRelayOnWarning` | `BOOL` |  | bHealthy drops for a warning alarm too |

**Status `sts`** (`ST_AnnunciatorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nFirstOut` | `INT` |  |  |
| `nActive` | `INT` |  |  |
| `nUnacked` | `INT` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Rows `ST_AlarmData` (pin `aAlarm`)

`aAlarm` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_AlarmData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdAck` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |
| `bCmdShelve` | `BOOL` |  | Shelve for `tShelveFor` (HMI command) |
| `bCmdUnshelve` | `BOOL` |  | Unshelve (HMI command) |
| `bCmdOutOfService` | `BOOL` |  | Take out of service (HMI command) |
| `bCmdInService` | `BOOL` |  | Back in service (HMI command) |
| `bCmdResetCount` | `BOOL` |  | Clear the counts (HMI command) |
| `bGrpAck` | `BOOL` |  | written only by FB_Annunciator |
| `set` | `ST_AlarmSettings` |  | fields below |
| `sts` | `ST_AlarmSts` |  | fields below |
| `det` | `ST_AlarmDet` |  | fields below |

**`set`** (`ST_AlarmSettings`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stRow` | `ST_AlarmSet` |  | as an FB_AlarmTable row; fields below |
| `bLatch` | `BOOL` |  | The output stays on until acknowledged after the condition cleared |
| `bAckRequired` | `BOOL` | `TRUE` | FALSE: an event that never needs acknowledging |
| `ePriority` | `E_AlarmPriority` | `E_AlarmPriority.Medium` | `Low`, `Medium`, `High` or `Critical` |
| `tMaxShelve` | `TIME` | `T#8h` | 0 = shelving not allowed |
| `tShelveFor` | `TIME` |  | 0 = tMaxShelve |
| `tRetryWindow` | `TIME` | `T#1h` | Retry: from the first raise (0 = until a reset) |

**`stRow`** (`ST_AlarmSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eResponse` | `E_Response` | `E_Response.Warn` | Off, Warn or Trip (Signal acts as Warn) |
| `eReset` | `E_ResetMode` | `E_ResetMode.Auto` | `Auto`, `Manual` or `Retry` (see conventions) |
| `tDelay` | `TIME` |  | the condition must last this long |
| `tRecover` | `TIME` |  | and be gone this long |
| `nMaxRetries` | `USINT` | `3` | Retry: raises in the window before it locks out (0..7) |
| `bSiren` | `BOOL` | `TRUE` | This one sounds the siren |
| `tRearm` | `TIME` |  | 0 = never |
| `eCode` | `E_UtError` | `E_UtError.ConditionOut` | what it is (the project's; not kept) |

**`sts`** (`ST_AlarmSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eIsaState` | `E_IsaState` |  | The ISA-18.2 state (status) |
| `bActive` | `BOOL` |  | Active now |
| `bUnacked` | `BOOL` |  | Not yet acknowledged |
| `bQ` | `BOOL` |  | The output |
| `nCount` | `UDINT` |  | Count |
| `tLastDuration` | `TIME` |  |  |
| `nSequence` | `UDINT` |  | when it was last raised (ms), orders the first-out |
| `dtRaisedAt` | `DT` |  | Clock time it was raised (blank without `dtClock`) |
| `dtAckedAt` | `DT` |  | Clock time it was acknowledged |
| `dtClearedAt` | `DT` |  | Clock time the condition cleared |
| `eCode` | `E_UtError` |  | Which alarm it is (an `E_UtError` code; the HMI shows its words) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**`det`** (`ST_AlarmDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tShelvedFor` | `TIME` |  | shelve time left |

## Lists

- `E_AlarmPriority`: `Low`, `Medium`, `High`, `Critical` (default `Low`)
- `E_IsaState`: `Normal`, `Unacked`, `Acked`, `RtnUnacked`, `Shelved`, `Suppressed`, `OutOfService`, `Latched`, `Locked` (default `Normal`)

## How it works

Horn, alarm lamp and first-out for a group of `FB_Alarms`. `aAlarm` is the project's array of the group's alarm records (each [`FB_Alarm`](FB_Alarm.md) has one element as its `refData`). The lamp follows the standard annunciator sequence: fast flash a new alarm not yet acknowledged; slow flash an alarm that cleared before it was acknowledged; steady alarms present, all acknowledged; off nothing ([`F_Blink`](F_Blink.md): every lamp in step). The horn sounds for each new alarm at or above `set.eHornPriority`, until an acknowledge, a silence, `set.tHornTimeout`, or nothing at that priority is left to acknowledge; `set.tReHorn` sounds it again while such an alarm stays unacknowledged. `bAck` acknowledges every alarm in the group (on each alarm's next call). `bLampTest`: lamp and horn on while held. `nFirstOut` is the alarm that started the current event (the earliest `sts.nSequence`; 1 = the first element, 0 = none); the event ends when no alarm is present or waiting for acknowledgement. Shelved, suppressed and out-of-service alarms are left out. `bHealthy`: no Trip alarm present (`set.bRelayOnWarning`: none at all).

## Example

The horn and lamp for a group of FB_Alarm blocks. Declare `aAlarms : ARRAY[1..10] OF ST_AlarmData`, one element per FB_Alarm.

| Pin | Wire |
| --- | --- |
| `bAck` | `DI_AckPB` |
| `bSilence` | `DI_SilencePB` |
| `aAlarm` | `aAlarms` |
| `refData` | `stAnn` |
| `bHorn` | `DO_Horn` |
| `bLamp` | `DO_AlarmLamp` |

**Back to** [the index](../README.md).
