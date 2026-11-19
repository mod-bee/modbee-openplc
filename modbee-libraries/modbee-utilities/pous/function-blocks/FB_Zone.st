(* FB_Zone — one zone of a zone program: its valve, its water time or volume, its progress. The project declares
`aZones : ARRAY [1..n] OF FB_Zone` with their records, calls each zone once per scan before the program, and
passes the array to FB_ZoneSeq.aZones.

Pins: ipValve (its valve: any I_Equipment, an FB_Valve; unwired = no valve: bPlainValveOutput drives a plain output),
refData -> bPlainValveOutput, bValveOpen (its valve is proven open: the valve's state, or, with no valve, after
set.tPlainValveOpenTime).
The program opens and closes it through Open (every scan) and tells it how much it watered through AddWatered. Its
progress (bZoneDone, cycles done, watered time and volume) is kept hourly and at each change of zone, for a resume.
Cycles and soak: set.nCycles splits the water (time and volume) into that many equal cycles; after each cycle but
the last the zone soaks for set.tSoakTime (the program waters the next zones meanwhile; Open is not asked of a
soaking zone). EndCycle ends a cycle; bIsReady is TRUE for an enabled zone with water left that is not soaking.
Flow check: while the program waters it, it tells the zone the meter's flow (Flow, every scan). Flow below
set.fMinFlowWhileWatering or above set.fMaxFlowWhileWatering (0 = not checked; in the meter's unit, per hour) for set.stFlowOutOfBandFault's delay
acts per its response: Warn = a warning (sts.stFlowOutOfBandFault, ZoneFlow), Trip = the zone is out (bOutOnFlowCheck, an error
ZoneFlow; the program ends that zone) until the check resets (Auto / Retry after the recover time, or a reset).
Pressure: set.fPressureSetpoint is the zone's pressure setpoint (0 = the program's default); the program passes the
watering zone's on as fZonePressureSetpoint (wire it to FB_SpeedLoop's fSetpoint pin, with its set.eSetpointFrom Pin).
A program can give the zone another water time for one run (its tWaterTime pin, 0 = set.tWaterTime).
What ends a cycle (set.eCycleEndsBy; the cycle's targets are the zone's tWaterTime and fWaterVolume divided by set.nCycles; a
volume target needs the program to have a meter, else it counts as 0 = no target):
  ByTime      the cycle's time; a volume is ignored
  ByVolume    the cycle's volume; the time is no target
  First       the time or the volume, whichever comes first
  Auto        the volume if set.fWaterVolume > 0, else the time
  UntilStop   no target: it waters until a skip or a stop
A mode with no target left (a volume mode with no volume or no meter, a time of 0) has none: it waters until a skip
or stop. A cycle whose only target is a volume has a time cap on its counted time, so a dry meter cannot water for
ever: the program's set.tMaxVolumeCycleTime (divided by the cycles) if set, else the volume at set.fMinFlowWhileWatering (per hour), else
the program's set.tDefaultTimeCap. When the cap ends the cycle sts.bEndedOnTimeCap is TRUE and the program warns RunCapped.
In a program: sts.eLastOutcome (how it ended: Done, or the stop reason; None = not yet) and sts.bSkipped (skipped:
a skip, the rain, its valve not opening, the pump wait), set by the sequence; both clear when a program starts. *)

