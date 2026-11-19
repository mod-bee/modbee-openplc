# F_Protect — Protection engine

The protection engine every block is built from: delay, response, reset mode and retries for one condition. Use it in your own ST code to protect something the library does not cover.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tNow` | `TIME` |  | TIME() of this scan |
| in | `bConditionPresent` | `BOOL` |  | the condition is present now |
| in | `bResetRequest` | `BOOL` |  | reset request this scan |
| in | `tRetryCountWindow` | `TIME` |  | Retry counts trips within this window (T#0s: no window) |
| in-out | `stSettings` | `ST_ProtectionSet` |  | settings (read only); a protection's settings ([protections](../conventions.md#protections)) |
| in-out | `stStatus` | `ST_ProtectionSts` |  | status; a protection's status ([protections](../conventions.md#protections)) |
| in-out | `stWorking` | `ST_ProtectionWork` |  | working memory |
| out | *(result)* | `BOOL` |  | TRUE while it trips |

## How it works

The protection engine every block is built from.

A FUNCTION: no instance; the VAR_IN_OUTs are references to the owner's settings, status and private state.

- a condition acts after its delay; Off ignores it; Signal follows it with no alarm (no latch, count, retry, warning or trip) and lets go once the cause has been gone `tAutoRecoverAfter` (a restart delay: a source refills before its pump starts again; 0 = at once);
- Auto clears once the cause has been gone `tAutoRecoverAfter`; Retry does the same but locks out after `nMaxRetriesBeforeLockout` trips in the window; Manual needs a reset;
- the recover wait counts from the raw cause gone; a cause back inside the wait starts it again; a reset is taken only while the cause is gone;
- an operator reset clearing an Auto / Retry latch early sets `bClearedEarly`, not `bResetDone`;
- a garbage response acts as Trip, a garbage reset as Retry, both with `bSettingBad`; a negative delay / recover acts as 0 (recover 0 keeps the retry limit), a negative `nMaxRetriesBeforeLockout` locks out at the first trip, a negative window is one hour.

Returns TRUE while it trips.

## Example

Used in ST: `bTripping := F_Protect(tNow := TIME(), bConditionPresent := bHighTemp, bResetRequest := bResetDone, tRetryCountWindow := T#1h, stSettings := stHighTempSet, stStatus := stHighTempSts, stWorking := stHighTempWork);`

**Back to** [the index](../README.md).
