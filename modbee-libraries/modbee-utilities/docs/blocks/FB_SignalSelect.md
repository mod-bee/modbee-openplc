# FB_SignalSelect — Sensor voting

Two or three sensors measuring the same thing, voted into one trusted measurement.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipSensor1` | `I_Measurement` |  | NULL = not fitted, never used. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipSensor2` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `ipSensor3` | `I_Measurement` |  | A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `bReset` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_SelectData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `fOut` | `REAL` |  | voted value (while not good: per eNoGood) |
| out | `bGood` | `BOOL` |  | the voted value can be used |
| out | `fSpread` | `REAL` |  | the largest difference between usable sensors |
| out | `nDeviating` | `INT` |  | the sensor dropped (1..3), 0 none |
| out | `nGoodCount` | `INT` |  | Usable sensors |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SelectData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | as bReset (cleared by the block) |

**Settings `set`** (`ST_SelectSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSelect` | `E_SelectMode` |  | combine the agreeing sensors |
| `eTwoDisagree` | `E_SelectMode` | `E_SelectMode.Highest` | two that disagree: Highest or Lowest |
| `fWarnSpread` | `REAL` | `1.0` |  |
| `fFaultSpread` | `REAL` | `2.0` | sensors further apart than this do not agree |
| `stDeviation` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#0s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stNoAgree` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#10s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryWindow` | `TIME` | `T#1h` | Retry protections count their trips within this window |
| `tFilter` | `TIME` |  |  |
| `eNoGood` | `E_NoGood` |  | fOut while not good |
| `fSubstitute` | `REAL` |  |  |

**Status `sts`** (`ST_SelectSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fOut` | `REAL` |  | the voted value; while not good per set.eNoGood |
| `fSpread` | `REAL` |  | the largest difference between usable sensors |
| `nSelected` | `INT` |  | the sensor used (1..3), 0 = a combination or none |
| `nGoodCount` | `INT` |  |  |
| `nDeviating` | `INT` |  | the sensor dropped (1..3), 0 none |
| `bGood` | `BOOL` |  | The value can be trusted |
| `bRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stDeviation` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stNoAgree` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

## Lists

- `E_NoGood`: `Hold`, `Lowest`, `Highest`, `Substitute`, `Midpoint` (default `Hold`)
- `E_SelectMode`: `Average`, `Lowest`, `Highest`, `Median`, `Primary` (default `Average`)

## How it works

Two or three sensors measuring the same thing, voted into one trusted measurement. Wire the instance to any `I_Measurement` pin.

A sensor is usable when it is fitted, good, has a value and the value is a number. Two sensors agree when they are within `set.fFaultSpread`.

```
  3 usable  all agree: combined by set.eSelect. One agrees with neither of the others while those two agree: it
            is dropped (nDeviating, warning SensorDeviates). No two agree: no agreement.
  2 usable  agree: combined by eSelect. Not: warning SensorsDisagree, set.eTwoDisagree (Highest or Lowest) used.
  1 usable  used, warning OneSensorLeft.
  0 usable  no agreement.
```

No agreement is a protection (`set.stNoAgree`, default Trip after 10 s, Auto): ridden through with the last voted value, then `bGood` FALSE, `bError` SensorsDisagree, `fOut` per `eNoGood` (Hold, Lowest / Highest of the raw values, Substitute `set.fSubstitute`, Midpoint of the raw values). The spread is another (`set.stDeviation`, default Warn after 5 s): `fSpread` above `set.fWarnSpread`, or a sensor dropped. `set.tFilter` smooths `fOut` (low-pass). No sensor wired: `bError` NoMeasurement. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. `eUnit`: sensor 1's.

## Example

Two level transmitters voted into one.

| Pin | Wire |
| --- | --- |
| `ipSensor1` | `fbLevelA` |
| `ipSensor2` | `fbLevelB` |
| `refData` | `stVote` |
| `fOut` | a display |

Wire `fbVote` to the blocks that use the level.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActValue : REAL`
- property `bIsGood : BOOL`
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
