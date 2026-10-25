(* UT_TOTALISER — totals from any meter: flow, energy, production, runtime;
day limit for a bore's take. Offers the UT_I_METER plug (Value = rate,
Total = lifetime total): wire the instance to a Meter or Flow pin - e.g. a
pump's Flow plug, so a pulse meter gives the no-flow check too (RUNTIME: no
value, HasValue FALSE - an estimate is not a measured flow).

countMethod, and where it reads:
  RATE      integrates the Flow plug's value (a rate in rateUnit); below
            lowCutoff counts as 0; countReverse: negative flow beyond
            lowCutoff counts into totalOut (reverse), not into Total
  PULSE     each rising edge of Pulse adds pulseValue (max one pulse per two
            scans; faster meters: node-uio PULSE_COUNT wired to Count)
  COUNT     Count (UDINT) from a hardware counter: each count adds
            pulseValue; exact in UDINT, a wrap past 2^32 (or rolloverAt) is
            counted, a drop of more than half the range is a counter restart
  REGISTER  the Meter plug's GetTotal() (exact LREAL), else the Register pin:
            adds each increase; a drop is a reset / glitch (nothing counted,
            only the part above where it was counts again); rolloverAt wraps
  CHANGE    the Level plug (a UT_VESSEL: its volume, any tank shape; else the
            value): rises to totalIn, falls to totalOut (deadband);
            Total / batch / periods / Rate take the rises, or the falls with
            changeCountFalls (a sump's drawdown while its pump runs)
  RUNTIME   while Active adds nominalRate over real time
  SAMPLE    every sampleTime adds the Flow value x sampleTime (a rate) or the
            value (sampleAsQuantity)
  SNAPSHOT  every sampleTime (or a Rollover) stores the meter's reading in
            snapshot, the previous one in prevSnapshot, the difference in
            period. Nothing is totalised.

scale multiplies every addition (and the rate); with inUnit and outUnit both
set, the additions and the rate are converted too.

A failed meter does not count (decision 24): from the first bad scan
(InGood FALSE for the raw inputs, the plug's GoodNow() FALSE) nothing is added;
with badEstimate (RATE / PULSE / SAMPLE) nominalRate is counted instead,
flagged as an estimate (tot.estimated, warning). REGISTER and COUNT catch up
when good again, limited by maxStep. After inputBad.delay: Good FALSE.
Meter failed: Running and Active, and nothing counted for noCount.delay:
Good FALSE, UT_F_METER_FAILED (a volume run on this meter ends). It
recovers when counting resumes.

Day limit: LimitReached = dayLimit > 0 AND today >= dayLimit (estimates
included); clears at the day close. Wire it to the bore pump's Inhibit.

Totals are kept in millionths of a unit in LINT (exact on every target),
in Data.tot, saved hourly (UT_KEEP) and at once on a reset, preset,
rollover, day close, when the day limit is reached and when a run ends
(Running falls: once per stop). Hour / day totals
and clock-aligned interval records need Clock (local time). *)

FUNCTION_BLOCK UT_TOTALISER IMPLEMENTS UT_I_METER
  VAR_INPUT
    Active : BOOL := TRUE; (* count only while TRUE (RUNTIME: the running signal) *)
    Running : BOOL; (* the meter should be counting now (pump runs); unwired = no meter-failed check *)
    Pulse : BOOL R_EDGE; (* PULSE: each rising edge *)
    Count : UDINT; (* COUNT: a hardware counter reading *)
    Register : LREAL; (* REGISTER / SNAPSHOT: the meter's own total (when Meter is unwired) *)
    InGood : BOOL := TRUE; (* the raw inputs' source is healthy *)
    Flow : UT_I_MEAS; (* RATE / SAMPLE *)
    Level : UT_I_MEAS; (* CHANGE *)
    Meter : UT_I_METER; (* REGISTER / SNAPSHOT from another meter *)
    Clock : DT; (* local time (hour / day totals, intervals, day limit); unwired = off *)
    Rollover : BOOL R_EDGE; (* close the user period *)
    ResetBatch : BOOL R_EDGE; (* batch to 0 *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* counting can be trusted *)
    Total : LREAL;
    Batch : LREAL;
    Today : LREAL;
    Rate : REAL;
    LimitReached : BOOL; (* today >= dayLimit (-> the bore pump's Inhibit) *)
    BatchDone : BOOL;
    IntervalDone : BOOL; (* one scan: an interval record was written *)
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_TOTAL_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_TOTAL_SET;
    keptGood : BOOL;
    keptTot : UT_TOTAL_TOT;
  END_VAR
  VAR
    vessel : UT_I_VESSEL; (* the Level plug as a vessel (CHANGE), NULL when it is not one *)
    hBatch : BOOL;
    runWas : BOOL; (* Running last scan (a run's end saves the totals once) *)
    hTotal : BOOL;
    hPreset : BOOL;
    hRoll : BOOL;
    keep : UT_KEEP;
    stBad : UT_PROT_ST;
    stNo : UT_PROT_ST;
    ncProt : UT_PROTECTION; (* noCount with its delay carried by the count watch *)
    ok : BOOL;
    x : BOOL;
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    elapsed : TIME;
    subMs : TIME;
    ms : LINT;
    unitSec : LREAL;
    v : LREAL; (* the reading this scan *)
    srcGood : BOOL; (* the source of this method is usable *)
    srcFitted : BOOL;
    noLink : BOOL; (* the plug this method needs is not wired *)
    valueOk : BOOL;
    estimating : BOOL;
    lastCountT : TIME; (* the last time something was counted *)
    chgRef : LREAL;
    chgValid : BOOL;
    nPulses : UDINT;
    nRejected : UDINT;
    rem : LREAL; (* millionths not yet counted *)
    remOut : LREAL;
    remEst : LREAL;
    q : LREAL; (* quantity this scan *)
    qOut : LREAL;
    qSwap : LREAL;
    qEst : LREAL;
    whole : LINT;
    stepQ : LREAL;
    wrapped : LREAL;
    cntR : UDINT;
    dCnt : UDINT;
    haveStep : BOOL;
    confirm : BOOL;
    closePeriod : BOOL;
    takeSnap : BOOL;
    saveNow : BOOL;
    saveNext : BOOL; (* an event this scan: the totals are saved on the next *)
    sampleAcc : TIME;
    nSamples : INT;
    sm : INT;
    sb : INT;
    lastEdge : TIME;
    fastUntil : TIME;
    evQ : LREAL;
    evT : TIME;
    evPeriod : TIME;
    evCount : INT;
    secs : LINT;
    newHour : LINT;
    newDay : LINT;
    dayClosed : BOOL;
    rateNow : LREAL;
    sinceEv : TIME;
    mult : LREAL;
    litIn : LREAL;
    litOut : LREAL;
    accIv : LINT;
    ivLen : TIME;
    ivMs : LINT;
    ivSlot : LINT := -1;
    ivAcc : TIME;
    slotNow : LINT;
    msDay : LINT;
    ivDone : BOOL;
    limitPrev : BOOL;
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
    mHasValue : BOOL := TRUE;
    mNe : UT_NE107;
    mStatus : UT_STATUS;
    mFaultId : UT_FAULT;
    mUnit : UT_UNIT;
    mTotal : LREAL;
    mTotalUnit : UT_UNIT;
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
  GetValue := mValue;               (* the rate; NaN when not Good *)
END_METHOD
METHOD PUBLIC GoodNow : BOOL
  GoodNow := mGood;
END_METHOD
METHOD PUBLIC HasValue : BOOL
  HasValue := mHasValue;
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
METHOD PUBLIC GetTotal : LREAL
  GetTotal := mTotal;
END_METHOD
METHOD PUBLIC TotalUnit : UT_UNIT
  TotalUnit := mTotalUnit;
END_METHOD

keep(TotalsEvery := T#1h, TotalsNow := saveNext);   (* an event last scan: save the totals now *)
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
IF keep.PowerUp THEN
  mNan := zero / zero;
END_IF;

(* settings: a bad write is put back *)
ok := UT_TOTAL_CHECK(Set := Data.set);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_TOTAL_CHECK(Set := Data.set);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
Data.sts.wrnConfig := NOT ok;

tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
  lastEdge := tCur - T#1h;
  fastUntil := tCur;
  lastCountT := tCur;
END_IF;
elapsed := tCur - tPrev;
tPrev := tCur;
IF elapsed < T#0s THEN
  elapsed := T#0s;
END_IF;
subMs := subMs + elapsed;
ms := TIME_TO_LINT(subMs);
subMs := subMs - LINT_TO_TIME(ms);

CASE Data.set.rateUnit OF
UT_PER_SEC: unitSec := 1.0;
UT_PER_MIN: unitSec := 60.0;
UT_PER_DAY: unitSec := 86400.0;
ELSE
  unitSec := 3600.0;
END_CASE;
CASE Data.set.inUnit OF
UT_VOL_L: litIn := 1.0;
UT_VOL_M3: litIn := 1000.0;
UT_VOL_ML: litIn := 1.0E6;
ELSE
  litIn := 0.0;
END_CASE;
CASE Data.set.outUnit OF
UT_VOL_L: litOut := 1.0;
UT_VOL_M3: litOut := 1000.0;
UT_VOL_ML: litOut := 1.0E6;
ELSE
  litOut := 0.0;
END_CASE;
IF litIn > 0.0 AND litOut > 0.0 THEN
  mult := Data.set.scale * litIn / litOut;
ELSE
  mult := Data.set.scale;
END_IF;

(* the source of this method: its reading and its health *)
v := 0.0;
srcGood := InGood;
srcFitted := TRUE;
noLink := FALSE;
CASE Data.set.countMethod OF
UT_TM_RATE, UT_TM_SAMPLE:
  IF Flow <> NULL THEN
    v := Flow.GetValue();
    srcFitted := Flow.IsFitted();
    srcGood := Flow.GoodNow();
  ELSE
    noLink := TRUE;
    srcGood := FALSE;
  END_IF;
UT_TM_CHANGE:
  IF Level <> NULL THEN
    vessel ?= Level;                 (* a vessel counts its volume, any tank shape *)
    IF vessel <> NULL THEN
      v := vessel.GetVolume();
    ELSE
      v := Level.GetValue();
    END_IF;
    srcFitted := Level.IsFitted();
    srcGood := Level.GoodNow();
  ELSE
    noLink := TRUE;
    srcGood := FALSE;
  END_IF;
UT_TM_REGISTER, UT_TM_SNAPSHOT:
  IF Meter <> NULL THEN
    v := Meter.GetTotal();
    srcFitted := Meter.IsFitted();
    srcGood := Meter.GoodNow();
  ELSE
    v := Register;
  END_IF;
END_CASE;
valueOk := v = v AND v < 1.0E300 AND v > -1.0E300;
IF NOT srcFitted THEN
  srcGood := FALSE;
END_IF;
Data.sts.wrnBadValue := srcGood AND NOT valueOk AND Data.set.countMethod <> UT_TM_PULSE
                        AND Data.set.countMethod <> UT_TM_RUNTIME AND Data.set.countMethod <> UT_TM_COUNT;
IF NOT valueOk THEN
  srcGood := FALSE;
END_IF;
IF Data.set.countMethod = UT_TM_RUNTIME THEN
  srcGood := TRUE;               (* nothing to read *)
END_IF;

(* hour and day periods, against the clock (before this scan's addition) *)
dayClosed := FALSE;
secs := DT_TO_LINT(Clock);
IF secs > 0 THEN
  newHour := secs / 3600;
  newDay := secs / 86400;
  IF newHour > Data.tot.hourNo THEN
    IF Data.tot.hourNo > 0 AND newHour = Data.tot.hourNo + 1 THEN
      Data.tot.lastHour := Data.tot.hour;
    ELSE
      Data.tot.lastHour := 0;
    END_IF;
    Data.tot.hour := 0;
    Data.tot.hourNo := newHour;
  ELSIF newHour < Data.tot.hourNo THEN
    Data.tot.hourNo := newHour;  (* clock set back: nothing closes *)
  END_IF;
  IF newDay > Data.tot.dayNo THEN
    IF Data.tot.dayNo > 0 AND newDay = Data.tot.dayNo + 1 THEN
      Data.tot.yesterday := Data.tot.day;
    ELSE
      Data.tot.yesterday := 0;
    END_IF;
    dayClosed := Data.tot.dayNo > 0;
    Data.tot.day := 0;
    Data.tot.dayNo := newDay;
  ELSIF newDay < Data.tot.dayNo THEN
    Data.tot.dayNo := newDay;
  END_IF;
END_IF;

(* interval records (before this scan's addition) *)
ivDone := FALSE;
IF Data.set.recordEvery <> ivLen THEN
  ivLen := Data.set.recordEvery;
  ivSlot := -1;
  ivAcc := T#0s;
  accIv := 0;
END_IF;
IF ivLen > T#0s THEN
  ivMs := TIME_TO_LINT(ivLen);
  IF ivMs < 1 THEN
    ivMs := 1;
  END_IF;
  IF secs > 0 THEN
    msDay := (secs MOD 86400) * 1000;
    slotNow := (secs / 86400) * 100000000 + msDay / ivMs;
    IF ivSlot < 0 THEN
      ivSlot := slotNow;
    ELSIF slotNow > ivSlot THEN
      ivDone := TRUE;
      ivSlot := slotNow;
    ELSIF slotNow < ivSlot THEN
      ivSlot := slotNow;
    END_IF;
    ivAcc := T#0s;
  ELSE
    ivSlot := -1;
    ivAcc := ivAcc + elapsed;
    IF ivAcc >= ivLen THEN
      ivDone := TRUE;
      ivAcc := ivAcc - ivLen;
      IF ivAcc >= ivLen THEN
        ivAcc := T#0s;
      END_IF;
    END_IF;
  END_IF;
  IF ivDone THEN
    Data.sts.intervalVolume := LINT_TO_LREAL(accIv / 1000000) + LINT_TO_LREAL(accIv MOD 1000000) / 1.0E6;
    Data.sts.intervalTotal := LINT_TO_LREAL(Data.tot.total / 1000000) + LINT_TO_LREAL(Data.tot.total MOD 1000000) / 1.0E6;
    IF secs > 0 THEN
      Data.sts.intervalEnd := LINT_TO_DT((secs / 86400) * 86400 + (msDay - msDay MOD ivMs) / 1000);
    ELSE
      Data.sts.intervalEnd := Clock;
    END_IF;
    Data.sts.intervalSeq := Data.sts.intervalSeq + 1;
    accIv := 0;
  END_IF;
END_IF;

(* what this scan adds: nothing from a bad source *)
q := 0.0;
qOut := 0.0;
qEst := 0.0;
takeSnap := FALSE;
IF Pulse THEN
  IF nPulses < 16#FFFFFFFF THEN
    nPulses := nPulses + 1;
  END_IF;
END_IF;

CASE Data.set.countMethod OF
UT_TM_PULSE:
  IF Pulse AND srcGood THEN
    IF tCur - lastEdge <= elapsed + elapsed + elapsed / 2 AND elapsed > T#0s THEN
      fastUntil := tCur + T#5s;  (* at the limit: one pulse every two scans *)
    END_IF;
    lastEdge := tCur;
    IF Active THEN
      q := REAL_TO_LREAL(Data.set.pulseValue) * mult;
      IF evCount > 0 THEN
        evPeriod := tCur - evT;
      END_IF;
      evQ := q;
      evT := tCur;
      IF evCount < 2 THEN
        evCount := evCount + 1;
      END_IF;
    END_IF;
  END_IF;

UT_TM_COUNT:
  IF srcGood THEN                (* a bad counter is read again when good: it kept counting *)
    IF Data.set.rolloverAt >= 2.0 AND Data.set.rolloverAt < 4294967295.5 THEN
      cntR := REAL_TO_UDINT(Data.set.rolloverAt);
    ELSE
      cntR := 0;
    END_IF;
    haveStep := FALSE;
    IF NOT Data.tot.regValid THEN
      Data.tot.cnt := Count;
      Data.tot.regValid := TRUE;
      Data.tot.regDropped := FALSE;
    ELSIF Count <> Data.tot.cnt THEN
      IF Count > Data.tot.cnt THEN
        dCnt := Count - Data.tot.cnt;
      ELSIF cntR = 0 THEN
        dCnt := Count - Data.tot.cnt;   (* modulo 2^32 *)
        IF dCnt >= 16#80000000 THEN
          dCnt := Count;                (* it restarted from 0 *)
        END_IF;
      ELSIF Data.tot.cnt < cntR AND Count + (cntR - Data.tot.cnt) < cntR / 2 THEN
        dCnt := Count + (cntR - Data.tot.cnt);
      ELSE
        dCnt := Count;
      END_IF;
      Data.tot.cnt := Count;
      stepQ := UDINT_TO_LREAL(dCnt);
      haveStep := dCnt > 0;
    END_IF;
    IF haveStep THEN
      IF Data.set.maxStep > 0.0 AND stepQ > Data.set.maxStep THEN
        nRejected := nRejected + 1;
        Data.sts.wrnRegisterJump := TRUE;
      ELSIF Active THEN
        q := stepQ * Data.set.pulseValue * mult;
        Data.sts.wrnRegisterJump := FALSE;
      END_IF;
    END_IF;
    IF q <> 0.0 THEN
      IF evCount > 0 THEN
        evPeriod := tCur - evT;
      END_IF;
      evQ := q;
      evT := tCur;
      IF evCount < 2 THEN
        evCount := evCount + 1;
      END_IF;
    END_IF;
  END_IF;

UT_TM_REGISTER:
  IF srcGood THEN
    haveStep := FALSE;
    IF NOT Data.tot.regValid THEN
      Data.tot.reg := v;
      Data.tot.regValid := TRUE;
      Data.tot.regDropped := FALSE;
    ELSIF v > Data.tot.reg THEN
      IF Data.tot.regDropped AND v >= Data.tot.regBefore THEN
        stepQ := v - Data.tot.regBefore;
      ELSE
        stepQ := v - Data.tot.reg;
      END_IF;
      Data.tot.regDropped := FALSE;
      haveStep := TRUE;
      Data.tot.reg := v;
    ELSIF v < Data.tot.reg THEN
      wrapped := v + Data.set.rolloverAt - Data.tot.reg;
      IF Data.set.rolloverAt > 0.0 AND NOT Data.tot.regDropped AND wrapped > 0.0 AND wrapped < Data.set.rolloverAt * 0.5 THEN
        stepQ := wrapped;
        haveStep := TRUE;
      ELSIF NOT Data.tot.regDropped THEN
        Data.tot.regDropped := TRUE;
        Data.tot.regBefore := Data.tot.reg;
        nRejected := nRejected + 1;
        Data.sts.wrnRegisterJump := TRUE;
      END_IF;
      Data.tot.reg := v;
    END_IF;
    IF haveStep THEN
      IF Data.set.maxStep > 0.0 AND stepQ > Data.set.maxStep THEN
        nRejected := nRejected + 1;
        Data.sts.wrnRegisterJump := TRUE;
      ELSIF Active THEN
        q := stepQ * mult;
        Data.sts.wrnRegisterJump := FALSE;
      END_IF;
    END_IF;
    IF q <> 0.0 THEN
      IF evCount > 0 THEN
        evPeriod := tCur - evT;
      END_IF;
      evQ := q;
      evT := tCur;
      IF evCount < 2 THEN
        evCount := evCount + 1;
      END_IF;
    END_IF;
  END_IF;

UT_TM_CHANGE:
  IF srcGood THEN
    IF NOT chgValid OR NOT Active THEN
      chgRef := v;
      chgValid := TRUE;
    ELSIF v - chgRef >= Data.set.deadband AND v > chgRef THEN
      q := (v - chgRef) * mult;
      chgRef := v;
    ELSIF chgRef - v >= Data.set.deadband AND v < chgRef THEN
      qOut := (chgRef - v) * mult;
      chgRef := v;
    END_IF;
    IF q <> 0.0 OR qOut <> 0.0 THEN
      IF evCount > 0 THEN
        evPeriod := tCur - evT;
      END_IF;
      IF Data.set.changeCountFalls THEN
        evQ := qOut - q;
      ELSE
        evQ := q - qOut;
      END_IF;
      evT := tCur;
      IF evCount < 2 THEN
        evCount := evCount + 1;
      END_IF;
    END_IF;
  ELSE
    chgValid := FALSE;           (* start again from the next good reading *)
  END_IF;

UT_TM_RUNTIME:
  IF Active THEN
    q := Data.set.nominalRate * mult * LINT_TO_LREAL(ms) / (1000.0 * unitSec);
  END_IF;

UT_TM_SAMPLE, UT_TM_SNAPSHOT:
  IF Data.set.sampleTime > T#0s AND (Active OR Data.set.countMethod = UT_TM_SNAPSHOT) THEN
    sampleAcc := sampleAcc + elapsed;
    nSamples := 0;
    IF sampleAcc / 1000 >= Data.set.sampleTime THEN
      nSamples := 1000;
      sampleAcc := T#0s;
    ELSE
      sm := 512;
      FOR sb := 1 TO 10 DO
        IF sampleAcc / sm >= Data.set.sampleTime THEN
          sampleAcc := sampleAcc - Data.set.sampleTime * sm;
          nSamples := nSamples + sm;
        END_IF;
        sm := sm / 2;
      END_FOR;
    END_IF;
    IF nSamples > 0 AND srcGood THEN
      IF Data.set.countMethod = UT_TM_SNAPSHOT THEN
        takeSnap := TRUE;
      ELSIF Data.set.sampleAsQuantity THEN
        q := v * mult * INT_TO_LREAL(nSamples);
      ELSE
        q := v * mult * INT_TO_LREAL(nSamples) * LINT_TO_LREAL(TIME_TO_LINT(Data.set.sampleTime)) / (1000.0 * unitSec);
      END_IF;
    END_IF;
  ELSE
    sampleAcc := T#0s;
  END_IF;

ELSE                             (* UT_TM_RATE *)
  IF Active AND srcGood THEN
    IF v >= Data.set.lowCutoff THEN
      q := v * mult * LINT_TO_LREAL(ms) / (1000.0 * unitSec);
    ELSIF Data.set.countReverse AND v <= -Data.set.lowCutoff AND v < 0.0 THEN
      qOut := -v * mult * LINT_TO_LREAL(ms) / (1000.0 * unitSec);   (* reverse flow *)
    END_IF;
  END_IF;
END_CASE;
Data.sts.wrnPulseTooFast := tCur < fastUntil;

(* a bad source with badEstimate: count nominalRate as an estimate *)
estimating := Data.set.badEstimate AND Active AND NOT srcGood
              AND (Data.set.countMethod = UT_TM_RATE OR Data.set.countMethod = UT_TM_PULSE
                   OR Data.set.countMethod = UT_TM_SAMPLE);
IF estimating THEN
  qEst := Data.set.nominalRate * mult * LINT_TO_LREAL(ms) / (1000.0 * unitSec);
  q := q + qEst;
END_IF;

(* add it: whole millionths to every total, the rest carried *)
IF NOT (q = q) OR q > 1.0E9 OR q < -1.0E9 THEN
  q := 0.0;
  qEst := 0.0;
  Data.sts.wrnBadValue := TRUE;
END_IF;
IF NOT (qOut = qOut) OR qOut > 1.0E9 OR qOut < -1.0E9 THEN
  qOut := 0.0;
END_IF;
IF Data.set.countMethod = UT_TM_CHANGE AND Data.set.changeCountFalls THEN
  qSwap := q;
  q := qOut;
  qOut := qSwap;
END_IF;
IF q > 0.0 OR qOut > 0.0 THEN
  IF NOT estimating THEN
    lastCountT := tCur;
  END_IF;
END_IF;
IF Data.set.countMethod = UT_TM_RATE AND Active AND srcGood AND ABS(v) >= Data.set.lowCutoff AND v <> 0.0 THEN
  lastCountT := tCur;            (* a flow is a count, even below a millionth this scan *)
END_IF;
rem := rem + q * 1.0E6;
whole := LREAL_TO_LINT(rem);
rem := rem - LINT_TO_LREAL(whole);
Data.tot.total := Data.tot.total + whole;
Data.tot.batch := Data.tot.batch + whole;
Data.tot.period := Data.tot.period + whole;
IF secs > 0 THEN
  Data.tot.hour := Data.tot.hour + whole;
  Data.tot.day := Data.tot.day + whole;
END_IF;
IF ivLen > T#0s THEN
  accIv := accIv + whole;
END_IF;
IF Data.set.countMethod = UT_TM_CHANGE AND Data.set.changeCountFalls THEN
  Data.tot.out := Data.tot.out + whole;
ELSIF Data.set.countMethod = UT_TM_CHANGE THEN
  Data.tot.in := Data.tot.in + whole;
END_IF;
remEst := remEst + qEst * 1.0E6;
whole := LREAL_TO_LINT(remEst);
remEst := remEst - LINT_TO_LREAL(whole);
Data.tot.estimated := Data.tot.estimated + whole;
remOut := remOut + qOut * 1.0E6;
whole := LREAL_TO_LINT(remOut);
remOut := remOut - LINT_TO_LREAL(whole);
IF Data.set.countMethod = UT_TM_CHANGE AND Data.set.changeCountFalls THEN
  Data.tot.in := Data.tot.in + whole;
ELSE
  Data.tot.out := Data.tot.out + whole;
END_IF;

(* commands and edges *)
saveNow := dayClosed;
(* a run's end: the totals kept at once - once per stop, on the edge, never every scan - so a blackout after the
   pump has stopped loses nothing of that run (between the hourly saves only a cut DURING a run can lose counts) *)
IF runWas AND NOT Running THEN
  saveNow := TRUE;
END_IF;
runWas := Running;
(* HMI commands act once per request, even when held on *)
IF (Data.cmdResetBatch AND NOT hBatch) OR ResetBatch THEN
  Data.tot.batch := 0;
  saveNow := TRUE;
END_IF;
hBatch := Data.cmdResetBatch;
Data.cmdResetBatch := FALSE;
confirm := Data.cmdConfirm;
IF Data.cmdResetTotal AND NOT hTotal AND confirm THEN
  Data.tot.total := 0;
  Data.tot.in := 0;
  Data.tot.out := 0;
  Data.tot.estimated := 0;
  saveNow := TRUE;
END_IF;
hTotal := Data.cmdResetTotal;
Data.cmdResetTotal := FALSE;
Data.cmdConfirm := FALSE;
IF Data.cmdPreset AND NOT hPreset AND Data.presetTotal >= 0.0 AND Data.presetTotal <= 1.0E12 THEN
  whole := LREAL_TO_LINT(Data.presetTotal);
  IF LINT_TO_LREAL(whole) > Data.presetTotal THEN
    whole := whole - 1;
  END_IF;
  Data.tot.total := whole * 1000000 + LREAL_TO_LINT((Data.presetTotal - LINT_TO_LREAL(whole)) * 1.0E6);
  saveNow := TRUE;
END_IF;
hPreset := Data.cmdPreset;
Data.cmdPreset := FALSE;
closePeriod := (Data.cmdRollover AND NOT hRoll) OR Rollover;
hRoll := Data.cmdRollover;
Data.cmdRollover := FALSE;
IF closePeriod THEN
  IF Data.set.countMethod = UT_TM_SNAPSHOT THEN
    takeSnap := srcGood;
  ELSE
    Data.tot.prevPeriod := Data.tot.period;
    Data.tot.period := 0;
  END_IF;
  saveNow := TRUE;
END_IF;
IF takeSnap THEN
  IF Data.tot.snapValid THEN
    Data.tot.prevSnap := Data.tot.snap;
    Data.tot.snap := v;
    Data.tot.prevPeriod := Data.tot.period;
    Data.tot.period := LREAL_TO_LINT((Data.tot.snap - Data.tot.prevSnap) * 1.0E6);
    IF evCount > 0 THEN
      evPeriod := tCur - evT;
    END_IF;
    evQ := Data.tot.snap - Data.tot.prevSnap;
    evT := tCur;
    evCount := 2;
    lastCountT := tCur;
  ELSE
    Data.tot.snap := v;
    Data.tot.prevSnap := v;
    Data.tot.snapValid := TRUE;
    evT := tCur;
    evCount := 1;
  END_IF;
END_IF;

(* rate *)
rateNow := 0.0;
IF srcGood OR Data.set.countMethod = UT_TM_RUNTIME THEN
  CASE Data.set.countMethod OF
  UT_TM_RATE:
    IF Active AND v >= Data.set.lowCutoff THEN
      rateNow := v * mult;
    END_IF;
  UT_TM_RUNTIME:
    IF Active THEN
      rateNow := Data.set.nominalRate * mult;
    END_IF;
  UT_TM_SAMPLE:
    IF Active THEN
      IF Data.set.sampleAsQuantity THEN
        IF Data.set.sampleTime > T#0s THEN
          rateNow := v * mult * unitSec * 1000.0 / LINT_TO_LREAL(TIME_TO_LINT(Data.set.sampleTime));
        END_IF;
      ELSE
        rateNow := v * mult;
      END_IF;
    END_IF;
  ELSE
    IF evCount >= 2 AND (Active OR Data.set.countMethod = UT_TM_SNAPSHOT) THEN
      sinceEv := tCur - evT;
      IF sinceEv < evPeriod THEN
        sinceEv := evPeriod;
      END_IF;
      IF sinceEv > T#0s THEN
        rateNow := evQ * unitSec * 1000.0 / LINT_TO_LREAL(TIME_TO_LINT(sinceEv));
      END_IF;
    END_IF;
  END_CASE;
ELSIF estimating THEN
  rateNow := Data.set.nominalRate * mult;
END_IF;
IF NOT (rateNow = rateNow) OR rateNow < Data.set.lowCutoff * mult THEN
  rateNow := 0.0;
END_IF;

(* the meter's health: input bad, meter failed *)
x := UT_PROT_RUN(TNow := tCur, Cause := NOT srcGood AND NOT noLink AND srcFitted
                                       AND Data.set.countMethod <> UT_TM_RUNTIME,
                 ResetReq := FALSE, RetryWindow := Data.set.retryWindow, Prot := Data.set.inputBad,
                 Sts := Data.sts.inputBad, St := stBad);
IF NOT (Running AND Active) OR NOT srcGood THEN
  lastCountT := tCur;            (* watch only while it should be counting from a good source *)
END_IF;
ncProt := Data.set.noCount;
ncProt.delay := T#0s;
x := UT_PROT_RUN(TNow := tCur, Cause := tCur - lastCountT >= Data.set.noCount.delay,
                 ResetReq := FALSE, RetryWindow := Data.set.retryWindow, Prot := ncProt,
                 Sts := Data.sts.noCount, St := stNo);

(* outputs *)
Data.sts.total := LINT_TO_LREAL(Data.tot.total / 1000000) + LINT_TO_LREAL(Data.tot.total MOD 1000000) / 1.0E6;
Data.sts.batch := LINT_TO_LREAL(Data.tot.batch / 1000000) + LINT_TO_LREAL(Data.tot.batch MOD 1000000) / 1.0E6;
Data.det.period := LINT_TO_LREAL(Data.tot.period / 1000000) + LINT_TO_LREAL(Data.tot.period MOD 1000000) / 1.0E6;
Data.sts.prevPeriod := LINT_TO_LREAL(Data.tot.prevPeriod / 1000000) + LINT_TO_LREAL(Data.tot.prevPeriod MOD 1000000) / 1.0E6;
Data.det.thisHour := LINT_TO_LREAL(Data.tot.hour / 1000000) + LINT_TO_LREAL(Data.tot.hour MOD 1000000) / 1.0E6;
Data.sts.lastHour := LINT_TO_LREAL(Data.tot.lastHour / 1000000) + LINT_TO_LREAL(Data.tot.lastHour MOD 1000000) / 1.0E6;
Data.sts.today := LINT_TO_LREAL(Data.tot.day / 1000000) + LINT_TO_LREAL(Data.tot.day MOD 1000000) / 1.0E6;
Data.sts.yesterday := LINT_TO_LREAL(Data.tot.yesterday / 1000000) + LINT_TO_LREAL(Data.tot.yesterday MOD 1000000) / 1.0E6;
Data.sts.totalIn := LINT_TO_LREAL(Data.tot.in / 1000000) + LINT_TO_LREAL(Data.tot.in MOD 1000000) / 1.0E6;
Data.sts.totalOut := LINT_TO_LREAL(Data.tot.out / 1000000) + LINT_TO_LREAL(Data.tot.out MOD 1000000) / 1.0E6;
Data.det.snapshot := Data.tot.snap;
Data.det.prevSnapshot := Data.tot.prevSnap;
Data.det.pulses := nPulses;
Data.det.rejectedSteps := nRejected;
Data.sts.rate := LREAL_TO_REAL(rateNow);
Total := Data.sts.total;
Batch := Data.sts.batch;
Today := Data.sts.today;
Rate := Data.sts.rate;
BatchDone := Data.set.batchTarget > 0.0 AND Data.sts.batch >= Data.set.batchTarget;
IntervalDone := ivDone;
LimitReached := Data.set.dayLimit > 0.0 AND Data.sts.today >= Data.set.dayLimit;
IF LimitReached AND NOT limitPrev THEN
  saveNow := TRUE;               (* a power cut must not lift it *)
END_IF;
limitPrev := LimitReached;
Good := NOT noLink AND srcFitted AND NOT stBad.trip AND NOT stNo.trip;
Warning := estimating OR Data.sts.wrnRegisterJump OR Data.sts.wrnPulseTooFast OR Data.sts.wrnBadValue
           OR Data.sts.wrnConfig OR stBad.warn OR stNo.warn OR (NOT srcGood AND NOT noLink AND srcFitted);

(* status *)
stF := UT_F_NONE;
Data.det.timeLeft := T#0s;
IF noLink THEN
  stCode := UT_ST_CONFIG;
  stF := UT_F_NO_LINK;
ELSIF NOT srcFitted THEN
  stCode := UT_ST_NOT_FITTED;
ELSIF stBad.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.inputBad.reset, Sts := Data.sts.inputBad);
  stF := UT_F_INPUT_BAD;
ELSIF stNo.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.noCount.reset, Sts := Data.sts.noCount);
  stF := UT_F_METER_FAILED;
ELSIF LimitReached THEN
  stCode := UT_ST_DAY_LIMIT;
ELSIF estimating THEN
  stCode := UT_ST_ESTIMATING;
  stF := UT_F_ESTIMATED;
ELSIF NOT srcGood OR stBad.warn THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_INPUT_BAD;
  Data.det.timeLeft := Data.sts.inputBad.timeLeft;
ELSIF stNo.warn THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_METER_FAILED;
ELSIF Data.sts.wrnRegisterJump THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_REGISTER_JUMP;
ELSIF Data.sts.wrnConfig THEN
  stCode := UT_ST_WARN_SETTING;
  stF := UT_F_SETTING;
ELSIF Active AND rateNow > 0.0 THEN
  stCode := UT_ST_RUNNING;
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
Data.sts.good := Good;
Data.sts.limitReached := LimitReached;
Data.sts.estimating := estimating;
Data.sts.configBad := noLink;
Data.sts.ne107 := UT_NE107_RUN(Fault := NOT Good AND srcFitted, Check := FALSE,
                               OutOfSpec := Warning OR LimitReached, Maint := FALSE);

saveNext := saveNow;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

(* the plug's answers *)
mGood := Good;
IF Good THEN mValue := Data.sts.rate; ELSE mValue := mNan; END_IF;
mFault := NOT Good AND srcFitted;
mWarn := Warning;
mLocked := Data.sts.inputBad.locked OR Data.sts.noCount.locked;
mFitted := srcFitted;
mHasValue := Data.set.countMethod <> UT_TM_RUNTIME;   (* run time x rate is an estimate, not a measured flow *)
mNe := Data.sts.ne107;
mStatus := stCode;
mFaultId := stF;
mTotal := Data.sts.total;
CASE Data.set.outUnit OF
UT_VOL_L: mTotalUnit := UT_UNIT_L;
UT_VOL_M3: mTotalUnit := UT_UNIT_M3;
UT_VOL_ML: mTotalUnit := UT_UNIT_ML;
ELSE
  mTotalUnit := UT_UNIT_NONE;
END_CASE;
mUnit := UT_UNIT_NONE;
IF Data.set.outUnit = UT_VOL_M3 AND Data.set.rateUnit = UT_PER_HOUR THEN
  mUnit := UT_UNIT_M3H;
ELSIF Data.set.outUnit = UT_VOL_L AND Data.set.rateUnit = UT_PER_SEC THEN
  mUnit := UT_UNIT_LPS;
ELSIF Data.set.outUnit = UT_VOL_L AND Data.set.rateUnit = UT_PER_MIN THEN
  mUnit := UT_UNIT_LPM;
END_IF;

END_FUNCTION_BLOCK