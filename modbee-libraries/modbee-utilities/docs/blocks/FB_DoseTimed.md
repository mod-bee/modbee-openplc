# FB_DoseTimed — Timed dosing

Timed dosing: the dosing pump on for a set time, off for a set time, over and over, while the carrier runs; Hand runs it at a set rate.

It is one of the `FB_Dose` family: the common part is described under *How it works*.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bCarrierRunning` | `BOOL` | `TRUE` | the carrier (irrigation) pump runs |
| in | `refData` | `REFERENCE TO ST_DoseTimedData` |  | Its record (a variable of this type) |
| in | `bRun` | `BOOL` |  | Batch: rising starts a dose; Flow / Timed: doses while TRUE *(from FB_Dose)* |
| in | `bStart` | `BOOL` |  | rising: Batch starts / resumes; Flow / Timed: a run latched until a stop *(from FB_Dose)* |
| in | `bStop` | `BOOL` |  | rising: ends the dose (a held bRun must drop first) *(from FB_Dose)* |
| in | `bReset` | `BOOL` |  | rising: resets trips whose cause has gone *(from FB_Dose)* |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: the pump off *(from FB_Dose)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: holds back a dose start *(from FB_Dose)* |
| in | `bStockLow` | `BOOL` |  | Stock low (status) *(from FB_Dose)* |
| in | `bHold` | `BOOL` |  | pause *(from FB_Dose)* |
| in | `bAbort` | `BOOL` |  | end, refuse a start *(from FB_Dose)* |
| in | `ipPump` | `I_Equipment` |  | optional: the dosing pump. The instance it drives (a motor, pump, valve or FB_Group) *(from FB_Dose)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bPumpRun` | `BOOL` |  | The dosing pump runs (status) *(from FB_Dose)* |
| out | `fRate` | `REAL` |  | % *(from FB_Dose)* |
| out | `bBusy` | `BOOL` |  | a dose is on *(from FB_Dose)* |
| out | `bDone` | `BOOL` |  | a Batch dose completed (one scan) *(from FB_Dose)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_DoseTimedData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto: once, then -1 (cleared) |
| `bCmdStart` | `BOOL` |  | start a dose (cleared by the block) |
| `bCmdStop` | `BOOL` |  | end the dose (cleared) |
| `bCmdHold` | `BOOL` |  | pause until the next start (cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (cleared) |
| `bCmdAbort` | `BOOL` |  | end the dose now, stop reason Abort (cleared) |

**Details `det`** (`ST_DoseDet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tDoseTime` | `TIME` |  | Time in this dose |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `nPulses` | `UDINT` |  | Stroke pulses given |

**Totals `tot`** (`ST_DoseTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nDosed` | `LINT` |  | millionths of a unit |
| `nDoses` | `UDINT` |  | Batch doses completed |

**Settings `set`** (`ST_DoseTimedSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEnabled` | `BOOL` | `TRUE` | FALSE: no dosing (a dose ends, stop reason Off) |
| `fPumpCapacity` | `REAL` |  | the dosing pump at 100 %, dose units per hour |
| `fMaxQuantity` | `LREAL` |  | per dose (0 = off) |
| `stMaxTime` | `ST_ProtectionSet` | `(eResponse := E_Response.Off, tDelay := T#1h, eReset := E_ResetMode.Manual)` | a protection's settings ([protections](../conventions.md#protections)) |
| `stStockLow` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#30s)` | a protection's settings ([protections](../conventions.md#protections)) |
| `tRetryWindow` | `TIME` | `T#1h` | Retry protections count their trips within this window |
| `eMode` | `E_Mode` | `E_Mode.Auto` | Off, Hand or Auto (kept) |
| `fHandRate` | `REAL` | `50.0` | Hand: the pump's speed, % |
| `bHandNeedsCarrier` | `BOOL` | `TRUE` | Hand: the carrier must be proven (Flow / Timed) |
| `tHandMax` | `TIME` | `T#5m` | Hand: the longest run (0 = no limit) |
| `tOnTime` | `TIME` | `T#10s` | On time |
| `tOffTime` | `TIME` | `T#5m` | Off time |
| `fRate` | `REAL` | `100.0` | % while on |
| `tCarrierProven` | `TIME` | `T#10s` | Waiting, not a fault |

**Status `sts`** (`ST_DoseTimedSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `ePhase` | `E_DosePhase` |  | The phase now (status) |
| `eStopReason` | `E_StopReason` |  | why the last dose ended |
| `bHeld` | `BOOL` |  | a dose is paused |
| `bQuantityHit` | `BOOL` |  | fMaxQuantity ended a dose (until a reset) |
| `fRate` | `REAL` |  | % |
| `fDelivered` | `LREAL` |  | this dose so far |
| `fLastDelivered` | `LREAL` |  | What the last dose delivered |
| `stMaxTime` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `stStockLow` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `eMode` | `E_Mode` |  | the mode in use |
| `bHandRun` | `BOOL` |  | a Hand run is on |
| `bCarrierOk` | `BOOL` |  | The carrier is proven (status) |

## Lists

- `E_DosePhase`: `Idle`, `Fast`, `Slow`, `Settle`, `Held`, `Done`, `Aborted`, `Dosing`, `Waiting` (default `Idle`)

## How it works

Timed dosing.

While `bRun` (or a `bStart` latch): the pump on at `set.fRate` % for `set.tOnTime`, off for `set.tOffTime`, over and over (on first); a pause stops the clock. It doses only while `bCarrierRunning` has been on for `set.tCarrierProven` (Waiting, not a fault). Dosed = `set.fPumpCapacity` x `fRate` % while the pump runs.

### Common to the FB_Dose family

`bRun` / `bStart` / `bStop` / `bReset` and the record's commands (`bCmdStart`, `bCmdStop`, `bCmdHold`, `bCmdReset`: once per write); `bInterlock` FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held); `bPermissive` FALSE holds back a dose start; `bHold` and `bCmdHold` (until the next start) pause; `bStop`, `bCmdStop`, `bAbort`, the record's `bCmdAbort` (stop reason Abort), `set.bEnabled` FALSE end a dose (a held `bRun` must drop before it doses again); `bStockLow` -> `set.stStockLow`; `set.stMaxTime` and `set.fMaxQuantity` cap a dose. `ipPump` (optional): the dosing pump, asked to run at `fRate` while dosing and held while `bInterlock` is FALSE; dosing counts only while it runs.

Modes (`set.eMode`, kept; the record's `nCmdMode` 0 Off / 1 Hand / 2 Auto, once, or a Command from [`FB_LocalControl`](FB_LocalControl.md), which drives a dose like a pump: IMPLEMENTS `I_Equipment`): Auto doses as above; Hand: a start (`bStart`, `bCmdStart`, the panel's start button) runs the pump at `set.fHandRate` % until a stop, `set.tHandMax` (0 = no limit), the interlock FALSE, an abort, `set.bEnabled` FALSE, a stop-trip or the mode left; with `set.bHandNeedsCarrier` the carrier must be proven (Flow / Timed; a Batch has none), else the pump waits (Held); a Hand run counts into the totals but is no dose (`nDoses`); Off: nothing doses. Hand never resumes after a power cut. An owner's Request(`bRun`) is a `bRun` (`bHold` = not asked); a variant's own pins and records work in Auto only. tot (millionths of a unit, and the doses) is kept at each dose end and every hour.

## Example

Chlorine on for 10 s every 5 min while the supply pump runs.

| Pin | Wire |
| --- | --- |
| `bRun` | `fbSystem.bIsAuto` |
| `bCarrierRunning` | `DI_SupplyPumpRunning` |
| `bStockLow` | `DI_ChlorineLow` |
| `refData` | `stDose` |
| `bPumpRun` | `DO_DosingPump` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Request(bRun, bHold, fSpeed, bUrgent) : E_UtError`: I_Equipment: an owner's request, a Command (FB_LocalControl) and the state, as a pump's
- method `Command(eCmd)`
- property `eActMode : E_Mode`
- property `bIsRunning : BOOL`
- property `bIsReady : BOOL`
- property `bIsAvailable : BOOL`
- property `bIsAuto : BOOL`
- property `bIsFaulted : BOOL`
- property `eActError : E_UtError`
- property `eActStopReason : E_StopReason`
- property `fActRunHours : REAL`: a dose counts no hours

## See also

[FB_DoseBatch](FB_DoseBatch.md), [FB_DoseFlow](FB_DoseFlow.md)

**Back to** [the index](../README.md).
