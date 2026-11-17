(* FB_LevelMeter — the volume a pump moves, worked out from the tank's level.

Pins: ipLevel (the tank: a vessel gives its volume, any other measurement its value), bActive (the pump
runs: only then is anything counted), ipAdd (optional: a meter on the tank's other inflow or outflow during the
run, whose rise is added), refData.
set.bCountFalls (a pump emptying the tank) counts the level's fall, else its rise. During a run the moved volume
is the change since the run's start plus ipAdd's rise; the total grows only when that passes its highest value
so far by set.fDeadband (a high-water mark): level noise and waves are never counted twice. A bad level counts
nothing (the mark is held). Offers I_Meter (an I_Measurement too: its rate): the total and the rate (per hour, over set.tRateWindow). *)

FUNCTION_BLOCK FB_LevelMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    ipLevel : I_Measurement; (* required *)
    bActive : BOOL;
    ipAdd : I_Meter;
    refData : REFERENCE TO ST_LevelMeterData;
  END_VAR
  VAR RETAIN
    stKept : ST_LevelMeterSet;
    nKeptLayout : UINT;
    stKeptTot : ST_LevelMeterTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bActivePrev : BOOL;
    bRefValid : BOOL;
    fRef : LREAL; (* the level volume at the run's start *)
    fAddRef : LREAL;
    fMark : LREAL; (* the highest volume moved so far in this run *)
    tKeptAt : TIME;
    tWindowAt : TIME;
    fWindowTotal : LREAL;
  END_VAR
  VAR_TEMP
    bRunEnded : BOOL; (* bActive fell this scan (the totals are kept) *)
    ipVessel : I_Vessel;
    fV : LREAL;
    fMoved : LREAL;
    bGood : BOOL;
    tWin : TIME;
  END_VAR


PROPERTY PUBLIC fActTotal : LREAL
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActRate : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActRate := refData.sts.fRate; ELSE fActRate := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), unit None (the vessel's volume unit is not known here), no bands *)
PROPERTY PUBLIC fActValue : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fRate; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipLevel = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tKeptAt := tNow;
  tWindowAt := tNow;
  fWindowTotal := refData.tot.fTotal;
ELSIF refData.set.fDeadband >= 0.0 AND refData.set.tRateWindow > T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

(* the level as a volume when it is a vessel *)
bGood := ipLevel.bIsFitted AND ipLevel.bHasValue AND ipLevel.bIsGood;
IF __QUERYINTERFACE(ipLevel, ipVessel) THEN
  fV := REAL_TO_LREAL(ipVessel.fActVolume);
ELSE
  fV := REAL_TO_LREAL(ipLevel.fActValue);
END_IF;

IF bActive AND NOT bActivePrev THEN
  bRefValid := FALSE;             // a new run
  fMark := 0.0;
  refData.sts.fRunMoved := 0.0;
END_IF;
bRunEnded := bActivePrev AND NOT bActive;
bActivePrev := bActive;
IF bActive AND bGood THEN
  IF NOT bRefValid THEN
    fRef := fV;
    IF ipAdd <> NULL THEN fAddRef := ipAdd.fActTotal; ELSE fAddRef := 0.0; END_IF;
    bRefValid := TRUE;
  END_IF;
  IF refData.set.bCountFalls THEN
    fMoved := fRef - fV;
  ELSE
    fMoved := fV - fRef;
  END_IF;
  IF ipAdd <> NULL THEN
    fMoved := fMoved + (ipAdd.fActTotal - fAddRef);
  END_IF;
  IF fMoved > fMark + REAL_TO_LREAL(refData.set.fDeadband) THEN
    refData.tot.fTotal := refData.tot.fTotal + (fMoved - fMark);
    fMark := fMoved;
    refData.sts.fRunMoved := fMark;
  END_IF;
END_IF;
refData.sts.bGood := bGood;

(* rate over the window *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fRate := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

IF refData.bCmdResetTotal THEN
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
  refData.bCmdResetTotal := FALSE;
END_IF;
IF bRunEnded OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

bError := FALSE;
bWarning := refData.sts.bRefused;
IF refData.sts.bRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF NOT bGood THEN
  eState := E_State.Fault;
ELSIF bActive THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK