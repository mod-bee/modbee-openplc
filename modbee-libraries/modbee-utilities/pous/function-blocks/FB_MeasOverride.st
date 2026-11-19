(* FB_MeasOverride — simulation and what a bad value shows. bSimulate (the record; never kept: off after a power cut)
gives fSimulatedValue, good, a warning (Simulated). While the input is bad, set.eWhenValueBad: Pass (its value), Hold (the last
good value) or Substitute (set.fSubstituteValue); bIsGood stays FALSE (a consumer still knows), only the value changes. *)

FUNCTION_BLOCK FB_MeasOverride EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipMeasurement : I_Measurement; (* the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...) *)
    refData : REFERENCE TO ST_MeasOverrideData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fValue : REAL; (* the value passed on *)
    bGood : BOOL; (* the value can be trusted *)
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


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (ABS(refData.set.fSubstituteValue) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.eWhenValueBad = E_OnBadValue.Pass OR refData.set.eWhenValueBad = E_OnBadValue.Hold
             OR refData.set.eWhenValueBad = E_OnBadValue.Substitute) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
  GET
    fActValue := fValue;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    bIsGood := bGood;
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

IF NOT __ISVALIDREF(refData) OR ipMeasurement = NULL THEN
  bGood := FALSE;
  bError := TRUE;
  IF ipMeasurement = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
IF ipMeasurement.bIsGood THEN
  fLastGood := ipMeasurement.fActValue;
END_IF;
IF refData.bSimulate THEN
  fValue := refData.fSimulatedValue;
  bGood := TRUE;
ELSIF ipMeasurement.bIsGood THEN
  fValue := ipMeasurement.fActValue;
  bGood := TRUE;
ELSE
  bGood := FALSE;
  CASE refData.set.eWhenValueBad OF
    E_OnBadValue.Hold: fValue := fLastGood;
    E_OnBadValue.Substitute: fValue := refData.set.fSubstituteValue;
  ELSE
    fValue := ipMeasurement.fActValue;
  END_CASE;
END_IF;
bError := FALSE;
bWarning := refData.bSimulate OR refData.sts.bSettingRefused;
IF refData.bSimulate THEN
  eErrorId := E_UtError.Simulated;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bGood THEN eState := E_State.Running; ELSE eState := E_State.Held; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK