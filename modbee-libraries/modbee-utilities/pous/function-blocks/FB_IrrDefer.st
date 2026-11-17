(* FB_IrrDefer — the wet-weather / defer-irrigation inhibit: says when not to irrigate, why, and to send the effluent
to storage instead.
Pins: bRain (a rain switch), bSoilWet (a moisture switch), bRainOk / bSoilOk (the sensors' health; FALSE = lost),
bManual (panel), bRemote (platform), ipSoil (a soil moisture transmitter or switch set, I_Measurement; NULL = the
switch pins) -> bDefer (do not irrigate: -> FB_ZoneSeq's hold), eReason, bToStorage (-> the route), plus
FB_Object's outputs. refData: its record.
bManual, set.bManualDefer (HMI) and bRemote defer at once and release at once. The weather causes (rain, wet soil,
a lost rain or soil sensor) must last set.tOnDelay to defer, so one tip of a gauge does not stop a run; once
deferred, every weather cause must be gone for set.tClearDelay (the soil drains) before irrigation is allowed
again. Wet soil: bSoilWet, or ipSoil (a value: wet at set.fSoilWet %, dry again below fSoilDry; a switch set: its
High band); ipSoil not good, or bSoilOk / bRainOk FALSE, is a lost sensor and defers (fail-safe, a warning).
set.bUseRain / bUseSoil FALSE ignore a sensor that is not fitted. eReason, when more than one applies: Manual,
Remote, Rain, Soil, RainLost, SoilLost. A weather defer is kept over a power cut (written on a change only; it
clears by its own delay afterwards). Settings are kept (a retained last-good copy, a bad write put back); a bad
setting that was never good defers (the safe way). *)

FUNCTION_BLOCK FB_IrrDefer EXTENDS FB_Object
  VAR_INPUT
    bRain : BOOL;
    bSoilWet : BOOL;
    bRainOk : BOOL := TRUE;
    bSoilOk : BOOL := TRUE;
    bManual : BOOL;
    bRemote : BOOL;
    ipSoil : I_Measurement; (* NULL = bSoilWet / bSoilOk *)
    refData : REFERENCE TO ST_IrrDeferData;
  END_VAR
  VAR_OUTPUT
    bDefer : BOOL; (* do not irrigate *)
    eReason : E_Defer;
    bToStorage : BOOL;
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


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_IrrDeferSet;
  END_VAR
  SetOk := stS.tOnDelay >= T#0s AND stS.tClearDelay >= T#0s
           AND ABS(stS.fSoilWet) <= REAL#3.4E38 AND ABS(stS.fSoilDry) <= REAL#3.4E38 AND stS.fSoilDry < stS.fSoilWet;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bDefer := TRUE;                 (* no record: defer, the safe way *)
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bRefused := FALSE;
END_IF;

(* the soil *)
bSoilWetNow := bSoilWet;
bSoilLost := NOT bSoilOk;
refData.sts.fSoil := fZero / fZero;
IF ipSoil <> NULL THEN
  IF ipSoil.bIsFitted THEN
    IF NOT ipSoil.bIsGood THEN
      bSoilLost := TRUE;
    ELSIF ipSoil.bHasValue THEN
      refData.sts.fSoil := ipSoil.fActValue;
      fbWet(fIn := ipSoil.fActValue, bEnable := TRUE, eDir := E_TwoPointDir.OnAbove,
            fOnPoint := refData.set.fSoilWet, fOffPoint := refData.set.fSoilDry);
      bSoilWetNow := bSoilWetNow OR fbWet.bQ;
    ELSE
      bSoilWetNow := bSoilWetNow OR ipSoil.Band(eBand := E_Band.High);
    END_IF;
  END_IF;
END_IF;
refData.sts.bSoilIsWet := bSoilWetNow;

(* the weather causes *)
eWxWhy := E_Defer.None;
IF refData.set.bUseRain AND bRainOk AND bRain THEN
  eWxWhy := E_Defer.Rain;
ELSIF refData.set.bUseSoil AND NOT bSoilLost AND bSoilWetNow THEN
  eWxWhy := E_Defer.Soil;
ELSIF refData.set.bUseRain AND NOT bRainOk THEN
  eWxWhy := E_Defer.RainLost;
ELSIF refData.set.bUseSoil AND bSoilLost THEN
  eWxWhy := E_Defer.SoilLost;
END_IF;
bWx := eWxWhy <> E_Defer.None;
IF bWx <> bWxPrev THEN
  tWxSince := tNow;
END_IF;
bWxPrev := bWx;
IF bWx THEN
  IF (bDeferKept OR tNow - tWxSince >= refData.set.tOnDelay) AND (NOT bDeferKept OR eReasonKept <> eWxWhy) THEN
    bDeferKept := TRUE;           (* RETAIN: written on a change only *)
    eReasonKept := eWxWhy;
  END_IF;
ELSIF bDeferKept AND tNow - tWxSince >= refData.set.tClearDelay THEN
  bDeferKept := FALSE;
  eReasonKept := E_Defer.None;
END_IF;
IF NOT bOk THEN
  eReason := E_Defer.Setting;     (* a bad setting never good: defer, the safe way *)
ELSIF bManual OR refData.set.bManualDefer THEN
  eReason := E_Defer.Manual;
ELSIF bRemote THEN
  eReason := E_Defer.Remote;
ELSIF bDeferKept THEN
  eReason := eReasonKept;
ELSE
  eReason := E_Defer.None;
END_IF;
bDefer := eReason <> E_Defer.None;
bToStorage := bDefer AND refData.set.bStorage;
IF NOT bOk THEN
  refData.sts.tTimeLeft := T#0s;
ELSIF bWx AND NOT bDeferKept THEN
  refData.sts.tTimeLeft := refData.set.tOnDelay - (tNow - tWxSince);
ELSIF bDeferKept AND NOT bWx THEN
  refData.sts.tTimeLeft := refData.set.tClearDelay - (tNow - tWxSince);
ELSE
  refData.sts.tTimeLeft := T#0s;
END_IF;
refData.sts.bDeferred := bDefer;
refData.sts.eReason := eReason;

(* errors: a defer is the block's job; a lost sensor is a warning *)
bError := NOT bOk;
bWarning := NOT bError AND (eWxWhy = E_Defer.RainLost OR eWxWhy = E_Defer.SoilLost OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF eWxWhy = E_Defer.RainLost OR eWxWhy = E_Defer.SoilLost THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bDefer THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK