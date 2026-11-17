(* FB_FlowTotal — totals from a flow rate, or from running time at a nominal rate. Offers I_Meter (the total, the
rate per hour; an I_Measurement too: its rate).
Pins: ipFlow (I_Measurement, the flow in its unit per set.eRateUnit), bActive (Runtime: counting while TRUE;
Rate / Sample: optional, counting only while TRUE when set.bOnlyActive), bResetBatch (rising edge: the batch to
0), refData -> bBatchDone.
set.eSource:
  Rate     integrates ipFlow; below set.fLowCutoff counts as 0; with set.bCountReverse a negative flow beyond the
           cut-off counts into tot.fTotalOut (reverse), not into tot.fTotal
  Runtime  adds set.fNominalRate while bActive (an estimate of what a pump moved; not a measured flow)
  Sample   every set.tSampleTime reads ipFlow once and adds it x tSampleTime (a rate, set.eRateUnit) or, with
           set.bSampleAsQuantity, the value itself (a quantity per sample); the same cut-off, reverse and bad
           meter rules as Rate. A slow reading, a meter that only updates now and then.
Units: set.eInUnit and set.eOutUnit (E_Unit, volume units: litre, m3, megalitre, gallon) both set convert every
addition from the flow's volume unit to the total's (and so the rate); both None = no conversion. One set, or a
unit that is not a volume, is a bad setting (put back).
Batch: tot.fBatch counts like tot.fTotal (forward flow, estimates included) until bResetBatch / bCmdResetBatch;
bBatchDone is TRUE once it has reached set.fBatchTarget (0 = off), until the batch is reset.
A failed meter (ipFlow not good or not wired) does not count; with set.bBadEstimate the nominal rate is counted
instead while bActive, into tot.fEstimated too (a warning). Bad past set.stInputBad's delay: bIsGood FALSE and
a warning (SensorBad). Totals and batch are LREAL, kept hourly, when bActive falls (the pump stops) and on a
reset (bCmdResetTotal, bCmdResetBatch). *)

FUNCTION_BLOCK FB_FlowTotal EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    ipFlow : I_Measurement;
    bActive : BOOL;
    bResetBatch : BOOL R_EDGE; (* the batch back to 0 *)
    refData : REFERENCE TO ST_FlowTotalData;
  END_VAR
  VAR_OUTPUT
    bBatchDone : BOOL; (* the batch has reached set.fBatchTarget *)
  END_VAR
  VAR RETAIN
    stKept : ST_FlowTotalSet;
    nKeptLayout : UINT;
    stKeptTot : ST_FlowTotalTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWInputBad : ST_ProtectionWork;
    tPrev : TIME;
    tKeptAt : TIME;
    bActiveWas : BOOL; (* bActive last scan (its fall keeps the totals) *)
    tWindowAt : TIME;
    fWindowTotal : LREAL;
    tSampleAcc : TIME; (* Sample: time since the last sample *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bMeterOk : BOOL;
    fFlow : REAL;
    fPerMs : LREAL; (* the rate unit in ms *)
    fDt : LREAL;
    fAdd : LREAL;
    tWin : TIME;
    nMs : LINT;
    fMult : LREAL; (* input unit to output unit *)
    bUnitOk : BOOL;
    nSamples : LINT;
    fFwd : LREAL; (* what was added to fTotal this scan *)
  END_VAR


PROPERTY PUBLIC fActTotal : LREAL
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActRate : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActRate := refData.sts.fRate; ELSE fActRate := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eOutUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fRate; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eOutUnit); END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_FlowTotalSet;
  END_VAR
  VAR
    bU : BOOL;
    fU : LREAL;
  END_VAR
  fU := F_UnitFactor(eFromUnit := stS.eInUnit, eToUnit := stS.eOutUnit, bOk => bU);
  SetOk := (stS.eSource = E_FlowSource.Rate OR stS.eSource = E_FlowSource.Runtime OR stS.eSource = E_FlowSource.Sample)
           AND bU AND stS.tSampleTime > T#0s AND stS.fBatchTarget >= 0.0 AND stS.fBatchTarget <= 1.0E15
           AND (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
                OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay)
           AND stS.fLowCutoff >= 0.0 AND stS.fLowCutoff <= REAL#3.4E38
           AND stS.fNominalRate >= 0.0 AND stS.fNominalRate <= REAL#3.4E38 AND stS.tRateWindow > T#0s
           AND stS.stInputBad.tDelay >= T#0s AND stS.stInputBad.tRecover >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tPrev := tNow;
  tKeptAt := tNow;
  tWindowAt := tNow;
  fWindowTotal := refData.tot.fTotal;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;

