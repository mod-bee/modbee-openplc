# FB_Equipment — The engine every equipment block shares

The engine every equipment block shares (motor, pump, valve): written once.

Modes (the record's set.eMode, kept over a power cut; eModeAtPowerUp Off forces Off at power-up; the record's command nCmdEquipmentMode 0 Off / 1 Hand / 2 Auto / 3 OutOfService writes it once (SMS, SCADA), a Command(ModeOff ...) the same): Off nothing runs; switching to Off resets trips whose cause has gone (set.bOffResetsFaults). Hand bCmdStart / bCmdStop (the panel, or FB_LocalControl): a start while not permitted is dropped; a start waits out the restart delay; Hand never resumes after a power cut. No owner reaches it. set.tMaxHandRunTime (0 = none) ends a Hand run after that long (stop reason MaxRun). Jog (Command(Jog) every scan, from FB_MotorJog; Hand only, not while a Hand run is latched): runs while held, past trips, delays and the permissive; only Off and bInterlock stop it. Auto follows its owner's Request (called every scan); an owner that stops calling = owner lost, stop. A start waits for: permissive, the restart delay, the system's power-up hold, no part holding it. bCmdStop stops it until the owner's request drops. OutOfService (where the child allows it: motors, valves; not pumps): nothing runs, and no protection trips or warns (taken out for maintenance); it is not ready, not available. bInterlock FALSE stops it in every mode (not a fault). bPermissive FALSE blocks a start, never stops it. Trips (the block's own protections and its parts') stop it in every mode; the first one is eErrorId. After a reset clears a trip it runs again at once while its owner still asks (set.bRestartAfterReset FALSE: the owner's request must drop and come back first: for machines that must not restart unexpectedly). set.bWarnWhenNotAuto: a warning (NotAuto) while it is not in Auto and the plant is (ipSystem; unwired: always expected in Auto). tActIdleTime: the time since it last stopped (0 while running; power-on time only, from power-up); tActHandTimeLeft: a Hand run's time left under set.tMaxHandRunTime (0 = none counting). A child shows both in its det.

A child calls, every scan: bReset := Begin(refData, refData.set, refData.sts); (its own protections, with bReset) Finish(refData, refData.set, refData.sts, its trip / warning / error, its restart delay); and implements Drive (sets its outputs) and FeedbackOk (it is really running).

An abstract base: not placed on its own; the blocks that extend it are.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

## Read from ST (methods and properties)

- method `Request(bRun, bHoldOff, fSpeedSetpointPct, bOverflowUrgent) : E_UtError`
- method `Command(eCommand)`
- property `eActMode : E_Mode`: the mode it is in now
- property `bIsRunning : BOOL`: running now
- property `bIsReady : BOOL`: could start now if asked
- property `tActIdleTime : TIME`: time since the last stop (0 while running)
- property `tActHandTimeLeft : TIME`: a Hand run's time left under set.tMaxHandRunTime (0 = none counting)
- property `bIsAvailable : BOOL`: in Auto, not tripped, not interlocked
- property `bIsAuto : BOOL`: in Auto now
- property `bIsFaulted : BOOL`: a trip or setting fault is active
- property `eActError : E_UtError`: the error shown now
- property `eActStopReason : E_StopReason`: why it last stopped
- property `fActRunHours : REAL`: run hours (0 where not counted): rotation by hours

**Back to** [the index](../README.md).
