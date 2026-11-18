# FB_IoMapOut — IO map, outputs

The output side of the IO map: functions to terminals, from a table, with commissioning forces and a hold-off per output. Call it last in the scan.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bForcePermit` | `BOOL` |  | outputs may be forced only while TRUE (system Off); unwired: never |
| in | `bReleaseAll` | `BOOL` |  | release every output force now and refuse new ones |
| in | `refData` | `REFERENCE TO ST_IoMapData` |  | set.tForceTime; counts |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aDoSet` | `ARRAY[*] OF ST_IoDoSet` |  | Digital output functions: one settings row each |
| in-out | `aDo` | `ARRAY[*] OF ST_IoDo` |  | digital output functions: rows / live |
| in-out | `aAoSet` | `ARRAY[*] OF ST_IoAoSet` |  | Analog output functions: one settings row each |
| in-out | `aAo` | `ARRAY[*] OF ST_IoAo` |  | analog |
| in-out | `aDoImg` | `ARRAY[*] OF ST_IoDch` |  | The digital terminals: your IO code copies `bQ` to the hardware |
| in-out | `aAoImg` | `ARRAY[*] OF ST_IoAch` |  | the terminals: your IO code reads bQ / fV |
| in-out | `aMods` | `ARRAY[*] OF ST_IoModule` |  | the module table, shared with FB_IoMapIn |
| in-out | `aForce` | `ARRAY[*] OF ST_IoForce` |  | the force slots, shared; never retained |
| out | `bAllOk` | `BOOL` |  | Every fitted function and module is good |
| out | `bAnyForced` | `BOOL` |  | A force is on |
| out | `bConfigBad` | `BOOL` |  | a wrong address, a function on a module not fitted, two functions on one output, tables that do not match or are longer than the kept copy |
| out | `dwTermBits` | `DWORD` |  | The first 32 digital terminals, a bit each |
| out | `dwFnBits` | `DWORD` |  | The first 32 digital functions' wanted `bQ`, a bit each |
| out | `dwOkBits` | `DWORD` |  | The first 32 digital functions' `bOk`, a bit each |
| out | `dwForcedBits` | `DWORD` |  | the first 32 digital terminals |
| out | `dwHeldBits` | `DWORD` |  | the first 32 digital functions: bQ wanted, bOk, bHoldOff |
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
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Details `det`** (`ST_IoMapDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tForceLeft` | `TIME` |  | the longest time left of the active forces |

## Rows `ST_IoDoSet` (pin `aDoSet`)

`aDoSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDoSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| `nModule` | `USINT` |  | The module number (0..127) |
| `nCh` | `USINT` |  | The channel number on the module |

## Rows `ST_IoDo` (pin `aDo`)

`aDo` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDo`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bQ` | `BOOL` |  | your logic: the output wanted |
| `bHoldOff` | `BOOL` |  | your logic (a motor's bHoldOff): holds the output off, forced or not |
| `bOut` | `BOOL` |  | status: what went to the channel (after a force or the hold) |
| `bOk` | `BOOL` |  | status: the channel is fitted, answering and good |
| `bFit` | `BOOL` |  | Mapped on this site |
| `eWhy` | `E_IoQ` |  | Why it is not good (`E_IoQ`) |

## Rows `ST_IoAoSet` (pin `aAoSet`)

`aAoSet` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAoSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| `nModule` | `USINT` |  | The module number (0..127) |
| `nCh` | `USINT` |  | The channel number on the module |

## Rows `ST_IoAo` (pin `aAo`)

`aAo` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoAo`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fV` | `REAL` |  | your logic: the raw value wanted |
| `fOut` | `REAL` |  | status: what went to the channel |
| `bOk` | `BOOL` |  | The value came from a good channel (or a force) |
| `bFit` | `BOOL` |  | Mapped on this site |
| `eWhy` | `E_IoQ` |  | Why it is not good (`E_IoQ`) |

## Rows `ST_IoDch` (pin `aDoImg`)

`aDoImg` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_IoDch`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bQ` | `BOOL` |  | the terminal: input contact made / output energised |
| `bBad` | `BOOL` |  | its driver: this channel can't be trusted |
| `bForced` | `BOOL` |  | status: a force slot holds it |
| `nFn` | `USINT` |  | status: the function row on it (inputs: the first one); 0 = spare |

## Rows `ST_IoAch` (pin `aAoImg`)

`aAoImg` is an array the project declares (any size, any lower bound): one row per item.

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
| `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
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
| `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| `nModule` | `USINT` |  | The module number (0..127) |
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

The output side of the IO map: functions to terminals, from the rows. Call it LAST in the scan, after all logic, before your IO code copies the image to the hardware.

The block owns the output image: every scan it first turns every output channel off (analog 0.0), then writes each function's `bQ` / `fV` to its channel; a force takes the place of the function's value. So a channel with no function is off, and a function moved to another channel leaves nothing behind. One channel carries one function: a second one on it is not written (`eWhy` Shared, a configuration fault). A function's `bOk` is TRUE when its channel is fitted, answering and good; `eWhy` says what is wrong otherwise; `bFit` says it is mapped on this site. `bHoldOff` (per digital function) holds the output off even while forced (`eWhy` Blocked): wire a motor's `bHoldOff` into it, so a commissioning force can never run a tripped motor.

Forcing: a slot names a channel (`eKind` DigitalOut or AnalogOut, `eSrc`, `nModule`, `nCh`), so spare outputs can be tested too; only while `bForcePermit`; it ends by itself after `set.tForceTime` (1 ms .. 10 min, default 5 s), `bCmdForce` again starts the time again, `bCmdRelease` or `bReleaseAll` end it at once, every force ends at power-up.

Errors: `bError` for a configuration fault (IoArraySize, IoAddress, IoShared, IoNotFitted) or rows that were never good (BadSetting); `bWarning` for IoForced, IoMissing, IoBad, SettingRefused.

Kept settings (a retained last-good copy, restored at power-up, a bad write put back, `sts.bRefused` / `eRefusedWhy`): each row is its address packed into one DWORD ([`F_IoAddrPack`](F_IoAddrPack.md): bits 0..2 `eSrc`, 3..9 `nModule` 0..127, 10..17 `nCh`). The first 32 digital and 4 analog rows are kept, with `set.tForceTime` and the layout number: 38 retained values.

A row with an unknown source or a module over 127 is a bad write and put back.

## Example

The site's outputs from a table. Copy `aDoImg` / `aAoImg` to the hardware after this rung.

| Pin | Wire |
| --- | --- |
| `bForcePermit` | `fbSystem.bIsManual` or Off |
| `aDoSet` | `aDoSet` |
| `aDo` | `aDo` |
| `aAoSet` | `aAoSet` |
| `aAo` | `aAo` |
| `aDoImg` | `aDoImg` |
| `aAoImg` | `aAoImg` |
| `aMods` | `aMods` |
| `aForce` | `aForce` |
| `refData` | `stIoOut` |

The logic writes `aDo[i].bQ` and `aAo[i].fV`; wire each motor's `bHoldOff` to its row's `bHoldOff`.

**Back to** [the index](../README.md).
