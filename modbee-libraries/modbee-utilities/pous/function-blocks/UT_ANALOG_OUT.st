(* UT_ANALOG_OUT — engineering demand to an analog output card.

Auto: Out follows In. Hand (the Hand pin held, or the kept choice set.hand
from the Mode pin / cmdMode: 1 Hand, 2 Auto): Out is set.handValue; at the
change to Hand, handValue takes the present Out (bumpless). The demand is
clamped to outMin..outMax and ramped by rampUp / rampDown (engineering
units per rateUnit; 0 = no ramp; UT_RAMP, exact at any rate). Interlock
FALSE gives failValue at once (or holds with holdOnInterlock), in Hand
too; when it returns the output ramps back from there. A NaN demand holds
the output (wrnBadInput). OutRaw = rawMin..rawMax over engMin..engMax,
clamped to 0..65535. A span setting that is not usable: Fault, Out at
engMin. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_ANALOG_OUT
  VAR_INPUT
    In : REAL; (* engineering demand (Auto) *)
    Interlock : BOOL := TRUE; (* FALSE: failValue at once (or hold) *)
    Hand : BOOL; (* held: Hand while TRUE (a panel switch; not kept) *)
    Mode : INT := -1; (* request on change: 1 Hand, 2 Auto (kept in set.hand); -1 none *)
  END_VAR
  VAR_OUTPUT
    Ok : BOOL; (* no config fault, demand a number *)
    Out : REAL; (* engineering value actually output *)
    OutRaw : UINT; (* for %QW *)
    Limited : BOOL; (* clamped or ramping *)
    Fault : BOOL; (* config fault *)
  END_VAR
  VAR_IN_OUT
    Data : UT_ANALOG_OUT_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_ANALOG_OUT_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ramp : UT_RAMP;
    setOk : BOOL;
    modePrev : INT := -1;
    handNow : BOOL;
    handPrev : BOOL;
    demand : REAL;
    target : REAL;
    lo : REAL;
    hi : REAL;
    cfgBad : BOOL;
    badIn : BOOL;
    clamped : BOOL;
    sc : BOOL;
    rawR : REAL;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
(* the span must be usable; ramps and limits numbers *)
setOk := ABS(Data.set.engMax - Data.set.engMin) > 0.0 AND ABS(Data.set.engMax - Data.set.engMin) <= 3.4E38
      AND ABS(Data.set.rawMin) <= 3.4E38 AND ABS(Data.set.rawMax) <= 3.4E38
      AND ABS(Data.set.outMin) <= 3.4E38 AND ABS(Data.set.outMax) <= 3.4E38
      AND Data.set.rampUp >= 0.0 AND Data.set.rampUp <= 3.4E38 AND Data.set.rampDown >= 0.0 AND Data.set.rampDown <= 3.4E38
      AND (Data.set.rateUnit = UT_PER_SEC OR Data.set.rateUnit = UT_PER_MIN OR Data.set.rateUnit = UT_PER_HOUR
           OR Data.set.rateUnit = UT_PER_DAY)
      AND ABS(Data.set.failValue) <= 3.4E38 AND ABS(Data.set.handValue) <= 3.4E38;
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
cfgBad := NOT (ABS(Data.set.engMax - Data.set.engMin) > 0.0 AND ABS(Data.set.engMax - Data.set.engMin) <= 3.4E38);

(* Hand / Auto: the pin on change, the HMI once *)
IF Mode <> modePrev THEN
  IF Mode = 1 THEN Data.set.hand := TRUE; ELSIF Mode = 2 THEN Data.set.hand := FALSE; END_IF;
END_IF;
modePrev := Mode;
IF Data.cmdMode = 1 THEN Data.set.hand := TRUE; ELSIF Data.cmdMode = 2 THEN Data.set.hand := FALSE; END_IF;
Data.cmdMode := -1;
handNow := Hand OR Data.set.hand;
IF handNow AND NOT handPrev AND NOT keep.PowerUp THEN
  Data.set.handValue := Out;     (* bumpless into Hand *)
END_IF;
handPrev := handNow;
IF handNow THEN
  demand := Data.set.handValue;
ELSE
  demand := In;
END_IF;
badIn := NOT (ABS(demand) <= 3.4E38);

IF Data.set.outMin <= Data.set.outMax THEN
  lo := Data.set.outMin;
  hi := Data.set.outMax;
ELSE
  lo := Data.set.outMax;
  hi := Data.set.outMin;
END_IF;
clamped := FALSE;
IF cfgBad THEN
  ramp(In := Data.set.engMin, Track := TRUE);
ELSIF NOT Interlock THEN
  IF Data.set.holdOnInterlock THEN
    ramp(In := Out, Track := TRUE);
  ELSE
    ramp(In := Data.set.failValue, Track := TRUE);   (* at once, no ramp *)
  END_IF;
ELSIF badIn THEN
  ramp(In := Out, Track := TRUE);                     (* hold *)
ELSE
  target := demand;
  IF target > hi THEN
    target := hi;
    clamped := TRUE;
  ELSIF target < lo THEN
    target := lo;
    clamped := TRUE;
  END_IF;
  ramp(In := target, RateUp := Data.set.rampUp, RateDown := Data.set.rampDown, RateUnit := Data.set.rateUnit, Track := FALSE);
END_IF;
Out := ramp.Out;

(* raw value for the card *)
rawR := UT_SCALE(In := Out, InMin := Data.set.engMin, InMax := Data.set.engMax, OutMin := Data.set.rawMin,
                 OutMax := Data.set.rawMax, Clamp := FALSE, SpanBad => sc);
IF NOT (rawR >= 0.0) THEN
  clamped := TRUE;
  rawR := 0.0;
ELSIF rawR > 65535.0 THEN
  clamped := TRUE;
  rawR := 65535.0;
END_IF;
OutRaw := REAL_TO_UINT(rawR);
Limited := clamped OR ramp.Ramping;
Fault := cfgBad;
Ok := NOT cfgBad AND NOT badIn;

stF := UT_F_NONE;
IF cfgBad THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_ENG_MIN_MAX;
ELSIF NOT Interlock THEN
  stCode := UT_ST_INTERLOCK;
ELSIF badIn THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_VALUE_BAD;
ELSIF handNow THEN
  stCode := UT_ST_HAND_VALUE;
ELSIF NOT setOk THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSE
  stCode := UT_ST_AUTO;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.out := Out;
Data.sts.hand := handNow;
Data.sts.wrnBadInput := badIn;
Data.sts.configBad := cfgBad;
Data.sts.wrnConfig := NOT setOk;
Data.raw := OutRaw;

END_FUNCTION_BLOCK