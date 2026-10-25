(* UT_DOSE — dosing and batching: FLOW-paced fertigation, TIMED, BATCH.

BATCH   a rising Run, Start or cmdStart delivers the target quantity: Fast
        until slowAt is left, then Slow, stopping early by the in-flight
        quantity (preact), then settleTime and the result. learnPreact
        corrects the preact by half of each dose's error (doses more than
        25 % off are not learned from), between 0 and half the target; the
        learned preact is written to set.preact at a dose's end. Delivered
        = Actual.GetValue(), or the rise of Meter.GetTotal() (actualIsTotal).
FLOW    while Run (per set.run.style) or the Start latch: the dosing pump
        runs in proportion to the carrier flow (Meter rate x ratio, Ratio pin
        for this run), Rate = required / pumpCapacity %, capped at maxRate;
        stroke pulses every pulseVolume dosed. It injects only while
        CarrierRunning and the carrier flow has been at or above minFlow for
        carrierProven ("Waiting: low carrier", not a fault).
TIMED   while Run: on for onTime, off for offTime (CarrierRunning too).
Hand    Start runs the pump at handRate until Stop or handMax; the carrier
        condition per handNeedsCarrier.

Every mode: Interlock FALSE outputs off (FLOW / TIMED resume by themselves,
a BATCH is held); StockLow -> the stockLow protection; Hold (pin, level) and
cmdHold (until the next start) pause; Stop / cmdAbort / Abort end the dose
(a held Run must drop); maxTime and maxQuantity cap a dose. Pump (optional
UT_I_MOTOR): Request(PumpRun, NOT Interlock, Rate, tag); dosing counts only
while it runs. Totals (tot) kept hourly and on events; settings kept, a bad
write put back. *)

FUNCTION_BLOCK UT_DOSE
  VAR_INPUT
    Run : BOOL; (* Auto: FLOW / TIMED dose while TRUE; BATCH: rising starts a dose *)
    Start : BOOL R_EDGE; (* BATCH start / resume; FLOW / TIMED latch; Hand start *)
    Stop : BOOL R_EDGE; (* end the dose (a held Run must drop) *)
    Reset : BOOL R_EDGE;
    Mode : INT := -1; (* 0 Off, 1 Hand, 2 Auto *)
    SwHand : BOOL;
    SwAuto : BOOL;
    Interlock : BOOL := TRUE; (* FALSE: outputs off in every mode *)
    Permissive : BOOL := TRUE; (* holds back a dose start *)
    CarrierRunning : BOOL := TRUE; (* the irrigation pump runs *)
    StockLow : BOOL;
    Hold : BOOL; (* pause (level) *)
    Abort : BOOL; (* end, refuse a start *)
    Target : REAL; (* BATCH quantity (0 = set.target) *)
    Ratio : REAL; (* FLOW ratio of this run (<= 0 / NaN = set.ratio) *)
    Meter : UT_I_METER; (* FLOW: the carrier meter; BATCH actualIsTotal: the product meter *)
    Actual : UT_I_MEAS; (* BATCH: delivered so far (a scale) *)
    Pump : UT_I_MOTOR; (* optional dosing pump *)
  END_VAR
  VAR_OUTPUT
    PumpRun : BOOL; (* FLOW / TIMED / Hand *)
    Fast : BOOL; (* BATCH feeds *)
    Slow : BOOL;
    Rate : REAL; (* % *)
    RateRaw : UINT;
    PulseOut : BOOL;
    Done : BOOL; (* BATCH complete (one scan) *)
    Busy : BOOL;
    Fault : BOOL;
    Warning : BOOL;
    Remaining : REAL; (* BATCH *)
  END_VAR
  VAR_IN_OUT
    Data : UT_DOSE_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_DOSE_SET;
    keptGood : BOOL;
    keptTot : UT_DOSE_TOT;
  END_VAR
  VAR
    keep : UT_KEEP;
    modeSel : UT_MODE_SELECT;
    runIn : UT_RUN_INPUT;
    sNoFlow : UT_PROT_ST;
    sMax : UT_PROT_ST;
    sCap : UT_PROT_ST;
    sTol : UT_PROT_ST;
    sStock : UT_PROT_ST;
    ok : BOOL;
    cfgF : UT_FAULT;
    cfgW : UT_FAULT;
    x : BOOL;
    tCur : TIME;
    tPrev : TIME;
    dMs : LINT;
    dts : REAL;
    started : BOOL;
    hStart : BOOL;
    hAbort : BOOL;
    hHold : BOOL;
    hReset : BOOL;
    runPrev : BOOL;
    startReq : BOOL;
    stopReq : BOOL;
    resetReq : BOOL;
    holdLatch : BOOL;
    isAuto : BOOL;
    isHand : BOOL;
    dm : UT_DOSE_MODE; (* the mode of the dose (taken when idle) *)
    busyNow : BOOL;
    busyPrev : BOOL;
    paused : BOOL;
    stage : INT; (* BATCH: 1 fast, 2 slow, 3 settle *)
    settleStart : TIME;
    tgt : REAL;
    dlv : LREAL;
    startRef : LREAL;
    riseRef : LREAL;
    rose : BOOL;
    feeding : BOOL;
    pAct : REAL;
    pUse : REAL;
    err : REAL;
    tolCause : BOOL;
    perSec : REAL;
    flowV : REAL;
    flowGood : BOOL;
    carrierCond : BOOL;
    carrierSince : TIME;
    carrierOk : BOOL;
    ratioUse : REAL;
    reqRate : REAL;
    pct : REAL;
    cap : REAL;
    dosed : LREAL;
    cycOn : BOOL;
    cycAcc : TIME;
    pulseAcc : LREAL;
    owed : DINT;
    pulseOn : BOOL;
    pulseT : TIME;
    w : LINT;
    handRun : BOOL;
    pumpGo : BOOL;
    counting : BOOL;
    tripHold : BOOL;
    quantityEnd : BOOL;
    qtyHit : BOOL;
    endCode : UT_STOP;
    doseStart : TIME;
    doneNow : BOOL;
    zero : REAL;
    nan : REAL;
    actV : REAL;
    actGood : BOOL;
    totFrac : LREAL;
    tripCode : DWORD;
    tripPrev : DWORD;
    newBits : DWORD;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    tLeft : TIME;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
IF NOT started THEN
  started := TRUE;
  tPrev := tCur;
  nan := zero / zero;
  runPrev := Run;                (* a Run already on at power-up is not an edge *)
END_IF;
dMs := TIME_TO_LINT(tCur - tPrev);
IF dMs < 0 THEN
  dMs := 0;
  tPrev := tCur;
END_IF;
tPrev := tPrev + LINT_TO_TIME(dMs);
dts := LINT_TO_REAL(dMs) / 1000.0;

keep(TotalsNow := doneNow);
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
IF keep.RestoreTot THEN
  Data.tot := keptTot;
END_IF;
ok := UT_DOSE_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  IF cfgF <> UT_F_NONE THEN Data.sts.refused := cfgF; ELSE Data.sts.refused := cfgW; END_IF;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_DOSE_CHECK(S := Data.set, Fault => cfgF, Warn => cfgW);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
IF keep.PowerUp THEN
  pAct := Data.set.preact;
END_IF;

(* commands: once per request *)
startReq := Start OR (Data.cmdStart AND NOT hStart);
hStart := Data.cmdStart;
Data.cmdStart := FALSE;
stopReq := Stop OR (Data.cmdAbort AND NOT hAbort);
hAbort := Data.cmdAbort;
Data.cmdAbort := FALSE;
IF Data.cmdHold AND NOT hHold THEN
  holdLatch := TRUE;
END_IF;
hHold := Data.cmdHold;
Data.cmdHold := FALSE;
resetReq := Reset OR (Data.cmdReset AND NOT hReset);
hReset := Data.cmdReset;
Data.cmdReset := FALSE;
IF startReq THEN
  holdLatch := FALSE;
END_IF;
IF resetReq THEN
  qtyHit := FALSE;
END_IF;

