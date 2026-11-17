# F_IoFind — IO channel lookup

Finds a channel through the IO module table (used by the IO maps).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eKind` | `E_IoKind` |  | The kind |
| in | `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| in | `nModule` | `USINT` |  | The module number (0..127) |
| in | `nCh` | `USINT` |  | The channel number on the module |
| in | `nImgLo` | `DINT` |  | The image's first row |
| in | `nImgHi` | `DINT` |  | The image's last row |
| in-out | `aMods` | `ARRAY[*] OF ST_IoModule` |  | The module table |
| out | `nMod` | `DINT` |  | the module row |
| out | `nIdx` | `DINT` |  | the image row |
| out | *(result)* | `E_IoQ` | | `Ok`, or why the channel is not found |

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

## How it works

A channel through the module table: Unused (`eSrc` None), NoModule (no module of that kind, source and number), NoChannel (no such channel, or outside the image `nImgLo`..nImgHi), else Ok with `nMod` (the module row) and `nIdx` (the image row). The caller then checks the module's fitted / ok and the channel's bad bit.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
