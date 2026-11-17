# FB_SettingArray — Setting write gates for a list

FB_SettingCheck for a list of project values, one row each; the values are kept over a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aItem` | `ARRAY[*] OF ST_SettingItem` |  | the project's table, VAR_IN_OUT, at most 32 kept |
| out | `bAccepted` | `BOOL` |  | one scan: a request was taken |
| out | `bRefused` | `BOOL` |  | one scan: a request was refused |
| out | `bAnyBad` | `BOOL` |  | A value in use fails its checks now |
| out | `nRefusedItem` | `INT` |  | the last refused item (0 = none since power-up) |
| out | `eRefusedId` | `E_UtError` |  | until its next accepted write |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Rows `ST_SettingItem` (pin `aItem`)

`aItem` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_SettingItem`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | the value in use (kept) |
| `fMin` | `REAL` | `REAL#-3.4E38` | Lowest value allowed |
| `fMax` | `REAL` | `REAL#3.4E38` | Highest value allowed |
| `nAbove` | `INT` |  | must be above this item's value (position; 0 = none) |
| `nBelow` | `INT` |  | must be below this item's value (position; 0 = none) |
| `fRequest` | `REAL` |  | the value wanted: checked when it changes |
| `bCmdCheck` | `BOOL` |  | check the request again even if unchanged (cleared by the block) |
| `bRefused` | `BOOL` |  | the last request was refused (until one is accepted) |
| `bBad` | `BOOL` |  | the value in use fails the checks now |
| `eRefusedId` | `E_UtError` |  | until its next accepted write |
| `fSeen` | `REAL` |  | the request as last read |

## How it works

[`FB_SettingCheck`](FB_SettingCheck.md) for a list of project values. `aItem` (the project's table, VAR_IN_OUT, at most 32 kept): each row holds the value in use (`fValue`: the project reads it), its limits `fMin` / `fMax` and the items it must be above / below (`nAbove` / `nBelow`: their POSITION in the table, 1 = the first element, 0 = none), the value wanted (`fRequest`: the HMI / SCADA writes it) and `bCmdCheck`.

Each time an item's `fRequest` changes (or on `bCmdCheck`) it is checked against its limits and the related items: passed, `fValue` := `fRequest`; failed, `fValue` is kept, the row shows `bRefused` / `eRefusedId` (until its next accepted write), and the block's `nRefusedItem` / `eRefusedId` say which. Items are checked in table order, so two related items changed in one scan check the later one against the earlier one's new value. Nothing is checked on the first scan (requests are only read). `bBad`: an item's value itself fails the checks now (written past the check, or a related item moved); `bError` BadSetting then.

Kept over a power cut by the block: each item's `fValue` (the first 32). The limits and relations are the project's configuration (set at the declaration), not kept.

## Example

Four project setpoints. Declare `aSet : ARRAY[1..4] OF ST_SettingItem` with their limits.

| Pin | Wire |
| --- | --- |
| `aItem` | `aSet` |
| `bRefused` | a lamp |

The HMI writes `aSet[i].fRequest`; the project reads `aSet[i].fValue`.

**Back to** [the index](../README.md).
