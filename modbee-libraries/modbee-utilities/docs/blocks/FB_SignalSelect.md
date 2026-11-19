# FB_SignalSelect — Sensor voting

Two or three sensors measuring the same thing, voted into one trusted measurement.

Offers `I_Measurement`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipSensor1` | `I_Measurement` |  | NULL = not fitted, never used. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipSensor2` | `I_Measurement` |  | second sensor (unwired = not fitted). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipSensor3` | `I_Measurement` |  | third sensor (unwired = not fitted). An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bResetFaults` | `BOOL R_EDGE` |  | rising edge: reset latched faults whose cause has gone |
| in | `refData` | `REFERENCE TO ST_SelectData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `fValue` | `REAL` |  | voted value (while not good: per eWhenNoneGood) |
| out | `bGood` | `BOOL` |  | the voted value can be used |
| out | `fSpread` | `REAL` |  | the largest difference between usable sensors |
| out | `nSensorDropped` | `INT` |  | the sensor dropped (1..3), 0 none |
| out | `nSensorsGood` | `INT` |  | usable sensors |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_SelectData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | as bResetFaults (cleared by the block) |

**Settings `set`** (`ST_SelectSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eCombineBy` | `E_SelectMode` |  | combine the agreeing sensors |
| `eWhenTwoDisagree` | `E_SelectMode` | `E_SelectMode.Highest` | two that disagree: Highest or Lowest |
| `fWarnSpreadAbove` | `REAL` | `1.0` | sensors further apart than this warn (stDeviation) |
| `fDisagreeSpreadAbove` | `REAL` | `2.0` | sensors further apart than this do not agree |
| `stDeviationFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#0s, nMaxRetriesBeforeLockout := 3)` | one sensor far from the others: protection settings; a protection's settings ([protections](../conventions.md#protections)) |
| `stNoAgreementFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#10s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#10s, nMaxRetriesBeforeLockout := 3)` | no two sensors agree: protection settings; a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry counts trips within this window (0 = until a reset) |
| `tFilterTime` | `TIME` |  | filter time on the voted value (0 = none) |
| `eWhenNoneGood` | `E_NoGood` |  | fValue while not good |
| `fSubstituteValue` | `REAL` |  | the value used by Substitute |

**Status `sts`** (`ST_SelectSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fValue` | `REAL` |  | the voted value; while not good per eWhenNoneGood |
| `fSpread` | `REAL` |  | the largest difference between usable sensors |
| `nSensorUsed` | `INT` |  | the sensor used (1..3), 0 = a combination or none |
| `nSensorsGood` | `INT` |  | usable sensors |
| `nSensorDropped` | `INT` |  | the sensor dropped (1..3), 0 none |
| `bGood` | `BOOL` |  | the voted value can be trusted |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stDeviationFault` | `ST_ProtectionSts` |  | deviation protection status; a protection's status ([protections](../conventions.md#protections)) |
| `stNoAgreementFault` | `ST_ProtectionSts` |  | no-agreement protection status; a protection's status ([protections](../conventions.md#protections)) |

## Lists

- `E_NoGood`: `Hold`, `Lowest`, `Highest`, `Substitute`, `Midpoint` (default `Hold`)
- `E_SelectMode`: `Average`, `Lowest`, `Highest`, `Median`, `Primary` (default `Average`)

## How it works

Two or three sensors measuring the same thing, voted into one trusted measurement. Wire the instance to any `I_Measurement` pin.

A sensor is usable when it is fitted, good, has a value and the value is a number. Two sensors agree when they are within `set.fDisagreeSpreadAbove`.

```
  3 usable  all agree: combined by set.eCombineBy. One agrees with neither of the others while those two agree: it
            is dropped (nSensorDropped, warning SensorDeviates). No two agree: no agreement.
  2 usable  agree: combined by eCombineBy. Not: warning SensorsDisagree, set.eWhenTwoDisagree (Highest or Lowest) used.
  1 usable  used, warning OneSensorLeft.
  0 usable  no agreement.
```

No agreement is a protection (`set.stNoAgreementFault`, default Trip after 10 s, Auto): ridden through with the last voted value, then `bGood` FALSE, `bError` SensorsDisagree, `fValue` per `eWhenNoneGood` (Hold, Lowest / Highest of the raw values, Substitute `set.fSubstituteValue`, Midpoint of the raw values). The spread is another (`set.stDeviationFault`, default Warn after 5 s): `fSpread` above `set.fWarnSpreadAbove`, or a sensor dropped. `set.tFilterTime` smooths `fValue` (low-pass). No sensor wired: `bError` NoMeasurement. Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. `eUnit`: sensor 1's.

## Example

Two level transmitters voted into one.

| Pin | Wire |
| --- | --- |
| `ipSensor1` | `fbLevelA` |
| `ipSensor2` | `fbLevelB` |
| `refData` | `stVote` |
| `fValue` | a display |

Wire `fbVote` to the blocks that use the level.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActValue : REAL`: the value in its unit (held at the last good one while bad, when so set)
- property `bIsGood : BOOL`: the value can be trusted now
- property `bHasValue : BOOL`: a continuous value (FALSE: switches only)
- property `bIsFitted : BOOL`: the sensor is on this site (FALSE: no value, no bands, no fault)
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
