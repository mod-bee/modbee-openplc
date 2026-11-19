(* FB_DoseFlow EXTENDS FB_Dose — flow-paced dosing (fertigation).
While bRun (or a bStart latch) the dosing pump runs in proportion to the carrier: the meter's rate (per hour) x
the ratio (fDosePerCarrierUnit pin for this run, <= 0 = set.fDosePerCarrierUnit); fPumpSpeedPct = required / set.fFlowAtFullSpeed %, capped at
set.fMaxPumpSpeedPct (no capacity: fMaxPumpSpeedPct, a pulse pump). It injects only while bCarrierRunning and the carrier flow has
been at / above set.fMinCarrierFlow for set.tCarrierProveDelay (Waiting, not a fault). bStrokePulse: one stroke every
set.fDosePerStroke dosed (0 = none), set.tStrokePulseWidth on and off. Asked for more than the pump can give:
set.stOverCapacityFault (a trip holds the dose).
Pins: FB_Dose's, bCarrierRunning, ipCarrierMeter (I_Meter: the carrier), fDosePerCarrierUnit, refData -> FB_Dose's outputs, bStrokePulse. *)

FUNCTION_BLOCK FB_DoseFlow EXTENDS FB_Dose
  VAR_INPUT
    bCarrierRunning : BOOL := TRUE; (* the carrier (irrigation) pump runs *)
    ipCarrierMeter : I_Meter; (* the carrier meter *)
    fDosePerCarrierUnit : REAL; (* this run's ratio (<= 0 = set.fDosePerCarrierUnit) *)
    refData : REFERENCE TO ST_DoseFlowData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bStrokePulse : BOOL; (* stroke pulses *)
  END_VAR
  VAR RETAIN
    stKept : ST_DoseFlowSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    tCarrierSince : TIME;
    fPulseAcc : LREAL;
    nOwed : DINT;
    bPulseOn : BOOL;
    tPulseAt : TIME;
    stWCap : ST_ProtectionWork;
    bCapTrip : BOOL;
  END_VAR
  VAR_TEMP
    bResetNow : BOOL;
    bOk : BOOL;
    fFlow : REAL;
    bFlowGood : BOOL;
    bCarrier : BOOL;
    bCarrierOk : BOOL;
    fRatioUse : REAL;
    fReq : REAL;
    fPct : REAL;
    fCap : REAL;
    nW : LINT;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_DoseFlowSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF BaseSetWhy(refSet := stS) <> E_UtError.None THEN
    SetWhy := BaseSetWhy(refSet := stS);
  ELSIF NOT (stS.fDosePerCarrierUnit >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fDosePerCarrierUnit <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fMinCarrierFlow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMinCarrierFlow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tCarrierProveDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fMaxPumpSpeedPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMaxPumpSpeedPct <= 100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fDosePerStroke >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fDosePerStroke <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tStrokePulseWidth >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_DoseFlowSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bPumpRunCommand := FALSE;
  fPumpSpeedPct := 0.0;
  bBusy := FALSE;
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

(* the carrier *)
fFlow := 0.0;
bFlowGood := FALSE;
IF ipCarrierMeter <> NULL THEN
  fFlow := ipCarrierMeter.fActFlowPerHour;
  bFlowGood := ipCarrierMeter.bIsGood AND ABS(fFlow) <= REAL#3.4E38;
END_IF;
bCarrier := bCarrierRunning AND bFlowGood AND fFlow >= refData.set.fMinCarrierFlow
            AND (refData.set.fMinCarrierFlow > 0.0 OR fFlow > 0.0);
IF NOT bCarrier THEN
  tCarrierSince := tNow;
END_IF;
bCarrierOk := bCarrier AND tNow - tCarrierSince >= refData.set.tCarrierProveDelay;
bTripHold := bTripHold OR bCapTrip;

(* dose while the run request is on *)
fReq := 0.0;
fRatioUse := refData.set.fDosePerCarrierUnit;
IF fDosePerCarrierUnit > 0.0 AND fDosePerCarrierUnit <= REAL#3.4E38 THEN
  fRatioUse := fDosePerCarrierUnit;
END_IF;
IF bOk AND bRunReq AND (bBusy OR bPermissive) THEN
  IF NOT bBusy THEN
    bBusy := TRUE;
    bHoldLatch := FALSE;
    fDlv := 0.0;
    fPulseAcc := 0.0;
    nOwed := 0;
  END_IF;
  bPaused := bPause OR bHoldLatch OR NOT bInterlock OR bTripHold OR NOT bCarrierOk;
  fCap := LIMIT(0.0, refData.set.fMaxPumpSpeedPct, 100.0);
  IF bCarrierOk THEN
    fReq := fFlow * fRatioUse;
  END_IF;
  IF NOT bPaused AND fReq > 0.0 THEN
    bPumpGo := TRUE;
    IF refData.set.fFlowAtFullSpeed > 0.0 THEN
      fPct := fReq / refData.set.fFlowAtFullSpeed * 100.0;
      fPumpSpeedPct := MIN(fPct, fCap);
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(fPumpSpeedPct / 100.0 * refData.set.fFlowAtFullSpeed) * fStepS / 3600.0;
      END_IF;
    ELSE
      fPumpSpeedPct := fCap;
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(fReq) * fStepS / 3600.0;   (* a pulse pump *)
      END_IF;
    END_IF;
  END_IF;
  (* stroke pulses: one every fDosePerStroke dosed *)
  IF refData.set.fDosePerStroke > 0.0 AND fDosed > 0.0 THEN
    fPulseAcc := fPulseAcc + fDosed / REAL_TO_LREAL(refData.set.fDosePerStroke);
    IF fPulseAcc >= 1.0 THEN
      IF fPulseAcc > 1.0E6 THEN
        fPulseAcc := 1.0E6;
      END_IF;
      nW := LREAL_TO_LINT(fPulseAcc);
      IF LINT_TO_LREAL(nW) > fPulseAcc THEN
        nW := nW - 1;
      END_IF;
      fPulseAcc := fPulseAcc - LINT_TO_LREAL(nW);
      nOwed := MIN(nOwed + LINT_TO_DINT(nW), 1000000);
    END_IF;
  END_IF;
  fDlv := fDlv + fDosed;
ELSE
  IF bBusy THEN
    refData.sts.fDeliveredLastDose := fDlv;
    eEnd := EndWhy(refSet := refData.set);
  END_IF;
  bBusy := FALSE;
  bPaused := FALSE;
  nOwed := 0;
END_IF;

(* the stroke pulse output *)
IF bPulseOn THEN
  IF tNow - tPulseAt >= refData.set.tStrokePulseWidth THEN
    bPulseOn := FALSE;
    tPulseAt := tNow;
  END_IF;
ELSIF nOwed > 0 AND tNow - tPulseAt >= refData.set.tStrokePulseWidth THEN
  bPulseOn := TRUE;
  tPulseAt := tNow;
  nOwed := nOwed - 1;
  refData.det.nStrokePulses := refData.det.nStrokePulses + 1;
END_IF;
bStrokePulse := bPulseOn;

bCapTrip := F_Protect(tNow := tNow, bConditionPresent := bBusy AND refData.set.fFlowAtFullSpeed > 0.0
                                              AND fReq > refData.set.fFlowAtFullSpeed * LIMIT(0.0, refData.set.fMaxPumpSpeedPct, 100.0) / 100.0,
                      bResetRequest := bResetNow, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stOverCapacityFault,
                      stStatus := refData.sts.stOverCapacityFault, stWorking := stWCap);
refData.sts.bCarrierProven := bCarrierOk;
bHandCarrier := bCarrierOk;
refData.sts.fDoseRateNeeded := fReq;
refData.sts.fRatioInUse := fRatioUse;
IF bPumpGo THEN
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk,
         bVTrip := bCapTrip, eVTrip := E_UtError.OverCapacity, bVWarn := stWCap.bWarning OR stWCap.bSettingBad,
         eVWarn := E_UtError.OverCapacity, eVPhase := E_DosePhase.Dosing, tVLeft := T#0s);
ELSE
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk,
         bVTrip := bCapTrip, eVTrip := E_UtError.OverCapacity, bVWarn := stWCap.bWarning OR stWCap.bSettingBad,
         eVWarn := E_UtError.OverCapacity, eVPhase := E_DosePhase.Waiting, tVLeft := T#0s);
END_IF;

END_FUNCTION_BLOCK