# UT_DIGITAL_IN — Digital input (debounce, alarm, chatter, simulate)

Conditions a switch, float or contact: debounce, alarm on a
state, detect chatter (a failing switch or a wave-tossed float), and simulate.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | BOOL | FALSE | The raw input (`%IX…`) |
| out | `Q` | BOOL | | Clean signal (after debounce) |
| out | `Alarm` | BOOL | | Alarm state reached (if configured) |
| out | `Chatter` | BOOL | | Too many changes; `Q` holds its last stable value |
| out | `Quality` | UT_QUALITY | | GOOD, BAD while chattering, SIM when simulated |
| inout | `Data` | UT_DIGITAL_DATA | | |

## Record `UT_DIGITAL_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `onDelay` / `offDelay` | TIME | T#50ms / T#50ms | Debounce: the input must hold its new state this long |
| `alarmOn` | UT_DI_ALARM | UT_DI_NONE | `UT_DI_NONE`, `UT_DI_WHEN_TRUE`, `UT_DI_WHEN_FALSE` (state of `Q`) |
| `alarmDelay` | TIME | T#0s | The alarm state must last this long |
| `alarmReset` | UT_RESET_MODE | UT_RST_AUTO | AUTO clears when `Q` returns; MANUAL holds until reset (refused while still in the alarm state) |
| `chatterCount` | INT | 0 | More than this many clean changes within `chatterTime` = chatter (0 = off) |
| `chatterTime` | TIME | T#10s | Chatter window, and how long the input must be steady to recover |
| `simulate` / `simValue` | BOOL | FALSE / FALSE | `Q` is `simValue` |
| `cmdReset` | BOOL | | HMI: reset a MANUAL alarm (acts once, cleared by the block) |
| `cmdDayRollover` | BOOL | | Midnight pulse (`UT_SCHEDULE.DayPulse`): `onTime` back to 0 (acts once, cleared) |
| `q`, `alarm`, `chatter`, `quality` | | | Status, as the pins |
| `changes` | UDINT | | Changes of the real input after debounce (not simulated ones) |
| `onTime` | TIME | | Time `Q` has been TRUE since the last day rollover |
| `stateFor` | TIME | | Time `Q` has been in its present state, since its last change (or power-up) |

## How it works
- **Debounce**: `Q` changes once the input has held its new state for `onDelay`
  (turning on) or `offDelay` (turning off). A pulse or gap shorter than that is
  ignored; contact bounce gives one clean change. With a delay of 0, `Q` follows
  the scan the input is seen. A change must last at least one scan to be seen.
- **Chatter**: counts clean changes (after the debounce, so the count is the same
  at any scan rate). More than `chatterCount` within `chatterTime` sets `Chatter`,
  `Quality` goes BAD and `Q` holds its last stable value. It clears once the input
  has been steady for `chatterTime`.
- **Alarm**: a [UT_PROTECT](UT_PROTECT.md) warning on the chosen state of `Q`.
- **Time in state**: `stateFor` restarts at 0 whenever `Q` changes (a bounce shorter
  than the debounce does not count), e.g. "float high for 12 m".
- **Simulate**: `Q` = `simValue` at once, `Quality` = SIM, the alarm works on the
  simulated value (for FAT), chatter is not reported.
- **Power cut**: nothing is kept. `changes` starts at 0, a MANUAL alarm is forgotten,
  and an alarm state that is still there raises the alarm again.

## Using it
```iecst
HighFloat(In := NOT %IX0.3, Data := HighFloatCfg);   (* an NC float: inverted at the pin *)
```
