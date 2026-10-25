(* UT_ZONE — one zone of a zone program (UT_ZONE_SEQ): its valve, its water
time / volume, cycles and soak, its own flow band, its progress. The
project declares `zones : ARRAY [1..n] OF UT_ZONE` with their records,
calls each zone once per scan BEFORE the program and passes the array to
UT_ZONE_SEQ.Zones. The program commands it through Water every scan and
tells it the end of each cycle (EndCycle); the zone owns its valve
(Valve.Request(open, NaN, By), By = 'Zones 3') or, with no valve linked,
sets ValveOut (the program's RouteOk proves it). While it waters it checks
its flow band (flowCheck: WARN or TRIP; a trip ends the zone). Its done
flag, cycles and watered time / volume are kept (VAR RETAIN) for an exact
resume; a soak is timed by the zone (SoakLeft). A zone not called in a
scan is not enabled for the program (UT_F_ELEMENT_IDLE). Settings kept; a
bad write is put back. *)

FUNCTION_BLOCK UT_ZONE IMPLEMENTS UT_I_STATUS
  VAR_INPUT
    Valve : UT_I_VALVE; (* the zone's valve; NULL = ValveOut + the program's RouteOk *)
  END_VAR
  VAR_OUTPUT
    ValveOut : BOOL; (* zone valve wanted (simple sites) *)
    Active : BOOL; (* watering now *)
    Done : BOOL; (* done this run *)
    Fault : BOOL;
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_ZONE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ZONE_SET;
    keptGood : BOOL;
    pDone : BOOL; (* progress (exact resume) *)
    pCycles : USINT;
    pWatered : LINT; (* ms of the finished cycles *)
    pVol : LREAL;
    pResult : UT_STOP;
  END_VAR
  VAR
    keep : UT_KEEP;
    st : UT_PROT_ST;
    ok : BOOL;
    cfgId : UT_FAULT;
    x : BOOL;
    tCur : TIME;
    bodyRan : BOOL; (* the body ran since the last Water *)
    idle : BOOL; (* not called: not enabled *)
    wOn : BOOL;
    wNo : INT;
    wBy : STRING(12);
    wRate : REAL;
    wRateGood : BOOL;
    wMs : LINT; (* this cycle's watered ms *)
    wVol : LREAL;
    wCalled : BOOL;
    refusedV : BOOL;
    proven : BOOL;
    soaking : BOOL;
    soakAt : TIME;
    qSoakLeft : TIME;
    flowTrip : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    endAt : DT;
    cur : UT_ZONE_SET; (* the settings in use (the methods read it) *)
    qLocked : BOOL;
    qNe : UT_NE107;
    zero : REAL;
    nan : REAL;
  END_VAR


METHOD PUBLIC Water : BOOL       // the program's command each scan; FALSE = refused
  VAR_INPUT
    On : BOOL;                   // the valve open (watering, or opening)
    No : INT;                    // the zone's place in the program (for By)
    Owner : STRING(12);          // the program's tag
    Rate : REAL;                 // meter rate
    RateGood : BOOL;
    Ms : LINT;                   // this cycle's watered time, ms (the program's run core)
    Vol : LREAL;                 // this cycle's volume
  END_VAR
  idle := NOT bodyRan;
  bodyRan := FALSE;
  wCalled := TRUE;
  wOn := On;
  wNo := No;
  wBy := Owner;
  wRate := Rate;
  wRateGood := RateGood;
  wMs := Ms;
  wVol := Vol;
  Water := NOT idle AND ok AND NOT refusedV AND NOT flowTrip;
END_METHOD
METHOD PUBLIC EndCycle : BOOL    // the cycle ended: DONE (target), TIME_CAP, or why the zone ends now
  VAR_INPUT
    Result : UT_STOP;
    When : DT;                   // the program's clock (lastRun)
  END_VAR
  pWatered := pWatered + wMs;
  pVol := pVol + wVol;
  wMs := 0;
  wVol := 0.0;
  IF Result = UT_STOP_DONE OR Result = UT_STOP_TIME_CAP THEN
    pCycles := pCycles + 1;
    IF Result = UT_STOP_TIME_CAP THEN
      pResult := UT_STOP_TIME_CAP;
    END_IF;
    IF USINT_TO_INT(pCycles) >= cur.cycles THEN
      pDone := TRUE;
      IF pResult = UT_STOP_NONE THEN
        pResult := UT_STOP_DONE;
      END_IF;
      endAt := When;
    ELSE
      soaking := cur.soakTime > T#0s;
      soakAt := tCur;
    END_IF;
  ELSE
    pDone := TRUE;               (* skipped, tripped, not proven, ... *)
    pResult := Result;
  END_IF;
  EndCycle := pDone;
END_METHOD
METHOD PUBLIC NewRun : BOOL      // a fresh run: progress cleared
  pDone := FALSE;
  pCycles := 0;
  pWatered := 0;
  pVol := 0.0;
  pResult := UT_STOP_NONE;
  soaking := FALSE;
  wMs := 0;
  wVol := 0.0;
  NewRun := TRUE;
END_METHOD
METHOD PUBLIC IsEnabled : BOOL
  IsEnabled := cur.enable AND ok AND NOT idle;
END_METHOD
METHOD PUBLIC IsUsable : BOOL    // may water at all (a one-zone run need not be enabled)
  IsUsable := ok AND NOT idle AND NOT flowTrip;
END_METHOD
METHOD PUBLIC IsDone : BOOL
  IsDone := pDone;
END_METHOD
METHOD PUBLIC IsProven : BOOL    // its valve is open (no valve: TRUE, the program's RouteOk)
  IsProven := proven;
END_METHOD
METHOD PUBLIC HasValve : BOOL
  HasValve := Valve <> NULL;
END_METHOD
METHOD PUBLIC SoakLeft : TIME
  SoakLeft := qSoakLeft;
END_METHOD
METHOD PUBLIC CyclesDone : INT
  CyclesDone := USINT_TO_INT(pCycles);
END_METHOD
METHOD PUBLIC Watered : LINT
  Watered := pWatered + wMs;
END_METHOD
METHOD PUBLIC WateredVol : LREAL
  WateredVol := pVol + wVol;
END_METHOD
METHOD PUBLIC Settings : UT_ZONE_SET
  Settings := cur;
END_METHOD
METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := stCode;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := stF;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := pResult;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := Fault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := Warning;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := qLocked;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := TRUE;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := qNe;
END_METHOD

tCur := TIME();
bodyRan := TRUE;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_ZONE_CHECK(S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_ZONE_CHECK(S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
IF ok THEN
  cur := Data.set;
END_IF;
IF NOT (nan <> nan) THEN
  nan := zero / zero;
END_IF;
IF NOT wCalled THEN
  wOn := FALSE;                  (* the program did not command it last scan *)
END_IF;
wCalled := FALSE;

(* the valve *)
refusedV := FALSE;
IF Valve <> NULL THEN
  refusedV := NOT Valve.Request(ReqOpen := wOn, ReqPos := nan, Owner := CONCAT(wBy, CONCAT(' ', INT_TO_STRING(wNo))));
  proven := Valve.IsOpenNow();
ELSE
  proven := TRUE;
END_IF;
ValveOut := wOn;

(* its flow band, while it waters *)
x := UT_PROT_RUN(TNow := tCur, Cause := wOn AND wRateGood AND proven
                                        AND ((cur.minFlow > 0.0 AND wRate < cur.minFlow)
                                             OR (cur.maxFlow > 0.0 AND wRate > cur.maxFlow)),
                 ResetReq := NOT wOn, RetryWindow := T#1h, Prot := Data.set.flowCheck, Sts := Data.sts.flowCheck, St := st);
flowTrip := st.trip;
IF st.event THEN
  Data.sts.flowAlarm := TRUE;
END_IF;

(* the soak *)
qSoakLeft := T#0s;
IF soaking THEN
  IF tCur - soakAt >= cur.soakTime THEN
    soaking := FALSE;
  ELSE
    qSoakLeft := cur.soakTime - (tCur - soakAt);
  END_IF;
END_IF;

(* outputs and status *)
Active := wOn;
Done := pDone;
Fault := NOT ok OR refusedV OR flowTrip OR idle;
Warning := st.warn OR Data.sts.flowAlarm;
stF := UT_F_NONE;
IF NOT ok THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF idle THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_ELEMENT_IDLE;
ELSIF flowTrip THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_ZONE_FLOW;
ELSIF refusedV THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_NOT_PROVEN;
ELSIF wOn AND NOT proven THEN
  stCode := UT_ST_WAIT_PROVEN;
ELSIF wOn THEN
  stCode := UT_ST_RUN_ZONE;
ELSIF soaking THEN
  stCode := UT_ST_SOAK;
ELSIF st.warn THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_ZONE_FLOW;
ELSIF pDone THEN
  stCode := UT_ST_STOPPED;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);
qNe := Data.sts.ne107;
qLocked := Data.sts.flowCheck.locked;
Data.sts.valve := wOn;
Data.sts.active := wOn;
Data.sts.done := pDone;
Data.sts.skipped := pDone AND pResult <> UT_STOP_DONE AND pResult <> UT_STOP_TIME_CAP;
Data.sts.capped := pResult = UT_STOP_TIME_CAP;
Data.sts.cycle := USINT_TO_INT(pCycles);
Data.sts.delivered := pVol + wVol;
Data.sts.result := pResult;
Data.sts.lastRun := endAt;
Data.det.watered := LINT_TO_TIME(pWatered + wMs);
Data.det.soakLeft := qSoakLeft;
IF cur.runTime > T#0s AND cur.endBy <> UT_ZE_VOLUME AND cur.endBy <> UT_ZE_UNTIL_STOP THEN
  Data.det.remaining := cur.runTime - LINT_TO_TIME(pWatered + wMs);
  IF Data.det.remaining < T#0s THEN Data.det.remaining := T#0s; END_IF;
ELSE
  Data.det.remaining := T#0s;
END_IF;

END_FUNCTION_BLOCK