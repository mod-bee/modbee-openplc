(* UT_PUMP_CASCADE — several pumps on one header holding a pressure (or a
flow): PV / flow staging, a shared VSD speed, a jockey, wear sharing,
failover. The pumps are the project's UT_PUMP instances (Pumps, any count;
call them first, then the cascade); each pump keeps its own motor (UT_MOTOR
or UT_MOTOR_VSD, mixed). Every call goes through Pumps[i].Request, so each
pump's dry run, prime, starts limit and holds act here too.

Roles (UT_PUMP set.role): DUTY pumps form the group (UT_GROUP_RUN: rotation,
failover, swap; VSD pumps are preferLead: first on, last off); one JOCKEY
covers the low demand; a BOOSTER or a second JOCKEY is left out (warning
UT_F_PUMP_ROLE).

The loop is UT_SPEED_CTRL_RUN on set.ctrl: setpoint, PID, pipe fill, sleep /
boost / wake, flow limit, overpressure, burst (lowPvAtMax waits while a pump
can still be added), hunting, sensor failure. Its Run starts the set, its
Speed goes to every called VSD pump.

Staging (stageBy), in CONTROL only, one pump at a time; the need must last
group.stageDelay (add) or group.destageDelay (drop):
  PV        with a VSD running: add at maximum speed with Pv short of sp by
            more than ctrl.atSpBand; drop at minimum speed or below
            dropSpeed. No VSD running: add addBand below sp, drop dropBand
            above.
  FLOW      add above addPct % of the running capacity; drop below dropPct %
            of the capacity left after the drop.
  PER_PUMP  add when the flow per pump is above bepMax (and stays above
            bepMin with one more); drop below bepMin (and stays below bepMax
            with one fewer).
FLOW / PER_PUMP also add on the PV rule (the pressure is never left short:
pvStaging warning until the set next starts from none) and fall back to PV
with a bad meter or unusable settings (a warning).

The jockey starts first (not for a pipe fill), hands over to a duty pump
when it cannot keep up (Flow above addPct % of its capacity, or the PV rule;
short of pressure below its capacity: skipped until the next start), and
the set hands back when one duty pump is left and the demand falls. The
jockey runs on until the duty pump runs.

A trip (the loop's, high flow), Interlock FALSE (Hold), Inhibit or a config
fault stops every pump at once. Run FALSE / sleep: stopMode ALL_AT_ONCE, or
STAGED (VSDs at minimum speed, one pump per stopStep, fixed speed first, the
jockey last). Overpressure WARN drops a pump each destageDelay. A failed
sensor with FALLBACK runs one pump at the fallback speed. Manual speed: no
pump added or dropped. Settings kept (the loop's too); a bad write is put
back. *)

FUNCTION_BLOCK UT_PUMP_CASCADE
  VAR_INPUT
    Run : BOOL; (* pumping wanted, per set.run.style *)
    Start : BOOL R_EDGE; (* latched start *)
    Stop : BOOL R_EDGE; (* stop (staged per stopMode); wins *)
    Reset : BOOL R_EDGE; (* reset trips (the loop's too) whose cause has gone *)
    Interlock : BOOL := TRUE; (* FALSE: every pump held *)
    Permissive : BOOL := TRUE; (* FALSE: no new pump start *)
    Inhibit : BOOL; (* stops the set, no fault, never overridden *)
    Rotate : BOOL R_EDGE; (* hand over now *)
    Manual : BOOL R_EDGE; (* run at the manual speed (kept choice) *)
    Auto : BOOL R_EDGE; (* back to the loop *)
    Preset : INT := -1; (* 0 NORMAL, 1 LOW, 2 HIGH while wired; -1 = the kept ctrl.preset *)
    ManualSpeed : REAL := -1.0; (* < 0 = the kept ctrl.manualSpeed *)
    Sp : REAL; (* setpoint when ctrl.spSource = PIN *)
    ExtSpeed : REAL := -1.0; (* external PID speed (ctrl.loop EXTERNAL); < 0 = not wired *)
    Pv : UT_I_MEAS; (* header pressure *)
    Flow : UT_I_MEAS; (* header flow *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL;
    AtSetpoint : BOOL;
    Filled : BOOL;
    Shortfall : BOOL;
    Fault : BOOL;
    Warning : BOOL;
    RunningCount : INT;
    Speed : REAL;
    Phase : UT_SC_PHASE;
  END_VAR
  VAR_IN_OUT
    Pumps : ARRAY [*] OF UT_PUMP;
    Data : UT_PUMP_CASCADE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_PUMP_CASCADE_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    grp : UT_GROUP_RUN;
    masks : UT_GROUP_MASKS;
    runIn : UT_RUN_INPUT;
    ctl : UT_SPEED_CTRL_RUN;
    use : UT_SC_USE;
    stHf : UT_PROT_ST;
    ok : BOOL;
    ctlOk : BOOL;
    cfgId : UT_FAULT;
    cfgOn : BOOL;
    started : BOOL;
    x : BOOL;
    tCur : TIME;
    i : DINT;
    lo : DINT;
    hi : DINT;
    k : INT;
    bit : DWORD;
    slot : ARRAY [0..31] OF DINT; (* duty member k is Pumps[slot[k]] *)
    nD : INT;
    jIdx : DINT; (* the jockey (lo - 1 = none) *)
    roleBad : BOOL;
    hReset : BOOL;
    hRot : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    hMan : BOOL;
    hAuto : BOOL;
    resetReq : BOOL;
    rotReq : BOOL;
    manReq : BOOL;
    autoReq : BOOL;
    pvFit : BOOL;
    pvOk : BOOL;
    pvV : REAL;
    flowFit : BOOL;
    flowOk : BOOL;
    flowV : REAL;
    nRunD : INT; (* duty pumps running *)
    nCalledD : INT;
    vsdOn : INT;
    jRun : BOOL;
    jAvail : BOOL;
    jSkip : BOOL;
    capOn : REAL;
    capJ : REAL;
    dutyCapZero : BOOL;
    loopOn : BOOL;
    runGrp : BOOL;
    runPrev : BOOL;
    tripStop : BOOL;
    jk : BOOL; (* the jockey's turn *)
    stage : INT; (* duty pumps wanted *)
    crit : UT_PC_STAGE;
    pvForced : BOOL;
    e : REAL;
    band : REAL;
    short : BOOL;
    atMax : BOOL;
    atMin : BOOL;
    pvAdd : BOOL;
    pvDrop : BOOL;
    perPump : REAL;
    addCond : BOOL;
    dropCond : BOOL;
    flowAdd : BOOL;
    handback : BOOL;
    ovp : BOOL;
    addSince : TIME;
    dropSince : TIME;
    settled : BOOL;
    staged : BOOL;
    stepAt : TIME;
    stopLeft : INT;
    jCall : BOOL;
    need : INT;
    spdV : REAL;
    zero : REAL;
    nan : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    stUnit : INT;
    tLeft : TIME;
    mirror : BOOL;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    faultMask : DWORD;
    faultPrev : BOOL;
    ctlTripsPrev : UDINT;
    lastPhase : UT_SC_PHASE;
    phaseAt : TIME;
  END_VAR


tCur := TIME();
IF NOT started THEN
  started := TRUE;
  nan := zero / zero;
  addSince := tCur;
  dropSince := tCur;
  phaseAt := tCur;
END_IF;

(* the pumps: duty members, the jockey, the left-out ones *)
lo := LOWER_BOUND(Pumps, 1);
hi := UPPER_BOUND(Pumps, 1);
jIdx := lo - 1;
roleBad := FALSE;
nD := 0;
FOR i := lo TO hi DO
  IF Pumps[i].Role() = UT_ROLE_JOCKEY THEN
    IF jIdx < lo THEN jIdx := i; ELSE roleBad := TRUE; END_IF;
  ELSIF Pumps[i].Role() = UT_ROLE_DUTY THEN
    IF nD < 32 THEN
      slot[nD] := i;
      nD := nD + 1;
    END_IF;
  ELSE
    roleBad := TRUE;
  END_IF;
END_FOR;

(* commands: once per request *)
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
rotReq := Rotate OR (Data.cmdRotate AND NOT hRot);
hRot := Data.cmdRotate;
Data.cmdRotate := FALSE;
manReq := Manual OR (Data.cmdManual AND NOT hMan);
hMan := Data.cmdManual;
Data.cmdManual := FALSE;
autoReq := Auto OR (Data.cmdAuto AND NOT hAuto);
hAuto := Data.cmdAuto;
Data.cmdAuto := FALSE;

(* the plugs *)
pvFit := FALSE;
pvOk := FALSE;
pvV := 0.0;
IF Pv <> NULL THEN
  pvFit := Pv.IsFitted();
  pvOk := pvFit AND Pv.GoodNow();
  pvV := Pv.GetValue();
END_IF;
flowFit := FALSE;
flowOk := FALSE;
flowV := 0.0;
IF Flow <> NULL THEN
  flowFit := Flow.IsFitted();
  flowOk := flowFit AND Flow.GoodNow();
  flowV := Flow.GetValue();
END_IF;

(* settings: kept; a bad write is put back (the cascade's and the loop's) *)
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_PUMP_CASCADE_CHECK(N := MAX(nD, 1), S := Data.set, Id => cfgId);
ctlOk := UT_SPEED_CTRL_CHECK(Preset := Preset, ManualSpeed := ManualSpeed, Sp := Sp, PvFitted := pvFit,
                             FlowFitted := flowFit, ExtSpeed := ExtSpeed, ManualReq := manReq, AutoReq := autoReq,
                             Set := Data.set.ctrl, U := use);
IF NOT (ok AND ctlOk) AND keptGood AND NOT keep.FirstBoot THEN
  IF NOT ok THEN Data.sts.refused := cfgId; ELSE Data.sts.refused := use.setId; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_PUMP_CASCADE_CHECK(N := MAX(nD, 1), S := Data.set, Id => cfgId);
  ctlOk := UT_SPEED_CTRL_CHECK(Preset := Preset, ManualSpeed := ManualSpeed, Sp := Sp, PvFitted := pvFit,
                               FlowFitted := flowFit, ExtSpeed := ExtSpeed, ManualReq := manReq, AutoReq := autoReq,
                               Set := Data.set.ctrl, U := use);
END_IF;
IF keep.SaveSet AND ((ok AND ctlOk) OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok AND ctlOk;
END_IF;
cfgOn := NOT ok;
IF nD < 1 THEN
  cfgOn := TRUE;
  cfgId := UT_F_NO_UNITS;
END_IF;

(* the duty members' flags, capacity *)
masks.count := nD;
masks.fitted := 0;
masks.available := 0;
masks.waiting := 0;
masks.running := 0;
masks.inHand := 0;
masks.startsHeld := 0;
masks.exercising := 0;
masks.preferLead := 0;
nRunD := 0;
nCalledD := 0;
vsdOn := 0;
capOn := 0.0;
dutyCapZero := FALSE;
FOR k := 0 TO 31 DO
  IF k < nD THEN
    bit := SHL(DWORD#1, k);
    i := slot[k];
    IF Pumps[i].IsFitted() THEN masks.fitted := masks.fitted OR bit; END_IF;
    IF Pumps[i].IsAvailable() THEN masks.available := masks.available OR bit; END_IF;
    IF Pumps[i].IsWaiting() THEN masks.waiting := masks.waiting OR bit; END_IF;
    IF Pumps[i].IsHand() THEN masks.inHand := masks.inHand OR bit; END_IF;
    IF Pumps[i].StartsHeld() THEN masks.startsHeld := masks.startsHeld OR bit; END_IF;
    IF Pumps[i].IsExercising() THEN masks.exercising := masks.exercising OR bit; END_IF;
    IF Pumps[i].IsVsd() THEN masks.preferLead := masks.preferLead OR bit; END_IF;
    masks.hours[k] := LREAL_TO_REAL(Pumps[i].RunHours());
    IF NOT (Pumps[i].Capacity() > 0.0) AND Pumps[i].IsFitted() THEN
      dutyCapZero := TRUE;
    END_IF;
    IF Pumps[i].IsRunning() THEN
      masks.running := masks.running OR bit;
      nRunD := nRunD + 1;
      capOn := capOn + Pumps[i].Capacity();
      IF Pumps[i].IsVsd() THEN vsdOn := vsdOn + 1; END_IF;
    END_IF;
    IF (masks.call AND bit) <> 0 THEN
      nCalledD := nCalledD + 1;
    END_IF;
  END_IF;
END_FOR;
jRun := FALSE;
jAvail := FALSE;
capJ := 0.0;
IF jIdx >= lo THEN
  jRun := Pumps[jIdx].IsRunning();
  jAvail := Pumps[jIdx].IsAvailable() AND NOT jSkip;
  capJ := Pumps[jIdx].Capacity();
  IF NOT (capJ >= 0.0 AND capJ <= 3.4E38) THEN capJ := 0.0; END_IF;
END_IF;

(* the request and the loop *)
runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := Data.cmdStart AND NOT hStart,
      CmdStop := Data.cmdStop AND NOT hStop, Drop := cfgOn, Linked := FALSE, TargetDone := FALSE,
      HasTarget := FALSE, Set := Data.set.run);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
x := UT_LEVEL_RUN(TNow := tCur, In := flowV, Good := flowOk, High := TRUE, UseIn := TRUE, Switch := FALSE,
                  Enable := Data.set.highFlow.sp > 0.0 AND (nRunD > 0 OR jRun), Release := NOT flowOk,
                  ResetReq := resetReq, RetryWindow := Data.set.ctrl.retryWindow, Level := Data.set.highFlow,
                  Sts := Data.sts.highFlow, St := stHf);
loopOn := runIn.Request AND NOT runIn.BadSetting AND NOT cfgOn AND NOT Inhibit AND Interlock AND NOT stHf.trip;
ctl(Enable := loopOn, Pv := pvV, PvGood := pvOk, Flow := flowV, FlowGood := flowOk, Sp := Sp,
    Running := nRunD > 0 OR jRun, ExtSpeed := ExtSpeed, ResetReq := resetReq,
    MoreAvailable := grp.CalledCount < nD AND masks.available <> 0 AND NOT jk,
    Set := Data.set.ctrl, U := use, Sts := Data.sts.ctrl, Det := Data.det.ctrl);
runGrp := ctl.Run AND loopOn;
tripStop := ctl.Fault OR stHf.trip OR cfgOn OR Inhibit OR NOT Interlock;

(* the criterion in use *)
crit := Data.set.stageBy;
IF crit <> UT_PC_STAGE_PV AND NOT flowOk THEN
  crit := UT_PC_STAGE_PV;        (* the meter has failed: stage on Pv *)
ELSIF (crit = UT_PC_STAGE_FLOW AND dutyCapZero)
      OR (crit = UT_PC_STAGE_PER_PUMP AND NOT (Data.set.bepMax > Data.set.bepMin)) OR pvForced THEN
  crit := UT_PC_STAGE_PV;
END_IF;

(* the staging conditions *)
ovp := Data.sts.ctrl.highPv.tripped;   (* WARN: the loop holds the speed at minimum *)
band := Data.set.ctrl.atSpBand;
e := 0.0;
IF pvOk THEN
  IF Data.set.ctrl.reverseActing THEN
    e := pvV - Data.sts.ctrl.spActive;
  ELSE
    e := Data.sts.ctrl.spActive - pvV;
  END_IF;
END_IF;
short := pvOk AND e > band;
atMax := ctl.Speed >= Data.set.ctrl.maxSpeed - 0.01 AND NOT Data.sts.ctrl.flowLimiting;
atMin := ctl.Speed <= Data.set.ctrl.minSpeed + 0.01;
IF vsdOn > 0 THEN
  pvAdd := atMax AND short;
  pvDrop := pvOk AND NOT short AND (atMin OR ctl.Speed < Data.set.dropSpeed);
ELSE
  pvAdd := pvOk AND e > Data.set.addBand;
  pvDrop := pvOk AND e < -Data.set.dropBand;
END_IF;
perPump := 0.0;
IF nRunD > 0 AND flowOk THEN
  perPump := flowV / INT_TO_REAL(nRunD);
END_IF;
addCond := FALSE;
dropCond := FALSE;
handback := FALSE;
flowAdd := TRUE;
IF ctl.Phase = UT_SC_CONTROL AND NOT ovp AND runGrp THEN
  IF jk THEN
    IF capJ > 0.0 AND flowOk THEN
      flowAdd := flowV > Data.set.addPct / 100.0 * capJ;
      addCond := flowAdd OR pvAdd;
    ELSE
      addCond := pvAdd;
    END_IF;
  ELSE
    handback := nCalledD = 1 AND jIdx >= lo AND jAvail;
    CASE crit OF
    UT_PC_STAGE_FLOW:
      flowAdd := flowV > Data.set.addPct / 100.0 * capOn;
      addCond := flowAdd OR pvAdd;
      IF nRunD > 0 THEN
        dropCond := nCalledD > 1 AND flowV < Data.set.dropPct / 100.0 * (capOn - capOn / INT_TO_REAL(nRunD));
      END_IF;
    UT_PC_STAGE_PER_PUMP:
      IF nRunD > 0 THEN
        flowAdd := perPump > Data.set.bepMax AND flowV / INT_TO_REAL(nRunD + 1) > Data.set.bepMin;
        addCond := flowAdd OR pvAdd;
        dropCond := nCalledD > 1 AND perPump < Data.set.bepMin
                    AND (nRunD <= 1 OR flowV / INT_TO_REAL(MAX(nRunD - 1, 1)) < Data.set.bepMax);
      END_IF;
    ELSE
      addCond := pvAdd;
      dropCond := nCalledD > 1 AND pvDrop;
    END_CASE;
    IF handback THEN
      IF capJ > 0.0 AND flowOk THEN
        dropCond := flowV < Data.set.dropPct / 100.0 * capJ;
      ELSE
        dropCond := pvDrop;
      END_IF;
    END_IF;
  END_IF;
ELSIF ovp AND runGrp THEN
  dropCond := nCalledD > 1;      (* overpressure warning: shed pumps one at a time *)
END_IF;
IF NOT addCond THEN
  addSince := tCur;
END_IF;
IF NOT dropCond THEN
  dropSince := tCur;
END_IF;

(* the stage *)
IF NOT runGrp THEN
  IF runPrev THEN
    staged := Data.set.stopMode = UT_PC_STOP_STAGED AND NOT tripStop;
    stepAt := tCur - Data.set.stopStep;   (* the first stops at once *)
    stopLeft := nCalledD;
  END_IF;
  stage := 0;
ELSE
  IF NOT runPrev THEN
    (* from none: the jockey first (not for a pipe fill), skipped pumps get another chance *)
    jSkip := FALSE;
    pvForced := FALSE;
    addSince := tCur;
    dropSince := tCur;
    IF staged AND nCalledD > 0 THEN
      jk := FALSE;               (* back during a staged stop: carry on with those still running *)
      stage := nCalledD;
    ELSIF jIdx >= lo AND Pumps[jIdx].IsAvailable() AND ctl.Phase <> UT_SC_FILLING THEN
      jk := TRUE;
      stage := 0;
    ELSE
      jk := FALSE;
      stage := 1;
    END_IF;
  END_IF;
  staged := FALSE;
  IF jk AND NOT jAvail AND NOT jRun AND masks.available <> 0 THEN
    jk := FALSE;                 (* the jockey cannot: a duty pump *)
    stage := 1;
  ELSIF NOT jk AND stage <= 1 AND nCalledD = 0 AND masks.available = 0 AND jAvail THEN
    jk := TRUE;
    stage := 0;
  END_IF;
  IF ctl.Phase = UT_SC_FILLING AND jk AND masks.available <> 0 THEN
    jk := FALSE;                 (* a pipe fill uses a duty pump *)
    stage := 1;
  END_IF;
  IF ctl.Phase = UT_SC_FALLBACK AND Data.sts.ctrl.pvBad AND Data.set.ctrl.pvFail = UT_PVFAIL_FALLBACK AND stage > 1 THEN
    stage := 1;                  (* a failed sensor: one pump at the fallback speed *)
  END_IF;
  settled := grp.CalledCount = grp.RunningCount AND ((jk AND jRun) OR (NOT jk AND NOT jRun) OR (NOT jk AND nRunD = 0));
  IF ctl.Phase = UT_SC_MANUAL THEN
    ;                            (* manual speed: no pump added or dropped *)
  ELSIF addCond AND settled AND Permissive AND tCur - addSince >= Data.set.group.stageDelay THEN
    IF jk THEN
      jk := FALSE;               (* hand over to a duty pump *)
      stage := 1;
      IF NOT flowAdd THEN
        jSkip := TRUE;           (* short of pressure below its capacity: skipped until the next start *)
      END_IF;
    ELSIF stage < nD THEN
      stage := nCalledD + 1;
      IF NOT flowAdd THEN
        pvForced := TRUE;        (* the flow rule left the pressure short *)
      END_IF;
    END_IF;
    addSince := tCur;
  ELSIF dropCond AND settled AND tCur - dropSince >= Data.set.group.destageDelay THEN
    IF nCalledD > 1 THEN
      stage := nCalledD - 1;
    ELSIF handback THEN
      jk := TRUE;                (* hand back to the jockey *)
      stage := 0;
    END_IF;
    dropSince := tCur;
  END_IF;
END_IF;
runPrev := runGrp;

(* a staged stop: one pump per stopStep, fixed speed first (the engine), the jockey last *)
IF staged THEN
  IF tripStop THEN
    staged := FALSE;
  ELSIF tCur - stepAt >= Data.set.stopStep THEN
    stepAt := tCur;
    IF stopLeft > 0 THEN
      stopLeft := stopLeft - 1;
    ELSE
      staged := FALSE;           (* the jockey goes last *)
    END_IF;
  END_IF;
END_IF;
IF staged THEN
  need := stopLeft;
ELSIF jk THEN
  need := 0;
ELSE
  need := stage;
END_IF;
IF NOT Permissive AND need > nRunD THEN
  need := MAX(nRunD, nCalledD);  (* no new start *)
END_IF;
grp(Enable := (runGrp OR staged) AND NOT tripStop, Required := need, Rotate := rotReq, Reset := resetReq,
    Set := Data.set.group, Members := masks);
IF grp.CfgFault AND NOT cfgOn THEN
  cfgOn := TRUE;
  cfgId := grp.FaultId;
END_IF;

(* the jockey: its turn, on until the duty pump runs, last in a staged stop *)
jCall := FALSE;
IF jIdx >= lo AND NOT tripStop THEN
  IF runGrp THEN
    jCall := (jk OR (jRun AND nRunD = 0)) AND jAvail;
    IF jk AND jRun THEN jCall := TRUE; END_IF;
  ELSIF staged THEN
    jCall := jRun;
  END_IF;
  IF NOT Permissive AND NOT jRun THEN
    jCall := FALSE;
  END_IF;
END_IF;

(* the requests *)
IF staged THEN
  spdV := Data.set.ctrl.minSpeed;
ELSE
  spdV := ctl.Speed;
END_IF;
FOR k := 0 TO 31 DO
  IF k < nD THEN
    i := slot[k];
    IF Pumps[i].IsVsd() THEN
      x := Pumps[i].Request(ReqRun := (masks.call AND SHL(DWORD#1, k)) <> 0, Hold := NOT Interlock,
                            ReqSpeed := spdV, Owner := Data.set.tag);
    ELSE
      x := Pumps[i].Request(ReqRun := (masks.call AND SHL(DWORD#1, k)) <> 0, Hold := NOT Interlock,
                            ReqSpeed := nan, Owner := Data.set.tag);
    END_IF;
  END_IF;
END_FOR;
IF jIdx >= lo THEN
  IF Pumps[jIdx].IsVsd() THEN
    x := Pumps[jIdx].Request(ReqRun := jCall, Hold := NOT Interlock, ReqSpeed := spdV, Owner := Data.set.tag);
  ELSE
    x := Pumps[jIdx].Request(ReqRun := jCall, Hold := NOT Interlock, ReqSpeed := nan, Owner := Data.set.tag);
  END_IF;
END_IF;

(* outputs *)
RunningCount := nRunD + BOOL_TO_INT(jRun);
Running := RunningCount > 0;
AtSetpoint := ctl.AtSetpoint;
Filled := ctl.Filled;
Shortfall := runGrp AND grp.Shortfall AND NOT grp.AllHeld AND NOT jk;
Speed := spdV;
Phase := ctl.Phase;
IF Phase <> lastPhase THEN
  lastPhase := Phase;
  phaseAt := tCur;
END_IF;
Data.sts.flowBad := Data.set.stageBy <> UT_PC_STAGE_PV AND NOT flowOk;
Data.sts.pvStaging := pvForced;
Data.sts.wrnConfig := roleBad OR (Data.set.stageBy = UT_PC_STAGE_FLOW AND dutyCapZero)
                      OR (Data.set.stageBy = UT_PC_STAGE_PER_PUMP AND NOT (Data.set.bepMax > Data.set.bepMin));
faultMask := 0;
IF cfgOn THEN faultMask := faultMask OR 16#1; END_IF;
IF ctl.Fault THEN faultMask := faultMask OR 16#2; END_IF;
IF stHf.trip OR stHf.warn THEN faultMask := faultMask OR 16#4; END_IF;
IF grp.NoneAvailable AND runGrp AND NOT jk THEN faultMask := faultMask OR 16#8; END_IF;
IF Data.sts.wrnConfig THEN faultMask := faultMask OR 16#400; END_IF;
IF Data.sts.pvStaging THEN faultMask := faultMask OR 16#800; END_IF;
IF Data.sts.flowBad THEN faultMask := faultMask OR 16#1000; END_IF;
Fault := cfgOn OR ctl.Fault OR stHf.trip OR (grp.NoneAvailable AND runGrp AND NOT jk);
Warning := ctl.Warning OR stHf.warn OR Shortfall OR (faultMask AND 16#1C00) <> 0 OR masks.skipped <> 0;
IF Fault AND NOT faultPrev THEN
  Data.sts.lastFaultCode := faultMask;
END_IF;
IF stHf.trip AND NOT faultPrev THEN
  Data.sts.trips := Data.sts.trips + 1;
  Data.sts.stopReason := UT_STOP_FAULT;
END_IF;
IF Data.sts.ctrl.trips <> ctlTripsPrev THEN
  Data.sts.trips := Data.sts.trips + (Data.sts.ctrl.trips - ctlTripsPrev);
  ctlTripsPrev := Data.sts.ctrl.trips;
END_IF;
faultPrev := Fault;
IF NOT runGrp AND NOT stHf.trip AND Data.sts.ctrl.stopReason <> UT_STOP_NONE THEN
  Data.sts.stopReason := Data.sts.ctrl.stopReason;
END_IF;

(* status: the loop's when it says more *)
stF := UT_F_NONE;
stUnit := 0;
tLeft := T#0s;
mirror := FALSE;
IF cfgOn THEN
  stCode := UT_ST_CONFIG;
  stF := cfgId;
ELSIF Data.sts.ctrl.statusCode = UT_ST_CONFIG THEN
  mirror := TRUE;
ELSIF stHf.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.highFlow.reset, Sts := Data.sts.highFlow);
  stF := UT_F_HIGH_FLOW;
  tLeft := Data.sts.highFlow.timeLeft;
ELSIF ctl.Fault THEN
  mirror := TRUE;
ELSIF Inhibit AND runIn.Request THEN
  stCode := UT_ST_INHIBITED;
ELSIF NOT Interlock AND runIn.Request THEN
  stCode := UT_ST_INTERLOCK;
ELSIF staged THEN
  stCode := UT_ST_STOPPING;
  tLeft := Data.set.stopStep - (tCur - stepAt);
ELSIF NOT runIn.Request THEN
  stCode := UT_ST_IDLE_NOT_ENABLED;
ELSIF Data.sts.ctrl.statusCode = UT_ST_SLEEPING OR Data.sts.ctrl.statusCode = UT_ST_ENABLE_CYCLE THEN
  mirror := TRUE;
ELSIF grp.AllHeld AND runGrp AND NOT jk THEN
  stCode := UT_ST_WAIT_STARTS;
ELSIF Shortfall THEN
  stCode := UT_ST_SHORTFALL;
ELSIF NOT Permissive AND addCond THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSE
  stCode := UT_ST_IDLE_NO_DEMAND;
  FOR k := 31 TO 0 BY -1 DO
    IF k < nD THEN
      IF (masks.call AND SHL(DWORD#1, k)) <> 0 AND (masks.running AND SHL(DWORD#1, k)) = 0 THEN
        stUnit := DINT_TO_INT(slot[k] - lo + 1);
      END_IF;
    END_IF;
  END_FOR;
  IF stUnit > 0 THEN
    stCode := UT_ST_STARTING;
  ELSIF jCall AND NOT jRun THEN
    stCode := UT_ST_STARTING;
    stUnit := DINT_TO_INT(jIdx - lo + 1);
  ELSIF Data.sts.flowBad THEN
    stCode := UT_ST_WARNING;
    stF := UT_F_FLOW_BAD;
  ELSIF Data.sts.pvStaging THEN
    stCode := UT_ST_WARNING;
    stF := UT_F_FLOW_SHORT;
  ELSIF stHf.warn THEN
    stCode := UT_ST_WARNING;
    stF := UT_F_HIGH_FLOW;
  ELSIF Data.sts.ctrl.statusCode = UT_ST_WARNING OR Data.sts.ctrl.statusCode = UT_ST_WARN_SETTING THEN
    mirror := TRUE;
  ELSIF Data.sts.wrnConfig THEN
    stCode := UT_ST_WARN_SETTING;
    IF roleBad THEN stF := UT_F_PUMP_ROLE; ELSE stF := UT_F_GROUP_SETTING; END_IF;
  ELSIF Data.sts.ctrl.statusCode = UT_ST_PIPE_FILL OR Data.sts.ctrl.statusCode = UT_ST_BOOST
        OR Data.sts.ctrl.statusCode = UT_ST_FLOW_LIMIT OR Data.sts.ctrl.statusCode = UT_ST_FALLBACK
        OR ctl.Phase = UT_SC_MANUAL THEN
    mirror := TRUE;
  ELSIF runGrp AND addCond THEN
    stCode := UT_ST_ADDING;
    tLeft := Data.set.group.stageDelay - (tCur - addSince);
  ELSIF runGrp AND dropCond THEN
    stCode := UT_ST_DROPPING;
    tLeft := Data.set.group.destageDelay - (tCur - dropSince);
  ELSIF runGrp AND jk THEN
    stCode := UT_ST_JOCKEY;
  ELSIF Running THEN
    stCode := UT_ST_RUNNING;
  END_IF;
END_IF;
IF mirror THEN
  stCode := Data.sts.ctrl.statusCode;
  stF := Data.sts.ctrl.faultId;
  tLeft := Data.det.ctrl.timeLeft;
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
Data.sts.statusUnit := stUnit;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := Inhibit OR ctl.Phase = UT_SC_MANUAL, OutOfSpec := Warning,
                               Maint := FALSE);
Data.sts.faultCode := faultMask;
Data.sts.stage := stage;
Data.sts.runningCount := RunningCount;
Data.sts.calledCount := grp.CalledCount + BOOL_TO_INT(jCall);
Data.sts.availableCount := BOOL_TO_INT(jAvail);
FOR k := 0 TO 31 DO
  IF (masks.available AND SHL(DWORD#1, k)) <> 0 THEN
    Data.sts.availableCount := Data.sts.availableCount + 1;
  END_IF;
END_FOR;
Data.sts.capacity := capOn;
Data.sts.flowPerPump := perPump;
Data.sts.speed := Speed;
Data.sts.stageByUsed := crit;
Data.sts.running := Running;
Data.sts.jockeyOn := jRun;
Data.sts.shortfall := Shortfall;
Data.sts.configBad := cfgOn OR Data.sts.ctrl.configBad;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.stopping := staged;
Data.sts.filled := Filled;
Data.sts.inhibited := Inhibit;
Data.sts.allHeld := grp.AllHeld;
Data.det.timeLeft := tLeft;
Data.det.phaseTime := tCur - phaseAt;

END_FUNCTION_BLOCK