(* UT_RUN_HOURS — run-hour meter with a service interval. Hours are counted
exactly (whole milliseconds, the rest carried: UT_HOURS_ADD) into lifetime,
since-service, today and yesterday counts, kept hourly. ServiceDue when the
hours since the last service reach set.serviceInterval (0 = off);
ResetService / cmdResetService: the service is done. cmdPreset sets the
lifetime hours (a replacement); cmdDayRollover closes the day. lastRun is
the length of the last run. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_RUN_HOURS
  VAR_INPUT
    Running : BOOL;
    ResetService : BOOL R_EDGE; (* service done *)
  END_VAR
  VAR_OUTPUT
    ServiceDue : BOOL;
    TotalHours : LREAL;
  END_VAR
  VAR_IN_OUT
    Data : UT_RUN_HOURS_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_RUN_HOURS_SET;
    keptGood : BOOL;
    keptTot : UT_RUN_HOURS_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    acc : UT_HOURS_ACC;
    ok : BOOL;
    ms : LINT;
    hSvc : BOOL;
    hPreset : BOOL;
    hRoll : BOOL;
    ev : BOOL;
    runPrev : BOOL;
    runAt : TIME;
    tNow : TIME;
    stCode : UT_STATUS;
    shownSt : UT_STATUS;
  END_VAR


tNow := TIME();
ev := ResetService OR (Data.cmdResetService AND NOT hSvc) OR (Data.cmdPreset AND NOT hPreset)
      OR (Data.cmdDayRollover AND NOT hRoll);
keep(TotalsNow := ev);
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := Data.set.serviceInterval >= 0.0 AND Data.set.serviceInterval <= 1.0E7;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_LIMITS;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

ms := UT_HOURS_ADD(Running := Running, TNow := tNow, Acc := acc);
Data.tot.totalMs := Data.tot.totalMs + ms;
Data.tot.serviceMs := Data.tot.serviceMs + ms;
Data.tot.todayMs := Data.tot.todayMs + ms;
IF ResetService OR (Data.cmdResetService AND NOT hSvc) THEN
  Data.tot.serviceMs := 0;
END_IF;
hSvc := Data.cmdResetService;
Data.cmdResetService := FALSE;
IF Data.cmdPreset AND NOT hPreset AND Data.presetHours >= 0.0 AND Data.presetHours <= 1.0E7 THEN
  Data.tot.totalMs := LREAL_TO_LINT(Data.presetHours * 3600000.0);
END_IF;
hPreset := Data.cmdPreset;
Data.cmdPreset := FALSE;
IF Data.cmdDayRollover AND NOT hRoll THEN
  Data.tot.yesterdayMs := Data.tot.todayMs;
  Data.tot.todayMs := 0;
END_IF;
hRoll := Data.cmdDayRollover;
Data.cmdDayRollover := FALSE;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

IF Running AND NOT runPrev THEN
  runAt := tNow;
ELSIF runPrev AND NOT Running THEN
  Data.sts.lastRun := tNow - runAt;
END_IF;
runPrev := Running;
IF Running THEN
  Data.currentRun := tNow - runAt;
ELSE
  Data.currentRun := T#0s;
END_IF;
Data.sts.totalHours := LINT_TO_LREAL(Data.tot.totalMs) / 3600000.0;
Data.sts.serviceHours := LINT_TO_LREAL(Data.tot.serviceMs) / 3600000.0;
Data.sts.todayHours := LINT_TO_LREAL(Data.tot.todayMs) / 3600000.0;
Data.sts.yesterdayHours := LINT_TO_LREAL(Data.tot.yesterdayMs) / 3600000.0;
IF Data.set.serviceInterval > 0.0 THEN
  Data.sts.serviceLeft := MAX(0.0, Data.set.serviceInterval - Data.sts.serviceHours);
  ServiceDue := Data.sts.serviceHours >= Data.set.serviceInterval;
ELSE
  Data.sts.serviceLeft := 0.0;
  ServiceDue := FALSE;
END_IF;
TotalHours := Data.sts.totalHours;
Data.sts.serviceDue := ServiceDue;
IF ServiceDue THEN
  stCode := UT_ST_SERVICE_DUE;
ELSIF Running THEN
  stCode := UT_ST_RUNNING;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stCode <> shownSt OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, UT_F_NONE);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := UT_F_NONE;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := FALSE, OutOfSpec := FALSE, Maint := ServiceDue);

END_FUNCTION_BLOCK