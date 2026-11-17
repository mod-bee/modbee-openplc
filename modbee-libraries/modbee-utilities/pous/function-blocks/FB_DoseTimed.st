(* FB_DoseTimed EXTENDS FB_Dose — timed dosing.
While bRun (or a bStart latch): the pump on at set.fRate % for set.tOnTime, off for set.tOffTime, over and over (on first);
a pause stops the clock. It doses only while bCarrierRunning has been on for set.tCarrierProven (Waiting, not a
fault). Dosed = set.fPumpCapacity x fRate % while the pump runs.
Pins: FB_Dose's, bCarrierRunning, refData -> FB_Dose's outputs. *)

FUNCTION_BLOCK FB_DoseTimed EXTENDS FB_Dose
  VAR_INPUT
    bCarrierRunning : BOOL := TRUE; (* the carrier (irrigation) pump runs *)
    refData : REFERENCE TO ST_DoseTimedData;
  END_VAR
  VAR RETAIN
    stKept : ST_DoseTimedSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    tCarrierSince : TIME;
    bCycOn : BOOL;
    tCycAcc : TIME;
  END_VAR
  VAR_TEMP
    bResetNow : BOOL;
    bOk : BOOL;
    bCarrierOk : BOOL;
    tLeft : TIME;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_DoseTimedSet;
  END_VAR
  SetOk := BaseSetOk(refSet := stS) AND stS.tOnTime >= T#0s AND stS.tOffTime >= T#0s
           AND stS.fRate >= 0.0 AND stS.fRate <= 100.0 AND stS.tCarrierProven >= T#0s;
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

IF NOT bCarrierRunning THEN
  tCarrierSince := tNow;
END_IF;
bCarrierOk := bCarrierRunning AND tNow - tCarrierSince >= refData.set.tCarrierProven;

tLeft := T#0s;
IF bOk AND bRunReq AND (bBusy OR bPermissive) THEN
  IF NOT bBusy THEN
    bBusy := TRUE;
    bHoldLatch := FALSE;
    fDlv := 0.0;
    bCycOn := TRUE;
    tCycAcc := T#0s;
  END_IF;
  bPaused := bHold OR bHoldLatch OR NOT bInterlock OR bTripHold OR NOT bCarrierOk;
  (* on for tOnTime, off for tOffTime; a pause stops the clock *)
  IF NOT bPaused THEN
    tCycAcc := tCycAcc + tStepT;
    IF bCycOn AND tCycAcc >= refData.set.tOnTime AND refData.set.tOffTime > T#0s THEN
      bCycOn := FALSE;
      tCycAcc := T#0s;
    ELSIF NOT bCycOn AND tCycAcc >= refData.set.tOffTime THEN
      bCycOn := TRUE;
      tCycAcc := T#0s;
    END_IF;
  END_IF;
  IF bCycOn AND NOT bPaused AND refData.set.tOnTime > T#0s THEN
    bPumpGo := TRUE;
    fRate := refData.set.fRate;
    IF bCounting THEN
      fDosed := REAL_TO_LREAL(refData.set.fPumpCapacity * fRate / 100.0) * fStepS / 3600.0;
    END_IF;
  END_IF;
  fDlv := fDlv + fDosed;
  IF bCycOn THEN
    tLeft := refData.set.tOnTime - tCycAcc;
  ELSE
    tLeft := refData.set.tOffTime - tCycAcc;
  END_IF;
ELSE
  IF bBusy THEN
    refData.sts.fLastDelivered := fDlv;
    eEnd := EndWhy(refSet := refData.set);
  END_IF;
  bBusy := FALSE;
  bPaused := FALSE;
END_IF;
refData.sts.bCarrierOk := bCarrierOk;
bHandCarrier := bCarrierOk;
IF bPumpGo THEN
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk, bVTrip := FALSE,
         eVTrip := E_UtError.None, bVWarn := FALSE, eVWarn := E_UtError.None, eVPhase := E_DosePhase.Dosing,
         tVLeft := tLeft);
ELSE
  Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts, bOk := bOk, bVTrip := FALSE,
         eVTrip := E_UtError.None, bVWarn := FALSE, eVWarn := E_UtError.None, eVPhase := E_DosePhase.Waiting,
         tVLeft := tLeft);
END_IF;

END_FUNCTION_BLOCK