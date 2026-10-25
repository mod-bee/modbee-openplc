(* UT_SWITCH_MEAS — any set of LL / L / H / HH switches (floats, pressure
switches, flow switches) as one measurement. Offers the UT_I_MEAS plug
with bands and no value: wire the instance to a Level, Pressure or Flow
pin; the consumer takes each band as its switch.

Only the switches set as used (set.useLL ... useHH) count. Each is
debounced (set.debounce). Bands: IsLoLo = LL; IsLo = L or LL; IsHi = H or
HH; IsHiHi = HH. Every band is reported as read: the block never decides
which wins (decision 31). Switches that cannot all be true (a high band and
a low band together; HH without H; LL without L) for set.disagree.delay:
WARN (default) = Disagree + Warning, still Good; TRIP = Good FALSE, Fault.

InGood FALSE (or a bad IO quality on a used switch): the bands hold their
last state for set.inputBad.delay, then Good FALSE (TRIP) or a warning.
QLL ... QHH (wired from the IO map rows instead of InGood): a used switch
whose row is not mapped is not fitted (HasBand FALSE for it); with no used
switch fitted the plug answers IsFitted() FALSE. Enable FALSE = out of
service (floats being cleaned): Good FALSE, status "Out of service". *)

FUNCTION_BLOCK UT_SWITCH_MEAS IMPLEMENTS UT_I_MEAS
  VAR_INPUT
    LL : BOOL; (* switch signalling (NOT at the pin for a contact that opens on the condition) *)
    L : BOOL;
    H : BOOL;
    HH : BOOL;
    InGood : BOOL := TRUE; (* the switches' source is healthy *)
    QLL : UT_IO_Q := UT_IOQ_OK; (* each switch's IO quality (wired instead of InGood) *)
    QL : UT_IO_Q := UT_IOQ_OK;
    QH : UT_IO_Q := UT_IOQ_OK;
    QHH : UT_IO_Q := UT_IOQ_OK;
    Enable : BOOL := TRUE; (* FALSE = out of service *)
    Reset : BOOL R_EDGE; (* reset a latched fault *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* usable *)
    IsHiHi : BOOL; (* band states, as read *)
    IsHi : BOOL;
    IsLo : BOOL;
    IsLoLo : BOOL;
    Disagree : BOOL; (* switches that cannot all be true (after the delay) *)
    Warning : BOOL;
    Fault : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_SWITCH_MEAS_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SWITCH_MEAS_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    hReset : BOOL;
    keep : UT_KEEP;
    dbLL : UT_DEBOUNCE;
    dbL : UT_DEBOUNCE;
    dbH : UT_DEBOUNCE;
    dbHH : UT_DEBOUNCE;
    stDis : UT_PROT_ST;
    stBad : UT_PROT_ST;
    ok : BOOL;
    resetReq : BOOL;
    fLL : BOOL; (* fitted: used, and its IO row is mapped *)
    fL : BOOL;
    fH : BOOL;
    fHH : BOOL;
    anyFitted : BOOL;
    bad : BOOL;
    sLL : BOOL; (* states in use (held while the input is bad) *)
    sL : BOOL;
    sH : BOOL;
    sHH : BOOL;
    clash : BOOL;
    x : BOOL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    zero : REAL;
    mNan : REAL;
    mGood : BOOL;
    mFault : BOOL;
    mWarn : BOOL;
    mLocked : BOOL;
    mFitted : BOOL;
    mNe : UT_NE107;
    mStatus : UT_STATUS;
    mFaultId : UT_FAULT;
    mUnit : UT_UNIT;
    mHH : BOOL;
    mH : BOOL;
    mL : BOOL;
    mLL : BOOL;
    mfHH : BOOL;
    mfH : BOOL;
    mfL : BOOL;
    mfLL : BOOL;
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
  IsLocked := mLocked;
END_METHOD
METHOD PUBLIC IsFitted : BOOL
  IsFitted := mFitted;
END_METHOD
METHOD PUBLIC Ne107 : UT_NE107
  Ne107 := mNe;
END_METHOD
METHOD PUBLIC GetValue : REAL
  GetValue := mNan;                 (* switches: no value *)
END_METHOD
METHOD PUBLIC GoodNow : BOOL
  GoodNow := mGood;
END_METHOD
METHOD PUBLIC HasValue : BOOL
  HasValue := FALSE;
END_METHOD
METHOD PUBLIC HasBand : BOOL
  VAR_INPUT
    Band : UT_LEVEL_ID;
  END_VAR
  CASE Band OF
  UT_LVL_HIHI: HasBand := mfHH;
  UT_LVL_HI: HasBand := mfH;
  UT_LVL_LO: HasBand := mfL;
  UT_LVL_LOLO: HasBand := mfLL;
  ELSE
    HasBand := FALSE;
  END_CASE;
END_METHOD
METHOD PUBLIC IsHiHiNow : BOOL
  IsHiHiNow := mHH;
END_METHOD
METHOD PUBLIC IsHiNow : BOOL
  IsHiNow := mH;
END_METHOD
METHOD PUBLIC IsLoNow : BOOL
  IsLoNow := mL;
END_METHOD
METHOD PUBLIC IsLoLoNow : BOOL
  IsLoLoNow := mLL;
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
resetReq := Reset OR (Data.cmdReset AND NOT hReset);   (* once per request, even when held on *)
hReset := Data.cmdReset;
Data.cmdReset := FALSE;

(* settings: a bad write is put back *)
ok := Data.set.debounce >= T#0s AND Data.set.retryWindow >= T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := Data.set.debounce >= T#0s AND Data.set.retryWindow >= T#0s;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* which switches are on this site *)
fLL := Data.set.useLL AND NOT (QLL = UT_IOQ_UNUSED OR QLL = UT_IOQ_NOT_FITTED);
fL := Data.set.useL AND NOT (QL = UT_IOQ_UNUSED OR QL = UT_IOQ_NOT_FITTED);
fH := Data.set.useH AND NOT (QH = UT_IOQ_UNUSED OR QH = UT_IOQ_NOT_FITTED);
fHH := Data.set.useHH AND NOT (QHH = UT_IOQ_UNUSED OR QHH = UT_IOQ_NOT_FITTED);
anyFitted := fLL OR fL OR fH OR fHH;
bad := NOT InGood
       OR (fLL AND NOT (QLL = UT_IOQ_OK OR QLL = UT_IOQ_FORCED))
       OR (fL AND NOT (QL = UT_IOQ_OK OR QL = UT_IOQ_FORCED))
       OR (fH AND NOT (QH = UT_IOQ_OK OR QH = UT_IOQ_FORCED))
       OR (fHH AND NOT (QHH = UT_IOQ_OK OR QHH = UT_IOQ_FORCED));

dbLL(In := LL AND fLL, OnDelay := Data.set.debounce, OffDelay := Data.set.debounce);
dbL(In := L AND fL, OnDelay := Data.set.debounce, OffDelay := Data.set.debounce);
dbH(In := H AND fH, OnDelay := Data.set.debounce, OffDelay := Data.set.debounce);
dbHH(In := HH AND fHH, OnDelay := Data.set.debounce, OffDelay := Data.set.debounce);
IF NOT bad THEN                  (* a bad input holds the bands (ride-through) *)
  sLL := dbLL.Q;
  sL := dbL.Q;
  sH := dbH.Q;
  sHH := dbHH.Q;
END_IF;

(* switches that cannot all be true *)
clash := ((sH OR sHH) AND (sL OR sLL)) OR (sHH AND fH AND NOT sH) OR (sLL AND fL AND NOT sL);
x := UT_PROT_RUN(TNow := TIME(), Cause := clash AND Enable, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.disagree, Sts := Data.sts.disagree, St := stDis);
x := UT_PROT_RUN(TNow := TIME(), Cause := bad AND Enable AND anyFitted, ResetReq := resetReq,
                 RetryWindow := Data.set.retryWindow, Prot := Data.set.inputBad, Sts := Data.sts.inputBad, St := stBad);

IsHiHi := sHH;
IsHi := sH OR sHH;
IsLo := sL OR sLL;
IsLoLo := sLL;
Disagree := stDis.trip OR stDis.warn;
Good := Enable AND anyFitted AND NOT stDis.trip AND NOT stBad.trip;
Fault := Enable AND (stDis.trip OR stBad.trip);
Warning := Enable AND (stDis.warn OR stBad.warn OR (bad AND anyFitted));

(* status *)
stF := UT_F_NONE;
Data.timeLeft := T#0s;
IF NOT Enable THEN
  stCode := UT_ST_OOS;
ELSIF NOT anyFitted THEN
  stCode := UT_ST_NOT_FITTED;
ELSIF stBad.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.inputBad.reset, Sts := Data.sts.inputBad);
  stF := UT_F_INPUT_BAD;
  Data.timeLeft := Data.sts.inputBad.timeLeft;
ELSIF stDis.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.disagree.reset, Sts := Data.sts.disagree);
  stF := UT_F_SWITCH_ORDER;
  Data.timeLeft := Data.sts.disagree.timeLeft;
ELSIF stBad.warn OR bad THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_INPUT_BAD;
  Data.timeLeft := Data.sts.inputBad.timeLeft;
ELSIF stDis.warn THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_SWITCH_ORDER;
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
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := NOT Enable, OutOfSpec := Warning, Maint := FALSE);
Data.sts.ll := sLL;
Data.sts.l := sL;
Data.sts.h := sH;
Data.sts.hh := sHH;
Data.sts.good := Good;
Data.sts.isHiHi := IsHiHi;
Data.sts.isHi := IsHi;
Data.sts.isLo := IsLo;
Data.sts.isLoLo := IsLoLo;

(* the plug's answers *)
mGood := Good;
mFault := Fault;
mWarn := Warning;
mLocked := Data.sts.disagree.locked OR Data.sts.inputBad.locked;
mFitted := anyFitted;
mNe := Data.sts.ne107;
mStatus := stCode;
mFaultId := stF;
mUnit := Data.set.unit;
mHH := IsHiHi;
mH := IsHi;
mL := IsLo;
mLL := IsLoLo;
mfHH := fHH;
mfH := fH;
mfL := fL;
mfLL := fLL;

END_FUNCTION_BLOCK