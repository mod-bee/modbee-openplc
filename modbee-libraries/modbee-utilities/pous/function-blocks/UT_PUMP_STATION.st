(* UT_PUMP_STATION — the PROCESS for any number of pumps (decision 12): empty
(sump, wet well, pond), fill (tank, reservoir, pressure supply), transfer
(a run on request by time / volume), timed (on / off cycling); staging,
duty / standby / assist (UT_GROUP_RUN), floats and float backup, source
wait, no-flow stop, cleaning, a series booster. Each pump is a UT_PUMP in
the project's Pumps array (call the pumps first, then the station); the
station commands them through their Request. It owns the pumps
firstPump .. firstPump + pumpsUsed - 1 of the array (positions, 1 = the
first) and never calls another: two stations can share one array.

Level: the Level plug (a transmitter through UT_ANALOG_IN, a switch set
through UT_SWITCH_MEAS, or a UT_VESSEL: the rise of its Volume gives the
inflow estimate, in the vessel's volume unit per hour). Floats: the Floats plug (backup / control switches). With no
level value (no Level, or its transmitter not fitted on this site) the
floats are the control (H starts the lead, L stops, HH all, LL cut-out in
EMPTY; L starts, H stops in FILL).

EMPTY: stages 1..4 (start above, stop below; UT_STAGE_RUN), Demand / cmdPumpDown
to demandStop, cleaning; the high float is the overflow backup (runAll:
every pump; held floats.highHold), also with a config fault; both floats
made: high wins + "floats disagree". FILL: stages on below start, off above
stop; the high float stops (destination full); source wait; no-flow stop.
TRANSFER: Run / Start per set.run.style is the run request, UT_RUN_CORE
ends it by transfer.runTime / runVolume (Flow meter), a full destination
ends a latched / timed run and pauses a held one, the source low pauses it.
TIMED: the lead on / off (onTime / offTime). A bad level past levelBad.delay
-> levelFail FLOATS / STOP / RUN_ON (keep as it is for levelRunOn). The high
float made while the level reads below highLevelAlarm for floats.checkDelay
-> the transducer protection (float control). Run FALSE (system Off) and
Inhibit (never overridden, decision 54) call nothing, the overflow
included. Interlock FALSE holds every pump; Permissive FALSE: no new start.

Booster: a pump whose role is BOOSTER (one, not in the rotation) runs with
the duty pumps while BoostWanted (after booster.delay, or by BoostPress
below startSp until above stopSp); at a cycle end it stops first, the duty
pumps stopGap later; booster.required and not running -> booster.lost.
Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_PUMP_STATION
  VAR_INPUT
    Run : BOOL := TRUE; (* process on (EMPTY / FILL / TIMED); TRANSFER: the run request *)
    Start : BOOL R_EDGE; (* process on / a transfer run (latched) *)
    Stop : BOOL R_EDGE; (* off / run ended (wins) *)
    Reset : BOOL R_EDGE; (* clear latched faults, skipped pumps, cleanFailed *)
    Interlock : BOOL := TRUE; (* FALSE: every pump held *)
    Permissive : BOOL := TRUE; (* FALSE: no new pump start *)
    Inhibit : BOOL; (* everything stops and waits, no fault, never overridden *)
    Demand : BOOL; (* extra pumping: EMPTY down to demandStop, FILL up to it *)
    Clean : BOOL R_EDGE; (* clean now (EMPTY) *)
    Rotate : BOOL R_EDGE; (* move the lead on *)
    StartHold : BOOL; (* calls wait (stirrer pre-run); LevelCall stays TRUE *)
    BoostWanted : BOOL := TRUE; (* the booster may run with the duty pumps *)
    Speed : REAL := -1.0; (* speed % to every called VSD pump; < 0 = none *)
    Level : UT_I_MEAS; (* level / pressure; NULL = floats only *)
    Floats : UT_I_MEAS; (* backup / control switches *)
    Source : UT_I_MEAS; (* source level / supply pressure / low-source switch; NULL = no source wait *)
    Flow : UT_I_METER; (* station meter: TRANSFER volume, no-flow stop, outflow *)
    BoostPress : UT_I_MEAS; (* pressure that starts the booster (startBy PRESSURE) *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL; (* any pump running *)
    LevelCall : BOOL; (* the process asks for pumping (-> stirrer PumpCall) *)
    AtStop : BOOL; (* level at its stop point (-> zone LevelEnd) *)
    Waiting : BOOL; (* a run waits on its source (-> a run's Pause) *)
    HighLevel : BOOL;
    Shortfall : BOOL;
    TransducerFault : BOOL;
    ConfigFault : BOOL;
    Fault : BOOL;
    Warning : BOOL;
    RunningCount : INT;
    Lead : INT;
    Inflow : REAL; (* inflow estimate per hour, in the vessel's volume unit (needs a vessel on Level) *)
  END_VAR
  VAR_IN_OUT
    Pumps : ARRAY [*] OF UT_PUMP;
    Data : UT_STATION_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_STATION_SET;
    keptGood : BOOL;
    keptTot : UT_STATION_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    grp : UT_GROUP_RUN;
    masks : UT_GROUP_MASKS;
    stages : UT_STAGE_RUN;
    runIn : UT_RUN_INPUT;
    core : UT_RUN_CORE;
    lvlRate : UT_RATE;
    rateData : UT_RATE_DATA := (set := (unit := UT_PER_HOUR, window := T#2m));
    flasher : UT_FLASHER;
    stTrans : UT_PROT_ST;
    stLvl : UT_PROT_ST;
    stSrc : UT_PROT_ST;
    stBoost : UT_PROT_ST;
    vess : UT_I_VESSEL;
    ok : BOOL;
    cfgId : UT_FAULT;
    tCur : TIME;
    started : BOOL;
    x : BOOL;
    i : DINT;
    lo : DINT;
    hi : DINT;
    n : DINT;
    nArr : DINT;
    k : INT;
    bit : DWORD;
    boostIdx : DINT; (* the booster pump (lo - 1 = none) *)
    nDuty : INT;
    cfgOn : BOOL;
    empty : BOOL;
    fill : BOOL;
    transfer : BOOL;
    timed : BOOL;
    procOn : BOOL; (* Run per its style (EMPTY / FILL / TIMED) *)
    hReset : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    hRot : BOOL;
    hClean : BOOL;
    hPd : BOOL;
    hStats : BOOL;
    hEx : BOOL;
    resetReq : BOOL;
    rotReq : BOOL;
    cleanReq : BOOL;
    pdReq : BOOL;
    lvl : REAL;
    lvlGood : BOOL;
    lvlHasV : BOOL;
    lvlFit : BOOL;
    bHH : BOOL;
    bH : BOOL;
    bL : BOOL;
    bLL : BOOL;
    fHH : BOOL; (* floats (from the Floats plug, or the level's own bands) *)
    fH : BOOL;
    fL : BOOL;
    fLL : BOOL;
    fHasHigh : BOOL;
    fHasLow : BOOL;
    floatsOnly : BOOL;
    trust : BOOL;
    fc : BOOL; (* float / timer control (a fallback) *)
    suspect : BOOL;
    chkOn : BOOL;
    chkAt : TIME;
    runOnActive : BOOL;
    runOnAt : TIME;
    runOnNeed : INT;
    hfOn : BOOL;
    hfAt : TIME;
    hfPrev : BOOL;
    fitF : BOOL;
    ovf : BOOL; (* the overflow float: H as backup, HH under float control *)
    lvlLast : REAL;
    tPrev : TIME;
    gapOn : BOOL;
    gapAt : TIME;
    abortCode : UT_STOP;
    tPause : BOOL; (* the transfer run is paused by the station *)
    modePrev : UT_STATION_MODE;
    locked : BOOL;
    lockAt : TIME;
    fcRun : BOOL;
    fcAt : TIME;
    floatLatch : BOOL;
    offset : REAL;
    rng : UDINT;
    need : INT;
    levelNeed : INT;
    reachedD : BOOL;
    recoveredD : BOOL;
    dStop : REAL;
    dRestart : REAL;
    demRun : BOOL;
    demDone : BOOL;
    pdRun : BOOL;
    demPrev : BOOL;
    cleaning : BOOL;
    cleanReached : BOOL;
    cleanStart : TIME;
    cleanAt : TIME;
    cleanFail : BOOL;
    srcV : REAL;
    srcGood : BOOL;
    srcLow : BOOL;
    srcBelow : BOOL;
    srcSince : TIME;
    srcAbove : BOOL;
    srcAboveSince : TIME;
    srcHasV : BOOL;
    srcFit : BOOL;
    sHH : BOOL;
    sH : BOOL;
    sL : BOOL;
    sLL : BOOL;
    flowRate : REAL;
    vesVol : REAL;
    flowGood : BOOL;
    noFlowStop : BOOL;
    lowFlowAt : TIME;
    runAllAt : TIME;
    full : BOOL;
    tRunReq : BOOL;
    boostRun : BOOL;
    boostAt : TIME;
    boostPressLow : BOOL;
    dutyRunning : BOOL;
    needPrev : INT;
    active : BOOL;
    activePrev : BOOL;
    phaseAt : TIME;
    cycL0 : REAL;
    reqSpeed : REAL;
    zero : REAL;
    nan : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    faultMask : DWORD;
    faultPrev : DWORD;
  END_VAR


tCur := TIME();
nArr := UPPER_BOUND(Pumps, 1) - LOWER_BOUND(Pumps, 1) + 1;
keep(TotalsNow := (Data.cmdResetStats AND NOT hStats));
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := UT_STATION_CHECK(S := Data.set, Units := nArr, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_STATION_CHECK(S := Data.set, Units := nArr, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
IF NOT started THEN
  started := TRUE;
  nan := zero / zero;
  phaseAt := tCur;
  tPrev := tCur;
  rng := DWORD_TO_UDINT(DWORD#16#2545F491 XOR UDINT_TO_DWORD(LINT_TO_UDINT(TIME_TO_LINT(tCur))));
END_IF;

(* commands: once per request *)
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
rotReq := Rotate OR (Data.cmdRotate AND NOT hRot);
hRot := Data.cmdRotate;
Data.cmdRotate := FALSE;
cleanReq := Clean OR (Data.cmdClean AND NOT hClean);
hClean := Data.cmdClean;
Data.cmdClean := FALSE;
pdReq := Data.cmdPumpDown AND NOT hPd;
hPd := Data.cmdPumpDown;
Data.cmdPumpDown := FALSE;
IF Data.cmdResetStats AND NOT hStats THEN
  Data.tot.cycles := 0;
  Data.tot.highFloatEvents := 0;
  Data.tot.highFloatTime := T#0s;
END_IF;
hStats := Data.cmdResetStats;
Data.cmdResetStats := FALSE;
IF resetReq THEN
  cleanFail := FALSE;
END_IF;

(* the pumps: duty members and the booster *)
lo := LOWER_BOUND(Pumps, 1);
hi := UPPER_BOUND(Pumps, 1);
IF Data.set.firstPump >= 1 AND INT_TO_DINT(Data.set.firstPump) <= nArr THEN
  lo := lo + INT_TO_DINT(Data.set.firstPump) - 1;
ELSE
  hi := lo - 1;                  (* a bad first pump (config fault): the station owns no pump *)
END_IF;
IF Data.set.pumpsUsed > 0 AND lo + INT_TO_DINT(Data.set.pumpsUsed) - 1 < hi THEN
  hi := lo + INT_TO_DINT(Data.set.pumpsUsed) - 1;
END_IF;
n := hi - lo + 1;
boostIdx := lo - 1;
FOR i := lo TO hi DO
  IF boostIdx < lo AND Pumps[i].Role() = UT_ROLE_BOOSTER THEN
    boostIdx := i;
  END_IF;
END_FOR;
masks.fitted := 0;
masks.available := 0;
masks.waiting := 0;
masks.running := 0;
masks.inHand := 0;
masks.startsHeld := 0;
masks.exercising := 0;
masks.preferLead := 0;
k := 0;
dutyRunning := FALSE;
FOR i := lo TO hi DO
  IF i <> boostIdx AND k < 32 THEN
    bit := SHL(DWORD#1, k);
    IF Pumps[i].IsFitted() THEN masks.fitted := masks.fitted OR bit; END_IF;
    IF Pumps[i].IsAvailable() THEN masks.available := masks.available OR bit; END_IF;
    IF Pumps[i].IsWaiting() THEN masks.waiting := masks.waiting OR bit; END_IF;
    IF Pumps[i].IsRunning() THEN
      masks.running := masks.running OR bit;
      dutyRunning := TRUE;
    END_IF;
    IF Pumps[i].IsHand() THEN masks.inHand := masks.inHand OR bit; END_IF;
    IF Pumps[i].StartsHeld() AND NOT hfOn THEN   (* the overflow runs a pump past its starts limit *)
      masks.startsHeld := masks.startsHeld OR bit;
    END_IF;
    IF Pumps[i].IsExercising() THEN masks.exercising := masks.exercising OR bit; END_IF;
    masks.hours[k] := LREAL_TO_REAL(Pumps[i].RunHours());
    k := k + 1;
  END_IF;
END_FOR;
nDuty := k;
masks.count := nDuty;
cfgOn := NOT ok OR n < 1 OR n - BOOL_TO_DINT(boostIdx >= lo) > 32;
IF n < 1 AND ok THEN
  cfgId := UT_F_NO_UNITS;
ELSIF n - BOOL_TO_DINT(boostIdx >= lo) > 32 THEN
  cfgId := UT_F_GROUP_SIZE;
END_IF;

empty := Data.set.stationMode = UT_SM_EMPTY;
fill := Data.set.stationMode = UT_SM_FILL;
transfer := Data.set.stationMode = UT_SM_TRANSFER;
timed := Data.set.stationMode = UT_SM_TIMED;

(* the level and the floats *)
x := UT_MEAS_READ(Sensor := Level, In := nan, InGood := FALSE, V => lvl, G => lvlGood, HasValue => lvlHasV,
                  Fitted => lvlFit, BandHH => bHH, BandH => bH, BandL => bL, BandLL => bLL);
IF Level = NULL OR NOT lvlFit THEN
  lvlHasV := FALSE;              (* no level, or its input not fitted on this site (decisions 76 / 77): floats only *)
  lvlFit := FALSE;
END_IF;
fitF := FALSE;
IF Floats <> NULL THEN
  fitF := Floats.IsFitted();
END_IF;
IF fitF THEN
  fHH := Floats.IsHiHiNow();
  fH := Floats.IsHiNow();
  fL := Floats.IsLoNow();
  fLL := Floats.IsLoLoNow();
  fHasHigh := Floats.HasBand(Band := UT_LVL_HI) OR Floats.HasBand(Band := UT_LVL_HIHI);
  fHasLow := Floats.HasBand(Band := UT_LVL_LO) OR Floats.HasBand(Band := UT_LVL_LOLO);
ELSIF lvlFit AND NOT lvlHasV THEN
  fHH := bHH;                    (* a switch set on Level: its bands are the floats *)
  fH := bH OR bHH;
  fL := bL OR bLL;
  fLL := bLL;
  fHasHigh := Level.HasBand(Band := UT_LVL_HI) OR Level.HasBand(Band := UT_LVL_HIHI);
  fHasLow := Level.HasBand(Band := UT_LVL_LO) OR Level.HasBand(Band := UT_LVL_LOLO);
ELSE
  fHH := FALSE;
  fH := FALSE;
  fL := FALSE;
  fLL := FALSE;
  fHasHigh := FALSE;
  fHasLow := FALSE;
END_IF;
floatsOnly := NOT lvlHasV AND (fHasHigh OR fHasLow);
Data.sts.floatsDisagree := fH AND fL;
IF Data.sts.floatsDisagree THEN
  fL := FALSE;                   (* high wins (decision 8) *)
  fLL := FALSE;
END_IF;
IF Level <> NULL THEN
  Data.sts.statusUnit := Level.Unit();
END_IF;
vess ?= Level;                   (* a vessel gives the water surface (IEC 6.6.6.7) *)

(* a bad level: ride-through, then the levelFail rule *)
x := UT_PROT_RUN(TNow := tCur, Cause := lvlHasV AND NOT lvlGood, ResetReq := resetReq,
                 RetryWindow := T#1h, Prot := Data.set.levelBad, Sts := Data.sts.levelBad, St := stLvl);
Data.sts.levelBadNow := Data.sts.levelBad.active;
(* the transducer check (EMPTY): the high float made while the level reads below highLevelAlarm *)
IF empty AND lvlHasV AND lvlGood AND fH AND lvl < Data.set.highLevelAlarm THEN
  IF NOT chkOn THEN
    chkOn := TRUE;
    chkAt := tCur;
  END_IF;
  IF tCur - chkAt >= Data.set.floats.checkDelay THEN
    suspect := TRUE;
  END_IF;
ELSE
  chkOn := FALSE;
END_IF;
IF NOT empty OR NOT lvlHasV OR (lvlGood AND lvl >= Data.set.highLevelAlarm) OR (resetReq AND NOT chkOn) THEN
  suspect := FALSE;
END_IF;
x := UT_PROT_RUN(TNow := tCur, Cause := suspect, ResetReq := resetReq, RetryWindow := T#1h,
                 Prot := Data.set.transducer, Sts := Data.sts.transducer, St := stTrans);
TransducerFault := stTrans.trip;
trust := lvlHasV AND (lvlGood OR NOT Data.sts.levelBad.active) AND NOT stTrans.trip AND NOT cfgOn;
IF lvlGood THEN
  lvlLast := lvl;
ELSE
  lvl := lvlLast;                (* riding through: hold the last good value (never used past the delay) *)
END_IF;
fc := lvlHasV AND Data.sts.levelBad.active AND Data.set.levelFail = UT_LF_FLOATS AND (fHasHigh OR fHasLow);
fc := fc OR stTrans.trip;

(* the process request *)
runIn(Run := Run, Start := Start, Stop := Stop OR core.Done, CmdStart := Data.cmdStart AND NOT hStart,
      CmdStop := Data.cmdStop AND NOT hStop, Drop := cfgOn OR Data.set.stationMode <> modePrev, Linked := FALSE,
      TargetDone := core.Done, HasTarget := transfer AND (Data.set.transfer.runTime > T#0s OR Data.set.transfer.runVolume > 0.0),
      Set := Data.set.run);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
modePrev := Data.set.stationMode;   (* a mode change starts the request afresh *)
procOn := runIn.Request AND NOT runIn.BadSetting;

(* the source *)
srcV := 0.0;
srcGood := TRUE;
srcHasV := FALSE;
srcFit := FALSE;
sHH := FALSE; sH := FALSE; sL := FALSE; sLL := FALSE;
IF Source <> NULL THEN
  x := UT_MEAS_READ(Sensor := Source, In := nan, InGood := TRUE, V => srcV, G => srcGood, HasValue => srcHasV,
                    Fitted => srcFit, BandHH => sHH, BandH => sH, BandL => sL, BandLL => sLL);
END_IF;
x := UT_PROT_RUN(TNow := tCur, Cause := Source <> NULL AND srcFit AND NOT srcGood, ResetReq := resetReq,
                 RetryWindow := T#1h, Prot := Data.set.source.bad, Sts := Data.sts.sourceBad, St := stSrc);
srcBelow := Source <> NULL AND srcFit AND ((srcHasV AND srcGood AND srcV <= Data.set.source.stop) OR sL OR sLL
                                           OR stSrc.trip);
srcAbove := Source = NULL OR NOT srcFit OR ((NOT srcHasV OR (srcGood AND srcV > Data.set.source.restart))
                                            AND NOT (sL OR sLL) AND NOT stSrc.trip);
IF NOT srcBelow THEN
  srcSince := tCur;
END_IF;
IF NOT srcAbove THEN
  srcAboveSince := tCur;
END_IF;
IF NOT empty AND srcBelow AND tCur - srcSince >= Data.set.source.stopDelay THEN
  IF NOT srcLow THEN
    Data.sts.stopReason := UT_STOP_SOURCE_LOW;
  END_IF;
  srcLow := TRUE;
ELSIF srcAbove AND tCur - srcAboveSince >= Data.set.source.restartDelay THEN
  srcLow := FALSE;
END_IF;
IF empty OR Source = NULL THEN
  srcLow := FALSE;
END_IF;
Waiting := srcLow;

(* the flow meter: outflow and the no-flow stop *)
flowRate := 0.0;
flowGood := FALSE;
IF Flow <> NULL THEN
  flowRate := Flow.GetValue();
  flowGood := Flow.GoodNow();
END_IF;
IF NOT flowGood THEN
  flowRate := 0.0;
END_IF;

(* EMPTY / FILL: the stages *)
Data.sts.startPointNow := Data.set.stage[1].start + offset;
stages(Level := lvl, Empty := empty, Run := (empty OR fill) AND trust AND procOn AND NOT Inhibit
                                           AND NOT (empty AND fLL) AND NOT cfgOn,
       Members := nDuty, Start1 := Data.sts.startPointNow, Stages := Data.set.stage);
levelNeed := stages.Need;
IF stages.StageBad AND (empty OR fill) AND NOT cfgOn THEN
  cfgOn := TRUE;
  cfgId := UT_F_POINTS;
END_IF;
need := levelNeed;
LevelCall := stages.LevelCall;
AtStop := stages.AtStop AND trust;

(* floats as the control: no level value, or the level has failed (FLOATS) *)
IF (floatsOnly OR fc) AND (empty OR fill) AND procOn AND NOT Inhibit THEN
  IF empty THEN
    IF fH AND NOT locked THEN
      floatLatch := TRUE;
      fcAt := tCur;
    ELSIF fL OR (floatLatch AND (fc OR NOT fHasLow) AND Data.set.floats.runTime > T#0s
                 AND tCur - fcAt >= Data.set.floats.runTime AND NOT fH) THEN
      IF floatLatch AND (fc OR NOT fHasLow) THEN
        locked := TRUE;
        lockAt := tCur;
      END_IF;
      floatLatch := FALSE;
    END_IF;
  ELSE
    IF fH THEN
      floatLatch := FALSE;       (* full *)
    ELSIF fL OR (NOT fHasLow AND NOT locked) THEN
      IF NOT floatLatch THEN fcAt := tCur; END_IF;
      floatLatch := TRUE;
    END_IF;
    IF floatLatch AND fc AND Data.set.floats.runTime > T#0s AND tCur - fcAt >= Data.set.floats.runTime THEN
      floatLatch := FALSE;
      locked := TRUE;
      lockAt := tCur;
    END_IF;
  END_IF;
  IF locked AND tCur - lockAt >= Data.set.floats.lockout THEN
    locked := FALSE;
  END_IF;
  IF floatLatch AND need < 1 THEN
    need := 1;
    LevelCall := TRUE;
  END_IF;
ELSE
  floatLatch := FALSE;
  locked := FALSE;
END_IF;
Data.sts.floatControl := (floatsOnly OR fc) AND (empty OR fill);

(* a failed level: STOP / RUN_ON *)
IF lvlHasV AND Data.sts.levelBad.active AND NOT fc THEN
  IF Data.set.levelFail = UT_LF_RUN_ON THEN
    IF NOT runOnActive THEN
      runOnActive := TRUE;
      runOnAt := tCur;
      runOnNeed := needPrev;
    END_IF;
    IF tCur - runOnAt < Data.set.levelRunOn THEN
      need := runOnNeed;
    ELSE
      need := 0;
    END_IF;
  ELSE
    need := 0;
  END_IF;
ELSE
  runOnActive := FALSE;
END_IF;
Data.sts.runOn := runOnActive AND tCur - runOnAt < Data.set.levelRunOn;

(* Demand / cmdPumpDown (EMPTY / FILL, a trusted level) *)
dStop := Data.set.demandStop;
IF dStop = 0.0 THEN
  dStop := Data.set.stage[1].stop;
END_IF;
dRestart := Data.set.demandRestart;
IF dRestart = 0.0 THEN
  dRestart := Data.sts.startPointNow;
END_IF;
IF empty THEN
  reachedD := lvl <= dStop;
  recoveredD := lvl >= dRestart;
ELSE
  reachedD := lvl >= dStop;
  recoveredD := lvl <= dRestart;
END_IF;
IF NOT trust OR NOT (empty OR fill) OR NOT procOn OR Inhibit OR (empty AND fLL) OR cfgOn THEN
  pdRun := FALSE;
  demRun := FALSE;
ELSE
  IF pdReq AND NOT reachedD THEN
    pdRun := TRUE;
  END_IF;
  IF Demand AND NOT demRun AND NOT reachedD AND (NOT demPrev OR recoveredD) THEN
    demRun := TRUE;              (* a new Demand, or a held one rerunning at demandRestart *)
  END_IF;
  IF NOT Demand THEN
    demRun := FALSE;
  END_IF;
  IF reachedD THEN
    pdRun := FALSE;
    demRun := FALSE;
  END_IF;
END_IF;
demDone := Demand AND NOT demRun;
demPrev := Demand;
Data.sts.demand := pdRun OR demRun;
IF Data.sts.demand AND need < Data.set.demandPumps THEN
  need := MIN(Data.set.demandPumps, nDuty);
END_IF;

(* the high float *)
IF fH AND NOT hfPrev THEN
  Data.tot.highFloatEvents := Data.tot.highFloatEvents + 1;
END_IF;
IF fH THEN
  Data.tot.highFloatTime := Data.tot.highFloatTime + (tCur - tPrev);
END_IF;
hfPrev := fH;
tPrev := tCur;
IF floatsOnly OR fc THEN
  ovf := fHH;
ELSE
  ovf := fH;
END_IF;
IF empty THEN
  IF ovf THEN
    hfOn := TRUE;
    hfAt := tCur;
  ELSIF hfOn AND tCur - hfAt >= Data.set.floats.highHold THEN
    hfOn := FALSE;
  END_IF;
  IF hfOn AND procOn AND NOT Inhibit THEN   (* the overflow backup, also with a config fault *)
    IF Data.set.floats.runAll OR fHH THEN
      need := nDuty;
    ELSIF need < 1 THEN
      need := 1;
    END_IF;
    LevelCall := TRUE;
  END_IF;
ELSE
  hfOn := FALSE;
END_IF;
IF fill AND fH THEN
  need := 0;                     (* destination full *)
  AtStop := TRUE;
END_IF;
HighLevel := fH OR (lvlHasV AND lvlGood AND lvl >= Data.set.highLevelAlarm);

(* cleaning (EMPTY): pump down to cleanLevel, then run on cleanTime *)
IF cleanReq AND empty AND trust AND procOn AND NOT Inhibit AND NOT fLL AND NOT cfgOn THEN
  cleaning := TRUE;
  cleanReached := FALSE;
  cleanStart := tCur;
END_IF;
IF cleaning THEN
  IF NOT empty OR NOT trust OR NOT procOn OR Inhibit OR fLL THEN
    cleaning := FALSE;
  ELSIF Data.set.maxCleanTime > T#0s AND tCur - cleanStart >= Data.set.maxCleanTime THEN
    cleaning := FALSE;
    cleanFail := TRUE;
    Data.sts.stopReason := UT_STOP_CLEAN_TIMEOUT;
  ELSIF lvl <= Data.set.cleanLevel OR cleanReached THEN
    IF NOT cleanReached THEN
      cleanReached := TRUE;
      cleanAt := tCur;
    END_IF;
    IF tCur - cleanAt >= Data.set.cleanTime THEN
      cleaning := FALSE;
      cleanFail := FALSE;
    END_IF;
  END_IF;
  IF cleaning AND need < 1 THEN
    need := 1;
  END_IF;
END_IF;

(* FILL: no-flow stop, restart by the start point *)
IF fill AND Data.set.noFlow.enable AND dutyRunning AND flowGood THEN
  IF flowRate >= Data.set.noFlow.sp OR tCur - runAllAt < Data.set.noFlow.minRun THEN
    lowFlowAt := tCur;
  END_IF;
  IF tCur - lowFlowAt >= Data.set.noFlow.delay THEN
    IF NOT noFlowStop THEN
      Data.sts.stopReason := UT_STOP_NO_FLOW;
    END_IF;
    noFlowStop := TRUE;
  END_IF;
ELSE
  lowFlowAt := tCur;
END_IF;
IF NOT dutyRunning THEN
  runAllAt := tCur;
END_IF;
IF noFlowStop AND (NOT fill OR (trust AND lvl <= Data.sts.startPointNow) OR (floatsOnly AND fL)) THEN
  noFlowStop := FALSE;           (* the start point reached again *)
END_IF;
IF noFlowStop THEN
  need := 0;
END_IF;

(* TRANSFER: a run by time / volume *)
(* the destination (Level, as FILL): full at stage 1 stop, clear again at stage 1 start *)
IF NOT transfer OR NOT Data.set.transfer.stopAtFull THEN
  full := FALSE;
ELSIF fH OR (trust AND lvl >= Data.set.stage[1].stop) THEN
  full := TRUE;
ELSIF NOT trust OR lvl <= Data.set.stage[1].start THEN
  full := FALSE;
END_IF;
IF full AND runIn.Latched THEN
  abortCode := UT_STOP_FULL;
ELSE
  abortCode := UT_STOP_SETTING;
END_IF;
tPause := srcLow OR Inhibit OR NOT Interlock OR (full AND NOT runIn.Latched);
core(Request := transfer AND procOn, StopEdge := runIn.StopEdge, Latched := runIn.Latched,
     Permissive := Permissive, Pause := tPause,
     Counting := dutyRunning, Abort := cfgOn OR (full AND runIn.Latched), AbortCode := abortCode,
     Part := FALSE, EndAtTarget := TRUE, RunTime := Data.set.transfer.runTime, RunVolume := Data.set.transfer.runVolume,
     MaxTime := Data.set.transfer.core.maxTime, MinFlow := Data.set.transfer.minFlow, Finish := FALSE, Meter := Flow,
     Set := Data.set.transfer.core);
IF transfer THEN
  IF core.Active AND NOT tPause AND NOT core.Waiting THEN
    need := MIN(Data.set.transfer.pumps, nDuty);
  ELSE
    need := 0;
  END_IF;
  LevelCall := core.Active;
  AtStop := full;
  IF core.Done THEN
    Data.sts.stopReason := core.StopReason;
  END_IF;
END_IF;

(* TIMED: the lead on / off *)
flasher(Enable := timed AND procOn AND NOT Inhibit AND NOT cfgOn, OnTime := Data.set.onTime, OffTime := Data.set.offTime);
IF timed THEN
  IF flasher.Q THEN need := 1; ELSE need := 0; END_IF;
  LevelCall := flasher.Q;
END_IF;

(* what stops everything *)
IF NOT procOn AND NOT (transfer AND core.Active) THEN
  need := 0;
  cleaning := FALSE;
END_IF;
IF Inhibit OR srcLow OR (empty AND fLL AND NOT hfOn) OR (cfgOn AND NOT (empty AND hfOn AND procOn)) THEN
  need := 0;
END_IF;
IF NOT Permissive AND need > needPrev THEN
  need := MAX(needPrev, 0);      (* no new start *)
END_IF;
IF StartHold AND NOT dutyRunning THEN
  need := 0;                     (* the calls wait; LevelCall stays *)
END_IF;
IF need > nDuty THEN
  need := nDuty;
END_IF;
IF need < 0 THEN
  need := 0;
END_IF;

(* the booster leaves first at a cycle end: the duty pumps stopGap later *)
IF need = 0 AND needPrev > 0 AND boostRun AND NOT gapOn AND NOT Inhibit AND Interlock THEN
  gapOn := TRUE;
  gapAt := tCur;
END_IF;
IF gapOn THEN
  IF need = 0 AND tCur - gapAt < Data.set.booster.stopGap THEN
    need := needPrev;
  ELSE
    gapOn := FALSE;
  END_IF;
END_IF;

(* cycles *)
active := need > 0;
IF active <> activePrev THEN
  phaseAt := tCur;
END_IF;
IF active AND NOT activePrev THEN
  Data.tot.cycles := Data.tot.cycles + 1;
  cycL0 := lvl;
  IF Data.set.cleanEvery > 0 AND empty AND trust AND NOT cleaning AND NOT Inhibit THEN
    IF Data.tot.cycles MOD INT_TO_UDINT(Data.set.cleanEvery) = 0 THEN
      cleaning := TRUE;
      cleanReached := FALSE;
      cleanStart := tCur;
    END_IF;
  END_IF;
ELSIF activePrev AND NOT active THEN
  IF NOT procOn THEN
    Data.sts.stopReason := UT_STOP_SWITCHED_OFF;
  ELSIF Inhibit THEN
    Data.sts.stopReason := UT_STOP_INHIBITED;
  ELSIF cfgOn THEN
    Data.sts.stopReason := UT_STOP_SETTING;
  ELSIF fill AND fH THEN
    Data.sts.stopReason := UT_STOP_FULL;
  ELSIF empty AND fLL THEN
    Data.sts.stopReason := UT_STOP_LOW_LEVEL;
  ELSIF srcLow THEN
    Data.sts.stopReason := UT_STOP_SOURCE_LOW;
  ELSIF noFlowStop THEN
    Data.sts.stopReason := UT_STOP_NO_FLOW;
  ELSIF transfer THEN
    Data.sts.stopReason := core.StopReason;
  ELSE
    Data.sts.stopReason := UT_STOP_DEMAND_ENDED;
  END_IF;
  Data.sts.cycleVolume := cycL0 - lvl;
  rng := rng * 1103515245 + 12345;
  IF Data.set.levelVariation > 0.0 AND Data.set.levelVariation < ABS(Data.set.stage[1].start - Data.set.stage[1].stop) THEN
    offset := (UDINT_TO_REAL((rng / 65536) MOD 32768) / 16383.5 - 1.0) * Data.set.levelVariation;
  ELSE
    offset := 0.0;
  END_IF;
END_IF;
activePrev := active;
needPrev := need;

(* the group engine: which duty pumps run *)
grp(Enable := (NOT cfgOn OR hfOn) AND NOT Inhibit, Required := need, Rotate := rotReq, Reset := resetReq, Set := Data.set.group, Members := masks);
IF grp.CfgFault AND NOT cfgOn THEN
  cfgOn := TRUE;
  cfgId := grp.FaultId;
END_IF;

(* the booster *)
IF boostIdx >= lo THEN
  boostPressLow := FALSE;
  IF BoostPress <> NULL THEN
    IF BoostPress.GoodNow() AND BoostPress.GetValue() < Data.set.booster.startSp THEN
      boostPressLow := TRUE;
    END_IF;
  END_IF;
  IF NOT (BoostWanted AND dutyRunning AND need > 0) OR gapOn THEN
    boostRun := FALSE;
    boostAt := tCur;
  ELSIF Data.set.booster.startBy = UT_BS_DELAY THEN
    IF tCur - boostAt >= Data.set.booster.delay THEN boostRun := TRUE; END_IF;
  ELSE
    IF NOT boostPressLow THEN boostAt := tCur; END_IF;
    IF boostPressLow AND tCur - boostAt >= Data.set.booster.delay THEN
      boostRun := TRUE;
    ELSIF BoostPress <> NULL THEN
      IF BoostPress.GoodNow() AND BoostPress.GetValue() > Data.set.booster.stopSp THEN boostRun := FALSE; END_IF;
    END_IF;
  END_IF;
  x := UT_PROT_RUN(TNow := tCur, Cause := Data.set.booster.required AND boostRun AND NOT Pumps[boostIdx].IsRunning(),
                   ResetReq := resetReq, RetryWindow := T#1h, Prot := Data.set.booster.lost, Sts := Data.sts.boosterLost,
                   St := stBoost);
ELSE
  boostRun := FALSE;
END_IF;
Data.sts.boosterOn := boostRun;

(* the requests to the pumps *)
IF Speed >= 0.0 THEN reqSpeed := Speed; ELSE reqSpeed := nan; END_IF;
k := 0;
RunningCount := 0;
FOR i := lo TO hi DO
  IF i = boostIdx THEN
    x := Pumps[i].Request(ReqRun := boostRun AND NOT stBoost.trip, Hold := NOT Interlock, ReqSpeed := reqSpeed,
                          Owner := Data.set.tag);
  ELSIF k < 32 THEN
    bit := SHL(DWORD#1, k);
    x := Pumps[i].Request(ReqRun := (masks.call AND bit) <> 0 AND NOT (stBoost.trip AND BoostWanted),
                          Hold := NOT Interlock, ReqSpeed := reqSpeed, Owner := Data.set.tag, Urgent := hfOn);
    k := k + 1;
  END_IF;
  IF Pumps[i].IsRunning() THEN
    RunningCount := RunningCount + 1;
  END_IF;
END_FOR;
Running := RunningCount > 0;
Lead := grp.Lead;
Shortfall := grp.Shortfall AND NOT grp.AllHeld;

(* inflow: the vessel's volume rise per hour (its volume unit), plus the outflow. The volume, never the level
   times the water surface: the level is in the vessel's levelUnit (mm, cm or %, not m: x1000 off in mm), and a
   shaped tank's surface changes with the level. *)
IF vess <> NULL THEN
  vesVol := vess.GetVolume();
ELSE
  vesVol := 0.0;
END_IF;
lvlRate(In := vesVol, InGood := vess <> NULL AND lvlHasV AND lvlGood, Reset := FALSE, Data := rateData);
IF vess <> NULL AND lvlRate.Good THEN
  Inflow := lvlRate.Rate + flowRate;
ELSE
  Inflow := 0.0;
END_IF;

(* fault bits, status *)
ConfigFault := cfgOn;
faultMask := 0;
IF cfgOn THEN faultMask := faultMask OR 16#1; END_IF;
IF stTrans.trip OR stTrans.warn THEN faultMask := faultMask OR 16#2; END_IF;
IF Data.sts.levelBad.tripped THEN faultMask := faultMask OR 16#4; END_IF;
IF grp.NoneAvailable AND need > 0 THEN faultMask := faultMask OR 16#8; END_IF;
IF Data.sts.floatsDisagree THEN faultMask := faultMask OR 16#10; END_IF;
IF stSrc.trip OR stSrc.warn THEN faultMask := faultMask OR 16#20; END_IF;
IF stBoost.trip OR stBoost.warn THEN faultMask := faultMask OR 16#40; END_IF;
IF cleanFail THEN faultMask := faultMask OR 16#80; END_IF;
IF transfer AND (core.StopReason = UT_STOP_METER_FAILED OR core.StopReason = UT_STOP_TIME_CAP) AND NOT core.Active THEN
  faultMask := faultMask OR 16#200;
END_IF;
Data.sts.faultCode := faultMask;
Fault := cfgOn OR stTrans.trip OR (grp.NoneAvailable AND need > 0) OR stBoost.trip OR stSrc.trip
         OR (Data.sts.levelBad.tripped AND Data.set.levelBad.response = UT_RESP_TRIP);
Warning := (faultMask AND NOT DWORD#1) <> 0 OR core.Warning OR Shortfall;
IF Fault AND faultPrev = 0 THEN
  Data.sts.trips := Data.sts.trips + 1;
  Data.sts.lastFaultCode := faultMask;
END_IF;
IF Fault THEN faultPrev := faultMask; ELSE faultPrev := 0; END_IF;

stF := UT_F_NONE;
tLeft := T#0s;
IF cfgOn THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF stTrans.trip THEN
  stCode := UT_ST_FLOAT_CONTROL;
  stF := UT_F_TRANSDUCER;
ELSIF stBoost.trip AND BoostWanted THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.booster.lost.reset, Sts := Data.sts.boosterLost);
  stF := UT_F_BOOSTER;
ELSIF grp.NoneAvailable AND need > 0 THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_NO_PUMP;
ELSIF Inhibit AND (LevelCall OR procOn) THEN
  stCode := UT_ST_INHIBITED;
ELSIF NOT procOn AND NOT (transfer AND core.Active) THEN
  stCode := UT_ST_OFF;
ELSIF srcLow THEN
  stCode := UT_ST_WAIT_SOURCE;
ELSIF grp.AllHeld AND need > 0 THEN
  stCode := UT_ST_WAIT_STARTS;
ELSIF StartHold AND LevelCall AND NOT Running THEN
  stCode := UT_ST_START_HOLD;
ELSIF Data.sts.floatControl AND (fc OR stTrans.warn) THEN
  stCode := UT_ST_FLOAT_CONTROL;
  stF := UT_F_LEVEL_FAIL;
ELSIF Data.sts.runOn THEN
  stCode := UT_ST_RUN_ON_BAD;
  tLeft := Data.set.levelRunOn - (tCur - runOnAt);
ELSIF hfOn AND empty THEN
  stCode := UT_ST_HIGH_FLOAT;
ELSIF fill AND fH AND NOT Running THEN
  stCode := UT_ST_FULL;
ELSIF cleaning THEN
  stCode := UT_ST_CLEANING;
ELSIF Warning AND NOT Running THEN
  stCode := UT_ST_WARNING;
  IF Data.sts.floatsDisagree THEN stF := UT_F_FLOAT_DISAGREE;
  ELSIF stSrc.warn THEN stF := UT_F_SOURCE_BAD;
  ELSIF Data.sts.levelBad.tripped THEN stF := UT_F_LEVEL_BAD;
  ELSIF Shortfall THEN stF := UT_F_NO_PUMP;
  ELSE stF := core.FaultId;
  END_IF;
ELSIF Shortfall THEN
  stCode := UT_ST_SHORTFALL;
ELSIF timed AND NOT flasher.Q AND procOn THEN
  stCode := UT_ST_TIMED_REST;
ELSIF timed AND Running THEN
  stCode := UT_ST_RUN_TIMED;
ELSIF Data.sts.demand AND Running THEN
  stCode := UT_ST_RUN_DEMAND;
ELSIF transfer AND core.Active AND tPause THEN
  stCode := UT_ST_PAUSED_HOLD;
ELSIF floatsOnly AND Running THEN
  stCode := UT_ST_FLOAT_RUN;       (* a floats-only site (no level transmitter fitted): its normal running *)
ELSIF Running THEN
  stCode := UT_ST_RUNNING;
  IF transfer THEN tLeft := core.TimeLeft; END_IF;
ELSIF fill AND noFlowStop THEN
  stCode := UT_ST_STOPPED_FULL;
ELSIF Demand AND demDone THEN
  IF fill THEN stCode := UT_ST_STOPPED_FULL; ELSE stCode := UT_ST_STOPPED_LOW; END_IF;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
IF Fault THEN
  Data.sts.lastFault := stF;
END_IF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := Inhibit, OutOfSpec := Warning OR HighLevel, Maint := FALSE);
Data.det.timeLeft := tLeft;
Data.det.phaseTime := tCur - phaseAt;
Data.det.rotateIn := grp.RotateIn;
IF cleaning THEN
  Data.det.cleanElapsed := tCur - cleanStart;
ELSE
  Data.det.cleanElapsed := T#0s;
END_IF;
Data.det.run.elapsed := core.Elapsed;
Data.det.run.timeLeft := core.TimeLeft;
Data.sts.run.active := core.Active;
Data.sts.run.paused := core.Paused;
Data.sts.run.waiting := core.Waiting;
Data.sts.run.delivered := core.Delivered;
Data.sts.run.volumeLeft := core.VolumeLeft;
Data.sts.run.timeCap := core.TimeCap;
Data.sts.lead := Lead;
Data.sts.runningCount := RunningCount;
Data.sts.calledCount := grp.CalledCount;
Data.sts.availableCount := 0;
FOR k := 0 TO 31 DO
  IF (masks.available AND SHL(DWORD#1, k)) <> 0 THEN
    Data.sts.availableCount := Data.sts.availableCount + 1;
  END_IF;
END_FOR;
Data.sts.running := Running;
Data.sts.shortfall := Shortfall;
Data.sts.highLevel := HighLevel;
Data.sts.transducerFault := TransducerFault;
Data.sts.configFault := cfgOn;
Data.sts.configBad := cfgOn;
Data.sts.cleaning := cleaning;
Data.sts.cleanFailed := cleanFail;
Data.sts.warning := Warning;
Data.sts.fault := Fault;
Data.sts.inhibited := Inhibit;
Data.sts.levelCall := LevelCall;
Data.sts.atStop := AtStop;
Data.sts.waiting := Waiting;
Data.sts.sourceLow := srcLow;
Data.sts.allHeld := grp.AllHeld;
Data.sts.startHold := StartHold;
Data.sts.inflow := Inflow;
Data.sts.outflow := flowRate;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

END_FUNCTION_BLOCK