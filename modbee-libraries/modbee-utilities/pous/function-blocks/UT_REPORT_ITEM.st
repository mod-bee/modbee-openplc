(* One value of a UT_REPORT_ARRAY (an element block, called before the array) *)

FUNCTION_BLOCK UT_REPORT_ITEM
  VAR_INPUT
    In : REAL; (* the value (BOOL / INT: convert to REAL) *)
    InQuality : UT_QUALITY := UT_Q_GOOD;
  END_VAR
  VAR_IN_OUT
    Data : UT_REPORT_ITEM_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_REPORT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    mem : UT_REPORT_MEM;
    ok : BOOL;
    tCur : TIME;
    hCmd : BOOL;
    pendForce : BOOL;
    linkOn : BOOL; (* from the array's last Link *)
    linkBeat : TIME;
    linkStart : BOOL := TRUE;
    bodyRan : BOOL;
    qReport : BOOL;
    qValue : REAL;
    v : REAL;
    why : UT_REPORT_REASON;
  END_VAR


METHOD PUBLIC Report : BOOL      // reported this scan
  Report := qReport;
END_METHOD
METHOD PUBLIC GetValue : REAL       // the value sent
  GetValue := qValue;
END_METHOD
METHOD PUBLIC IsValid : BOOL
  IsValid := ok;
END_METHOD
METHOD PUBLIC WasCalled : BOOL   // the item ran since the last ask
  WasCalled := bodyRan;
  bodyRan := FALSE;
END_METHOD
METHOD PUBLIC ForceNext : BOOL   // report on the next run
  pendForce := TRUE;
  ForceNext := TRUE;
END_METHOD
METHOD PUBLIC Born : BOOL        // start fresh: FIRST on the next run (reportOnStart)
  mem.started := FALSE;
  Born := TRUE;
END_METHOD
METHOD PUBLIC Link : BOOL        // the array's link state and settings, every scan
  VAR_INPUT
    Enabled : BOOL;
    Heartbeat : TIME;
    OnStart : BOOL;
  END_VAR
  linkOn := Enabled;
  linkBeat := Heartbeat;
  linkStart := OnStart;
  Link := TRUE;
END_METHOD

tCur := TIME();
bodyRan := TRUE;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_REPORT_CHECK(S := Data.set);
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
IF Data.set.heartbeat > T#0s THEN
  linkBeat := Data.set.heartbeat;
END_IF;
qReport := UT_REPORT_RUN(TNow := tCur, In := In, Quality := InQuality, ForceReq := pendForce OR (Data.cmdForce AND NOT hCmd),
                         Enable := linkOn, Heartbeat := linkBeat, OnStart := linkStart AND Data.set.reportOnStart,
                         Set := Data.set, Mem := mem, Sts := Data.sts, Value => v, Reason => why);
pendForce := FALSE;
hCmd := Data.cmdForce;
Data.cmdForce := FALSE;
IF qReport THEN
  qValue := v;
END_IF;
Data.sts.badSetting := NOT ok;

END_FUNCTION_BLOCK