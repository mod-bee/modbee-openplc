# FB_IoMapIn — IO map, inputs

The input side of the IO map: terminals to functions, from a table, with fail-safe values, debounce and commissioning forces. Call it first in the scan.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bReleaseAll` | `BOOL` | `FALSE` | release every input force now and refuse new ones |
| in | `bUnusedOff` | `BOOL` | `TRUE` | a function not fitted (eSrc None) reads FALSE / 0.0, not its fail-safe |
| in | `refData` | `REFERENCE TO ST_IoMapData` |  | set.tForceTime; counts |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aDiSet` | `ARRAY[*] OF ST_IoDiSet` |  | Digital input functions: one settings row each |
| in-out | `aDi` | `ARRAY[*] OF ST_IoDi` |  | digital input functions: rows / live |
| in-out | `aAiSet` | `ARRAY[*] OF ST_IoAiSet` |  | Analog input functions: one settings row each |
| in-out | `aAi` | `ARRAY[*] OF ST_IoAi` |  | analog: rows / live, raw |
| in-out | `aDiImg` | `ARRAY[*] OF ST_IoDch` |  | The digital terminals: your IO code writes `bQ` and `bBad` |
| in-out | `aAiImg` | `ARRAY[*] OF ST_IoAch` |  | the terminals: your IO code writes bQ / fV and bBad |
| in-out | `aMods` | `ARRAY[*] OF ST_IoModule` |  | the module table, shared with FB_IoMapOut |
| in-out | `aForce` | `ARRAY[*] OF ST_IoForce` |  | the force slots, shared with FB_IoMapOut; never retained |
| out | `bAllOk` | `BOOL` |  | every fitted function and fitted module is good |
| out | `bAnyForced` | `BOOL` |  | A force is on |
| out | `bConfigBad` | `BOOL` |  | a wrong address, a function on a module not fitted, tables that do not match or are longer than the kept copy |
| out | `dwTermBits` | `DWORD` |  | The first 32 digital terminals, a bit each |
| out | `dwFnBits` | `DWORD` |  | The first 32 digital functions' `bQ`, a bit each |
| out | `dwOkBits` | `DWORD` |  | the first 32 digital functions: bQ, bOk |
| out | `dwForcedBits` | `DWORD` |  | the first 32 digital terminals |
| out | `dwAnaOkBits` | `DWORD` |  | the first 32 analog functions: bOk |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IoMapData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_IoMapSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tForceTime` | `TIME` | `T#5s` | how long a force lasts (1 ms .. 10 min); bCmdForce again starts it again |

