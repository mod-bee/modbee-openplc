# FB_IoMapOut — IO map, outputs

The output side of the IO map: functions to terminals, from a table, with commissioning forces and a hold-off per output. Call it last in the scan.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bForcingAllowed` | `BOOL` |  | outputs may be forced only while TRUE (system Off); unwired: never |
| in | `bReleaseAllForces` | `BOOL` |  | release every output force now and refuse new ones |
| in | `refData` | `REFERENCE TO ST_IoMapData` |  | the map's record: force time, counts |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aDigitalOutSettings` | `ARRAY[*] OF ST_IoDoSet` |  | digital output functions: one settings row each |
| in-out | `aDigitalOuts` | `ARRAY[*] OF ST_IoDo` |  | digital output functions: the live rows |
| in-out | `aAnalogOutSettings` | `ARRAY[*] OF ST_IoAoSet` |  | analog output functions: one settings row each |
| in-out | `aAnalogOuts` | `ARRAY[*] OF ST_IoAo` |  | analog output functions: the live rows |
| in-out | `aDigitalOutTerminals` | `ARRAY[*] OF ST_IoDch` |  | the digital terminals: your IO code copies bTerminal to the hardware |
| in-out | `aAnalogOutTerminals` | `ARRAY[*] OF ST_IoAch` |  | the analog terminals: your IO code reads fRawValue |
| in-out | `aModules` | `ARRAY[*] OF ST_IoModule` |  | the module table, shared by FB_IoMapIn and FB_IoMapOut |
| in-out | `aForces` | `ARRAY[*] OF ST_IoForce` |  | the force slots, shared; never retained |
| out | `bAllGood` | `BOOL` |  | every fitted function and fitted module is good |
| out | `bAnyForced` | `BOOL` |  | a force is on |
| out | `bMapSettingBad` | `BOOL` |  | a wrong address, a function on a module not fitted, or tables that do not match |
| out | `nTerminalBits` | `DWORD` |  | the first 32 digital terminals, a bit each |
| out | `nFunctionBits` | `DWORD` |  | the first 32 digital functions' wanted output, a bit each |
| out | `nGoodBits` | `DWORD` |  | the first 32 digital functions' bGood, a bit each |
| out | `nForcedBits` | `DWORD` |  | the first 32 digital terminals forced, a bit each |
| out | `nHeldOffBits` | `DWORD` |  | the first 32 digital functions held off (bHoldOff), a bit each |
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

## Rows `ST_IoDoSet` (pin `aDigitalOutSettings`)

`aDigitalOutSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDoSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| `nChannel` | `USINT` |  | the channel number on the module |

## Rows `ST_IoDo` (pin `aDigitalOuts`)

`aDigitalOuts` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDo`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCommanded` | `BOOL` |  | your logic: the output wanted |
| `bHoldOutputOff` | `BOOL` |  | your logic (a motor's bHoldOutputOff): holds the output off, forced or not |
| `bOutput` | `BOOL` |  | status: what went to the channel (after a force or the hold) |
| `bGood` | `BOOL` |  | status: the channel is fitted, answering and good |
| `bFitted` | `BOOL` |  | mapped on this site (source not None, module fitted) |
| `eQuality` | `E_IoQ` |  | the quality and why it is not good (E_IoQ) |

## Rows `ST_IoAoSet` (pin `aAnalogOutSettings`)

`aAnalogOutSettings` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAoSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| `nChannel` | `USINT` |  | the channel number on the module |

## Rows `ST_IoAo` (pin `aAnalogOuts`)

`aAnalogOuts` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAo`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fRawValue` | `REAL` |  | your logic: the raw value wanted |
| `fOutput` | `REAL` |  | status: what went to the channel |
| `bGood` | `BOOL` |  | the value comes from a good channel, or a force |
| `bFitted` | `BOOL` |  | mapped on this site (source not None, module fitted) |
| `eQuality` | `E_IoQ` |  | the quality and why it is not good (E_IoQ) |

## Rows `ST_IoDch` (pin `aDigitalOutTerminals`)

`aDigitalOutTerminals` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bTerminal` | `BOOL` |  | the terminal: input contact made / output energised |
| `bChannelBad` | `BOOL` |  | its driver: this channel can't be trusted |
| `bForced` | `BOOL` |  | status: a force slot holds it |
| `nFunctionRow` | `USINT` |  | status: the function row on it (inputs: the first one); 0 = spare |

## Rows `ST_IoAch` (pin `aAnalogOutTerminals`)

`aAnalogOutTerminals` is an array the project declares (any size, any lower bound): one row per item.

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

The output side of the IO map: functions to terminals, from the rows. Call it LAST in the scan, after all logic, before your IO code copies the image to the hardware.

The block owns the output image: every scan it first turns every output channel off (analog 0.0), then writes each function's `bCommanded` / `fRawValue` to its channel; a force takes the place of the function's value. So a channel with no function is off, and a function moved to another channel leaves nothing behind. One channel carries one function: a second one on it is not written (`eQuality` Shared, a configuration fault). A function's `bGood` is TRUE when its channel is fitted, answering and good; `eQuality` says what is wrong otherwise; `bFitted` says it is mapped on this site. `bHoldOutputOff` (per digital function) holds the output off even while forced (`eQuality` Blocked): wire a motor's `bHoldOutputOff` into it, so a commissioning force can never run a tripped motor.

Forcing: a slot names a channel (`eChannelKind` DigitalOut or AnalogOut, `eSource`, `nModuleNumber`, `nChannel`), so spare outputs can be tested too; only while `bForcingAllowed`; it ends by itself after `set.tForceTime` (1 ms .. 10 min, default 5 s), `bCmdForceNow` again starts the time again, `bCmdReleaseNow` or `bReleaseAllForces` end it at once, every force ends at power-up.

Errors: `bError` for a configuration fault (IoArraySize, IoAddress, IoShared, IoNotFitted) or rows that were never good (BadSetting); `bWarning` for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bSettingRefused` / `eSettingRefusedErrorId`): each row is its address packed into one DWORD ([`F_IoAddrPack`](F_IoAddrPack.md): bits 0..2 `eSource`, 3..9 `nModuleNumber` 0..127, 10..17 `nChannel`). The first 32 digital and 4 analog rows are kept, with `set.tForceTime` and the layout number: 38 retained values.

A row with an unknown source or a module over 127 is a bad write and put back.

## Example

The site's outputs from a table. Copy `aDigitalOutTerminals` / `aAnalogOutTerminals` to the hardware after this rung.

| Pin | Wire |
| --- | --- |
| `bForcingAllowed` | `fbSystem.bIsManual` or Off |
| `aDigitalOutSettings` | `aDigitalOutSettings` |
| `aDigitalOuts` | `aDigitalOuts` |
| `aAnalogOutSettings` | `aAnalogOutSettings` |
| `aAnalogOuts` | `aAnalogOuts` |
| `aDigitalOutTerminals` | `aDigitalOutTerminals` |
| `aAnalogOutTerminals` | `aAnalogOutTerminals` |
| `aModules` | `aModules` |
| `aForces` | `aForces` |
| `refData` | `stIoOut` |

The logic writes `aDigitalOuts[i].bCommanded` and `aAnalogOuts[i].fRawValue`; wire each motor's `bHoldOutputOff` to its row's `bHoldOutputOff`.

**Back to** [the index](../README.md).
