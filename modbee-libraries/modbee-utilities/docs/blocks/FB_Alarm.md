# FB_Alarm — One ISA-18.2 alarm

One alarm as its own block, the ISA-18.2 way: shelving, suppression, out of service, priority and time stamps. Use FB_Annunciator for the group's horn and lamp.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bConditionPresent` | `BOOL` |  | the condition |
| in | `eAlarmCodeNow` | `E_UtError` |  | what it is now (None = set.stRowSettings.eAlarmCode) |
| in | `bSuppress` | `BOOL` |  | suppressed by design |
| in | `bAcknowledge` | `BOOL R_EDGE` |  | rising edge: acknowledge |
| in | `bResetFaults` | `BOOL R_EDGE` |  | rising edge: acknowledge, and clear a latched or locked alarm whose condition has gone |
| in | `dtLocalTime` | `DT` | `DT#1970-01-01-00:00:00` | a real-time clock (optional); unwired: the times stay blank |
| in | `refData` | `REFERENCE TO ST_AlarmData` |  | the alarm's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bAlarmOn` | `BOOL` |  | to annunciate |
| out | `bUnacknowledged` | `BOOL` |  | an alarm is waiting to be acknowledged |
| out | `bConditionActive` | `BOOL` |  | the condition now (after the delays) |
| out | `eAlarmCode` | `E_UtError` |  | which alarm is shown now |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AlarmData` (pin `refData`)

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

**Settings `set`** (`ST_AlarmSettings`)

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

**Status `sts`** (`ST_AlarmSts`)

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

**Details `det`** (`ST_AlarmDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tShelveTimeLeft` | `TIME` |  | shelve time left |

## Lists

- `E_AlarmPriority`: `Low`, `Medium`, `High`, `Critical` (default `Low`)
- `E_IsaState`: `Normal`, `Unacked`, `Acked`, `RtnUnacked`, `Shelved`, `Suppressed`, `OutOfService`, `Latched`, `Locked` (default `Normal`)

## How it works

One alarm as its own block, the ISA-18.2 way. Optional: alarm lists, history and notifications are the HMI / SCADA's. [`FB_AlarmTable`](FB_AlarmTable.md) is the lean choice for a panel's alarms; this block adds shelving, suppression, out of service, priorities, time stamps and the group annunciator ([`FB_Annunciator`](FB_Annunciator.md)).

The condition is `bConditionPresent` (wire a device's `bError` or `bWarning`); `eAlarmCodeNow` names it (wire the device's `eErrorId`; None = `set.stRowSettings.eAlarmCode`). `F_AlarmRun` does the rest as an [`FB_AlarmTable`](FB_AlarmTable.md) row: on / off delays (`stRowSettings.tTripDelay` / `tAutoRecoverAfter`), Auto / Manual (latched until a reset with the condition gone) / Retry (locks out after `stRowSettings.nMaxRetriesBeforeLockout` raises within `set.tRetryCountWindow`), acknowledge, re-arm. `sts.eAlarmState`: Normal, Unacked, Acked, RtnUnacked, Shelved (`bCmdShelve`, for `set.tShelveTime`, at most `set.tMaxShelveTime`), Suppressed (`bSuppress`), OutOfService (`bCmdOutOfService`), Latched, Locked. A shelved, suppressed or out-of-service alarm still present comes back as a new one. `set.bLatchUntilAcknowledged`: `bAlarmOn` stays on until acknowledged after the condition cleared; `set.bAcknowledgeRequired` FALSE: an event that never needs acknowledging. `bAcknowledge` / `bCmdAcknowledge` / `bGroupAcknowledge` (from [`FB_Annunciator`](FB_Annunciator.md)) acknowledge; `bResetFaults` / `bCmdResetFaults` acknowledge and clear a latched / locked alarm whose condition has gone. `dtRaisedAt` / `dtAcknowledgedAt` / `dtClearedAt` from `dtLocalTime` (optional; unwired: blank - the boards have no real-time clock, the SCADA stamps on arrival); `sts.nRaisedAtMs` (ms) orders the first-out. HMI commands act once per write.

Settings are kept (a retained last-good copy, a bad write put back).

## Example

A high-high level alarm with shelving.

| Pin | Wire |
| --- | --- |
| `bConditionPresent` | `fbLevelCtl.bHighHigh` |
| `refData` | `aAlarms[1]` (an element of the group's array) |

FB_Annunciator reads the same array.

## See also

[FB_Annunciator](FB_Annunciator.md), [FB_AlarmTable](FB_AlarmTable.md)

**Back to** [the index](../README.md).
