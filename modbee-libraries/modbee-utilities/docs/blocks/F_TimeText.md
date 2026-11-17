# F_TimeText — TIME as short text

A duration as a short text for a simple display ('42 m 10 s').

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `tIn` | `TIME` |  | any duration |
| out | *(result)* | `STRING(16)` | | The text |

## How it works

A duration as short text for a simple display (function).

The blocks do not call it: their times are TIME fields (timeLeft ...).

The two largest units, rounded up to the smaller one, so a countdown never shows 0 while time is still left:

```
  under 1 min        '35 s'
  under 1 h          '42 m 10 s'   ('42 m' when the seconds are 0)
  under 1 day        '1 h 20 m'    ('1 h')
  1 day and more     '2 d 3 h'     ('2 d')
```

0, anything under a millisecond, and a negative TIME give '0 s'.

txt := CONCAT('Restart in ', `F_TimeText`(Pump1.timeLeft));

## Example

A countdown on a text display.

| Pin | Wire |
| --- | --- |
| `tIn` | `stPump1.det.tTimeLeft` |

**Back to** [the index](../README.md).
