# FB_Booster — Booster pump (a part)

A series booster pump that runs with a station's duty pumps, added to the station's level control: started after a delay or on low pressure; a booster that will not run can stop the station.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipBooster` | `I_Equipment` |  | the booster pump (required). The instance it drives (a motor, pump, valve or FB_Group) |
| in | `ipPressure` | `I_Measurement` |  | Pressure start (optional). A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipOwner` | `I_PartOwner` |  | the station's level control (required). The owner's instance |
| in | `refData` | `REFERENCE TO ST_BoosterData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bWanted` | `BOOL` |  |  |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_BoosterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |
| `bWanted` | `BOOL` |  | status |
| `stLost` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_BoosterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStartBy` | `E_BoostStart` |  |  |
| `tDelay` | `TIME` | `T#10s` | Delay: after the duty pumps run |
| `fStartAt` | `REAL` |  | Pressure: start at or below |
| `fStopAt` | `REAL` |  | Pressure: stop at or above |
| `bRequired` | `BOOL` | `TRUE` | a booster that does not run when wanted is BoosterLost |
| `stLost` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#30s)` | a protection's settings ([protections](../conventions.md#protections)) |

## Lists

- `E_BoostStart`: `Delay`, `Pressure` (default `Delay`)

## How it works

A series booster pump that runs with a station's duty pumps, as a part of the station's [`FB_LevelControl`](FB_LevelControl.md) (one booster, not in the duty rotation).

While the station runs (its request on and its pumps running): `set.eStartBy` Delay starts the booster `set.tDelay` after the duty pumps run; Pressure starts it while `ipPressure` is at or below `set.fStartAt`, until it is at or above `set.fStopAt` (with a pressure that is not good: as Delay). At a cycle end the booster stops at once; give the duty pumps a stop delay ([`FB_Pump`](FB_Pump.md) `set.tStopDelay` = the gap) so they stop that much later. `set.bRequired`: wanted and not running for `set.stLost`'s delay -> BoosterLost (a trip stops the station).

## Example

A station whose duty pumps push through a booster pump.

| Pin | Wire |
| --- | --- |
| `ipBooster` | `fbBoosterPump` |
| `ipPressure` | `fbSuctionPressure` |
| `ipOwner` | `fbLevelCtl` |
| `refData` | `stBooster` |

Give the duty pumps a stop delay (`set.tStopDelay` on each FB_Pump) so they stop after the booster.

**Back to** [the index](../README.md).
