(* FB_DoseBatch EXTENDS FB_Dose — batching a quantity.
A rising bRun, bStart or bCmdStart delivers the target (fTarget pin, 0 = set.fTarget): bFast until set.fSlowAt is
left, then bSlow, stopping early by the in-flight quantity (set.fPreact), then set.tSettle and the result.
set.bLearnPreact corrects the preact by half of each dose's error (doses more than 25 % off are not learned from),
between 0 and half the target; the learned preact is written to set.fPreact at a dose's end. Delivered =
ipActual's value (a scale), or the rise of ipMeter's total (set.bActualIsTotal). A feed that does not raise the
delivered quantity: set.stNoFlow; a result off by more than set.fTolerance: set.stOutOfTolerance. A pause (bHold,
bCmdHold, bInterlock FALSE, a trip) holds the feeds; bStart resumes after bCmdHold.
Pins: FB_Dose's, ipActual, ipMeter, fTarget, refData -> FB_Dose's outputs, bFast, bSlow, fRemaining. *)

FUNCTION_BLOCK FB_DoseBatch EXTENDS FB_Dose
  VAR_INPUT
    ipActual : I_Measurement; (* delivered so far (a scale) *)
    ipMeter : I_Meter; (* set.bActualIsTotal: the product meter *)
    fTarget : REAL; (* 0 = set.fTarget *)
    refData : REFERENCE TO ST_DoseBatchData;
  END_VAR
  VAR_OUTPUT
    bFast : BOOL;
    bSlow : BOOL;
    fRemaining : REAL;
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
  ELSIF NOT (stS.fTarget >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fTarget <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fSlowAt >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fSlowAt <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fPreact >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fPreact <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fTolerance >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fTolerance <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tSettle >= T#0s) THEN
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
  bPumpRun := FALSE;
  fRate := 0.0;
  bBusy := FALSE;
  bFast := FALSE;
  bSlow := FALSE;
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
  fPAct := refData.set.fPreact;
END_IF;
bResetNow := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF bOk AND NOT bBusy THEN
  fPAct := refData.set.fPreact;   (* a write while idle is taken *)
END_IF;

(* the delivered quantity *)
bActGood := FALSE;
fActV := 0.0;
IF refData.set.bActualIsTotal THEN
  IF ipMeter <> NULL THEN
    fActV := LREAL_TO_REAL(ipMeter.fActTotal);
    bActGood := ipMeter.bIsGood AND ABS(fActV) <= REAL#3.4E38;
  END_IF;
ELSIF ipActual <> NULL THEN
  fActV := ipActual.fActValue;
  bActGood := ipActual.bIsGood AND ABS(fActV) <= REAL#3.4E38;
END_IF;
bTripHold := bTripHold OR bNoFlowTrip OR bTolTrip;

bStartNow := bStartReq OR bRunEdge;
IF bBusy AND bActGood THEN
  IF refData.set.bActualIsTotal THEN
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
    IF fTarget > 0.0 THEN
      fTgt := fTarget;
    ELSE
      fTgt := refData.set.fTarget;
    END_IF;
    IF fTgt > 0.0 AND fTgt <= REAL#3.4E38 THEN
      bBusy := TRUE;
      bHoldLatch := FALSE;
      IF refData.set.bActualIsTotal AND bActGood THEN
        fStartRef := REAL_TO_LREAL(fActV);
        fDlv := 0.0;
      ELSIF bActGood THEN
        fDlv := REAL_TO_LREAL(fActV);
      ELSE
        fDlv := 0.0;
      END_IF;
      fRiseRef := fDlv;
      IF refData.set.fSlowAt >= fTgt THEN
        nStage := 2;
      ELSE
        nStage := 1;
      END_IF;
    END_IF;
  END_IF;
ELSIF bEndReq OR NOT bOk THEN
  bBusy := FALSE;
  refData.sts.fLastDelivered := fDlv;
  refData.sts.fLastError := LREAL_TO_REAL(fDlv) - fTgt;
  eEnd := EndWhy(refSet := refData.set);
ELSE
  IF nStage < 3 AND fDlv >= REAL_TO_LREAL(fTgt - fPUse) THEN
    nStage := 3;
    tSettleAt := tNow;
  ELSIF nStage = 1 AND refData.set.fSlowAt > 0.0 AND fDlv >= REAL_TO_LREAL(fTgt - refData.set.fSlowAt) THEN
    nStage := 2;
  END_IF;
  IF nStage = 3 AND tNow - tSettleAt >= refData.set.tSettle THEN
    bBusy := FALSE;               (* complete *)
    bDoneNow := TRUE;
    eEnd := E_StopReason.Done;
    fErr := LREAL_TO_REAL(fDlv) - fTgt;
    refData.sts.fLastDelivered := fDlv;
    refData.sts.fLastError := fErr;
    IF refData.set.bLearnPreact AND ABS(fErr) <= 0.25 * fTgt THEN
      fPAct := LIMIT(0.0, fPAct + 0.5 * fErr, 0.5 * fTgt);
      refData.set.fPreact := fPAct;   (* written at a dose's end only *)
      stKept.fPreact := fPAct;
    END_IF;
    bTolCause := refData.set.fTolerance > 0.0 AND ABS(fErr) > refData.set.fTolerance;
  END_IF;
END_IF;
bFast := FALSE;
bSlow := FALSE;
tLeft := T#0s;
IF bBusy THEN
  bPaused := bHold OR bHoldLatch OR NOT bInterlock OR bTripHold;
  bFast := nStage = 1 AND NOT bPaused;
  bSlow := nStage = 2 AND NOT bPaused;
  fRemaining := MAX(0.0, fTgt - LREAL_TO_REAL(fDlv));
  IF nStage = 3 THEN
    tLeft := refData.set.tSettle - (tNow - tSettleAt);
  END_IF;
ELSE
  bPaused := FALSE;
  fRemaining := 0.0;
END_IF;
bRose := fDlv > fRiseRef;
IF bRose THEN
  fDosed := fDlv - fRiseRef;
  fRiseRef := fDlv;
END_IF;
bFeeding := bFast OR bSlow;

bNoFlowTrip := F_Protect(tNow := tNow, bCause := bBusy AND bFeeding AND NOT bRose, bResetReq := bResetNow,
                         tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stNoFlow,
                         stSts := refData.sts.stNoFlow, stWork := stWNoFlow);
bTolTrip := F_Protect(tNow := tNow, bCause := bTolCause, bResetReq := bResetNow,
                      tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stOutOfTolerance,
                      stSts := refData.sts.stOutOfTolerance, stWork := stWTol);
IF bBusy AND (bMaxTrip OR bQtyEnd) THEN
  bBusy := FALSE;                 (* the whole dose took too long, or reached fMaxQuantity *)
  refData.sts.fLastDelivered := fDlv;
  refData.sts.fLastError := LREAL_TO_REAL(fDlv) - fTgt;
  eEnd := EndWhy(refSet := refData.set);
  bFast := FALSE;
  bSlow := FALSE;
END_IF;
refData.sts.fTargetActive := fTgt;
refData.sts.fPreactActive := fPUse;
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
         eVTrip := E_UtError.OutOfTolerance, bVWarn := stWNoFlow.bWarn OR stWTol.bWarn
                                                       OR stWNoFlow.bBadSetting OR stWTol.bBadSetting,
         eVWarn := SEL(stWNoFlow.bWarn, E_UtError.OutOfTolerance, E_UtError.NoFlow), eVPhase := ePh, tVLeft := tLeft);
END_IF;

END_FUNCTION_BLOCK