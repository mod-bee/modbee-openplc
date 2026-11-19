# FB_MeterCycle — This cycle / last cycle on a meter

This cycle's and the last cycle's quantity on any meter (a pump run, a fill): a rollover, e.g. the pump's start, closes the cycle; kept over a power cut.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bCloseCycle` | `BOOL` | `FALSE` | rising edge: close the cycle |
| in | `ipMeter` | `I_Meter` |  | required. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `bPumpRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `dtLocalTime` | `DT` |  | optional: the local time, for tot.dtLastCycleEnd |
| in | `refData` | `REFERENCE TO ST_MeterCycleData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MeterCycleData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdCloseCycle` | `BOOL` |  | close the cycle (cleared by the block) |

**Totals `tot`** (`ST_MeterCycleTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fThisCycle` | `LREAL` |  | this cycle so far, in the meter's total unit |
| `fLastCycle` | `LREAL` |  | the last cycle |
| `nCycleCount` | `UDINT` |  | cycles closed (a sequence number for the last one) |
| `dtLastCycleEnd` | `DT` |  | when the last cycle closed (dtLocalTime; blank when unwired) |

## How it works

This cycle's and the last cycle's quantity on any meter (a pump run, a fill, an irrigation): an observer that reads its meter and changes nothing.

## Example

The irrigation volume this cycle and last cycle, for the panel and SCADA.

| Pin | Wire |
| --- | --- |
| `bCloseCycle` | `fbPump1.bRunCommand` (each pump start closes the cycle) |
| `ipMeter` | `fbFlowMeter` |
| `bPumpRunning` | `DI_P1_Running` |
| `refData` | `stIrrCycle` |

Show `stIrrCycle.tot.fThisCycle` and `stIrrCycle.tot.fLastCycle`.

**Back to** [the index](../README.md).
