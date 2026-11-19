# FB_MotorCurrent — Motor current (a part)

A motor's current from a CT, added to its motor as a part: % of full load, a run proven by current, high and low current, a start that takes too long, a bad CT.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipCurrentSensor` | `I_Measurement` |  | the CT. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipOwner` | `I_Equipment` |  | the motor (required) |
| in | `refData` | `REFERENCE TO ST_MotorCurrentData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fCurrentPct` | `REAL` |  | of full load (0 while not monitoring or not good) |
| out | `bCurrentProvesRun` | `BOOL` |  | at or above set.fProvesRunAbovePct: wire to the motor's bFeedback for run by current |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorCurrentData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset its trips whose cause has gone (cleared by the block) |

**Settings `set`** (`ST_MotorCurrentSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fFullLoadCurrent` | `REAL` |  | full-load current, in the CT's unit (0 = no monitoring) |
| `fProvesRunAbovePct` | `REAL` | `20.0` | bCurrentProvesRun at or above this % of full load |
| `tMaskAfterStart` | `TIME` | `T#5s` | high / low wait this long after the motor runs |
| `stHighCurrentFault` | `ST_CurrentLevelSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#5s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#5m, nMaxRetriesBeforeLockout := 3, fLevelPct := 115.0, fClearDeadbandPct := 5.0)` | overload by current (default Off); fields below |
| `stLowCurrentFault` | `ST_CurrentLevelSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#5s, eResetMode := E_ResetMode.Retry, tAutoRecoverAfter := T#5m, nMaxRetriesBeforeLockout := 3, fLevelPct := 40.0, fClearDeadbandPct := 5.0)` | dry run or broken belt (default Off); fields below |
| `stLockedRotorFault` | `ST_CurrentLevelSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#15s, eResetMode := E_ResetMode.Manual, fLevelPct := 150.0, fClearDeadbandPct := 0.0)` | start current lasts too long: a locked rotor (default Off); fields below |
| `stCurrentBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | the current signal is bad (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**`stHighCurrentFault`, `stLowCurrentFault`, `stLockedRotorFault` (each; its own defaults are in the column above)** (`ST_CurrentLevelSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActionOnFault` | `E_Response` | `E_Response.Trip` | what it does when the condition lasts: Off, Warn, Trip or Signal |
| `tTripDelay` | `TIME` | `T#1s` | the condition must last this long before it acts |
| `eResetMode` | `E_ResetMode` | `E_ResetMode.Retry` | how it clears: Auto, Manual (held until a reset) or Retry (locks out after too many) |
| `tAutoRecoverAfter` | `TIME` | `T#10s` | the condition must be gone this long before it clears |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | Retry: trips within the retry window before it locks out |
| `fLevelPct` | `REAL` |  | % of full load |
| `fClearDeadbandPct` | `REAL` | `5.0` | % of full load: clears this far back |

**Status `sts`** (`ST_MotorCurrentSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fCurrent` | `REAL` |  | in the CT's unit |
| `fCurrentPct` | `REAL` |  | of full load |
| `bCurrentProvesRun` | `BOOL` |  | the current is at or above fProvesRunAbovePct |
| `stHighCurrentFault` | `ST_ProtectionSts` |  | overload by current (default Off); a protection's status ([protections](../conventions.md#protections)) |
| `stLowCurrentFault` | `ST_ProtectionSts` |  | dry run or broken belt (default Off); a protection's status ([protections](../conventions.md#protections)) |
| `stLockedRotorFault` | `ST_ProtectionSts` |  | start current lasts too long: a locked rotor (default Off); a protection's status ([protections](../conventions.md#protections)) |
| `stCurrentBadFault` | `ST_ProtectionSts` |  | the current signal is bad (default a warning); a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `tStartMaskTimeLeft` | `TIME` |  | running: the start mask's time left (0 when past it or stopped) |

## How it works

A motor's current from a CT, as a part of its motor. Off until `set.fFullLoadCurrent` (the motor's full-load current, in the CT's unit) is set.

- `fCurrentPct`: the current as % of full load. `bCurrentProvesRun`: at or above `set.fProvesRunAbovePct`; wire it to the motor's `bRunFeedback` when the CT, not an auxiliary contact, proves the motor runs.
- `stHighCurrentFault` (overload by current, default Off) and `stLowCurrentFault` (dry run / broken belt, default Off): % of full load with a deadband, checked once the motor runs (`bIsRunning`) and `set.tMaskAfterStart` has passed (`sts.tStartMaskTimeLeft`: the time left of the mask).
- `stLockedRotorFault` (a locked rotor, default Off): the current still at or above its % while the motor's run command is on, for its delay.
- `stCurrentBadFault` (default a warning): the current is not good while monitoring is wanted; high / low / start checks then wait (they never act on a bad reading).

Settings are kept (a retained last-good copy, a bad write put back).

## Example

A pump motor's current from a 4-20 mA CT transmitter.

| Pin | Wire |
| --- | --- |
| `ipCurrentSensor` | `fbCt` (an FB_AnalogIn in amps) |
| `ipOwner` | `fbMotor1` |
| `refData` | `stCurrent1` |
| `fCurrentPct` | a display |

Set `stCurrent1.set.fFullLoadCurrent` to the motor's full-load current; the checks are off until it is set. Put this rung before the motor's rung.

**Back to** [the index](../README.md).
