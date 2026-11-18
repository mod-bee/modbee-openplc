# FB_MeterCycle — This cycle / last cycle on a meter

This cycle's and the last cycle's quantity on any meter (a pump run, a fill): a rollover, e.g. the pump's start, closes the cycle; kept over a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRollover` | `BOOL` | `FALSE` | rising edge: close the cycle |
| in | `ipMeter` | `I_Meter` |  | required. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `bRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `dtClock` | `DT` |  | optional: the local time, for tot.dtLastEnd |
| in | `refData` | `REFERENCE TO ST_MeterCycleData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeterCycleData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdRollover` | `BOOL` |  | close the cycle (cleared by the block) |

**Totals `tot`** (`ST_MeterCycleTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fThis` | `LREAL` |  | this cycle so far, in the meter's total unit |
| `fLast` | `LREAL` |  | the last cycle |
| `nCycles` | `UDINT` |  | cycles closed (a sequence number for the last one) |
| `dtLastEnd` | `DT` |  | when the last cycle closed (dtClock; blank when unwired) |

## How it works

This cycle's and the last cycle's quantity on any meter (a pump run, a fill, an irrigation): an observer that reads its meter and changes nothing.

## Example

The irrigation volume this cycle and last cycle, for the panel and SCADA.

| Pin | Wire |
| --- | --- |
| `bRollover` | `fbPump1.bRunCmd` (each pump start closes the cycle) |
| `ipMeter` | `fbFlowMeter` |
| `bRunning` | `DI_P1_Running` |
| `refData` | `stIrrCycle` |

Show `stIrrCycle.tot.fThis` and `stIrrCycle.tot.fLast`.

**Back to** [the index](../README.md).
