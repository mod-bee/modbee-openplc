(* FB_DoseFlow EXTENDS FB_Dose — flow-paced dosing (fertigation; src-v2 UT_DOSE FLOW).
While bRun (or a bStart latch) the dosing pump runs in proportion to the carrier: the meter's rate (per hour) x
the ratio (fRatio pin for this run, <= 0 = set.fRatio); fRate = required / set.fPumpCapacity %, capped at
set.fMaxRate (no capacity: fMaxRate, a pulse pump). It injects only while bCarrierRunning and the carrier flow has
been at / above set.fMinFlow for set.tCarrierProven (Waiting, not a fault). bPulse: one stroke every
set.fPulseVolume dosed (0 = none), set.tPulseWidth on and off. Asked for more than the pump can give:
set.stOverCapacity (a trip holds the dose).
Pins: FB_Dose's, bCarrierRunning, ipMeter (I_Meter: the carrier), fRatio, refData -> FB_Dose's outputs, bPulse. *)

FUNCTION_BLOCK FB_DoseFlow EXTENDS FB_Dose
  VAR_INPUT
    bCarrierRunning : BOOL := TRUE; (* the carrier (irrigation) pump runs *)
    ipMeter : I_Meter; (* the carrier meter *)
    fRatio : REAL; (* this run's ratio (<= 0 = set.fRatio) *)
    refData : REFERENCE TO ST_DoseFlowData;
  END_VAR
  VAR_OUTPUT
    bPulse : BOOL; (* stroke pulses *)
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


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_DoseFlowSet;
  END_VAR
  SetOk := BaseSetOk(refSet := stS)
           AND stS.fRatio >= 0.0 AND stS.fRatio <= REAL#3.4E38 AND stS.fMinFlow >= 0.0 AND stS.fMinFlow <= REAL#3.4E38
           AND stS.tCarrierProven >= T#0s AND stS.fMaxRate >= 0.0 AND stS.fMaxRate <= 100.0
           AND stS.fPulseVolume >= 0.0 AND stS.fPulseVolume <= REAL#3.4E38 AND stS.tPulseWidth >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bPumpRun := FALSE;
  fRate := 0.0;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;

(* the carrier *)
fFlow := 0.0;
bFlowGood := FALSE;
IF ipMeter <> NULL THEN
  fFlow := ipMeter.fActRate;
  bFlowGood := ipMeter.bIsGood AND ABS(fFlow) <= REAL#3.4E38;
END_IF;
bCarrier := bCarrierRunning AND bFlowGood AND fFlow >= refData.set.fMinFlow
            AND (refData.set.fMinFlow > 0.0 OR fFlow > 0.0);
IF NOT bCarrier THEN
  tCarrierSince := tNow;
END_IF;
bCarrierOk := bCarrier AND tNow - tCarrierSince >= refData.set.tCarrierProven;
bTripHold := bTripHold OR bCapTrip;

(* dose while the run request is on *)
fReq := 0.0;
fRatioUse := refData.set.fRatio;
IF fRatio > 0.0 AND fRatio <= REAL#3.4E38 THEN
  fRatioUse := fRatio;
END_IF;
IF bOk AND bRunReq AND (bBusy OR bPermissive) THEN
  IF NOT bBusy THEN
    bBusy := TRUE;
    bHoldLatch := FALSE;
    fDlv := 0.0;
    fPulseAcc := 0.0;
    nOwed := 0;
  END_IF;
  bPaused := bHold OR bHoldLatch OR NOT bInterlock OR bTripHold OR NOT bCarrierOk;
  fCap := LIMIT(0.0, refData.set.fMaxRate, 100.0);
  IF bCarrierOk THEN
    fReq := fFlow * fRatioUse;
  END_IF;
  IF NOT bPaused AND fReq > 0.0 THEN
    bPumpGo := TRUE;
    IF refData.set.fPumpCapacity > 0.0 THEN
      fPct := fReq / refData.set.fPumpCapacity * 100.0;
      fRate := MIN(fPct, fCap);
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(fRate / 100.0 * refData.set.fPumpCapacity) * fStepS / 3600.0;
      END_IF;
    ELSE
      fRate := fCap;
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(fReq) * fStepS / 3600.0;   (* a pulse pump *)
      END_IF;
    END_IF;
  END_IF;
  (* stroke pulses: one every fPulseVolume dosed *)
  IF refData.set.fPulseVolume > 0.0 AND fDosed > 0.0 THEN
    fPulseAcc := fPulseAcc + fDosed / REAL_TO_LREAL(refData.set.fPulseVolume);
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
    refData.sts.fLastDelivered := fDlv;
    eEnd := EndWhy(refSet := refData.set);
  END_IF;
  bBusy := FALSE;
  bPaused := FALSE;
  nOwed := 0;
END_IF;

(* the stroke pulse output *)
IF bPulseOn THEN
  IF tNow - tPulseAt >= refData.set.tPulseWidth THEN
    bPulseOn := FALSE;
    tPulseAt := tNow;
  END_IF;
ELSIF nOwed > 0 AND tNow - tPulseAt >= refData.set.tPulseWidth THEN
  bPulseOn := TRUE;
  tPulseAt := tNow;
  nOwed := nOwed - 1;
  refData.det.nPulses := refData.det.nPulses + 1;
END_IF;
bPulse := bPulseOn;

bCapTrip := F_Protect(tNow := tNow, bCause := bBusy AND refData.set.fPumpCapacity > 0.0
                                              AND fReq > refData.set.fPumpCapacity * LIMIT(0.0, refData.set.fMaxRate, 100.0) / 100.0,
                      bResetReq := bResetNow, tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stOverCapacity,
                      stSts := refData.sts.stOverCapacity, stWork := stWCap);
refData.sts.bCarrierOk := bCarrierOk;
bHandCarrier := bCarrierOk;
refData.sts.fRequired := fReq;
refData.sts.fRatioActive := fRatioUse;
IF bPumpGo THEN
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk,
         bVTrip := bCapTrip, eVTrip := E_UtError.OverCapacity, bVWarn := stWCap.bWarn OR stWCap.bBadSetting,
         eVWarn := E_UtError.OverCapacity, eVPhase := E_DosePhase.Dosing, tVLeft := T#0s);
ELSE
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk,
         bVTrip := bCapTrip, eVTrip := E_UtError.OverCapacity, bVWarn := stWCap.bWarn OR stWCap.bBadSetting,
         eVWarn := E_UtError.OverCapacity, eVPhase := E_DosePhase.Waiting, tVLeft := T#0s);
END_IF;

END_FUNCTION_BLOCK