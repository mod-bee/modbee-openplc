(* One value of a UT_SETTING_ARRAY (an element block, called before the array) *)

FUNCTION_BLOCK UT_SETTING
  VAR_OUTPUT
    Value : REAL; (* the value in use *)
  END_VAR
  VAR_IN_OUT
    Data : UT_SETTING_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SETTING_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    started : BOOL;
    qValue : REAL;
    qReq : REAL;
    qPending : BOOL;
    qMin : REAL;
    qMax : REAL;
    qAbove : INT;
    qBelow : INT;
    qRefused : BOOL;
    qBad : BOOL;
    qWhy : UT_FAULT;
    accepted : BOOL;
  END_VAR


METHOD PUBLIC GetValue : REAL
  GetValue := qValue;
END_METHOD
METHOD PUBLIC Refused : BOOL
  Refused := qRefused;
END_METHOD
METHOD PUBLIC Bad : BOOL
  Bad := qBad;
END_METHOD
METHOD PUBLIC Why : UT_FAULT
  Why := qWhy;
END_METHOD
METHOD PUBLIC Pending : BOOL     // a new request to check
  Pending := qPending;
END_METHOD
METHOD PUBLIC Request : REAL
  Request := qReq;
END_METHOD
METHOD PUBLIC MinValue : REAL
  MinValue := qMin;
END_METHOD
METHOD PUBLIC MaxValue : REAL
  MaxValue := qMax;
END_METHOD
METHOD PUBLIC AboveItem : INT
  AboveItem := qAbove;
END_METHOD
METHOD PUBLIC BelowItem : INT
  BelowItem := qBelow;
END_METHOD
METHOD PUBLIC Accept : BOOL      // the request passed: it is the value now
  qValue := qReq;
  qRefused := FALSE;
  qWhy := UT_F_NONE;
  qPending := FALSE;
  accepted := TRUE;
  Accept := TRUE;
END_METHOD
METHOD PUBLIC Refuse : BOOL
  VAR_INPUT
    Reason : UT_FAULT;
  END_VAR
  qRefused := TRUE;
  qWhy := Reason;
  qPending := FALSE;
  Refuse := TRUE;
END_METHOD
METHOD PUBLIC SetBad : BOOL
  VAR_INPUT
    IsBad : BOOL;
  END_VAR
  qBad := IsBad;
  SetBad := IsBad;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF accepted THEN
  Data.set.value := qValue;      (* an accepted request, from the array last scan *)
  accepted := FALSE;
END_IF;
IF keep.SaveSet THEN
  keptSet := Data.set;           (* the array checks the values: every value is kept as it is *)
  keptGood := TRUE;
END_IF;
qValue := Data.set.value;        (* also a value written past the check: Bad shows it *)
qMin := Data.set.minValue;
qMax := Data.set.maxValue;
qAbove := Data.set.above;
qBelow := Data.set.below;
qReq := Data.request;
IF NOT started THEN
  started := TRUE;               (* requests are only read on the first scan *)
ELSIF NOT (qReq = Data.sts.seen OR (NOT (qReq = qReq) AND NOT (Data.sts.seen = Data.sts.seen))) OR Data.cmdCheck THEN
  qPending := TRUE;
END_IF;
Data.sts.seen := qReq;
Data.cmdCheck := FALSE;
Value := qValue;
Data.sts.refused := qRefused;
Data.sts.bad := qBad;
Data.sts.refusedWhy := qWhy;

END_FUNCTION_BLOCK