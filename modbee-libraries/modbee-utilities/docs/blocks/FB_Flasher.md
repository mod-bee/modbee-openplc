# FB_Flasher — Pulse generator

An on / off pulse generator that never drifts: a flasher, or an "every X, pulse" timer.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | runs while TRUE |
| in | `tOnTime` | `TIME` | `T#500ms` | On time |
| in | `tOffTime` | `TIME` | `T#500ms` | Off time |
| in | `bStartOn` | `BOOL` | `TRUE` | first phase on (TRUE) or off (FALSE) |
| in | `bHold` | `BOOL` |  | freeze the phase clock, bQ off; carries on when released |
| in | `bStartNow` | `BOOL` |  | rising edge: start an on phase now, the cycle restarts from it |
| out | `bQ` | `BOOL` |  | The output |
| out | `bPulse` | `BOOL` |  | one scan at the start of every on phase |
| out | `nCycles` | `UDINT` |  | on phases since bEnable came on |
| out | `tET` | `TIME` |  | time spent in the phase running now |
| out | `tRemaining` | `TIME` |  | time left in the phase running now |
| out | `tNextOnIn` | `TIME` |  | time to the next on phase (0 while on) |

## How it works

On/off pulse generator.

While `bEnable` is on, `bQ` is on for `tOnTime` and off for `tOffTime`, over and over. `bStartOn` chooses the first phase: on (a flasher) or off (an "every X, pulse" timer). `bPulse` is on for one scan at the start of every on phase, and `nCycles` counts the on phases since `bEnable` came on.

The phases are timed from where they should have started, not from the scan that noticed them, so the timing never drifts: after 10,000 cycles the on phases still start at exact multiples of `tOnTime` + `tOffTime`. A change of `tOnTime` or `tOffTime` acts on the phase running now.

`tOnTime` = 0: `bQ` stays off and `bPulse` fires every `tOffTime`. `tOffTime` = 0: `bQ` stays on and `bPulse` fires every `tOnTime`. Both 0: `bPulse` fires every scan. Negative times count as 0. If a cycle is shorter than the task interval, `bQ` and `bPulse` can only change once per scan, but `nCycles` still counts every cycle.

`bHold` freezes the phase clock with `bQ` off (a stirrer blocked at minimum level keeps the rest of its on phase); the phase carries on where it stopped when `bHold` drops. A rising edge on `bStartNow` starts an on phase now and restarts the cycle from it (while `bHold` is on, it starts when `bHold` drops). `tET` and `tRemaining` are the time spent in and left of the phase running now; `tNextOnIn` is the time to the next on phase (0 while on).

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
