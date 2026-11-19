# FB_AlarmTable — Panel alarm table

All of a panel's alarms in one block, one row each, with the fault and warning lamps, the beacon, the siren and the healthy relay.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSilenceHorn` | `BOOL R_EDGE` |  | rising edge: silence the horn |
| in | `bResetFaults` | `BOOL R_EDGE` |  | acknowledge all; clear latched / locked rows whose condition has gone |
| in | `bLampTest` | `BOOL` |  | held: every lamp and the horn on |
| in | `refData` | `REFERENCE TO ST_AlarmTableData` |  | the table's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aAlarmSettings` | `ARRAY[*] OF ST_AlarmSet` |  | each alarm's settings (same size as aAlarm, at most 32) |
| in-out | `aAlarms` | `ARRAY[*] OF ST_Alarm` |  | each alarm's live row; the project writes aAlarm[i].bConditionPresent |
| out | `bFaultLamp` | `BOOL` |  | fault lamp: fast flash new, slow flash cleared, steady acknowledged |
| out | `bWarningLamp` | `BOOL` |  | warning lamp: fast flash new, slow flash cleared, steady acknowledged |
| out | `bBeacon` | `BOOL` |  | the beacon output |
| out | `bHorn` | `BOOL` |  | the horn output |
| out | `bFailSafeRelay` | `BOOL` |  | the common alarm relay (fail-safe) |
| out | `nAlarmsActive` | `INT` |  | rows on now |
| out | `bAlarmsChanged` | `BOOL` |  | one scan: an alarm came, went or was acknowledged |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AlarmTableData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdSilenceHorn` | `BOOL` |  | cleared by the block |
| `bCmdResetFaults` | `BOOL` |  | cleared by the block |

**Settings `set`** (`ST_AlarmTableSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bBeaconOnWarning` | `BOOL` | `TRUE` | warnings light the beacon too |
| `bRelayDropsOnWarning` | `BOOL` |  | warnings drop the fail-safe relay (bFailSafeRelay) too |
| `tHornStopsAfter` | `TIME` |  | 0 = until silenced |
| `tFastFlash` | `TIME` | `T#250ms` | lamp flash period for a new alarm |
| `tSlowFlash` | `TIME` | `T#1s` | lamp flash period for an alarm that has cleared but is not acknowledged |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry rows: from the first raise (0 = until a reset) |

**Status `sts`** (`ST_AlarmTableSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nTopAlarmRow` | `INT` |  | the first trip (lowest row), else the first warning (0 none) |
| `nLatestAlarmRow` | `INT` |  | the row raised last |
| `nFirstOutRow` | `INT` |  | the first row raised since the last reset |
| `eTopAlarmCode` | `E_UtError` |  | alarm code of nTopAlarmRow |
| `eLatestAlarmCode` | `E_UtError` |  | alarm code of nLatestAlarmRow |
| `nAlarmsActive` | `INT` |  | rows on now |
| `nTripsActive` | `INT` |  | rows on now that are trips |
| `nAlarmsUnacknowledged` | `INT` |  | rows waiting to be acknowledged |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_AlarmSet` (pin `aAlarmSettings`)

`aAlarmSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_AlarmSet`)

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

## Rows `ST_Alarm` (pin `aAlarms`)

`aAlarms` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Alarm`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bConditionPresent` | `BOOL` |  | the condition (the project's rung) |
| `eRowState` | `E_AlarmState` |  | the engine's state: Normal, Active, Latched, Locked |
| `bAlarmOn` | `BOOL` |  | on: Active, Latched or Locked |
| `bUnacknowledged` | `BOOL` |  | an alarm is waiting to be acknowledged |
| `nRetriesUsed` | `INT` |  | trips counted in the current retry window |
| `bConditionConfirmed` | `BOOL` |  | the condition after the delays |
| `bConditionLastScan` | `BOOL` |  | engine memory: the condition on the last scan |
| `bSilenced` | `BOOL` |  | silenced: the horn stays off for this alarm |
| `tConditionChangedAt` | `TIME` |  | when bConditionPresent last changed |
| `tRetryWindowStartedAt` | `TIME` |  | when the retry window started |
| `tSilencedOrAcknowledgedAt` | `TIME` |  | when it was silenced or acknowledged |
| `bCallsForHorn` | `BOOL` |  | it calls for the horn now |

## Lists

- `E_AlarmState`: `Normal`, `Active`, `Returned`, `Latched`, `Locked`, `Off` (default `Normal`)

## How it works

The site's on-panel alarms in one block, with the lamps, the beacon, the siren and the healthy relay. Optional: alarm lists, history and notifications are the HMI / SCADA's; the blocks detect and act without this.

Each row: `eActionOnFault` Off / Warn / Trip; the condition after `tTripDelay` (on) and `tAutoRecoverAfter` (off); `eResetMode` Auto (clears itself), Manual (latches until a reset with the condition gone), Retry (clears itself, locks out after `nMaxRetriesBeforeLockout` raises within `set.tRetryCountWindow`); `bHorn`; `tReAlarmAfter` (silenced or acknowledged but still on after this long: it annunciates again; 0 = never); `eAlarmCode` (the HMI's text for it; the project's, set at the declaration).

The row number is the alarm's number for the HMI. Bad times act as 0 (louder, never quieter).

Kept (a retained last-good copy, restored at power-up, a bad write put back, `sts.bSettingRefused` / `eSettingRefusedErrorId`): set, and each row's settings but `eAlarmCode` packed into two DWORDs for the first 32 rows (`tTripDelay` in 10 ms steps up to 46 h, `tAutoRecoverAfter` in 100 ms steps up to 109 min, `tReAlarmAfter` in seconds up to 18 h, `nMaxRetriesBeforeLockout` 0..7). Nothing else is kept: a condition still present raises again after a power cut. `bAlarmsChanged` is TRUE for one scan when an alarm comes, goes or is acknowledged (counts or the latest row change).

## Example

Eight panel alarms. Declare `aAlmSet : ARRAY[1..8] OF ST_AlarmSet` and `aAlm : ARRAY[1..8] OF ST_Alarm`.

| Pin | Wire |
| --- | --- |
| `bSilenceHorn` | `DI_SilencePB` |
| `bResetFaults` | `DI_ResetPB` |
| `bLampTest` | `DI_LampTestPB` |
| `aAlarmSettings` | `aAlmSet` |
| `aAlarms` | `aAlm` |
| `refData` | `stAlarms` |
| `bFaultLamp` | `DO_FaultLamp` |
| `bHorn` | `DO_Siren` |
| `bFailSafeRelay` | `DO_Healthy` |

Each alarm's condition goes on its own rung: a coil on `aAlm[1].bConditionPresent` from `fbPump1.bError`, and so on.

## See also

[FB_Alarm](FB_Alarm.md), [FB_Annunciator](FB_Annunciator.md), [FB_AlarmBeacon](FB_AlarmBeacon.md)

**Back to** [the index](../README.md).
