# F_IoAddrOk — IO address check

TRUE when an IO address can be kept by the IO maps (a known source, a module of at most 127).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eSrc` | `E_IoSrc` |  | Where the channel is: `None` (not on this site), `Board`, `I2c`, `Field`, `Remote` |
| in | `nModule` | `USINT` |  | The module number (0..127) |
| out | *(result)* | `BOOL` | | TRUE when the address can be kept |

## How it works

An address the IO maps can keep: a known source and a module of at most 127.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
