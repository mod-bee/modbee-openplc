(* FB_MeterSelect — one meter from two sources, chosen at run time (a site setting): e.g. a pulse flow meter or the
tank level's meter. It is a meter itself (I_Meter, so an I_Measurement too): wire it where one meter goes
(FB_RunVolume, FB_RunLog, FB_MeterCycle, FB_LevelCheck).

Pins: bUseMeterB (FALSE: meter A, TRUE: meter B), ipMeterA, ipMeterB (each a meter block: FB_PulseMeter,
FB_RegisterMeter, FB_FlowTotal, FB_LevelMeter), bPumpRunning (optional: the pump runs; its fall keeps the total),
refData.
tot.fTotal counts every rise of the source in use (a fall, e.g. that meter's total reset, is not counted), so it
carries on smoothly when the source changes: the other meter's own total never jumps into it. The rate, good and
the unit are the source in use's. The source in use not wired: no count, not good, error NoMeasurement.
bCmdResetTotals sets the total back to 0. tot is kept over a power cut: when the source changes, when bPumpRunning
falls, on a reset and hourly. *)

FUNCTION_BLOCK FB_MeterSelect EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    bUseMeterB : BOOL := FALSE; (* FALSE: meter A, TRUE: meter B *)
    ipMeterA : I_Meter; (* meter A *)
    ipMeterB : I_Meter; (* meter B *)
    bPumpRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the total *)
    refData : REFERENCE TO ST_MeterSelectData; (* the block's record *)
  END_VAR
  VAR RETAIN
    stKeptTot : ST_MeterSelectTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipUse : I_Meter; (* the source in use *)
    fLastA : LREAL; (* each meter's total last scan *)
    fLastB : LREAL;
    bUseBWas : BOOL;
    bRunningWas : BOOL;
    tKeptAt : TIME;
  END_VAR
  VAR_TEMP
    fA : LREAL;
    fB : LREAL;
  END_VAR


PROPERTY PUBLIC fActTotal : LREAL    // the total in its unit
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActFlowPerHour : REAL    // the flow per hour of the meter in use
  GET
    IF __ISVALIDREF(refData) THEN fActFlowPerHour := refData.sts.fFlowPerHour; ELSE fActFlowPerHour := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the meter in use can be trusted
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in the source in use's unit, no bands *)
PROPERTY PUBLIC fActValue : REAL    // the value now (the total)
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fFlowPerHour; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a value is available
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
    IF ipUse <> NULL THEN eUnit := ipUse.eUnit; END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
fA := 0.0;
fB := 0.0;
IF ipMeterA <> NULL THEN fA := ipMeterA.fActTotal; END_IF;
IF ipMeterB <> NULL THEN fB := ipMeterB.fActTotal; END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.tot := stKeptTot;
  ELSE
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  fLastA := fA;
  fLastB := fB;
  bUseBWas := bUseMeterB;
  bRunningWas := bPumpRunning;
  tKeptAt := tNow;
  bFirstScan := FALSE;
END_IF;

(* the source in use: count its rises; the other one's change is never counted *)
IF bUseMeterB THEN ipUse := ipMeterB; ELSE ipUse := ipMeterA; END_IF;
IF ipUse <> NULL THEN
  IF bUseMeterB THEN
    IF fB > fLastB THEN refData.tot.fTotal := refData.tot.fTotal + (fB - fLastB); END_IF;
  ELSIF fA > fLastA THEN
    refData.tot.fTotal := refData.tot.fTotal + (fA - fLastA);
  END_IF;
  refData.sts.bGood := ipUse.bIsGood;
  refData.sts.fFlowPerHour := ipUse.fActFlowPerHour;
ELSE
  refData.sts.bGood := FALSE;
  refData.sts.fFlowPerHour := 0.0;
END_IF;
fLastA := fA;
fLastB := fB;
refData.sts.bUsingMeterB := bUseMeterB;

(* reset, keep *)
IF refData.bCmdResetTotals THEN
  refData.tot.fTotal := 0.0;
  refData.bCmdResetTotals := FALSE;
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
IF bUseMeterB <> bUseBWas OR (bRunningWas AND NOT bPumpRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bUseBWas := bUseMeterB;
bRunningWas := bPumpRunning;

bError := ipUse = NULL;
bWarning := ipUse <> NULL AND NOT refData.sts.bGood;
IF ipUse = NULL THEN
  eErrorId := E_UtError.NoMeasurement;
ELSIF NOT refData.sts.bGood THEN
  eErrorId := E_UtError.SensorBad;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN eState := E_State.Fault; ELSE eState := E_State.Running; END_IF;

END_FUNCTION_BLOCK