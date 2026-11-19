(* FB_ZoneSeq — an irrigation / wash-down zone program: the zones (aZones, the project's FB_Zone instances in run
order, each with its own valve and settings) watered in turn, by time or by volume, in a safe valve and pump
order.

Pins: bRun (held: the program runs while held), bStart (rising edge: a latched run), bStop (rising edge: ends it,
wins), bPause (held: the pump stops and the valves close as at the end; the zone keeps its progress), bSkipZone
(rising edge: the watering zone is done now), bInterlock (FALSE ends the program and refuses a start),
bPermissive (FALSE holds back the start of the program or of the next zone), bSourceAtStopLevel (the source is at its stop
level: ends the program), bIrrigatorTripped (the irrigator's fail-safe: ends the program and refuses a start),
aZones, ipPump (the pump, a group or a level control: optional), bPumpRunning (with no ipPump: the pump runs),
bPumpFaulted (the supply has tripped: no water counts and the wait for it runs), ipMeter (for zones by volume and
the flow check: optional), ipMasterValve (the master valve: optional), nRunOnlyZone (at the start: 0 = the program, n =
only zone n, index in aZones), nDoseRequest (at the start: -1 = set.bDoseByDefault, 0 no, 1 dose this run), tRunTime (at the start: each
zone's water time this run, 0 = its own), refData ->
bPumpRunCommand, bBusy, nZoneWatering (the zone watering, 0 = none), bDosingAllowed, bDosingPaused, plus FB_Object's outputs.
Order, so the pump never deadheads or hammers:
  start   the zone's valve (and the master valve) opens; once they are proven, set.tPumpStartDelay later the pump
          is asked;
  change  the next zone's valve opens; once it is proven, set.tValveOverlap later the last one closes;
  end     the pump is released; the valves close once set.tValveCloseDelay has passed AND the pump has stopped; the
          master valve set.tMasterCloseDelay after the last zone valve.
Water counts only while the pump runs and has no fault, for the zone watering (not during a change: the overlap is
hydraulic). A zone's valve not proven within set.tValveProveTimeout: that zone is skipped (a warning). A zone whose rung is
not called is not in the program. A master valve that is refused, faulted or not open within set.tValveProveTimeout ends
the program (stop reason Fault, error MasterValve) until a reset or the next start.
Zone cycles: a zone with set.nCycles > 1 gives its water in cycles; when a cycle is given and no other zone is
ready, the pump stops and the valves close as at the end (phase Soaking) until a zone has soaked
(set.tSoakTime) and is ready again; the program ends when no zone has water left.
Zone cycle cap: a cycle whose only target is a volume ends at a time cap (see FB_Zone: set.tMaxVolumeCycleTime, else the volume at
the zone's minimum flow, else set.tDefaultTimeCap) with a warning RunCapped, so a dry meter cannot water for ever.
Flow check: the zone watering is told the meter's flow every scan (see FB_Zone); a zone that trips on it is out of
the program (a warning ZoneFlow).
Pump wait: with no pump running (or bPumpFaulted) while a zone should water, the time is counted (sts.tWaitingForPump);
at set.tPumpWaitTimeout (0 = wait for ever) the program ends (stop reason PumpFault, error PumpWait) or, with
set.bPumpWaitSkipsZone, that zone is skipped (a warning).
One zone: nRunOnlyZone (at the start), the record's nCmdRunOnlyZone (a start, then -1) or a start while idle runs only that
zone (it need not be enabled), one pass.
Dosing hook: bDosingAllowed = this run doses (nDoseRequest / set.bDoseByDefault, read at the start): wire it to FB_Dose.bRun.
bDosingPaused = pause the injection now: no zone is watering with the pump running, or the zone may not be dosed
(FB_Zone set.bDoseByDefault), or its cycle has set.tFlushTime or less to run (the pipe is flushed with clean water before
the valve closes): wire it to FB_Dose.bPause.
End reasons (sts.eStopReason): Done, Request (stop, held run dropped), Interlock, LevelEnd, IrrigatorStop,
PumpFault (the pump wait), Fault (the master valve).
Repeats: set.nPasses (1..100) runs the whole program that many times (a one-zone run is one pass); sts.nPassRunning.
Rain: bDeferIrrigation (wire FB_IrrDefer's bDeferIrrigation to it; its bSendToStorage goes to the route) acts per set.eActionOnDefer:
Pause holds the program (pump off, valves closed as at the end; the zones keep their progress) until it is gone;
Skip ends the zone watering and every zone not yet done (the program ends Done); Cancel ends the program (stop
reason Rain); Ignore does nothing. The active zone's pressure setpoint is fZonePressureSetpoint: the zone's set.fPressureSetpoint, else
set.fDefaultPressureSetpoint (wire it to FB_SpeedLoop's fSetpoint pin, with its set.eSetpointFrom Pin).
Power cut: the program's place (running, latched or held, the zone, the pass, a one-zone run, the dose choice) is
kept at each start, change of zone, new pass and end; each zone keeps its own progress. After a cut, set.eAfterPowerCut:
Resume goes on at the same zone (its valves start closed, its time and cycles kept); a latched run goes on at
once, a held one when its bRun is back within set.tHeldRunTimeout, else it ends (PowerCut); Restart does the same
from the first zone and pass; None ends it (stop reason PowerCut). At most the water of the last hour in a zone is
repeated (the zone saves its watered time hourly).
Pause from the record: bCmdPause holds the program as bPause does, until bCmdResume (or the program ends);
set.tMaxPauseBeforeEnd > 0: a pause that long ends the program (stop reason PauseMax). set.tProgressSaveInterval > 0: the watering
zone's progress is kept that often (else on its events), so a power cut loses at most that much. Status:
sts.bPaused, sts.nRunCount (programs started since power-up), sts.fDeliveredThisRun (this program's water); det.tPassTimeLeft (this
pass's time left over the timed zones not done), det.tInPhaseFor. Each zone shows how it ended (FB_Zone
sts.eLastOutcome, sts.bSkipped). *)

FUNCTION_BLOCK FB_ZoneSeq EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL := FALSE; (* held: the program runs while held *)
    bStart : BOOL R_EDGE; (* rising edge: a latched program run *)
    bStop : BOOL R_EDGE; (* rising edge: ends it; wins over a start *)
    bPause : BOOL; (* held: the pump stops and the valves close as at the end; the zone keeps its progress *)
    bSkipZone : BOOL R_EDGE; (* rising edge: the watering zone is done now *)
    bInterlock : BOOL := TRUE; (* FALSE ends the program and refuses a start *)
    bPermissive : BOOL := TRUE; (* FALSE holds back the start of the program or of the next zone *)
    bSourceAtStopLevel : BOOL; (* the source is at its stop level: ends the program *)
    bIrrigatorTripped : BOOL; (* the irrigator's fail-safe: ends the program and refuses a start *)
    ipPump : I_Equipment; (* the pump, a group or a level control (optional) *)
    bPumpRunning : BOOL; (* with no ipPump: the pump runs *)
    bPumpFaulted : BOOL; (* the supply has tripped: no water counts and the wait for it runs *)
    bDeferIrrigation : BOOL; (* rain (or wet soil): acts per set.eActionOnDefer *)
    ipMeter : I_Meter; (* the flow meter for zones by volume and the flow check (optional) *)
    ipMasterValve : I_Equipment; (* the master valve (optional) *)
    nRunOnlyZone : INT; (* at the start: 0 = the program, n = only zone n (index in aZones) *)
    nDoseRequest : INT := -1; (* at the start: -1 = bDoseByDefault, 0 = no, 1 = dose this run *)
    tRunTime : TIME; (* at the start: each zone's water time this run (0 = its own set.tWaterTime) *)
    refData : REFERENCE TO ST_ZoneSeqData; (* the block's record *)
  END_VAR
  VAR_IN_OUT
    aZones : ARRAY [*] OF FB_ZONE; (* the FB_Zone instances, in run order (ARRAY[1..n] OF FB_Zone) *)
  END_VAR
  VAR_OUTPUT
    bPumpRunCommand : BOOL; (* ask for the pump (with no ipPump) *)
    bBusy : BOOL; (* the program is on *)
    nZoneWatering : INT; (* the zone watering (0 = none) *)
    bDosingAllowed : BOOL; (* dosing may run now *)
    bDosingPaused : BOOL; (* pause the injection now: no zone watering with the pump running, or the zone may not be dosed *)
    fZonePressureSetpoint : REAL; (* the watering zone's pressure setpoint *)
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
  ELSIF NOT (refData.set.tValveProveTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMasterCloseDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tFlushTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tPumpWaitTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nPasses >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nPasses <= 100) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.eActionOnDefer = E_RainAction.Pause OR refData.set.eActionOnDefer = E_RainAction.Skip
             OR refData.set.eActionOnDefer = E_RainAction.Cancel OR refData.set.eActionOnDefer = E_RainAction.Ignore) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (refData.set.tMaxVolumeCycleTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tDefaultTimeCap >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fDefaultPressureSetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fDefaultPressureSetpoint <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tHeldRunTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMaxPauseBeforeEnd >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tProgressSaveInterval >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.eAfterPowerCut = E_RunResume.Resume OR refData.set.eAfterPowerCut = E_RunResume.Restart
             OR refData.set.eAfterPowerCut = E_RunResume.None) THEN
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
    IF aZ[nK].bIsPending AND (nRunOnly = DINT_TO_INT(nK) OR (nRunOnly = 0 AND aZ[nK].bIsInProgram)) THEN
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
  IF nRunOnly = 0 AND nPass < refData.set.nPasses THEN
    nPass := nPass + 1;
    FOR nK := LOWER_BOUND(aZ, 1) TO UPPER_BOUND(aZ, 1) DO
      aZ[nK].SetDone(bZoneDone := FALSE);
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
  nOldZ := nZoneWatering;
  aZ[nZoneWatering].SetDone(bZoneDone := TRUE);
  nZoneWatering := NextZone(nAfter := 0, aZ := aZ);
  IF nZoneWatering > 0 THEN
    Go(ePh := E_ZonePhase.Opening);
  ELSE
    nClosing := nOldZ;
    IF AnyLeft(aZ := aZ) THEN
      Go(ePh := E_ZonePhase.Soaking);
    ELSIF NextPass(aZ := aZ) THEN
      Go(ePh := E_ZonePhase.Soaking);
    ELSE
      bBusy := FALSE;
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
  bPumpRunCommand := FALSE;
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
    stProgress.bBusy := FALSE;
    nKeptLayout := cLayout;
  END_IF;
  tLast := tNow;
  bRunPrev := TRUE;               // a Run held at power-up is not a new program
  IF ipMeter <> NULL THEN fLastTotal := ipMeter.fActTotal; END_IF;
  (* a program that was on at the cut *)
  IF stProgress.bBusy THEN
    IF refData.set.eAfterPowerCut = E_RunResume.None THEN
      stProgress.bBusy := FALSE;
      refData.sts.eStopReason := E_StopReason.PowerCut;
    ELSE
      nRunOnly := stProgress.nRunOnlyZone;
      IF nRunOnly < nLo OR nRunOnly > nHi THEN nRunOnly := 0; END_IF;
      bDoseRun := stProgress.bDosingThisRun;
      nPass := MAX(stProgress.nPassRunning, 1);
      bLatched := stProgress.bLatched;
      FOR nI := nLo TO nHi DO
        aZones[nI].SetRunTime(tRunTime := stProgress.tRunTime);
      END_FOR;
      IF refData.set.eAfterPowerCut = E_RunResume.Restart THEN
        FOR nI := nLo TO nHi DO
          aZones[nI].SetDone(bZoneDone := FALSE);
        END_FOR;
        nPass := 1;
        nZoneWatering := NextZone(nAfter := 0, aZ := aZones);
      ELSE
        nZoneWatering := stProgress.nZoneWatering;
        IF nZoneWatering < nLo OR nZoneWatering > nHi THEN
          nZoneWatering := 0;
        ELSIF NOT aZones[nZoneWatering].bIsPending THEN
          nZoneWatering := 0;
        END_IF;
        IF nZoneWatering = 0 THEN
          nZoneWatering := NextZone(nAfter := 0, aZ := aZones);
        END_IF;
      END_IF;
      IF nZoneWatering > 0 THEN
        bBusy := TRUE;
        bResumeWait := NOT bLatched;
        tPowerUp := tNow;
        IF bResumeWait THEN
          Go(ePh := E_ZonePhase.Paused);      // valves closed until its bRun is back
          nClosing := 0;
        ELSE
          Go(ePh := E_ZonePhase.Opening);
        END_IF;
      ELSE
        stProgress.bBusy := FALSE;          // nothing left to water
        refData.sts.eStopReason := E_StopReason.Done;
      END_IF;
    END_IF;
  END_IF;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
bReset := refData.bCmdResetFaults OR SystemReset();
IF refData.bCmdResetFaults THEN
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
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
bCounting := bPumpOn AND NOT bPumpFaulted;
IF refData.bCmdPause AND bBusy THEN bPauseLatch := TRUE; END_IF;
IF refData.bCmdResume OR NOT bBusy THEN bPauseLatch := FALSE; END_IF;
refData.bCmdPause := FALSE;
refData.bCmdResume := FALSE;
bHoldNow := bPause OR bPauseLatch OR (bDeferIrrigation AND refData.set.eActionOnDefer = E_RainAction.Pause) OR bResumeWait;
IF bHoldNow AND NOT bHoldWas THEN tHeldAt := tNow; END_IF;
bHoldWas := bHoldNow;
bRainSkip := bBusy AND bDeferIrrigation AND refData.set.eActionOnDefer = E_RainAction.Skip;
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
  fRateNow := ipMeter.fActFlowPerHour;
  bRateGood := ipMeter.bIsGood AND ABS(fRateNow) <= REAL#3.4E38;
END_IF;

(* a one-zone run asked for by the record: a start (refused while a program runs) *)
nCmdZ := 0;
bCmdRun := FALSE;
IF refData.nCmdRunOnlyZone >= nLo AND refData.nCmdRunOnlyZone <= nHi THEN
  nCmdZ := refData.nCmdRunOnlyZone;
  bCmdRun := NOT bBusy;
END_IF;
refData.nCmdRunOnlyZone := -1;

(* a new program *)
bNew := ((bRun AND NOT bRunPrev) OR bStart OR refData.bCmdStart OR bCmdRun) AND NOT bBusy;
bRunPrev := bRun;
refData.bCmdStart := FALSE;
IF bNew AND bInterlock AND NOT bIrrigatorTripped THEN
  nRunOnly := 0;
  IF nCmdZ > 0 THEN
    nRunOnly := nCmdZ;
  ELSIF nRunOnlyZone >= nLo AND nRunOnlyZone <= nHi THEN
    nRunOnly := nRunOnlyZone;
  END_IF;
  FOR nI := nLo TO nHi DO
    aZones[nI].SetDone(bZoneDone := FALSE);
    aZones[nI].SetRunTime(tRunTime := tRunTime);
  END_FOR;
  stProgress.tRunTime := MAX(tRunTime, T#0s);
  nZoneWatering := NextZone(nAfter := 0, aZ := aZones);
  IF nZoneWatering > 0 THEN
    bBusy := TRUE;
    bLatched := bStart OR bCmdRun OR NOT bRun;
    refData.sts.eStopReason := E_StopReason.None;
    refData.sts.nRunCount := refData.sts.nRunCount + 1;
    refData.sts.fDeliveredThisRun := 0.0;
    tPumpWait := T#0s;
    nPass := 1;
    bResumeWait := FALSE;
    bProveWarn := FALSE;
    bFlowWarn := FALSE;
    bWaitWarn := FALSE;
    bCapWarn := FALSE;
    bFaultEnd := FALSE;
    eFaultCode := E_UtError.None;
    IF nDoseRequest = 0 THEN
      bDoseRun := FALSE;
    ELSIF nDoseRequest = 1 THEN
      bDoseRun := TRUE;
    ELSE
      bDoseRun := refData.set.bDoseByDefault;
    END_IF;
    Go(ePh := E_ZonePhase.Opening);
  END_IF;
END_IF;

(* the program ends: stop, interlock, the irrigator, the level, the master valve, the pump wait, the held run dropped *)
bEnd := FALSE;
IF bBusy THEN
  IF bStop OR refData.bCmdStop THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Request;
  ELSIF NOT bInterlock THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Interlock;
  ELSIF bIrrigatorTripped THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.IrrigatorStop;
  ELSIF bSourceAtStopLevel THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.LevelEnd;
  ELSIF bDeferIrrigation AND refData.set.eActionOnDefer = E_RainAction.Cancel THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.Rain;
  ELSIF bHoldNow AND NOT bResumeWait AND refData.set.tMaxPauseBeforeEnd > T#0s AND tNow - tHeldAt >= refData.set.tMaxPauseBeforeEnd THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.PauseMax;
  ELSIF bResumeWait AND NOT bRun AND tNow - tPowerUp >= refData.set.tHeldRunTimeout THEN
    bEnd := TRUE;
    refData.sts.eStopReason := E_StopReason.PowerCut;
  ELSIF bMasterFault THEN
    bEnd := TRUE;
    bFaultEnd := TRUE;
    eFaultCode := E_UtError.MasterValve;
    refData.sts.eStopReason := E_StopReason.Fault;
  ELSIF refData.set.tPumpWaitTimeout > T#0s AND tPumpWait >= refData.set.tPumpWaitTimeout AND NOT refData.set.bPumpWaitSkipsZone THEN
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
IF bEnd AND nZoneWatering >= nLo AND nZoneWatering <= nHi AND nZoneWatering > 0 THEN
  aZones[nZoneWatering].SetResult(eResult := refData.sts.eStopReason, bSkipped := FALSE);   // the zone it was on
END_IF;
IF bEnd AND ePhase <> E_ZonePhase.Ending THEN
  bBusy := FALSE;
  nClosing := nZoneWatering;
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
    IF nI <> nZoneWatering AND aZones[nI].bIsPending AND (nRunOnly = DINT_TO_INT(nI) OR (nRunOnly = 0 AND aZones[nI].bIsInProgram)) THEN
      aZones[nI].SetDone(bZoneDone := TRUE);
    END_IF;
  END_FOR;
END_IF;

CASE ePhase OF
  E_ZonePhase.Opening:
    IF bHoldNow THEN
      nClosing := nZoneWatering;
      Go(ePh := E_ZonePhase.Paused);
    ELSIF bRainSkip THEN
      aZones[nZoneWatering].SetResult(eResult := E_StopReason.Rain, bSkipped := TRUE);
      DropZone(aZ := aZones);                     // the rain skips it
    ELSIF aZones[nZoneWatering].bValveOpen AND bMasterOk THEN
      IF NOT bProved THEN bProved := TRUE; tProvedAt := tNow; END_IF;
      IF tNow - tProvedAt >= refData.set.tPumpStartDelay THEN
        Go(ePh := E_ZonePhase.Watering);
      END_IF;
    ELSIF tNow - tPhaseAt >= refData.set.tValveProveTimeout AND NOT aZones[nZoneWatering].bValveOpen THEN
      bProveWarn := TRUE;         // its valve did not open: skip it
      aZones[nZoneWatering].SetResult(eResult := E_StopReason.Fault, bSkipped := TRUE);
      DropZone(aZ := aZones);
    END_IF;

  E_ZonePhase.Watering, E_ZonePhase.Changing:
    IF bCounting AND ePhase = E_ZonePhase.Watering THEN
      aZones[nZoneWatering].AddWatered(tWateredTime := tDt, fWateredVolume := fDv);   // not during a change: its target is reached
      refData.sts.fDeliveredThisRun := refData.sts.fDeliveredThisRun + fDv;
      IF refData.set.tProgressSaveInterval > T#0s AND tNow - tSavedAt >= refData.set.tProgressSaveInterval THEN
        aZones[nZoneWatering].SaveProgress();
        tSavedAt := tNow;
      END_IF;
      aZones[nZoneWatering].Flow(fFlowPerHour := fRateNow, bFlowGood := bRateGood);
    END_IF;
    IF bHoldNow THEN
      nClosing := nZoneWatering;
      Go(ePh := E_ZonePhase.Paused);
    ELSE
      IF ePhase = E_ZonePhase.Watering AND NOT bCycleDone THEN
        (* the zone's cycle ends: its water is given, or it is skipped, tripped on its flow, or the pump never came *)
        bEndNow := FALSE;
        IF bSkipZone OR refData.bCmdSkipZone OR bRainSkip THEN
          bEndNow := TRUE;
          IF bRainSkip THEN
            aZones[nZoneWatering].SetResult(eResult := E_StopReason.Rain, bSkipped := TRUE);
          ELSE
            aZones[nZoneWatering].SetResult(eResult := E_StopReason.Request, bSkipped := TRUE);
          END_IF;
        ELSIF aZones[nZoneWatering].bIsOutOnFlowCheck THEN
          bEndNow := TRUE;
          bFlowWarn := TRUE;
          aZones[nZoneWatering].SetResult(eResult := E_StopReason.Fault, bSkipped := FALSE);
        ELSIF refData.set.tPumpWaitTimeout > T#0s AND tPumpWait >= refData.set.tPumpWaitTimeout AND refData.set.bPumpWaitSkipsZone THEN
          bEndNow := TRUE;
          bWaitWarn := TRUE;
          tPumpWait := T#0s;
          aZones[nZoneWatering].SetResult(eResult := E_StopReason.PumpFault, bSkipped := TRUE);
        END_IF;
        IF bEndNow THEN
          bFinalCycle := TRUE;
          bCycleDone := TRUE;
          aZones[nZoneWatering].SetDone(bZoneDone := TRUE);
        ELSIF aZones[nZoneWatering].Reached(bProgramMetered := ipMeter <> NULL, tMaxVolumeCycleTime := refData.set.tMaxVolumeCycleTime,
                                    tDefaultTimeCap := refData.set.tDefaultTimeCap) THEN
          bFinalCycle := aZones[nZoneWatering].EndCycle();
          IF aZones[nZoneWatering].bIsEndedOnTimeCap THEN
            bCapWarn := TRUE;
          END_IF;
          bCycleDone := TRUE;
          IF bFinalCycle THEN
            aZones[nZoneWatering].SetDone(bZoneDone := TRUE);
            aZones[nZoneWatering].SetResult(eResult := E_StopReason.Done, bSkipped := FALSE);
          END_IF;
        END_IF;
      END_IF;
      IF ePhase = E_ZonePhase.Watering AND bCycleDone THEN
        nNext := NextZone(nAfter := 0, aZ := aZones);
        IF nNext = nZoneWatering THEN
          bCycleDone := FALSE;                   // its next cycle at once (no soak): the valve stays open
        ELSIF nNext = 0 THEN
          nClosing := nZoneWatering;
          IF AnyLeft(aZ := aZones) THEN
            Go(ePh := E_ZonePhase.Soaking);       // the others soak: pump off, valves closed meanwhile
          ELSIF NextPass(aZ := aZones) THEN
            Go(ePh := E_ZonePhase.Soaking);       // the next pass: the valves close, then the first zone
          ELSE
            bBusy := FALSE;
            refData.sts.eStopReason := E_StopReason.Done;
            Go(ePh := E_ZonePhase.Ending);
          END_IF;
        ELSIF bPermissive THEN
          Go(ePh := E_ZonePhase.Changing);     // open the next one; this one keeps watering meanwhile
          bCycleDone := TRUE;
        END_IF;
      ELSIF ePhase = E_ZonePhase.Changing THEN
        IF bRainSkip THEN
          aZones[nNext].SetDone(bZoneDone := TRUE);
          nNext := 0;
          Go(ePh := E_ZonePhase.Watering);
          bCycleDone := TRUE;
        ELSIF aZones[nNext].bValveOpen THEN
          IF NOT bProved THEN bProved := TRUE; tProvedAt := tNow; END_IF;
          IF tNow - tProvedAt >= refData.set.tValveOverlap THEN
            nZoneWatering := nNext;
            nNext := 0;
            Go(ePh := E_ZonePhase.Watering);
          END_IF;
        ELSIF tNow - tPhaseAt >= refData.set.tValveProveTimeout THEN
          bProveWarn := TRUE;     // the next one did not open: skip it, carry on with this one
          aZones[nNext].SetDone(bZoneDone := TRUE);
          nNext := 0;
          Go(ePh := E_ZonePhase.Watering);
          bCycleDone := TRUE;
        END_IF;
      END_IF;
    END_IF;
    refData.bCmdSkipZone := FALSE;

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
        nZoneWatering := nRdy;
        Go(ePh := E_ZonePhase.Opening);
      ELSIF NOT AnyLeft(aZ := aZones) THEN
        IF NOT NextPass(aZ := aZones) THEN
          bBusy := FALSE;
          nZoneWatering := 0;
          refData.sts.eStopReason := E_StopReason.Done;
          Go(ePh := E_ZonePhase.Idle);
        END_IF;
      END_IF;
    END_IF;

  E_ZonePhase.Ending:
    IF tNow - tPhaseAt >= refData.set.tValveCloseDelay AND NOT bPumpOn THEN
      nClosing := 0;
      nZoneWatering := 0;
      Go(ePh := E_ZonePhase.Idle);
    END_IF;
ELSE
  ;
END_CASE;

(* the valves: the zone opening or watering; the next during an overlap; the last kept open at the end until
   the pump has stopped *)
bAnyValve := FALSE;
FOR nI := nLo TO nHi DO
  bWantI := (ePhase = E_ZonePhase.Opening AND nI = nZoneWatering)
            OR ((ePhase = E_ZonePhase.Watering OR ePhase = E_ZonePhase.Changing) AND nI = nZoneWatering)
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
  ipMasterValve.Request(bRun := bMasterWant, bHoldOff := FALSE);
  IF bMasterWant AND (NOT bMasterOk OR ipMasterValve.bIsFaulted) THEN
    IF NOT bMasterLost THEN
      bMasterLost := TRUE;
      tMasterLostAt := tNow;
    END_IF;
    IF ipMasterValve.bIsFaulted OR tNow - tMasterLostAt >= refData.set.tValveProveTimeout THEN
      bMasterFault := TRUE;
    END_IF;
  ELSE
    bMasterLost := FALSE;
  END_IF;
END_IF;
IF bReset OR (NOT bBusy AND NOT bMasterWant) THEN
  bMasterFault := FALSE;
  bMasterLost := FALSE;
END_IF;

(* the pump *)
bPumpRunCommand := ePhase = E_ZonePhase.Watering OR ePhase = E_ZonePhase.Changing;
IF ipPump <> NULL THEN
  ipPump.Request(bRun := bPumpRunCommand, bHoldOff := FALSE);
END_IF;

(* the dosing hook *)
bDosingAllowed := bBusy AND bDoseRun;
bDosingPaused := TRUE;
IF ePhase = E_ZonePhase.Watering AND bCounting AND nZoneWatering > 0 THEN
  IF aZones[nZoneWatering].bDoseAllowed AND (aZones[nZoneWatering].bRunsUntilStop OR aZones[nZoneWatering].tActTimeLeft > refData.set.tFlushTime) THEN
    bDosingPaused := FALSE;
  END_IF;
END_IF;

(* the active zone's pressure *)
nAct := 0;
IF ePhase = E_ZonePhase.Opening OR ePhase = E_ZonePhase.Watering THEN
  nAct := nZoneWatering;
ELSIF ePhase = E_ZonePhase.Changing THEN
  nAct := nNext;
END_IF;
fZonePressureSetpoint := refData.set.fDefaultPressureSetpoint;
IF nAct >= nLo AND nAct <= nHi THEN
  IF aZones[nAct].fActPressureSetpoint > 0.0 THEN
    fZonePressureSetpoint := aZones[nAct].fActPressureSetpoint;
  END_IF;
END_IF;

(* what a power cut keeps: written at a start, a change of zone, a new pass and the end *)
IF bBusy <> stProgress.bBusy OR bLatched <> stProgress.bLatched OR nPass <> stProgress.nPassRunning
   OR nRunOnly <> stProgress.nRunOnlyZone OR bDoseRun <> stProgress.bDosingThisRun
   OR (bBusy AND nZoneWatering > 0 AND nZoneWatering <> stProgress.nZoneWatering) THEN
  stProgress.bBusy := bBusy;
  stProgress.bLatched := bLatched;
  stProgress.nPassRunning := nPass;
  stProgress.nRunOnlyZone := nRunOnly;
  stProgress.bDosingThisRun := bDoseRun;
  IF nZoneWatering > 0 THEN
    stProgress.nZoneWatering := nZoneWatering;
  END_IF;
END_IF;

(* status *)
bError := bFaultEnd;
bWarning := bProveWarn OR bFlowWarn OR bWaitWarn OR bCapWarn OR refData.sts.bSettingRefused;
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
ELSIF refData.sts.bSettingRefused THEN
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
refData.sts.eZonePhase := ePhase;
refData.sts.nZoneWatering := nZoneWatering;
refData.sts.bBusy := bBusy;
refData.sts.nRunOnlyZone := nRunOnly;
refData.sts.nPassRunning := nPass;
refData.sts.bDeferIrrigation := bDeferIrrigation;
refData.sts.bMasterValveOpenCommand := bMasterWant;
refData.sts.bDosingAllowed := bDosingAllowed;
refData.sts.tWaitingForPump := tPumpWait;
refData.sts.bPaused := bHoldNow AND bBusy;
refData.det.tInPhaseFor := tNow - tPhaseAt;
refData.det.tPassTimeLeft := T#0s;
IF bBusy THEN
  FOR nI := nLo TO nHi DO
    IF nRunOnly = 0 OR nRunOnly = DINT_TO_INT(nI) THEN
      refData.det.tPassTimeLeft := refData.det.tPassTimeLeft + aZones[nI].tActWaterTimeLeft;
    END_IF;
  END_FOR;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK