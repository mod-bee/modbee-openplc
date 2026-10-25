(* UT_DUTY — duty / assist / standby for motor-driven units without process
logic (fans, compressors, blowers, stirrers): Required units run, chosen by
the group engine (UT_GROUP_RUN: rotation, staging, failover, exercise).
Units are plugs (UT_I_MOTOR: any motor kind, NULL = not fitted); the duty
commands each through its Request every scan, so each unit runs "Auto: by
<tag>" and a unit in Hand counts per set.group.handCounts.

Run (per set.run.style) / Start / Stop / cmdStart / cmdStop switch the group
on; while on, Required units are called. Interlock FALSE holds every unit;
Permissive FALSE: no new start (running units stay). Reset (pin or
cmdReset) lets skipped units be called again. Settings kept; a bad write is
put back. *)

FUNCTION_BLOCK UT_DUTY
  VAR_INPUT
    Run : BOOL := TRUE; (* Required acts while on (per set.run.style) *)
    Start : BOOL R_EDGE;
    Stop : BOOL R_EDGE;
    Reset : BOOL R_EDGE; (* skipped units may be called again *)
    Interlock : BOOL := TRUE; (* FALSE: every unit held *)
    Permissive : BOOL := TRUE; (* FALSE: no new start *)
    Rotate : BOOL R_EDGE;
    Required : INT := 1; (* units that should run *)
    Speed : REAL := -1.0; (* speed % to every called VSD unit; < 0 = none *)
    Units : ARRAY [1..8] OF UT_I_MOTOR; (* NULL = not fitted *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL;
    Shortfall : BOOL;
    Fault : BOOL;
    Warning : BOOL;
    RunningCount : INT;
    Lead : INT;
  END_VAR
  VAR_IN_OUT
    Data : UT_DUTY_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_DUTY_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    grp : UT_GROUP_RUN;
    masks : UT_GROUP_MASKS;
    runIn : UT_RUN_INPUT;
    ok : BOOL;
    cfgId : UT_FAULT;
    cfgOn : BOOL;
    started : BOOL;
    x : BOOL;
    i : INT;
    k : INT;
    bit : DWORD;
    slot : ARRAY [0..7] OF INT; (* member k is Units[slot[k]] *)
    n : INT;
    need : INT;
    nRun : INT;
    hReset : BOOL;
    hRot : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    resetReq : BOOL;
    rotReq : BOOL;
    reqSpeed : REAL;
    zero : REAL;
    nan : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    stUnit : INT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


IF NOT started THEN
  started := TRUE;
  nan := zero / zero;
END_IF;

(* the fitted units are the members *)
n := 0;
FOR i := 1 TO 8 DO
  IF Units[i] <> NULL THEN
    IF Units[i].IsFitted() THEN
      slot[n] := i;
      n := n + 1;
    END_IF;
  END_IF;
END_FOR;

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_DUTY_CHECK(N := MAX(n, 1), S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_DUTY_CHECK(N := MAX(n, 1), S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
cfgOn := NOT ok;
IF n < 1 THEN
  cfgOn := TRUE;
  cfgId := UT_F_NO_UNITS;
END_IF;

(* commands: once per request *)
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
rotReq := Rotate OR (Data.cmdRotate AND NOT hRot);
hRot := Data.cmdRotate;
Data.cmdRotate := FALSE;
runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := Data.cmdStart AND NOT hStart,
      CmdStop := Data.cmdStop AND NOT hStop, Drop := cfgOn, Linked := FALSE, TargetDone := FALSE,
      HasTarget := FALSE, Set := Data.set.run);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;

(* the members' flags *)
masks.count := n;
masks.fitted := 0;
masks.available := 0;
masks.waiting := 0;
masks.running := 0;
masks.inHand := 0;
masks.startsHeld := 0;
masks.exercising := 0;
masks.preferLead := 0;
nRun := 0;
FOR k := 0 TO 7 DO
  IF k < n THEN
    bit := SHL(DWORD#1, k);
    i := slot[k];
    masks.fitted := masks.fitted OR bit;
    IF Units[i].IsAvailable() THEN
      masks.available := masks.available OR bit;
      IF NOT Units[i].IsReady() THEN
        masks.waiting := masks.waiting OR bit;   (* its restart wait *)
      END_IF;
    END_IF;
    IF Units[i].IsRunning() THEN
      masks.running := masks.running OR bit;
      nRun := nRun + 1;
    END_IF;
    IF Units[i].IsHand() THEN
      masks.inHand := masks.inHand OR bit;
    END_IF;
    masks.hours[k] := LREAL_TO_REAL(Units[i].RunHours());
  END_IF;
END_FOR;

(* how many *)
need := 0;
IF runIn.Request AND NOT runIn.BadSetting AND NOT cfgOn AND Interlock THEN
  need := MAX(Required, 0);
END_IF;
IF NOT Permissive AND need > nRun THEN
  need := nRun;                  (* no new start *)
END_IF;
grp(Enable := NOT cfgOn, Required := need, Rotate := rotReq, Reset := resetReq, Set := Data.set.group,
    Members := masks);

(* the requests *)
IF Speed >= 0.0 THEN reqSpeed := Speed; ELSE reqSpeed := nan; END_IF;
FOR k := 0 TO 7 DO
  IF k < n THEN
    x := Units[slot[k]].Request(ReqRun := (masks.call AND SHL(DWORD#1, k)) <> 0, Hold := NOT Interlock,
                                ReqSpeed := reqSpeed, Owner := Data.set.tag);
  END_IF;
END_FOR;

Running := nRun > 0;
RunningCount := nRun;
Lead := 0;
IF grp.Lead >= 1 AND grp.Lead <= n THEN
  Lead := slot[grp.Lead - 1];
END_IF;
Shortfall := grp.Shortfall AND NOT grp.AllHeld;
Fault := cfgOn OR grp.CfgFault OR grp.NoneAvailable;
Warning := Shortfall OR masks.skipped <> 0;

(* status: the unit it is about *)
stF := UT_F_NONE;
stUnit := 0;
tLeft := T#0s;
IF cfgOn OR grp.CfgFault THEN
  stCode := UT_ST_CONFIG;
  IF cfgOn THEN stF := cfgId; ELSE stF := grp.FaultId; END_IF;
ELSIF grp.NoneAvailable THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_NO_UNITS;
ELSIF NOT Interlock AND runIn.Request THEN
  stCode := UT_ST_INTERLOCK;
ELSIF NOT runIn.Request THEN
  IF Running THEN stCode := UT_ST_RUN_HAND; ELSE stCode := UT_ST_OFF; END_IF;
ELSIF grp.AllHeld THEN
  stCode := UT_ST_WAIT_STARTS;
ELSIF NOT Permissive AND MAX(Required, 0) > nRun THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSE
  stCode := UT_ST_IDLE_NO_DEMAND;
  FOR k := 7 TO 0 BY -1 DO
    IF k < n THEN
      bit := SHL(DWORD#1, k);
      i := slot[k];
      IF (masks.call AND bit) <> 0 AND (masks.running AND bit) = 0 THEN
        stUnit := i;
        IF masks.skipped <> 0 THEN
          stCode := UT_ST_FAILOVER;
        ELSIF (masks.waiting AND bit) <> 0 THEN
          stCode := UT_ST_RESTART_DELAY;
          tLeft := Units[i].RestartIn();
        ELSIF (masks.exercise AND bit) <> 0 THEN
          stCode := UT_ST_EXERCISING;
        ELSE
          stCode := UT_ST_STARTING;
        END_IF;
      END_IF;
    END_IF;
  END_FOR;
  IF stUnit = 0 THEN
    IF Shortfall THEN
      stCode := UT_ST_SHORTFALL;
    ELSIF masks.exercise <> 0 THEN
      stCode := UT_ST_EXERCISING;
    ELSIF grp.CalledCount < nRun AND need < nRun THEN
      stCode := UT_ST_STOPPING;
    ELSIF Running AND need > 0 THEN
      stCode := UT_ST_RUNNING;
    ELSIF Running THEN
      stCode := UT_ST_RUN_HAND;
    END_IF;
  END_IF;
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
Data.sts.statusUnit := stUnit;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);
Data.sts.lead := Lead;
Data.sts.runningCount := nRun;
Data.sts.calledCount := grp.CalledCount;
Data.sts.availableCount := 0;
FOR k := 0 TO 7 DO
  IF (masks.available AND SHL(DWORD#1, k)) <> 0 THEN
    Data.sts.availableCount := Data.sts.availableCount + 1;
  END_IF;
END_FOR;
Data.sts.running := Running;
Data.sts.shortfall := Shortfall;
Data.sts.exercising := masks.exercise <> 0;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.cfgFault := cfgOn OR grp.CfgFault;
Data.sts.allHeld := grp.AllHeld;
Data.det.rotateIn := grp.RotateIn;
Data.det.nextExerciseIn := grp.ExerciseIn;
Data.det.timeLeft := tLeft;

END_FUNCTION_BLOCK