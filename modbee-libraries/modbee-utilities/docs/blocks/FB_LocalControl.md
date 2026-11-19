# FB_LocalControl — Panel selector and buttons

The panel-door controls of one motor, pump or valve: an Off / Hand / Auto selector and start / stop push-buttons. It drives the equipment through its `ipEquipment` pin.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bSelectorHand` | `BOOL` | `FALSE` | the selector's Hand contact (both FALSE = Off) |
| in | `bSelectorAuto` | `BOOL` |  | the selector's Auto contact |
| in | `bStartButton` | `BOOL R_EDGE` |  | rising edge: start (Hand) |
| in | `bStopButton` | `BOOL` |  | the stop button (held stops) |
| in | `bOpenButton` | `BOOL R_EDGE` |  | a valve: open (Hand) |
| in | `bCloseButton` | `BOOL R_EDGE` |  | a valve: close (Hand) |
| in | `bHaltButton` | `BOOL R_EDGE` |  | a motorised valve: stop where it is (Hand) |
| in | `bPosition1Button` | `BOOL R_EDGE` |  | a three-position valve: go to 1 (Hand) |
| in | `bPosition2Button` | `BOOL R_EDGE` |  | a three-position valve: go to 2 (Hand), rising edge |
| in | `bPosition3Button` | `BOOL R_EDGE` |  | a three-position valve: go to 3 (Hand), rising edge |
| in | `bLowSpeedButton` | `BOOL R_EDGE` |  | a two-speed motor: low (Hand) |
| in | `bHighSpeedButton` | `BOOL R_EDGE` |  | a two-speed motor: high (Hand) |
| in | `bReverseButton` | `BOOL R_EDGE` |  | a reversing motor: reverse (Hand) |
| in | `ipEquipment` | `I_Equipment` |  | the equipment it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_LocalControlData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bModeChanged` | `BOOL` |  | one scan: the owner's mode changed |
| out | `bChangedToOff` | `BOOL` |  | one scan: ... to Off |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LocalControlData` (pin `refData`)

**Settings `set`** (`ST_LocalControlSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eModeSource` | `E_ModeSource` | `E_ModeSource.Switch` | the selector is fitted and sets the mode |
| `bStopButtonInAuto` | `BOOL` | `TRUE` | the stop button also stops it in Auto |
| `eSelectorAtPowerUp` | `E_PowerUp` |  | Off: a selector out of Off at power-up is held Off until moved |
| `eHmiModeInAuto` | `E_Mode` | `E_Mode.Auto` | Remote: the operator's choice while the selector is in Auto |

**Status `sts`** (`ST_LocalControlSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSelectorFault` | `BOOL` |  | both selector contacts made |
| `bHeldOffAtPowerUp` | `BOOL` |  | power-up: held Off until the selector is moved |
| `bModeFromHmi` | `BOOL` |  | the mode comes from the operator's choice now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

The panel-door controls of one piece of equipment: an Off / Hand / Auto selector and the push-buttons of a motor or a valve.

The mode (`set.eModeSource`):

```
  Hmi     the selector is not used: the owner's own mode (its record, the HMI)
  Switch  the selector sets the owner's mode: bSelectorHand = Hand, bSelectorAuto = Auto, neither = Off (the panel cannot
          change it while it is fitted)
  Remote  the selector's Off and Hand act here; its Auto hands the mode to the operator's choice set.eHmiModeInAuto
          (written by the block from the owner's mode while the selector is in Auto, so the HMI's choice comes
          back when the selector returns to Auto)
```

Both selector contacts made: Off, a warning (SelectorFault). With `set.eSelectorAtPowerUp` Off a selector found out of Off at power-up is held Off until it is moved (Remote: a selector found in Hand; the operator's choice goes to Off).

The buttons (rising edges; `bStopButton` is TRUE = pressed, an NC button inverted with NOT at the pin; a stop wins):

```
  bStartButton          Hand start (a valve: open), as the record's bCmdStart
  bStopButton           stops the owner in Hand, and in Auto too with set.bStopButtonInAuto (off until the owner's request
                  drops)
  bOpenButton / bCloseButton  a valve in Hand: open / close (bOpenButton as bStartButton; bCloseButton acts in Hand only)
  bHaltButton           a motorised valve in Hand: stop where it is
  bPosition1Button..bPosition3Button    a three-position valve in Hand: go to that position
  bLowSpeedButton / bHighSpeedButton    a two-speed motor in Hand: that speed (and start)
  bReverseButton            a reversing motor in Hand: reverse (and start); bStartButton starts in the last direction
```

`bHaltButton` .. `bReverseButton` go to the owner's `I_LocalChoice` ([`FB_ValveMotor`](FB_ValveMotor.md), [`FB_Valve3Pos`](FB_Valve3Pos.md), [`FB_Motor2Speed`](FB_Motor2Speed.md), [`FB_MotorRev`](FB_MotorRev.md)); an owner without that choice ignores the button. Only the owner starts anything.

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. `bModeChanged` / `bChangedToOff` are TRUE for one scan when the owner's mode changes (to Off).

## Example

A pump motor with a Hand / Off / Auto selector and start / stop buttons on the panel door.

| Pin | Wire |
| --- | --- |
| `bSelectorHand` | `DI_P1_Hand` |
| `bSelectorAuto` | `DI_P1_Auto` |
| `bStartButton` | `DI_P1_StartPB` |
| `bStopButton` | `NOT DI_P1_StopPB` (an NC stop button) |
| `ipEquipment` | `fbMotor1` |
| `refData` | `stLocal1` |

`stLocal1.set.eModeSource` is `Switch` by default: the selector sets the mode. `Remote` lets the selector's Auto hand over to the HMI.

**Back to** [the index](../README.md).
