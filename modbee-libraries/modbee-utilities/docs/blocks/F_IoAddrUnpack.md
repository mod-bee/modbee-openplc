# F_IoAddrUnpack — IO address unpack

Unpacks the address F_IoAddrPack packed.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nPackedAddress` | `DWORD` |  | the packed address |
| out | `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| out | `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| out | `nChannel` | `USINT` |  | the channel number on the module |
| out | *(result)* | `BOOL` |  | always TRUE (the parts are in the outputs) |

## How it works

The address [`F_IoAddrPack`](F_IoAddrPack.md) packed (the higher bits are the caller's).

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
