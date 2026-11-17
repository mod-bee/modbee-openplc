# F_Protect — Protection engine

The protection engine every block is built from: delay, response, reset mode and retries for one condition. Use it in your own ST code to protect something the library does not cover.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tNow` | `TIME` |  | TIME() of this scan |
| in | `bCause` | `BOOL` |  | the condition is present now |
| in | `bResetReq` | `BOOL` |  | reset request this scan |
| in | `tRetryWindow` | `TIME` |  | Retry counts trips within this window (T#0s: no window) |
| in-out | `stSet` | `ST_ProtectionSet` |  | settings (read only) |
| in-out | `stSts` | `ST_ProtectionSts` |  | The protection's status |
| in-out | `stWork` | `ST_ProtectionWork` |  | Its working memory (one per protection) |
| out | *(result)* | `BOOL` | | TRUE while it trips |

## How it works

The protection engine every block is built from.

A FUNCTION: no instance; the VAR_IN_OUTs are references to the owner's settings, status and private state.

- a condition acts after its delay; Off ignores it; Signal follows it with no alarm (no latch, count, retry, warning or trip);
- Auto clears once the cause has been gone `tRecover`; Retry does the same but locks out after `nMaxRetries` trips in the window; Manual needs a reset;
- the recover wait counts from the raw cause gone; a cause back inside the wait starts it again; a reset is taken only while the cause is gone;
- an operator reset clearing an Auto / Retry latch early sets `bCleared`, not `bReset`;
- a garbage response acts as Trip, a garbage reset as Retry, both with `bBadSetting`; a negative delay / recover acts as 0 (recover 0 keeps the retry limit), a negative `nMaxRetries` locks out at the first trip, a negative window is one hour.

Returns TRUE while it trips.

## Example

Used in ST: `bTrip := F_Protect(tNow := TIME(), bCause := bHighTemp, bResetReq := bReset, tRetryWindow := T#1h, stSet := stHighTempSet, stSts := stHighTempSts, stWork := stHighTempWork);`

**Back to** [the index](../README.md).