(* the mode *)
modeSel(SwAuto := SwAuto, SwHand := SwHand, ForceOff := FALSE, HandOn := handRun, HandToOff := FALSE, AllowOOS := TRUE,
        Source := Data.set.modeSource, ModeReq := Mode, PowerUp := UT_PU_LAST, HandPowerUp := UT_HPU_OFF,
        HandMax := Data.set.handMax, CmdMode := Data.cmdMode, Choice := Data.set.mode);
isAuto := modeSel.Mode = UT_MODE_AUTO;
isHand := modeSel.Mode = UT_MODE_HAND;

(* the links *)
CASE Data.set.flowPer OF
UT_PER_SEC: perSec := 1.0;
UT_PER_MIN: perSec := 60.0;
UT_PER_DAY: perSec := 86400.0;
ELSE
  perSec := 3600.0;
END_CASE;
flowV := 0.0;
flowGood := FALSE;
IF Meter <> NULL THEN
  flowV := Meter.GetValue();
  flowGood := Meter.GoodNow() AND flowV = flowV AND ABS(flowV) <= 3.4E38;
END_IF;
actGood := FALSE;
actV := 0.0;
IF Data.set.actualIsTotal THEN
  IF Meter <> NULL THEN
    actV := LREAL_TO_REAL(Meter.GetTotal());
    actGood := Meter.GoodNow() AND actV = actV;
  END_IF;
ELSIF Actual <> NULL THEN
  actV := Actual.GetValue();
  actGood := Actual.GoodNow() AND actV = actV AND ABS(actV) <= 3.4E38;
END_IF;
carrierCond := CarrierRunning AND flowGood AND flowV >= Data.set.minFlow AND (Data.set.minFlow > 0.0 OR flowV > 0.0);
IF NOT carrierCond THEN
  carrierSince := tCur;
END_IF;
carrierOk := carrierCond AND tCur - carrierSince >= Data.set.carrierProven;

(* protections that hold every mode *)
x := UT_PROT_RUN(TNow := tCur, Cause := StockLow, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.stockLow, Sts := Data.sts.stockLow, St := sStock);
tripHold := sStock.trip OR (sCap.trip AND dm = UT_DOSE_FLOW) OR cfgF <> UT_F_NONE;

(* the Auto run request (FLOW / TIMED) *)
IF NOT busyNow THEN
  dm := Data.set.doseMode;       (* a mode change takes effect when idle *)
END_IF;
runIn(Run := Run AND isAuto, Start := startReq AND isAuto, Stop := stopReq OR Abort OR quantityEnd OR sMax.trip,
      CmdStart := FALSE, CmdStop := FALSE, Drop := NOT isAuto OR dm = UT_DOSE_BATCH OR cfgF <> UT_F_NONE,
      Linked := FALSE, TargetDone := FALSE, HasTarget := FALSE, Set := Data.set.run);
quantityEnd := FALSE;

IF NOT (pAct >= 0.0) THEN
  pAct := 0.0;
END_IF;
pUse := pAct;
IF tgt > 0.0 AND pUse > 0.5 * tgt THEN
  pUse := 0.5 * tgt;
END_IF;
dosed := 0.0;
doneNow := FALSE;
Fast := FALSE;
Slow := FALSE;
pumpGo := FALSE;
Rate := 0.0;
Data.sts.required := 0.0;
counting := Pump = NULL;
IF Pump <> NULL THEN
  counting := Pump.IsRunning();
END_IF;

IF isHand THEN
  (* Hand: Start runs the pump at handRate until Stop or handMax *)
  IF busyNow AND NOT handRun THEN
    busyNow := FALSE;            (* an Auto dose ends on leaving Auto *)
    endCode := UT_STOP_SWITCHED_OFF;
  END_IF;
  IF startReq AND Interlock AND NOT tripHold THEN
    handRun := TRUE;
    dlv := 0.0;
  END_IF;
  IF stopReq OR modeSel.HandUp OR NOT Interlock OR Abort THEN
    handRun := FALSE;
  END_IF;
  busyNow := handRun;
  IF handRun AND NOT tripHold AND (carrierOk OR NOT Data.set.handNeedsCarrier) THEN
    pumpGo := TRUE;
    Rate := LIMIT(0.0, Data.set.handRate, 100.0);
    IF counting THEN
      dosed := Data.set.pumpCapacity * Rate / 100.0 * dts / perSec;
    END_IF;
  END_IF;
  paused := handRun AND NOT pumpGo;
  stage := 0;
