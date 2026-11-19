# F_IoAddrPack — IO address pack

Packs an IO channel address into one DWORD (the IO maps' kept copies).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| in | `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| in | `nChannel` | `USINT` |  | the channel number on the module |
| out | *(result)* | `DWORD` |  | the address packed into one DWORD |

## How it works

An IO channel address packed into one DWORD, for the IO maps' kept copies: bits 0..2 the source (`E_IoSrc`: None 0, Board 1, I2c 2, Field 3, Remote 4), bits 3..9 the module (0..127), bits 10..17 the channel (0..255). The caller checks the module is at most 127 ([`F_IoAddrOk`](F_IoAddrOk.md)).

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
