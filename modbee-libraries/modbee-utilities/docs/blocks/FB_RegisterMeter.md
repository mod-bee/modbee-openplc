# FB_RegisterMeter — Meter from a total register

A total from a device's own total register (a Modbus energy or flow meter, a BeeBus counter): increases counted, resets, wraps and glitches handled, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `fRegister` | `LREAL` |  | the device's running total, in its unit; LREAL so a 32-bit register stays exact |
| in | `bInGood` | `BOOL` | `TRUE` | the read can be trusted |
| in | `bRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `refData` | `REFERENCE TO ST_RegisterMeterData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RegisterMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotal` | `BOOL` |  | the total back to 0 (cleared by the block) |

**Settings `set`** (`ST_RegisterMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fScale` | `REAL` | `1.0` | total units per register unit |
| `eInUnit` | `E_Unit` |  | the volume unit of the register (None = no conversion) |
| `eOutUnit` | `E_Unit` |  | the volume unit of the total (None = no conversion) |
| `fRolloverAt` | `LREAL` |  | the register wraps to 0 here (0 = never) |
| `fMaxStep` | `LREAL` |  | a larger increase in one read is a glitch (0 = no limit) |
| `tRateWindow` | `TIME` | `T#60s` | The rate is worked out over this window |
| `stInputBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#30s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_RegisterMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | The value can be trusted |
| `fRate` | `REAL` |  | per hour |
| `fRegister` | `LREAL` |  | the last good reading |
| `nGlitches` | `UDINT` |  | drops and too-large steps (not kept) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `stInputBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_RegisterMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | The total (kept) |

## How it works

Totals from a device's own total register (a Modbus energy / flow meter, a BeeBus counter).

Offers `I_Meter` (the total, the rate per hour; an `I_Measurement` too: its rate).

Each increase adds (`fRegister` - the last) x `set.fScale`. A drop is a device reset or a glitch: nothing is counted, and only the part above the highest reading seen counts again, unless it is a wrap (`set.fRolloverAt` > 0: the register restarts from 0 past it; a fall from the top half to the bottom half counts the wrap). An increase above `set.fMaxStep` (0 = no limit) is a glitch: taken as the new reading, nothing counted. While bad nothing is counted; the register catches up when good again. Bad past `set.stInputBad`'s delay: `bIsGood` FALSE, a warning (SensorBad). Units: `set.eInUnit` (the register's volume unit, with `fScale` applied after) and `set.eOutUnit` (the total's), `E_Unit` volume units, both set convert each addition; both None = no conversion; one set, or a unit that is not a volume, is a bad setting (put back). The total is LREAL, kept hourly, when `bRunning` falls (the pump stops; optional) and on a reset (`bCmdResetTotal`).

## Example

A Modbus flow meter's own total register.

| Pin | Wire |
| --- | --- |
| `fRegister` | `fMeterTotalReg` |
| `bInGood` | `bModbusOk` |
| `refData` | `stMeter` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActTotal : LREAL`
- property `fActRate : REAL`
- property `bIsGood : BOOL`
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in set.eOutUnit per hour, no bands
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
