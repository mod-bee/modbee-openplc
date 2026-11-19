# FB_SwitchSet — Level switches

Up to four level switches (LL, L, H, HH) and one plain contact as one measurement, each debounced, with a quality per switch and a check that the switches agree.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLowLowSwitch` | `BOOL` | `FALSE` | the low-low switch (TRUE = the level is in that band; NOT at the pin for a contact that opens) |
| in | `bLowSwitch` | `BOOL` |  | the low switch (TRUE = in that band) |
| in | `bHighSwitch` | `BOOL` |  | the high switch (TRUE = in that band) |
| in | `bHighHighSwitch` | `BOOL` |  | the high-high switch (TRUE = in that band) |
| in | `bContact` | `BOOL` |  | a plain contact (a float, a pressure or flow switch, a door) |
| in | `bLowLowSwitchGood` | `BOOL` | `TRUE` | the low-low switch's input is healthy |
| in | `bLowSwitchGood` | `BOOL` | `TRUE` | the low switch's input is healthy |
| in | `bHighSwitchGood` | `BOOL` | `TRUE` | the high switch's input is healthy |
| in | `bHighHighSwitchGood` | `BOOL` | `TRUE` | the high-high switch's input is healthy |
| in | `bContactGood` | `BOOL` | `TRUE` | the contact's input is healthy (IO module, comms) |
| in | `refData` | `REFERENCE TO ST_SwitchSetData` |  | the block's record |
| in | `stConfig` | `ST_SwitchSetConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bLowLow` | `BOOL` |  | the low-low switch / level |
| out | `bLowOrBelow` | `BOOL` |  | L or LL |
| out | `bHighOrAbove` | `BOOL` |  | H or HH |
| out | `bHighHigh` | `BOOL` |  | the high-high switch / level |
| out | `bGood` | `BOOL` |  | the switches can be trusted |
| out | `bContactDebounced` | `BOOL` |  | the plain contact, debounced |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SwitchSetData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | reset a latched fault (cleared by the block) |

**Settings `set`** (`ST_SwitchSetSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bSensorFitted` | `BOOL` | `TRUE` | FALSE: not on this site (not good, no fault) |
| `stSwitchOrderFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#10s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | switches out of order (high and low together, HH without H, LL without L); default a warning; a protection's settings ([protections](../conventions.md#protections)) |
| `stInputBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | a switch input is bad: protection settings; a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_SwitchSetSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLowLow` | `BOOL` |  | the low-low switch / level |
| `bLowOrBelow` | `BOOL` |  | L or LL |
| `bHighOrAbove` | `BOOL` |  | H or HH |
| `bHighHigh` | `BOOL` |  | the high-high switch / level |
| `bContact` | `BOOL` |  | the plain contact, debounced |
| `bGood` | `BOOL` |  | the switches can be trusted |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stSwitchOrderFault` | `ST_ProtectionSts` |  | switches out of order (high and low together, HH without H, LL without L); default a warning; a protection's status ([protections](../conventions.md#protections)) |
| `stInputBadFault` | `ST_ProtectionSts` |  | input-bad protection status; a protection's status ([protections](../conventions.md#protections)) |

## Constants `ST_SwitchSetConfig` (pin `stConfig`)

**Fields** (`ST_SwitchSetConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLowLowSwitchFitted` | `BOOL` |  | the low-low switch is fitted |
| `bLowSwitchFitted` | `BOOL` |  | the low switch is fitted |
| `bHighSwitchFitted` | `BOOL` |  | the high switch is fitted |
| `bHighHighSwitchFitted` | `BOOL` |  | the high-high switch is fitted |
| `bContactFitted` | `BOOL` |  | the plain contact is fitted |
| `tLevelSwitchDebounceTime` | `TIME` | `T#2s` | level switches |
| `tContactDebounceTime` | `TIME` | `T#50ms` | debounce of the plain contact |

Set once, at the variable's declaration (engineering constants, not changed while running).

## How it works

Up to four level switches (LL, L, H, HH) on one vessel or line as switch bands, and one plain contact (a float, a pressure or flow switch, a door), each debounced, with a quality per switch. Wire the instance to any `I_Measurement` pin: owners read the bands through Band(`E_Band.HighHigh`) ...; rungs read `bLowLow` .. `bHighHigh` and `bContactDebounced`.

A switch follows its input once the input has held its new state for the debounce time (power-up: at once).

A switch whose quality is bad holds its last state; after `set.stInputBadFault` it trips (SensorBad, not good).

Disagree (high and low together, HH without H, LL without L) acts per `set.stSwitchOrderFault` (default a warning); the switches are still reported as read. `set.bSensorFitted` FALSE: not on this site (not good, no fault).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

A chattering contact: [`FB_DigitalIn`](FB_DigitalIn.md)'s chatter check, on each switch before it reaches this block.

## Example

High and low floats in a sump.

| Pin | Wire |
| --- | --- |
| `bHighSwitch` | `DI_HighFloat` |
| `bLowSwitch` | `DI_LowFloat` |
| `refData` | `stFloats` |
| `stConfig` | `cfgFloats` (which switches are fitted) |
| `bHighOrAbove` | a lamp |

Wire `fbFloats` to FB_LevelFloats' `ipFloats`, or to an FB_LevelCheck's `ipMeasurement`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
