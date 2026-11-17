(* FB_PumpDiag — the likely cause of a pump's hydraulic trouble from its pressure, flow and suction. An observer: it
only tells, the pump's FB_LevelCheck parts act.
While bRunning (the pump runs), after set.tDelay of the same finding:
  Blocked   pressure high and flow low (a closed valve, a blocked line)
  Burst     pressure low and flow high (a burst or open line)
  Suction   suction low (a dry well, a blocked inlet)
  NoLift    pressure low and flow low (air-locked, worn, turning backwards)
in that order. Each measurement is optional (unwired, not fitted or not good: its tests are left out); each limit
0 is off. Not running: Normal.
Pins: bRunning, ipPressure, ipFlow, ipSuction, refData -> eDiagnosis, plus FB_Object's outputs (bWarning while a
diagnosis other than Normal stands, eErrorId PumpDiagnosis). Settings are kept (a retained last-good copy, a bad
write put back). *)

FUNCTION_BLOCK FB_PumpDiag EXTENDS FB_Object
  VAR_INPUT
    bRunning : BOOL; (* the pump runs *)
    ipPressure : I_Measurement; (* optional *)
    ipFlow : I_Measurement; (* optional *)
    ipSuction : I_Measurement; (* optional *)
    refData : REFERENCE TO ST_PumpDiagData;
  END_VAR
  VAR_OUTPUT
    eDiagnosis : E_PumpDiag;
  END_VAR
  VAR RETAIN
    stKept : ST_PumpDiagSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    eSeen : E_PumpDiag; (* the finding now, before the delay *)
    tSeenAt : TIME;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bPHigh : BOOL;
    bPLow : BOOL;
    bFHigh : BOOL;
    bFLow : BOOL;
    bSLow : BOOL;
    eNow : E_PumpDiag;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_PumpDiagSet;
  END_VAR
  SetOk := stS.tDelay >= T#0s
           AND (stS.fPressureHigh <= 0.0 OR stS.fPressureLow <= 0.0 OR stS.fPressureLow < stS.fPressureHigh)
           AND (stS.fFlowHigh <= 0.0 OR stS.fFlowLow <= 0.0 OR stS.fFlowLow < stS.fFlowHigh);
END_METHOD

(* the measurement can be used: wired, fitted, good *)
METHOD PRIVATE Usable : BOOL
  VAR_INPUT
    ipM : I_Measurement;
  END_VAR
  Usable := FALSE;
  IF ipM <> NULL THEN
    IF ipM.bIsFitted AND ipM.bIsGood THEN
      Usable := TRUE;
    END_IF;
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  eDiagnosis := E_PumpDiag.Normal;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
END_IF;

(* the findings now *)
bPHigh := FALSE; bPLow := FALSE; bFHigh := FALSE; bFLow := FALSE; bSLow := FALSE;
IF Usable(ipM := ipPressure) THEN
  bPHigh := refData.set.fPressureHigh > 0.0 AND ipPressure.fActValue >= refData.set.fPressureHigh;
  bPLow := refData.set.fPressureLow > 0.0 AND ipPressure.fActValue <= refData.set.fPressureLow;
END_IF;
IF Usable(ipM := ipFlow) THEN
  bFHigh := refData.set.fFlowHigh > 0.0 AND ipFlow.fActValue >= refData.set.fFlowHigh;
  bFLow := refData.set.fFlowLow > 0.0 AND ipFlow.fActValue <= refData.set.fFlowLow;
END_IF;
IF Usable(ipM := ipSuction) THEN
  bSLow := refData.set.fSuctionLow > 0.0 AND ipSuction.fActValue <= refData.set.fSuctionLow;
END_IF;
IF NOT bRunning OR NOT bOk THEN
  eNow := E_PumpDiag.Normal;
ELSIF bPHigh AND bFLow THEN
  eNow := E_PumpDiag.Blocked;
ELSIF bPLow AND bFHigh THEN
  eNow := E_PumpDiag.Burst;
ELSIF bSLow THEN
  eNow := E_PumpDiag.Suction;
ELSIF bPLow AND bFLow THEN
  eNow := E_PumpDiag.NoLift;
ELSE
  eNow := E_PumpDiag.Normal;
END_IF;
(* the delay: a finding must stand; Normal at once *)
IF eNow <> eSeen THEN
  eSeen := eNow;
  tSeenAt := tNow;
END_IF;
IF eNow = E_PumpDiag.Normal THEN
  eDiagnosis := E_PumpDiag.Normal;
ELSIF tNow - tSeenAt >= refData.set.tDelay THEN
  eDiagnosis := eNow;
END_IF;
refData.eDiagnosis := eDiagnosis;

bError := NOT bOk;
bWarning := NOT bError AND (eDiagnosis <> E_PumpDiag.Normal OR refData.bRefused);
IF bError THEN
  eErrorId := E_UtError.BadSetting;
ELSIF eDiagnosis <> E_PumpDiag.Normal THEN
  eErrorId := E_UtError.PumpDiagnosis;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bRunning THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK