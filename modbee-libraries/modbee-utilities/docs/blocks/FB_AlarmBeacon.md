# FB_AlarmBeacon — Alarm numbers on one lamp

Flashes alarm numbers on a single lamp, for sites with one fault lamp and no HMI.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | Works only while TRUE |
| in | `refData` | `REFERENCE TO ST_BeaconData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aAlarms` | `ARRAY[*] OF BOOL` |  | the project's array of BOOL, one per alarm; alarm number = index - lower bound + 1; write it with coils |
| out | `bLamp` | `BOOL` |  | The fault lamp: flashes the alarm numbers |
| out | `nCode` | `INT` |  | the alarm number being shown (0 = none) |
| out | `bActive` | `BOOL` |  | any alarm |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_BeaconData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nActive` | `INT` |  | status |
| `nCode` | `INT` |  | the number being shown, 0 = none |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_BeaconSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStyle` | `E_BeaconStyle` |  |  |
| `nBits` | `INT` | `6` | Binary: bits shown (1..15) |
| `tShort` | `TIME` | `T#250ms` | short flash (Count, and Binary 0) |
| `tLong` | `TIME` | `T#1s` | long flash (Binary 1) |
| `tGap` | `TIME` | `T#500ms` | lamp off between flashes |
| `tPause` | `TIME` | `T#3s` | lamp off between numbers |
| `bSteadyWhenNone` | `BOOL` |  |  |

## Lists

- `E_BeaconStyle`: `Count`, `Binary` (default `Count`)

## How it works

Flash alarm numbers on a single lamp, for sites with one fault lamp and no HMI. `aAlarms` (the project's array of BOOL, one per alarm; alarm number = index - lower bound + 1; write it with coils).

The block steps through every active alarm in turn (from the lowest after an idle spell, then round again) and flashes its number: Count (that many short flashes) or Binary (`set.nBits` flashes, most significant bit first: long = 1, short = 0; a number too big for `nBits` uses as many bits as it needs, up to 15). Flashes are separated by `tGap`, numbers by `tPause`. A number that has started is always finished, even if its alarm clears meanwhile; each time lasts at least one scan. `set.bSteadyWhenNone`: the lamp on steady while no alarm is active.

## Example

One fault lamp for a site with no HMI. Declare `aBeacon : ARRAY[1..8] OF BOOL`.

| Pin | Wire |
| --- | --- |
| `aAlarms` | `aBeacon` (a coil per alarm, on its own rung) |
| `refData` | `stBeacon` |
| `bLamp` | `DO_FaultLamp` |

**Back to** [the index](../README.md).
