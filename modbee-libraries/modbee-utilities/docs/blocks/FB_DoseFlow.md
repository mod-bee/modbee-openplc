# FB_DoseFlow — Flow-paced dosing

Doses in proportion to the carrier flow (fertigation, chlorination): the dosing pump's speed follows the flow, or stroke pulses go to a pulse pump; Hand runs it at a set rate.

It is one of the `FB_Dose` family: the common part is described under *How it works*.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bCarrierRunning` | `BOOL` | `TRUE` | the carrier (irrigation) pump runs |
| in | `ipCarrierMeter` | `I_Meter` |  | the carrier meter. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `fDosePerCarrierUnit` | `REAL` |  | this run's ratio (<= 0 = set.fDosePerCarrierUnit) |
| in | `refData` | `REFERENCE TO ST_DoseFlowData` |  | the block's record |
| in | `bRun` | `BOOL` |  | Batch: rising starts a dose; Flow / Timed: doses while TRUE *(from FB_Dose)* |
| in | `bStart` | `BOOL` |  | rising: Batch starts / resumes; Flow / Timed: a run latched until a stop *(from FB_Dose)* |
| in | `bStop` | `BOOL` |  | rising: ends the dose (a held bRun must drop first) *(from FB_Dose)* |
| in | `bResetFaults` | `BOOL` |  | rising: resets trips whose cause has gone *(from FB_Dose)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: the pump off *(from FB_Dose)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: holds back a dose start *(from FB_Dose)* |
| in | `bStockLowSwitch` | `BOOL` |  | the chemical stock is low (a level switch) *(from FB_Dose)* |
| in | `bPause` | `BOOL` |  | pause *(from FB_Dose)* |
| in | `bAbortWhileHeld` | `BOOL` |  | end, refuse a start *(from FB_Dose)* |
| in | `ipDosingPump` | `I_Equipment` |  | optional: the dosing pump *(from FB_Dose)* |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bStrokePulse` | `BOOL` |  | stroke pulses |
| out | `bPumpRunCommand` | `BOOL` |  | run the dosing pump *(from FB_Dose)* |
| out | `fPumpSpeedPct` | `REAL` |  | % *(from FB_Dose)* |
| out | `bBusy` | `BOOL` |  | a dose is on *(from FB_Dose)* |
| out | `bDone` | `BOOL` |  | a Batch dose completed (one scan) *(from FB_Dose)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_DoseFlowData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdDoseMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto: once, then -1 (cleared) |
| `bCmdStart` | `BOOL` |  | start a dose (cleared by the block) |
| `bCmdStop` | `BOOL` |  | end the dose (cleared) |
| `bCmdPause` | `BOOL` |  | pause until the next start (cleared) |
| `bCmdResetFaults` | `BOOL` |  | reset trips whose cause has gone (cleared) |
| `bCmdAbort` | `BOOL` |  | end the dose now, stop reason Abort (cleared) |

**Details `det`** (`ST_DoseDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tThisDoseTime` | `TIME` |  | time in this dose |
| `tTimeLeft` | `TIME` |  | time left in the delay or phase running now |
| `nStrokePulses` | `UDINT` |  | stroke pulses given in this dose |

**Totals `tot`** (`ST_DoseTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nDosedMillionths` | `LINT` |  | millionths of a unit |
| `nDoseCount` | `UDINT` |  | Batch doses completed |

**Settings `set`** (`ST_DoseFlowSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bDosingEnabled` | `BOOL` | `TRUE` | FALSE: no dosing (a dose ends, stop reason Off) |
| `fFlowAtFullSpeed` | `REAL` |  | the dosing pump at 100 %, dose units per hour |
| `fMaxQuantityPerDose` | `LREAL` |  | per dose (0 = off) |
| `stMaxDoseTimeFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Off, tTripDelay := T#1h, eResetMode := E_ResetMode.Manual)` | a dose lasted longer than the delay (default Off); a protection's settings ([protections](../conventions.md#protections)) |
| `stStockLowFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Trip, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#30s)` | the chemical stock is low (bStockLow); a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryCountWindow` | `TIME` | `T#1h` | Retry counts trips within this window (0 = until a reset) |
| `eMode` | `E_Mode` | `E_Mode.Auto` | Off, Hand or Auto (kept) |
| `fHandSpeedPct` | `REAL` | `50.0` | Hand: the pump's speed, % |
| `bHandNeedsCarrier` | `BOOL` | `TRUE` | Hand: the carrier must be proven (Flow / Timed) |
| `tMaxHandRunTime` | `TIME` | `T#5m` | Hand: the longest run (0 = no limit) |
| `fDosePerCarrierUnit` | `REAL` |  | dose units per carrier unit |
| `fMinCarrierFlow` | `REAL` |  | carrier flow needed (per hour) |
| `tCarrierProveDelay` | `TIME` | `T#10s` | the carrier must run this long before dosing (waiting, not a fault) |
| `fMaxPumpSpeedPct` | `REAL` | `100.0` | % |
| `fDosePerStroke` | `REAL` |  | dose per stroke pulse (0 = no pulses) |
| `tStrokePulseWidth` | `TIME` | `T#200ms` | length of each stroke pulse |
| `stOverCapacityFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, eResetMode := E_ResetMode.Auto)` | the dose needs more than the pump gives (a trip holds the dose); a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_DoseFlowSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eDosePhase` | `E_DosePhase` |  | Idle, Fast, Slow, Settle, Held, Done, Aborted, Dosing or Waiting |
| `eStopReason` | `E_StopReason` |  | why the last dose ended |
| `bPaused` | `BOOL` |  | a dose is paused |
| `bMaxQuantityReached` | `BOOL` |  | fMaxQuantityPerDose ended a dose (until a reset) |
| `fPumpSpeedPct` | `REAL` |  | % |
| `fDeliveredThisDose` | `LREAL` |  | this dose so far |
| `fDeliveredLastDose` | `LREAL` |  | delivered in the last dose |
| `stMaxDoseTimeFault` | `ST_ProtectionSts` |  | a dose lasted longer than the delay (default Off); a protection's status ([protections](../conventions.md#protections)) |
| `stStockLowFault` | `ST_ProtectionSts` |  | the chemical stock is low (bStockLow); a protection's status ([protections](../conventions.md#protections)) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `eModeInUse` | `E_Mode` |  | the mode in use |
| `bHandRunActive` | `BOOL` |  | a Hand run is on |
| `bCarrierProven` | `BOOL` |  | the carrier is proven |
| `fDoseRateNeeded` | `REAL` |  | dose units per hour |
| `fRatioInUse` | `REAL` |  | the dose ratio this run uses |
| `stOverCapacityFault` | `ST_ProtectionSts` |  | the dose needs more than the pump gives (a trip holds the dose); a protection's status ([protections](../conventions.md#protections)) |

## Lists

- `E_DosePhase`: `Idle`, `Fast`, `Slow`, `Settle`, `Held`, `Done`, `Aborted`, `Dosing`, `Waiting` (default `Idle`)

## How it works

Flow-paced dosing (fertigation).

While `bRun` (or a `bStart` latch) the dosing pump runs in proportion to the carrier: the meter's rate (per hour) x the ratio (`fDosePerCarrierUnit` pin for this run, <= 0 = `set.fDosePerCarrierUnit`); `fPumpSpeedPct` = required / `set.fFlowAtFullSpeed` %, capped at `set.fMaxPumpSpeedPct` (no capacity: `fMaxPumpSpeedPct`, a pulse pump). It injects only while `bCarrierRunning` and the carrier flow has been at / above `set.fMinCarrierFlow` for `set.tCarrierProveDelay` (Waiting, not a fault). `bStrokePulse`: one stroke every `set.fDosePerStroke` dosed (0 = none), `set.tStrokePulseWidth` on and off. Asked for more than the pump can give: `set.stOverCapacityFault` (a trip holds the dose).

### Common to the FB_Dose family

`bRun` / `bStart` / `bStop` / `bResetFaults` and the record's commands (`bCmdStart`, `bCmdStop`, `bCmdPause`, `bCmdResetFaults`: once per write); `bInterlock` FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held); `bPermissive` FALSE holds back a dose start; `bPause` and `bCmdPause` (until the next start) pause; `bStop`, `bCmdStop`, `bAbortWhileHeld`, the record's `bCmdAbort` (stop reason Abort), `set.bDosingEnabled` FALSE end a dose (a held `bRun` must drop before it doses again); `bStockLowSwitch` -> `set.stStockLowFault`; `set.stMaxDoseTimeFault` and `set.fMaxQuantityPerDose` cap a dose. `ipDosingPump` (optional): the dosing pump, asked to run at `fPumpSpeedPct` while dosing and held while `bInterlock` is FALSE; dosing counts only while it runs.

Modes (`set.eMode`, kept; the record's `nCmdDoseMode` 0 Off / 1 Hand / 2 Auto, once, or a Command from [`FB_LocalControl`](FB_LocalControl.md), which drives a dose like a pump: IMPLEMENTS `I_Equipment`): Auto doses as above; Hand: a start (`bStart`, `bCmdStart`, the panel's start button) runs the pump at `set.fHandSpeedPct` % until a stop, `set.tMaxHandRunTime` (0 = no limit), the interlock FALSE, an abort, `set.bDosingEnabled` FALSE, a stop-trip or the mode left; with `set.bHandNeedsCarrier` the carrier must be proven (Flow / Timed; a Batch has none), else the pump waits (Held); a Hand run counts into the totals but is no dose (`nDoseCount`); Off: nothing doses. Hand never resumes after a power cut. An owner's Request(`bRun`) is a `bRun` (`bPause` = not asked); a variant's own pins and records work in Auto only. tot (millionths of a unit, and the doses) is kept at each dose end and every hour.

## Example

Fertigation: dose in proportion to the irrigation flow.

| Pin | Wire |
| --- | --- |
| `bRun` | `fbZoneSeq.bBusy` |
| `bCarrierRunning` | `DI_IrrPump_Running` (the irrigation pump's run feedback) |
| `ipCarrierMeter` | `fbIrrFlow` (an FB_PulseMeter) |
| `ipDosingPump` | `fbDosingMotor` |
| `bStockLowSwitch` | `DI_StockLow` |
| `refData` | `stDose` |

Set `stDose.set.fDosePerCarrierUnit` (dose units per carrier unit) and `fFlowAtFullSpeed` (per hour).

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Request(bRun, bHoldOff, fSpeedSetpointPct, bOverflowUrgent) : E_UtError`: I_Equipment: an owner's request, a Command (FB_LocalControl) and the state, as a pump's
- method `Command(eCommand)`
- property `eActMode : E_Mode`: the mode it is in now
- property `bIsRunning : BOOL`: running now
- property `bIsReady : BOOL`: could start now if asked
- property `bIsAvailable : BOOL`: in Auto, not tripped, not interlocked
- property `bIsAuto : BOOL`: in Auto now
- property `bIsFaulted : BOOL`: a trip or setting fault is active
- property `eActError : E_UtError`: the error shown now
- property `eActStopReason : E_StopReason`: why it last stopped (None while one runs)
- property `fActRunHours : REAL`: a dose counts no hours

## See also

[FB_DoseBatch](FB_DoseBatch.md), [FB_DoseTimed](FB_DoseTimed.md)

**Back to** [the index](../README.md).
