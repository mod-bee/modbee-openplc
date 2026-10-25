(* UT_ANALOG_IN — a raw analog reading (or a remote / computed value) to an
engineering value with health. Offers the UT_I_MEAS plug: wire the instance
to any measurement pin (Pv, Level, Pressure ...).

`rawMin` / `rawMax` are the raw values at the bottom and top of the signal
(4 mA and 20 mA for 4-20 mA); raw counts or mA both work.

  UT_AI_4_20MA   NE43: <= 3.6 mA fail low, 3.6-3.8 under range,
                 3.8-20.5 measurement, 20.5-21 over range, >= 21 fail high
  UT_AI_0_20MA,  below 0 % / above 100 % of the span is under / over range
  UT_AI_0_10V    (no fail bands: a live zero is needed to see a wire break)
  UT_AI_CUSTOM   as 0-20 mA, plus fail bands at customLowFail /
                 customHighFail % of the span
  UT_AI_DIRECT   In is already the engineering value (Modbus register,
                 BeeBus value, a calculation): no raw scaling; the custom
                 fail bands around engMin..engMax, trim, clamp, low cutoff
                 and the frozen check still apply

A failure (fail band, NaN, InGood FALSE, a bad IO quality) is ridden through
for set.fault.delay (value held, UNCERTAIN), then: TRIP = BAD (Good FALSE),
WARN = UNCERTAIN + warning. faultAction picks the value at the Value pin
while BAD; the plug's GetValue() gives NaN whenever it is not Good.

InQ (wired instead of InGood from the IO map row): UNUSED / NOT_FITTED = this
input is not on this site: IsFitted() FALSE, Good FALSE, no fault, status
"Not fitted"; OK / FORCED = good; anything else = bad.

simulate / simValue (not kept) give a fixed value, status "Simulated".
Every setting is kept by the block; a bad write is put back (decision 62). *)

FUNCTION_BLOCK UT_ANALOG_IN IMPLEMENTS UT_I_MEAS
  VAR_INPUT
    In : REAL; (* raw value (INT_TO_REAL(%IW0)), or the value itself with DIRECT *)
    InGood : BOOL := TRUE; (* the source is healthy (IO module, comms, device) *)
    InQ : UT_IO_Q := UT_IOQ_OK; (* quality from the IO map row, wired instead of InGood *)
    Reset : BOOL R_EDGE; (* reset a latched fault *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* usable: GOOD, UNCERTAIN or SIM *)
    Value : REAL; (* engineering value (while BAD: per faultAction) *)
    Percent : REAL; (* 0-100 % of the range *)
    Fault : BOOL; (* BAD *)
    Warning : BOOL; (* UNCERTAIN, frozen warning, simulated, a setting warning *)
    Quality : UT_QUALITY;
  END_VAR
  VAR_IN_OUT
    Data : UT_ANALOG_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ANALOG_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    hReset : BOOL;
    keep : UT_KEEP;
    filt : UT_FILTER;
    stFault : UT_PROT_ST;
    stFrozen : UT_PROT_ST;
    ok : BOOL;
    setId : UT_FAULT;
    spanBad : BOOL;
    cfgWarn : BOOL;
    resetReq : BOOL;
    notFitted : BOOL;
    qBad : BOOL;
    inNaN : BOOL;
    failing : BOOL;
    faulted : BOOL;
    faultWarn : BOOL;
    frozenTrip : BOOL;
    frozenWarn : BOOL;
    haveGood : BOOL;
    engSpan : REAL;
    pos : REAL;
    pct : REAL;
    eng : REAL;
    v : REAL;
    refVal : REAL; (* the value the frozen check compares with *)
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
    mLocked : BOOL;
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
  IsLocked := mLocked;
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
  Data.simulate := FALSE;        (* simulation never survives a power cut *)
  mNan := zero / zero;
END_IF;
resetReq := Reset OR (Data.cmdReset AND NOT hReset);   (* once per request, even when held on *)
hReset := Data.cmdReset;
Data.cmdReset := FALSE;

(* settings: a bad write is put back *)
ok := UT_ANALOG_CHECK(Set := Data.set, Id => setId, SpanBad => spanBad, Warn => cfgWarn);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := setId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_ANALOG_CHECK(Set := Data.set, Id => setId, SpanBad => spanBad, Warn => cfgWarn);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

(* the source *)
notFitted := InQ = UT_IOQ_UNUSED OR InQ = UT_IOQ_NOT_FITTED;
qBad := NOT notFitted AND NOT (InQ = UT_IOQ_OK OR InQ = UT_IOQ_FORCED);
inNaN := NOT (ABS(In) <= 3.4E38);
Data.sts.inBad := NOT InGood OR qBad;
Data.sts.notFitted := notFitted;

