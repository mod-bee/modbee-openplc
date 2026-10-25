# UT_SETTING_CHECK — Check a setting before it is used

An HMI or SCADA user can type anything: a stop level above the start level, a
negative time, a number with a slipped decimal point. UT_SETTING_CHECK takes a
written setting only if it is sensible, and otherwise keeps the old one and says
why, as a `UT_FAULT` code the HMI turns into its own words (`not below related`).

**UT_SETTING_ARRAY** does the same for a whole list of settings in one block (see
below).

## Pins (UT_SETTING_CHECK)
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `New` | REAL | 0.0 | The value the master wrote: its own variable, not the setting in use |
| in | `Written` | BOOL | FALSE | Rising edge: check `New` now, even if unchanged (an HMI "Apply" button) |
| in | `MinValue` | REAL | −3.4E38 | Lowest value allowed (allowed itself) |
| in | `MaxValue` | REAL | 3.4E38 | Highest value allowed (allowed itself) |
| in | `Above` | REAL | −3.4E38 | Must be above this related setting (H above L). Unwired: no check |
| in | `Below` | REAL | 3.4E38 | Must be below this related setting (L below H). Unwired: no check |
| out | `Accepted` | BOOL | | One scan: `New` was taken into `Value` |
| out | `Refused` | BOOL | | One scan: `New` was refused, `Value` kept |
| out | `Bad` | BOOL | | `Value` itself fails the checks now (written past this block, or a limit or related setting has moved since) |
| out | `RefusedWhy` | UT_FAULT | | Why the last write was refused (below); `UT_F_NONE` after an accepted one |
| inout | `Value` | REAL | | The setting in use (in your settings record) |

## How it works
`New` is checked **each time it changes**, or on a rising edge of `Written`:

| Check | `RefusedWhy` when it fails | Words (as in [UT_STATUS_TEXT](UT_STATUS_TEXT.md)) |
| --- | --- | --- |
| Not NaN, not infinite | `UT_F_VALUE_BAD` | `value not a number` |
| The limits are numbers, and `MinValue` ≤ `MaxValue` | `UT_F_LIMITS` | `limits not valid` |
| `New` ≥ `MinValue` | `UT_F_BELOW_MIN` | `below minimum` |
| `New` ≤ `MaxValue` | `UT_F_ABOVE_MAX` | `above maximum` |
| `New` > `Above` (strictly: equal is refused) | `UT_F_NOT_ABOVE` | `not above related` |
| `New` < `Below` (strictly) | `UT_F_NOT_BELOW` | `not below related` |

Passed: `Value := New`, `RefusedWhy` `UT_F_NONE`. Refused: `Value` keeps its old value
and `RefusedWhy` says why. The HMI knows which setting it wrote, so it can show its
own words, e.g. "L refused: not below H".

- A master that writes the same refused value every poll is refused once (the value
  hasn't changed). After fixing the related setting, write the value again, or
  pulse `Written`.
- **Nothing is checked on the first scan** after a power cut or PLC start: `New` is
  only read. A master variable that comes back 0 never overwrites a setting kept in
  a `RETAIN` record.
- The HMI shows `Value` (the setting in use) and writes `New`.
- For two related settings use two blocks, each with the other as its limit:
  L with `Below := H`, H with `Above := L`.

```iecst
LChk(New := HMI_LevelL, MinValue := 0.0, MaxValue := 5.0, Below := Cfg.levelH,
     Value := Cfg.levelL);
HChk(New := HMI_LevelH, MinValue := 0.0, MaxValue := 5.0, Above := Cfg.levelL,
     Value := Cfg.levelH);
HRefused := HChk.RefusedWhy;     (* UT_F_NOT_ABOVE: H not above L *)
```

---

## UT_SETTING_ARRAY — a list of settings

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| out | `Accepted` | BOOL | | One scan: a request was taken |
| out | `Refused` | BOOL | | One scan: a request was refused |
| out | `AnyBad` | BOOL | | An item's `value` fails its checks now |
| out | `RefusedItem` | INT | | Position of the last refused item (1 = the first element; 0 = none since power-up) |
| out | `RefusedWhy` | UT_FAULT | | Why it was refused (as UT_SETTING_CHECK's); kept until the next refusal |
| inout | `Items` | ARRAY[*] OF UT_SETTING | | The settings, any size and any lower bound |

### Record `UT_SETTING` (one item)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `minValue` | REAL | −3.4E38 | Lowest value allowed |
| `maxValue` | REAL | 3.4E38 | Highest value allowed |
| `above` | INT | 0 | Must be above the `value` of the item at this **position** (1 = the first element, whatever the lower bound). 0 = none |
| `below` | INT | 0 | Must be below the `value` of the item at this position. 0 = none |
| `request` | REAL | 0.0 | Written by the HMI or SCADA: the value wanted. Checked when it changes |
| `cmdCheck` | BOOL | FALSE | Check `request` again even if unchanged. Set back to FALSE |
| `value` | REAL | 0.0 | *status*: the setting in use. Use this one |
| `refused` | BOOL | | *status*: the last request was refused (until one is accepted) |
| `bad` | BOOL | | *status*: `value` fails the checks now |
| `seen` | REAL | | Block memory: the request as last read. Don't write it |

- The checks and `RefusedWhy` codes are UT_SETTING_CHECK's. A position outside the array, or
  the item's own position, means no check.
- Items are checked in array order. When two related items change in the same
  scan, the later one is checked against the earlier one's new value; the earlier
  one against the later one's old value (it may then need `cmdCheck`).
- Nothing is checked on the first scan after power-up. Declare the array `RETAIN`
  to keep the settings over a power cut.

```iecst
(* Levels[1] = L, Levels[2] = H: L.below := 2, H.above := 1 *)
LevelSettings(Items := Levels);
Station.stage[1].stop := Levels[1].value;
Station.stage[1].start := Levels[2].value;
```
