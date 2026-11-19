# FB_Dose — The engine every dosing block shares

The engine every dosing block shares (FB_DoseBatch, FB_DoseFlow, FB_DoseTimed): written once. bRun / bStart / bStop / bResetFaults and the record's commands (bCmdStart, bCmdStop, bCmdPause, bCmdResetFaults: once per write); bInterlock FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held); bPermissive FALSE holds back a dose start; bPause and bCmdPause (until the next start) pause; bStop, bCmdStop, bAbortWhileHeld, the record's bCmdAbort (stop reason Abort), set.bDosingEnabled FALSE end a dose (a held bRun must drop before it doses again); bStockLowSwitch -> set.stStockLowFault; set.stMaxDoseTimeFault and set.fMaxQuantityPerDose cap a dose. ipDosingPump (optional): Request(bRun := bPumpRunCommand, bPause := NOT bInterlock, fSpeed := fPumpSpeedPct); dosing counts only while it runs. Modes (set.eMode, kept; the record's nCmdDoseMode 0 Off / 1 Hand / 2 Auto, once, or a Command from FB_LocalControl, which drives a dose like a pump: IMPLEMENTS I_Equipment): Auto doses as above; Hand: a start (bStart, bCmdStart, the panel's start button) runs the pump at set.fHandSpeedPct % until a stop, set.tMaxHandRunTime (0 = no limit), the interlock FALSE, an abort, set.bDosingEnabled FALSE, a stop-trip or the mode left; with set.bHandNeedsCarrier the carrier must be proven (Flow / Timed; a Batch has none), else the pump waits (Held); a Hand run counts into the totals but is no dose (nDoseCount); Off: nothing doses. Hand never resumes after a power cut. An owner's Request(bRun) is a bRun (bPause = not asked); a variant's own pins and records work in Auto only. tot (millionths of a unit, and the doses) is kept at each dose end and every hour. A variant calls, every scan: bResetFaults := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts); (its settings, its dosing: bBusy, bPaused, bPumpGo, fPumpSpeedPct, fDosed, fDlv, eEnd, bDoneNow, its protections) Finish(refCmd, refSet, refSts, bOk, its trip / warning and codes, its phase, its time left);

An abstract base: not placed on its own; the blocks that extend it are.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | Batch: rising starts a dose; Flow / Timed: doses while TRUE |
| in | `bStart` | `BOOL` |  | rising: Batch starts / resumes; Flow / Timed: a run latched until a stop |
| in | `bStop` | `BOOL` |  | rising: ends the dose (a held bRun must drop first) |
| in | `bResetFaults` | `BOOL` |  | rising: resets trips whose cause has gone |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE: the pump off |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE: holds back a dose start |
| in | `bStockLowSwitch` | `BOOL` |  | the chemical stock is low (a level switch) |
| in | `bPause` | `BOOL` |  | pause |
| in | `bAbortWhileHeld` | `BOOL` |  | end, refuse a start |
| in | `ipDosingPump` | `I_Equipment` |  | optional: the dosing pump |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bPumpRunCommand` | `BOOL` |  | run the dosing pump |
| out | `fPumpSpeedPct` | `REAL` |  | % |
| out | `bBusy` | `BOOL` |  | a dose is on |
| out | `bDone` | `BOOL` |  | a Batch dose completed (one scan) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

## Read from ST (methods and properties)

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

**Back to** [the index](../README.md).
