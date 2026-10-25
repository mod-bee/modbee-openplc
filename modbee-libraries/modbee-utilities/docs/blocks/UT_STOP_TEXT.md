# UT_STOP_TEXT — Why it stopped, as text (function)

The words for a `stopReason` (`UT_STOP`), so a simple display can say why a run
ended (see [conventions](../conventions.md#why-it-stopped)). The blocks don't call it:
an HMI or SCADA shows its own words for the reason's number. Use it for a person
looking at the PLC, or a display with no word list of its own.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Code` | UT_STOP | UT_STOP_NONE | A `stopReason` (or `endReason`, `lastResult`) |
| returns | | STRING(30) | | Its words, at most 30 characters |

```iecst
StopWords := UT_STOP_TEXT(Pump1Data.stopReason);   (* UT_STOP_INTERLOCK -> 'Stopped: interlock' *)
```

## How it works
Every member of `UT_STOP` has its words:

| No. | Name | Words (`UT_STOP_TEXT`) |
| --- | --- | --- |
| 0 | `UT_STOP_NONE` | (empty) |
| 1 | `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` |
| 2 | `UT_STOP_OPERATOR` | `Stopped: operator` |
| 3 | `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` |
| 4 | `UT_STOP_INTERLOCK` | `Stopped: interlock` |
| 5 | `UT_STOP_FAULT` | `Stopped: fault` |
| 6 | `UT_STOP_MAX_RUN` | `Stopped: max run time` |
| 7 | `UT_STOP_DONE` | `Done` |
| 8 | `UT_STOP_ABORTED` | `Stopped: aborted` |
| 9 | `UT_STOP_INHIBITED` | `Stopped: inhibited` |
| 10 | `UT_STOP_COMMS_LOST` | `Stopped: comms lost` |
| 11 | `UT_STOP_GROUP` | `Stopped: group` |
| 12 | `UT_STOP_LOW_LEVEL` | `Stopped: low level` |
| 13 | `UT_STOP_FULL` | `Stopped: full` |
| 14 | `UT_STOP_EXERCISE_DONE` | `Done: exercise` |
| 15 | `UT_STOP_BY_MOTOR` | `Stopped: by the motor` |
| 16 | `UT_STOP_REMOTE_OFF` | `Stopped: remote off` |
| 17 | `UT_STOP_NOT_PERMITTED` | `Stopped: not permitted` |
| 18 | `UT_STOP_PAUSED_LONG` | `Stopped: paused too long` |
| 19 | `UT_STOP_SETTING` | `Stopped: setting invalid` |
| 20 | `UT_STOP_POWER_CUT` | `Stopped: power cut` |
| 21 | `UT_STOP_RAIN` | `Stopped: rain` |
| 22 | `UT_STOP_PUMP_FAULT` | `Stopped: pump fault` |
| 23 | `UT_STOP_STEP_TIMEOUT` | `Stopped: step timeout` |
| 24 | `UT_STOP_REFUSED` | `Stopped: recipe refused` |
| 25 | `UT_STOP_ABORT_CMD` | `Stopped: aborted (HMI)` |
| 26 | `UT_STOP_ASLEEP` | `Asleep: demand met` |
| 27 | `UT_STOP_LEVEL_BAD` | `Stopped: level signal bad` |
| 28 | `UT_STOP_CLEAN_TIMEOUT` | `Stopped: cleaning too long` |

`UT_STOP_NONE` (no run has ended since power-up) gives `''`; a number outside the
list gives `Stopped`. The words hold no
numbers: how far a run got is in the block's record (`elapsed`, `delivered`,
`lastVolume` and so on).
