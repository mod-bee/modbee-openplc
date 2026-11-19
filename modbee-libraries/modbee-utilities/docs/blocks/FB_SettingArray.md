# FB_SettingArray — Setting write gates for a list

FB_SettingCheck for a list of project values, one row each; the values are kept over a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aItems` | `ARRAY[*] OF ST_SettingItem` |  | the project's table of settings (at most 32 kept) |
| out | `bRequestAccepted` | `BOOL` |  | one scan: a request was taken |
| out | `bRequestRefused` | `BOOL` |  | one scan: a request was refused |
| out | `bAnyValueBad` | `BOOL` |  | a value in use fails its checks now |
| out | `nRefusedItem` | `INT` |  | the last refused item (0 = none since power-up) |
| out | `eRefusedReason` | `E_UtError` |  | why the last request was refused (None after an accepted one) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Rows `ST_SettingItem` (pin `aItems`)

`aItems` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SettingItem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValueInUse` | `REAL` |  | the value in use (kept) |
| `fLowestAllowed` | `REAL` | `REAL#-3.4E38` | lowest value allowed |
| `fHighestAllowed` | `REAL` | `REAL#3.4E38` | highest value allowed |
| `nMustBeAboveItem` | `INT` |  | must be above this item's value (position; 0 = none) |
| `nMustBeBelowItem` | `INT` |  | must be below this item's value (position; 0 = none) |
| `fRequestedValue` | `REAL` |  | the value wanted: checked when it changes |
| `bCmdCheckNow` | `BOOL` |  | check the request again even if unchanged (cleared by the block) |
| `bRequestRefused` | `BOOL` |  | the last request was refused (until one is accepted) |
| `bValueBad` | `BOOL` |  | the value in use fails the checks now |
| `eRefusedReason` | `E_UtError` |  | why the last request was refused (until the next accepted write) |
| `fRequestLastRead` | `REAL` |  | the request as last read |

## How it works

[`FB_SettingCheck`](FB_SettingCheck.md) for a list of project values. `aItems` (the project's table, VAR_IN_OUT, at most 32 kept): each row holds the value in use (`fValueInUse`: the project reads it), its limits `fLowestAllowed` / `fHighestAllowed` and the items it must be above / below (`nMustBeAboveItem` / `nMustBeBelowItem`: their POSITION in the table, 1 = the first element, 0 = none), the value wanted (`fRequestedValue`: the HMI / SCADA writes it) and `bCmdCheckNow`.

Each time an item's `fRequestedValue` changes (or on `bCmdCheckNow`) it is checked against its limits and the related items: passed, `fValueInUse` := `fRequestedValue`; failed, `fValueInUse` is kept, the row shows `bRequestRefused` / `eRefusedReason` (until its next accepted write), and the block's `nRefusedItem` / `eRefusedReason` say which. Items are checked in table order, so two related items changed in one scan check the later one against the earlier one's new value. Nothing is checked on the first scan (requests are only read). `bValueBad`: an item's value itself fails the checks now (written past the check, or a related item moved); `bError` BadSetting then.

Kept over a power cut by the block: each item's `fValueInUse` (the first 32). The limits and relations are the project's configuration (set at the declaration), not kept.

## Example

Four project setpoints. Declare `aSet : ARRAY[1..4] OF ST_SettingItem` with their limits.

| Pin | Wire |
| --- | --- |
| `aItems` | `aSet` |
| `bRequestRefused` | a lamp |

The HMI writes `aSet[i].fRequestedValue`; the project reads `aSet[i].fValueInUse`.

**Back to** [the index](../README.md).
