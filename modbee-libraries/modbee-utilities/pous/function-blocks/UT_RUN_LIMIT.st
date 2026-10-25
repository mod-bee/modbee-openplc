(* UT_RUN_LIMIT — one run of any equipment, limited by time and / or volume,
or held: wire RunCmd to the equipment (pump.Run, a station's Demand) and
its running signal to EquipRunning; time counts only while it runs.

Run per set.run.style (HELD / TOGGLE / KEEPALIVE / PULSE_TIMER), Start
(latched) / Stop (wins). byTime: the run ends after runTime; byVolume:
after targetVolume on the Meter (UT_I_METER: total, rate, health; NULL = no
volume runs); both: whichever first; neither: it runs until its own stop.
A volume run always has a time cap (UT_RUN_CORE). Interlock FALSE ends the
run and refuses a start; Permissive FALSE makes a new run wait; Pause holds
it (RunCmd off, no counting; maxPause ends it); Abort ends it with a code.
RunTime / RunVolume pins (> 0) override the settings for the next run.
Progress is kept over a power cut (UT_RUN_CORE); the last run's volume,
duration and end reason are kept. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_RUN_LIMIT
  VAR_INPUT
    Run : BOOL; (* run request per set.run.style *)
    Start : BOOL R_EDGE; (* start (latched) *)
    Stop : BOOL R_EDGE; (* end the run (wins) *)
    Reset : BOOL R_EDGE; (* clear the fault status *)
    Interlock : BOOL := TRUE; (* FALSE ends the run and refuses a start *)
    Permissive : BOOL := TRUE; (* FALSE: a new run waits *)
    Pause : BOOL; (* hold: RunCmd off, no counting *)
    Abort : BOOL; (* end the run with AbortCode; refuse a start *)
    AbortCode : UT_STOP;
    EquipRunning : BOOL := TRUE; (* counting only while TRUE *)
    RunTime : TIME; (* this run's targets (0 = the settings) *)
    RunVolume : LREAL;
    Meter : UT_I_METER; (* NULL = no volume runs *)
  END_VAR
  VAR_OUTPUT
    RunCmd : BOOL; (* run the equipment *)
    Running : BOOL; (* a run is active *)
    Done : BOOL; (* one scan: the run ended *)
    Fault : BOOL;
    Warning : BOOL;
    Elapsed : TIME;
    TimeLeft : TIME;
    Delivered : LREAL;
    VolumeLeft : LREAL;
  END_VAR
  VAR_IN_OUT
    Data : UT_RUN_LIMIT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_RUN_LIMIT_SET;
    keptGood : BOOL;
    keptTot : UT_RUN_LIMIT_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    runIn : UT_RUN_INPUT;
    core : UT_RUN_CORE;
    ok : BOOL;
    hStart : BOOL;
    hStop : BOOL;
    hReset : BOOL;
    cStart : BOOL;
    cStop : BOOL;
    rtUse : TIME;
    rvUse : LREAL;
    faultShown : BOOL;
    tCur : TIME;
    phaseAt : TIME;
    activePrev : BOOL;
    pauseAt : TIME;
    pausedPrev : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
keep(TotalsNow := core.Done);
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := Data.set.runTime >= T#0s AND Data.set.targetVolume >= 0.0 AND Data.set.targetVolume <= 1.0E15
      AND Data.set.minFlow >= 0.0 AND Data.set.minFlow <= 3.4E38
      AND (Data.set.run.style = UT_RS_HELD OR Data.set.run.style = UT_RS_TOGGLE
           OR (Data.set.run.style = UT_RS_KEEPALIVE AND Data.set.run.keepAlive > T#0s)
           OR (Data.set.run.style = UT_RS_PULSE_TIMER AND Data.set.run.pulseTime > T#0s))
      AND Data.set.core.maxTime >= T#0s AND Data.set.core.maxPause >= T#0s AND Data.set.core.progressSave >= T#0s
      AND Data.set.core.defaultCap > T#0s AND Data.set.core.meterFailTime > T#0s
      AND (Data.set.core.powerUp = UT_RPU_RESUME OR Data.set.core.powerUp = UT_RPU_RESTART OR Data.set.core.powerUp = UT_RPU_NONE);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
cStart := Data.cmdStart AND NOT hStart;
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
cStop := Data.cmdStop AND NOT hStop;
hStop := Data.cmdStop;
Data.cmdStop := FALSE;

(* this run's targets *)
rtUse := T#0s;
rvUse := 0.0;
IF RunTime > T#0s THEN
  rtUse := RunTime;
ELSIF Data.set.byTime THEN
  rtUse := Data.set.runTime;
END_IF;
IF RunVolume > 0.0 THEN
  rvUse := RunVolume;
ELSIF Data.set.byVolume THEN
  rvUse := Data.set.targetVolume;
END_IF;

runIn(Run := Run, Start := Start, Stop := Stop, CmdStart := cStart, CmdStop := cStop,
      Drop := NOT Interlock OR Abort OR core.Done, Linked := FALSE, TargetDone := core.Done,
      HasTarget := rtUse > T#0s OR rvUse > 0.0, Set := Data.set.run);
core(Request := runIn.Request AND Interlock, StopEdge := Stop OR cStop, Latched := runIn.Latched, Permissive := Permissive,
     Pause := Pause, Counting := EquipRunning, Abort := Abort OR NOT Interlock,
     AbortCode := SEL(Interlock, UT_STOP_INTERLOCK, AbortCode), Part := FALSE, EndAtTarget := TRUE,
     RunTime := rtUse, RunVolume := rvUse, MaxTime := Data.set.core.maxTime, MinFlow := Data.set.minFlow,
     Finish := FALSE, Meter := Meter, Set := Data.set.core);

RunCmd := core.Active AND NOT Pause AND Interlock;
Running := core.Active;
Done := core.Done;
Elapsed := core.Elapsed;
TimeLeft := core.TimeLeft;
Delivered := core.Delivered;
VolumeLeft := core.VolumeLeft;
IF core.Done THEN
  Data.sts.runs := Data.sts.runs + 1;
  Data.tot.lastVolume := core.Delivered;
  Data.tot.lastDuration := core.Elapsed;
  Data.tot.lastEndReason := core.StopReason;
  Data.sts.stopReason := core.StopReason;
  faultShown := core.StopReason = UT_STOP_METER_FAILED OR core.StopReason = UT_STOP_SETTING;
  IF faultShown THEN
    Data.sts.trips := Data.sts.trips + 1;
    Data.sts.lastFault := core.FaultId;
  END_IF;
END_IF;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;
IF Reset OR (Data.cmdReset AND NOT hReset) OR core.Active THEN
  faultShown := FALSE;
END_IF;
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
Fault := core.CfgFault OR faultShown;
Warning := core.Warning OR NOT ok OR runIn.BadSetting;

IF core.Active <> activePrev THEN
  phaseAt := tCur;
END_IF;
activePrev := core.Active;
IF core.Paused AND NOT pausedPrev THEN
  pauseAt := tCur;
END_IF;
pausedPrev := core.Paused;
Data.det.phaseTime := tCur - phaseAt;
IF core.Paused THEN
  Data.det.pauseTime := tCur - pauseAt;
ELSE
  Data.det.pauseTime := T#0s;
END_IF;
Data.det.elapsed := core.Elapsed;
Data.det.timeLeft := core.TimeLeft;

stF := UT_F_NONE;
IF core.CfgFault THEN
  stCode := UT_ST_CONFIG;
  stF := core.FaultId;
ELSIF faultShown THEN
  stCode := UT_ST_FAULT;
  stF := core.FaultId;
ELSIF NOT Interlock AND (Run OR runIn.Latched) THEN
  stCode := UT_ST_INTERLOCK;
ELSIF core.Waiting THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSIF core.Active AND Pause THEN
  stCode := UT_ST_PAUSED_HOLD;
ELSIF core.Active AND core.Warning THEN
  stCode := UT_ST_WARNING;
  stF := core.FaultId;
ELSIF core.Active THEN
  stCode := UT_ST_RUNNING;
ELSIF NOT ok OR runIn.BadSetting THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF Data.sts.stopReason <> UT_STOP_NONE THEN
  stCode := UT_ST_STOPPED;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  IF stCode = UT_ST_STOPPED THEN
    Data.sts.statusText := UT_STOP_TEXT(Data.sts.stopReason);
  ELSE
    Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
  END_IF;
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.active := core.Active;
Data.sts.paused := core.Paused;
Data.sts.waiting := core.Waiting;
Data.sts.configBad := core.CfgFault;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.delivered := core.Delivered;
Data.sts.volumeLeft := core.VolumeLeft;
Data.sts.timeCap := core.TimeCap;

END_FUNCTION_BLOCK