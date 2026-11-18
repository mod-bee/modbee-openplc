(* FB_Zone — one zone of a zone program: its valve, its water time or volume, its progress. The project declares
`aZones : ARRAY [1..n] OF FB_Zone` with their records, calls each zone once per scan before the program, and
passes the array to FB_ZoneSeq.aZones.

Pins: ipValve (its valve: any I_Equipment, an FB_Valve; unwired = no valve: bValveOut drives a plain output),
refData -> bValveOut, bOpen (its valve is proven open: the valve's state, or, with no valve, after
set.tOpenTime).
The program opens and closes it through Open (every scan) and tells it how much it watered through AddWatered. Its
progress (bDone, cycles done, watered time and volume) is kept hourly and at each change of zone, for a resume.
Cycles and soak: set.nCycles splits the water (time and volume) into that many equal cycles; after each cycle but
the last the zone soaks for set.tSoakTime (the program waters the next zones meanwhile; Open is not asked of a
soaking zone). EndCycle ends a cycle; bIsReady is TRUE for an enabled zone with water left that is not soaking.
Flow check: while the program waters it, it tells the zone the meter's flow (Flow, every scan). Flow below
set.fMinFlow or above set.fMaxFlow (0 = not checked; in the meter's unit, per hour) for set.stFlowCheck's delay
acts per its response: Warn = a warning (sts.stFlowCheck, ZoneFlow), Trip = the zone is out (bFlowTrip, an error
ZoneFlow; the program ends that zone) until the check resets (Auto / Retry after the recover time, or a reset).
Pressure: set.fPressure is the zone's pressure setpoint (0 = the program's default); the program passes the
watering zone's on as fZoneSp (wire it to FB_SpeedLoop's fSp pin, with its set.eSpSource Pin).
A program can give the zone another water time for one run (its tRunTime pin, 0 = set.tRunTime).
What ends a cycle (set.eEndBy; the cycle's targets are the zone's tRunTime and fVolume divided by set.nCycles; a
volume target needs the program to have a meter, else it counts as 0 = no target):
  ByTime      the cycle's time; a volume is ignored
  ByVolume    the cycle's volume; the time is no target
  First       the time or the volume, whichever comes first
  Auto        the volume if set.fVolume > 0, else the time
  UntilStop   no target: it waters until a skip or a stop
A mode with no target left (a volume mode with no volume or no meter, a time of 0) has none: it waters until a skip
or stop. A cycle whose only target is a volume has a time cap on its counted time, so a dry meter cannot water for
ever: the program's set.tMaxTime (divided by the cycles) if set, else the volume at set.fMinFlow (per hour), else
the program's set.tDefaultCap. When the cap ends the cycle sts.bCapped is TRUE and the program warns RunCapped.
In a program: sts.eResult (how it ended: Done, or the stop reason; None = not yet) and sts.bSkipped (skipped:
a skip, the rain, its valve not opening, the pump wait), set by the sequence; both clear when a program starts. *)

FUNCTION_BLOCK FB_Zone EXTENDS FB_Object
  VAR_INPUT
    ipValve : I_Equipment;
    refData : REFERENCE TO ST_ZoneData;
  END_VAR
  VAR_OUTPUT
    bValveOut : BOOL;
    bOpen : BOOL;
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
    tCycBase : TIME; (* sts.tWatered / fWatered when this cycle began *)
    fCycBase : LREAL;
    tLeftNow : TIME; (* the cycle's time left, worked out by Reached *)
    bCapHit : BOOL;
    tRunFor : TIME; (* the program's run time for this run (0 = set.tRunTime) *)
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fVolume >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tOpenTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nCycles >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nCycles <= 100) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tSoakTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fMinFlow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMinFlow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMaxFlow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fMaxFlow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.fMaxFlow = 0.0 OR refData.set.fMaxFlow > refData.set.fMinFlow) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (refData.set.stFlowCheck.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stFlowCheck.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stFlowCheck.nMaxRetries >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fPressure >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fPressure <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.eEndBy = E_ZoneEnd.Auto OR refData.set.eEndBy = E_ZoneEnd.ByTime
             OR refData.set.eEndBy = E_ZoneEnd.UntilStop OR refData.set.eEndBy = E_ZoneEnd.ByVolume
             OR refData.set.eEndBy = E_ZoneEnd.First) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

(* the program: open (TRUE) or close the valve; every scan *)
METHOD PUBLIC Open
  VAR_INPUT
    bOpen : BOOL;
  END_VAR
  bWantOpen := bOpen;
  bOpenSeen := TRUE;
END_METHOD

(* the program: water given this scan *)
METHOD PUBLIC AddWatered
  VAR_INPUT
    tWatered : TIME;
    fWatered : LREAL;
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.tWatered := refData.sts.tWatered + tWatered;
    refData.sts.fWatered := refData.sts.fWatered + fWatered;
  END_IF;
END_METHOD

(* the program: the flow of the meter this scan, while it waters this zone *)
METHOD PUBLIC Flow
  VAR_INPUT
    fRate : REAL;                 // per hour, the meter's unit
    bGood : BOOL;
  END_VAR
  fRateNow := fRate;
  bRateGood := bGood;
  bFlowSeen := TRUE;
END_METHOD

(* the program: this zone is done (TRUE) or starts afresh (FALSE) *)
METHOD PUBLIC SetDone
  VAR_INPUT
    bDone : BOOL;
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.bDone := bDone;
    IF NOT bDone THEN
      refData.sts.bSkipped := FALSE;
      refData.sts.eResult := E_StopReason.None;
      refData.sts.tWatered := T#0s;
      refData.sts.fWatered := 0.0;
      refData.sts.nCycle := 0;
      refData.sts.bCapped := FALSE;
      tCycBase := T#0s;
      fCycBase := 0.0;
      bSoaking := FALSE;
    END_IF;
    stProgress.bDone := bDone;
    stProgress.tBase := tCycBase;
    stProgress.fBase := fCycBase;
    stProgress.nCycle := refData.sts.nCycle;
    stProgress.tWatered := refData.sts.tWatered;
    stProgress.fWatered := refData.sts.fWatered;
  END_IF;
END_METHOD

(* the program, at its start: this run's water time (0 = the zone's own set.tRunTime) *)
METHOD PUBLIC SetRunTime
  VAR_INPUT
    tRunTime : TIME;
  END_VAR
  tRunFor := MAX(tRunTime, T#0s);
END_METHOD

(* the water time in use: this run's (SetRunTime) or set.tRunTime *)
PROPERTY PUBLIC tRunTimeNow : TIME
  GET
    tRunTimeNow := T#0s;
    IF tRunFor > T#0s THEN
      tRunTimeNow := tRunFor;
    ELSIF __ISVALIDREF(refData) THEN
      tRunTimeNow := refData.set.tRunTime;
    END_IF;
  END_GET
END_PROPERTY

(* the program: how the zone ended in this program (sts.eResult, sts.bSkipped) *)
METHOD PUBLIC SetResult
  VAR_INPUT
    eResult : E_StopReason;
    bSkipped : BOOL;
  END_VAR
  IF __ISVALIDREF(refData) THEN
    refData.sts.eResult := eResult;
    refData.sts.bSkipped := bSkipped;
  END_IF;
END_METHOD

(* the program: keep the progress now (its set.tProgressSave) *)
METHOD PUBLIC SaveProgress
  IF __ISVALIDREF(refData) THEN
    stProgress.nCycle := refData.sts.nCycle;
    stProgress.tWatered := refData.sts.tWatered;
    stProgress.fWatered := refData.sts.fWatered;
  END_IF;
END_METHOD

(* the program: the cycle's water is given. TRUE: that was the last cycle; FALSE: the zone soaks (set.tSoakTime) or
   is ready for its next cycle at once *)
METHOD PUBLIC EndCycle : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    EndCycle := TRUE;
    RETURN;
  END_IF;
  refData.sts.nCycle := refData.sts.nCycle + 1;
  refData.sts.bCapped := bCapHit;
  bCapHit := FALSE;
  tCycBase := refData.sts.tWatered;
  fCycBase := refData.sts.fWatered;
  stProgress.tBase := tCycBase;
  stProgress.fBase := fCycBase;
  IF refData.sts.nCycle >= refData.set.nCycles THEN
    EndCycle := TRUE;
    bSoaking := FALSE;
  ELSE
    EndCycle := FALSE;
    bSoaking := refData.set.tSoakTime > T#0s;
    tSoakAt := TIME();
  END_IF;
  stProgress.nCycle := refData.sts.nCycle;
  stProgress.tWatered := refData.sts.tWatered;
  stProgress.fWatered := refData.sts.fWatered;
END_METHOD

(* this cycle's water is given, per set.eEndBy (see the header); the program's cap values are passed in *)
METHOD PUBLIC Reached : BOOL
  VAR_INPUT
    bByVolume : BOOL;             // the program has a meter
    tMaxTime : TIME;              // the program's cap for a volume cycle (0 = worked out), per zone (divided by the cycles)
    tDefaultCap : TIME;           // the cap when there is neither
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
  IF refData.sts.nCycle >= refData.set.nCycles THEN
    bCapHit := FALSE;
    Reached := TRUE;
    RETURN;
  END_IF;
  nN := MAX(INT_TO_DINT(refData.set.nCycles), 1);
  tTgtT := T#0s;
  fTgtV := 0.0;
  CASE refData.set.eEndBy OF
    E_ZoneEnd.ByTime:
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tRunTimeNow) / DINT_TO_LINT(nN));
    E_ZoneEnd.ByVolume:
      fTgtV := refData.set.fVolume / DINT_TO_LREAL(nN);
    E_ZoneEnd.First:
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tRunTimeNow) / DINT_TO_LINT(nN));
      fTgtV := refData.set.fVolume / DINT_TO_LREAL(nN);
    E_ZoneEnd.UntilStop:
      ;
  ELSE
    IF refData.set.fVolume > 0.0 THEN
      fTgtV := refData.set.fVolume / DINT_TO_LREAL(nN);
    ELSE
      tTgtT := LINT_TO_TIME(TIME_TO_LINT(tRunTimeNow) / DINT_TO_LINT(nN));
    END_IF;
  END_CASE;
  IF NOT bByVolume THEN
    fTgtV := 0.0;
  END_IF;
  tCyc := refData.sts.tWatered - tCycBase;
  fCyc := refData.sts.fWatered - fCycBase;
  bTimeEnd := tTgtT > T#0s AND tCyc >= tTgtT;
  bVolEnd := fTgtV > 0.0 AND fCyc >= fTgtV;
  (* a cycle whose only target is a volume always has a time cap *)
  tCap := T#0s;
  IF fTgtV > 0.0 AND tTgtT <= T#0s THEN
    IF tMaxTime > T#0s THEN
      tCap := LINT_TO_TIME(TIME_TO_LINT(tMaxTime) / DINT_TO_LINT(nN));
    ELSIF refData.set.fMinFlow > 0.0 THEN
      tCap := LINT_TO_TIME(LREAL_TO_LINT(fTgtV * 3600000.0 / REAL_TO_LREAL(refData.set.fMinFlow)));
    ELSE
      tCap := tDefaultCap;
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

