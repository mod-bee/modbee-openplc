# F_BitPut — Set one bit

Sets one bit of a DWORD.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nBits` | `DWORD` |  | the word to change |
| in | `nBitNumber` | `SINT` |  | which bit, 0..31 |
| in | `bValue` | `BOOL` |  | the value to put in it |
| out | *(result)* | `DWORD` |  | nBits with the bit set to bValue |

## How it works

`nBits` with bit `nBitNumber` (0..31) set to `bValue`; `nBitNumber` outside 0..31 leaves it as is

## Example

| Pin | Wire |
| --- | --- |
| `nBits` | `dwLamps` |
| `nBitNumber` | 3 |
| `bValue` | `bPump4Run` |

**Back to** [the index](../README.md).
