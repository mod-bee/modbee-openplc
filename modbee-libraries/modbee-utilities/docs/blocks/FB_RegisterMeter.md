# FB_RegisterMeter — Meter from a total register

A total from a device's own total register (a Modbus energy or flow meter, a BeeBus counter): increases counted, resets, wraps and glitches handled, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fRegisterTotal` | `LREAL` |  | the device's running total register, in its unit (LREAL keeps 32 bits exact) |
| in | `bInputGood` | `BOOL` | `TRUE` | the input can be trusted |
| in | `bPumpRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `refData` | `REFERENCE TO ST_RegisterMeterData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RegisterMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotals` | `BOOL` |  | the total back to 0 (cleared by the block) |
| `bCmdConfirmReset` | `BOOL` |  | confirms bCmdResetTotals (set.bResetNeedsConfirm); cleared by the block |
| `bCmdPresetTotal` | `BOOL` |  | the total to fPresetTotal (cleared by the block) |
| `fPresetTotal` | `LREAL` |  | the total bCmdPresetTotal writes, in the meter's unit |

**Settings `set`** (`ST_RegisterMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotalPerRegisterUnit` | `REAL` | `1.0` | total units per register unit |
| `eMeterUnit` | `E_Unit` |  | the volume unit of the register (None = no conversion) |
| `eTotalUnit` | `E_Unit` |  | the volume unit of the total (None = no conversion) |
| `fRegisterWrapsAt` | `LREAL` |  | the register wraps to 0 here (0 = never) |
| `fMaxStepPerRead` | `LREAL` |  | a larger increase in one read is a glitch (0 = no limit) |
| `tRateWindow` | `TIME` | `T#60s` | the rate is worked out over this window |
| `stMeterBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#30s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the meter's input is bad (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `bResetNeedsConfirm` | `BOOL` |  | a total reset needs the record's bCmdConfirmReset in the same write |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_RegisterMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | counting: the meter can be trusted |
| `fFlowPerHour` | `REAL` |  | per hour |
| `fLastGoodReading` | `LREAL` |  | the last good reading |
| `nGlitchCount` | `UDINT` |  | drops and too-large steps (not kept) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stMeterBadFault` | `ST_ProtectionSts` |  | the meter's input is bad (default a warning); a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_RegisterMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | the total (kept) |

## How it works

Totals from a device's own total register (a Modbus energy / flow meter, a BeeBus counter).

Offers `I_Meter` (the total, the rate per hour; an `I_Measurement` too: its rate).

Each increase adds (`fRegisterTotal` - the last) x `set.fTotalPerRegisterUnit`. A drop is a device reset or a glitch: nothing is counted, and only the part above the highest reading seen counts again, unless it is a wrap (`set.fRegisterWrapsAt` > 0: the register restarts from 0 past it; a fall from the top half to the bottom half counts the wrap). An increase above `set.fMaxStepPerRead` (0 = no limit) is a glitch: taken as the new reading, nothing counted. While bad nothing is counted; the register catches up when good again. Bad past `set.stMeterBadFault`'s delay: `bIsGood` FALSE, a warning (SensorBad). Units: `set.eMeterUnit` (the register's volume unit, with `fTotalPerRegisterUnit` applied after) and `set.eTotalUnit` (the total's), `E_Unit` volume units, both set convert each addition; both None = no conversion; one set, or a unit that is not a volume, is a bad setting (put back). The total is LREAL, kept hourly, when `bPumpRunning` falls (the pump stops; optional) and on a reset (`bCmdResetTotals`).

Total commands: `bCmdResetTotals` (with `set.bResetNeedsConfirm`, only together with `bCmdConfirmReset` in the same write) and `bCmdPresetTotal` (the total to `fPresetTotal`, 0 .. 1E12).

## Example

A Modbus flow meter's own total register.

| Pin | Wire |
| --- | --- |
| `fRegisterTotal` | `fMeterTotalReg` |
| `bInputGood` | `bModbusOk` |
| `refData` | `stMeter` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActTotal : LREAL`: the lifetime total in its unit
- property `fActFlowPerHour : REAL`: the rate, per hour
- property `bIsGood : BOOL`: the value can be trusted now
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in set.eTotalUnit per hour, no bands
- property `bHasValue : BOOL`: a value is available (fitted and read at least once)
- property `bIsFitted : BOOL`: fitted on this site
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
