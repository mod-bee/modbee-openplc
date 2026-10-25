(* UT_STARTS — start counter and starts-per-hour inhibit for a motor that is
not in a pump (a pump has it built in). Wire StartPermit to the motor's
Permissive and the motor's Running to Running.

set.limit (UT_START_LIMIT_SET): maxPerHour (0 = off, 1..30) in a sliding
window of exact start times, minBetween, failWait after a failed start.
StartPermit is TRUE while running. An unusable setting: Fault, no start.
Counts: lifetime, today, yesterday (cmdDayRollover), kept hourly; cmdPreset
sets the lifetime count (a replacement motor). Settings kept; a bad write
is put back. *)

FUNCTION_BLOCK UT_STARTS
  VAR_INPUT
    Running : BOOL; (* each rising edge is one start *)
    StartFailed : BOOL R_EDGE; (* a start attempt failed *)
    Reset : BOOL R_EDGE; (* clear the wait (not the counts) *)
  END_VAR
  VAR_OUTPUT
    StartPermit : BOOL; (* -> the motor's Permissive; TRUE while running *)
    Fault : BOOL; (* an unusable setting: no start *)
    Starts : UDINT; (* lifetime starts *)
    PermitIn : TIME;
  END_VAR
  VAR_IN_OUT
    Data : UT_STARTS_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_STARTS_SET;
    keptGood : BOOL;
    keptTot : UT_STARTS_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    lim : UT_START_LIMIT;
    ok : BOOL;
    runPrev : BOOL;
    hReset : BOOL;
    hCount : BOOL;
    hPreset : BOOL;
    hRoll : BOOL;
    ev : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


ev := (Data.cmdResetCount AND NOT hCount) OR (Data.cmdPreset AND NOT hPreset) OR (Data.cmdDayRollover AND NOT hRoll);
keep(TotalsNow := ev);
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := Data.set.limit.maxPerHour >= 0 AND Data.set.limit.maxPerHour <= 30 AND Data.set.limit.window > T#0s
      AND Data.set.limit.minBetween >= T#0s AND Data.set.limit.failWait >= T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_STARTS_LIMIT;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

lim(Running := Running, Failed := StartFailed, Reset := Reset OR (Data.cmdReset AND NOT hReset), Set := Data.set.limit);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
IF Running AND NOT runPrev THEN
  Data.tot.total := Data.tot.total + 1;
  Data.tot.todayStarts := Data.tot.todayStarts + 1;
END_IF;
runPrev := Running;
IF Data.cmdResetCount AND NOT hCount THEN
  Data.tot.total := 0;
  Data.tot.todayStarts := 0;
END_IF;
hCount := Data.cmdResetCount;
Data.cmdResetCount := FALSE;
IF Data.cmdPreset AND NOT hPreset THEN
  Data.tot.total := Data.presetStarts;
END_IF;
hPreset := Data.cmdPreset;
Data.cmdPreset := FALSE;
IF Data.cmdDayRollover AND NOT hRoll THEN
  Data.tot.yesterdayStarts := Data.tot.todayStarts;
  Data.tot.todayStarts := 0;
END_IF;
hRoll := Data.cmdDayRollover;
Data.cmdDayRollover := FALSE;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

Fault := lim.CfgFault;
StartPermit := Running OR (lim.Permit AND NOT Fault);
Starts := Data.tot.total;
PermitIn := lim.PermitIn;
Data.permitIn := PermitIn;
Data.sts.lastHour := lim.InWindow;
Data.sts.startsLeft := lim.StartsLeft;
Data.sts.startPermit := StartPermit;
Data.sts.configBad := Fault;
stF := UT_F_NONE;
IF Fault THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_STARTS_LIMIT;
ELSIF NOT StartPermit THEN
  stCode := UT_ST_WAIT_STARTS;
ELSIF Running THEN
  stCode := UT_ST_RUNNING;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := FALSE, OutOfSpec := FALSE,
                               Maint := lim.StartsLeft = 0);

END_FUNCTION_BLOCK