(* UT_SIGNAL_SELECT — two or three sensors measuring the same thing, voted
into one trusted measurement (decision 16). Offers the UT_I_MEAS plug.

A sensor is usable when its plug is linked, GoodNow(), HasValue() and its
value a number; an unwired sensor is not fitted and never used. Two
sensors agree when they are within faultSpread.
  3 usable  all agree: combined by selectMode. One agrees with neither
            of the others while those two agree: it is dropped (Deviating,
            warning "Sensor n deviates"). No two agree: noAgree.
  2 usable  agree: combined by selectMode. Not: warning "Sensors
            disagree", the twoDisagree side is used (MAX: the higher).
  1 usable  used, warning "One sensor left".
  0 usable  noAgree.
noAgree is ridden through for its delay (the last voted value held), then
TRIP: Good FALSE, Out per noGoodAction. Deviation: Spread (largest
difference between usable sensors) above warnSpread for deviation.delay,
or a sensor dropped. filterTime smooths Out. Settings kept; a bad write is
put back. *)

FUNCTION_BLOCK UT_SIGNAL_SELECT IMPLEMENTS UT_I_MEAS
  VAR_INPUT
    Sensor1 : UT_I_MEAS; (* NULL = not fitted, never used *)
    Sensor2 : UT_I_MEAS;
    Sensor3 : UT_I_MEAS;
    Reset : BOOL R_EDGE;
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* the voted value can be used *)
    Out : REAL; (* voted value (while not Good: per noGoodAction) *)
    Spread : REAL;
    Deviation : BOOL;
    Deviating : INT; (* the sensor dropped (1..3), 0 none *)
    Fault : BOOL; (* no two agree / none usable (after its delay) *)
    GoodCount : INT;
  END_VAR
  VAR_IN_OUT
    Data : UT_SELECT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SELECT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    filt : UT_FILTER;
    stDev : UT_PROT_ST;
    stNo : UT_PROT_ST;
    setOk : BOOL;
    hReset : BOOL;
    resetReq : BOOL;
    v : ARRAY [1..3] OF REAL;
    usable : ARRAY [1..3] OF BOOL;
    use : ARRAY [1..3] OF BOOL;
    raw : ARRAY [1..3] OF BOOL; (* a number, health ignored (noGoodAction MIN / MAX / PASS) *)
    ag12 : BOOL;
    ag13 : BOOL;
    ag23 : BOOL;
    i : INT;
    n : INT;
    lo : REAL;
    hi : REAL;
    sum : REAL;
    loIdx : INT;
    hiIdx : INT;
    selIdx : INT;
    pick : REAL;
    haveSel : BOOL;
    held : REAL;
    noAgreeNow : BOOL;
    twoApart : BOOL;
    mode : UT_SELECT_METHOD;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    mNan : REAL;
    mValue : REAL;
    mGood : BOOL;
    mFault : BOOL;
    mWarn : BOOL;
    mFitted : BOOL;
    mNe : UT_NE107;
    mStatus : UT_STATUS;
    mFaultId : UT_FAULT;
    mUnit : UT_UNIT;
  END_VAR


METHOD PUBLIC StatusCode : UT_STATUS
  StatusCode := mStatus;
END_METHOD
METHOD PUBLIC FaultId : UT_FAULT
  FaultId := mFaultId;
END_METHOD
METHOD PUBLIC StopReason : UT_STOP
  StopReason := UT_STOP_NONE;
END_METHOD
METHOD PUBLIC HasFault : BOOL
  HasFault := mFault;
END_METHOD
METHOD PUBLIC HasWarning : BOOL
  HasWarning := mWarn;
END_METHOD
METHOD PUBLIC IsLocked : BOOL
  IsLocked := FALSE;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := mFitted;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := mNe;
END_METHOD
METHOD PUBLIC GetValue : REAL
  GetValue := mValue;
END_METHOD
METHOD PUBLIC GoodNow : BOOL
  GoodNow := mGood;
END_METHOD
METHOD PUBLIC HasValue : BOOL
  HasValue := TRUE;
END_METHOD
METHOD PUBLIC HasBand : BOOL
  VAR_INPUT
    Band : UT_LEVEL_ID;
  END_VAR
  HasBand := FALSE;
END_METHOD
METHOD PUBLIC IsHiHiNow : BOOL
  IsHiHiNow := FALSE;
END_METHOD
METHOD PUBLIC IsHiNow : BOOL
  IsHiNow := FALSE;
END_METHOD
METHOD PUBLIC IsLoNow : BOOL
  IsLoNow := FALSE;
END_METHOD
METHOD PUBLIC IsLoLoNow : BOOL
  IsLoLoNow := FALSE;
END_METHOD
METHOD PUBLIC Unit : UT_UNIT
  Unit := mUnit;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.PowerUp THEN
  mNan := zero / zero;
END_IF;
setOk := Data.set.warnSpread >= 0.0 AND Data.set.warnSpread <= 3.4E38
         AND Data.set.faultSpread >= 0.0 AND Data.set.faultSpread <= 3.4E38
         AND Data.set.filterTime >= T#0s AND Data.set.retryWindow >= T#0s AND ABS(Data.set.substValue) <= 3.4E38
         AND UT_PROT_OK(P := Data.set.deviation) AND UT_PROT_OK(P := Data.set.noAgree)
         AND (Data.set.twoDisagree = UT_SEL_MAX OR Data.set.twoDisagree = UT_SEL_MIN)
         AND (Data.set.selectMode = UT_SEL_AVERAGE OR Data.set.selectMode = UT_SEL_MIN OR Data.set.selectMode = UT_SEL_MAX
              OR Data.set.selectMode = UT_SEL_MEDIAN OR Data.set.selectMode = UT_SEL_PRIMARY)
         AND (Data.set.noGoodAction = UT_AI_HOLD OR Data.set.noGoodAction = UT_AI_MIN OR Data.set.noGoodAction = UT_AI_MAX
              OR Data.set.noGoodAction = UT_AI_SUBST OR Data.set.noGoodAction = UT_AI_PASS);
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SPREAD_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
resetReq := Reset OR (Data.cmdReset AND NOT hReset);   (* once per request, even when held on *)
hReset := Data.cmdReset;
Data.cmdReset := FALSE;

(* the sensors *)
FOR i := 1 TO 3 DO
  usable[i] := FALSE;
  raw[i] := FALSE;
  v[i] := 0.0;
END_FOR;
mFitted := FALSE;
IF Sensor1 <> NULL THEN
  v[1] := Sensor1.GetValue(); raw[1] := ABS(v[1]) <= 3.4E38;
  usable[1] := Sensor1.GoodNow() AND Sensor1.HasValue() AND raw[1];
  mFitted := TRUE;
  mUnit := Sensor1.Unit();
END_IF;
IF Sensor2 <> NULL THEN
  v[2] := Sensor2.GetValue(); raw[2] := ABS(v[2]) <= 3.4E38;
  usable[2] := Sensor2.GoodNow() AND Sensor2.HasValue() AND raw[2];
  mFitted := TRUE;
END_IF;
IF Sensor3 <> NULL THEN
  v[3] := Sensor3.GetValue(); raw[3] := ABS(v[3]) <= 3.4E38;
  usable[3] := Sensor3.GoodNow() AND Sensor3.HasValue() AND raw[3];
  mFitted := TRUE;
END_IF;
GoodCount := BOOL_TO_INT(usable[1]) + BOOL_TO_INT(usable[2]) + BOOL_TO_INT(usable[3]);

(* the vote *)
ag12 := usable[1] AND usable[2] AND ABS(v[1] - v[2]) <= Data.set.faultSpread;
ag13 := usable[1] AND usable[3] AND ABS(v[1] - v[3]) <= Data.set.faultSpread;
ag23 := usable[2] AND usable[3] AND ABS(v[2] - v[3]) <= Data.set.faultSpread;
FOR i := 1 TO 3 DO
  use[i] := usable[i];
END_FOR;
Deviating := 0;
noAgreeNow := FALSE;
twoApart := FALSE;
mode := Data.set.selectMode;
IF GoodCount = 3 THEN
  IF NOT ag12 AND NOT ag13 AND NOT ag23 THEN
    noAgreeNow := TRUE;
  ELSIF ag23 AND NOT ag12 AND NOT ag13 THEN
    Deviating := 1;
  ELSIF ag13 AND NOT ag12 AND NOT ag23 THEN
    Deviating := 2;
  ELSIF ag12 AND NOT ag13 AND NOT ag23 THEN
    Deviating := 3;
  END_IF;
  IF Deviating > 0 THEN
    use[Deviating] := FALSE;
  END_IF;
ELSIF GoodCount = 2 THEN
  IF NOT (ag12 OR ag13 OR ag23) THEN
    twoApart := TRUE;
    mode := Data.set.twoDisagree;
  END_IF;
ELSIF GoodCount = 0 THEN
  noAgreeNow := TRUE;
END_IF;
IF noAgreeNow THEN
  FOR i := 1 TO 3 DO
    use[i] := FALSE;
  END_FOR;
END_IF;

(* lowest, highest and mean of those used *)
n := 0;
sum := 0.0;
loIdx := 0;
hiIdx := 0;
FOR i := 1 TO 3 DO
  IF use[i] THEN
    n := n + 1;
    sum := sum + v[i];
    IF loIdx = 0 THEN
      loIdx := i;
      hiIdx := i;
    ELSIF v[i] < v[loIdx] THEN
      loIdx := i;
    ELSIF v[i] > v[hiIdx] THEN
      hiIdx := i;
    END_IF;
  END_IF;
END_FOR;
IF n > 0 THEN
  lo := v[loIdx];
  hi := v[hiIdx];
END_IF;
(* the spread among the usable sensors *)
Spread := 0.0;
FOR i := 1 TO 3 DO
  IF usable[i] AND usable[(i MOD 3) + 1] THEN
    Spread := MAX(Spread, ABS(v[i] - v[(i MOD 3) + 1]));
  END_IF;
END_FOR;

haveSel := n > 0;
selIdx := 0;
IF haveSel THEN
  CASE mode OF
  UT_SEL_MIN:
    pick := lo;
    selIdx := loIdx;
  UT_SEL_MAX:
    pick := hi;
    selIdx := hiIdx;
  UT_SEL_MEDIAN:
    IF n = 3 THEN
      selIdx := 6 - loIdx - hiIdx;
      IF selIdx = loIdx OR selIdx = hiIdx OR selIdx < 1 OR selIdx > 3 THEN
        selIdx := 2;             (* all equal *)
      END_IF;
      pick := v[selIdx];
    ELSE
      pick := sum / INT_TO_REAL(n);
      IF n = 1 THEN selIdx := loIdx; END_IF;
    END_IF;
  UT_SEL_PRIMARY:
    IF use[1] THEN
      selIdx := 1;
    ELSIF use[2] THEN
      selIdx := 2;
    ELSE
      selIdx := 3;
    END_IF;
    pick := v[selIdx];
  ELSE
    pick := sum / INT_TO_REAL(n);
    IF n = 1 THEN selIdx := loIdx; END_IF;
  END_CASE;
  held := pick;
END_IF;

(* no agreement: ridden through, then not Good *)
x := UT_PROT_RUN(TNow := TIME(), Cause := noAgreeNow AND mFitted, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.noAgree, Sts := Data.sts.noAgree, St := stNo);
x := UT_PROT_RUN(TNow := TIME(), Cause := Spread > Data.set.warnSpread OR Deviating > 0, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.deviation, Sts := Data.sts.dev, St := stDev);
Fault := stNo.trip;
Good := mFitted AND NOT stNo.trip;
Deviation := stDev.warn OR stDev.trip;

IF NOT Good THEN                 (* the value at the pin while not Good *)
  n := 0;
  lo := 0.0;
  hi := 0.0;
  FOR i := 1 TO 3 DO
    IF raw[i] THEN
      IF n = 0 OR v[i] < lo THEN lo := v[i]; END_IF;
      IF n = 0 OR v[i] > hi THEN hi := v[i]; END_IF;
      n := n + 1;
    END_IF;
  END_FOR;
  CASE Data.set.noGoodAction OF
  UT_AI_MIN: IF n > 0 THEN held := lo; END_IF;
  UT_AI_MAX: IF n > 0 THEN held := hi; END_IF;
  UT_AI_SUBST: held := Data.set.substValue;
  UT_AI_PASS: IF n > 0 THEN held := (lo + hi) / 2.0; END_IF;
  END_CASE;
  selIdx := 0;
END_IF;
filt(In := held, Tc := Data.set.filterTime, Mode := UT_FILTER_LOWPASS);
Out := filt.Out;

(* status *)
stF := UT_F_NONE;
IF NOT mFitted THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_NO_LINK;
ELSIF stNo.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.noAgree.reset, Sts := Data.sts.noAgree);
  stF := UT_F_SENSORS_DISAGREE;
ELSIF noAgreeNow OR twoApart THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_SENSORS_DISAGREE;
ELSIF Deviating > 0 THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_SENSOR_DEVIATES;
ELSIF GoodCount = 1 THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_ONE_SENSOR;
ELSIF Deviation THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_SPREAD_SETTING;
ELSIF NOT setOk THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stF = UT_F_SPREAD_SETTING THEN
  stF := UT_F_SENSORS_DISAGREE;  (* spread above warnSpread *)
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
(* NE107: no agreement = FAILURE; disagree (2), deviating, one left = OUT_OF_SPEC; one outvoted of three = MAINTENANCE *)
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault OR NOT mFitted, Check := FALSE,
                               OutOfSpec := twoApart OR noAgreeNow OR GoodCount = 1 OR Deviation,
                               Maint := Deviating > 0);
Data.sts.out := Out;
Data.sts.spread := Spread;
Data.sts.selected := selIdx;
Data.sts.goodCount := GoodCount;
Data.sts.deviating := Deviating;
Data.sts.deviation := Deviation;
Data.sts.fault := Fault;
Data.sts.configBad := NOT mFitted;

mGood := Good;
IF Good THEN mValue := Out; ELSE mValue := mNan; END_IF;
mFault := Fault OR NOT mFitted;
mWarn := Deviation OR twoApart OR noAgreeNow OR GoodCount = 1 OR Deviating > 0;
mNe := Data.sts.ne107;
mStatus := stCode;
mFaultId := stF;

END_FUNCTION_BLOCK