(* scaling and the signal checks *)
Data.sts.failLow := FALSE;
Data.sts.failHigh := FALSE;
Data.sts.underRange := FALSE;
Data.sts.overRange := FALSE;
engSpan := Data.set.engMax - Data.set.engMin;
IF NOT spanBad AND NOT inNaN THEN
  IF Data.set.signal = UT_AI_DIRECT THEN
    eng := In;
    pos := (In - Data.set.engMin) / engSpan;
  ELSE
    eng := UT_SCALE(In := In, InMin := Data.set.rawMin, InMax := Data.set.rawMax,
                    OutMin := Data.set.engMin, OutMax := Data.set.engMax, Clamp := FALSE);
    pos := (In - Data.set.rawMin) / (Data.set.rawMax - Data.set.rawMin);
  END_IF;
  IF ABS(Data.set.trimOffset) <= 3.4E38 THEN
    eng := eng + Data.set.trimOffset;   (* the field zero trim *)
  END_IF;
  CASE Data.set.signal OF
  UT_AI_0_20MA, UT_AI_0_10V:
    Data.sts.underRange := pos < 0.0;
    Data.sts.overRange := pos > 1.0;
  UT_AI_CUSTOM, UT_AI_DIRECT:
    pct := pos * 100.0;
    Data.sts.failLow := pct <= Data.set.customLowFail;
    Data.sts.failHigh := pct >= Data.set.customHighFail;
    Data.sts.underRange := NOT Data.sts.failLow AND pos < 0.0;
    Data.sts.overRange := NOT Data.sts.failHigh AND pos > 1.0;
  ELSE
    (* NE43, as a fraction of the 16 mA span: 3.6 mA = -0.025,
       3.8 mA = -0.0125, 20.5 mA = 1.03125, 21 mA = 1.0625 *)
    Data.sts.failLow := pos <= -0.025;
    Data.sts.underRange := pos > -0.025 AND pos < -0.0125;
    Data.sts.overRange := pos > 1.03125 AND pos < 1.0625;
    Data.sts.failHigh := pos >= 1.0625;
  END_CASE;
END_IF;
failing := inNaN OR Data.sts.inBad OR Data.sts.failLow OR Data.sts.failHigh;

(* the fault: ridden through for its delay; TRIP = BAD, WARN = UNCERTAIN *)
x := UT_PROT_RUN(TNow := TIME(), Cause := failing AND NOT spanBad AND NOT Data.simulate AND NOT notFitted,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.fault,
                 Sts := Data.sts.fault, St := stFault);
faulted := stFault.trip;
faultWarn := stFault.warn;

(* filter: fed usable readings only, so a failure holds the last good value *)
filt(In := eng, InGood := NOT spanBad AND NOT inNaN AND NOT notFitted
                          AND ((NOT failing AND NOT faulted) OR Data.set.faultAction = UT_AI_PASS),
     Tc := Data.set.filterTime, Mode := UT_FILTER_LOWPASS, Reset := FALSE);
IF filt.Good THEN
  haveGood := TRUE;
END_IF;

(* frozen: no change larger than frozenBand for its delay *)
IF NOT filt.Good OR ABS(filt.Out - refVal) > Data.set.frozenBand THEN
  refVal := filt.Out;
  x := UT_PROT_RUN(TNow := TIME(), Cause := FALSE, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                   Prot := Data.set.frozen, Sts := Data.sts.frozen, St := stFrozen);
ELSE
  x := UT_PROT_RUN(TNow := TIME(), Cause := NOT Data.simulate, ResetReq := resetReq,
                   RetryWindow := Data.set.retryWindow, Prot := Data.set.frozen, Sts := Data.sts.frozen, St := stFrozen);
END_IF;
frozenTrip := stFrozen.trip;
frozenWarn := stFrozen.warn;

(* the value *)
IF haveGood THEN
  v := filt.Out;
  IF Data.set.lowCutoff <> 0.0 AND v < Data.set.lowCutoff THEN
    v := Data.set.engMin;
  END_IF;
  IF Data.set.clamp AND NOT spanBad THEN
    IF Data.set.engMax >= Data.set.engMin THEN
      v := LIMIT(Data.set.engMin, v, Data.set.engMax);
    ELSE
      v := LIMIT(Data.set.engMax, v, Data.set.engMin);
    END_IF;
  END_IF;
ELSE
  v := Data.set.engMin;
END_IF;
IF Data.simulate THEN
  v := Data.simValue;
ELSIF spanBad OR faulted OR frozenTrip THEN
  CASE Data.set.faultAction OF
  UT_AI_MIN: v := Data.set.engMin;
  UT_AI_MAX: v := Data.set.engMax;
  UT_AI_SUBST: v := Data.set.substValue;
  END_CASE;
END_IF;
IF ABS(v) <= 3.4E38 THEN
  Value := v;
ELSIF NOT (ABS(Value) <= 3.4E38) THEN
  Value := 0.0;                  (* never a NaN or infinity out *)
END_IF;
IF spanBad THEN
  Percent := 0.0;
ELSE
  Percent := (Value - Data.set.engMin) / engSpan * 100.0;
END_IF;

(* quality *)
IF Data.simulate THEN
  Quality := UT_Q_SIM;
ELSIF spanBad OR faulted OR frozenTrip OR notFitted THEN
  Quality := UT_Q_BAD;
ELSIF failing OR faultWarn OR Data.sts.underRange OR Data.sts.overRange THEN
  Quality := UT_Q_UNCERTAIN;
ELSE
  Quality := UT_Q_GOOD;
END_IF;
Fault := Quality = UT_Q_BAD AND NOT notFitted;
Good := NOT (Quality = UT_Q_BAD);
Warning := Quality = UT_Q_UNCERTAIN OR frozenWarn OR Data.simulate OR cfgWarn;

(* status: config, not fitted, simulated, fault, warning, ok *)
stF := UT_F_NONE;
Data.det.timeLeft := T#0s;
IF spanBad THEN
  stCode := UT_ST_CONFIG;
  stF := setId;
ELSIF notFitted THEN
  stCode := UT_ST_NOT_FITTED;
ELSIF Data.simulate THEN
  stCode := UT_ST_SIMULATED;
  stF := UT_F_SIMULATED;
ELSIF faulted OR frozenTrip THEN
  IF faulted THEN
    stCode := UT_PROT_STATUS(Reset := Data.set.fault.reset, Sts := Data.sts.fault);
    Data.det.timeLeft := Data.sts.fault.timeLeft;
  ELSE
    stCode := UT_PROT_STATUS(Reset := Data.set.frozen.reset, Sts := Data.sts.frozen);
    Data.det.timeLeft := Data.sts.frozen.timeLeft;
  END_IF;
ELSIF failing OR faultWarn OR Data.sts.underRange OR Data.sts.overRange OR frozenWarn THEN
  stCode := UT_ST_WARNING;
  IF failing THEN
    Data.det.timeLeft := Data.sts.fault.timeLeft;
  END_IF;
ELSIF cfgWarn THEN
  stCode := UT_ST_WARN_SETTING;
  stF := setId;
ELSE
  stCode := UT_ST_OK;
END_IF;
IF stF = UT_F_NONE AND stCode <> UT_ST_OK AND stCode <> UT_ST_NOT_FITTED THEN
  IF frozenTrip OR (frozenWarn AND NOT failing AND NOT faulted) THEN
    stF := UT_F_FROZEN;
  ELSIF Data.sts.inBad THEN
    stF := UT_F_INPUT_BAD;
  ELSIF Data.sts.failLow OR Data.sts.underRange OR inNaN THEN
    stF := UT_F_SIGNAL_LOW;
  ELSIF Data.sts.failHigh OR Data.sts.overRange THEN
    stF := UT_F_SIGNAL_HIGH;
  END_IF;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := Data.simulate,
                               OutOfSpec := Quality = UT_Q_UNCERTAIN OR frozenWarn OR cfgWarn, Maint := FALSE);

Data.det.raw := In;
Data.sts.value := Value;
Data.sts.percent := Percent;
Data.sts.quality := Quality;
Data.sts.configBad := spanBad;
Data.sts.wrnConfig := cfgWarn;
v := 0.0;
IF ABS(Data.set.altFactor) <= 3.4E38 AND ABS(Data.set.altOffset) <= 3.4E38 THEN
  v := Value * Data.set.altFactor + Data.set.altOffset;
END_IF;
IF ABS(v) <= 3.4E38 THEN
  Data.sts.valueAlt := v;
ELSE
  Data.sts.valueAlt := 0.0;
END_IF;

(* the plug's answers *)
mGood := Good;
IF Good THEN mValue := Value; ELSE mValue := mNan; END_IF;
mFault := Fault;
mWarn := Warning;
mLocked := Data.sts.fault.locked OR Data.sts.frozen.locked;
mFitted := NOT notFitted;
mNe := Data.sts.ne107;
mStatus := stCode;
mFaultId := stF;
mUnit := Data.set.unit;

END_FUNCTION_BLOCK