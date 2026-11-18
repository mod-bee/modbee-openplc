# FB_RunVolume — Run volume target (a part)

A volume target for a run, added to it: the run ends when the target has been delivered; a meter that stops counting trips the run.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. The FB_Run instance |
| in | `ipMeter` | `I_Meter` |  | required. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `refData` | `REFERENCE TO ST_RunVolumeData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunVolumeData` (pin `refData`)

**Settings `set`** (`ST_RunVolumeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTarget` | `LREAL` |  | 0 = no volume target |
| `fMinFlow` | `REAL` |  | the least flow expected, per hour in the meter's unit (0 = use tDefaultCap) |
| `tDefaultCap` | `TIME` | `T#2h` | the safety time cap when fMinFlow is 0 |
| `stMeterFailed` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#2m, eReset := E_ResetMode.Auto, tRecover := T#0s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_RunVolumeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDelivered` | `LREAL` |  |  |
| `fLeft` | `LREAL` |  |  |
| `tCap` | `TIME` |  | the safety time cap in use (0 = no volume target) |
| `bDefaultCap` | `BOOL` |  | the cap is tDefaultCap, not worked out from fMinFlow |
| `stMeterFailed` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by the run's reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## How it works

A volume target for a run, as a part of it.

When the run starts (a restart too: `ipRun.nActRunId` changes), the meter's total is the start; the run ends Done when `set.fTarget` has been delivered (0 = no target: it only watches the meter). Meter failed: while the run is running, the meter not good, or its total not rising for `set.stMeterFailed`'s delay, trips the run (MeterFailed). The delivered volume and what is left are in its status.

A run with a volume target always has a safety time cap on its counted time: the target at `set.fMinFlow` (the least flow expected, per hour in the meter's unit) takes at most `fTarget` / `fMinFlow` hours; with `fMinFlow` 0 the cap is `set.tDefaultCap` (`sts.bDefaultCap` shows it). When the run's counted time reaches the cap before the target, the run ends with stop reason TimeCap and the warning RunCapped (`E_PartAction.Cap`). The run's own `set.tMaxTime` still applies: whichever is first ends the run. `sts.tCap` shows the cap in use.

A bad settings write is put back (`sts.bRefused` / `sts.eRefusedWhy`) and warns its owner (SettingRefused) until the run's reset.

## Example

End the run after 50 m3.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stRunVol` |

Set `stRunVol.set.fTarget := 50.0`.

**Back to** [the index](../README.md).
