(* FB_FlowTotal — totals from a flow rate, or from running time at a nominal rate. Offers I_Meter (the total, the
rate per hour; an I_Measurement too: its rate).
Pins: ipFlow (I_Measurement, the flow in its unit per set.eRateUnit), bPumpRunning (Runtime: counting while TRUE;
Rate / Sample: optional, counting only while TRUE when set.bCountOnlyWhilePumpRunning), bResetBatch (rising edge: the batch to
0), refData -> bBatchDone.
set.eCountFrom:
  Rate     integrates ipFlow; below set.fZeroBelow counts as 0; with set.bCountReverseFlow a negative flow beyond the
           cut-off counts into tot.fTotalReverse (reverse), not into tot.fTotal
  Runtime  adds set.fNominalRate while bPumpRunning (an estimate of what a pump moved; not a measured flow)
  Sample   every set.tSampleInterval reads ipFlow once and adds it x tSampleInterval (a rate, set.eRateUnit) or, with
           set.bSampleAsQuantity, the value itself (a quantity per sample); the same cut-off, reverse and bad
           meter rules as Rate. A slow reading, a meter that only updates now and then.
Units: set.eMeterUnit and set.eTotalUnit (E_Unit, volume units: litre, m3, megalitre, gallon) both set convert every
addition from the flow's volume unit to the total's (and so the rate); both None = no conversion. One set, or a
unit that is not a volume, is a bad setting (put back).
Batch: tot.fBatchTotal counts like tot.fTotal (forward flow, estimates included) until bResetBatch / bCmdResetBatch;
bBatchDone is TRUE once it has reached set.fBatchSetpoint (0 = off), until the batch is reset.
A failed meter (ipFlow not good or not wired) does not count; with set.bEstimateWhenBad the nominal rate is counted
instead while bPumpRunning, into tot.fTotalEstimated too (a warning). Bad past set.stMeterBadFault's delay: bIsGood FALSE and
a warning (SensorBad). Totals and batch are LREAL, kept hourly, when bPumpRunning falls (the pump stops) and on a
reset (bCmdResetTotals, bCmdResetBatch).
Total commands: bCmdResetTotals (with set.bResetNeedsConfirm, only together with bCmdConfirmReset in the same write) and
bCmdPresetTotal (the total to fPresetTotal, 0 .. 1E12). *)

FUNCTION_BLOCK FB_FlowTotal EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    ipFlow : I_Measurement; (* the flow measurement, in its unit per eRateUnit *)
    bPumpRunning : BOOL; (* Runtime: counting while TRUE; Rate / Sample: counting only while TRUE when bCountOnlyWhilePumpRunning *)
    bResetBatch : BOOL R_EDGE; (* the batch back to 0 *)
    refData : REFERENCE TO ST_FlowTotalData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bBatchDone : BOOL; (* the batch has reached set.fBatchSetpoint *)
  END_VAR
  VAR RETAIN
    stKept : ST_FlowTotalSet;
    nKeptLayout : UINT;
    stKeptTot : ST_FlowTotalTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 3;
  END_VAR
  VAR
    stWInputBad : ST_ProtectionWork;
    tPrev : TIME;
    tKeptAt : TIME;
    bActiveWas : BOOL; (* bPumpRunning last scan (its fall keeps the totals) *)
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


PROPERTY PUBLIC fActTotal : LREAL    // the lifetime total in its unit
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActFlowPerHour : REAL    // the rate, per hour
  GET
    IF __ISVALIDREF(refData) THEN fActFlowPerHour := refData.sts.fFlowPerHour; ELSE fActFlowPerHour := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eTotalUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL    // the value now (the total, in its unit)
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fFlowPerHour; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a value is available (fitted and read at least once)
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // fitted on this site
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eTotalUnit); END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_FlowTotalSet;
  END_VAR
  VAR
    bU : BOOL;
    fU : LREAL;
  END_VAR
  fU := F_UnitFactor(eFromUnit := stS.eMeterUnit, eToUnit := stS.eTotalUnit, bUnitsMatch => bU);
  SetWhy := E_UtError.None;
  IF NOT (stS.eCountFrom = E_FlowSource.Rate OR stS.eCountFrom = E_FlowSource.Runtime
          OR stS.eCountFrom = E_FlowSource.Sample) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (bU) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.tSampleInterval > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fBatchSetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fBatchSetpoint <= 1.0E15) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.eRateUnit = E_RateUnit.PerSec OR stS.eRateUnit = E_RateUnit.PerMin
             OR stS.eRateUnit = E_RateUnit.PerHour OR stS.eRateUnit = E_RateUnit.PerDay) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.fZeroBelow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fZeroBelow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fNominalRate >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fNominalRate <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tRateWindow > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stMeterBadFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stMeterBadFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_FlowTotalSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
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

