# F_IoAddrUnpack — IO address unpack

Unpacks the address F_IoAddrPack packed.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `dwAddr` | `DWORD` |  | The packed address |
| out | `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| out | `nModule` | `USINT` |  | The module number (0..127) |
| out | `nCh` | `USINT` |  | The channel number on the module |
| out | *(result)* | `BOOL` | | Always TRUE |

## How it works

The address [`F_IoAddrPack`](F_IoAddrPack.md) packed (the higher bits are the caller's).

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
