# FB_MotorCurrent — Motor current (a part)

A motor's current from a CT, added to its motor as a part: % of full load, a run proven by current, high and low current, a start that takes too long, a bad CT.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipCurrent` | `I_Measurement` |  | the CT. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipOwner` | `I_Equipment` |  | the motor (required). The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_MotorCurrentData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fPercent` | `REAL` |  | of full load (0 while not monitoring or not good) |
| out | `bProvesRun` | `BOOL` |  | at or above set.fRunPercent: wire to the motor's bFeedback for run by current |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MotorCurrentData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset its trips whose cause has gone (cleared by the block) |

**Settings `set`** (`ST_MotorCurrentSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fFullLoad` | `REAL` |  | full-load current, in the CT's unit (0 = no monitoring) |
| `fRunPercent` | `REAL` | `20.0` | bProvesRun at or above this % of full load |
| `tStartMask` | `TIME` | `T#5s` | high / low wait this long after the motor runs |
| `stHigh` | `ST_CurrentLevelSet` | `(eResponse := E_Response.Off, tDelay := T#5s, eReset := E_ResetMode.Retry, tRecover := T#5m, nMaxRetries := 3, fPercent := 115.0, fDeadband := 5.0)` | overload by current, default Off; fields below |
| `stLow` | `ST_CurrentLevelSet` | `(eResponse := E_Response.Off, tDelay := T#5s, eReset := E_ResetMode.Retry, tRecover := T#5m, nMaxRetries := 3, fPercent := 40.0, fDeadband := 5.0)` | dry run / broken belt, default Off; fields below |
| `stStartTooLong` | `ST_CurrentLevelSet` | `(eResponse := E_Response.Off, tDelay := T#15s, eReset := E_ResetMode.Manual, fPercent := 150.0, fDeadband := 0.0)` | a locked rotor, default Off; fields below |
| `stBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | default a warning; a protection's settings ([protections](../conventions.md#protections)) |

**`stHigh`, `stLow`, `stStartTooLong` (each; its own defaults are in the column above)** (`ST_CurrentLevelSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eResponse` | `E_Response` | `E_Response.Trip` | `Off`, `Warn`, `Trip` or `Signal` (see conventions) |
| `tDelay` | `TIME` | `T#1s` | The condition must last this long |
| `eReset` | `E_ResetMode` | `E_ResetMode.Retry` | `Auto`, `Manual` or `Retry` (see conventions) |
| `tRecover` | `TIME` | `T#10s` | The cause must be gone this long before it clears |
| `nMaxRetries` | `INT` | `3` | Retry: trips in the window before it locks out |
| `fPercent` | `REAL` |  | % of full load |
| `fDeadband` | `REAL` | `5.0` | % of full load: clears this far back |

**Status `sts`** (`ST_MotorCurrentSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fCurrent` | `REAL` |  | in the CT's unit |
| `fPercent` | `REAL` |  | of full load |
| `bProvesRun` | `BOOL` |  |  |
| `stHigh` | `ST_ProtectionSts` |  | overload by current, default Off; a protection's status ([protections](../conventions.md#protections)) |
| `stLow` | `ST_ProtectionSts` |  | dry run / broken belt, default Off; a protection's status ([protections](../conventions.md#protections)) |
| `stStartTooLong` | `ST_ProtectionSts` |  | a locked rotor, default Off; a protection's status ([protections](../conventions.md#protections)) |
| `stBad` | `ST_ProtectionSts` |  | default a warning; a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `tMaskLeft` | `TIME` |  | running: the start mask's time left (0 when past it or stopped) |

## How it works

A motor's current from a CT, as a part of its motor. Off until `set.fFullLoad` (the motor's full-load current, in the CT's unit) is set.

- `fPercent`: the current as % of full load. `bProvesRun`: at or above `set.fRunPercent`; wire it to the motor's `bFeedback` when the CT, not an auxiliary contact, proves the motor runs.
- `stHigh` (overload by current, default Off) and `stLow` (dry run / broken belt, default Off): % of full load with a deadband, checked once the motor runs (`bIsRunning`) and `set.tStartMask` has passed (`sts.tMaskLeft`: the time left of the mask).
- `stStartTooLong` (a locked rotor, default Off): the current still at or above its % while the motor's run command is on, for its delay.
- `stBad` (default a warning): the current is not good while monitoring is wanted; high / low / start checks then wait (they never act on a bad reading).

Settings are kept (a retained last-good copy, a bad write put back).

## Example

A pump motor's current from a 4-20 mA CT transmitter.

| Pin | Wire |
| --- | --- |
| `ipCurrent` | `fbCt` (an FB_AnalogIn in amps) |
| `ipOwner` | `fbMotor1` |
| `refData` | `stCurrent1` |
| `fPercent` | a display |

Set `stCurrent1.set.fFullLoad` to the motor's full-load current; the checks are off until it is set. Put this rung before the motor's rung.

**Back to** [the index](../README.md).
