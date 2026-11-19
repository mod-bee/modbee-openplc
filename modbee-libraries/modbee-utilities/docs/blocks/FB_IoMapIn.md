# FB_IoMapIn — IO map, inputs

The input side of the IO map: terminals to functions, from a table, with fail-safe values, debounce and commissioning forces. Call it first in the scan.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bReleaseAllForces` | `BOOL` | `FALSE` | release every input force now and refuse new ones |
| in | `bUnfittedReadsOff` | `BOOL` | `TRUE` | a function not fitted (eSource None) reads FALSE / 0.0, not its fail-safe |
| in | `refData` | `REFERENCE TO ST_IoMapData` |  | the map's record: force time, counts |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aDigitalInSettings` | `ARRAY[*] OF ST_IoDiSet` |  | digital input functions: one settings row each |
| in-out | `aDigitalIns` | `ARRAY[*] OF ST_IoDi` |  | digital input functions: the live rows |
| in-out | `aAnalogInSettings` | `ARRAY[*] OF ST_IoAiSet` |  | analog input functions: one settings row each |
| in-out | `aAnalogIns` | `ARRAY[*] OF ST_IoAi` |  | analog input functions: the live rows (raw) |
| in-out | `aDigitalInTerminals` | `ARRAY[*] OF ST_IoDch` |  | the digital terminals: your IO code writes bTerminal and bChannelBad |
| in-out | `aAnalogInTerminals` | `ARRAY[*] OF ST_IoAch` |  | the analog terminals: your IO code writes fRawValue and bChannelBad |
| in-out | `aModules` | `ARRAY[*] OF ST_IoModule` |  | the module table, shared by FB_IoMapIn and FB_IoMapOut |
| in-out | `aForces` | `ARRAY[*] OF ST_IoForce` |  | the force slots, shared; never retained |
| out | `bAllGood` | `BOOL` |  | every fitted function and fitted module is good |
| out | `bAnyForced` | `BOOL` |  | a force is on |
| out | `bMapSettingBad` | `BOOL` |  | a wrong address, a function on a module not fitted, or tables that do not match |
| out | `nTerminalBits` | `DWORD` |  | the first 32 digital terminals, a bit each |
| out | `nFunctionBits` | `DWORD` |  | the first 32 digital functions' bActive, a bit each |
| out | `nGoodBits` | `DWORD` |  | the first 32 digital functions' bGood, a bit each |
| out | `nForcedBits` | `DWORD` |  | the first 32 digital terminals forced, a bit each |
| out | `nAnalogGoodBits` | `DWORD` |  | the first 32 analog functions' bGood, a bit each |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_IoMapData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearRefused` | `BOOL` |  | clear the refused report (cleared by the block) |

