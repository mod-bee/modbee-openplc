# F_IoAddrOk — IO address check

TRUE when an IO address can be kept by the IO maps (a known source, a module of at most 127).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eSource` | `E_IoSrc` |  | where the channel is: None (not on this site), Board, I2c, Field or Remote |
| in | `nModuleNumber` | `USINT` |  | the module number within that source (0..127) |
| out | *(result)* | `BOOL` |  | TRUE when the IO maps can keep this address |

## How it works

An address the IO maps can keep: a known source and a module of at most 127.

## Example

Used by the IO maps; rarely needed in a project.

**Back to** [the index](../README.md).
