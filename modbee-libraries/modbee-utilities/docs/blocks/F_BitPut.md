# F_BitPut — Set one bit

Sets one bit of a DWORD.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nBits` | `DWORD` |  |  |
| in | `nBit` | `SINT` |  | 0..31 |
| in | `bValue` | `BOOL` |  |  |
| out | *(result)* | `DWORD` | | `nBits` with the bit set to `bValue` |

## How it works

`nBits` with bit `nBit` (0..31) set to `bValue`; `nBit` outside 0..31 leaves it as is

## Example

| Pin | Wire |
| --- | --- |
| `nBits` | `dwLamps` |
| `nBit` | 3 |
| `bValue` | `bPump4Run` |

**Back to** [the index](../README.md).
