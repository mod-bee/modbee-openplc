(* UT_ZONE_SEQ — irrigation / wash-down zone program (features frozen): the
zones (Zones, the project's UT_ZONE instances in run order, each with its
own valve and settings) watered in turn by time and / or volume, cycles
with soak (while a zone soaks the next ones run), repeats, rain action,
per-zone pressure and flow band, a one-zone run, the master valve, the
dosing hook. UT_RUN_CORE times each zone cycle (one part each); the zones
keep their own progress, the program its pass and place (exact resume).

Valves and pump, in this order, so the pump never deadheads or hammers:
  start   the zone valve opens; pumpStartDelay later, once it is proven
          (its valve IsOpen; no valve: RouteOk) and the master valve is
          open, PumpDemand comes on
  change  the next valve opens; valveOverlap later (proven) the last closes
  end     PumpDemand goes off; the valves close once valveCloseDelay has
          passed AND PumpRunning has gone; the master masterCloseDelay later
Water counts only while PumpRunning and not PumpFault. Pause (pin, cmdPause
until a Start), a rain PAUSE and a soak with nothing else ready stop the
pump and close the valves as at the end; the zone keeps its time.

Run (per set.run.style) / Start / cmdStart run the program; Stop / cmdStop
end it safely. RunZone (or cmdRunZone) = only that zone, one pass;
RunTime / RunVolume / DoseReq read at the start. Off (Mode 0 / set.mode),
Interlock FALSE, IrrigatorStop, LevelEnd, Abort, rain CANCEL, the meter
failed, a master valve fault and maxPumpWait end the program safely and
refuse a start; the status shows why until the next start. Skip / cmdSkip
ends the zone watering now; a flow trip or a valve not proven within
valveLostDelay ends that zone; maxPumpWait ends the program or, with
pumpWaitSkips, the zone. Permissive FALSE holds back the start of the
program or of the next zone (a watering zone carries on). DoseEnable: this
run doses; DoseHold: no zone watering with time left beyond flushTime.
Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_ZONE_SEQ
  VAR_INPUT
    Run : BOOL; (* run request per set.run.style *)
    Start : BOOL R_EDGE; (* run the program (latched); resumes a pause *)
    Stop : BOOL R_EDGE; (* end it safely (wins) *)
    Reset : BOOL R_EDGE; (* clear the fault status *)
    Mode : INT := -1; (* 0 Off, 2 Auto (acts on change; Hand / OOS refused) *)
    Interlock : BOOL := TRUE; (* FALSE ends the program safely, refuses a start *)
    Permissive : BOOL := TRUE; (* holds back the start of the program / next zone *)
    Pause : BOOL; (* pump off, valves closed, time kept *)
    Skip : BOOL R_EDGE; (* skip the zone watering now *)
    RainHold : BOOL; (* per set.rainAction *)
    LevelEnd : BOOL; (* the source at its stop level: end *)
    IrrigatorStop : BOOL; (* the irrigator fail-safe: end, refuse a start *)
    Abort : BOOL; (* end, refuse a start *)
    AbortCode : UT_STOP;
    PumpRunning : BOOL; (* the supply delivers *)
    PumpFault : BOOL; (* the supply tripped *)
    RouteOk : BOOL := TRUE; (* zones with no valve link: the outlet path is proven *)
    RunZone : INT; (* at the start: 0 = the program; n = only zone n *)
    RunTime : TIME; (* at the start: each zone's time this run (0 = its own) *)
    RunVolume : LREAL; (* at the start: each zone's volume this run (0 = its own) *)
    DoseReq : INT := -1; (* at the start: -1 = set.dose, 0 no, 1 dose this run *)
    Clock : DT; (* for each zone's lastRun *)
    Meter : UT_I_METER; (* volume zones, flow band, delivered *)
    MasterValve : UT_I_VALVE; (* NULL = none (sts.masterWanted) *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL; (* a run is active *)
    PumpDemand : BOOL; (* ask the supply for water *)
    DoseEnable : BOOL; (* this run doses (-> dose.Run) *)
    DoseHold : BOOL; (* pause injection now (-> dose.Hold) *)
    ZoneSp : REAL; (* the active zone's pressure *)
    ActiveZone : INT; (* the zone watering (0 none) *)
    Busy : BOOL; (* running or closing *)
    Done : BOOL; (* one scan: the program ended *)
    Fault : BOOL;
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Zones : ARRAY [*] OF UT_ZONE;
    Data : UT_ZONE_SEQ_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ZONE_SEQ_SET;
    keptGood : BOOL;
    rPass : INT; (* progress (exact resume); each zone keeps its own *)
    rZone : INT;
    rRunZone : INT;
    rRunTime : TIME;
    rRunVolume : LREAL;
    rDose : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    runIn : UT_RUN_INPUT;
    core : UT_RUN_CORE;
    ok : BOOL;
    cfgF : UT_FAULT;
    cfgW : UT_FAULT;
    cfgOn : BOOL;
    noZoneShown : BOOL; (* a start was refused for it: shown until a zone is enabled / reset *)
    noZone : BOOL; (* no zone enabled: a program start is refused (a one-zone run still works) *)
    tCur : TIME;
    x : BOOL;
    lo : DINT;
    n : INT; (* zones (up to 32) *)
    k : INT;
    j : INT;
    zs : UT_ZONE_SET;
    hStart : BOOL;
    hStop : BOOL;
    hPause : BOOL;
    hSkip : BOOL;
    hReset : BOOL;
    modePrev : INT := -1;
    modeRefused : BOOL;
    startReq : BOOL;
    stopReq : BOOL;
    skipReq : BOOL;
    resetReq : BOOL;
    zoneReq : INT; (* cmdRunZone this scan *)
    hmiPause : BOOL;
    endWhy : UT_STOP; (* what ends the program / refuses a start now *)
    active : BOOL;
    activePrev : BOOL;
    cur : INT; (* the zone whose valve is wanted (watering / opening), 0 none *)
    prevZ : INT; (* the zone still open in an overlap *)
    nxt : INT;
    ph : UT_ZONE_PHASE;
    phPrev : UT_ZONE_PHASE;
    phaseAt : TIME;
    openAt : TIME;
    closeAt : TIME;
    ovAt : TIME;
    lastValveAt : TIME;
    proven : BOOL;
    provenNx : BOOL;
    curWants : BOOL; (* the cur zone's valve open *)
    prevWants : BOOL;
    pumpOn : BOOL;
    counting : BOOL;
    hold : BOOL; (* pause / rain / soak: pump off, valves closed *)
    soakWait : BOOL;
    partNow : BOOL;
    finishNow : BOOL;
    cycleEnd : UT_STOP; (* the cur zone's cycle ends now with this *)
    anyLeft : BOOL;
    tgtT : TIME;
    tgtV : LREAL;
    useT : TIME;
    useV : LREAL;
    capT : TIME;
    waitAcc : TIME;
    tPrev : TIME;
    lostAt : TIME;
    lostOn : BOOL;
    masterWanted : BOOL;
    masterOk : BOOL;
    masterFault : BOOL;
    mLostAt : TIME;
    mLostOn : BOOL;
    rate : REAL;
    rateGood : BOOL;
    zero : REAL;
    nan : REAL;
    started : BOOL;
    blockedAt : TIME;
    blockedOn : BOOL;
    faultEnd : BOOL; (* the last end was a fault: shown until the next start *)
    flowWarn : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    partOpen : BOOL; (* the core's part belongs to partZone and has not ended *)
    partZone : INT;
    permHold : BOOL; (* Permissive FALSE holds back the next zone *)
  END_VAR


tCur := TIME();
IF NOT started THEN
  started := TRUE;
  nan := zero / zero;
  tPrev := tCur;
  phaseAt := tCur;
END_IF;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_ZONE_SEQ_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN Data.sts.refused := cfgF; ELSE Data.sts.refused := cfgW; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_ZONE_SEQ_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
lo := LOWER_BOUND(Zones, 1);
n := DINT_TO_INT(MIN(UPPER_BOUND(Zones, 1) - lo + 1, 32));
cfgOn := cfgF <> UT_F_NONE OR n < 1;
noZone := n >= 1;
FOR k := 1 TO n DO
  IF Zones[lo + INT_TO_DINT(k) - 1].IsEnabled() THEN noZone := FALSE; END_IF;
END_FOR;

(* commands: once per request *)
startReq := Start OR (Data.cmdStart AND NOT hStart);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
stopReq := Stop OR (Data.cmdStop AND NOT hStop);
hStop := Data.cmdStop;
Data.cmdStop := FALSE;
skipReq := Skip OR (Data.cmdSkip AND NOT hSkip);
hSkip := Data.cmdSkip;
Data.cmdSkip := FALSE;
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
IF Data.cmdPause AND NOT hPause THEN
  hmiPause := TRUE;
END_IF;
hPause := Data.cmdPause;
Data.cmdPause := FALSE;
zoneReq := 0;
IF Data.cmdRunZone >= 1 AND Data.cmdRunZone <= n THEN
  zoneReq := Data.cmdRunZone;
END_IF;
Data.cmdRunZone := -1;
IF NOT noZone OR resetReq THEN
  noZoneShown := FALSE;
ELSIF startReq AND zoneReq = 0 AND NOT core.Active THEN
  noZoneShown := TRUE;           (* a site without irrigation is not nagged: only a refused start shows it *)
END_IF;
IF noZoneShown AND cfgW = UT_F_NONE THEN
  cfgW := UT_F_NO_ZONE_ENABLED;
END_IF;
IF startReq THEN
  hmiPause := FALSE;             (* a Start resumes an HMI pause *)
END_IF;
IF Mode <> modePrev THEN
  IF Mode = 0 THEN
    Data.set.mode := UT_MODE_OFF;
    modeRefused := FALSE;
  ELSIF Mode = 2 THEN
    Data.set.mode := UT_MODE_AUTO;
    modeRefused := FALSE;
  ELSIF Mode = 1 OR Mode = 3 THEN
    modeRefused := TRUE;         (* Hand / OOS: a program has none *)
  END_IF;
  modePrev := Mode;
END_IF;

(* what ends the program and refuses a start *)
endWhy := UT_STOP_NONE;
IF cfgOn THEN
  endWhy := UT_STOP_SETTING;
ELSIF Data.set.mode = UT_MODE_OFF THEN
  endWhy := UT_STOP_SWITCHED_OFF;
ELSIF noZone AND NOT core.Active AND zoneReq = 0 THEN
  endWhy := UT_STOP_SETTING;     (* no zone enabled: refused, shown as a configuration problem *)
ELSIF NOT Interlock THEN
  endWhy := UT_STOP_INTERLOCK;
ELSIF IrrigatorStop THEN
  endWhy := UT_STOP_IRRIGATOR;
ELSIF Abort THEN
  IF AbortCode = UT_STOP_NONE THEN endWhy := UT_STOP_ABORTED; ELSE endWhy := AbortCode; END_IF;
ELSIF LevelEnd AND core.Active THEN
  endWhy := UT_STOP_LEVEL_END;
ELSIF RainHold AND Data.set.rainAction = UT_RAIN_CANCEL AND core.Active THEN
  endWhy := UT_STOP_RAIN;
ELSIF masterFault THEN
  endWhy := UT_STOP_FAULT;
ELSIF Data.set.maxPumpWait > T#0s AND waitAcc >= Data.set.maxPumpWait AND NOT Data.set.pumpWaitSkips THEN
  endWhy := UT_STOP_PUMP_FAULT;
END_IF;

(* the request *)
runIn(Run := Run, Start := startReq OR (zoneReq > 0 AND NOT core.Active), Stop := stopReq OR core.Done, CmdStart := FALSE,
      CmdStop := FALSE, Drop := endWhy <> UT_STOP_NONE, Linked := FALSE, TargetDone := FALSE, HasTarget := FALSE,
      Set := Data.set.run);
IF zoneReq > 0 AND core.Active THEN
  blockedOn := TRUE;             (* a request while busy: refused, nothing changes *)
  blockedAt := tCur;
END_IF;
IF blockedOn AND tCur - blockedAt >= T#10s THEN
  blockedOn := FALSE;
END_IF;

(* a new run: read the run's values; a resumed run: back where it was *)
active := core.Active;
IF core.Resumed THEN
  cur := 0;                      (* the valves start closed; the zone resumes its part *)
  prevZ := 0;
  partOpen := rZone > 0;
  partZone := rZone;
ELSIF active AND NOT activePrev THEN
  IF zoneReq > 0 THEN rRunZone := zoneReq;
  ELSIF RunZone >= 1 AND RunZone <= n THEN rRunZone := RunZone;
  ELSE rRunZone := 0;
  END_IF;
  rRunTime := RunTime;
  rRunVolume := RunVolume;
  IF DoseReq = 0 THEN rDose := FALSE;
  ELSIF DoseReq = 1 THEN rDose := TRUE;
  ELSE rDose := Data.set.dose;
  END_IF;
  rPass := 1;
  rZone := 0;
  FOR k := 1 TO n DO
    x := Zones[lo + INT_TO_DINT(k) - 1].NewRun();
  END_FOR;
  Data.sts.programDelivered := 0.0;
  faultEnd := FALSE;
  flowWarn := FALSE;
  waitAcc := T#0s;
  cur := 0;
  prevZ := 0;
  partOpen := FALSE;
END_IF;
activePrev := active;

(* the meter *)
rate := 0.0;
rateGood := FALSE;
IF Meter <> NULL THEN
  rate := Meter.GetValue();
  rateGood := Meter.GoodNow();
END_IF;

(* the cur zone's cycle ends now? (the core's results from last scan) *)
cycleEnd := UT_STOP_NONE;
IF NOT (partOpen AND partZone = cur) THEN
  ;                              (* no part of this zone running *)
ELSIF cur > 0 AND (ph = UT_ZS_WATERING OR ph = UT_ZS_PUMP_FAULT) THEN
  IF core.TargetReached THEN
    cycleEnd := UT_STOP_DONE;
  ELSIF core.Capped THEN
    cycleEnd := UT_STOP_TIME_CAP;
  END_IF;
END_IF;
IF cur > 0 AND active AND partOpen AND partZone = cur THEN
  IF skipReq THEN
    cycleEnd := UT_STOP_OPERATOR;
  ELSIF NOT Zones[lo + INT_TO_DINT(cur) - 1].IsUsable() THEN
    cycleEnd := UT_STOP_FAULT;   (* flow trip, valve refused, bad setting *)
  ELSIF lostOn AND tCur - lostAt >= Data.set.valveLostDelay + Data.set.pumpStartDelay THEN
    cycleEnd := UT_STOP_NOT_PROVEN;
  ELSIF RainHold AND Data.set.rainAction = UT_RAIN_SKIP THEN
    cycleEnd := UT_STOP_RAIN;
  ELSIF Data.set.maxPumpWait > T#0s AND waitAcc >= Data.set.maxPumpWait AND Data.set.pumpWaitSkips THEN
    cycleEnd := UT_STOP_PUMP_FAULT;
  END_IF;
END_IF;
IF cycleEnd <> UT_STOP_NONE THEN
  x := Zones[lo + INT_TO_DINT(cur) - 1].EndCycle(Result := cycleEnd, When := Clock);
  IF cycleEnd = UT_STOP_FAULT THEN flowWarn := TRUE; END_IF;
  IF cycleEnd = UT_STOP_TIME_CAP THEN flowWarn := TRUE; END_IF;
  waitAcc := T#0s;
  lostOn := FALSE;
  partOpen := FALSE;
END_IF;

(* the next zone ready: in order, not done, in this run, not soaking *)
nxt := 0;
anyLeft := FALSE;
partNow := FALSE;
finishNow := FALSE;
IF active THEN
  FOR k := 1 TO n DO
    j := k;
    IF (rRunZone = 0 AND Zones[lo + INT_TO_DINT(j) - 1].IsEnabled()) OR (rRunZone = j AND Zones[lo + INT_TO_DINT(j) - 1].IsUsable()) THEN
      IF NOT Zones[lo + INT_TO_DINT(j) - 1].IsDone() THEN
        IF RainHold AND Data.set.rainAction = UT_RAIN_SKIP AND j <> cur THEN
          x := Zones[lo + INT_TO_DINT(j) - 1].EndCycle(Result := UT_STOP_RAIN, When := Clock);
        ELSE
          anyLeft := TRUE;
          IF nxt = 0 AND Zones[lo + INT_TO_DINT(j) - 1].SoakLeft() <= T#0s
             AND (cycleEnd = UT_STOP_NONE OR j <> cur OR NOT Zones[lo + INT_TO_DINT(j) - 1].IsDone()) THEN
            nxt := j;
          END_IF;
        END_IF;
      END_IF;
    END_IF;
  END_FOR;
  IF rZone > 0 AND rZone <= n AND nxt > 0 THEN
    IF NOT Zones[lo + INT_TO_DINT(rZone) - 1].IsDone() AND Zones[lo + INT_TO_DINT(rZone) - 1].SoakLeft() <= T#0s
       AND (Zones[lo + INT_TO_DINT(rZone) - 1].IsEnabled() OR rRunZone = rZone) THEN
      nxt := rZone;              (* a paused / resumed zone first *)
    END_IF;
  END_IF;
  IF NOT anyLeft THEN
    (* the pass is done *)
    IF rPass < Data.set.repeats AND rRunZone = 0 THEN
      rPass := rPass + 1;
      FOR k := 1 TO n DO
        x := Zones[lo + INT_TO_DINT(k) - 1].NewRun();
      END_FOR;
    ELSE
      finishNow := TRUE;
    END_IF;
  END_IF;
END_IF;

(* hold: pump off, valves closed, the zone keeps its time *)
hold := Pause OR hmiPause OR (RainHold AND Data.set.rainAction = UT_RAIN_PAUSE);
permHold := FALSE;
IF NOT Permissive AND nxt > 0 AND nxt <> cur AND (cur = 0 OR cycleEnd <> UT_STOP_NONE) THEN
  permHold := TRUE;              (* the next zone waits; the ended one closes *)
  nxt := 0;
END_IF;
soakWait := FALSE;
IF active AND anyLeft AND nxt = 0 THEN
  IF cur = 0 OR cycleEnd <> UT_STOP_NONE THEN
    soakWait := TRUE;            (* IEC OR does not short-circuit: index only when cur > 0 *)
  ELSIF Zones[lo + INT_TO_DINT(cur) - 1].IsDone() OR Zones[lo + INT_TO_DINT(cur) - 1].SoakLeft() > T#0s THEN
    soakWait := TRUE;
  END_IF;
END_IF;

(* the valve and pump sequence *)
IF NOT active OR finishNow OR endWhy <> UT_STOP_NONE THEN
  (* the end: pump off, then the valves *)
  IF pumpOn THEN
    pumpOn := FALSE;
    closeAt := tCur;
  END_IF;
  IF cur > 0 OR prevZ > 0 THEN
    IF ph <> UT_ZS_CLOSING THEN
      ph := UT_ZS_CLOSING;
      closeAt := tCur;
    END_IF;
    IF tCur - closeAt >= Data.set.valveCloseDelay AND NOT PumpRunning THEN
      cur := 0;
      prevZ := 0;
    END_IF;
  END_IF;
  IF cur = 0 AND prevZ = 0 THEN
    ph := UT_ZS_IDLE;
  END_IF;
ELSIF hold OR soakWait OR permHold OR (cycleEnd <> UT_STOP_NONE AND nxt = 0) THEN
  (* pause / rain / soak / the zone ended with none ready: close as at the end *)
  IF pumpOn THEN
    pumpOn := FALSE;
    closeAt := tCur;
  END_IF;
  IF cur > 0 OR prevZ > 0 THEN
    IF ph <> UT_ZS_CLOSING THEN
      ph := UT_ZS_CLOSING;
      closeAt := tCur;
    END_IF;
    IF tCur - closeAt >= Data.set.valveCloseDelay AND NOT PumpRunning THEN
      IF hold AND cycleEnd = UT_STOP_NONE AND cur > 0 THEN
        IF NOT Zones[lo + INT_TO_DINT(cur) - 1].IsDone() THEN
          rZone := cur;          (* paused: this zone resumes *)
        END_IF;
      END_IF;
      cur := 0;
      prevZ := 0;
    END_IF;
  END_IF;
  IF cur = 0 AND prevZ = 0 THEN
    IF hold AND (RainHold AND Data.set.rainAction = UT_RAIN_PAUSE) THEN ph := UT_ZS_RAIN;
    ELSIF hold THEN ph := UT_ZS_PAUSED;
    ELSIF permHold THEN ph := UT_ZS_HELD;
    ELSE ph := UT_ZS_SOAKING;
    END_IF;
  END_IF;
ELSIF cur = 0 THEN
  (* start a zone: its valve first; a zone that was paused carries on with its part *)
  IF nxt > 0 THEN
    cur := nxt;
    rZone := cur;
    ph := UT_ZS_OPENING;
    openAt := tCur;
    lostOn := FALSE;
    partNow := NOT (partOpen AND partZone = cur);
  END_IF;
ELSIF cycleEnd <> UT_STOP_NONE AND nxt > 0 THEN
  (* the next zone: overlap (or the same zone's next cycle at once) *)
  IF nxt = cur THEN
    partNow := TRUE;
  ELSE
    prevZ := cur;
    cur := nxt;
    rZone := cur;
    ph := UT_ZS_OVERLAP;
    ovAt := tCur;
    partNow := TRUE;
  END_IF;
END_IF;
IF partNow THEN
  partOpen := TRUE;
  partZone := cur;
END_IF;

(* proving, the pump, the overlap *)
proven := FALSE;
IF cur > 0 THEN
  IF Zones[lo + INT_TO_DINT(cur) - 1].HasValve() THEN
    proven := Zones[lo + INT_TO_DINT(cur) - 1].IsProven();
  ELSE
    proven := RouteOk;
  END_IF;
END_IF;
masterOk := MasterValve = NULL;
IF MasterValve <> NULL THEN
  masterOk := MasterValve.IsOpenNow();
END_IF;
IF active AND NOT finishNow AND endWhy = UT_STOP_NONE AND NOT hold AND NOT soakWait AND cur > 0 THEN
  IF ph = UT_ZS_OPENING THEN
    IF tCur - openAt >= Data.set.pumpStartDelay AND proven AND masterOk THEN
      pumpOn := TRUE;
      ph := UT_ZS_WATERING;
    END_IF;
  ELSIF ph = UT_ZS_OVERLAP THEN
    pumpOn := TRUE;
    IF tCur - ovAt >= Data.set.valveOverlap AND proven THEN
      prevZ := 0;
      ph := UT_ZS_WATERING;
    END_IF;
  ELSIF ph = UT_ZS_HELD OR ph = UT_ZS_CLOSING OR ph = UT_ZS_PAUSED OR ph = UT_ZS_RAIN OR ph = UT_ZS_SOAKING THEN
    ph := UT_ZS_OPENING;
    openAt := tCur;
  END_IF;
  IF ph = UT_ZS_WATERING OR ph = UT_ZS_PUMP_FAULT THEN
    IF NOT PumpRunning OR PumpFault THEN
      ph := UT_ZS_PUMP_FAULT;
    ELSE
      ph := UT_ZS_WATERING;
    END_IF;
  END_IF;
  (* a linked valve not open when wanted *)
  IF NOT proven AND ph <> UT_ZS_OVERLAP THEN
    IF NOT lostOn THEN
      lostOn := TRUE;
      lostAt := tCur;
    END_IF;
  ELSE
    lostOn := FALSE;
  END_IF;
ELSE
  lostOn := FALSE;
END_IF;
counting := active AND cur > 0 AND ph = UT_ZS_WATERING AND PumpRunning AND NOT PumpFault AND proven;
IF active AND cur > 0 AND (ph = UT_ZS_WATERING OR ph = UT_ZS_PUMP_FAULT) AND NOT counting THEN
  waitAcc := waitAcc + (tCur - tPrev);
ELSIF counting THEN
  waitAcc := T#0s;
END_IF;
tPrev := tCur;

(* the master valve *)
IF cur > 0 OR prevZ > 0 THEN
  lastValveAt := tCur;
END_IF;
masterWanted := cur > 0 OR prevZ > 0 OR (Busy AND tCur - lastValveAt < Data.set.masterCloseDelay);
IF MasterValve <> NULL THEN
  IF NOT MasterValve.Request(ReqOpen := masterWanted, ReqPos := nan, Owner := CONCAT(Data.set.tag, ' MV')) THEN
    masterFault := masterWanted;
  END_IF;
  IF masterWanted AND NOT masterOk THEN
    IF NOT mLostOn THEN
      mLostOn := TRUE;
      mLostAt := tCur;
    END_IF;
    IF tCur - mLostAt >= Data.set.valveLostDelay + Data.set.pumpStartDelay THEN
      masterFault := TRUE;
    END_IF;
  ELSE
    mLostOn := FALSE;
  END_IF;
END_IF;
IF resetReq OR (NOT active AND NOT masterWanted) THEN
  masterFault := FALSE;
END_IF;

(* the zone targets for a new part *)
IF cur > 0 THEN
  zs := Zones[lo + INT_TO_DINT(cur) - 1].Settings();
END_IF;
useT := zs.runTime;
useV := zs.volume;
IF rRunTime > T#0s OR rRunVolume > 0.0 THEN
  useT := rRunTime;
  useV := rRunVolume;
END_IF;
tgtT := T#0s;
tgtV := 0.0;
CASE zs.endBy OF
UT_ZE_TIME: tgtT := useT;
UT_ZE_VOLUME: tgtV := useV;
UT_ZE_FIRST: tgtT := useT; tgtV := useV;
UT_ZE_UNTIL_STOP: ;
ELSE
  IF useV > 0.0 THEN tgtV := useV; ELSE tgtT := useT; END_IF;
END_CASE;
IF Meter = NULL THEN
  tgtV := 0.0;
END_IF;
IF zs.cycles > 1 THEN
  tgtT := tgtT / zs.cycles;
  tgtV := tgtV / INT_TO_LREAL(zs.cycles);
  capT := Data.set.core.maxTime / zs.cycles;
ELSE
  capT := Data.set.core.maxTime;
END_IF;

(* the run core: one part per zone cycle *)
core(Request := runIn.Request AND NOT runIn.BadSetting, StopEdge := runIn.StopEdge, Latched := runIn.Latched,
     Permissive := Permissive, Pause := hold, Counting := counting, Abort := endWhy <> UT_STOP_NONE AND core.Active,
     AbortCode := endWhy, Part := partNow, EndAtTarget := FALSE, RunTime := tgtT, RunVolume := tgtV, MaxTime := capT,
     MinFlow := zs.minFlow, Finish := finishNow, Meter := Meter, Set := Data.set.core);
IF core.Done THEN
  Data.sts.stopReason := core.StopReason;
  Data.sts.endZone := cur;
  IF core.StopReason = UT_STOP_DONE THEN
    Data.sts.runs := Data.sts.runs + 1;
  END_IF;
  faultEnd := core.StopReason = UT_STOP_FAULT OR core.StopReason = UT_STOP_PUMP_FAULT
              OR core.StopReason = UT_STOP_METER_FAILED OR core.StopReason = UT_STOP_SETTING;
  IF faultEnd THEN
    Data.sts.trips := Data.sts.trips + 1;
    IF masterFault THEN Data.sts.lastFault := UT_F_MASTER_VALVE;
    ELSIF core.StopReason = UT_STOP_PUMP_FAULT THEN Data.sts.lastFault := UT_F_PUMP_FAULT;
    ELSIF core.StopReason = UT_STOP_METER_FAILED THEN Data.sts.lastFault := UT_F_METER_FAILED;
    ELSE Data.sts.lastFault := cfgF;
    END_IF;
  END_IF;
  rZone := 0;
  hmiPause := FALSE;
  partOpen := FALSE;
END_IF;
IF NOT core.Active AND NOT core.Waiting AND endWhy <> UT_STOP_NONE AND (startReq OR zoneReq > 0) THEN
  Data.sts.stopReason := endWhy; (* a start refused: why *)
END_IF;
IF resetReq THEN
  faultEnd := FALSE;
END_IF;
IF core.Active THEN
  Data.sts.programDelivered := core.RunDelivered;
END_IF;

(* every zone is commanded every scan *)
FOR k := 1 TO n DO
  curWants := (k = cur OR k = prevZ);
  IF k = cur AND partOpen AND partZone = cur AND (ph = UT_ZS_WATERING OR ph = UT_ZS_PUMP_FAULT OR ph = UT_ZS_OPENING OR ph = UT_ZS_OVERLAP
                  OR ph = UT_ZS_CLOSING OR ph = UT_ZS_HELD) THEN
    x := Zones[lo + INT_TO_DINT(k) - 1].Water(On := curWants, No := k, Owner := Data.set.tag, Rate := rate,
                                              RateGood := rateGood, Ms := TIME_TO_LINT(core.Elapsed), Vol := core.Delivered);
  ELSE
    x := Zones[lo + INT_TO_DINT(k) - 1].Water(On := curWants, No := k, Owner := Data.set.tag, Rate := rate,
                                              RateGood := rateGood, Ms := 0, Vol := 0.0);
  END_IF;
END_FOR;

(* outputs *)
Running := core.Active;
PumpDemand := pumpOn;
Busy := core.Active OR cur > 0 OR prevZ > 0;
Done := core.Done;
IF cur > 0 AND (ph = UT_ZS_WATERING OR ph = UT_ZS_PUMP_FAULT OR ph = UT_ZS_OVERLAP OR ph = UT_ZS_OPENING) THEN
  ActiveZone := cur;
ELSE
  ActiveZone := 0;
END_IF;
ZoneSp := Data.set.defaultSp;
IF ActiveZone > 0 AND zs.sp > 0.0 THEN
  ZoneSp := zs.sp;
END_IF;
DoseEnable := core.Active AND rDose;
DoseHold := NOT (counting AND zs.dose AND (zs.endBy = UT_ZE_UNTIL_STOP OR core.TimeLeft > Data.set.flushTime));
Fault := cfgOn OR masterFault OR faultEnd;
Warning := cfgW <> UT_F_NONE OR flowWarn OR modeRefused OR core.Warning;
Data.sts.configZone := 0;
FOR k := n TO 1 BY -1 DO
  IF Zones[lo + INT_TO_DINT(k) - 1].HasFault() AND NOT Zones[lo + INT_TO_DINT(k) - 1].IsUsable() THEN
    Data.sts.configZone := k;
  END_IF;
END_FOR;

(* status *)
IF ph <> phPrev THEN
  phPrev := ph;
  phaseAt := tCur;
END_IF;
stF := UT_F_NONE;
tLeft := T#0s;
IF cfgOn THEN
  stCode := UT_ST_CONFIG;
  IF n < 1 THEN stF := UT_F_NO_UNITS; ELSE stF := cfgF; END_IF;
ELSIF masterFault THEN
  stCode := UT_ST_FAULT;
  stF := UT_F_MASTER_VALVE;
ELSIF noZoneShown AND NOT core.Active THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_NO_ZONE_ENABLED;
ELSIF blockedOn THEN
  stCode := UT_ST_START_BLOCKED;
ELSIF NOT core.Active AND cur > 0 THEN
  stCode := UT_ST_STOPPING;
  tLeft := Data.set.valveCloseDelay - (tCur - closeAt);
ELSIF NOT core.Active AND core.Waiting THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSIF NOT core.Active AND (faultEnd OR Data.sts.stopReason <> UT_STOP_NONE) THEN
  stCode := UT_ST_STOPPED;
ELSIF NOT core.Active THEN
  IF Data.set.mode = UT_MODE_OFF THEN stCode := UT_ST_OFF; ELSE stCode := UT_ST_IDLE; END_IF;
ELSIF ph = UT_ZS_PAUSED AND hmiPause THEN
  stCode := UT_ST_PAUSED_START;
ELSIF ph = UT_ZS_PAUSED THEN
  stCode := UT_ST_PAUSED_INPUT;
ELSIF ph = UT_ZS_RAIN THEN
  stCode := UT_ST_PAUSED_RAIN;
ELSIF ph = UT_ZS_SOAKING THEN
  stCode := UT_ST_SOAK;
ELSIF ph = UT_ZS_HELD THEN
  stCode := UT_ST_NOT_PERMITTED;
ELSIF ph = UT_ZS_PUMP_FAULT THEN
  IF PumpFault THEN stCode := UT_ST_PUMP_FAULT_HOLD; ELSE stCode := UT_ST_WAIT_PUMP; END_IF;
  IF Data.set.maxPumpWait > T#0s THEN tLeft := Data.set.maxPumpWait - waitAcc; END_IF;
ELSIF ph = UT_ZS_OPENING AND NOT proven THEN
  stCode := UT_ST_WAIT_PROVEN;
ELSIF ph = UT_ZS_OPENING THEN
  stCode := UT_ST_OPENING;
  tLeft := Data.set.pumpStartDelay - (tCur - openAt);
ELSIF ph = UT_ZS_CLOSING THEN
  stCode := UT_ST_STOPPING;
  tLeft := Data.set.valveCloseDelay - (tCur - closeAt);
ELSIF Warning THEN
  stCode := UT_ST_WARNING;
  IF flowWarn THEN stF := UT_F_ZONE_FLOW; ELSIF cfgW <> UT_F_NONE THEN stF := cfgW; ELSE stF := core.FaultId; END_IF;
ELSIF zs.endBy = UT_ZE_UNTIL_STOP AND ActiveZone > 0 THEN
  stCode := UT_ST_RUN_UNTIL_STOP;
ELSE
  stCode := UT_ST_RUN_ZONE;
  tLeft := core.TimeLeft;
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
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
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := Data.set.mode = UT_MODE_OFF, OutOfSpec := Warning, Maint := FALSE);
Data.sts.phase := ph;
Data.sts.activeZone := ActiveZone;
Data.sts.pass := rPass;
Data.sts.runZone := rRunZone;
Data.sts.running := core.Active;
Data.sts.paused := ph = UT_ZS_PAUSED OR ph = UT_ZS_RAIN;
Data.sts.waiting := core.Waiting OR ph = UT_ZS_HELD;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.configBad := cfgOn OR cfgW <> UT_F_NONE;
Data.sts.doseOn := DoseEnable;
Data.sts.masterWanted := masterWanted;
Data.sts.timeCap := core.TimeCap;
Data.det.timeLeft := tLeft;
Data.det.phaseTime := tCur - phaseAt;

END_FUNCTION_BLOCK