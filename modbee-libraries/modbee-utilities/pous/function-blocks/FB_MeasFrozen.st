(* FB_MeasFrozen — a measurement that should move but does not: no change larger than set.fMinChange for the protection's
delay (set.stFrozenFault, default Warn after 10 min, Auto, recover 10 s): Warn = a warning (still good), Trip = not
good, bError. Error Frozen. A change past the band restarts the wait; a bad input is not frozen. *)

FUNCTION_BLOCK FB_MeasFrozen EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipMeasurement : I_Measurement; (* the measurement block it works on (FB_AnalogIn, FB_SwitchSet, FB_Vessel ...) *)
    refData : REFERENCE TO ST_MeasFrozenData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fValue : REAL; (* the value passed on (the source's) *)
    bGood : BOOL; (* fValue can be trusted: the source is good and not frozen past a trip *)
    bValueFrozen : BOOL; (* the value has not moved for the delay *)
  END_VAR
  VAR RETAIN
    stKept : ST_MeasFrozenSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stWFrozen : ST_ProtectionWork;
    fRef : REAL; (* the value the check compares with *)
    bTripNow : BOOL;
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bCause : BOOL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
  GET
    fActValue := 0.0;
    IF ipMeasurement <> NULL THEN fActValue := ipMeasurement.fActValue; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    bIsGood := FALSE;
    IF ipMeasurement <> NULL THEN bIsGood := ipMeasurement.bIsGood AND NOT bTripNow; END_IF;
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
    stS : REFERENCE TO ST_MeasFrozenSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fMinChange >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMinChange <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.stFrozenFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stFrozenFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stFrozenFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFrozenSet;
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
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  fRef := ipMeasurement.fActValue;
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
bReset := SystemReset();
IF refData.bCmdResetFaults THEN
  bReset := TRUE;
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
(* a bad input or a change past the band restarts the wait *)
IF NOT ipMeasurement.bIsGood OR ABS(ipMeasurement.fActValue - fRef) > refData.set.fMinChange THEN
  fRef := ipMeasurement.fActValue;
  bCause := FALSE;
ELSE
  bCause := TRUE;
END_IF;
bTripNow := F_Protect(tNow := tNow, bConditionPresent := bCause, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                      stSettings := refData.set.stFrozenFault, stStatus := refData.sts.stFrozenFault, stWorking := stWFrozen);
bValueFrozen := stWFrozen.bTripping OR stWFrozen.bWarning;
fValue := ipMeasurement.fActValue;
bGood := ipMeasurement.bIsGood AND NOT bTripNow;
bError := bTripNow;
bWarning := NOT bError AND (stWFrozen.bWarning OR refData.sts.bSettingRefused);
IF bValueFrozen THEN
  eErrorId := E_UtError.Frozen;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK