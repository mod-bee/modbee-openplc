# FB_Alarm — One ISA-18.2 alarm

One alarm as its own block, the ISA-18.2 way: shelving, suppression, out of service, priority and time stamps. Use FB_Annunciator for the group's horn and lamp.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | the condition |
| in | `eCause` | `E_UtError` |  | what it is now (None = set.stRow.eCode) |
| in | `bInhibit` | `BOOL` |  | suppressed by design |
| in | `bAck` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bReset` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `dtClock` | `DT` | `DT#1970-01-01-00:00:00` | a real-time clock (optional); unwired: the times stay blank |
| in | `refData` | `REFERENCE TO ST_AlarmData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bQ` | `BOOL` |  | to annunciate |
| out | `bUnacked` | `BOOL` |  | Not yet acknowledged |
| out | `bActive` | `BOOL` |  | the condition now (after the delays) |
| out | `eCode` | `E_UtError` |  | Which alarm it is (an `E_UtError` code; the HMI shows its words) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_AlarmData` (pin `refData`)

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

**Settings `set`** (`ST_AlarmSettings`)

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

**Status `sts`** (`ST_AlarmSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eIsaState` | `E_IsaState` |  | The ISA-18.2 state (status) |
| `bActive` | `BOOL` |  | the condition after the delays |
| `bUnacked` | `BOOL` |  | Not yet acknowledged |
| `bQ` | `BOOL` |  | annunciate |
| `nCount` | `UDINT` |  | Count |
| `tLastDuration` | `TIME` |  |  |
| `nSequence` | `UDINT` |  | when it was last raised (ms), orders the first-out |
| `dtRaisedAt` | `DT` |  | Clock time it was raised (blank without `dtClock`) |
| `dtAckedAt` | `DT` |  | Clock time it was acknowledged |
| `dtClearedAt` | `DT` |  | Clock time the condition cleared |
| `eCode` | `E_UtError` |  | Which alarm it is (an `E_UtError` code; the HMI shows its words) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Details `det`** (`ST_AlarmDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tShelvedFor` | `TIME` |  | shelve time left |

## Lists

- `E_AlarmPriority`: `Low`, `Medium`, `High`, `Critical` (default `Low`)
- `E_IsaState`: `Normal`, `Unacked`, `Acked`, `RtnUnacked`, `Shelved`, `Suppressed`, `OutOfService`, `Latched`, `Locked` (default `Normal`)

## How it works

One alarm as its own block, the ISA-18.2 way. Optional: alarm lists, history and notifications are the HMI / SCADA's. [`FB_AlarmTable`](FB_AlarmTable.md) is the lean choice for a panel's alarms; this block adds shelving, suppression, out of service, priorities, time stamps and the group annunciator ([`FB_Annunciator`](FB_Annunciator.md)).

The condition is `bIn` (wire a device's `bError` or `bWarning`); `eCause` names it (wire the device's `eErrorId`; None = `set.stRow.eCode`). `F_AlarmRun` does the rest as an [`FB_AlarmTable`](FB_AlarmTable.md) row: on / off delays (`stRow.tDelay` / `tRecover`), Auto / Manual (latched until a reset with the condition gone) / Retry (locks out after `stRow.nMaxRetries` raises within `set.tRetryWindow`), acknowledge, re-arm. `sts.eIsaState`: Normal, Unacked, Acked, RtnUnacked, Shelved (`bCmdShelve`, for `set.tShelveFor`, at most `set.tMaxShelve`), Suppressed (`bInhibit`), OutOfService (`bCmdOutOfService`), Latched, Locked. A shelved, suppressed or out-of-service alarm still present comes back as a new one. `set.bLatch`: `bQ` stays on until acknowledged after the condition cleared; `set.bAckRequired` FALSE: an event that never needs acknowledging. `bAck` / `bCmdAck` / `bGrpAck` (from [`FB_Annunciator`](FB_Annunciator.md)) acknowledge; `bReset` / `bCmdReset` acknowledge and clear a latched / locked alarm whose condition has gone. `dtRaisedAt` / `dtAckedAt` / `dtClearedAt` from `dtClock` (optional; unwired: blank - the boards have no real-time clock, the SCADA stamps on arrival); `sts.nSequence` (ms) orders the first-out. HMI commands act once per write.

Settings are kept (a retained last-good copy, a bad write put back).

## Example

A high-high level alarm with shelving.

| Pin | Wire |
| --- | --- |
| `bIn` | `fbLevelCtl.bHighHigh` |
| `refData` | `aAlarms[1]` (an element of the group's array) |

FB_Annunciator reads the same array.

## See also

[FB_Annunciator](FB_Annunciator.md), [FB_AlarmTable](FB_AlarmTable.md)

**Back to** [the index](../README.md).
