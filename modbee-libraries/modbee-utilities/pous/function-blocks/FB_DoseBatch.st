(* FB_DoseBatch EXTENDS FB_Dose — batching a quantity.
A rising bRun, bStart or bCmdStart delivers the target (fQuantitySetpoint pin, 0 = set.fQuantitySetpoint): bFastFeed until set.fSlowFeedLast is
left, then bSlowFeed, stopping early by the in-flight quantity (set.fStopEarlyBy), then set.tSettleTime and the result.
set.bLearnStopEarly corrects the preact by half of each dose's error (doses more than 25 % off are not learned from),
between 0 and half the target; the learned preact is written to set.fStopEarlyBy at a dose's end. Delivered =
ipDelivered's value (a scale), or the rise of ipProductMeter's total (set.bDeliveredFromMeterTotal). A feed that does not raise the
delivered quantity: set.stNoFlowFault; a result off by more than set.fToleranceQuantity: set.stOutOfToleranceFault. A pause (bPause,
bCmdPause, bInterlock FALSE, a trip) holds the feeds; bStart resumes after bCmdPause.
Pins: FB_Dose's, ipDelivered, ipProductMeter, fQuantitySetpoint, refData -> FB_Dose's outputs, bFastFeed, bSlowFeed, fQuantityLeft. *)

