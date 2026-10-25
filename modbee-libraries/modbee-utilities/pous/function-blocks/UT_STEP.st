(* One step of a UT_STEP_SEQ recipe (an element block: the project calls it before the sequence) *)

FUNCTION_BLOCK UT_STEP
  VAR_INPUT
    Cond : BOOL; (* the step's wait condition *)
  END_VAR
  VAR_IN_OUT
    Data : UT_STEP_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_STEP_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    cur : UT_STEP_SET;
    qActive : BOOL;
    qLoops : INT;
    qCond : BOOL;
  END_VAR


METHOD PUBLIC Settings : UT_STEP_SET
  Settings := cur;
END_METHOD
METHOD PUBLIC CondNow : BOOL
  CondNow := qCond;
END_METHOD
METHOD PUBLIC SetActive : BOOL
  VAR_INPUT
    On : BOOL;
  END_VAR
  qActive := On;
  SetActive := On;
END_METHOD
METHOD PUBLIC LoopCount : INT
  LoopCount := qLoops;
END_METHOD
METHOD PUBLIC SetLoops : BOOL
  VAR_INPUT
    Count : INT;
  END_VAR
  qLoops := Count;
  SetLoops := TRUE;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.duration >= T#0s AND Data.set.timeout >= T#0s AND Data.set.loops >= 0
      AND (Data.set.onTimeout = UT_STEP_FAULT OR Data.set.onTimeout = UT_STEP_NEXT OR Data.set.onTimeout = UT_STEP_STOP);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_STEP_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
qCond := Cond;
cur := Data.set;                 (* a bad first-boot setting is the sequence's config fault *)
Data.sts.active := qActive;
Data.sts.loopCount := qLoops;
IF NOT ok THEN
  Data.sts.statusCode := UT_ST_CONFIG;
  Data.sts.faultId := UT_F_STEP_SETTING;
ELSIF qActive THEN
  Data.sts.statusCode := UT_ST_RUN_STEP;
  Data.sts.faultId := UT_F_NONE;
ELSE
  Data.sts.statusCode := UT_ST_IDLE;
  Data.sts.faultId := UT_F_NONE;
END_IF;

END_FUNCTION_BLOCK