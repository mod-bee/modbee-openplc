# F_IoFind — IO channel lookup

Finds a channel through the IO module table (used by the IO maps).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eChannelKind` | `E_IoKind` |  | the kind of channel looked for |
| in | `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| in | `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| in | `nChannel` | `USINT` |  | the channel number on the module |
| in | `nImageFirstRow` | `DINT` |  | the image's first row |
| in | `nImageLastRow` | `DINT` |  | the image's last row |
| in-out | `aModules` | `ARRAY[*] OF ST_IoModule` |  | the module table |
| out | `nModuleRow` | `DINT` |  | the module row found |
| out | `nImageRow` | `DINT` |  | the image row found |
| out | *(result)* | `E_IoQ` |  | the channel's quality, or why it was not found |

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

## How it works

A channel through the module table: Unused (`eSource` None), NoModule (no module of that kind, source and number), NoChannel (no such channel, or outside the image `nImageFirstRow`..nImageLastRow), else Ok with `nModuleRow` (the module row) and `nImageRow` (the image row). The caller then checks the module's fitted / ok and the channel's bad bit.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
