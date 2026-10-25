# UT_DEBOUNCE — On/off delay filter

Cleans up a noisy contact: a float switch on a choppy surface, a pressure switch
near its setpoint, a bouncing limit switch.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | BOOL | FALSE | Noisy signal |
| in | `OnDelay` | TIME | T#100ms | Must be TRUE this long to switch on |
| in | `OffDelay` | TIME | T#100ms | Must be FALSE this long to switch off |
| out | `Q` | BOOL | | Clean signal |
| out | `Rising` / `Falling` | BOOL | | One scan when `Q` switches |
| out | `ET` | TIME | | How long `In` has held its new state (0 when `Q` agrees with `In`) |
| out | `Remaining` | TIME | | The delay still to run before `Q` follows (0 when `Q` agrees with `In`) |

## How it works
- `Q` switches on once `In` has been TRUE for `OnDelay` **without a break**, and off
  once it has been FALSE for `OffDelay` without a break. Anything shorter is ignored.
- A delay of 0 (or a negative one) passes `In` straight through in the same scan.
- A delay changed while timing acts at once: lowering `OnDelay` below the time
  `In` has already been on switches `Q` on at the next scan.
- `Q` starts off. An input that is already on at start switches `Q` on after `OnDelay`.
- While `In` differs from `Q`, `ET` counts up and `Remaining` counts down, like a
  TON's `ET` and `PT - ET`: show "float high, pump stops in 3 s" on an HMI. Once `Q`
  follows, or `In` goes back, both are 0.
- `In` is only seen once per scan, so a change shorter than the task interval may be missed.

For a switch that needs alarms or chatter detection, use [UT_DIGITAL_IN](UT_DIGITAL_IN.md).
