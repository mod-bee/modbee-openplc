(* FB_MeasFilter — smooths and shapes a measurement: set.tFilterTime (FB_Filter, set.eFilterType), then below set.fZeroBelow
(> 0) reads 0 (a flow meter's creep), then with set.bClampOn held to fMinValue..fMaxValue. A bad input holds the
filter (the time not counted); bIsGood is the input's. *)

FUNCTION_BLOCK FB_MeasFilter EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipMeasurement : I_Measurement; (* the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...) *)
    refData : REFERENCE TO ST_MeasFilterData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fValue : REAL; (* the filtered value *)
    bGood : BOOL; (* fValue can be trusted (the source's bIsGood) *)
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


PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
  GET
    fActValue := fValue;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    bIsGood := FALSE;
    IF ipMeasurement <> NULL THEN bIsGood := ipMeasurement.bIsGood; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a continuous value (FALSE: switches only)
  GET
    bHasValue := FALSE;
    IF ipMeasurement <> NULL THEN bHasValue := ipMeasurement.bHasValue; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // the sensor is on this site (FALSE: no value, no bands, no fault)
  GET
    bIsFitted := FALSE;
    IF ipMeasurement <> NULL THEN bIsFitted := ipMeasurement.bIsFitted; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := E_Unit.None;
    IF ipMeasurement <> NULL THEN eUnit := ipMeasurement.eUnit; END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;    // the band asked about (LowLow, Low, High, HighHigh); returns TRUE while the value is in it
  END_VAR
  Band := FALSE;
  IF ipMeasurement <> NULL THEN Band := ipMeasurement.Band(eBand := eBand); END_IF;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFilterSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tFilterTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fZeroBelow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fZeroBelow <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF stS.bClampOn AND NOT (stS.fMinValue <= stS.fMaxValue) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.eFilterType = E_FilterMode.Lowpass OR stS.eFilterType = E_FilterMode.Average
             OR stS.eFilterType = E_FilterMode.BlockAvg) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFilterSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipMeasurement = NULL THEN
  bError := TRUE;
  bGood := FALSE;
  IF ipMeasurement = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bInOk := ipMeasurement.bIsGood;
fbFilter(fIn := ipMeasurement.fActValue, bInputGood := bInOk, tFilterTime := refData.set.tFilterTime, eFilterType := refData.set.eFilterType);
fV := fbFilter.fOut;
IF refData.set.fZeroBelow > 0.0 AND ABS(fV) < refData.set.fZeroBelow THEN
  fV := 0.0;
END_IF;
IF refData.set.bClampOn THEN
  fV := LIMIT(refData.set.fMinValue, fV, refData.set.fMaxValue);
END_IF;
fValue := fV;
bGood := bInOk;
refData.sts.fValue := fV;
bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF bInOk THEN eState := E_State.Running; ELSE eState := E_State.Held; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK