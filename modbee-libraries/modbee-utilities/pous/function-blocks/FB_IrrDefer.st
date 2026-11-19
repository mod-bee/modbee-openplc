(* FB_IrrDefer — the wet-weather / defer-irrigation inhibit: says when not to irrigate, why, and to send the effluent
to storage instead.
Pins: bRainSwitch (a rain switch), bSoilWetSwitch (a moisture switch), bRainSwitchGood / bSoilWetSwitchGood (the sensors' health; FALSE = lost),
bManualDefer (panel), bRemoteDefer (platform), ipSoilMoisture (a soil moisture transmitter or switch set, I_Measurement; NULL = the
switch pins) -> bDeferIrrigation (do not irrigate: -> FB_ZoneSeq's hold), eDeferReason, bSendToStorage (-> the route), plus
FB_Object's outputs. refData: its record.
bManualDefer, set.bManualDefer (HMI) and bRemoteDefer defer at once and release at once. The weather causes (rain, wet soil,
a lost rain or soil sensor) must last set.tDeferDelay to defer, so one tip of a gauge does not stop a run; once
deferred, every weather cause must be gone for set.tClearDelay (the soil drains) before irrigation is allowed
again. Wet soil: bSoilWetSwitch, or ipSoilMoisture (a value: wet at set.fSoilWetAtPct %, dry again below fSoilDryBelowPct; a switch set: its
High band); ipSoilMoisture not good, or bSoilWetSwitchGood / bRainSwitchGood FALSE, is a lost sensor and defers (fail-safe, a warning).
set.bRainSensorFitted / bSoilSensorFitted FALSE ignore a sensor that is not fitted. eDeferReason, when more than one applies: Manual,
Remote, Rain, Soil, RainLost, SoilLost. A weather defer is kept over a power cut (written on a change only; it
clears by its own delay afterwards). Settings are kept (a retained last-good copy, a bad write put back); a bad
setting that was never good defers (the safe way). *)

FUNCTION_BLOCK FB_IrrDefer EXTENDS FB_Object
  VAR_INPUT
    bRainSwitch : BOOL; (* a rain switch *)
    bSoilWetSwitch : BOOL; (* a soil moisture switch *)
    bRainSwitchGood : BOOL := TRUE; (* the rain sensor is healthy (FALSE = lost: defers, a warning) *)
    bSoilWetSwitchGood : BOOL := TRUE; (* the soil sensor is healthy (FALSE = lost) *)
    bManualDefer : BOOL; (* defer from the panel *)
    bRemoteDefer : BOOL; (* defer from the platform (SCADA) *)
    ipSoilMoisture : I_Measurement; (* NULL = bSoilWetSwitch / bSoilWetSwitchGood *)
    refData : REFERENCE TO ST_IrrDeferData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bDeferIrrigation : BOOL; (* do not irrigate *)
    eDeferReason : E_Defer; (* why it defers *)
    bSendToStorage : BOOL; (* to the route: send the water to storage *)
  END_VAR
  VAR RETAIN
    stKept : ST_IrrDeferSet;
    nKeptLayout : UINT;
    bDeferKept : BOOL; (* the weather defer (written on a change only) *)
    eReasonKept : E_Defer;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fbWet : FB_TwoPoint;
    bWxPrev : BOOL;
    tWxSince : TIME;
    fZero : REAL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bSoilWetNow : BOOL;
    bSoilLost : BOOL;
    eWxWhy : E_Defer;
    bWx : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_IrrDeferSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tDeferDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tClearDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ABS(stS.fSoilWetAtPct) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fSoilDryBelowPct) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.fSoilDryBelowPct < stS.fSoilWetAtPct) THEN
    SetWhy := E_UtError.LimitsBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IrrDeferSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bDeferIrrigation := TRUE;                 (* no record: defer, the safe way *)
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
  tWxSince := tNow;
  bWxPrev := bDeferKept;          (* a kept weather defer clears by its own delay *)
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the soil *)
bSoilWetNow := bSoilWetSwitch;
bSoilLost := NOT bSoilWetSwitchGood;
refData.sts.fSoilMoisturePct := fZero / fZero;
IF ipSoilMoisture <> NULL THEN
  IF ipSoilMoisture.bIsFitted THEN
    IF NOT ipSoilMoisture.bIsGood THEN
      bSoilLost := TRUE;
    ELSIF ipSoilMoisture.bHasValue THEN
      refData.sts.fSoilMoisturePct := ipSoilMoisture.fActValue;
      fbWet(fIn := ipSoilMoisture.fActValue, bEnable := TRUE, eDirection := E_TwoPointDir.OnAbove,
            fOnPoint := refData.set.fSoilWetAtPct, fOffPoint := refData.set.fSoilDryBelowPct);
      bSoilWetNow := bSoilWetNow OR fbWet.bOutputOn;
    ELSE
      bSoilWetNow := bSoilWetNow OR ipSoilMoisture.Band(eBand := E_Band.High);
    END_IF;
  END_IF;
END_IF;
refData.sts.bSoilIsWet := bSoilWetNow;

(* the weather causes *)
eWxWhy := E_Defer.None;
IF refData.set.bRainSensorFitted AND bRainSwitchGood AND bRainSwitch THEN
  eWxWhy := E_Defer.Rain;
ELSIF refData.set.bSoilSensorFitted AND NOT bSoilLost AND bSoilWetNow THEN
  eWxWhy := E_Defer.Soil;
ELSIF refData.set.bRainSensorFitted AND NOT bRainSwitchGood THEN
  eWxWhy := E_Defer.RainLost;
ELSIF refData.set.bSoilSensorFitted AND bSoilLost THEN
  eWxWhy := E_Defer.SoilLost;
END_IF;
bWx := eWxWhy <> E_Defer.None;
IF bWx <> bWxPrev THEN
  tWxSince := tNow;
END_IF;
bWxPrev := bWx;
IF bWx THEN
  IF (bDeferKept OR tNow - tWxSince >= refData.set.tDeferDelay) AND (NOT bDeferKept OR eReasonKept <> eWxWhy) THEN
    bDeferKept := TRUE;           (* RETAIN: written on a change only *)
    eReasonKept := eWxWhy;
  END_IF;
ELSIF bDeferKept AND tNow - tWxSince >= refData.set.tClearDelay THEN
  bDeferKept := FALSE;
  eReasonKept := E_Defer.None;
END_IF;
IF NOT bOk THEN
  eDeferReason := E_Defer.Setting;     (* a bad setting never good: defer, the safe way *)
ELSIF bManualDefer OR refData.set.bManualDefer THEN
  eDeferReason := E_Defer.Manual;
ELSIF bRemoteDefer THEN
  eDeferReason := E_Defer.Remote;
ELSIF bDeferKept THEN
  eDeferReason := eReasonKept;
ELSE
  eDeferReason := E_Defer.None;
END_IF;
bDeferIrrigation := eDeferReason <> E_Defer.None;
bSendToStorage := bDeferIrrigation AND refData.set.bStorageFitted;
IF NOT bOk THEN
  refData.sts.tTimeLeft := T#0s;
ELSIF bWx AND NOT bDeferKept THEN
  refData.sts.tTimeLeft := refData.set.tDeferDelay - (tNow - tWxSince);
ELSIF bDeferKept AND NOT bWx THEN
  refData.sts.tTimeLeft := refData.set.tClearDelay - (tNow - tWxSince);
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.bDeferred := bDeferIrrigation;
refData.sts.eDeferReason := eDeferReason;

(* errors: a defer is the block's job; a lost sensor is a warning *)
bError := NOT bOk;
bWarning := NOT bError AND (eWxWhy = E_Defer.RainLost OR eWxWhy = E_Defer.SoilLost OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF eWxWhy = E_Defer.RainLost OR eWxWhy = E_Defer.SoilLost THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bDeferIrrigation THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK