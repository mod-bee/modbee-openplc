# FB_SwitchSet — Level switches

Up to four level switches (LL, L, H, HH) and one plain contact as one measurement, each debounced, with a quality per switch and a check that the switches agree.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLL` | `BOOL` | `FALSE` | The low-low switch (TRUE = in that band) |
| in | `bL` | `BOOL` |  | The low switch |
| in | `bH` | `BOOL` |  | The high switch |
| in | `bHH` | `BOOL` |  | TRUE = the level is in that band: wire NOT at the pin for a contact that opens |
| in | `bContact` | `BOOL` |  | A plain contact (a float, a pressure or flow switch, a door) |
| in | `bLLGood` | `BOOL` | `TRUE` | The low-low switch's input is healthy |
| in | `bLGood` | `BOOL` | `TRUE` | The low switch's input is healthy |
| in | `bHGood` | `BOOL` | `TRUE` | The high switch's input is healthy |
| in | `bHHGood` | `BOOL` | `TRUE` | The high-high switch's input is healthy |
| in | `bContactGood` | `BOOL` | `TRUE` | default TRUE: the IO module / comms are healthy |
| in | `refData` | `REFERENCE TO ST_SwitchSetData` |  | Its record (a variable of this type) |
| in | `stConfig` | `ST_SwitchSetConfig` |  | engineering constants (set at the declaration) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bLowLow` | `BOOL` |  | The low-low switch / level |
| out | `bLow` | `BOOL` |  | L or LL |
| out | `bHigh` | `BOOL` |  | H or HH |
| out | `bHighHigh` | `BOOL` |  | The high-high switch / level |
| out | `bQ` | `BOOL` |  | the plain contact, debounced |
| out | `bGood` | `BOOL` |  | The value can be trusted |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SwitchSetData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | reset a latched fault (cleared by the block) |

**Settings `set`** (`ST_SwitchSetSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bFitted` | `BOOL` | `TRUE` | FALSE: not on this site (not good, no fault) |
| `stDisagree` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#10s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | default a warning; a protection's settings ([protections](../conventions.md#protections)) |
| `stInputBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_SwitchSetSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLowLow` | `BOOL` |  | The low-low switch / level |
| `bLow` | `BOOL` |  | L or LL |
| `bHigh` | `BOOL` |  | H or HH |
| `bHighHigh` | `BOOL` |  | The high-high switch / level |
| `bContact` | `BOOL` |  |  |
| `bGood` | `BOOL` |  | The value can be trusted |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `stDisagree` | `ST_ProtectionSts` |  | default a warning; a protection's status ([protections](../conventions.md#protections)) |
| `stInputBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

## Constants `ST_SwitchSetConfig` (pin `stConfig`)

Set once, at the variable's declaration (engineering constants, not changed while running).

**Fields** (`ST_SwitchSetConfig`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bUseLL` | `BOOL` |  | the low-low switch is fitted |
| `bUseL` | `BOOL` |  |  |
| `bUseH` | `BOOL` |  |  |
| `bUseHH` | `BOOL` |  |  |
| `bUseContact` | `BOOL` |  | the plain contact is fitted |
| `tDebounce` | `TIME` | `T#2s` | level switches |
| `tContactDebounce` | `TIME` | `T#50ms` |  |
| `tRetryWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window |

## How it works

Up to four level switches (LL, L, H, HH) on one vessel or line as switch bands, and one plain contact (a float, a pressure or flow switch, a door), each debounced, with a quality per switch. Wire the instance to any `I_Measurement` pin: owners read the bands through Band(`E_Band.HighHigh`) ...; rungs read `bLowLow` .. `bHighHigh` and `bQ`.

A switch follows its input once the input has held its new state for the debounce time (power-up: at once).

A switch whose quality is bad holds its last state; after `set.stInputBad` it trips (SensorBad, not good).

Disagree (high and low together, HH without H, LL without L) acts per `set.stDisagree` (default a warning); the switches are still reported as read. `set.bFitted` FALSE: not on this site (not good, no fault).

Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

A chattering contact: [`FB_DigitalIn`](FB_DigitalIn.md)'s chatter check, on each switch before it reaches this block.

## Example

High and low floats in a sump.

| Pin | Wire |
| --- | --- |
| `bH` | `DI_HighFloat` |
| `bL` | `DI_LowFloat` |
| `refData` | `stFloats` |
| `stConfig` | `cfgFloats` (which switches are fitted) |
| `bHigh` | a lamp |

Wire `fbFloats` to FB_LevelFloats' `ipFloats`, or to an FB_LevelCheck's `ipMeas`.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
