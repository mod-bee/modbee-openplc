# FB_DigitalIn — Digital input

A switch, float or contact cleaned up: debounce, an alarm on a state, chatter detection, and running totals of changes and on-time.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | the raw input (NC: NOT at the pin) |
| in | `eInQ` | `E_IoQ` | `E_IoQ.Ok` | quality from the IO map row |
| in | `bReset` | `BOOL R_EDGE` |  | reset a Manual alarm Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_DigitalInData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bQ` | `BOOL` |  | clean signal |
| out | `bAlarm` | `BOOL` |  | The state alarm (a warning) |
| out | `bChatter` | `BOOL` |  | too many changes; bQ holds its last stable value |
| out | `bGood` | `BOOL` |  | bQ is usable |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_DigitalInData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a Manual alarm, clear bRefused (cleared by the block) |
| `bCmdResetTot` | `BOOL` |  | clear the totals (cleared by the block) |

**Settings `set`** (`ST_DigitalInSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tOnDelay` | `TIME` | `T#50ms` | debounce turning on |
| `tOffDelay` | `TIME` | `T#50ms` | debounce turning off |
| `eAlarmOn` | `E_DiAlarm` |  | none, when TRUE, when FALSE |
| `tAlarmDelay` | `TIME` |  | the alarm state must last this long |
| `eAlarmReset` | `E_ResetMode` | `E_ResetMode.Auto` | Auto clears when bQ returns; Manual holds until reset |
| `nChatterCount` | `INT` |  | more than this many clean changes within tChatterTime = chatter (0 = off) |
| `tChatterTime` | `TIME` | `T#10s` | count 0 = off |

**Status `sts`** (`ST_DigitalInSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bQ` | `BOOL` |  | the clean signal |
| `bAlarm` | `BOOL` |  |  |
| `bChatter` | `BOOL` |  |  |
| `bGood` | `BOOL` |  | The value can be trusted |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |

**Details `det`** (`ST_DigitalInDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tStateFor` | `TIME` |  | time bQ has been in its present state |

**Totals `tot`** (`ST_DigitalInTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nChanges` | `UDINT` |  | changes of the input after debounce |
| `tOnTime` | `TIME` |  | time bQ has been TRUE |

## Lists

- `E_DiAlarm`: `None`, `WhenTrue`, `WhenFalse` (default `None`)

## How it works

A switch, float or contact, cleaned up: debounce, an alarm on a state, chatter detection.

```
  debounce  bQ follows the input once it has held its new state for set.tOnDelay (turning on) or tOffDelay
            (turning off)
  chatter   more than set.nChatterCount clean changes within set.tChatterTime: bQ holds its last stable value,
            not good, a warning (Chatter), until the input has been steady for tChatterTime (count 0 = off)
  alarm     a warning (StateAlarm) on the chosen state of bQ (set.eAlarmOn), after set.tAlarmDelay; it clears per
            set.eAlarmReset (Auto when bQ returns; Manual holds until a reset)
  eInQ      NotFitted / Unused: not on this site: bQ FALSE, no alarm, eState Off; any other bad quality: bQ
            held, not good, bError IoBad
```

Totals (tot): `nChanges` of the clean input, `tOnTime` while `bQ` is TRUE; running totals (no day rollover: the board has no clock; SCADA makes days), kept hourly; `bCmdResetTot` clears them. Simulation is an IO map force.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A door switch with an alarm when it is open.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_Door` |
| `refData` | `stDoor` |
| `bQ` | the clean signal |
| `bAlarm` | a lamp |

Set `stDoor.set.eAlarmOn := E_DiAlarm.WhenTrue`.

**Back to** [the index](../README.md).
