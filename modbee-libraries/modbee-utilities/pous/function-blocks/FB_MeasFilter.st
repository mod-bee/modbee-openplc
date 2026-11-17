FUNCTION_BLOCK FB_MeasFilter EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipIn : I_Measurement;
    refData : REFERENCE TO ST_MeasFilterData;
  END_VAR
  VAR_OUTPUT
    fValue : REAL;
  END_VAR
  VAR RETAIN
    stKept : ST_MeasFilterSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fbFilter : FB_Filter;
  END_VAR
  VAR_TEMP
    bInOk : BOOL;
    fV : REAL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := fValue;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := FALSE;
    IF ipIn <> NULL THEN bIsGood := ipIn.bIsGood; END_IF;
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

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFilterSet;
  END_VAR
  SetOk := stS.tFilter >= T#0s AND stS.fLowCutoff >= 0.0 AND stS.fLowCutoff <= REAL#3.4E38
           AND (NOT stS.bClamp OR stS.fClampMin <= stS.fClampMax)
           AND (stS.eMode = E_FilterMode.Lowpass OR stS.eMode = E_FilterMode.Average
                OR stS.eMode = E_FilterMode.BlockAvg);
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipIn = NULL THEN
  bError := TRUE;
  IF ipIn = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
bInOk := ipIn.bIsGood;
fbFilter(fIn := ipIn.fActValue, bInGood := bInOk, tTc := refData.set.tFilter, eMode := refData.set.eMode);
fV := fbFilter.fOut;
IF refData.set.fLowCutoff > 0.0 AND ABS(fV) < refData.set.fLowCutoff THEN
  fV := 0.0;
END_IF;
IF refData.set.bClamp THEN
  fV := LIMIT(refData.set.fClampMin, fV, refData.set.fClampMax);
END_IF;
fValue := fV;
refData.fValue := fV;
bError := FALSE;
bWarning := refData.bRefused;
IF refData.bRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF bInOk THEN eState := E_State.Running; ELSE eState := E_State.Held; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK