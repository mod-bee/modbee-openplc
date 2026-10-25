# UT_MODE_SELECT — Off / Hand / Auto / Out of service

The mode logic every device block uses, and usable on its own for anything that
needs a mode. The HMI mode starts at **Off** and is **retained**. After a power cut
it comes back as `PowerUp` says: as it was (the default), or Off.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Source` | UT_MODE_SOURCE | UT_SRC_HMI | `UT_SRC_HMI` · `UT_SRC_SWITCH` · `UT_SRC_REMOTE` |
| in | `SwHand` / `SwAuto` | BOOL | FALSE | Selector switch contacts |
| in | `AllowOOS` | BOOL | TRUE | FALSE: code 3 (out of service) is not offered |
| in | `PowerUp` | UT_POWERUP | UT_PU_LAST | What the mode does after a power cut or a PLC stop / start (below). A device block passes its record's `powerUp` here |
| in | `ForceOff` | BOOL | FALSE | TRUE holds the mode at Off, in every source. The choice underneath is kept and comes back when it drops |
| out | `Mode` | UT_MODE | | The mode now |
| out | `EnteredOff` | BOOL | | One scan: just changed to Off (reset-by-Off uses this) |
| out | `Changed` | BOOL | | One scan: the mode just changed |
| out | `HmiChoice` | UT_MODE | | The HMI's choice (what `CmdMode` last selected), whatever the source and `ForceOff` |
| out | `HeldOff` | BOOL | | `Mode` is Off because of `ForceOff`, or because a selector is waiting to be moved after power-up |
| inout | `CmdMode` | INT | | HMI request: 0 Off · 1 Hand · 2 Auto · 3 OOS. Set back to −1 |

## How it works
| Source | Mode |
| --- | --- |
| `UT_SRC_HMI` | The HMI's choice (retained) |
| `UT_SRC_SWITCH` | The selector: Hand, Auto, neither = Off, both made = Off |
| `UT_SRC_REMOTE` | Selector Off and Hand act locally; selector Auto hands control to the HMI's choice |

**`CmdMode` acts once, when a new value arrives**: when it differs from the value
read the scan before. The block then sets it back to −1 ("no request"). A value
held there (a debugger force, a master that rewrites it) acts once. Any other code
that is not a mode (4 and up, a negative number, or 3 while `AllowOOS` is FALSE)
is ignored and set back to −1. If two masters (a panel HMI and SCADA) both change
the mode, put [UT_CMD](UT_CMD.md) in front.

**Power-up** (a power cut, or a PLC stop / start):

| `PowerUp` | HMI mode | Selector found in Hand or Auto |
| --- | --- | --- |
| `UT_PU_LAST` (default) | Comes back as it was left, from the first scan | Acts at once |
| `UT_PU_OFF` | Back to Off: the operator selects it again | Held at Off (`HeldOff`) until it is moved. With `UT_SRC_REMOTE` only a selector in Hand is held; its Auto position hands over to the HMI, which is Off |

`UT_PU_LAST` suits an unattended pump that must carry on after a power cut;
`UT_PU_OFF` suits plant that someone must restart on purpose (a quarry conveyor).
A motor in Hand needs a fresh start press after a power cut in either case (the
motor blocks never keep a Hand start).

**`ForceOff`** holds the mode at Off while it is TRUE: a plant-wide off, a
maintenance isolator's auxiliary contact. `EnteredOff` and reset-by-Off work as for
any change to Off. The HMI's choice is still accepted and kept (`HmiChoice`) and
takes effect when `ForceOff` drops.

There is no local / remote lock on `CmdMode` here: this block can't tell which
master wrote it. Local / remote belongs in [UT_CMD](UT_CMD.md) (which knows the
source) or in the selector with `UT_SRC_REMOTE`.
