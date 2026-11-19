# FB_Booster — Booster pump (a part)

A series booster pump that runs with a station's duty pumps, added to the station's level control: started after a delay or on low pressure; a booster that will not run can stop the station.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipBoosterPump` | `I_Equipment` |  | the booster pump (required) |
| in | `ipPressure` | `I_Measurement` |  | Pressure start (optional). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipOwner` | `I_PartOwner` |  | the station's level control (required). An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: the booster does not run now (it stops at once) |
| in | `refData` | `REFERENCE TO ST_BoosterData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bBoosterRunCommand` | `BOOL` |  | the booster is asked to run now |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_BoosterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |

**Settings `set`** (`ST_BoosterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStartBoosterBy` | `E_BoostStart` |  | what starts the booster: Delay (after the duty pumps run) or Pressure |
| `tStartDelay` | `TIME` | `T#10s` | Delay: after the duty pumps run |
| `fStartAtOrBelow` | `REAL` |  | Pressure: start at or below |
| `fStopAtOrAbove` | `REAL` |  | Pressure: stop at or above |
| `bBoosterRequired` | `BOOL` | `TRUE` | a booster that does not run when wanted is BoosterLost |
| `stBoosterLostFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#30s)` | the booster did not run when wanted (bRequired); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_BoosterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bBoosterRunCommand` | `BOOL` |  | the booster is asked to run now |
| `stBoosterLostFault` | `ST_ProtectionSts` |  | the booster did not run when wanted (bRequired); a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_BoostStart`: `Delay`, `Pressure` (default `Delay`)

## How it works

A series booster pump that runs with a station's duty pumps, as a part of the station's [`FB_LevelControl`](FB_LevelControl.md) (one booster, not in the duty rotation).

While the station runs (its request on and its pumps running): `set.eStartBoosterBy` Delay starts the booster `set.tStartDelay` after the duty pumps run; Pressure starts it while `ipPressure` is at or below `set.fStartAtOrBelow`, until it is at or above `set.fStopAtOrAbove` (with a pressure that is not good: as Delay). At a cycle end the booster stops at once; give the duty pumps a stop delay ([`FB_Pump`](FB_Pump.md) `set.tStopDelay` = the gap) so they stop that much later. `set.bBoosterRequired`: wanted and not running for `set.stBoosterLostFault`'s delay -> BoosterLost (a trip stops the station). `bPermissive` FALSE (default TRUE) keeps the booster off whatever the rule says (it stops at once).

## Example

A station whose duty pumps push through a booster pump.

| Pin | Wire |
| --- | --- |
| `ipBoosterPump` | `fbBoosterPump` |
| `ipPressure` | `fbSuctionPressure` |
| `ipOwner` | `fbLevelCtl` |
| `refData` | `stBooster` |

Give the duty pumps a stop delay (`set.tStopDelay` on each FB_Pump) so they stop after the booster.

**Back to** [the index](../README.md).
