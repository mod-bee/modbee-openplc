(* FB_MeterCycle — this cycle's and the last cycle's quantity on any meter (a pump run, a fill, an irrigation): an
observer that reads its meter and changes nothing.

Pins: bRollover (rising edge: closes the cycle, e.g. the pump's start command), ipMeter (required), bRunning
(optional: the pump runs; its fall keeps the totals), refData -> FB_Object's outputs.
tot.fThis counts every rise of the meter's total since the last rollover (a fall, e.g. the meter's total reset,
is not counted). A rollover (bRollover or the record's bCmdRollover) moves tot.fThis to tot.fLast and starts the
next cycle from zero. tot is kept over a power cut: at each rollover, when bRunning falls and hourly. *)

FUNCTION_BLOCK FB_MeterCycle EXTENDS FB_Object
  VAR_INPUT
    bRollover : BOOL := FALSE; (* rising edge: close the cycle *)
    ipMeter : I_Meter; (* required *)
    bRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    refData : REFERENCE TO ST_MeterCycleData;
  END_VAR
  VAR RETAIN
    stKeptTot : ST_MeterCycleTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fLastTotal : LREAL; (* the meter's total last scan *)
    bRolloverPrev : BOOL;
    bRunningWas : BOOL;
    tKeptAt : TIME;
  END_VAR
  VAR_TEMP
    fTotal : LREAL;
  END_VAR


IF ipMeter = NULL OR NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  IF ipMeter = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
fTotal := ipMeter.fActTotal;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.tot := stKeptTot;
  ELSE
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  fLastTotal := fTotal;
  bRolloverPrev := bRollover;     // a rollover held at power-up is not a new cycle
  bRunningWas := bRunning;
  tKeptAt := tNow;
  bFirstScan := FALSE;
END_IF;

(* count the meter's rises *)
IF fTotal > fLastTotal THEN
  refData.tot.fThis := refData.tot.fThis + (fTotal - fLastTotal);
END_IF;
fLastTotal := fTotal;

(* the rollover *)
IF (bRollover AND NOT bRolloverPrev) OR refData.bCmdRollover THEN
  refData.tot.fLast := refData.tot.fThis;
  refData.tot.fThis := 0.0;
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRolloverPrev := bRollover;
refData.bCmdRollover := FALSE;

(* keep *)
IF (bRunningWas AND NOT bRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bRunning;

bError := FALSE;
bWarning := FALSE;
eErrorId := E_UtError.None;
eState := E_State.Running;

END_FUNCTION_BLOCK