FUNCTION_BLOCK FB_Zone EXTENDS FB_Object
  VAR_INPUT
    ipValve : I_Equipment; (* its valve (an FB_Valve or any I_Equipment); unwired = bPlainValveOutput drives a plain output *)
    refData : REFERENCE TO ST_ZoneData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bPlainValveOutput : BOOL; (* a plain valve output, with no ipValve *)
    bValveOpen : BOOL; (* its valve is proven open *)
  END_VAR
  VAR RETAIN
    stKept : ST_ZoneSet;
    nKeptLayout : UINT;
    stProgress : ST_ZoneProgress;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 4;
  END_VAR
  VAR
    bWantOpen : BOOL;
    bOpenSeen : BOOL; (* Open was called since the last scan *)
    tOpenedAt : TIME;
    bWantPrev : BOOL;
    tSavedAt : TIME;
    bCalled : BOOL; (* its rung ran this scan (the program skips a zone that is not called) *)
    stWFlow : ST_ProtectionWork;
    fRateNow : REAL; (* the flow the program told it this scan *)
    bRateGood : BOOL;
    bFlowSeen : BOOL; (* Flow was called since the last scan *)
    bSoaking : BOOL;
    tSoakAt : TIME;
    bFlowTripped : BOOL;
    tCycBase : TIME; (* sts.tWateredTime / fWateredVolume when this cycle began *)
    fCycBase : LREAL;
    tLeftNow : TIME; (* the cycle's time left, worked out by Reached *)
    bCapHit : BOOL;
    tRunFor : TIME; (* the program's run time for this run (0 = set.tWaterTime) *)
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tWaterTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fWaterVolume >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tPlainValveOpenTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nCycles >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nCycles <= 100) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tSoakTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fMinFlowWhileWatering >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMinFlowWhileWatering <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMaxFlowWhileWatering >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMaxFlowWhileWatering <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMaxFlowWhileWatering = 0.0 OR refData.set.fMaxFlowWhileWatering > refData.set.fMinFlowWhileWatering) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (refData.set.stFlowOutOfBandFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stFlowOutOfBandFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stFlowOutOfBandFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fPressureSetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fPressureSetpoint <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.eCycleEndsBy = E_ZoneEnd.Auto OR refData.set.eCycleEndsBy = E_ZoneEnd.ByTime
             OR refData.set.eCycleEndsBy = E_ZoneEnd.UntilStop OR refData.set.eCycleEndsBy = E_ZoneEnd.ByVolume
             OR refData.set.eCycleEndsBy = E_ZoneEnd.First) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

(* the program: open (TRUE) or close the valve; every scan *)
METHOD PUBLIC Open
  VAR_INPUT
    bOpen : BOOL;    // called by FB_ZoneSeq: open (TRUE) or close the zone
  END_VAR
  bWantOpen := bOpen;
  bOpenSeen := TRUE;
END_METHOD

(* the program: water given this scan *)
METHOD PUBLIC AddWatered
  VAR_INPUT
    tWateredTime : TIME;    // called by FB_ZoneSeq: watering time to add
    fWateredVolume : LREAL;    // called by FB_ZoneSeq: volume to add
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.tWateredTime := refData.sts.tWateredTime + tWateredTime;
    refData.sts.fWateredVolume := refData.sts.fWateredVolume + fWateredVolume;
  END_IF;
END_METHOD

(* the program: the flow of the meter this scan, while it waters this zone *)
METHOD PUBLIC Flow
  VAR_INPUT
    fFlowPerHour : REAL;                 // per hour, the meter's unit
    bFlowGood : BOOL;    // called by FB_ZoneSeq: the flow can be trusted
  END_VAR
  fRateNow := fFlowPerHour;
  bRateGood := bFlowGood;
  bFlowSeen := TRUE;
END_METHOD

(* the program: this zone is done (TRUE) or starts afresh (FALSE) *)
METHOD PUBLIC SetDone
  VAR_INPUT
    bZoneDone : BOOL;    // called by FB_ZoneSeq: mark the zone done (or not)
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.bZoneDone := bZoneDone;
    IF NOT bZoneDone THEN
      refData.sts.bSkipped := FALSE;
      refData.sts.eLastOutcome := E_StopReason.None;
      refData.sts.tWateredTime := T#0s;
      refData.sts.fWateredVolume := 0.0;
      refData.sts.nCycleCount := 0;
      refData.sts.bEndedOnTimeCap := FALSE;
      tCycBase := T#0s;
      fCycBase := 0.0;
      bSoaking := FALSE;
    END_IF;
    stProgress.bZoneDone := bZoneDone;
    stProgress.tWateredAtCycleStart := tCycBase;
    stProgress.fWateredAtCycleStart := fCycBase;
    stProgress.nCycleCount := refData.sts.nCycleCount;
    stProgress.tWateredTime := refData.sts.tWateredTime;
    stProgress.fWateredVolume := refData.sts.fWateredVolume;
  END_IF;
