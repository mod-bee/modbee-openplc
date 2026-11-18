FUNCTION_BLOCK FB_MeasFrozen EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipIn : I_Measurement;
    refData : REFERENCE TO ST_MeasFrozenData;
  END_VAR
  VAR_OUTPUT
    bFrozen : BOOL;
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


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := 0.0;
    IF ipIn <> NULL THEN fActValue := ipIn.fActValue; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := FALSE;
    IF ipIn <> NULL THEN bIsGood := ipIn.bIsGood AND NOT bTripNow; END_IF;
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

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFrozenSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fBand >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fBand <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.stFrozen.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stFrozen.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stFrozen.nMaxRetries >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MeasFrozenSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipIn = NULL THEN
  bError := TRUE;
  IF ipIn = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  fRef := ipIn.fActValue;
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
bReset := SystemReset();
IF refData.bCmdReset THEN
  bReset := TRUE;
  refData.bCmdReset := FALSE;
  refData.bRefused := FALSE;
  refData.eRefusedWhy := E_UtError.None;
END_IF;
(* a bad input or a change past the band restarts the wait *)
IF NOT ipIn.bIsGood OR ABS(ipIn.fActValue - fRef) > refData.set.fBand THEN
  fRef := ipIn.fActValue;
  bCause := FALSE;
ELSE
  bCause := TRUE;
END_IF;
bTripNow := F_Protect(tNow := tNow, bCause := bCause, bResetReq := bReset, tRetryWindow := T#1h,
                      stSet := refData.set.stFrozen, stSts := refData.stFrozen, stWork := stWFrozen);
bFrozen := stWFrozen.bTrip OR stWFrozen.bWarn;
bError := bTripNow;
bWarning := NOT bError AND (stWFrozen.bWarn OR refData.bRefused);
IF bFrozen THEN
  eErrorId := E_UtError.Frozen;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault; ELSE eState := E_State.Running; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK