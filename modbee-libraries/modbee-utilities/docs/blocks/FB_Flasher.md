# FB_Flasher — Pulse generator

An on / off pulse generator that never drifts: a flasher, or an "every X, pulse" timer.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | runs while TRUE |
| in | `tOnTime` | `TIME` | `T#500ms` | on time |
| in | `tOffTime` | `TIME` | `T#500ms` | off time |
| in | `bStartOn` | `BOOL` | `TRUE` | first phase on (TRUE) or off (FALSE) |
| in | `bPause` | `BOOL` |  | freeze the phase clock, bQ off; carries on when released |
| in | `bStartNow` | `BOOL` |  | rising edge: start an on phase now, the cycle restarts from it |
| out | `bQ` | `BOOL` |  | the flashing output |
| out | `bPulse` | `BOOL` |  | one scan at the start of every on phase |
| out | `nOnPhaseCount` | `UDINT` |  | on phases since bEnable came on |
| out | `tElapsedTime` | `TIME` |  | time spent in the phase running now |
| out | `tTimeLeft` | `TIME` |  | time left in the phase running now |
| out | `tNextOnTimeLeft` | `TIME` |  | time to the next on phase (0 while on) |

## How it works

On/off pulse generator.

While `bEnable` is on, `bQ` is on for `tOnTime` and off for `tOffTime`, over and over. `bStartOn` chooses the first phase: on (a flasher) or off (an "every X, pulse" timer). `bPulse` is on for one scan at the start of every on phase, and `nOnPhaseCount` counts the on phases since `bEnable` came on.

The phases are timed from where they should have started, not from the scan that noticed them, so the timing never drifts: after 10,000 cycles the on phases still start at exact multiples of `tOnTime` + `tOffTime`. A change of `tOnTime` or `tOffTime` acts on the phase running now.

`tOnTime` = 0: `bQ` stays off and `bPulse` fires every `tOffTime`. `tOffTime` = 0: `bQ` stays on and `bPulse` fires every `tOnTime`. Both 0: `bPulse` fires every scan. Negative times count as 0. If a cycle is shorter than the task interval, `bQ` and `bPulse` can only change once per scan, but `nOnPhaseCount` still counts every cycle.

`bPause` freezes the phase clock with `bQ` off (a stirrer blocked at minimum level keeps the rest of its on phase); the phase carries on where it stopped when `bPause` drops. A rising edge on `bStartNow` starts an on phase now and restarts the cycle from it (while `bPause` is on, it starts when `bPause` drops). `tElapsedTime` and `tTimeLeft` are the time spent in and left of the phase running now; `tNextOnTimeLeft` is the time to the next on phase (0 while on).

## Example

A lamp flashing 1 s on, 1 s off.

| Pin | Wire |
| --- | --- |
| `bEnable` | `bAlarmOn` |
| `tOnTime` | `T#1s` |
| `tOffTime` | `T#1s` |
| `bStartOn` | TRUE |
| `bQ` | `DO_Lamp` |

**Back to** [the index](../README.md).