END_METHOD

(* the program, at its start: this run's water time (0 = the zone's own set.tWaterTime) *)
METHOD PUBLIC SetRunTime
  VAR_INPUT
    tRunTime : TIME;
  END_VAR
  tRunFor := MAX(tRunTime, T#0s);
END_METHOD

(* the water time in use: this run's (SetRunTime) or set.tWaterTime *)
PROPERTY PUBLIC tActRunTime : TIME    // its water time in use now (the run's, else set.tWaterTime)
  GET
    tActRunTime := T#0s;
    IF tRunFor > T#0s THEN
      tActRunTime := tRunFor;
    ELSIF __ISVALIDREF(refData) THEN
      tActRunTime := refData.set.tWaterTime;
    END_IF;
  END_GET
END_PROPERTY

(* the program: how the zone ended in this program (sts.eLastOutcome, sts.bSkipped) *)
METHOD PUBLIC SetResult
  VAR_INPUT
    eResult : E_StopReason;
    bSkipped : BOOL;
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.eLastOutcome := eResult;
    refData.sts.bSkipped := bSkipped;
  END_IF;
END_METHOD

(* the program: keep the progress now (its set.tProgressSaveInterval) *)
METHOD PUBLIC SaveProgress
  IF __ISVALIDREF(refData) THEN
    stProgress.nCycleCount := refData.sts.nCycleCount;
    stProgress.tWateredTime := refData.sts.tWateredTime;
    stProgress.fWateredVolume := refData.sts.fWateredVolume;
  END_IF;
END_METHOD

(* the program: the cycle's water is given. TRUE: that was the last cycle; FALSE: the zone soaks (set.tSoakTime) or
   is ready for its next cycle at once *)
METHOD PUBLIC EndCycle : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    EndCycle := TRUE;
    RETURN;
  END_IF;
  refData.sts.nCycleCount := refData.sts.nCycleCount + 1;
  refData.sts.bEndedOnTimeCap := bCapHit;
  bCapHit := FALSE;
  tCycBase := refData.sts.tWateredTime;
  fCycBase := refData.sts.fWateredVolume;
  stProgress.tWateredAtCycleStart := tCycBase;
  stProgress.fWateredAtCycleStart := fCycBase;
  IF refData.sts.nCycleCount >= refData.set.nCycles THEN
    EndCycle := TRUE;
    bSoaking := FALSE;
  ELSE
    EndCycle := FALSE;
    bSoaking := refData.set.tSoakTime > T#0s;
    tSoakAt := TIME();
  END_IF;
  stProgress.nCycleCount := refData.sts.nCycleCount;
  stProgress.tWateredTime := refData.sts.tWateredTime;
  stProgress.fWateredVolume := refData.sts.fWateredVolume;
END_METHOD

(* this cycle's water is given, per set.eCycleEndsBy (see the header); the program's cap values are passed in *)
METHOD PUBLIC Reached : BOOL
  VAR_INPUT
    bProgramMetered : BOOL;             // the program has a meter
    tMaxVolumeCycleTime : TIME;              // the program's cap for a volume cycle (0 = worked out), per zone (divided by the cycles)
    tDefaultTimeCap : TIME;           // the cap when there is neither
  END_VAR
  VAR
    nN : DINT;
    tTgtT : TIME;
    fTgtV : LREAL;
    tCyc : TIME;
    fCyc : LREAL;
    tCap : TIME;
    bTimeEnd : BOOL;
    bVolEnd : BOOL;
    bCapEnd : BOOL;
  END_VAR
  tLeftNow := T#0s;
  IF NOT __ISVALIDREF(refData) THEN
    bCapHit := FALSE;
    Reached := TRUE;
    RETURN;
  END_IF;
  IF refData.sts.nCycleCount >= refData.set.nCycles THEN
    bCapHit := FALSE;
    Reached := TRUE;
    RETURN;
  END_IF;
  nN := MAX(INT_TO_DINT(refData.set.nCycles), 1);
  tTgtT := T#0s;
  fTgtV := 0.0;
  CASE refData.set.eCycleEndsBy OF
    E_ZoneEnd.ByTime:
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tActRunTime) / DINT_TO_LINT(nN));
    E_ZoneEnd.ByVolume:
      fTgtV := refData.set.fWaterVolume / DINT_TO_LREAL(nN);
    E_ZoneEnd.First:
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tActRunTime) / DINT_TO_LINT(nN));
      fTgtV := refData.set.fWaterVolume / DINT_TO_LREAL(nN);
    E_ZoneEnd.UntilStop:
      ;
  ELSE
    IF refData.set.fWaterVolume > 0.0 THEN
      fTgtV := refData.set.fWaterVolume / DINT_TO_LREAL(nN);
    ELSE
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tActRunTime) / DINT_TO_LINT(nN));
    END_IF;
  END_CASE;
  IF NOT bProgramMetered THEN
    fTgtV := 0.0;
  END_IF;
  tCyc := refData.sts.tWateredTime - tCycBase;
  fCyc := refData.sts.fWateredVolume - fCycBase;
  bTimeEnd := tTgtT > T#0s AND tCyc >= tTgtT;
  bVolEnd := fTgtV > 0.0 AND fCyc >= fTgtV;
  (* a cycle whose only target is a volume always has a time cap *)
  tCap := T#0s;
  IF fTgtV > 0.0 AND tTgtT <= T#0s THEN
    IF tMaxVolumeCycleTime > T#0s THEN
      tCap := LINT_TO_TIME(TIME_TO_LINT(tMaxVolumeCycleTime) / DINT_TO_LINT(nN));
    ELSIF refData.set.fMinFlowWhileWatering > 0.0 THEN
      tCap := LINT_TO_TIME(LREAL_TO_LINT(fTgtV * 3600000.0 / REAL_TO_LREAL(refData.set.fMinFlowWhileWatering)));
    ELSE
      tCap := tDefaultTimeCap;
    END_IF;
    bCapEnd := tCap > T#0s AND tCyc >= tCap;
  END_IF;
  (* the time left in the cycle (for the dosing flush): its time, or the volume left at the flow now *)
  IF tTgtT > T#0s THEN
    tLeftNow := tTgtT - tCyc;
  ELSIF fTgtV > 0.0 THEN
    IF bRateGood AND fRateNow > 0.0 THEN
      tLeftNow := LINT_TO_TIME(LREAL_TO_LINT((fTgtV - fCyc) * 3600000.0 / REAL_TO_LREAL(fRateNow)));
    ELSIF tCap > T#0s THEN
      tLeftNow := tCap - tCyc;
    END_IF;
  END_IF;
  IF tLeftNow < T#0s THEN
    tLeftNow := T#0s;
  END_IF;
  bCapHit := bCapEnd AND NOT bTimeEnd AND NOT bVolEnd;
  Reached := bTimeEnd OR bVolEnd OR bCapEnd;