**Settings `set`** (`ST_IoMapSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tForceTime` | `TIME` | `T#5s` | how long a force lasts (1 ms .. 10 min); bCmdForceNow again starts it again |

**Status `sts`** (`ST_IoMapSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nForcesActive` | `INT` |  | force slots active |
| `nFunctionsBad` | `INT` |  | fitted functions whose channel is not good |
| `nModulesMissing` | `INT` |  | fitted modules not answering |
| `bSettingRefused` | `BOOL` |  | a bad settings write (record or rows) was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_IoMapDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tForceTimeLeft` | `TIME` |  | the longest time left of the active forces |

## Rows `ST_IoDiSet` (pin `aDigitalInSettings`)

`aDigitalInSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDiSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_IoSrc` |  | where it is wired (None = not fitted) |
| `nModuleNumber` | `USINT` |  | 0..127 |
| `nChannel` | `USINT` |  | the channel number on the module |
| `bNormallyClosed` | `BOOL` |  | normally-closed contact, inverted here (bActive TRUE = active) |
| `bFailSafeState` | `BOOL` |  | bActive when the channel is missing, bad or its module not fitted |
| `tDebounceTime` | `TIME` |  | a new state must hold this long (0..40.95 s, in 10 ms steps) |

## Rows `ST_IoDi` (pin `aDigitalIns`)

`aDigitalIns` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDi`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bActive` | `BOOL` |  | the value for your logic, TRUE = active |
| `bGood` | `BOOL` |  | bActive comes from a good channel, or a force |
| `bFitted` | `BOOL` |  | mapped on this site (eSource not None, module fitted) |
| `eQuality` | `E_IoQ` |  | the quality and why |
| `bRawLastState` | `BOOL` |  | the block's: the last state after NC |
| `tRawChangedAt` | `TIME` |  | the block's: when bRawLastState changed |

## Rows `ST_IoAiSet` (pin `aAnalogInSettings`)

`aAnalogInSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAiSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| `nChannel` | `USINT` |  | the channel number on the module |
| `fFailSafeValue` | `REAL` |  | fV when the channel is missing, bad or its module not fitted |

## Rows `ST_IoAi` (pin `aAnalogIns`)

`aAnalogIns` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAi`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawValue` | `REAL` |  | the raw value for your logic |
| `bGood` | `BOOL` |  | the value comes from a good channel, or a force |
| `bFitted` | `BOOL` |  | mapped on this site (source not None, module fitted) |
| `eQuality` | `E_IoQ` |  | the quality and why it is not good (E_IoQ) |

## Rows `ST_IoDch` (pin `aDigitalInTerminals`)

`aDigitalInTerminals` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bTerminal` | `BOOL` |  | the terminal: input contact made / output energised |
| `bChannelBad` | `BOOL` |  | its driver: this channel can't be trusted |
| `bForced` | `BOOL` |  | status: a force slot holds it |
| `nFunctionRow` | `USINT` |  | status: the function row on it (inputs: the first one); 0 = spare |

## Rows `ST_IoAch` (pin `aAnalogInTerminals`)

`aAnalogInTerminals` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawValue` | `REAL` |  | the raw value (inputs: before scaling) |
| `bChannelBad` | `BOOL` |  | your IO code writes it: this channel cannot be trusted |
| `bForced` | `BOOL` |  | status: a force slot holds it |
| `nFunctionRow` | `USINT` |  | status: the function row on it (inputs: the first one); 0 = spare |

## Rows `ST_IoModule` (pin `aModules`)

`aModules` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoModule`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eChannelKind` | `E_IoKind` |  | the kind of channels it has |
| `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| `nModuleNumber` | `USINT` |  | its number within that source (1 = the first) |
| `nFirstImageRow` | `INT` |  | the image row of its channel 1 |
| `nChannels` | `USINT` |  | how many channels it has |
| `bModuleFitted` | `BOOL` | `TRUE` | installed on this site |
| `bAnswering` | `BOOL` |  | present and answering: its driver / comms sets this every scan |
| `eModuleState` | `E_IoQ` |  | status: Ok, NotFitted or Missing (Unused for an empty row) |
| `nFunctionsMapped` | `USINT` |  | status: functions mapped to it |

## Rows `ST_IoForce` (pin `aForces`)

`aForces` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoForce`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eChannelKind` | `E_IoKind` |  | the channel to force: DigitalIn, DigitalOut, AnalogIn or AnalogOut (None = not used) |
| `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| `nChannel` | `USINT` |  | the channel number on the module |
| `bForceState` | `BOOL` |  | digital: the state (inputs: the terminal, as if the contact were made) |
| `fForceValue` | `REAL` |  | analog: the raw value (inputs: before scaling) |
| `bCmdForceNow` | `BOOL` |  | force now, or start the time again (cleared by the map) |
| `bCmdReleaseNow` | `BOOL` |  | release now (cleared by the map) |
| `bForcing` | `BOOL` |  | status: forcing now |
| `tTimeLeft` | `TIME` |  | status: until it releases by itself |
| `eForceState` | `E_IoQ` |  | status: Forced, or why not (NoModule, NoChannel, NotPermitted) |
| `nImageRow` | `INT` |  | the map's: the image row it forces |
| `bForceCommandTaken` | `BOOL` |  | the map's |
| `bReleaseCommandTaken` | `BOOL` |  | the map's |
| `tReleasesAt` | `TIME` |  | the map's: when it releases |

## How it works

The input side of the IO map: terminals to functions, from the rows. Call it FIRST in the scan, after your IO code has copied the hardware into the image, before any logic.

For each function row it finds the channel (`eSource`, `nModuleNumber`, `nChannel`) through the module table and gives: `bActive` / `fRawValue`  the value. Digital: after the NC setting (`bActive` TRUE = active) and the debounce.

```
  bGood    TRUE only when the value came from a good channel (or a force).
  bFitted     mapped on this site (eSource not None, module fitted).
  eQuality Unused (eSource None), NotFitted (its module not fitted), Missing (the module not answering), Bad (the
           channel is stale / bad), NoModule / NoChannel (a wrong address), Forced, Ok.
```

A function that is not good reads its fail-safe value and `bGood` FALSE: your logic decides what a lost signal means. When the channel comes back, `bActive` follows it at once (no debounce). An input channel may feed several functions; the image row's `nFunctionRow` shows the first.

Forcing (commissioning): a slot names a channel (`eChannelKind` DigitalIn or AnalogIn, `eSource`, `nModuleNumber`, `nChannel`) and the value; `bCmdForceNow` starts it (again: starts its time again), `bCmdReleaseNow` or `bReleaseAllForces` end it, it ends by itself after `set.tForceTime` (1 ms .. 10 min, default 5 s), every force ends at power-up. The force goes on the terminal, before NC and before scaling, as a test wire would; the debounce is skipped while forced. The image keeps the real terminal value. A forced channel on a missing module reads good while forced.

Errors: `bError` for a configuration fault (IoArraySize, IoAddress, IoNotFitted) or rows that were never good (BadSetting); `bWarning` for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bSettingRefused` / `eSettingRefusedErrorId`): the rows are packed so each row is one retained value: a digital row: one DWORD, bits 0..2 `eSource` (None 0, Board 1, I2c 2, Field 3, Remote 4), 3..9 `nModuleNumber` (0..127), 10..17 `nChannel`, 18 `bNormallyClosed`, 19 `bFailSafeState`, 20..31 `tDebounceTime` in 10 ms steps (0..40.95 s); an analog row: `ST_IoAiKept` (the address DWORD as above, `fFailSafeValue` REAL); plus `set.tForceTime` and the layout number. The first 32 digital and 8 analog rows are kept: 32 + 2 x 8 + 2 = 50 retained values. A row the packing cannot hold exactly (`nModuleNumber` over 127, a debounce over 40.95 s or not in 10 ms steps, a fail-safe that is not a number, an unknown source) is a bad write and put back.

## Example

The site's inputs from a table. Declare the tables (sized for the site) and copy the hardware into `aDigitalInTerminals` / `aAnalogInTerminals` before this rung.

| Pin | Wire |
| --- | --- |
| `aDigitalInSettings` | `aDigitalInSettings` |
| `aDigitalIns` | `aDigitalIns` |
| `aAnalogInSettings` | `aAnalogInSettings` |
| `aAnalogIns` | `aAnalogIns` |
| `aDigitalInTerminals` | `aDigitalInTerminals` |
| `aAnalogInTerminals` | `aAnalogInTerminals` |
| `aModules` | `aModules` |
| `aForces` | `aForces` |
| `refData` | `stIoIn` |

The logic reads `aDigitalIns[i].bActive` and `aAnalogIns[i].fRawValue`.

**Back to** [the index](../README.md).
