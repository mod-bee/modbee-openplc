# UT_TOGGLE — Push-on / push-off

One pushbutton turns something on, the next press turns it off.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | BOOL | FALSE | Pushbutton. Each press (rising edge) flips `Q` |
| in | `Reset` | BOOL | FALSE | Forces `Q` off while held (wins over everything) |
| in | `ForceOn` | BOOL | FALSE | Forces `Q` on while held (`Set` is avoided as a name) |
| out | `Q` | BOOL | | |

## How it works
- Only a press counts: holding the button does nothing more, and releasing it does nothing.
- `Reset` wins over `ForceOn`, and both win over the button. A press while either is held is ignored, and releasing them with the button still held doesn't count as a press.
- `ForceOn` leaves `Q` on when it releases.
- **Power cut**: nothing is kept. `Q` starts off.
- Like the standard `R_TRIG`, a button already held on the first scan after start counts as a press.
