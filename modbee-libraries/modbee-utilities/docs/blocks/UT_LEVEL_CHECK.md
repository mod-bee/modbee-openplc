# UT_LEVEL_CHECK — One alarm level with a setpoint

A [UT_PROTECT](UT_PROTECT.md) with a setpoint and deadband: one HH, H, L or LL
level. [UT_LIMIT](UT_LIMIT.md) is four of these.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | The value |
| in | `High` | BOOL | TRUE | TRUE = high level, FALSE = low level |
| in | `UseIn` | BOOL | TRUE | FALSE: `In` is not used (only a switch is fitted) |
| in | `Switch` | BOOL | FALSE | A switch signalling this level; counts as beyond, no deadband. Either the value or the switch raises the level |
| in | `Enable` | BOOL | TRUE | FALSE treats the condition as absent (inhibit, start mask) |
| in | `ResetReq` | BOOL | FALSE | Reset request this scan |
| in | `RetryWindow` | TIME | T#1h | RETRY window |
| out | `Trip` / `Warn` / `Event` / `Reset` | BOOL | | As UT_PROTECT |
| out | `BadInput` | BOOL | | `In` is NaN or infinite (the level holds its state) |
| out | `BadSetting` | BOOL | | The level is in use (response not OFF) and `sp` is NaN or infinite (the value can never raise it; a switch still can), `deadband` is negative, NaN or infinite (0 is used), or a time is invalid ([UT_PROTECT](UT_PROTECT.md)) |
| inout | `Level` | UT_LEVEL | | Settings and status |

## Record `UT_LEVEL`
Every [`UT_PROTECTION`](UT_PROTECT.md#record-ut_protection) field (including the status `timeLeft`: the delay, or the recover / retry wait, still to go), plus:

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `sp` | REAL | 0.0 | Setpoint |
| `deadband` | REAL | 0.0 | High: clears below `sp - deadband`. Low: clears above `sp + deadband` |

Exactly at `sp` is not beyond it.

## For block builders: UT_LEVEL_RUN
The same logic as a function, `UT_LEVEL_RUN`, which the device blocks use inside (see
[UT_PROT_RUN](UT_PROTECT.md#for-block-builders-ut_prot_run)). The owning block keeps
the level's working state in a `UT_PROT_ST` and passes it with the record.

| | Pin | Type | What to wire |
| --- | --- | --- | --- |
| in | `TNow` | TIME | `TIME()` of this scan |
| in | `In`, `High`, `UseIn`, `Switch`, `Enable`, `ResetReq`, `RetryWindow` | | As the block's pins above (no defaults: wire every one) |
| inout | `Level` | UT_LEVEL | Settings and status |
| inout | `St` | UT_PROT_ST | The working state. Its `trip`, `warn`, `event`, `reset`, `badInput` and `badSetting` are the block's outputs. Not for HMIs |
| returns | | BOOL | `Trip` |