FUNCTION_BLOCK FB_DoseBatch EXTENDS FB_Dose
  VAR_INPUT
    ipDelivered : I_Measurement; (* delivered so far (a scale) *)
    ipProductMeter : I_Meter; (* set.bDeliveredFromMeterTotal: the product meter *)
    fQuantitySetpoint : REAL; (* 0 = set.fQuantitySetpoint *)
    refData : REFERENCE TO ST_DoseBatchData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bFastFeed : BOOL; (* the fast feed *)
    bSlowFeed : BOOL; (* the slow feed *)
    fQuantityLeft : REAL; (* quantity still to go *)
  END_VAR
  VAR RETAIN
    stKept : ST_DoseBatchSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    nStage : INT; (* 1 fast, 2 slow, 3 settle *)
    tSettleAt : TIME;
    fTgt : REAL;
    fStartRef : LREAL;
    fRiseRef : LREAL;
    fPAct : REAL;
    bTolCause : BOOL;
    stWNoFlow : ST_ProtectionWork;
    stWTol : ST_ProtectionWork;
    bNoFlowTrip : BOOL;
    bTolTrip : BOOL;
  END_VAR
  VAR_TEMP
    bResetNow : BOOL;
    bOk : BOOL;
    bStartNow : BOOL;
    fActV : REAL;
    bActGood : BOOL;
    fPUse : REAL;
    fErr : REAL;
    bRose : BOOL;
    bFeeding : BOOL;
    ePh : E_DosePhase;
    tLeft : TIME;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_DoseBatchSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF BaseSetWhy(refSet := stS) <> E_UtError.None THEN
    SetWhy := BaseSetWhy(refSet := stS);
  ELSIF NOT (stS.fQuantitySetpoint >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fQuantitySetpoint <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fSlowFeedLast >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fSlowFeedLast <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fStopEarlyBy >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fStopEarlyBy <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fToleranceQuantity >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fToleranceQuantity <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tSettleTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_DoseBatchSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bPumpRunCommand := FALSE;
  fPumpSpeedPct := 0.0;
  bBusy := FALSE;
  bFastFeed := FALSE;
  bSlowFeed := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  fPAct := refData.set.fStopEarlyBy;
END_IF;
bResetNow := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF bOk AND NOT bBusy THEN
  fPAct := refData.set.fStopEarlyBy;   (* a write while idle is taken *)
END_IF;

(* the delivered quantity *)
bActGood := FALSE;
fActV := 0.0;
IF refData.set.bDeliveredFromMeterTotal THEN
  IF ipProductMeter <> NULL THEN
    fActV := LREAL_TO_REAL(ipProductMeter.fActTotal);
    bActGood := ipProductMeter.bIsGood AND ABS(fActV) <= REAL#3.4E38;
  END_IF;
ELSIF ipDelivered <> NULL THEN
  fActV := ipDelivered.fActValue;
  bActGood := ipDelivered.bIsGood AND ABS(fActV) <= REAL#3.4E38;
END_IF;
bTripHold := bTripHold OR bNoFlowTrip OR bTolTrip;

bStartNow := bStartReq OR bRunEdge;
IF bBusy AND bActGood THEN
  IF refData.set.bDeliveredFromMeterTotal THEN
    fDlv := REAL_TO_LREAL(fActV) - fStartRef;
  ELSE
    fDlv := REAL_TO_LREAL(fActV);
  END_IF;
END_IF;
IF bStartNow OR bResetNow THEN
  bTolCause := FALSE;             (* the last result is acknowledged *)
END_IF;
IF NOT (fPAct >= 0.0) THEN
  fPAct := 0.0;
END_IF;
fPUse := fPAct;
IF fTgt > 0.0 AND fPUse > 0.5 * fTgt THEN
  fPUse := 0.5 * fTgt;
END_IF;
IF NOT bBusy THEN
  IF bOk AND bStartNow AND NOT bEndReq AND bPermissive AND NOT bTripHold THEN
    IF fQuantitySetpoint > 0.0 THEN
      fTgt := fQuantitySetpoint;
    ELSE
      fTgt := refData.set.fQuantitySetpoint;
    END_IF;
    IF fTgt > 0.0 AND fTgt <= REAL#3.4E38 THEN
      bBusy := TRUE;
      bHoldLatch := FALSE;
      IF refData.set.bDeliveredFromMeterTotal AND bActGood THEN
        fStartRef := REAL_TO_LREAL(fActV);
        fDlv := 0.0;
      ELSIF bActGood THEN
        fDlv := REAL_TO_LREAL(fActV);
      ELSE
        fDlv := 0.0;
      END_IF;
      fRiseRef := fDlv;
      IF refData.set.fSlowFeedLast >= fTgt THEN
        nStage := 2;
      ELSE
        nStage := 1;
      END_IF;
    END_IF;
  END_IF;
ELSIF bEndReq OR NOT bOk THEN
  bBusy := FALSE;
  refData.sts.fDeliveredLastDose := fDlv;
  refData.sts.fLastDoseError := LREAL_TO_REAL(fDlv) - fTgt;
  eEnd := EndWhy(refSet := refData.set);
ELSE
  IF nStage < 3 AND fDlv >= REAL_TO_LREAL(fTgt - fPUse) THEN
    nStage := 3;
    tSettleAt := tNow;
  ELSIF nStage = 1 AND refData.set.fSlowFeedLast > 0.0 AND fDlv >= REAL_TO_LREAL(fTgt - refData.set.fSlowFeedLast) THEN
    nStage := 2;
  END_IF;
  IF nStage = 3 AND tNow - tSettleAt >= refData.set.tSettleTime THEN
    bBusy := FALSE;               (* complete *)
    bDoneNow := TRUE;
    eEnd := E_StopReason.Done;
    fErr := LREAL_TO_REAL(fDlv) - fTgt;
    refData.sts.fDeliveredLastDose := fDlv;
    refData.sts.fLastDoseError := fErr;
    IF refData.set.bLearnStopEarly AND ABS(fErr) <= 0.25 * fTgt THEN
      fPAct := LIMIT(0.0, fPAct + 0.5 * fErr, 0.5 * fTgt);
      refData.set.fStopEarlyBy := fPAct;   (* written at a dose's end only *)
      stKept.fStopEarlyBy := fPAct;
    END_IF;
    bTolCause := refData.set.fToleranceQuantity > 0.0 AND ABS(fErr) > refData.set.fToleranceQuantity;
  END_IF;
END_IF;
bFastFeed := FALSE;
bSlowFeed := FALSE;
tLeft := T#0s;
IF bBusy THEN
  bPaused := bPause OR bHoldLatch OR NOT bInterlock OR bTripHold;
  bFastFeed := nStage = 1 AND NOT bPaused;
  bSlowFeed := nStage = 2 AND NOT bPaused;
  fQuantityLeft := MAX(0.0, fTgt - LREAL_TO_REAL(fDlv));
  IF nStage = 3 THEN
    tLeft := refData.set.tSettleTime - (tNow - tSettleAt);
  END_IF;
ELSE
  bPaused := FALSE;
  fQuantityLeft := 0.0;
END_IF;
bRose := fDlv > fRiseRef;
IF bRose THEN
  fDosed := fDlv - fRiseRef;
  fRiseRef := fDlv;
END_IF;
bFeeding := bFastFeed OR bSlowFeed;

bNoFlowTrip := F_Protect(tNow := tNow, bConditionPresent := bBusy AND bFeeding AND NOT bRose, bResetRequest := bResetNow,
                         tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stNoFlowFault,
                         stStatus := refData.sts.stNoFlowFault, stWorking := stWNoFlow);
bTolTrip := F_Protect(tNow := tNow, bConditionPresent := bTolCause, bResetRequest := bResetNow,
                      tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stOutOfToleranceFault,
                      stStatus := refData.sts.stOutOfToleranceFault, stWorking := stWTol);
IF bBusy AND (bMaxTrip OR bQtyEnd) THEN
  bBusy := FALSE;                 (* the whole dose took too long, or reached fMaxQuantityPerDose *)
  refData.sts.fDeliveredLastDose := fDlv;
  refData.sts.fLastDoseError := LREAL_TO_REAL(fDlv) - fTgt;
  eEnd := EndWhy(refSet := refData.set);
  bFastFeed := FALSE;
  bSlowFeed := FALSE;
END_IF;
refData.sts.fQuantitySetpointInUse := fTgt;
refData.sts.fStopEarlyInUse := fPUse;
IF nStage = 1 THEN
  ePh := E_DosePhase.Fast;
ELSIF nStage = 2 THEN
  ePh := E_DosePhase.Slow;
ELSE
  ePh := E_DosePhase.Settle;
END_IF;
IF bNoFlowTrip THEN
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk, bVTrip := TRUE,
         eVTrip := E_UtError.NoFlow, bVWarn := FALSE, eVWarn := E_UtError.None, eVPhase := ePh, tVLeft := tLeft);
ELSE
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk, bVTrip := bTolTrip,
         eVTrip := E_UtError.OutOfTolerance, bVWarn := stWNoFlow.bWarning OR stWTol.bWarning
                                                       OR stWNoFlow.bSettingBad OR stWTol.bSettingBad,
         eVWarn := SEL(stWNoFlow.bWarning, E_UtError.OutOfTolerance, E_UtError.NoFlow), eVPhase := ePh, tVLeft := tLeft);
END_IF;

END_FUNCTION_BLOCK