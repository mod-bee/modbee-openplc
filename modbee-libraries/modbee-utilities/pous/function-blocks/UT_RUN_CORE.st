(* UT_RUN_CORE — one run of any equipment (private; UT_RUN_LIMIT, UT_ZONE_SEQ,
the station's TRANSFER). A run is made of one or more parts (UT_RUN_LIMIT:
one part = the run; UT_ZONE_SEQ: one part per zone cycle, EndAtTarget
FALSE). It owns: start, the permissive wait, pause, time and volume
counting, the part's target and time cap, meter failed, abort with a
reason, time left, the stop reason and the run's progress over a power cut.

Request rising = a new run (it waits while Permissive is FALSE; StopEdge
cancels it); Request falling while not Latched = the run ends (DEMAND_ENDED).
After a run ends a new one needs the request to drop and rise again.
A run without a target is valid and has no cap (decision 32). A volume part
always has a cap (decision 24): MaxTime, else RunVolume / MinFlow, else
defaultCap (warning "no time cap set" without MaxTime). Meter failed (Good
FALSE, or no total rise (TOTAL) / rate <= 0 (FLOW), for meterFailTime while
counting) ends the run whatever EndAtTarget says. Part and run time in
LINT ms, volumes LREAL; TOTAL = the rise of Meter.GetTotal().

Progress is kept (VAR RETAIN) on events and every progressSave. Power-up:
RESUME continues a run that was latched or whose request is back, from its
saved progress (at most one progressSave repeated; TOTAL counts the meter's
rise meanwhile); RESTART the same from zero; NONE ends it (POWER_CUT). A
meter that is not good yet on that first scan (a block that runs later in
the scan has no total yet) gives the base at its first good total. *)

