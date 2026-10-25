(* UT_IRR_DEFER — wet-weather / defer-irrigation inhibit: says when not to
irrigate, why, and to send the effluent to storage instead.

Manual (pin), set.manualDefer (HMI) and Remote (platform) defer at once and
release at once. The weather causes (Rain, wet soil, a lost rain or soil
sensor) must last onDelay to defer, so one tip of a gauge does not stop a
run; once deferred, every weather cause must be gone for clearDelay (the
soil drains) before irrigation is allowed again. Wet soil: SoilWet, or the
Soil plug (a transmitter: wet at soilWet %, dry again below soilDry; a
switch set: its H band); a Soil plug not Good, or SoilOk / RainOk FALSE, is
a lost sensor and defers (fail-safe). useRain / useSoil FALSE ignore a
sensor that is not fitted. Reason, when more than one applies: MANUAL,
REMOTE, RAIN, SOIL, RAIN_LOST, SOIL_LOST. A weather defer is kept over a
power cut (it clears by its own delay afterwards). Settings kept; a bad
write is put back. *)

FUNCTION_BLOCK UT_IRR_DEFER
  VAR_INPUT
    Rain : BOOL; (* raining (a rain switch) *)
    SoilWet : BOOL; (* soil saturated (a moisture switch) *)
    RainOk : BOOL := TRUE; (* the rain sensor's health (FALSE = lost: defers) *)
    SoilOk : BOOL := TRUE;
    Manual : BOOL; (* panel defer *)
    Remote : BOOL; (* platform defer *)
    Soil : UT_I_MEAS; (* soil moisture transmitter or switch set; NULL = SoilWet / SoilOk *)
  END_VAR
  VAR_OUTPUT
    Defer : BOOL; (* do not irrigate (-> zs.RainHold) *)
    Reason : UT_DEFER;
    ToStorage : BOOL; (* (-> UT_ROUTE) *)
    Warning : BOOL; (* a sensor lost *)
  END_VAR
  VAR_IN_OUT
    Data : UT_IRR_DEFER_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_IRR_DEFER_SET;
    keptGood : BOOL;
    deferKept : BOOL; (* kept on change *)
    reasonKept : UT_DEFER;
  END_VAR
  VAR
    keep : UT_KEEP;
    wet : UT_TWO_POINT;
    ok : BOOL;
    cfgId : UT_FAULT;
    tCur : TIME;
    zero : REAL;
    started : BOOL;
    soilWetNow : BOOL;
    soilLost : BOOL;
    wxWhy : UT_DEFER;
    wx : BOOL;
    wxPrev : BOOL;
    wxSince : TIME;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_IRR_DEFER_CHECK(S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_IRR_DEFER_CHECK(S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
IF NOT started THEN
  started := TRUE;
  wxSince := tCur;
  wxPrev := deferKept;           (* a kept weather defer clears by its own delay *)
END_IF;

(* the soil *)
soilWetNow := SoilWet;
soilLost := NOT SoilOk;
Data.sts.soil := zero / zero;
IF Soil <> NULL THEN
  IF Soil.IsFitted() THEN
    IF NOT Soil.GoodNow() THEN
      soilLost := TRUE;
    ELSIF Soil.HasValue() THEN
      Data.sts.soil := Soil.GetValue();
      wet(In := Soil.GetValue(), Enable := TRUE, Dir := UT_TP_ON_ABOVE, OnPoint := Data.set.soilWet,
          OffPoint := Data.set.soilDry);
      soilWetNow := soilWetNow OR wet.Q;
    ELSE
      soilWetNow := soilWetNow OR Soil.IsHiNow();
    END_IF;
  END_IF;
END_IF;
Data.sts.soilIsWet := soilWetNow;

(* the weather causes *)
wxWhy := UT_DEF_NONE;
IF Data.set.useRain AND RainOk AND Rain THEN
  wxWhy := UT_DEF_RAIN;
ELSIF Data.set.useSoil AND NOT soilLost AND soilWetNow THEN
  wxWhy := UT_DEF_SOIL;
ELSIF Data.set.useRain AND NOT RainOk THEN
  wxWhy := UT_DEF_RAIN_LOST;
ELSIF Data.set.useSoil AND soilLost THEN
  wxWhy := UT_DEF_SOIL_LOST;
END_IF;
wx := wxWhy <> UT_DEF_NONE;
IF wx <> wxPrev THEN
  wxSince := tCur;
END_IF;
wxPrev := wx;
IF wx THEN
  IF (deferKept OR tCur - wxSince >= Data.set.onDelay) AND (NOT deferKept OR reasonKept <> wxWhy) THEN
    deferKept := TRUE;           (* RETAIN: written on change only *)
    reasonKept := wxWhy;
  END_IF;
ELSIF deferKept AND tCur - wxSince >= Data.set.clearDelay THEN
  deferKept := FALSE;
  reasonKept := UT_DEF_NONE;
END_IF;

IF NOT ok THEN
  Reason := UT_DEF_SETTING;      (* a bad setting at first boot: defer, the safe way *)
ELSIF Manual OR Data.set.manualDefer THEN
  Reason := UT_DEF_MANUAL;
ELSIF Remote THEN
  Reason := UT_DEF_REMOTE;
ELSIF deferKept THEN
  Reason := reasonKept;
ELSE
  Reason := UT_DEF_NONE;
END_IF;
Defer := Reason <> UT_DEF_NONE;
ToStorage := Defer AND Data.set.storage;
Warning := wxWhy = UT_DEF_RAIN_LOST OR wxWhy = UT_DEF_SOIL_LOST;
IF NOT ok THEN
  Data.det.timeLeft := T#0s;
ELSIF wx AND NOT deferKept THEN
  Data.det.timeLeft := Data.set.onDelay - (tCur - wxSince);
ELSIF deferKept AND NOT wx THEN
  Data.det.timeLeft := Data.set.clearDelay - (tCur - wxSince);
ELSE
  Data.det.timeLeft := T#0s;
END_IF;

stF := UT_F_NONE;
CASE Reason OF
UT_DEF_SETTING:
  stCode := UT_ST_CONFIG;
  stF := cfgId;
UT_DEF_MANUAL: stCode := UT_ST_DEFER_MANUAL;
UT_DEF_REMOTE: stCode := UT_ST_DEFER_REMOTE;
UT_DEF_NONE: stCode := UT_ST_OK;
ELSE
  IF NOT wx THEN
    stCode := UT_ST_DEFER_CLEARING;
  ELSIF reasonKept = UT_DEF_RAIN THEN
    stCode := UT_ST_DEFER_RAIN;
  ELSIF reasonKept = UT_DEF_SOIL THEN
    stCode := UT_ST_DEFER_SOIL;
  ELSE
    stCode := UT_ST_DEFER_SENSOR;
  END_IF;
END_CASE;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := NOT ok, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);
Data.sts.deferred := Defer;
Data.sts.reason := Reason;

END_FUNCTION_BLOCK