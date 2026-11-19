# FB_DigitalIn — Digital input

A switch, float or contact cleaned up: debounce, an alarm on a state, chatter detection, and running totals of changes and on-time.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRawIn` | `BOOL` |  | the raw input (NC: NOT at the pin) |
| in | `eInputQuality` | `E_IoQ` | `E_IoQ.Ok` | quality from the IO map row |
| in | `bResetFaults` | `BOOL R_EDGE` |  | reset a Manual alarm |
| in | `refData` | `REFERENCE TO ST_DigitalInData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bSignal` | `BOOL` |  | clean signal |
| out | `bGood` | `BOOL` |  | bSignal is usable |
| out | `bStateAlarm` | `BOOL` |  | the state alarm (a warning) |
| out | `bChattering` | `BOOL` |  | too many changes; bSignal holds its last stable value |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_DigitalInData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a Manual alarm, clear bSettingRefused (cleared by the block) |
| `bCmdResetTotals` | `BOOL` |  | clear the totals (cleared by the block) |

**Settings `set`** (`ST_DigitalInSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tDebounceOnTime` | `TIME` | `T#50ms` | debounce turning on |
| `tDebounceOffTime` | `TIME` | `T#50ms` | debounce turning off |
| `eAlarmWhen` | `E_DiAlarm` |  | none, when TRUE, when FALSE |
| `tAlarmDelay` | `TIME` |  | the alarm state must last this long |
| `eAlarmResetMode` | `E_ResetMode` | `E_ResetMode.Auto` | Auto clears when bSignal returns; Manual holds until reset |
| `nChatterChanges` | `INT` |  | more than this many clean changes within tChatterWindow = chatter (0 = off) |
| `tChatterWindow` | `TIME` | `T#10s` | the window chatter is counted in |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_DigitalInSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSignal` | `BOOL` |  | the clean (debounced) signal |
| `bStateAlarm` | `BOOL` |  | the state alarm is on (a warning) |
| `bChattering` | `BOOL` |  | too many changes: the signal holds its last stable value |
| `bGood` | `BOOL` |  | the signal can be trusted |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Details `det`** (`ST_DigitalInDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tInStateFor` | `TIME` |  | time bSignal has been in its present state |

**Totals `tot`** (`ST_DigitalInTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nChangeCount` | `UDINT` |  | changes of the input after debounce |
| `tTotalOnTime` | `TIME` |  | time bSignal has been TRUE |

## Lists

- `E_DiAlarm`: `None`, `WhenTrue`, `WhenFalse` (default `None`)

## How it works

A switch, float or contact, cleaned up: debounce, an alarm on a state, chatter detection.

```
  debounce  bSignal follows the input once it has held its new state for set.tDebounceOnTime (turning on) or tDebounceOffTime
            (turning off)
  chatter   more than set.nChatterChanges clean changes within set.tChatterWindow: bSignal holds its last stable value,
            not good, a warning (Chatter), until the input has been steady for tChatterWindow (count 0 = off)
  alarm     a warning (StateAlarm) on the chosen state of bSignal (set.eAlarmWhen), after set.tAlarmDelay; it clears per
            set.eAlarmResetMode (Auto when bSignal returns; Manual holds until a reset)
  eInputQuality      NotFitted / Unused: not on this site: bSignal FALSE, no alarm, eState Off; any other bad quality: bSignal
            held, not good, bError IoBad
```

Totals (tot): `nChangeCount` of the clean input, `tTotalOnTime` while `bSignal` is TRUE; running totals (no day rollover: the board has no clock; SCADA makes days), kept hourly; `bCmdResetTotals` clears them. Simulation is an IO map force.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A door switch with an alarm when it is open.

| Pin | Wire |
| --- | --- |
| `bRawIn` | `DI_Door` |
| `refData` | `stDoor` |
| `bSignal` | the clean signal |
| `bStateAlarm` | a lamp |

Set `stDoor.set.eAlarmWhen := E_DiAlarm.WhenTrue`.

**Back to** [the index](../README.md).
