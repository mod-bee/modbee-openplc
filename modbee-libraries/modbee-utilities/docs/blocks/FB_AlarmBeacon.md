# FB_AlarmBeacon — Alarm numbers on one lamp

Flashes alarm numbers on a single lamp, for sites with one fault lamp and no HMI.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` | `TRUE` | FALSE: the lamp stays off |
| in | `refData` | `REFERENCE TO ST_BeaconData` |  | the beacon's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aAlarms` | `ARRAY[*] OF BOOL` |  | the alarm bits; element n is alarm number n |
| out | `bLamp` | `BOOL` |  | the beacon lamp output |
| out | `nAlarmShown` | `INT` |  | the alarm number being shown (0 = none) |
| out | `bAnyAlarmActive` | `BOOL` |  | any alarm |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_BeaconData` (pin `refData`)

**Settings `set`** (`ST_BeaconSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eFlashStyle` | `E_BeaconStyle` |  | how the number is flashed: Count or Binary |
| `nBinaryBits` | `INT` | `6` | Binary: bits shown (1..15) |
| `tShortFlash` | `TIME` | `T#250ms` | short flash (Count, and Binary 0) |
| `tLongFlash` | `TIME` | `T#1s` | long flash (Binary 1) |
| `tGapBetweenFlashes` | `TIME` | `T#500ms` | lamp off between flashes |
| `tGapBetweenNumbers` | `TIME` | `T#3s` | lamp off between numbers |
| `bSteadyWhenNoAlarm` | `BOOL` |  | lamp on steady while no alarm is present |

**Status `sts`** (`ST_BeaconSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nAlarmsActive` | `INT` |  | alarms present now |
| `nAlarmShown` | `INT` |  | the alarm number the lamp is flashing now (0 = none) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_BeaconStyle`: `Count`, `Binary` (default `Count`)

## How it works

Flash alarm numbers on a single lamp, for sites with one fault lamp and no HMI. `aAlarms` (the project's array of BOOL, one per alarm; alarm number = index - lower bound + 1; write it with coils).

The block steps through every active alarm in turn (from the lowest after an idle spell, then round again) and flashes its number: Count (that many short flashes) or Binary (`set.nBinaryBits` flashes, most significant bit first: long = 1, short = 0; a number too big for `nBinaryBits` uses as many bits as it needs, up to 15). Flashes are separated by `tGapBetweenFlashes`, numbers by `tGapBetweenNumbers`. A number that has started is always finished, even if its alarm clears meanwhile; each time lasts at least one scan. `set.bSteadyWhenNoAlarm`: the lamp on steady while no alarm is active.

## Example

One fault lamp for a site with no HMI. Declare `aBeacon : ARRAY[1..8] OF BOOL`.

| Pin | Wire |
| --- | --- |
| `aAlarms` | `aBeacon` (a coil per alarm, on its own rung) |
| `refData` | `stBeacon` |
| `bLamp` | `DO_FaultLamp` |

**Back to** [the index](../README.md).