PROPERTY PUBLIC bIsEnabled : BOOL
  GET
    bIsEnabled := __ISVALIDREF(refData) AND bCalled;
    IF bIsEnabled THEN bIsEnabled := refData.set.bEnable; END_IF;
  END_GET
END_PROPERTY

(* water left, not soaking, usable: it may water now (a one-zone run need not have it enabled) *)
PROPERTY PUBLIC bIsWaterable : BOOL
  GET
    bIsWaterable := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsWaterable THEN
      bIsWaterable := NOT refData.sts.bDone AND NOT bSoaking AND refData.sts.nCycle < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

(* in the program as well: the program's next zone *)
PROPERTY PUBLIC bIsReady : BOOL
  GET
    bIsReady := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsReady THEN
      bIsReady := refData.set.bEnable AND NOT refData.sts.bDone AND NOT bSoaking AND refData.sts.nCycle < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

(* water left (soaking too) and usable: the program is not over while it is TRUE *)
PROPERTY PUBLIC bIsPending : BOOL
  GET
    bIsPending := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
    IF bIsPending THEN
      bIsPending := NOT refData.sts.bDone AND refData.sts.nCycle < refData.set.nCycles;
    END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsSoaking : BOOL
  GET
    bIsSoaking := bSoaking;
  END_GET
END_PROPERTY

(* it may water (a one-zone run need not have it in the program): called, valid, not out on its flow check *)
PROPERTY PUBLIC bIsUsable : BOOL
  GET
    bIsUsable := __ISVALIDREF(refData) AND bCalled AND NOT bFlowTripped;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsFlowTrip : BOOL
  GET
    bIsFlowTrip := bFlowTripped;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsDone : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bIsDone := refData.sts.bDone; ELSE bIsDone := TRUE; END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsCapped : BOOL
  GET
    bIsCapped := __ISVALIDREF(refData) AND refData.sts.bCapped;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bUntilStop : BOOL
  GET
    bUntilStop := __ISVALIDREF(refData) AND refData.set.eEndBy = E_ZoneEnd.UntilStop;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActPressure : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActPressure := refData.set.fPressure; ELSE fActPressure := 0.0; END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bDoseAllowed : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bDoseAllowed := refData.set.bDose; ELSE bDoseAllowed := FALSE; END_IF;
  END_GET
END_PROPERTY

(* the time this cycle's water has left (as of the last Reached) *)
PROPERTY PUBLIC tActTimeLeft : TIME
  GET
    tActTimeLeft := tLeftNow;
  END_GET
END_PROPERTY

(* the time this zone still has to water in this program (its cycles left x the cycle's share of the water
   time in use, less the running cycle's watered time); 0 for a zone done, not enabled, or watered by volume
   only *)
PROPERTY PUBLIC tActRemaining : TIME
  GET
    tActRemaining := T#0s;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.bEnable AND NOT refData.sts.bDone AND tRunTimeNow > T#0s THEN
        tActRemaining := LINT_TO_TIME(MAX(LINT#0,
                           TIME_TO_LINT(tRunTimeNow) / INT_TO_LINT(MAX(refData.set.nCycles, 1))
                           * INT_TO_LINT(MAX(0, refData.set.nCycles - refData.sts.nCycle))
                           - TIME_TO_LINT(refData.sts.tWatered - tCycBase)));
      END_IF;
    END_IF;
  END_GET
END_PROPERTY

IF NOT __ISVALIDREF(refData) THEN
  bValveOut := FALSE;
  bOpen := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.sts.bDone := stProgress.bDone;
    refData.sts.nCycle := stProgress.nCycle;
    refData.sts.tWatered := stProgress.tWatered;
    refData.sts.fWatered := stProgress.fWatered;
    tCycBase := stProgress.tBase;
    fCycBase := stProgress.fBase;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tSavedAt := tNow;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
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
  ipValve.Request(bRun := bWantOpen, bHold := FALSE);
  bValveOut := FALSE;
  bOpen := bWantOpen AND ipValve.bIsRunning;      // a valve's "running" is open
ELSE
  bValveOut := bWantOpen;
  bOpen := bWantOpen AND tNow - tOpenedAt >= refData.set.tOpenTime;
END_IF;

(* its flow band, while the program waters it *)
bFlowTripped := F_Protect(tNow := tNow,
                          bCause := bFlowSeen AND bRateGood AND bOpen
                                    AND ((refData.set.fMinFlow > 0.0 AND fRateNow < refData.set.fMinFlow)
                                         OR (refData.set.fMaxFlow > 0.0 AND fRateNow > refData.set.fMaxFlow)),
                          bResetReq := NOT bWantOpen OR SystemReset(), tRetryWindow := T#1h,
                          stSet := refData.set.stFlowCheck, stSts := refData.sts.stFlowCheck, stWork := stWFlow);
bFlowSeen := FALSE;

(* the soak *)
IF bSoaking AND tNow - tSoakAt >= refData.set.tSoakTime THEN
  bSoaking := FALSE;
END_IF;
refData.sts.bSoaking := bSoaking;
IF bSoaking THEN
  refData.sts.tSoakLeft := refData.set.tSoakTime - (tNow - tSoakAt);
ELSE
  refData.sts.tSoakLeft := T#0s;
END_IF;
refData.sts.bFlowTrip := bFlowTripped;

(* progress kept hourly (and at each change of zone, by SetDone) *)
IF tNow - tSavedAt >= T#1h THEN
  stProgress.nCycle := refData.sts.nCycle;
  stProgress.tWatered := refData.sts.tWatered;
  stProgress.fWatered := refData.sts.fWatered;
  tSavedAt := tNow;
END_IF;
refData.sts.bOpen := bOpen;
refData.sts.bWatering := bWantOpen;
IF tRunTimeNow > refData.sts.tWatered THEN
  refData.sts.tTimeLeft := tRunTimeNow - refData.sts.tWatered;
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
bCalled := TRUE;
bError := bFlowTripped;
bWarning := NOT bError AND (stWFlow.bWarn OR refData.sts.bRefused);
IF bFlowTripped OR stWFlow.bWarn THEN
  eErrorId := E_UtError.ZoneFlow;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bFlowTripped THEN
  eState := E_State.Fault;
ELSIF bOpen THEN
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