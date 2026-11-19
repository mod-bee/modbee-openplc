# FB_SystemMode — Plant mode, power-on delay and reset

The plant's own mode: Off / Manual / Auto, the auto type, a manual run, the power-on delay and the plant-wide reset. Every other block can read it through its `ipSystem` pin.

Offers `I_SystemMode`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bManualRunRequest` | `BOOL` |  | manual run request (held) |
| in | `bPlantReset` | `BOOL R_EDGE` |  | the plant reset |
| in | `bSelectorManual` | `BOOL` |  | the selector in Manual (set.eModeSource Switch / Remote) |
| in | `bSelectorAuto` | `BOOL` |  | the selector in Auto |
| in | `bForceOff` | `BOOL` |  | holds the plant Off (the choice is kept) |
| in | `refData` | `REFERENCE TO ST_SystemModeData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bIsAuto` | `BOOL` |  | the plant is in Auto |
| out | `bIsManual` | `BOOL` |  | the plant is in Manual |
| out | `bNotOff` | `BOOL` |  | the plant is not Off |
| out | `bAutoMode1` | `BOOL` |  | Auto with type 1 |
| out | `bAutoMode2` | `BOOL` |  | Auto with type 2 |
| out | `bAutoMode3` | `BOOL` |  | Auto with type 3 |
| out | `bAutoMode4` | `BOOL` |  | Auto with type 4 |
| out | `bManualRun` | `BOOL` |  | the manual run is on |
| out | `bModeChanged` | `BOOL` |  | one scan: the mode changed |
| out | `bPowerUpHold` | `BOOL` |  | TRUE for tPowerOnDelay after power-up: automatic starts wait |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SystemModeData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdSystemMode` | `INT` | `-1` | 0 Off, 1 Manual, 2 Auto: writes set.eSystemMode once, then -1 (cleared; SMS, SCADA) |
| `bCmdStartManualRun` | `BOOL` |  | latch the manual run (rising edge, cleared) |
| `bCmdStopManualRun` | `BOOL` |  | HMI: end the manual run (acts once, cleared) |
| `bCmdResetFaults` | `BOOL` |  | the plant reset, as the bPlantReset pin |

**Settings `set`** (`ST_SystemModeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSystemMode` | `E_SysMode` |  | Off, Manual or Auto (kept over a power cut) |
| `eModeAtPowerUp` | `E_PowerUp` |  | Last: back in the mode it had; Off: Off after every power-up |
| `nAutoModeChosen` | `INT` | `1` | the auto type chosen (1..nAutoModesOffered; kept) |
| `nAutoModesOffered` | `INT` | `1` | 1..8 offered |
| `tMaxManualRunTime` | `TIME` |  | 0 = no limit |
| `tPowerOnDelay` | `TIME` |  | after power-up, automatic starts wait this long |
| `eModeSource` | `E_ModeSource` |  | where the mode comes from |
| `bManualOffered` | `BOOL` | `TRUE` | FALSE: the plant is Off / Auto only (Manual refused, a Manual contact is Off) |

**Status `sts`** (`ST_SystemModeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSystemModeInUse` | `E_SysMode` |  | Off, Manual or Auto now |
| `nAutoModeInUse` | `INT` |  | the type in use (0 = invalid setting) |
| `bManualRun` | `BOOL` |  | the manual run is on |
| `bPowerUpHold` | `BOOL` |  | TRUE for tPowerOnDelay after power-up: automatic starts wait |
| `eManualRunStopReason` | `E_StopReason` |  | why the last manual run ended |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `bSelectorFault` | `BOOL` |  | both selector contacts made |
| `bForcedOffByInput` | `BOOL` |  | the bForceOff input holds the plant Off |

**Details `det`** (`ST_SystemModeDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tManualRunTime` | `TIME` |  | time in this manual run |
| `tTimeLeft` | `TIME` |  | time left in the delay running now |
| `tPowerUpHoldLeft` | `TIME` |  | time left in the power-up hold |

## How it works

The plant's own mode: Off / Manual / Auto, the auto type (1..nAutoModesOffered), a manual run, the power-on delay and the plant-wide reset.

The mode and the auto type are the record's `set.eSystemMode` / `set.nAutoModeChosen` (kept over a power cut; `set.eModeAtPowerUp` Off forces Off at power-up; the record's command `nCmdSystemMode` 0 Off / 1 Manual / 2 Auto writes `set.eSystemMode` once, for SMS and SCADA); a bad write is put back and reported. Manual run: on while Manual and `bManualRunRequest` is held (or `bCmdStartManualRun` latched until `bCmdStopManualRun`), after the power-on delay, for at most `set.tMaxManualRunTime`. A Run held at power-up, over a mode change or past the maximum must be released and given again before it runs.

Other blocks read it through `I_SystemMode` (their `ipSystem` pin).

The mode in use (`set.eModeSource`): Hmi = the record's choice; Switch = the selector `bSelectorManual` / `bSelectorAuto` (neither: Off; both: Off and a SelectorFault warning); Remote = the selector's Off and Manual act here, its Auto hands over to the record's choice. With `set.eModeAtPowerUp` Off a selector found out of Off at power-up is held Off until moved. `bForceOff` holds the plant Off (the choice is kept). `sts.eSystemModeInUse` is the mode in use. `set.bManualOffered` FALSE: the plant is Off / Auto only (Off / On): Manual is refused as a bad write (`set.eSystemMode`, `nCmdSystemMode` 1), a selector's Manual contact acts as Off, and there is no manual run. `bModeChanged` is TRUE for one scan when the mode changes.

## Example

A plant with one remote-run contact and a reset button. Declare `fbSystem : FB_SystemMode` and `stSystem : ST_SystemModeData`.

| Pin | Wire |
| --- | --- |
| `bManualRunRequest` | `DI_RemoteRun` (held while the remote asks for a manual run) |
| `bPlantReset` | `DI_ResetButton` |
| `refData` | `stSystem` |
| `bIsAuto` | a lamp `DO_AutoLamp` |

Wire `fbSystem` to the `ipSystem` pin of every motor, pump and process block: they then follow the system's Auto, wait out its power-on delay, and reset on its reset button.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `bSystemAuto : BOOL`: the plant is in Auto
- property `bSystemOff : BOOL`: the plant is Off
- property `bSystemHold : BOOL`: the power-up hold is on: automatic starts wait
- property `bSystemReset : BOOL`: the plant reset this scan
