# FB_SystemMode — Plant mode, power-on delay and reset

The plant's own mode: Off / Manual / Auto, the auto type, a manual run, the power-on delay and the plant-wide reset. Every other block can read it through its `ipSystem` pin.

Offers `I_SystemMode`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | manual run request (held) |
| in | `bReset` | `BOOL R_EDGE` |  | the plant reset Acts on its rising edge. |
| in | `bSwManual` | `BOOL` |  | the selector in Manual (set.eModeSource Switch / Remote) |
| in | `bSwAuto` | `BOOL` |  | the selector in Auto |
| in | `bForceOff` | `BOOL` |  | holds the plant Off (the choice is kept) |
| in | `refData` | `REFERENCE TO ST_SystemModeData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bIsAuto` | `BOOL` |  | The plant is in Auto |
| out | `bIsManual` | `BOOL` |  | The plant is in Manual |
| out | `bNotOff` | `BOOL` |  | The plant is not Off |
| out | `bAuto1` | `BOOL` |  | Auto with type 1 |
| out | `bAuto2` | `BOOL` |  | Auto with type 2 |
| out | `bAuto3` | `BOOL` |  | Auto with type 3 |
| out | `bAuto4` | `BOOL` |  | Auto with that type |
| out | `bManualRun` | `BOOL` |  | The manual run is on |
| out | `bPowerUpHold` | `BOOL` |  | TRUE for set.tPowerOnDelay after power-up: automatic starts wait |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SystemModeData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Manual, 2 Auto: writes set.eMode once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | latch the manual run (rising edge, cleared) |
| `bCmdStop` | `BOOL` |  | Stop (HMI command; acts once, cleared by the block) |
| `bCmdReset` | `BOOL` |  | the plant reset, as the bReset pin |

**Settings `set`** (`ST_SystemModeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_SysMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `nAutoType` | `INT` | `1` | kept over a power cut; set.ePowerUp Off forces Off at power-up; the record's command nCmdMode 0 Off / 1 Manual / 2 Auto writes set.eMode once, for SMS and SCADA |
| `nAutoTypes` | `INT` | `1` | 1..8 offered |
| `tManualMaxRun` | `TIME` |  | 0 = no limit |
| `tPowerOnDelay` | `TIME` |  |  |
| `eModeSource` | `E_ModeSource` |  | where the mode comes from |

**Status `sts`** (`ST_SystemModeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_SysMode` |  | The operator's choice Off / Hand / Auto, kept over a power cut |
| `nAutoType` | `INT` |  | the type in use (0 = invalid setting) |
| `bManualRun` | `BOOL` |  |  |
| `bPowerUpHold` | `BOOL` |  | TRUE for set.tPowerOnDelay after power-up: automatic starts wait |
| `eStopReason` | `E_StopReason` |  | why the last manual run ended |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `bSelectorFault` | `BOOL` |  | both selector contacts made |
| `bForcedOff` | `BOOL` |  |  |

**Details `det`** (`ST_SystemModeDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRunTime` | `TIME` |  | Time in this run |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `tPowerUpLeft` | `TIME` |  |  |

## How it works

The plant's own mode: Off / Manual / Auto, the auto type (1..nAutoTypes), a manual run, the power-on delay and the plant-wide reset.

The mode and the auto type are the record's `set.eMode` / `set.nAutoType` (kept over a power cut; `set.ePowerUp` Off forces Off at power-up; the record's command `nCmdMode` 0 Off / 1 Manual / 2 Auto writes `set.eMode` once, for SMS and SCADA); a bad write is put back and reported. Manual run: on while Manual and `bRun` is held (or `bCmdStart` latched until `bCmdStop`), after the power-on delay, for at most `set.tManualMaxRun`. A Run held at power-up, over a mode change or past the maximum must be released and given again before it runs.

Other blocks read it through `I_SystemMode` (their `ipSystem` pin).

The mode in use (`set.eModeSource`): Hmi = the record's choice; Switch = the selector `bSwManual` / `bSwAuto` (neither: Off; both: Off and a SelectorFault warning); Remote = the selector's Off and Manual act here, its Auto hands over to the record's choice. With `set.ePowerUp` Off a selector found out of Off at power-up is held Off until moved. `bForceOff` holds the plant Off (the choice is kept). `sts.eMode` is the mode in use.

## Example

A plant with one remote-run contact and a reset button. Declare `fbSystem : FB_SystemMode` and `stSystem : ST_SystemModeData`.

| Pin | Wire |
| --- | --- |
| `bRun` | `DI_RemoteRun` (held while the remote asks for a manual run) |
| `bReset` | `DI_ResetButton` |
| `refData` | `stSystem` |
| `bIsAuto` | a lamp `DO_AutoLamp` |

Wire `fbSystem` to the `ipSystem` pin of every motor, pump and process block: they then follow the system's Auto, wait out its power-on delay, and reset on its reset button.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `bSystemAuto : BOOL`
- property `bSystemOff : BOOL`
- property `bSystemHold : BOOL`
- property `bSystemReset : BOOL`

**Back to** [the index](../README.md).