FUNCTION_BLOCK UT_RUN_CORE
  VAR_INPUT
    Request : BOOL; (* run wanted *)
    StopEdge : BOOL; (* end the run now (operator) *)
    Latched : BOOL; (* the request is a latch: may resume without a held request *)
    Permissive : BOOL := TRUE; (* FALSE: a new run waits; a running run carries on *)
    Pause : BOOL; (* hold: no counting; ends after maxPause *)
    Counting : BOOL := TRUE; (* water flows / equipment runs *)
    Abort : BOOL; (* end the run with AbortCode; refuses a start *)
    AbortCode : UT_STOP; (* NONE = UT_STOP_ABORTED *)
    Part : BOOL; (* rising: a new part with the targets present now *)
    EndAtTarget : BOOL := TRUE; (* a part reaching its target or cap ends the run *)
    RunTime : TIME; (* this part's time target (0 = none) *)
    RunVolume : LREAL; (* this part's volume target (0 = none) *)
    MaxTime : TIME; (* this part's time cap (0 = worked out) *)
    MinFlow : REAL; (* expected minimum flow, in the meter's rate unit *)
    Finish : BOOL; (* rising: end the run as completed *)
    Meter : UT_I_METER; (* NULL: no volume targets *)
  END_VAR
  VAR_OUTPUT
    Active : BOOL;
    Waiting : BOOL; (* asked, held back by Permissive *)
    Paused : BOOL;
    Done : BOOL; (* one scan: the run ended *)
    TargetReached : BOOL; (* one scan: the part reached its target *)
    Capped : BOOL; (* one scan: a volume part reached its cap *)
    StopReason : UT_STOP;
    Elapsed : TIME; (* this part *)
    Delivered : LREAL;
    RunElapsed : TIME; (* the whole run *)
    RunDelivered : LREAL;
    TimeLeft : TIME;
    VolumeLeft : LREAL;
    TimeCap : TIME; (* the cap of this part (0 = none) *)
    Warning : BOOL; (* no time cap set, capped, meter failed *)
    CfgFault : BOOL;
    FaultId : UT_FAULT;
    Resumed : BOOL; (* one scan: a run came back after a power cut *)
  END_VAR
  VAR_IN_OUT
    Set : UT_RUN_SET;
  END_VAR
  VAR RETAIN
    prog : UT_RUN_PROGRESS;
  END_VAR
  VAR NON_RETAIN
    started : BOOL;
  END_VAR
  VAR
    tCur : TIME;
    tPrev : TIME;
    dMs : LINT;
    lastSave : TIME;
    saveNow : BOOL;
    reqPrev : BOOL;
    partPrev : BOOL;
    finPrev : BOOL;
    needDrop : BOOL;
    latchedRun : BOOL;
    partMs : LINT;
    runMs : LINT;
    partVol : LREAL;
    runVol : LREAL;
    rt : TIME;
    rv : LREAL;
    cap : TIME;
    noCapSet : BOOL;
    totalAtPart : LREAL;
    pausedMs : LINT;
    meterFail : BOOL;
    meterBadSince : TIME;
    lastRise : TIME;
    lastTotal : LREAL;
    baseWait : BOOL; (* power-up: the meter not worked out yet - the base waits for its first good total *)
    catchUp : BOOL; (* ... and then adds what it counted since the last save (RESUME) *)
    haveMeter : BOOL;
    mTotal : LREAL;
    mRate : REAL;
    mGood : BOOL;
    mUnit : UT_UNIT;
    mTotUnit : UT_UNIT;
    perS : LREAL;
    rateLs : LREAL; (* rate in litres / s (0 = unknown) *)
    volL : LREAL; (* litres per volume unit *)
    ok : BOOL;
    endWhy : UT_STOP;
    reached : BOOL;
    x : LREAL;
    pausePrev : BOOL;
  END_VAR


tCur := TIME();
Done := FALSE;
TargetReached := FALSE;
Capped := FALSE;
Resumed := FALSE;
saveNow := FALSE;
endWhy := UT_STOP_NONE;

(* the meter *)
haveMeter := Meter <> NULL;
IF haveMeter THEN
  mTotal := Meter.GetTotal();
  mRate := Meter.GetValue();
  mGood := Meter.GoodNow() AND Meter.IsFitted();
  mUnit := Meter.Unit();
  mTotUnit := Meter.TotalUnit();
ELSE
  mTotal := 0.0;
  mRate := 0.0;
  mGood := FALSE;
END_IF;
CASE Set.flowPer OF
UT_PER_SEC: perS := 1.0;
UT_PER_MIN: perS := 60.0;
UT_PER_DAY: perS := 86400.0;
ELSE
  perS := 3600.0;
END_CASE;
CASE mUnit OF
UT_UNIT_LPS: rateLs := REAL_TO_LREAL(mRate);
UT_UNIT_LPM: rateLs := REAL_TO_LREAL(mRate) / 60.0;
UT_UNIT_M3H: rateLs := REAL_TO_LREAL(mRate) * 1000.0 / 3600.0;
UT_UNIT_GPM: rateLs := REAL_TO_LREAL(mRate) * 3.785411784 / 60.0;
ELSE
  rateLs := REAL_TO_LREAL(mRate) / perS;   (* per flowPer, in the total's unit *)
  IF UT_UNIT_LITRES(U := mTotUnit) > 0.0 THEN
    rateLs := rateLs * UT_UNIT_LITRES(U := mTotUnit);
  END_IF;
END_CASE;
volL := UT_UNIT_LITRES(U := mTotUnit);
IF volL <= 0.0 THEN
  volL := UT_UNIT_LITRES(U := mUnit);
END_IF;
IF volL <= 0.0 THEN
  volL := 1.0;                   (* unknown units: the rate's volume is the total's *)
END_IF;
IF NOT (rateLs = rateLs) THEN
  rateLs := 0.0;
END_IF;

(* settings and targets *)
FaultId := UT_F_NONE;
IF NOT (Set.powerUp = UT_RPU_RESUME OR Set.powerUp = UT_RPU_RESTART OR Set.powerUp = UT_RPU_NONE) THEN
  FaultId := UT_F_POWERUP;
ELSIF NOT (Set.volFrom = UT_VF_FLOW OR Set.volFrom = UT_VF_TOTAL) THEN
  FaultId := UT_F_SETTING;
ELSIF NOT (Set.flowPer = UT_PER_SEC OR Set.flowPer = UT_PER_MIN OR Set.flowPer = UT_PER_HOUR OR Set.flowPer = UT_PER_DAY) THEN
  FaultId := UT_F_RATE_UNIT;
ELSIF Set.maxTime < T#0s OR Set.maxPause < T#0s OR Set.progressSave < T#0s OR MaxTime < T#0s THEN
  FaultId := UT_F_SETTING;
ELSIF RunTime < T#0s OR NOT (RunVolume >= 0.0 AND RunVolume <= 1.0E15) OR NOT (MinFlow >= 0.0) THEN
  FaultId := UT_F_SETTING;
ELSIF RunVolume > 0.0 AND (Set.defaultCap <= T#0s OR Set.meterFailTime <= T#0s) THEN
  FaultId := UT_F_SETTING;
ELSIF RunVolume > 0.0 AND NOT haveMeter THEN
  FaultId := UT_F_NO_METER;
END_IF;
CfgFault := FaultId <> UT_F_NONE;

(* time: whole ms, the rest carried *)
IF NOT started THEN
  tPrev := tCur;
  lastSave := tCur;
END_IF;
dMs := TIME_TO_LINT(tCur - tPrev);
IF dMs < 0 THEN
  dMs := 0;
  tPrev := tCur;
END_IF;
tPrev := tPrev + LINT_TO_TIME(dMs);

(* power-up: resume, restart or end the kept run *)
IF NOT started THEN
  started := TRUE;
  reqPrev := Request;
  partPrev := Part;
  finPrev := Finish;
  IF prog.active THEN
    IF Set.powerUp = UT_RPU_NONE OR NOT (prog.latched OR Request) OR CfgFault THEN
      prog.active := FALSE;
      StopReason := UT_STOP_POWER_CUT;
      needDrop := Request;
      saveNow := TRUE;
    ELSE
      Active := TRUE;
      latchedRun := prog.latched;
      rt := prog.runTime;
      rv := prog.runVolume;
      cap := prog.cap;
      IF Set.powerUp = UT_RPU_RESTART THEN
        partMs := 0;
        runMs := 0;
        partVol := 0.0;
        runVol := 0.0;
      ELSE
        partMs := prog.partMs;
        runMs := prog.runMs;
        partVol := prog.partVol;
        runVol := prog.runVol;
        IF Set.volFrom = UT_VF_TOTAL AND haveMeter AND mGood AND mTotal >= prog.totalAtSave THEN
          x := mTotal - prog.totalAtSave;   (* the meter kept counting *)
          partVol := partVol + x;
          runVol := runVol + x;
        END_IF;
      END_IF;
      totalAtPart := mTotal - partVol;
      lastTotal := mTotal;
      (* a meter that runs later in the scan (a later program) has no total yet on this first scan: 0, not good *)
      baseWait := haveMeter AND NOT mGood AND Set.volFrom = UT_VF_TOTAL;
      catchUp := baseWait AND Set.powerUp = UT_RPU_RESUME;
      lastRise := tCur;
      meterBadSince := tCur;
      Resumed := TRUE;
    END_IF;
  END_IF;
END_IF;

(* a new run *)
IF NOT Request THEN
  needDrop := FALSE;
END_IF;
IF NOT Active THEN
  IF Request AND NOT reqPrev AND NOT needDrop THEN
    Waiting := TRUE;
  END_IF;
  IF NOT Request OR StopEdge OR Abort OR CfgFault THEN
    Waiting := FALSE;
  END_IF;
  IF Waiting AND Permissive THEN
    Waiting := FALSE;
    Active := TRUE;
    latchedRun := Latched;
    partMs := 0;
    runMs := 0;
    partVol := 0.0;
    runVol := 0.0;
    pausedMs := 0;
    rt := RunTime;
    rv := RunVolume;
    totalAtPart := mTotal;
    lastTotal := mTotal;
    lastRise := tCur;
    meterBadSince := tCur;
    meterFail := FALSE;
    StopReason := UT_STOP_NONE;
    saveNow := TRUE;
  END_IF;
END_IF;
IF Active AND Latched THEN
  latchedRun := TRUE;
END_IF;

IF Active THEN
  (* a new part *)
  IF Part AND NOT partPrev THEN
    partMs := 0;
    partVol := 0.0;
    catchUp := FALSE;            (* a new part starts from zero *)
    rt := RunTime;
    rv := RunVolume;
    totalAtPart := mTotal;
    lastTotal := mTotal;
    lastRise := tCur;
    meterBadSince := tCur;
    saveNow := TRUE;
  END_IF;
  (* the cap of a volume part *)
  noCapSet := FALSE;
  IF rv > 0.0 AND rt <= T#0s THEN
    IF MaxTime > T#0s THEN
      cap := MaxTime;
    ELSE
      noCapSet := TRUE;
      IF MinFlow > 0.0 AND rateLs >= 0.0 THEN
        (* volume / minimum flow, both in litres *)
        x := MinFlow;
        IF mUnit = UT_UNIT_LPS THEN x := x;
        ELSIF mUnit = UT_UNIT_LPM THEN x := x / 60.0;
        ELSIF mUnit = UT_UNIT_M3H THEN x := x * 1000.0 / 3600.0;
        ELSIF mUnit = UT_UNIT_GPM THEN x := x * 3.785411784 / 60.0;
        ELSE x := x / perS * volL;
        END_IF;
        IF x > 0.0 THEN
          cap := LINT_TO_TIME(LREAL_TO_LINT(rv * volL / x * 1000.0));
        ELSE
          cap := Set.defaultCap;
        END_IF;
      ELSE
        cap := Set.defaultCap;
      END_IF;
    END_IF;
  ELSE
    cap := T#0s;
  END_IF;
  (* counting *)
  Paused := Pause OR NOT Counting;
  IF NOT Paused THEN
    partMs := partMs + dMs;
    runMs := runMs + dMs;
    pausedMs := 0;
  ELSIF Pause THEN
    pausedMs := pausedMs + dMs;
  END_IF;
  IF haveMeter AND mGood THEN
    IF baseWait THEN             (* the meter's first good total after a power-up: the base, never a rise *)
      IF catchUp AND mTotal >= prog.totalAtSave THEN
        x := mTotal - prog.totalAtSave;   (* the meter kept counting *)
        partVol := partVol + x;
        runVol := runVol + x;
      END_IF;
      baseWait := FALSE;
      catchUp := FALSE;
      totalAtPart := mTotal - partVol;
      lastTotal := mTotal;
    ELSIF Set.volFrom = UT_VF_TOTAL THEN
      IF mTotal > lastTotal THEN
        x := mTotal - lastTotal;
        partVol := partVol + x;
        runVol := runVol + x;
        lastRise := tCur;
      END_IF;
      lastTotal := mTotal;
    ELSIF NOT Paused AND rateLs > 0.0 THEN
      x := rateLs * LINT_TO_LREAL(dMs) / 1000.0 / volL;
      partVol := partVol + x;
      runVol := runVol + x;
    END_IF;
  END_IF;
  (* meter failed: a volume part counting *)
  IF rv > 0.0 AND NOT Paused AND (NOT mGood OR (Set.volFrom = UT_VF_TOTAL AND tCur - lastRise >= Set.meterFailTime)
                                  OR (Set.volFrom = UT_VF_FLOW AND NOT (mRate > 0.0))) THEN
    IF tCur - meterBadSince >= Set.meterFailTime THEN
      meterFail := TRUE;
      endWhy := UT_STOP_METER_FAILED;
    END_IF;
  ELSE
    meterBadSince := tCur;
  END_IF;
  IF rv > 0.0 AND Paused THEN
    lastRise := tCur;            (* no flow is expected while paused *)
  END_IF;
  (* target and cap *)
  reached := (rt > T#0s AND partMs >= TIME_TO_LINT(rt)) OR (rv > 0.0 AND partVol >= rv);
  IF reached THEN
    TargetReached := TRUE;
    IF EndAtTarget AND endWhy = UT_STOP_NONE THEN
      endWhy := UT_STOP_DONE;
    END_IF;
  ELSIF cap > T#0s AND partMs >= TIME_TO_LINT(cap) THEN
    Capped := TRUE;
    IF EndAtTarget AND endWhy = UT_STOP_NONE THEN
      endWhy := UT_STOP_TIME_CAP;
    END_IF;
  END_IF;
  (* the other ends, in order *)
  IF endWhy = UT_STOP_NONE THEN
    IF Abort THEN
      IF AbortCode = UT_STOP_NONE THEN endWhy := UT_STOP_ABORTED; ELSE endWhy := AbortCode; END_IF;
    ELSIF CfgFault THEN
      endWhy := UT_STOP_SETTING;
    ELSIF StopEdge THEN
      endWhy := UT_STOP_OPERATOR;
    ELSIF Finish AND NOT finPrev THEN
      endWhy := UT_STOP_DONE;
    ELSIF NOT Request AND NOT latchedRun THEN
      endWhy := UT_STOP_DEMAND_ENDED;
    ELSIF Set.maxPause > T#0s AND pausedMs >= TIME_TO_LINT(Set.maxPause) THEN
      endWhy := UT_STOP_PAUSED_LONG;
    END_IF;
  END_IF;
  IF endWhy <> UT_STOP_NONE THEN
    Active := FALSE;
    Done := TRUE;
    StopReason := endWhy;
    needDrop := Request;
    saveNow := TRUE;
  END_IF;
ELSE
  Paused := FALSE;
  noCapSet := FALSE;
END_IF;
reqPrev := Request;
partPrev := Part;
finPrev := Finish;

(* the progress kept over a power cut *)
IF tCur - lastSave >= Set.progressSave AND Set.progressSave > T#0s THEN
  saveNow := TRUE;
END_IF;
IF Paused <> pausePrev THEN
  saveNow := TRUE;               (* a pause change is an event *)
END_IF;
pausePrev := Paused;
IF saveNow THEN
  prog.active := Active;
  prog.latched := latchedRun;
  prog.partMs := partMs;
  prog.runMs := runMs;
  prog.partVol := partVol;
  prog.runVol := runVol;
  prog.runTime := rt;
  prog.runVolume := rv;
  prog.cap := cap;
  IF NOT baseWait THEN
    prog.totalAtSave := mTotal;  (* not a meter that has no total yet *)
  END_IF;
  lastSave := tCur;
END_IF;

(* outputs *)
Elapsed := LINT_TO_TIME(partMs);
RunElapsed := LINT_TO_TIME(runMs);
Delivered := partVol;
RunDelivered := runVol;
TimeCap := cap;
IF rv > 0.0 THEN
  VolumeLeft := MAX(0.0, rv - partVol);
ELSE
  VolumeLeft := 0.0;
END_IF;
TimeLeft := T#0s;
IF Active THEN
  IF rt > T#0s THEN
    TimeLeft := rt - Elapsed;
  ELSIF rv > 0.0 AND rateLs > 0.0 THEN
    TimeLeft := LINT_TO_TIME(LREAL_TO_LINT(VolumeLeft * volL / rateLs * 1000.0));
  ELSIF cap > T#0s THEN
    TimeLeft := cap - Elapsed;
  END_IF;
  IF TimeLeft < T#0s THEN
    TimeLeft := T#0s;
  END_IF;
END_IF;
IF Active THEN
  meterFail := FALSE;
END_IF;
IF endWhy = UT_STOP_METER_FAILED THEN
  meterFail := TRUE;
END_IF;
IF meterFail AND NOT Active THEN
  FaultId := UT_F_METER_FAILED;
ELSIF noCapSet AND Active AND NOT CfgFault THEN
  FaultId := UT_F_NO_TIME_CAP;
END_IF;
Warning := (noCapSet AND Active) OR meterFail OR StopReason = UT_STOP_TIME_CAP;

END_FUNCTION_BLOCK