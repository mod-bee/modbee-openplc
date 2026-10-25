# UT_MEAS_CHECK — A measurement's four levels (switch, transmitter, both or none)

Checks one [`UT_MEAS`](../conventions.md#ut_meas--a-measurement-that-might-be-a-switch-a-transmitter-both-or-nothing)
measurement (pressure, flow, suction level…) against its HH, H, L and LL levels,
whatever is fitted on site: a transmitter, a high and/or low switch, both, or
nothing. The building block the pump and controllers use; usable on its own.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | The transmitter's value (used when `sensor` is ANALOG or BOTH) |
| in | `HighSwitch` | BOOL | FALSE | The high switch is signalling, TRUE = high (used when `sensor` is SWITCH or BOTH). A NC contact: through NOT at the pin |
| in | `LowSwitch` | BOOL | FALSE | The low switch is signalling, TRUE = low. A flow switch that is TRUE with flow: `NOT FlowSwitch` at the pin |
| in | `Running` | BOOL | FALSE | The equipment runs (for `onlyWhenRunning`) |
| in | `Masked` | BOOL | FALSE | Start mask or priming in progress (for `maskAtStart`) |
| in | `ResetReq` | BOOL | FALSE | Reset request this scan |
| in | `RetryWindow` | TIME | T#1h | RETRY window |
| out | `Trip` / `Warn` | BOOL | | A level set to trip / warn is in effect |
| out | `HiHi` / `Hi` / `Lo` / `LoLo` | BOOL | | That level is in effect (trip or warning) |
| out | `Reset` | BOOL | | One scan: a latched level was reset |
| out | `BadInput` | BOOL | | A fitted transmitter reads NaN or infinity (the levels hold) |
| out | `BadSetting` | BOOL | | Installed, and a level in use has an invalid `sp`, `deadband` or time ([UT_LEVEL_CHECK](UT_LEVEL_CHECK.md)) |
| inout | `Meas` | UT_MEAS | | Settings and status |

## How it works
- Nothing is checked unless `installed`.
- A transmitter is checked against the four [`UT_LEVEL`](UT_LEVEL_CHECK.md) setpoints.
- The high switch raises the level `highSwitch` names (`UT_LVL_HIHI`, `UT_LVL_HI`, or
  `UT_LVL_NONE` = not fitted); the low switch the level `lowSwitch` names. The switch
  pins are TRUE = signalling; there is no NC setting: wire a NC contact through NOT.
- BOTH: either the switch or the transmitter raises the level, so the switch backs up
  the transmitter. Each level has one delay, one reset and one count either way.
- `onlyWhenRunning`: checked only while `Running`. `maskAtStart`: the low levels are
  ignored while `Masked`.
- Each level's status fields stay up to date in the record, including `timeLeft`
  (`Meas.lo.timeLeft`: its delay, or its recover / retry wait, still to go).

## For block builders: UT_MEAS_RUN
The same logic as a function, `UT_MEAS_RUN`, which the pump and controller blocks
use inside (see [UT_PROT_RUN](UT_PROTECT.md#for-block-builders-ut_prot_run)). The
owning block keeps the measurement's working state in a `UT_MEAS_ST` (one
`UT_PROT_ST` per level) and passes it with the record.

| | Pin | Type | What to wire |
| --- | --- | --- | --- |
| in | `TNow` | TIME | `TIME()` of this scan |
| in | `In`, `HighSwitch`, `LowSwitch`, `Running`, `Masked`, `ResetReq`, `RetryWindow` | | As the block's pins above (no defaults: wire every one) |
| inout | `Meas` | UT_MEAS | Settings and status |
| inout | `St` | UT_MEAS_ST | The working state. Its `trip`, `warn`, `hiHi`, `hi`, `lo`, `loLo`, `reset`, `badInput` and `badSetting` are the block's outputs. Not for HMIs |
| returns | | BOOL | `Trip` |