ELSIF NOT isAuto THEN
  (* Off / OOS: nothing *)
  IF busyNow THEN
    endCode := UT_STOP_SWITCHED_OFF;
  END_IF;
  busyNow := FALSE;
  handRun := FALSE;
  paused := FALSE;
  stage := 0;
ELSIF dm = UT_DOSE_BATCH THEN
  handRun := FALSE;
  startReq := startReq OR (Run AND NOT runPrev);
  IF busyNow AND actGood THEN
    IF Data.set.actualIsTotal THEN dlv := REAL_TO_LREAL(actV) - startRef; ELSE dlv := REAL_TO_LREAL(actV); END_IF;
  END_IF;
  IF startReq OR resetReq THEN
    tolCause := FALSE;           (* the last result is acknowledged *)
  END_IF;
  IF NOT busyNow THEN
    IF startReq AND NOT Abort AND NOT stopReq AND Permissive AND NOT tripHold
       AND NOT (sNoFlow.trip OR sMax.trip OR sTol.trip) THEN
      IF Target > 0.0 THEN tgt := Target; ELSE tgt := Data.set.target; END_IF;
      IF tgt > 0.0 AND tgt <= 3.4E38 THEN
        busyNow := TRUE;
        holdLatch := FALSE;
        IF Data.set.actualIsTotal AND actGood THEN
          startRef := REAL_TO_LREAL(actV);
          dlv := 0.0;
        ELSIF actGood THEN
          dlv := REAL_TO_LREAL(actV);
        ELSE
          dlv := 0.0;
        END_IF;
        riseRef := dlv;
        IF Data.set.slowAt >= tgt THEN stage := 2; ELSE stage := 1; END_IF;
      END_IF;
    END_IF;
  ELSIF stopReq OR Abort OR sMax.trip OR qtyHit THEN
    busyNow := FALSE;
    Data.sts.lastDelivered := dlv;
    Data.sts.lastError := LREAL_TO_REAL(dlv) - tgt;
    IF sMax.trip THEN endCode := UT_STOP_MAX_RUN;
    ELSIF qtyHit THEN endCode := UT_STOP_QUANTITY;
    ELSIF Abort THEN endCode := UT_STOP_ABORTED;
    ELSE endCode := UT_STOP_ABORT_CMD;
    END_IF;
  ELSE
    IF stage < 3 AND dlv >= REAL_TO_LREAL(tgt - pUse) THEN
      stage := 3;
      settleStart := tCur;
    ELSIF stage = 1 AND Data.set.slowAt > 0.0 AND dlv >= REAL_TO_LREAL(tgt - Data.set.slowAt) THEN
      stage := 2;
    END_IF;
    IF stage = 3 AND tCur - settleStart >= Data.set.settleTime THEN
      busyNow := FALSE;          (* complete *)
      doneNow := TRUE;
      endCode := UT_STOP_DONE;
      err := LREAL_TO_REAL(dlv) - tgt;
      Data.sts.lastDelivered := dlv;
      Data.sts.lastError := err;
      Data.tot.doses := Data.tot.doses + 1;
      IF Data.set.learnPreact AND ABS(err) <= 0.25 * tgt THEN
        pAct := LIMIT(0.0, pAct + 0.5 * err, 0.5 * tgt);
        Data.set.preact := pAct; (* written at a dose's end only *)
      END_IF;
      tolCause := Data.set.tolerance > 0.0 AND ABS(err) > Data.set.tolerance;
    END_IF;
  END_IF;
  IF busyNow THEN
    paused := Hold OR holdLatch OR NOT Interlock OR tripHold OR sNoFlow.trip OR sTol.trip;
    Fast := stage = 1 AND NOT paused;
    Slow := stage = 2 AND NOT paused;
    Remaining := MAX(0.0, tgt - LREAL_TO_REAL(dlv));
  ELSE
    paused := FALSE;
    Remaining := 0.0;
  END_IF;
  rose := dlv > riseRef;
  IF rose THEN
    dosed := dlv - riseRef;
    riseRef := dlv;
  END_IF;
  feeding := Fast OR Slow;
ELSE
  (* FLOW / TIMED while the run request is on *)
  handRun := FALSE;
  IF runIn.Request AND NOT runIn.BadSetting AND (busyNow OR Permissive) THEN
    IF NOT busyNow THEN
      busyNow := TRUE;
      holdLatch := FALSE;
      dlv := 0.0;
      cycOn := TRUE;
      cycAcc := T#0s;
      pulseAcc := 0.0;
      owed := 0;
    END_IF;
    paused := Hold OR holdLatch OR NOT Interlock OR tripHold OR NOT carrierOk;
    cap := LIMIT(0.0, Data.set.maxRate, 100.0);
    IF dm = UT_DOSE_FLOW THEN
      ratioUse := Data.set.ratio;
      IF Ratio > 0.0 AND Ratio <= 3.4E38 THEN
        ratioUse := Ratio;
      END_IF;
      IF carrierOk THEN
        reqRate := flowV * ratioUse;
      ELSE
        reqRate := 0.0;
      END_IF;
      IF Data.set.pumpCapacity > 0.0 THEN
        pct := reqRate / Data.set.pumpCapacity * 100.0;
      ELSE
        pct := 0.0;
      END_IF;
      Data.sts.required := reqRate;
      IF NOT paused AND reqRate > 0.0 THEN
        pumpGo := TRUE;
        IF Data.set.pumpCapacity > 0.0 THEN
          Rate := MIN(pct, cap);
        ELSE
          Rate := cap;
        END_IF;
        IF counting THEN
          IF Data.set.pumpCapacity > 0.0 THEN
            dosed := Rate / 100.0 * Data.set.pumpCapacity * dts / perSec;
          ELSE
            dosed := reqRate * dts / perSec;   (* a pulse pump *)
          END_IF;
        END_IF;
      END_IF;
    ELSE
      (* TIMED: on for onTime, off for offTime; a pause stops the clock *)
      IF NOT paused THEN
        cycAcc := cycAcc + LINT_TO_TIME(dMs);
        IF cycOn AND cycAcc >= Data.set.onTime AND Data.set.offTime > T#0s THEN
          cycOn := FALSE;
          cycAcc := T#0s;
        ELSIF NOT cycOn AND cycAcc >= Data.set.offTime THEN
          cycOn := TRUE;
          cycAcc := T#0s;
        END_IF;
      END_IF;
      IF cycOn AND NOT paused AND Data.set.onTime > T#0s THEN
        pumpGo := TRUE;
        Rate := cap;
        IF counting THEN
          dosed := Data.set.pumpCapacity * cap / 100.0 * dts / perSec;
        END_IF;
      END_IF;
    END_IF;
    (* stroke pulses: one every pulseVolume dosed *)
    IF Data.set.pulseVolume > 0.0 AND dm = UT_DOSE_FLOW AND dosed > 0.0 THEN
      pulseAcc := pulseAcc + dosed / REAL_TO_LREAL(Data.set.pulseVolume);
      IF pulseAcc >= 1.0 THEN
        IF pulseAcc > 1.0E6 THEN pulseAcc := 1.0E6; END_IF;
        w := LREAL_TO_LINT(pulseAcc);
        IF LINT_TO_LREAL(w) > pulseAcc THEN w := w - 1; END_IF;
        pulseAcc := pulseAcc - LINT_TO_LREAL(w);
        owed := MIN(owed + LINT_TO_DINT(w), 1000000);
      END_IF;
    END_IF;
    dlv := dlv + dosed;
  ELSE
    IF busyNow THEN
      Data.sts.lastDelivered := dlv;
      IF sMax.trip THEN endCode := UT_STOP_MAX_RUN;
      ELSIF qtyHit THEN endCode := UT_STOP_QUANTITY;
      ELSIF Abort THEN endCode := UT_STOP_ABORTED;
      ELSIF stopReq THEN endCode := UT_STOP_ABORT_CMD;
      ELSE endCode := UT_STOP_DEMAND_ENDED;
      END_IF;
    END_IF;
    busyNow := FALSE;
    paused := FALSE;
    owed := 0;
  END_IF;
  stage := 0;
END_IF;
IF isHand AND handRun THEN
  dlv := dlv + dosed;
END_IF;
runPrev := Run;

(* caps: maxQuantity (every mode); maxTime below *)
IF busyNow AND Data.set.maxQuantity > 0.0 AND dlv >= Data.set.maxQuantity THEN
  qtyHit := TRUE;
  quantityEnd := TRUE;           (* the run input gets a stop next scan *)
  handRun := FALSE;
END_IF;
IF busyNow AND NOT busyPrev THEN
  doseStart := tCur;
END_IF;
IF busyNow OR busyPrev THEN
  Data.det.doseTime := tCur - doseStart;
END_IF;

(* stroke pulse output *)
IF pulseOn THEN
  IF tCur - pulseT >= Data.set.pulseWidth THEN
    pulseOn := FALSE;
    pulseT := tCur;
  END_IF;
ELSIF owed > 0 AND tCur - pulseT >= Data.set.pulseWidth THEN
  pulseOn := TRUE;
  pulseT := tCur;
  owed := owed - 1;
  Data.det.pulses := Data.det.pulses + 1;
END_IF;
PulseOut := pulseOn;

(* protections *)
x := UT_PROT_RUN(TNow := tCur, Cause := dm = UT_DOSE_BATCH AND isAuto AND busyNow AND feeding AND NOT rose,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.noFlow,
                 Sts := Data.sts.noFlow, St := sNoFlow);
x := UT_PROT_RUN(TNow := tCur, Cause := busyNow, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.maxTime, Sts := Data.sts.maxTime, St := sMax);
x := UT_PROT_RUN(TNow := tCur, Cause := dm = UT_DOSE_FLOW AND busyNow AND Data.set.pumpCapacity > 0.0
                                        AND Data.sts.required > Data.set.pumpCapacity * LIMIT(0.0, Data.set.maxRate, 100.0) / 100.0,
                 ResetReq := resetReq, RetryWindow := Data.set.retryWindow, Prot := Data.set.overCapacity,
                 Sts := Data.sts.overCapacity, St := sCap);
x := UT_PROT_RUN(TNow := tCur, Cause := tolCause, ResetReq := resetReq, RetryWindow := Data.set.retryWindow,
                 Prot := Data.set.outOfTolerance, Sts := Data.sts.outOfTolerance, St := sTol);
IF busyNow AND sMax.trip AND dm = UT_DOSE_BATCH AND isAuto THEN
  busyNow := FALSE;              (* the whole dose took too long *)
  endCode := UT_STOP_MAX_RUN;
  Fast := FALSE;
  Slow := FALSE;
END_IF;
IF busyNow AND isAuto AND dm = UT_DOSE_BATCH AND qtyHit THEN
  busyNow := FALSE;
  endCode := UT_STOP_QUANTITY;
  Fast := FALSE;
  Slow := FALSE;
END_IF;
IF (NOT busyNow AND busyPrev) OR doneNow THEN
  Data.sts.stopReason := endCode;
END_IF;
IF NOT busyNow THEN
  pumpGo := FALSE;
  Rate := 0.0;
END_IF;
busyPrev := busyNow;

(* the pump link *)
PumpRun := pumpGo AND Interlock;
IF Pump <> NULL THEN
  x := Pump.Request(ReqRun := PumpRun, Hold := NOT Interlock, ReqSpeed := Rate, Owner := Data.set.tag);
END_IF;
IF Rate > 0.0 THEN
  RateRaw := REAL_TO_UINT(LIMIT(0.0, Rate, 100.0) * 655.35);
ELSE
  RateRaw := 0;
END_IF;

(* totals: millionths in a LINT *)
IF dosed > 0.0 AND dosed <= 1.0E15 THEN
  totFrac := totFrac + dosed * 1000000.0;
  w := LREAL_TO_LINT(totFrac);
  IF LINT_TO_LREAL(w) > totFrac THEN w := w - 1; END_IF;
  Data.tot.dosed := Data.tot.dosed + w;
  totFrac := totFrac - LINT_TO_LREAL(w);
END_IF;
IF keep.SaveTot THEN
  keptTot := Data.tot;
END_IF;

(* outputs, fault code *)
Done := doneNow;
Busy := busyNow;
Fault := sNoFlow.trip OR sMax.trip OR sCap.trip OR sTol.trip OR sStock.trip OR cfgF <> UT_F_NONE;
Warning := sNoFlow.warn OR sMax.warn OR sCap.warn OR sTol.warn OR sStock.warn OR cfgW <> UT_F_NONE OR qtyHit;
Data.sts.faultCode := 0;
IF cfgF <> UT_F_NONE OR cfgW <> UT_F_NONE THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1; END_IF;
IF Data.sts.noFlow.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2; END_IF;
IF Data.sts.maxTime.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#4; END_IF;
IF Data.sts.overCapacity.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#8; END_IF;
IF Data.sts.outOfTolerance.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#10; END_IF;
IF Data.sts.stockLow.tripped THEN Data.sts.faultCode := Data.sts.faultCode OR 16#20; END_IF;
IF qtyHit THEN Data.sts.faultCode := Data.sts.faultCode OR 16#40; END_IF;
tripCode := 0;
IF sNoFlow.trip THEN tripCode := tripCode OR 16#2; END_IF;
IF sMax.trip THEN tripCode := tripCode OR 16#4; END_IF;
IF sCap.trip THEN tripCode := tripCode OR 16#8; END_IF;
IF sTol.trip THEN tripCode := tripCode OR 16#10; END_IF;
IF sStock.trip THEN tripCode := tripCode OR 16#20; END_IF;
newBits := tripCode AND NOT tripPrev;
tripPrev := tripCode;
IF newBits <> 0 THEN
  Data.sts.trips := Data.sts.trips + 1;
  Data.sts.lastFaultCode := tripCode;
  IF (newBits AND 16#2) <> 0 THEN Data.sts.lastFault := UT_F_DOSE_NO_FLOW;
  ELSIF (newBits AND 16#4) <> 0 THEN Data.sts.lastFault := UT_F_DOSE_TOO_LONG;
  ELSIF (newBits AND 16#8) <> 0 THEN Data.sts.lastFault := UT_F_PUMP_TOO_SMALL;
  ELSIF (newBits AND 16#10) <> 0 THEN Data.sts.lastFault := UT_F_TOLERANCE;
  ELSE Data.sts.lastFault := UT_F_STOCK_LOW;
  END_IF;
END_IF;

(* status *)
stF := UT_F_NONE;
tLeft := T#0s;
IF cfgF <> UT_F_NONE THEN
  stCode := UT_ST_CONFIG;
  stF := cfgF;
ELSIF sStock.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.stockLow.reset, Sts := Data.sts.stockLow);
  stF := UT_F_STOCK_LOW;
  tLeft := Data.sts.stockLow.timeLeft;
ELSIF sNoFlow.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.noFlow.reset, Sts := Data.sts.noFlow);
  stF := UT_F_DOSE_NO_FLOW;
  tLeft := Data.sts.noFlow.timeLeft;
ELSIF sMax.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.maxTime.reset, Sts := Data.sts.maxTime);
  stF := UT_F_DOSE_TOO_LONG;
ELSIF sCap.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.overCapacity.reset, Sts := Data.sts.overCapacity);
  stF := UT_F_PUMP_TOO_SMALL;
ELSIF sTol.trip THEN
  stCode := UT_PROT_STATUS(Reset := Data.set.outOfTolerance.reset, Sts := Data.sts.outOfTolerance);
  stF := UT_F_TOLERANCE;
ELSIF busyNow AND NOT Interlock THEN
  stCode := UT_ST_INTERLOCK;
ELSIF busyNow AND paused AND (Hold OR holdLatch) THEN
  stCode := UT_ST_PAUSED_HOLD;
ELSIF busyNow AND paused AND (dm <> UT_DOSE_BATCH OR isHand) AND NOT carrierOk THEN
  stCode := UT_ST_LOW_CARRIER;
ELSIF Warning THEN
  stCode := UT_ST_WARNING;
  IF qtyHit THEN stF := UT_F_DOSE_QUANTITY;
  ELSIF sNoFlow.warn THEN stF := UT_F_DOSE_NO_FLOW;
  ELSIF sMax.warn THEN stF := UT_F_DOSE_TOO_LONG;
  ELSIF sCap.warn THEN stF := UT_F_PUMP_TOO_SMALL;
  ELSIF sTol.warn THEN stF := UT_F_TOLERANCE;
  ELSIF sStock.warn THEN stF := UT_F_STOCK_LOW;
  ELSE stF := cfgW;
  END_IF;
ELSIF isHand AND handRun THEN
  stCode := UT_ST_RUN_HAND;
  tLeft := modeSel.HandLeft;
ELSIF busyNow AND dm = UT_DOSE_BATCH THEN
  IF stage = 1 THEN stCode := UT_ST_DOSE_FAST;
  ELSIF stage = 2 THEN stCode := UT_ST_DOSE_SLOW;
  ELSE stCode := UT_ST_SETTLING;
  END_IF;
  IF stage = 3 THEN tLeft := Data.set.settleTime - (tCur - settleStart); END_IF;
ELSIF busyNow AND dm = UT_DOSE_FLOW THEN
  stCode := UT_ST_DOSE_FLOW;
ELSIF busyNow AND dm = UT_DOSE_TIMED THEN
  IF pumpGo THEN
    stCode := UT_ST_DOSE_TIMED;
    tLeft := Data.set.onTime - cycAcc;
  ELSE
    stCode := UT_ST_DOSE_NEXT;
    tLeft := Data.set.offTime - cycAcc;
  END_IF;
ELSIF modeSel.Mode = UT_MODE_OFF THEN
  stCode := UT_ST_OFF;
ELSIF Data.sts.stopReason = UT_STOP_DONE THEN
  stCode := UT_ST_DONE;
ELSIF Data.sts.stopReason <> UT_STOP_NONE AND Data.sts.stopReason <> UT_STOP_DEMAND_ENDED THEN
  stCode := UT_ST_ABORTED;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := NOT isAuto, OutOfSpec := Warning, Maint := FALSE);