END_METHOD

PROPERTY PUBLIC bIsInProgram : BOOL    // called by FB_ZoneSeq: the zone is in the program
  GET
    bIsInProgram := __ISVALIDREF(refData) AND bCalled;
    IF bIsInProgram THEN bIsInProgram := refData.set.bInProgram; END_IF;
  END_GET
END_PROPERTY

(* water left, not soaking, usable: it may water now (a one-zone run need not have it enabled) *)
PROPERTY PUBLIC bIsWaterable : BOOL    // called by FB_ZoneSeq: it can water now (not done, not soaking, cycles left)
  GET
    bIsWaterable := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsWaterable THEN
      bIsWaterable := NOT refData.sts.bZoneDone AND NOT bSoaking AND refData.sts.nCycleCount < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

(* in the program as well: the program's next zone *)
PROPERTY PUBLIC bIsReady : BOOL    // called by FB_ZoneSeq: ready to water
  GET
    bIsReady := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsReady THEN
      bIsReady := refData.set.bInProgram AND NOT refData.sts.bZoneDone AND NOT bSoaking AND refData.sts.nCycleCount < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

(* water left (soaking too) and usable: the program is not over while it is TRUE *)
PROPERTY PUBLIC bIsPending : BOOL    // called by FB_ZoneSeq: water still to give (not done, cycles left)
  GET
    bIsPending := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsPending THEN
      bIsPending := NOT refData.sts.bZoneDone AND refData.sts.nCycleCount < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsSoaking : BOOL    // called by FB_ZoneSeq: soaking between cycles
  GET
    bIsSoaking := bSoaking;
  END_GET
END_PROPERTY

(* it may water (a one-zone run need not have it in the program): called, valid, not out on its flow check *)
PROPERTY PUBLIC bIsAvailable : BOOL    // called by FB_ZoneSeq: the zone has a record, is called and not out on the flow check
  GET
    bIsAvailable := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsOutOnFlowCheck : BOOL    // called by FB_ZoneSeq: the flow check has taken the zone out
  GET
    bIsOutOnFlowCheck := bFlowTripped;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsDone : BOOL    // called by FB_ZoneSeq: done in this program
  GET
    IF __ISVALIDREF(refData) THEN bIsDone := refData.sts.bZoneDone; ELSE bIsDone := TRUE; END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsEndedOnTimeCap : BOOL    // called by FB_ZoneSeq: the last cycle ended on its time cap
  GET
    bIsEndedOnTimeCap := __ISVALIDREF(refData) AND refData.sts.bEndedOnTimeCap;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bRunsUntilStop : BOOL    // the zone waters until a stop (eCycleEndsBy UntilStop)
  GET
    bRunsUntilStop := __ISVALIDREF(refData) AND refData.set.eCycleEndsBy = E_ZoneEnd.UntilStop;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActPressureSetpoint : REAL    // the zone's pressure setpoint in use
  GET
    IF __ISVALIDREF(refData) THEN fActPressureSetpoint := refData.set.fPressureSetpoint; ELSE fActPressureSetpoint := 0.0; END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bDoseAllowed : BOOL    // this zone may be dosed
  GET
    IF __ISVALIDREF(refData) THEN bDoseAllowed := refData.set.bDoseAllowed; ELSE bDoseAllowed := FALSE; END_IF;
  END_GET
END_PROPERTY

(* the time this cycle's water has left (as of the last Reached) *)
PROPERTY PUBLIC tActTimeLeft : TIME    // time left in the zone now
  GET
    tActTimeLeft := tLeftNow;
  END_GET
END_PROPERTY

(* the time this zone still has to water in this program (its cycles left x the cycle's share of the water
   time in use, less the running cycle's watered time); 0 for a zone done, not enabled, or watered by volume
   only *)
PROPERTY PUBLIC tActWaterTimeLeft : TIME    // the water time still to give in this program (0 when done, not in the program, or by volume)
  GET
    tActWaterTimeLeft := T#0s;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.bInProgram AND NOT refData.sts.bZoneDone AND tActRunTime > T#0s THEN
        tActWaterTimeLeft := LINT_TO_TIME(MAX(LINT#0,
                           TIME_TO_LINT(tActRunTime) / INT_TO_LINT(MAX(refData.set.nCycles, 1))
                           * INT_TO_LINT(MAX(0, refData.set.nCycles - refData.sts.nCycleCount))
                           - TIME_TO_LINT(refData.sts.tWateredTime - tCycBase)));
      END_IF;
    END_IF;
  END_GET
END_PROPERTY

IF NOT __ISVALIDREF(refData) THEN
  bPlainValveOutput := FALSE;
  bValveOpen := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.sts.bZoneDone := stProgress.bZoneDone;
    refData.sts.nCycleCount := stProgress.nCycleCount;
    refData.sts.tWateredTime := stProgress.tWateredTime;
    refData.sts.fWateredVolume := stProgress.fWateredVolume;
    tCycBase := stProgress.tWateredAtCycleStart;
    fCycBase := stProgress.fWateredAtCycleStart;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tSavedAt := tNow;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the program's command: every scan, else closed *)
IF NOT bOpenSeen THEN
  bWantOpen := FALSE;
END_IF;
bOpenSeen := FALSE;
IF bWantOpen AND NOT bWantPrev THEN
  tOpenedAt := tNow;
END_IF;
bWantPrev := bWantOpen;
IF ipValve <> NULL THEN
  ipValve.Request(bRun := bWantOpen, bHoldOff := FALSE);
  bPlainValveOutput := FALSE;
  bValveOpen := bWantOpen AND ipValve.bIsRunning;      // a valve's "running" is open
ELSE
  bPlainValveOutput := bWantOpen;
  bValveOpen := bWantOpen AND tNow - tOpenedAt >= refData.set.tPlainValveOpenTime;
END_IF;

(* its flow band, while the program waters it *)
bFlowTripped := F_Protect(tNow := tNow,
                          bConditionPresent := bFlowSeen AND bRateGood AND bValveOpen
                                    AND ((refData.set.fMinFlowWhileWatering > 0.0 AND fRateNow < refData.set.fMinFlowWhileWatering)
                                         OR (refData.set.fMaxFlowWhileWatering > 0.0 AND fRateNow > refData.set.fMaxFlowWhileWatering)),
                          bResetRequest := NOT bWantOpen OR SystemReset(), tRetryCountWindow := refData.set.tRetryCountWindow,
                          stSettings := refData.set.stFlowOutOfBandFault, stStatus := refData.sts.stFlowOutOfBandFault, stWorking := stWFlow);
bFlowSeen := FALSE;

(* the soak *)
IF bSoaking AND tNow - tSoakAt >= refData.set.tSoakTime THEN
  bSoaking := FALSE;
END_IF;
refData.sts.bSoaking := bSoaking;
IF bSoaking THEN
  refData.sts.tSoakTimeLeft := refData.set.tSoakTime - (tNow - tSoakAt);
ELSE
  refData.sts.tSoakTimeLeft := T#0s;
END_IF;
refData.sts.bOutOnFlowCheck := bFlowTripped;

(* progress kept hourly (and at each change of zone, by SetDone) *)
IF tNow - tSavedAt >= T#1h THEN
  stProgress.nCycleCount := refData.sts.nCycleCount;
  stProgress.tWateredTime := refData.sts.tWateredTime;
  stProgress.fWateredVolume := refData.sts.fWateredVolume;
  tSavedAt := tNow;
END_IF;
refData.sts.bValveOpen := bValveOpen;
refData.sts.bWatering := bWantOpen;
IF tActRunTime > refData.sts.tWateredTime THEN
  refData.sts.tTimeLeft := tActRunTime - refData.sts.tWateredTime;
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
bCalled := TRUE;
bError := bFlowTripped;
bWarning := NOT bError AND (stWFlow.bWarning OR refData.sts.bSettingRefused);
IF bFlowTripped OR stWFlow.bWarning THEN
  eErrorId := E_UtError.ZoneFlow;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bFlowTripped THEN
  eState := E_State.Fault;
ELSIF bValveOpen THEN
  eState := E_State.Running;
ELSIF bWantOpen THEN
  eState := E_State.Starting;
ELSIF bSoaking THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK