(* UT_STATS — minimum, maximum and time-weighted average of a value, for the
current period and the previous one.

Each scan the value read now stands for the time since the previous scan
(time-weighted: the same result at any scan rate). Only samples taken while
Enable is TRUE and Good, that are numbers and not excluded by ignoreBelow /
ignoreAbove, count. Rollover (rising edge) closes the period: the current
statistics move to the previous ones. Reset / cmdResetStats clears both.
The running and the last period are kept hourly (Data.tot); the sum is
LREAL with compensated (Kahan) summation. samples saturates at the UDINT
maximum. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_STATS
  VAR_INPUT
    In : REAL;
    Good : BOOL := TRUE; (* its health; FALSE: samples skipped *)
    Enable : BOOL := TRUE; (* collect while TRUE *)
    Rollover : BOOL R_EDGE; (* close the period *)
    Reset : BOOL R_EDGE; (* clear both periods *)
  END_VAR
  VAR_OUTPUT
    Minimum : REAL; (* current period *)
    Maximum : REAL;
    Average : REAL;
  END_VAR
  VAR_IN_OUT
    Data : UT_STATS_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_STATS_SET;
    keptGood : BOOL;
    keptTot : UT_STATS_TOT;
  END_VAR
  VAR
    hReset : BOOL;
    resetReq : BOOL;
    keep : UT_KEEP;
    setOk : BOOL;
    tCur : TIME;
    tPrev : TIME;
    started : BOOL;
    ms : LINT;
    dtScan : TIME;
    valid : BOOL;
    ky : LREAL;
    kt : LREAL;
    avg : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


resetReq := Reset OR (Data.cmdResetStats AND NOT hReset);   (* once per request, even when held on *)
hReset := Data.cmdResetStats;
keep(TotalsNow := Rollover OR resetReq);
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
setOk := ABS(Data.set.ignoreBelow) <= 3.4E38 AND ABS(Data.set.ignoreAbove) <= 3.4E38;
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_VALUE_BAD;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;

tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
END_IF;
ms := TIME_TO_LINT(tCur - tPrev);
IF ms < 0 THEN
  ms := 0;
  tPrev := tCur;
END_IF;
dtScan := LINT_TO_TIME(ms);
tPrev := tPrev + dtScan;

Data.tot.cur.elapsed := Data.tot.cur.elapsed + dtScan;
valid := Enable AND Good AND ABS(In) <= 3.4E38;
IF Data.set.ignoreBelow <> 0.0 AND In < Data.set.ignoreBelow THEN
  valid := FALSE;
END_IF;
IF Data.set.ignoreAbove <> 0.0 AND In > Data.set.ignoreAbove THEN
  valid := FALSE;
END_IF;
IF valid THEN
  IF Data.tot.cur.samples = 0 THEN
    Data.tot.cur.min := In;
    Data.tot.cur.max := In;
    Data.tot.cur.minAt := Data.tot.cur.elapsed;
    Data.tot.cur.maxAt := Data.tot.cur.elapsed;
  ELSIF In < Data.tot.cur.min THEN
    Data.tot.cur.min := In;
    Data.tot.cur.minAt := Data.tot.cur.elapsed;
  ELSIF In > Data.tot.cur.max THEN
    Data.tot.cur.max := In;
    Data.tot.cur.maxAt := Data.tot.cur.elapsed;
  END_IF;
  IF Data.tot.cur.samples < 16#FFFFFFFF THEN
    Data.tot.cur.samples := Data.tot.cur.samples + 1;
  END_IF;
  ky := REAL_TO_LREAL(In) * LINT_TO_LREAL(ms) - Data.tot.cur.comp;
  kt := Data.tot.cur.sum + ky;
  Data.tot.cur.comp := (kt - Data.tot.cur.sum) - ky;
  Data.tot.cur.sum := kt;
  Data.tot.cur.duration := Data.tot.cur.duration + dtScan;
END_IF;
IF Data.tot.cur.duration > T#0s THEN
  avg := LREAL_TO_REAL(Data.tot.cur.sum / TIME_TO_LREAL(Data.tot.cur.duration));
ELSIF Data.tot.cur.samples > 0 THEN
  avg := Data.tot.cur.min + (Data.tot.cur.max - Data.tot.cur.min) / 2.0;
ELSE
  avg := 0.0;
END_IF;

(* close the period *)
IF Rollover THEN
  Data.tot.prev.samples := Data.tot.cur.samples;
  Data.tot.prev.duration := Data.tot.cur.duration;
  IF Data.tot.cur.samples > 0 THEN
    Data.tot.prev.min := Data.tot.cur.min;
    Data.tot.prev.max := Data.tot.cur.max;
    Data.tot.prev.average := avg;
  ELSE
    Data.tot.prev.min := 0.0;
    Data.tot.prev.max := 0.0;
    Data.tot.prev.average := 0.0;
  END_IF;
  Data.tot.cur.samples := 0;
  Data.tot.cur.sum := 0.0;
  Data.tot.cur.comp := 0.0;
  Data.tot.cur.duration := T#0s;
  Data.tot.cur.minAt := T#0s;
  Data.tot.cur.maxAt := T#0s;
  Data.tot.cur.elapsed := T#0s;
  avg := 0.0;
END_IF;
IF resetReq THEN
  Data.tot.cur.samples := 0;
  Data.tot.cur.sum := 0.0;
  Data.tot.cur.comp := 0.0;
  Data.tot.cur.duration := T#0s;
  Data.tot.cur.minAt := T#0s;
  Data.tot.cur.maxAt := T#0s;
  Data.tot.cur.elapsed := T#0s;
  avg := 0.0;
  Data.tot.prev.min := 0.0;
  Data.tot.prev.max := 0.0;
  Data.tot.prev.average := 0.0;
  Data.tot.prev.duration := T#0s;
  Data.tot.prev.samples := 0;
END_IF;
Data.cmdResetStats := FALSE;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

IF Data.tot.cur.samples > 0 THEN
  Minimum := Data.tot.cur.min;
  Maximum := Data.tot.cur.max;
  Data.sts.minimumAt := Data.tot.cur.minAt;
  Data.sts.maximumAt := Data.tot.cur.maxAt;
ELSE
  Minimum := 0.0;
  Maximum := 0.0;
  Data.sts.minimumAt := T#0s;
  Data.sts.maximumAt := T#0s;
END_IF;
Average := avg;
Data.sts.minimum := Minimum;
Data.sts.maximum := Maximum;
Data.sts.average := Average;
Data.sts.samples := Data.tot.cur.samples;
Data.sts.duration := Data.tot.cur.duration;
Data.sts.prevMinimum := Data.tot.prev.min;
Data.sts.prevMaximum := Data.tot.prev.max;
Data.sts.prevAverage := Data.tot.prev.average;
Data.sts.prevDuration := Data.tot.prev.duration;
Data.sts.prevSamples := Data.tot.prev.samples;

stF := UT_F_NONE;
IF Enable AND NOT Good THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_INPUT_BAD;
ELSIF Enable THEN
  stCode := UT_ST_RUNNING;       (* collecting *)
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

END_FUNCTION_BLOCK