Data.det.timeLeft := tLeft;
Data.sts.mode := modeSel.Mode;
IF NOT busyNow THEN
  IF Data.sts.stopReason = UT_STOP_DONE THEN Data.sts.phase := UT_DP_DONE;
  ELSIF Data.sts.stopReason <> UT_STOP_NONE AND Data.sts.stopReason <> UT_STOP_DEMAND_ENDED THEN Data.sts.phase := UT_DP_ABORTED;
  ELSE Data.sts.phase := UT_DP_IDLE;
  END_IF;
ELSIF paused THEN
  Data.sts.phase := UT_DP_HELD;
ELSIF dm = UT_DOSE_BATCH AND NOT isHand THEN
  IF stage = 1 THEN Data.sts.phase := UT_DP_FAST; ELSIF stage = 2 THEN Data.sts.phase := UT_DP_SLOW; ELSE Data.sts.phase := UT_DP_SETTLE; END_IF;
ELSIF pumpGo THEN
  Data.sts.phase := UT_DP_DOSING;
ELSE
  Data.sts.phase := UT_DP_WAITING;
END_IF;
Data.sts.modeActive := dm;
Data.sts.held := busyNow AND paused;
Data.sts.configBad := cfgF <> UT_F_NONE OR cfgW <> UT_F_NONE;
Data.sts.fault := Fault;
Data.sts.warning := Warning;
Data.sts.carrierOk := carrierOk;
Data.sts.targetActive := tgt;
Data.sts.preactActive := pUse;
Data.sts.rate := Rate;
Data.sts.ratioActive := ratioUse;
Data.sts.delivered := dlv;
Data.sts.dosedTotal := LINT_TO_LREAL(Data.tot.dosed) / 1000000.0;
Data.sts.doses := Data.tot.doses;

END_FUNCTION_BLOCK