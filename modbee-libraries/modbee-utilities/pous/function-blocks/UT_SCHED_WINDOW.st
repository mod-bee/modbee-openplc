(* One time window of a UT_SCHEDULE (an element block: the project calls it, the schedule asks it) *)

FUNCTION_BLOCK UT_SCHED_WINDOW
  VAR_IN_OUT
    Data : UT_SCHED_WINDOW_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SCHED_WINDOW_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    cur : UT_SCHED_WINDOW_SET; (* the settings in use (the methods read it) *)
    lastIn : BOOL;
  END_VAR


METHOD PUBLIC IsValid : BOOL
  IsValid := ok;
END_METHOD
METHOD PUBLIC IsIn : BOOL        // the window is on at this local time
  VAR_INPUT
    Local : DT;
  END_VAR
  VAR
    secs : LINT;
    dayP : LINT;
    dow : INT;
    dowPrev : INT;
    ms : DINT;
    st : DINT;
    sp : DINT;
    dOk : BOOL;
    dOkPrev : BOOL;
    sDay : LINT;
  END_VAR
  IsIn := FALSE;
  IF ok AND cur.enable AND cur.start <> cur.stop THEN
    secs := DT_TO_LINT(Local);
    dayP := secs / 86400;
    dow := LINT_TO_INT((dayP + 3) MOD 7);
    dowPrev := (dow + 6) MOD 7;
    ms := LINT_TO_DINT(secs MOD 86400) * 1000;
    st := TOD_TO_DINT(cur.start);
    sp := TOD_TO_DINT(cur.stop);
    dOk := (cur.days AND SHL(BYTE#1, dow)) <> 0;
    dOkPrev := (cur.days AND SHL(BYTE#1, dowPrev)) <> 0;
    IF cur.everyDays >= 2 THEN
      sDay := DATE_TO_LINT(cur.startDate) / 86400;
      dOk := dOk AND dayP >= sDay AND (dayP - sDay) MOD INT_TO_LINT(cur.everyDays) = 0;
      dOkPrev := dOkPrev AND dayP - 1 >= sDay AND (dayP - 1 - sDay) MOD INT_TO_LINT(cur.everyDays) = 0;
    END_IF;
    IF st < sp THEN
      IsIn := dOk AND ms >= st AND ms < sp;
    ELSE
      IsIn := (dOk AND ms >= st) OR (dOkPrev AND ms < sp);
    END_IF;
  END_IF;
  lastIn := IsIn;
END_METHOD
METHOD PUBLIC NextChange : DT    // its next start or stop after this local time (DT#1970... = none)
  VAR_INPUT
    Local : DT;
  END_VAR
  VAR
    secs : LINT;
    day0 : LINT;
    a : LINT;
    b : LINT;
  END_VAR
  NextChange := DT#1970-01-01-00:00:00;
  IF ok AND cur.enable AND cur.start <> cur.stop THEN
    secs := DT_TO_LINT(Local);
    day0 := (secs / 86400) * 86400;
    a := day0 + (TOD_TO_LINT(cur.start) + 999) / 1000;
    IF a <= secs THEN a := a + 86400; END_IF;
    b := day0 + (TOD_TO_LINT(cur.stop) + 999) / 1000;
    IF b <= secs THEN b := b + 86400; END_IF;
    NextChange := LINT_TO_DT(MIN(a, b));
  END_IF;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_SCHED_WINDOW_CHECK(S := Data.set);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SCHED_WINDOW;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_SCHED_WINDOW_CHECK(S := Data.set);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
IF ok THEN
  cur := Data.set;
END_IF;
Data.sts.configBad := NOT ok;
Data.sts.inWindow := lastIn;
IF NOT ok THEN
  Data.sts.statusCode := UT_ST_CONFIG;
  Data.sts.faultId := UT_F_SCHED_WINDOW;
ELSIF lastIn THEN
  Data.sts.statusCode := UT_ST_ACTIVE;
  Data.sts.faultId := UT_F_NONE;
ELSE
  Data.sts.statusCode := UT_ST_IDLE;
  Data.sts.faultId := UT_F_NONE;
END_IF;

END_FUNCTION_BLOCK