(* the time this scan stands for, in whole ms (the rest carries on) *)
nMs := TIME_TO_LINT(tNow - tPrev);
IF nMs < 0 THEN nMs := 0; tPrev := tNow; END_IF;
tPrev := tPrev + LINT_TO_TIME(nMs);
fDt := LINT_TO_LREAL(nMs);
CASE refData.set.eRateUnit OF
  E_RateUnit.PerSec:  fPerMs := 1000.0;
  E_RateUnit.PerMin:  fPerMs := 60000.0;
  E_RateUnit.PerDay:  fPerMs := 86400000.0;
ELSE
  fPerMs := 3600000.0;
END_CASE;

fMult := F_UnitFactor(eFromUnit := refData.set.eInUnit, eToUnit := refData.set.eOutUnit, bOk => bUnitOk);
fFwd := 0.0;

(* the meter *)
bMeterOk := FALSE;
fFlow := 0.0;
IF ipFlow <> NULL THEN
  IF ipFlow.bIsFitted THEN
    fFlow := ipFlow.fActValue;
    bMeterOk := ipFlow.bIsGood AND ABS(fFlow) <= REAL#3.4E38;
  END_IF;
END_IF;
refData.sts.bEstimating := FALSE;
IF refData.set.eSource = E_FlowSource.Runtime THEN
  bMeterOk := TRUE;               (* nothing to fail *)
  IF bActive THEN
    fFwd := REAL_TO_LREAL(refData.set.fNominalRate) * fDt / fPerMs * fMult;
    refData.tot.fTotal := refData.tot.fTotal + fFwd;
  END_IF;
ELSIF bMeterOk THEN
  IF NOT refData.set.bOnlyActive OR bActive THEN
    IF ABS(fFlow) < refData.set.fLowCutoff THEN
      fFlow := 0.0;
    END_IF;
    IF refData.set.eSource = E_FlowSource.Sample THEN
      (* every tSampleTime the value is read: a rate for that time, or a quantity *)
      tSampleAcc := tSampleAcc + LINT_TO_TIME(nMs);
      nSamples := 0;
      IF tSampleAcc >= refData.set.tSampleTime THEN
        nSamples := TIME_TO_LINT(tSampleAcc) / TIME_TO_LINT(refData.set.tSampleTime);
        tSampleAcc := LINT_TO_TIME(TIME_TO_LINT(tSampleAcc) - nSamples * TIME_TO_LINT(refData.set.tSampleTime));
      END_IF;
      IF refData.set.bSampleAsQuantity THEN
        fAdd := REAL_TO_LREAL(fFlow) * LINT_TO_LREAL(nSamples) * fMult;
      ELSE
        fAdd := REAL_TO_LREAL(fFlow) * LINT_TO_LREAL(nSamples) * TIME_TO_LREAL(refData.set.tSampleTime) / fPerMs * fMult;
      END_IF;
    ELSE
      fAdd := REAL_TO_LREAL(fFlow) * fDt / fPerMs * fMult;
    END_IF;
    IF fAdd >= 0.0 THEN
      refData.tot.fTotal := refData.tot.fTotal + fAdd;
      fFwd := fAdd;
    ELSIF refData.set.bCountReverse THEN
      refData.tot.fTotalOut := refData.tot.fTotalOut - fAdd;
    END_IF;
  ELSE
    tSampleAcc := T#0s;
  END_IF;
ELSIF refData.set.bBadEstimate AND bActive THEN
  fAdd := REAL_TO_LREAL(refData.set.fNominalRate) * fDt / fPerMs * fMult;
  refData.tot.fTotal := refData.tot.fTotal + fAdd;
  refData.tot.fEstimated := refData.tot.fEstimated + fAdd;
  refData.sts.bEstimating := TRUE;
  fFwd := fAdd;
END_IF;
refData.tot.fBatch := refData.tot.fBatch + fFwd;

(* the meter bad *)
F_Protect(tNow := tNow, bCause := NOT bMeterOk, bResetReq := SystemReset(), tRetryWindow := T#1h,
          stSet := refData.set.stInputBad, stSts := refData.sts.stInputBad, stWork := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window, per hour *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fRate := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotal THEN
  refData.bCmdResetTotal := FALSE;
  refData.tot.fTotal := 0.0;
  refData.tot.fTotalOut := 0.0;
  refData.tot.fEstimated := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
IF bResetBatch OR refData.bCmdResetBatch THEN
  refData.bCmdResetBatch := FALSE;
  refData.tot.fBatch := 0.0;
  stKeptTot := refData.tot;
END_IF;
bBatchDone := refData.set.fBatchTarget > 0.0 AND refData.tot.fBatch >= refData.set.fBatchTarget;
IF (bActiveWas AND NOT bActive) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bActiveWas := bActive;

bError := NOT bOk OR stWInputBad.bTrip;
bWarning := NOT bError AND (stWInputBad.bWarn OR refData.sts.bEstimating OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF stWInputBad.bTrip OR stWInputBad.bWarn OR refData.sts.bEstimating THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT refData.sts.bGood THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK