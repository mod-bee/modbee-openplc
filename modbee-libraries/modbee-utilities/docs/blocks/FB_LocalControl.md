# FB_LocalControl — Panel selector and buttons

The panel-door controls of one motor, pump or valve: an Off / Hand / Auto selector and start / stop push-buttons. It drives the equipment through its `ipOwner` pin.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSwHand` | `BOOL` | `FALSE` | The selector's Hand contact (both FALSE = Off) |
| in | `bSwAuto` | `BOOL` |  |  |
| in | `bStart` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bStop` | `BOOL` |  |  |
| in | `ipOwner` | `I_Equipment` |  | The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_LocalControlData` |  | Its record (a variable of this type) |
| in | `bOpen` | `BOOL R_EDGE` |  | a valve: open (Hand) Acts on its rising edge. |
| in | `bClose` | `BOOL R_EDGE` |  | a valve: close (Hand) Acts on its rising edge. |
| in | `bHalt` | `BOOL R_EDGE` |  | a motorised valve: stop where it is (Hand) Acts on its rising edge. |
| in | `bPos1` | `BOOL R_EDGE` |  | a three-position valve: go to 1 (Hand) Acts on its rising edge. |
| in | `bPos2` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bPos3` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bLow` | `BOOL R_EDGE` |  | a two-speed motor: low (Hand) Acts on its rising edge. |
| in | `bHigh` | `BOOL R_EDGE` |  | a two-speed motor: high (Hand) Acts on its rising edge. |
| in | `bRev` | `BOOL R_EDGE` |  | a reversing motor: reverse (Hand) Acts on its rising edge. |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LocalControlData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSelectorFault` | `BOOL` |  | both selector contacts made |
| `bHeldOff` | `BOOL` |  | power-up: held Off until the selector is moved |
| `bRemote` | `BOOL` |  | the mode comes from the operator's choice now |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_LocalControlSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eModeSource` | `E_ModeSource` | `E_ModeSource.Switch` | the selector is fitted and sets the mode |
| `bStopInAuto` | `BOOL` | `TRUE` | the stop button also stops it in Auto |
| `ePowerUp` | `E_PowerUp` |  | Off: a selector out of Off at power-up is held Off until moved |
| `eHmiMode` | `E_Mode` | `E_Mode.Auto` | Remote: the operator's choice while the selector is in Auto |

## How it works

The panel-door controls of one piece of equipment: an Off / Hand / Auto selector and the push-buttons of a motor or a valve.

The mode (`set.eModeSource`):

```
  Hmi     the selector is not used: the owner's own mode (its record, the HMI)
  Switch  the selector sets the owner's mode: bSwHand = Hand, bSwAuto = Auto, neither = Off (the panel cannot
          change it while it is fitted)
  Remote  the selector's Off and Hand act here; its Auto hands the mode to the operator's choice set.eHmiMode
          (written by the block from the owner's mode while the selector is in Auto, so the HMI's choice comes
          back when the selector returns to Auto)
```

Both selector contacts made: Off, a warning (SelectorFault). With `set.ePowerUp` Off a selector found out of Off at power-up is held Off until it is moved (Remote: a selector found in Hand; the operator's choice goes to Off).

The buttons (rising edges; `bStop` is TRUE = pressed, an NC button inverted with NOT at the pin; a stop wins):

```
  bStart          Hand start (a valve: open), as the record's bCmdStart
  bStop           stops the owner in Hand, and in Auto too with set.bStopInAuto (off until the owner's request
                  drops)
  bOpen / bClose  a valve in Hand: open / close (bOpen as bStart; bClose acts in Hand only)
  bHalt           a motorised valve in Hand: stop where it is
  bPos1..bPos3    a three-position valve in Hand: go to that position
  bLow / bHigh    a two-speed motor in Hand: that speed (and start)
  bRev            a reversing motor in Hand: reverse (and start); bStart starts in the last direction
```

`bHalt` .. `bRev` go to the owner's `I_LocalChoice` ([`FB_ValveMotor`](FB_ValveMotor.md), [`FB_Valve3Pos`](FB_Valve3Pos.md), [`FB_Motor2Speed`](FB_Motor2Speed.md), [`FB_MotorRev`](FB_MotorRev.md)); an owner without that choice ignores the button. Only the owner starts anything.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A pump motor with a Hand / Off / Auto selector and start / stop buttons on the panel door.

| Pin | Wire |
| --- | --- |
| `bSwHand` | `DI_P1_Hand` |
| `bSwAuto` | `DI_P1_Auto` |
| `bStart` | `DI_P1_StartPB` |
| `bStop` | `NOT DI_P1_StopPB` (an NC stop button) |
| `ipOwner` | `fbMotor1` |
| `refData` | `stLocal1` |

`stLocal1.set.eModeSource` is `Switch` by default: the selector sets the mode. `Remote` lets the selector's Auto hand over to the HMI.

**Back to** [the index](../README.md).