fMult := F_UnitFactor(eFromUnit := refData.set.eMeterUnit, eToUnit := refData.set.eTotalUnit, bUnitsMatch => bUnitOk);
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
IF refData.set.eCountFrom = E_FlowSource.Runtime THEN
  bMeterOk := TRUE;               (* nothing to fail *)
  IF bPumpRunning THEN
    fFwd := REAL_TO_LREAL(refData.set.fNominalRate) * fDt / fPerMs * fMult;
    refData.tot.fTotal := refData.tot.fTotal + fFwd;
  END_IF;
ELSIF bMeterOk THEN
  IF NOT refData.set.bCountOnlyWhilePumpRunning OR bPumpRunning THEN
    IF ABS(fFlow) < refData.set.fZeroBelow THEN
      fFlow := 0.0;
    END_IF;
    IF refData.set.eCountFrom = E_FlowSource.Sample THEN
      (* every tSampleInterval the value is read: a rate for that time, or a quantity *)
      tSampleAcc := tSampleAcc + LINT_TO_TIME(nMs);
      nSamples := 0;
      IF tSampleAcc >= refData.set.tSampleInterval THEN
        nSamples := TIME_TO_LINT(tSampleAcc) / TIME_TO_LINT(refData.set.tSampleInterval);
        tSampleAcc := LINT_TO_TIME(TIME_TO_LINT(tSampleAcc) - nSamples * TIME_TO_LINT(refData.set.tSampleInterval));
      END_IF;
      IF refData.set.bSampleAsQuantity THEN
        fAdd := REAL_TO_LREAL(fFlow) * LINT_TO_LREAL(nSamples) * fMult;
      ELSE
        fAdd := REAL_TO_LREAL(fFlow) * LINT_TO_LREAL(nSamples) * TIME_TO_LREAL(refData.set.tSampleInterval) / fPerMs * fMult;
      END_IF;
    ELSE
      fAdd := REAL_TO_LREAL(fFlow) * fDt / fPerMs * fMult;
    END_IF;
    IF fAdd >= 0.0 THEN
      refData.tot.fTotal := refData.tot.fTotal + fAdd;
      fFwd := fAdd;
    ELSIF refData.set.bCountReverseFlow THEN
      refData.tot.fTotalReverse := refData.tot.fTotalReverse - fAdd;
    END_IF;
  ELSE
    tSampleAcc := T#0s;
  END_IF;
ELSIF refData.set.bEstimateWhenBad AND bPumpRunning THEN
  fAdd := REAL_TO_LREAL(refData.set.fNominalRate) * fDt / fPerMs * fMult;
  refData.tot.fTotal := refData.tot.fTotal + fAdd;
  refData.tot.fTotalEstimated := refData.tot.fTotalEstimated + fAdd;
  refData.sts.bEstimating := TRUE;
  fFwd := fAdd;
END_IF;
refData.tot.fBatchTotal := refData.tot.fBatchTotal + fFwd;

(* the meter bad *)
F_Protect(tNow := tNow, bConditionPresent := NOT bMeterOk, bResetRequest := SystemReset(), tRetryCountWindow := refData.set.tRetryCountWindow,
          stSettings := refData.set.stMeterBadFault, stStatus := refData.sts.stMeterBadFault, stWorking := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window, per hour *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fFlowPerHour := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotals AND (refData.bCmdConfirmReset OR NOT refData.set.bResetNeedsConfirm) THEN
  refData.bCmdResetTotals := FALSE;
  refData.tot.fTotal := 0.0;
  refData.tot.fTotalReverse := 0.0;
  refData.tot.fTotalEstimated := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
refData.bCmdResetTotals := FALSE;
refData.bCmdConfirmReset := FALSE;
IF refData.bCmdPresetTotal THEN
  IF refData.fPresetTotal >= 0.0 AND refData.fPresetTotal <= 1.0E12 THEN
    refData.tot.fTotal := refData.fPresetTotal;
    fWindowTotal := refData.fPresetTotal;
    stKeptTot := refData.tot;
  END_IF;
  refData.bCmdPresetTotal := FALSE;
END_IF;
IF bResetBatch OR refData.bCmdResetBatch THEN
  refData.bCmdResetBatch := FALSE;
  refData.tot.fBatchTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
bBatchDone := refData.set.fBatchSetpoint > 0.0 AND refData.tot.fBatchTotal >= refData.set.fBatchSetpoint;
IF (bActiveWas AND NOT bPumpRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bActiveWas := bPumpRunning;

bError := NOT bOk OR stWInputBad.bTripping;
bWarning := NOT bError AND (stWInputBad.bWarning OR refData.sts.bEstimating OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF stWInputBad.bTripping OR stWInputBad.bWarning OR refData.sts.bEstimating THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bSettingRefused THEN
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