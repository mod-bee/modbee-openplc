(* UT_LEVEL_CHECK — one alarm level on a value (high or low), with a switch
backing it up, and the value's own sensor-bad protection: a bad reading is
ridden through (the level holds) until sensorBad acts, then the value part
drops (the switch still acts). Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_LEVEL_CHECK
  VAR_INPUT
    In : REAL;
    InGood : BOOL := TRUE;
    High : BOOL := TRUE; (* high level (FALSE = low) *)
    UseIn : BOOL := TRUE; (* FALSE: switch only *)
    Switch : BOOL; (* a switch signalling this level *)
    Enable : BOOL := TRUE; (* FALSE: the condition is treated as absent *)
    Reset : BOOL R_EDGE;
    ResetReq : BOOL; (* a reset while TRUE (builders) *)
    RetryWindow : TIME := T#1h;
  END_VAR
  VAR_OUTPUT
    Trip : BOOL;
    Warn : BOOL;
    Signal : BOOL;
    Event : BOOL;
    ResetDone : BOOL;
    Cleared : BOOL;
    SensorBad : BOOL; (* the value is bad past its delay *)
    BadInput : BOOL; (* the value is bad now *)
    BadSetting : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_LEVEL_CHECK_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_LEVEL_CHECK_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    hReset : BOOL;
    keep : UT_KEEP;
    stL : UT_PROT_ST;
    stB : UT_PROT_ST;
    ok : BOOL;
    isGood : BOOL;
    rst : BOOL;
    x : BOOL;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_LEVEL_OK(L := Data.set.level) AND UT_PROT_OK(P := Data.set.sensorBad);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_LEVEL_SETTING;
  Data.set := keptSet;
  ok := UT_LEVEL_OK(L := Data.set.level) AND UT_PROT_OK(P := Data.set.sensorBad);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
rst := Reset OR ResetReq OR (Data.cmdReset AND NOT hReset);   (* once per request, even when held on *)
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
isGood := InGood AND ABS(In) <= 3.4E38;
x := UT_PROT_RUN(TNow := TIME(), Cause := UseIn AND Enable AND NOT isGood, ResetReq := rst,
                 RetryWindow := RetryWindow, Prot := Data.set.sensorBad, Sts := Data.sts.sensorBad, St := stB);
x := UT_LEVEL_RUN(TNow := TIME(), In := In, Good := isGood, High := High, UseIn := UseIn, Switch := Switch,
                  Enable := Enable, Release := Data.sts.sensorBad.active, ResetReq := rst, RetryWindow := RetryWindow,
                  Level := Data.set.level, Sts := Data.sts.level, St := stL);
Trip := stL.trip;
Warn := stL.warn;
Signal := stL.sig;
Event := stL.event;
ResetDone := stL.reset OR stB.reset;
Cleared := stL.cleared OR stB.cleared;
SensorBad := stB.trip OR stB.warn;
BadInput := UseIn AND NOT isGood;
BadSetting := stL.badSetting OR stB.badSetting;
Data.sts.value := In;

END_FUNCTION_BLOCK