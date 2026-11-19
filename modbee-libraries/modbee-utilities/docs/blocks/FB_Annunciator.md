# FB_Annunciator — Alarm horn and lamp

The horn, alarm lamp and first-out for a group of FB_Alarm blocks.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bAcknowledge` | `BOOL R_EDGE` |  | acknowledge all (panel button) |
| in | `bSilenceHorn` | `BOOL R_EDGE` |  | silence the horn without acknowledging |
| in | `bLampTest` | `BOOL` |  | lamp and horn on while held |
| in | `refData` | `REFERENCE TO ST_AnnunciatorData` |  | the annunciator's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aAlarms` | `ARRAY[*] OF ST_AlarmData` |  | the FB_Alarm records of the group |
| out | `bHorn` | `BOOL` |  | the horn output |
| out | `bLamp` | `BOOL` |  | the common alarm lamp output |
| out | `bAnyAlarmActive` | `BOOL` |  | any alarm present |
| out | `bAnyUnacknowledged` | `BOOL` |  | any alarm waiting to be acknowledged |
| out | `nFirstOutAlarm` | `INT` |  | the alarm that started this event, 1 = the first element; 0 none |
| out | `eHighestPriority` | `E_AlarmPriority` |  | the highest priority present |
| out | `nAlarmsActive` | `INT` |  | alarms present now |
| out | `bFailSafeRelay` | `BOOL` |  | fail-safe relay: no Trip alarm present |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AnnunciatorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdAcknowledge` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdSilenceHorn` | `BOOL` |  | HMI: silence the horn without acknowledging (acts once) |

**Settings `set`** (`ST_AnnunciatorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eHornFromPriority` | `E_AlarmPriority` | `E_AlarmPriority.Low` | only alarms at or above this sound the horn |
| `tHornStopsAfter` | `TIME` |  | the horn stops by itself after this (0 = never) |
| `tHornAgainAfter` | `TIME` |  | sound again after this while still unacknowledged (0 = off) |
| `tFastFlash` | `TIME` | `T#250ms` | lamp flash period for a new alarm |
| `tSlowFlash` | `TIME` | `T#1s` | lamp flash period for an alarm that has cleared but is not acknowledged |
| `bRelayDropsOnWarning` | `BOOL` |  | bFailSafeRelay drops for a warning alarm too |

**Status `sts`** (`ST_AnnunciatorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nFirstOutAlarm` | `INT` |  | the alarm that started this event (1 = first element; 0 = none) |
| `nAlarmsActive` | `INT` |  | alarms present now |
| `nAlarmsUnacknowledged` | `INT` |  | alarms waiting to be acknowledged |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_AlarmData` (pin `aAlarms`)

`aAlarms` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_AlarmData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdAcknowledge` | `BOOL` |  | HMI commands, once per write, cleared by the block |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `bCmdShelve` | `BOOL` |  | HMI: shelve the alarm for set.tShelveTime (acts once) |
| `bCmdUnshelve` | `BOOL` |  | HMI: end the shelving (acts once) |
| `bCmdOutOfService` | `BOOL` |  | HMI: take the alarm out of service (acts once) |
| `bCmdInService` | `BOOL` |  | HMI: put the alarm back in service (acts once) |
| `bCmdResetCounters` | `BOOL` |  | HMI: clear sts.nRaiseCount (acts once) |
| `bGroupAcknowledge` | `BOOL` |  | written only by FB_Annunciator |
| `set` | `ST_AlarmSettings` |  | settings (kept); fields below |
| `sts` | `ST_AlarmSts` |  | status; fields below |
| `det` | `ST_AlarmDet` |  | details; fields below |

**`set`** (`ST_AlarmSettings`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stRowSettings` | `ST_AlarmSet` |  | as an FB_AlarmTable row; fields below |
| `bLatchUntilAcknowledged` | `BOOL` |  | the output stays on until acknowledged after the condition cleared |
| `bAcknowledgeRequired` | `BOOL` | `TRUE` | FALSE: an event that never needs acknowledging |
| `ePriority` | `E_AlarmPriority` | `E_AlarmPriority.Medium` | Low, Medium, High or Urgent: the annunciator's horn level |
| `tMaxShelveTime` | `TIME` | `T#8h` | 0 = shelving not allowed |
| `tShelveTime` | `TIME` |  | 0 = tMaxShelveTime |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry: from the first raise (0 = until a reset) |

**`stRowSettings`** (`ST_AlarmSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActionOnFault` | `E_Response` | `E_Response.Warn` | Off, Warn or Trip (Signal acts as Warn) |
| `eResetMode` | `E_ResetMode` | `E_ResetMode.Auto` | how it clears: Auto, Manual (held until a reset) or Retry (locks out after too many) |
| `tTripDelay` | `TIME` |  | the condition must last this long |
| `tAutoRecoverAfter` | `TIME` |  | and be gone this long |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | Retry: raises in the window before it locks out (0..7) |
| `bSoundsHorn` | `BOOL` | `TRUE` | this alarm sounds the horn |
| `tReAlarmAfter` | `TIME` |  | 0 = never |
| `eAlarmCode` | `E_UtError` | `E_UtError.ConditionOut` | what it is (the project's; not kept) |

**`sts`** (`ST_AlarmSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eAlarmState` | `E_IsaState` |  | ISA-18.2 state: Normal, Unacked, Acked, RtnUnacked, Shelved, Suppressed, OutOfService, Latched, Locked |
| `bConditionActive` | `BOOL` |  | the condition now, after the delays |
| `bUnacknowledged` | `BOOL` |  | an alarm is waiting to be acknowledged |
| `bAlarmOn` | `BOOL` |  | the alarm annunciates now |
| `nRaiseCount` | `UDINT` |  | times raised since the count was cleared |
| `tLastAlarmDuration` | `TIME` |  | how long the last alarm lasted |
| `nRaisedAtMs` | `UDINT` |  | when it was last raised (ms), orders the first-out |
| `dtRaisedAt` | `DT` |  | when it was last raised (blank without a clock) |
| `dtAcknowledgedAt` | `DT` |  | when it was last acknowledged (blank without a clock) |
| `dtClearedAt` | `DT` |  | when it last cleared (blank without a clock) |
| `eAlarmCode` | `E_UtError` |  | which alarm is shown now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**`det`** (`ST_AlarmDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tShelveTimeLeft` | `TIME` |  | shelve time left |

## Lists

- `E_AlarmPriority`: `Low`, `Medium`, `High`, `Critical` (default `Low`)
- `E_IsaState`: `Normal`, `Unacked`, `Acked`, `RtnUnacked`, `Shelved`, `Suppressed`, `OutOfService`, `Latched`, `Locked` (default `Normal`)

## How it works

Horn, alarm lamp and first-out for a group of `FB_Alarms`. `aAlarms` is the project's array of the group's alarm records (each [`FB_Alarm`](FB_Alarm.md) has one element as its `refData`). The lamp follows the standard annunciator sequence: fast flash a new alarm not yet acknowledged; slow flash an alarm that cleared before it was acknowledged; steady alarms present, all acknowledged; off nothing ([`F_Blink`](F_Blink.md): every lamp in step). The horn sounds for each new alarm at or above `set.eHornFromPriority`, until an acknowledge, a silence, `set.tHornStopsAfter`, or nothing at that priority is left to acknowledge; `set.tHornAgainAfter` sounds it again while such an alarm stays unacknowledged. `bAcknowledge` acknowledges every alarm in the group (on each alarm's next call). `bLampTest`: lamp and horn on while held. `nFirstOutAlarm` is the alarm that started the current event (the earliest `sts.nRaisedAtMs`; 1 = the first element, 0 = none); the event ends when no alarm is present or waiting for acknowledgement. Shelved, suppressed and out-of-service alarms are left out. `bFailSafeRelay`: no Trip alarm present (`set.bRelayDropsOnWarning`: none at all).

## Example

The horn and lamp for a group of FB_Alarm blocks. Declare `aAlarms : ARRAY[1..10] OF ST_AlarmData`, one element per FB_Alarm.

| Pin | Wire |
| --- | --- |
| `bAcknowledge` | `DI_AckPB` |
| `bSilenceHorn` | `DI_SilencePB` |
| `aAlarms` | `aAlarms` |
| `refData` | `stAnn` |
| `bHorn` | `DO_Horn` |
| `bLamp` | `DO_AlarmLamp` |

**Back to** [the index](../README.md).
