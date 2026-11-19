# FB_PumpDiag — Pump hydraulic diagnosis

Names the likely cause of a pump's hydraulic trouble from its pressure, flow and suction: blocked, burst, suction low or no lift. It only tells; it stops nothing.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bPumpRunning` | `BOOL` |  | the pump runs |
| in | `ipPressure` | `I_Measurement` |  | optional. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipFlow` | `I_Measurement` |  | optional. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `ipSuction` | `I_Measurement` |  | optional. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `refData` | `REFERENCE TO ST_PumpDiagData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `eDiagnosis` | `E_PumpDiag` |  | Normal, Blocked, Burst, NoLift or Suction |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PumpDiagData` (pin `refData`)

**Settings `set`** (`ST_PumpDiagSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fHighPressureAbove` | `REAL` |  | in the pressure's unit (0 = off) |
| `fLowPressureBelow` | `REAL` |  | pressure below this (0 = off) |
| `fHighFlowAbove` | `REAL` |  | in the flow's unit (0 = off) |
| `fLowFlowBelow` | `REAL` |  | flow below this (0 = off) |
| `fLowSuctionBelow` | `REAL` |  | in the suction's unit (0 = off) |
| `tDiagnosisDelay` | `TIME` | `T#10s` | the finding must stand this long |

**Status `sts`** (`ST_PumpDiagSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eDiagnosis` | `E_PumpDiag` |  | Normal, Blocked, Burst, NoLift or Suction |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_PumpDiag`: `Normal`, `Blocked`, `Burst`, `NoLift`, `Suction` (default `Normal`)

## How it works

The likely cause of a pump's hydraulic trouble from its pressure, flow and suction. An observer: it only tells, the pump's [`FB_LevelCheck`](FB_LevelCheck.md) parts act.

While `bPumpRunning` (the pump runs), after `set.tDiagnosisDelay` of the same finding:

```
  Blocked   pressure high and flow low (a closed valve, a blocked line)
  Burst     pressure low and flow high (a burst or open line)
  Suction   suction low (a dry well, a blocked inlet)
  NoLift    pressure low and flow low (air-locked, worn, turning backwards)
```

in that order. Each measurement is optional (unwired, not fitted or not good: its tests are left out); each limit 0 is off. Not running: Normal.

## Example

A pump with pressure and flow transmitters.

| Pin | Wire |
| --- | --- |
| `bPumpRunning` | `fbMotor1.bRunOutput` (or the motor's run feedback) |
| `ipPressure` | `fbPressure` |
| `ipFlow` | `fbFlow` |
| `refData` | `stDiag1` |
| `eDiagnosis` | the HMI |

**Back to** [the index](../README.md).
