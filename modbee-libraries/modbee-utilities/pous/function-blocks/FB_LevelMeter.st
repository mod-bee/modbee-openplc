(* FB_LevelMeter — the volume a pump moves, worked out from the tank's level.

Pins: ipLevel (the tank: a vessel gives its volume, any other measurement its value), bPumpRunning (the pump
runs: only then is anything counted), ipOtherMeter (optional: a meter on the tank's other inflow or outflow during the
run, whose rise is added), refData.
set.bCountLevelFall (a pump emptying the tank) counts the level's fall, else its rise. During a run the moved volume
is the change since the run's start plus ipOtherMeter's rise; the total grows only when that passes its highest value
so far by set.fMinRiseToCount (a high-water mark): level noise and waves are never counted twice. A bad level counts
nothing (the mark is held). Offers I_Meter (an I_Measurement too: its rate): the total and the rate (per hour, over set.tRateWindow). *)

FUNCTION_BLOCK FB_LevelMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    ipLevel : I_Measurement; (* required *)
    bPumpRunning : BOOL; (* the pump runs: only then is anything counted *)
    ipOtherMeter : I_Meter; (* a meter on the tank's other inflow or outflow during the run, whose rise is added (optional) *)
    refData : REFERENCE TO ST_LevelMeterData; (* the block's record *)
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
    bRunEnded : BOOL; (* bPumpRunning fell this scan (the totals are kept) *)
    ipVessel : I_Vessel;
    fV : LREAL;
    fMoved : LREAL;
    bGood : BOOL;
    tWin : TIME;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.fMinRiseToCount >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.tRateWindow > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

PROPERTY PUBLIC fActTotal : LREAL    // the lifetime total in its unit
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActFlowPerHour : REAL    // the rate, per hour
  GET
    IF __ISVALIDREF(refData) THEN fActFlowPerHour := refData.sts.fFlowPerHour; ELSE fActFlowPerHour := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), unit None (the vessel's volume unit is not known here), no bands *)
PROPERTY PUBLIC fActValue : REAL    // the value now (the total, in its unit)
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fFlowPerHour; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a value is available (fitted and read at least once)
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // fitted on this site
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
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

(* the level as a volume when it is a vessel *)
bGood := ipLevel.bIsFitted AND ipLevel.bHasValue AND ipLevel.bIsGood;
IF __QUERYINTERFACE(ipLevel, ipVessel) THEN
  fV := REAL_TO_LREAL(ipVessel.fActVolume);
ELSE
  fV := REAL_TO_LREAL(ipLevel.fActValue);
END_IF;

IF bPumpRunning AND NOT bActivePrev THEN
  bRefValid := FALSE;             // a new run
  fMark := 0.0;
  refData.sts.fDeliveredThisRun := 0.0;
END_IF;
bRunEnded := bActivePrev AND NOT bPumpRunning;
bActivePrev := bPumpRunning;
IF bPumpRunning AND bGood THEN
  IF NOT bRefValid THEN
    fRef := fV;
    IF ipOtherMeter <> NULL THEN fAddRef := ipOtherMeter.fActTotal; ELSE fAddRef := 0.0; END_IF;
    bRefValid := TRUE;
  END_IF;
  IF refData.set.bCountLevelFall THEN
    fMoved := fRef - fV;
  ELSE
    fMoved := fV - fRef;
  END_IF;
  IF ipOtherMeter <> NULL THEN
    fMoved := fMoved + (ipOtherMeter.fActTotal - fAddRef);
  END_IF;
  IF fMoved > fMark + REAL_TO_LREAL(refData.set.fMinRiseToCount) THEN
    refData.tot.fTotal := refData.tot.fTotal + (fMoved - fMark);
    fMark := fMoved;
    refData.sts.fDeliveredThisRun := fMark;
  END_IF;
END_IF;
refData.sts.bGood := bGood;

(* rate over the window *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fFlowPerHour := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

IF refData.bCmdResetTotals THEN
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
  refData.bCmdResetTotals := FALSE;
END_IF;
IF bRunEnded OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF NOT bGood THEN
  eState := E_State.Fault;
ELSIF bPumpRunning THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK