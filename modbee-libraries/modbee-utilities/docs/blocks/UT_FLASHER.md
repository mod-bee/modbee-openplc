# UT_FLASHER — On/off pulse generator

A flashing lamp, a horn that pulses, or an "every 10 minutes, do this" trigger.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | FALSE | Runs while TRUE |
| in | `OnTime` | TIME | T#500ms | |
| in | `OffTime` | TIME | T#500ms | |
| in | `StartOn` | BOOL | TRUE | First phase ON (a flasher) or OFF (an "every X, pulse" timer) |
| in | `Hold` | BOOL | FALSE | Freezes the cycle with `Q` off; it carries on where it stopped when released |
| in | `StartNow` | BOOL | FALSE | Rising edge: an ON phase starts now and the cycle restarts from it |
| out | `Q` | BOOL | | |
| out | `Pulse` | BOOL | | One scan at the start of every ON phase. Use as an "every N seconds" trigger |
| out | `Cycles` | UDINT | | ON phases since `Enable` came on |
| out | `ET` | TIME | | Time spent in the phase running now |
| out | `Remaining` | TIME | | Time left in the phase running now |
| out | `NextOnIn` | TIME | | Time to the next ON phase (`T#0s` while on). "Stirrer: next start in 42 m" |

## How it works
- `Q` is off whenever `Enable` is off. When `Enable` comes on, the first phase starts
  at once: ON with `StartOn` TRUE (and a `Pulse`), or OFF for `OffTime` with `StartOn` FALSE.
- Turning `Enable` off stops at once. Turning it on again starts again from the first
  phase, and `Cycles` starts again from 0. `Cycles` keeps its last value while `Enable` is off.
- **No drift.** Each phase is timed from when it should have started, not from the
  scan that noticed it. After 10,000 cycles the ON phases still start at exact
  multiples of `OnTime + OffTime`.
- A change of `OnTime` or `OffTime` acts on the phase running now. Shortening the ON
  time below the time already on turns `Q` off on the next scan.
- `OnTime` = 0: `Q` stays off and only `Pulse` fires, every `OffTime`.
  `OffTime` = 0: `Q` stays on and `Pulse` fires every `OnTime`. Both 0: `Pulse`
  fires every scan. A negative time counts as 0. Very long times are fine.
- `Q` and `Pulse` can change at most once per scan. If a cycle is shorter than the
  task interval, `Cycles` still counts every cycle.
- **`Hold`** stops the cycle's clock and turns `Q` off. When `Hold` drops, the phase
  carries on where it stopped: a stirrer blocked at minimum level gets the rest of
  its ON phase once the level is back, and an OFF phase is lengthened by the time
  held. `ET`, `Remaining` and `NextOnIn` stand still while held (`NextOnIn` stays
  0 when the hold came in an ON phase: that phase is still to finish).
- **`StartNow`** (rising edge) starts an ON phase at once, with a `Pulse`, and the
  cycle is timed from it. A held `StartNow` acts once. While `Hold` is on, the ON
  phase starts when `Hold` drops.
- `ET`, `Remaining` and `NextOnIn` are all `T#0s` while `Enable` is off. Show them
  with [UT_TIME_TEXT](UT_TIME_TEXT.md).
