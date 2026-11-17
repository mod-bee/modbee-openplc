FUNCTION_BLOCK FB_MeasOverride EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipIn : I_Measurement;
    refData : REFERENCE TO ST_MeasOverrideData;
  END_VAR
  VAR_OUTPUT
    fValue : REAL;
    bGood : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_MeasOverrideSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fLastGood : REAL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := fValue;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := FALSE;
    IF ipIn <> NULL THEN bHasValue := ipIn.bHasValue; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := FALSE;
    IF ipIn <> NULL THEN bIsFitted := ipIn.bIsFitted; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;
    IF ipIn <> NULL THEN eUnit := ipIn.eUnit; END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
  IF ipIn <> NULL THEN Band := ipIn.Band(eBand := eBand); END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipIn = NULL THEN
  bGood := FALSE;
  bError := TRUE;
  IF ipIn = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  refData.bSimulate := FALSE;     (* simulation never survives a power cut *)
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
ELSIF ABS(refData.set.fSubstitute) <= REAL#3.4E38
      AND (refData.set.eOnBad = E_OnBadValue.Pass OR refData.set.eOnBad = E_OnBadValue.Hold
           OR refData.set.eOnBad = E_OnBadValue.Substitute) THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF ipIn.bIsGood THEN
  fLastGood := ipIn.fActValue;
END_IF;
IF refData.bSimulate THEN
  fValue := refData.fSimValue;
  bGood := TRUE;
ELSIF ipIn.bIsGood THEN
  fValue := ipIn.fActValue;
  bGood := TRUE;
ELSE
  bGood := FALSE;
  CASE refData.set.eOnBad OF
    E_OnBadValue.Hold: fValue := fLastGood;
    E_OnBadValue.Substitute: fValue := refData.set.fSubstitute;
  ELSE
    fValue := ipIn.fActValue;
  END_CASE;
END_IF;
bError := FALSE;
bWarning := refData.bSimulate OR refData.bRefused;
IF refData.bSimulate THEN
  eErrorId := E_UtError.Simulated;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bGood THEN eState := E_State.Running; ELSE eState := E_State.Held; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK