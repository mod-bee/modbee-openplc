# FB_RunVolume — Run volume target (a part)

A volume target for a run, added to it: the run ends when the target has been delivered; a meter that stops counting trips the run.

It is a **part**: it adds itself to its run (`ipRun`) and acts through the run. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. An instance of a block that offers I_Run (FB_Run) |
| in | `ipMeter` | `I_Meter` |  | required. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `refData` | `REFERENCE TO ST_RunVolumeData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunVolumeData` (pin `refData`)

**Settings `set`** (`ST_RunVolumeSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fVolumeSetpoint` | `LREAL` |  | 0 = no volume target |
| `fMinExpectedFlow` | `REAL` |  | the least flow expected, per hour in the meter's unit (0 = use tDefaultTimeCap) |
| `tDefaultTimeCap` | `TIME` | `T#2h` | the safety time cap when fMinExpectedFlow is 0 |
| `stMeterFailedFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#2m, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 0)` | the meter does not count while the run runs; a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_RunVolumeSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fDeliveredThisRun` | `LREAL` |  | volume delivered in this run |
| `fVolumeLeft` | `LREAL` |  | volume left to the target |
| `tTimeCapInUse` | `TIME` |  | the safety time cap in use (0 = no volume target) |
| `bDefaultTimeCapInUse` | `BOOL` |  | the cap is tDefaultTimeCap, not worked out from fMinExpectedFlow |
| `stMeterFailedFault` | `ST_ProtectionSts` |  | the meter does not count while the run runs; a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by the run's reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

A volume target for a run, as a part of it.

When the run starts (a restart too: `ipRun.nActRunId` changes), the meter's total is the start; the run ends Done when `set.fVolumeSetpoint` has been delivered (0 = no target: it only watches the meter). Meter failed: while the run is running, the meter not good, or its total not rising for `set.stMeterFailedFault`'s delay, trips the run (MeterFailed). The delivered volume and what is left are in its status.

A run with a volume target always has a safety time cap on its counted time: the target at `set.fMinExpectedFlow` (the least flow expected, per hour in the meter's unit) takes at most `fVolumeSetpoint` / `fMinExpectedFlow` hours; with `fMinExpectedFlow` 0 the cap is `set.tDefaultTimeCap` (`sts.bDefaultTimeCapInUse` shows it). When the run's counted time reaches the cap before the target, the run ends with stop reason TimeCap and the warning RunCapped (`E_PartAction.Cap`). The run's own `set.tMaxTimeFromStart` still applies: whichever is first ends the run. `sts.tTimeCapInUse` shows the cap in use.

A bad settings write is put back (`sts.bSettingRefused` / `sts.eSettingRefusedErrorId`) and warns its owner (SettingRefused) until the run's reset.

## Example

End the run after 50 m3.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `ipMeter` | `fbFlowMeter` |
| `refData` | `stRunVol` |

Set `stRunVol.set.fVolumeSetpoint := 50.0`.

**Back to** [the index](../README.md).
