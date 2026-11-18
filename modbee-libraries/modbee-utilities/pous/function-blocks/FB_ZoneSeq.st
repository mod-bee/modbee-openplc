(* FB_ZoneSeq — an irrigation / wash-down zone program: the zones (aZones, the project's FB_Zone instances in run
order, each with its own valve and settings) watered in turn, by time or by volume, in a safe valve and pump
order.

Pins: bRun (held: the program runs while held), bStart (rising edge: a latched run), bStop (rising edge: ends it,
wins), bPause (held: the pump stops and the valves close as at the end; the zone keeps its progress), bSkip
(rising edge: the watering zone is done now), bInterlock (FALSE ends the program and refuses a start),
bPermissive (FALSE holds back the start of the program or of the next zone), bLevelEnd (the source is at its stop
level: ends the program), bIrrigatorStop (the irrigator's fail-safe: ends the program and refuses a start),
aZones, ipPump (the pump, a group or a level control: optional), bPumpRunning (with no ipPump: the pump runs),
bPumpFault (the supply has tripped: no water counts and the wait for it runs), ipMeter (for zones by volume and
the flow check: optional), ipMasterValve (the master valve: optional), nRunZone (at the start: 0 = the program, n =
only zone n, index in aZones), nDoseReq (at the start: -1 = set.bDose, 0 no, 1 dose this run), tRunTime (at the start: each
zone's water time this run, 0 = its own), refData ->
bPumpDemand, bActive, nZone (the zone watering, 0 = none), bDoseEnable, bDoseHold, plus FB_Object's outputs.
Order, so the pump never deadheads or hammers:
  start   the zone's valve (and the master valve) opens; once they are proven, set.tPumpStartDelay later the pump
          is asked;
  change  the next zone's valve opens; once it is proven, set.tValveOverlap later the last one closes;
  end     the pump is released; the valves close once set.tValveCloseDelay has passed AND the pump has stopped; the
          master valve set.tMasterCloseDelay after the last zone valve.
Water counts only while the pump runs and has no fault, for the zone watering (not during a change: the overlap is
hydraulic). A zone's valve not proven within set.tValveProve: that zone is skipped (a warning). A zone whose rung is
not called is not in the program. A master valve that is refused, faulted or not open within set.tValveProve ends
the program (stop reason Fault, error MasterValve) until a reset or the next start.
Zone cycles: a zone with set.nCycles > 1 gives its water in cycles; when a cycle is given and no other zone is
ready, the pump stops and the valves close as at the end (phase Soaking) until a zone has soaked
(set.tSoakTime) and is ready again; the program ends when no zone has water left.
Zone cycle cap: a cycle whose only target is a volume ends at a time cap (see FB_Zone: set.tMaxTime, else the volume at
the zone's minimum flow, else set.tDefaultCap) with a warning RunCapped, so a dry meter cannot water for ever.
Flow check: the zone watering is told the meter's flow every scan (see FB_Zone); a zone that trips on it is out of
the program (a warning ZoneFlow).
Pump wait: with no pump running (or bPumpFault) while a zone should water, the time is counted (sts.tPumpWait);
at set.tMaxPumpWait (0 = wait for ever) the program ends (stop reason PumpFault, error PumpWait) or, with
set.bPumpWaitSkips, that zone is skipped (a warning).
One zone: nRunZone (at the start), the record's nCmdRunZone (a start, then -1) or a start while idle runs only that
zone (it need not be enabled), one pass.
Dosing hook: bDoseEnable = this run doses (nDoseReq / set.bDose, read at the start): wire it to FB_Dose.bRun.
bDoseHold = pause the injection now: no zone is watering with the pump running, or the zone may not be dosed
(FB_Zone set.bDose), or its cycle has set.tFlushTime or less to run (the pipe is flushed with clean water before
the valve closes): wire it to FB_Dose.bHold.
End reasons (sts.eStopReason): Done, Request (stop, held run dropped), Interlock, LevelEnd, IrrigatorStop,
PumpFault (the pump wait), Fault (the master valve).
Repeats: set.nRepeats (1..100) runs the whole program that many times (a one-zone run is one pass); sts.nPass.
Rain: bRainHold (wire FB_IrrDefer's bDefer to it; its bToStorage goes to the route) acts per set.eRainAction:
Pause holds the program (pump off, valves closed as at the end; the zones keep their progress) until it is gone;
Skip ends the zone watering and every zone not yet done (the program ends Done); Cancel ends the program (stop
reason Rain); Ignore does nothing. The active zone's pressure setpoint is fZoneSp: the zone's set.fPressure, else
set.fDefaultSp (wire it to FB_SpeedLoop's fSp pin, with its set.eSpSource Pin).
Power cut: the program's place (running, latched or held, the zone, the pass, a one-zone run, the dose choice) is
kept at each start, change of zone, new pass and end; each zone keeps its own progress. After a cut, set.eResume:
Resume goes on at the same zone (its valves start closed, its time and cycles kept); a latched run goes on at
once, a held one when its bRun is back within set.tResumeWindow, else it ends (PowerCut); Restart does the same
from the first zone and pass; None ends it (stop reason PowerCut). At most the water of the last hour in a zone is
repeated (the zone saves its watered time hourly).
Pause from the record: bCmdPause holds the program as bPause does, until bCmdResume (or the program ends);
set.tMaxPause > 0: a pause that long ends the program (stop reason PauseMax). set.tProgressSave > 0: the watering
zone's progress is kept that often (else on its events), so a power cut loses at most that much. Status:
sts.bPaused, sts.nRuns (programs started since power-up), sts.fDelivered (this program's water); det.tLeft (this
pass's time left over the timed zones not done), det.tPhaseTime. Each zone shows how it ended (FB_Zone
sts.eResult, sts.bSkipped). *)

FUNCTION_BLOCK FB_ZoneSeq EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL := FALSE;
    bStart : BOOL R_EDGE;
    bStop : BOOL R_EDGE;
    bPause : BOOL;
    bSkip : BOOL R_EDGE;
    bInterlock : BOOL := TRUE;
    bPermissive : BOOL := TRUE;
    bLevelEnd : BOOL;
    bIrrigatorStop : BOOL;
    ipPump : I_Equipment;
    bPumpRunning : BOOL;
    bPumpFault : BOOL;
    bRainHold : BOOL; (* rain (or wet soil): acts per set.eRainAction *)
    ipMeter : I_Meter;
    ipMasterValve : I_Equipment;
    nRunZone : INT;
    nDoseReq : INT := -1;
    tRunTime : TIME; (* at the start: each zone's water time this run (0 = its own set.tRunTime) *)
    refData : REFERENCE TO ST_ZoneSeqData;
  END_VAR
  VAR_IN_OUT
    aZones : ARRAY [*] OF FB_ZONE;
  END_VAR
  VAR_OUTPUT
    bPumpDemand : BOOL;
    bActive : BOOL;
    nZone : INT;
    bDoseEnable : BOOL;
    bDoseHold : BOOL;
    fZoneSp : REAL; (* the watering zone's pressure setpoint *)
  END_VAR
  VAR RETAIN
    stKept : ST_ZoneSeqSet;
    nKeptLayout : UINT;
    stProgress : ST_ZoneSeqProgress;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 6;
  END_VAR
  VAR
    ePhase : E_ZonePhase;
    nNext : INT; (* the zone opening during an overlap *)
    nClosing : INT; (* the zone whose valve waits to close at the end *)
    bLatched : BOOL;
    bRunPrev : BOOL;
    tPhaseAt : TIME;
    bPauseLatch : BOOL; (* the record's bCmdPause *)
    bHoldWas : BOOL;
    tHeldAt : TIME;
    tSavedAt : TIME;
    tProvedAt : TIME;
    bProved : BOOL;
    tLast : TIME;
    fLastTotal : LREAL;
    bProveWarn : BOOL;
    nRunOnly : INT; (* the one zone of this run (0 = the program) *)
    bDoseRun : BOOL;
    bCycleDone : BOOL; (* the watering zone's cycle has been ended (once per cycle) *)
    bFinalCycle : BOOL; (* ... and it was the last *)
    tPumpWait : TIME;
    bFlowWarn : BOOL;
    bWaitWarn : BOOL;
    bCapWarn : BOOL; (* a zone cycle ended on its time cap *)
    bFaultEnd : BOOL; (* the program ended on a fault: shown until a reset or the next start *)
    eFaultCode : E_UtError;
    bMasterFault : BOOL;
    bMasterLost : BOOL;
    tMasterLostAt : TIME;
    tLastValveAt : TIME;
    bValveSeen : BOOL;
    bMasterWant : BOOL;
    nPass : INT;
    bResumeWait : BOOL; (* a held run after a power cut: its bRun must come back *)
    tPowerUp : TIME;
  END_VAR
  VAR_TEMP
    nI : DINT;
    nLo : DINT;
    nHi : DINT;
    bPumpOn : BOOL;
    bEnd : BOOL;
    bNew : BOOL;
    tDt : TIME;
    fDv : LREAL;
    bEndNow : BOOL;
    bMasterOk : BOOL;
    bCounting : BOOL;
    bAnyValve : BOOL;
    bWantI : BOOL;
    nCmdZ : INT;
    nOld : INT;
    nRdy : INT;
    fRateNow : REAL;
    bRateGood : BOOL;
    bCmdRun : BOOL;
    bReset : BOOL;
    bHoldNow : BOOL;
    bRainSkip : BOOL;
    nAct : INT;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tPumpStartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tValveOverlap >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tValveCloseDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tValveProve >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMasterCloseDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tFlushTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMaxPumpWait >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nRepeats >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nRepeats <= 100) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.eRainAction = E_RainAction.Pause OR refData.set.eRainAction = E_RainAction.Skip
             OR refData.set.eRainAction = E_RainAction.Cancel OR refData.set.eRainAction = E_RainAction.Ignore) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (refData.set.tMaxTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tDefaultCap >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fDefaultSp >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fDefaultSp <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tResumeWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMaxPause >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tProgressSave >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.eResume = E_RunResume.Resume OR refData.set.eResume = E_RunResume.Restart
             OR refData.set.eResume = E_RunResume.None) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

(* the first zone that may water now (in the program, water left, not soaking; with a one-zone run, that zone),
   from zone nAfter + 1 (0 = from the start); 0 = none *)
METHOD PRIVATE NextZone : INT
  VAR_INPUT
    nAfter : INT;
  END_VAR
  VAR_IN_OUT
    aZ : ARRAY[*] OF FB_Zone;     // the block's in-out is not visible in a method: passed in
  END_VAR
  VAR
    nK : DINT;
  END_VAR
  NextZone := 0;
  FOR nK := MAX(LOWER_BOUND(aZ, 1), INT_TO_DINT(nAfter) + 1) TO UPPER_BOUND(aZ, 1) DO
    IF (nRunOnly = 0 AND aZ[nK].bIsReady) OR (nRunOnly = DINT_TO_INT(nK) AND aZ[nK].bIsWaterable) THEN
      NextZone := DINT_TO_INT(nK);
      RETURN;
    END_IF;
  END_FOR;
END_METHOD

(* a zone still has water to give (one that soaks counts) *)
METHOD PRIVATE AnyLeft : BOOL
  VAR_IN_OUT
    aZ : ARRAY[*] OF FB_Zone;
  END_VAR
  VAR
    nK : DINT;
  END_VAR
  AnyLeft := FALSE;
  FOR nK := LOWER_BOUND(aZ, 1) TO UPPER_BOUND(aZ, 1) DO
    IF aZ[nK].bIsPending AND (nRunOnly = DINT_TO_INT(nK) OR (nRunOnly = 0 AND aZ[nK].bIsEnabled)) THEN
      AnyLeft := TRUE;
      RETURN;
    END_IF;
  END_FOR;
END_METHOD

(* the pass is over: another one is due (repeats): every zone starts afresh *)
METHOD PRIVATE NextPass : BOOL
  VAR_IN_OUT
    aZ : ARRAY[*] OF FB_Zone;
  END_VAR
  VAR
    nK : DINT;
  END_VAR
  NextPass := FALSE;
  IF nRunOnly = 0 AND nPass < refData.set.nRepeats THEN
    nPass := nPass + 1;
    FOR nK := LOWER_BOUND(aZ, 1) TO UPPER_BOUND(aZ, 1) DO
      aZ[nK].SetDone(bDone := FALSE);
    END_FOR;
    NextPass := TRUE;
  END_IF;
END_METHOD

(* the zone being opened is left out (its valve did not open, or the rain skips it): the next one, else wait for a
   soak or a new pass, else the end *)
METHOD PRIVATE DropZone
  VAR_IN_OUT
    aZ : ARRAY[*] OF FB_Zone;
  END_VAR
  VAR
    nOldZ : INT;
  END_VAR
  nOldZ := nZone;
  aZ[nZone].SetDone(bDone := TRUE);
  nZone := NextZone(nAfter := 0, aZ := aZ);
  IF nZone > 0 THEN
    Go(ePh := E_ZonePhase.Opening);
  ELSE
    nClosing := nOldZ;
    IF AnyLeft(aZ := aZ) THEN
      Go(ePh := E_ZonePhase.Soaking);
    ELSIF NextPass(aZ := aZ) THEN
      Go(ePh := E_ZonePhase.Soaking);
    ELSE
      bActive := FALSE;
      refData.sts.eStopReason := E_StopReason.Done;
      Go(ePh := E_ZonePhase.Ending);
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE Go
  VAR_INPUT
    ePh : E_ZonePhase;
  END_VAR
  ePhase := ePh;
  tPhaseAt := tNow;
  bProved := FALSE;
  bCycleDone := FALSE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bPumpDemand := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aZones, 1);
nHi := UPPER_BOUND(aZones, 1);
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    stProgress.bActive := FALSE;
    nKeptLayout := cLayout;
  END_IF;
  tLast := tNow;
  bRunPrev := TRUE;               // a Run held at power-up is not a new program
  IF ipMeter <> NULL THEN fLastTotal := ipMeter.fActTotal; END_IF;
  (* a program that was on at the cut *)
  IF stProgress.bActive THEN
    IF refData.set.eResume = E_RunResume.None THEN
      stProgress.bActive := FALSE;
      refData.sts.eStopReason := E_StopReason.PowerCut;
    ELSE
      nRunOnly := stProgress.nRunOnly;
      IF nRunOnly < nLo OR nRunOnly > nHi THEN nRunOnly := 0; END_IF;
      bDoseRun := stProgress.bDoseRun;
      nPass := MAX(stProgress.nPass, 1);
      bLatched := stProgress.bLatched;
      FOR nI := nLo TO nHi DO
        aZones[nI].SetRunTime(tRunTime := stProgress.tRunTime);
      END_FOR;
      IF refData.set.eResume = E_RunResume.Restart THEN
        FOR nI := nLo TO nHi DO
          aZones[nI].SetDone(bDone := FALSE);
        END_FOR;
        nPass := 1;
        nZone := NextZone(nAfter := 0, aZ := aZones);
      ELSE
        nZone := stProgress.nZone;
        IF nZone < nLo OR nZone > nHi THEN
          nZone := 0;
        ELSIF NOT aZones[nZone].bIsPending THEN
          nZone := 0;
        END_IF;
        IF nZone = 0 THEN
          nZone := NextZone(nAfter := 0, aZ := aZones);
        END_IF;
      END_IF;
      IF nZone > 0 THEN
        bActive := TRUE;
        bResumeWait := NOT bLatched;
        tPowerUp := tNow;
        IF bResumeWait THEN
          Go(ePh := E_ZonePhase.Paused);      // valves closed until its bRun is back
          nClosing := 0;
        ELSE
          Go(ePh := E_ZonePhase.Opening);
        END_IF;
      ELSE
        stProgress.bActive := FALSE;          // nothing left to water
        refData.sts.eStopReason := E_StopReason.Done;
      END_IF;
    END_IF;
  END_IF;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
bReset := refData.bCmdReset OR SystemReset();
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;
IF bReset THEN
  bProveWarn := FALSE;
  bFlowWarn := FALSE;
  bWaitWarn := FALSE;
  bCapWarn := FALSE;
  bFaultEnd := FALSE;
  eFaultCode := E_UtError.None;
END_IF;

IF ipPump <> NULL THEN
  bPumpOn := ipPump.bIsRunning;
ELSE
  bPumpOn := bPumpRunning;
END_IF;
bCounting := bPumpOn AND NOT bPumpFault;
IF refData.bCmdPause AND bActive THEN bPauseLatch := TRUE; END_IF;
IF refData.bCmdResume OR NOT bActive THEN bPauseLatch := FALSE; END_IF;
refData.bCmdPause := FALSE;
refData.bCmdResume := FALSE;
bHoldNow := bPause OR bPauseLatch OR (bRainHold AND refData.set.eRainAction = E_RainAction.Pause) OR bResumeWait;
IF bHoldNow AND NOT bHoldWas THEN tHeldAt := tNow; END_IF;
bHoldWas := bHoldNow;
bRainSkip := bActive AND bRainHold AND refData.set.eRainAction = E_RainAction.Skip;
IF bResumeWait AND bRun THEN
  bResumeWait := FALSE;
END_IF;
bMasterOk := TRUE;
IF ipMasterValve <> NULL THEN
  bMasterOk := ipMasterValve.bIsRunning;      // a valve's "running" is open
END_IF;
fRateNow := 0.0;
bRateGood := FALSE;
IF ipMeter <> NULL THEN
  fRateNow := ipMeter.fActRate;
  bRateGood := ipMeter.bIsGood AND ABS(fRateNow) <= REAL#3.4E38;
END_IF;

(* a one-zone run asked for by the record: a start (refused while a program runs) *)
nCmdZ := 0;
bCmdRun := FALSE;
IF refData.nCmdRunZone >= nLo AND refData.nCmdRunZone <= nHi THEN
  nCmdZ := refData.nCmdRunZone;
  bCmdRun := NOT bActive;
END_IF;
refData.nCmdRunZone := -1;

(* a new program *)
bNew := ((bRun AND NOT bRunPrev) OR bStart OR refData.bCmdStart OR bCmdRun) AND NOT bActive;
bRunPrev := bRun;
refData.bCmdStart := FALSE;
IF bNew AND bInterlock AND NOT bIrrigatorStop THEN
  nRunOnly := 0;
  IF nCmdZ > 0 THEN
    nRunOnly := nCmdZ;
  ELSIF nRunZone >= nLo AND nRunZone <= nHi THEN
    nRunOnly := nRunZone;
  END_IF;
  FOR nI := nLo TO nHi DO
    aZones[nI].SetDone(bDone := FALSE);
    aZones[nI].SetRunTime(tRunTime := tRunTime);
  END_FOR;
  stProgress.tRunTime := MAX(tRunTime, T#0s);
  nZone := NextZone(nAfter := 0, aZ := aZones);
  IF nZone > 0 THEN
    bActive := TRUE;
    bLatched := bStart OR bCmdRun OR NOT bRun;
    refData.sts.eStopReason := E_StopReason.None;
    refData.sts.nRuns := refData.sts.nRuns + 1;
    refData.sts.fDelivered := 0.0;
    tPumpWait := T#0s;
    nPass := 1;
    bResumeWait := FALSE;
    bProveWarn := FALSE;
    bFlowWarn := FALSE;
    bWaitWarn := FALSE;
    bCapWarn := FALSE;
    bFaultEnd := FALSE;
    eFaultCode := E_UtError.None;
    IF nDoseReq = 0 THEN
      bDoseRun := FALSE;
    ELSIF nDoseReq = 1 THEN
      bDoseRun := TRUE;
    ELSE
      bDoseRun := refData.set.bDose;
    END_IF;
    Go(ePh := E_ZonePhase.Opening);
  END_IF;
END_IF;

(* the program ends: stop, interlock, the irrigator, the level, the master valve, the pump wait, the held run dropped *)
bEnd := FALSE;
IF bActive THEN
  IF bStop OR refData.bCmdStop THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Request;
  ELSIF NOT bInterlock THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Interlock;
  ELSIF bIrrigatorStop THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.IrrigatorStop;
  ELSIF bLevelEnd THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.LevelEnd;
  ELSIF bRainHold AND refData.set.eRainAction = E_RainAction.Cancel THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Rain;
  ELSIF bHoldNow AND NOT bResumeWait AND refData.set.tMaxPause > T#0s AND tNow - tHeldAt >= refData.set.tMaxPause THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.PauseMax;
  ELSIF bResumeWait AND NOT bRun AND tNow - tPowerUp >= refData.set.tResumeWindow THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.PowerCut;
  ELSIF bMasterFault THEN
    bEnd := TRUE;
    bFaultEnd := TRUE;
    eFaultCode := E_UtError.MasterValve;
    refData.sts.eStopReason := E_StopReason.Fault;
  ELSIF refData.set.tMaxPumpWait > T#0s AND tPumpWait >= refData.set.tMaxPumpWait AND NOT refData.set.bPumpWaitSkips THEN
    bEnd := TRUE;
    bFaultEnd := TRUE;
    eFaultCode := E_UtError.PumpWait;
    refData.sts.eStopReason := E_StopReason.PumpFault;
  ELSIF NOT bLatched AND NOT bRun AND NOT bResumeWait THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Request;
  END_IF;
END_IF;
refData.bCmdStop := FALSE;
IF bEnd AND nZone >= nLo AND nZone <= nHi AND nZone > 0 THEN
  aZones[nZone].SetResult(eResult := refData.sts.eStopReason, bSkipped := FALSE);   // the zone it was on
END_IF;
IF bEnd AND ePhase <> E_ZonePhase.Ending THEN
  bActive := FALSE;
  nClosing := nZone;
  Go(ePh := E_ZonePhase.Ending);
END_IF;

(* water counted while the pump runs, and the time with no pump *)
tDt := tNow - tLast;
tLast := tNow;
fDv := 0.0;
IF ipMeter <> NULL THEN
  fDv := ipMeter.fActTotal - fLastTotal;
  fLastTotal := ipMeter.fActTotal;
END_IF;
IF ePhase = E_ZonePhase.Watering AND NOT bCounting AND NOT bHoldNow THEN
  tPumpWait := tPumpWait + tDt;
ELSIF bCounting THEN
  tPumpWait := T#0s;
END_IF;

(* the rain skips every zone that is not watering *)
IF bRainSkip THEN
  FOR nI := nLo TO nHi DO
    IF nI <> nZone AND aZones[nI].bIsPending AND (nRunOnly = DINT_TO_INT(nI) OR (nRunOnly = 0 AND aZones[nI].bIsEnabled)) THEN
      aZones[nI].SetDone(bDone := TRUE);
    END_IF;
  END_FOR;
END_IF;

CASE ePhase OF
  E_ZonePhase.Opening:
    IF bHoldNow THEN
      nClosing := nZone;
      Go(ePh := E_ZonePhase.Paused);
    ELSIF bRainSkip THEN
      aZones[nZone].SetResult(eResult := E_StopReason.Rain, bSkipped := TRUE);
      DropZone(aZ := aZones);                     // the rain skips it
    ELSIF aZones[nZone].bOpen AND bMasterOk THEN
      IF NOT bProved THEN bProved := TRUE; tProvedAt := tNow; END_IF;
      IF tNow - tProvedAt >= refData.set.tPumpStartDelay THEN
        Go(ePh := E_ZonePhase.Watering);
      END_IF;
    ELSIF tNow - tPhaseAt >= refData.set.tValveProve AND NOT aZones[nZone].bOpen THEN
      bProveWarn := TRUE;         // its valve did not open: skip it
      aZones[nZone].SetResult(eResult := E_StopReason.Fault, bSkipped := TRUE);
      DropZone(aZ := aZones);
    END_IF;

  E_ZonePhase.Watering, E_ZonePhase.Changing:
    IF bCounting AND ePhase = E_ZonePhase.Watering THEN
      aZones[nZone].AddWatered(tWatered := tDt, fWatered := fDv);   // not during a change: its target is reached
      refData.sts.fDelivered := refData.sts.fDelivered + fDv;
      IF refData.set.tProgressSave > T#0s AND tNow - tSavedAt >= refData.set.tProgressSave THEN
        aZones[nZone].SaveProgress();
        tSavedAt := tNow;
      END_IF;
      aZones[nZone].Flow(fRate := fRateNow, bGood := bRateGood);
    END_IF;
    IF bHoldNow THEN
      nClosing := nZone;
      Go(ePh := E_ZonePhase.Paused);
    ELSE
      IF ePhase = E_ZonePhase.Watering AND NOT bCycleDone THEN
        (* the zone's cycle ends: its water is given, or it is skipped, tripped on its flow, or the pump never came *)
        bEndNow := FALSE;
        IF bSkip OR refData.bCmdSkip OR bRainSkip THEN
          bEndNow := TRUE;
          IF bRainSkip THEN
            aZones[nZone].SetResult(eResult := E_StopReason.Rain, bSkipped := TRUE);
          ELSE
            aZones[nZone].SetResult(eResult := E_StopReason.Request, bSkipped := TRUE);
          END_IF;
        ELSIF aZones[nZone].bIsFlowTrip THEN
          bEndNow := TRUE;
          bFlowWarn := TRUE;
          aZones[nZone].SetResult(eResult := E_StopReason.Fault, bSkipped := FALSE);
        ELSIF refData.set.tMaxPumpWait > T#0s AND tPumpWait >= refData.set.tMaxPumpWait AND refData.set.bPumpWaitSkips THEN
          bEndNow := TRUE;
          bWaitWarn := TRUE;
          tPumpWait := T#0s;
          aZones[nZone].SetResult(eResult := E_StopReason.PumpFault, bSkipped := TRUE);
        END_IF;
        IF bEndNow THEN
          bFinalCycle := TRUE;
          bCycleDone := TRUE;
          aZones[nZone].SetDone(bDone := TRUE);
        ELSIF aZones[nZone].Reached(bByVolume := ipMeter <> NULL, tMaxTime := refData.set.tMaxTime,
                                    tDefaultCap := refData.set.tDefaultCap) THEN
          bFinalCycle := aZones[nZone].EndCycle();
          IF aZones[nZone].bIsCapped THEN
            bCapWarn := TRUE;
          END_IF;
          bCycleDone := TRUE;
          IF bFinalCycle THEN
            aZones[nZone].SetDone(bDone := TRUE);
            aZones[nZone].SetResult(eResult := E_StopReason.Done, bSkipped := FALSE);
          END_IF;
        END_IF;
      END_IF;
      IF ePhase = E_ZonePhase.Watering AND bCycleDone THEN
        nNext := NextZone(nAfter := 0, aZ := aZones);
        IF nNext = nZone THEN
          bCycleDone := FALSE;                   // its next cycle at once (no soak): the valve stays open
        ELSIF nNext = 0 THEN
          nClosing := nZone;
          IF AnyLeft(aZ := aZones) THEN
            Go(ePh := E_ZonePhase.Soaking);       // the others soak: pump off, valves closed meanwhile
          ELSIF NextPass(aZ := aZones) THEN
            Go(ePh := E_ZonePhase.Soaking);       // the next pass: the valves close, then the first zone
          ELSE
            bActive := FALSE;
            refData.sts.eStopReason := E_StopReason.Done;
            Go(ePh := E_ZonePhase.Ending);
          END_IF;
        ELSIF bPermissive THEN
          Go(ePh := E_ZonePhase.Changing);     // open the next one; this one keeps watering meanwhile
          bCycleDone := TRUE;
        END_IF;
      ELSIF ePhase = E_ZonePhase.Changing THEN
        IF bRainSkip THEN
          aZones[nNext].SetDone(bDone := TRUE);
          nNext := 0;
          Go(ePh := E_ZonePhase.Watering);
          bCycleDone := TRUE;
        ELSIF aZones[nNext].bOpen THEN
          IF NOT bProved THEN bProved := TRUE; tProvedAt := tNow; END_IF;
          IF tNow - tProvedAt >= refData.set.tValveOverlap THEN
            nZone := nNext;
            nNext := 0;
            Go(ePh := E_ZonePhase.Watering);
          END_IF;
        ELSIF tNow - tPhaseAt >= refData.set.tValveProve THEN
          bProveWarn := TRUE;     // the next one did not open: skip it, carry on with this one
          aZones[nNext].SetDone(bDone := TRUE);
          nNext := 0;
          Go(ePh := E_ZonePhase.Watering);
          bCycleDone := TRUE;
        END_IF;
      END_IF;
    END_IF;
    refData.bCmdSkip := FALSE;

  E_ZonePhase.Paused:
    IF NOT bHoldNow AND tNow - tPhaseAt >= refData.set.tValveCloseDelay AND NOT bPumpOn THEN
      Go(ePh := E_ZonePhase.Opening);     // resume: the same zone, its progress kept
    END_IF;

  E_ZonePhase.Soaking:
    (* nothing is ready: the valves close as at the end, then the program waits for a zone to be ready again *)
    IF tNow - tPhaseAt >= refData.set.tValveCloseDelay AND NOT bPumpOn THEN
      nClosing := 0;
      nRdy := NextZone(nAfter := 0, aZ := aZones);
      IF nRdy > 0 THEN
        nZone := nRdy;
        Go(ePh := E_ZonePhase.Opening);
      ELSIF NOT AnyLeft(aZ := aZones) THEN
        IF NOT NextPass(aZ := aZones) THEN
          bActive := FALSE;
          nZone := 0;
          refData.sts.eStopReason := E_StopReason.Done;
          Go(ePh := E_ZonePhase.Idle);
        END_IF;
      END_IF;
    END_IF;

  E_ZonePhase.Ending:
    IF tNow - tPhaseAt >= refData.set.tValveCloseDelay AND NOT bPumpOn THEN
      nClosing := 0;
      nZone := 0;
      Go(ePh := E_ZonePhase.Idle);
    END_IF;
ELSE
  ;
END_CASE;

(* the valves: the zone opening or watering; the next during an overlap; the last kept open at the end until
   the pump has stopped *)
bAnyValve := FALSE;
FOR nI := nLo TO nHi DO
  bWantI := (ePhase = E_ZonePhase.Opening AND nI = nZone)
            OR ((ePhase = E_ZonePhase.Watering OR ePhase = E_ZonePhase.Changing) AND nI = nZone)
            OR (ePhase = E_ZonePhase.Changing AND nI = nNext)
            OR ((ePhase = E_ZonePhase.Ending OR ePhase = E_ZonePhase.Paused OR ePhase = E_ZonePhase.Soaking)
                AND nI = nClosing AND (bPumpOn OR tNow - tPhaseAt < refData.set.tValveCloseDelay));
  aZones[nI].Open(bOpen := bWantI);
  bAnyValve := bAnyValve OR bWantI;
END_FOR;

(* the master valve: with the first zone valve, closed set.tMasterCloseDelay after the last *)
IF bAnyValve THEN
  tLastValveAt := tNow;
  bValveSeen := TRUE;
END_IF;
bMasterWant := bAnyValve OR (bValveSeen AND tNow - tLastValveAt < refData.set.tMasterCloseDelay);
IF NOT bMasterWant THEN
  bValveSeen := FALSE;
END_IF;
IF ipMasterValve <> NULL THEN
  ipMasterValve.Request(bRun := bMasterWant, bHold := FALSE);
  IF bMasterWant AND (NOT bMasterOk OR ipMasterValve.bIsFaulted) THEN
    IF NOT bMasterLost THEN
      bMasterLost := TRUE;
      tMasterLostAt := tNow;
    END_IF;
    IF ipMasterValve.bIsFaulted OR tNow - tMasterLostAt >= refData.set.tValveProve THEN
      bMasterFault := TRUE;
    END_IF;
  ELSE
    bMasterLost := FALSE;
  END_IF;
END_IF;
IF bReset OR (NOT bActive AND NOT bMasterWant) THEN
  bMasterFault := FALSE;
  bMasterLost := FALSE;
END_IF;

(* the pump *)
bPumpDemand := ePhase = E_ZonePhase.Watering OR ePhase = E_ZonePhase.Changing;
IF ipPump <> NULL THEN
  ipPump.Request(bRun := bPumpDemand, bHold := FALSE);
END_IF;

(* the dosing hook *)
bDoseEnable := bActive AND bDoseRun;
bDoseHold := TRUE;
IF ePhase = E_ZonePhase.Watering AND bCounting AND nZone > 0 THEN
  IF aZones[nZone].bDoseAllowed AND (aZones[nZone].bUntilStop OR aZones[nZone].tActTimeLeft > refData.set.tFlushTime) THEN
    bDoseHold := FALSE;
  END_IF;
END_IF;

(* the active zone's pressure *)
nAct := 0;
IF ePhase = E_ZonePhase.Opening OR ePhase = E_ZonePhase.Watering THEN
  nAct := nZone;
ELSIF ePhase = E_ZonePhase.Changing THEN
  nAct := nNext;
END_IF;
fZoneSp := refData.set.fDefaultSp;
IF nAct >= nLo AND nAct <= nHi THEN
  IF aZones[nAct].fActPressure > 0.0 THEN
    fZoneSp := aZones[nAct].fActPressure;
  END_IF;
END_IF;

(* what a power cut keeps: written at a start, a change of zone, a new pass and the end *)
IF bActive <> stProgress.bActive OR bLatched <> stProgress.bLatched OR nPass <> stProgress.nPass
   OR nRunOnly <> stProgress.nRunOnly OR bDoseRun <> stProgress.bDoseRun
   OR (bActive AND nZone > 0 AND nZone <> stProgress.nZone) THEN
  stProgress.bActive := bActive;
  stProgress.bLatched := bLatched;
  stProgress.nPass := nPass;
  stProgress.nRunOnly := nRunOnly;
  stProgress.bDoseRun := bDoseRun;
  IF nZone > 0 THEN
    stProgress.nZone := nZone;
  END_IF;
END_IF;

(* status *)
bError := bFaultEnd;
bWarning := bProveWarn OR bFlowWarn OR bWaitWarn OR bCapWarn OR refData.sts.bRefused;
IF bFaultEnd THEN
  eErrorId := eFaultCode;
ELSIF bProveWarn THEN
  eErrorId := E_UtError.PositionLost;
ELSIF bFlowWarn THEN
  eErrorId := E_UtError.ZoneFlow;
ELSIF bWaitWarn THEN
  eErrorId := E_UtError.PumpWait;
ELSIF bCapWarn THEN
  eErrorId := E_UtError.RunCapped;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
CASE ePhase OF
  E_ZonePhase.Idle: eState := E_State.Idle;
  E_ZonePhase.Opening: eState := E_State.Starting;
  E_ZonePhase.Paused, E_ZonePhase.Soaking: eState := E_State.Held;
  E_ZonePhase.Ending: eState := E_State.Stopping;
ELSE
  eState := E_State.Running;
END_CASE;
IF bFaultEnd AND ePhase = E_ZonePhase.Idle THEN eState := E_State.Fault; END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.ePhase := ePhase;
refData.sts.nZone := nZone;
refData.sts.bActive := bActive;
refData.sts.nRunZone := nRunOnly;
refData.sts.nPass := nPass;
refData.sts.bRainHold := bRainHold;
refData.sts.bMasterWanted := bMasterWant;
refData.sts.bDoseOn := bDoseEnable;
refData.sts.tPumpWait := tPumpWait;
refData.sts.bPaused := bHoldNow AND bActive;
refData.det.tPhaseTime := tNow - tPhaseAt;
refData.det.tLeft := T#0s;
IF bActive THEN
  FOR nI := nLo TO nHi DO
    IF nRunOnly = 0 OR nRunOnly = DINT_TO_INT(nI) THEN
      refData.det.tLeft := refData.det.tLeft + aZones[nI].tActRemaining;
    END_IF;
  END_FOR;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK