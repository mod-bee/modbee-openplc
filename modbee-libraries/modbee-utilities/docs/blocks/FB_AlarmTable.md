# FB_AlarmTable — Panel alarm table

All of a panel's alarms in one block, one row each, with the fault and warning lamps, the beacon, the siren and the healthy relay.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSilence` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bReset` | `BOOL R_EDGE` |  | acknowledge all; clear latched / locked rows whose condition has gone Acts on its rising edge. |
| in | `bLampTest` | `BOOL` |  | Held: every lamp, the beacon and the siren on |
| in | `refData` | `REFERENCE TO ST_AlarmTableData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aAlarmSet` | `ARRAY[*] OF ST_AlarmSet` |  | The alarms' settings: one row per alarm (at most 32) |
| in-out | `aAlarm` | `ARRAY[*] OF ST_Alarm` |  | The alarms' live rows, the same size: the project writes `aAlarm[i].bIn` |
| out | `bFaultLamp` | `BOOL` |  | Trip alarms: fast flash new, slow flash returned, steady acknowledged |
| out | `bWarnLamp` | `BOOL` |  | Warning alarms: the same flashing |
| out | `bBeacon` | `BOOL` |  | The beacon |
| out | `bSiren` | `BOOL` |  | with set.tSirenTimeout; a new alarm sounds again |
| out | `bHealthy` | `BOOL` |  | the common alarm relay (fail-safe) |
| out | `nOn` | `INT` |  | Alarms on now |
| out | `bChanged` | `BOOL` |  | one scan: an alarm came, went or was acknowledged |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AlarmTableData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdSilence` | `BOOL` |  | cleared by the block |
| `bCmdReset` | `BOOL` |  | cleared by the block |

**Settings `set`** (`ST_AlarmTableSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bBeaconWarnings` | `BOOL` | `TRUE` | warnings light the beacon too |
| `bRelayOnWarning` | `BOOL` |  | warnings drop the healthy relay too |
| `tSirenTimeout` | `TIME` |  | 0 = until silenced |
| `tFastFlash` | `TIME` | `T#250ms` |  |
| `tSlowFlash` | `TIME` | `T#1s` |  |
| `tRetryWindow` | `TIME` | `T#1h` | Retry rows: from the first raise (0 = until a reset) |

**Status `sts`** (`ST_AlarmTableSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nFirst` | `INT` |  | the first trip (lowest row), else the first warning (0 none) |
| `nLatest` | `INT` |  | the row raised last |
| `nFirstOut` | `INT` |  | the first row raised since the last reset |
| `eFirstCode` | `E_UtError` |  |  |
| `eLatestCode` | `E_UtError` |  |  |
| `nOn` | `INT` |  |  |
| `nTrips` | `INT` |  |  |
| `nUnacked` | `INT` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Rows `ST_AlarmSet` (pin `aAlarmSet`)

`aAlarmSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_AlarmSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eResponse` | `E_Response` | `E_Response.Warn` | Off, Warn or Trip (Signal acts as Warn) |
| `eReset` | `E_ResetMode` | `E_ResetMode.Auto` | `Auto`, `Manual` or `Retry` (see conventions) |
| `tDelay` | `TIME` |  | the condition must last this long |
| `tRecover` | `TIME` |  | and be gone this long |
| `nMaxRetries` | `USINT` | `3` | Retry: raises in the window before it locks out (0..7) |
| `bSiren` | `BOOL` | `TRUE` | with set.tSirenTimeout; a new alarm sounds again |
| `tRearm` | `TIME` |  | 0 = never |
| `eCode` | `E_UtError` | `E_UtError.ConditionOut` | what it is (the project's; not kept) |

## Rows `ST_Alarm` (pin `aAlarm`)

`aAlarm` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Alarm`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bIn` | `BOOL` |  | the condition (the project's rung) |
| `eState` | `E_AlarmState` |  | What it is doing now (status) |
| `bQ` | `BOOL` |  | on: Active, Latched or Locked |
| `bUnacked` | `BOOL` |  | Not yet acknowledged |
| `nRetries` | `USINT` |  | Trips counted in the retry window |
| `bCond` | `BOOL` |  | the condition after the delays |
| `bInPrev` | `BOOL` |  |  |
| `bSilenced` | `BOOL` |  |  |
| `tChange` | `TIME` |  | when bIn last changed |
| `tWin` | `TIME` |  | when the retry window started |
| `tAck` | `TIME` |  | when it was silenced or acknowledged |
| `bSounding` | `BOOL` |  | it calls for the siren now |

## Lists

- `E_AlarmState`: `Normal`, `Active`, `Returned`, `Latched`, `Locked`, `Off` (default `Normal`)

## How it works

The site's on-panel alarms in one block, with the lamps, the beacon, the siren and the healthy relay. Optional: alarm lists, history and notifications are the HMI / SCADA's; the blocks detect and act without this.

Each row: `eResponse` Off / Warn / Trip; the condition after `tDelay` (on) and `tRecover` (off); `eReset` Auto (clears itself), Manual (latches until a reset with the condition gone), Retry (clears itself, locks out after `nMaxRetries` raises within `set.tRetryWindow`); `bSiren`; `tRearm` (silenced or acknowledged but still on after this long: it annunciates again; 0 = never); `eCode` (the HMI's text for it; the project's, set at the declaration).

The row number is the alarm's number for the HMI. Bad times act as 0 (louder, never quieter).

Kept (a retained last-good copy, restored at power-up, a bad write put back, `sts.bRefused` / `eRefusedWhy`): set, and each row's settings but `eCode` packed into two DWORDs for the first 32 rows (`tDelay` in 10 ms steps up to 46 h, `tRecover` in 100 ms steps up to 109 min, `tRearm` in seconds up to 18 h, `nMaxRetries` 0..7). Nothing else is kept: a condition still present raises again after a power cut. `bChanged` is TRUE for one scan when an alarm comes, goes or is acknowledged (counts or the latest row change).

## Example

Eight panel alarms. Declare `aAlmSet : ARRAY[1..8] OF ST_AlarmSet` and `aAlm : ARRAY[1..8] OF ST_Alarm`.

| Pin | Wire |
| --- | --- |
| `bSilence` | `DI_SilencePB` |
| `bReset` | `DI_ResetPB` |
| `bLampTest` | `DI_LampTestPB` |
| `aAlarmSet` | `aAlmSet` |
| `aAlarm` | `aAlm` |
| `refData` | `stAlarms` |
| `bFaultLamp` | `DO_FaultLamp` |
| `bSiren` | `DO_Siren` |
| `bHealthy` | `DO_Healthy` |

Each alarm's condition goes on its own rung: a coil on `aAlm[1].bIn` from `fbPump1.bError`, and so on.

## See also

[FB_Alarm](FB_Alarm.md), [FB_Annunciator](FB_Annunciator.md), [FB_AlarmBeacon](FB_AlarmBeacon.md)

**Back to** [the index](../README.md).