**Status `sts`** (`ST_IoMapSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nForced` | `INT` |  | force slots active |
| `nBad` | `INT` |  | fitted functions whose channel is not good |
| `nMissing` | `INT` |  | fitted modules not answering |
| `bRefused` | `BOOL` |  | a bad settings write (record or rows) was put back (cleared by a reset) |

**Details `det`** (`ST_IoMapDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tForceLeft` | `TIME` |  | the longest time left of the active forces |

## Rows `ST_IoDiSet` (pin `aDiSet`)

`aDiSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDiSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSrc` | `E_IoSrc` |  | where it is wired (None = not fitted) |
| `nModule` | `USINT` |  | 0..127 |
| `nCh` | `USINT` |  | The channel number on the module |
| `bNc` | `BOOL` |  | normally-closed contact, inverted here (bQ TRUE = active) |
| `bFailSafe` | `BOOL` |  | bQ when the channel is missing, bad or its module not fitted |
| `tDebounce` | `TIME` |  | a new state must hold this long (0..40.95 s, in 10 ms steps) |

## Rows `ST_IoDi` (pin `aDi`)

`aDi` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDi`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bQ` | `BOOL` |  | the value for your logic, TRUE = active |
| `bOk` | `BOOL` |  | bQ comes from a good channel, or a force |
| `bFit` | `BOOL` |  | mapped on this site (eSrc not None, module fitted) |
| `eWhy` | `E_IoQ` |  | the quality and why |
| `bRaw` | `BOOL` |  | the block's: the last state after NC |
| `tRawAt` | `TIME` |  | the block's: when bRaw changed |

## Rows `ST_IoAiSet` (pin `aAiSet`)

`aAiSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAiSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSrc` | `E_IoSrc` |  | None 0, Board 1, I2c 2, Field 3, Remote 4 |
| `nModule` | `USINT` |  | 0..127 |
| `nCh` | `USINT` |  | The channel number on the module |
| `fFailSafe` | `REAL` |  | fV when the channel is missing, bad or its module not fitted |

## Rows `ST_IoAi` (pin `aAi`)

`aAi` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAi`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fV` | `REAL` |  | the raw value for your logic |
| `bOk` | `BOOL` |  | The value came from a good channel (or a force) |
| `bFit` | `BOOL` |  | Mapped on this site |
| `eWhy` | `E_IoQ` |  | Why it is not good (`E_IoQ`) |

## Rows `ST_IoDch` (pin `aDiImg`)

`aDiImg` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bQ` | `BOOL` |  | the terminal: input contact made / output energised |
| `bBad` | `BOOL` |  | its driver: this channel can't be trusted |
| `bForced` | `BOOL` |  | status: a force slot holds it |
| `nFn` | `USINT` |  | status: the function row on it (inputs: the first one); 0 = spare |

## Rows `ST_IoAch` (pin `aAiImg`)

`aAiImg` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fV` | `REAL` |  | the raw value (inputs: before scaling) |
| `bBad` | `BOOL` |  | The channel is bad / stale (written by your IO code) |
| `bForced` | `BOOL` |  | Forced now |
| `nFn` | `USINT` |  | The first function using this channel |

## Rows `ST_IoModule` (pin `aMods`)

`aMods` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoModule`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eKind` | `E_IoKind` |  | The kind |
| `eSrc` | `E_IoSrc` |  | None 0, Board 1, I2c 2, Field 3, Remote 4 |
| `nModule` | `USINT` |  | its number within that source (1 = the first) |
| `nFirst` | `INT` |  | the image row of its channel 1 |
| `nCount` | `USINT` |  | how many channels it has |
| `bFitted` | `BOOL` | `TRUE` | installed on this site |
| `bOk` | `BOOL` |  | present and answering: its driver / comms sets this every scan |
| `eState` | `E_IoQ` |  | status: Ok, NotFitted or Missing (Unused for an empty row) |
| `nUsed` | `USINT` |  | status: functions mapped to it |

## Rows `ST_IoForce` (pin `aForce`)

`aForce` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoForce`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eKind` | `E_IoKind` |  | the channel to force: DigitalIn, DigitalOut, AnalogIn or AnalogOut (None = not used) |
| `eSrc` | `E_IoSrc` |  | None 0, Board 1, I2c 2, Field 3, Remote 4 |
| `nModule` | `USINT` |  | 0..127 |
| `nCh` | `USINT` |  | The channel number on the module |
| `bQ` | `BOOL` |  | digital: the state (inputs: the terminal, as if the contact were made) |
| `fV` | `REAL` |  | analog: the raw value (inputs: before scaling) |
| `bCmdForce` | `BOOL` |  | force now, or start the time again (cleared by the map) |
| `bCmdRelease` | `BOOL` |  | release now (cleared by the map) |
| `bActive` | `BOOL` |  | status: forcing now |
| `tTimeLeft` | `TIME` |  | status: until it releases by itself |
| `eState` | `E_IoQ` |  | status: Forced, or why not (NoModule, NoChannel, NotPermitted) |
| `nRow` | `INT` |  | the map's: the image row it forces |
| `bForceSeen` | `BOOL` |  | the map's |
| `bReleaseSeen` | `BOOL` |  | the map's |
| `tEndAt` | `TIME` |  | the map's: when it releases |

## How it works

The input side of the IO map: terminals to functions, from the rows. Call it FIRST in the scan, after your IO code has copied the hardware into the image, before any logic.

For each function row it finds the channel (`eSrc`, `nModule`, `nCh`) through the module table and gives: `bQ` / `fV`  the value. Digital: after the NC setting (`bQ` TRUE = active) and the debounce.

```
  bOk      TRUE only when the value came from a good channel (or a force).
  bFit     mapped on this site (eSrc not None, module fitted).
  eWhy     Unused (eSrc None), NotFitted (its module not fitted), Missing (the module not answering), Bad (the
           channel is stale / bad), NoModule / NoChannel (a wrong address), Forced, Ok.
```

A function that is not good reads its fail-safe value and `bOk` FALSE: your logic decides what a lost signal means. When the channel comes back, `bQ` follows it at once (no debounce). An input channel may feed several functions; the image row's `nFn` shows the first.

Forcing (commissioning): a slot names a channel (`eKind` DigitalIn or AnalogIn, `eSrc`, `nModule`, `nCh`) and the value; `bCmdForce` starts it (again: starts its time again), `bCmdRelease` or `bReleaseAll` end it, it ends by itself after `set.tForceTime` (1 ms .. 10 min, default 5 s), every force ends at power-up. The force goes on the terminal, before NC and before scaling, as a test wire would; the debounce is skipped while forced. The image keeps the real terminal value. A forced channel on a missing module reads good while forced.

Errors: `bError` for a configuration fault (IoArraySize, IoAddress, IoNotFitted) or rows that were never good (BadSetting); `bWarning` for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bRefused`): the rows are packed so each row is one retained value: a digital row: one DWORD, bits 0..2 `eSrc` (None 0, Board 1, I2c 2, Field 3, Remote 4), 3..9 `nModule` (0..127), 10..17 `nCh`, 18 `bNc`, 19 `bFailSafe`, 20..31 `tDebounce` in 10 ms steps (0..40.95 s); an analog row: `ST_IoAiKept` (the address DWORD as above, `fFailSafe` REAL); plus `set.tForceTime` and the layout number. The first 32 digital and 8 analog rows are kept: 32 + 2 x 8 + 2 = 50 retained values. A row the packing cannot hold exactly (`nModule` over 127, a debounce over 40.95 s or not in 10 ms steps, a fail-safe that is not a number, an unknown source) is a bad write and put back.

## Example

The site's inputs from a table. Declare the tables (sized for the site) and copy the hardware into `aDiImg` / `aAiImg` before this rung.

| Pin | Wire |
| --- | --- |
| `aDiSet` | `aDiSet` |
| `aDi` | `aDi` |
| `aAiSet` | `aAiSet` |
| `aAi` | `aAi` |
| `aDiImg` | `aDiImg` |
| `aAiImg` | `aAiImg` |
| `aMods` | `aMods` |
| `aForce` | `aForce` |
| `refData` | `stIoIn` |

The logic reads `aDi[i].bQ` and `aAi[i].fV`.

**Back to** [the index](../README.md).
