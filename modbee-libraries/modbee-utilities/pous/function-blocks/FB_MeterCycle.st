(* FB_MeterCycle — this cycle's and the last cycle's quantity on any meter (a pump run, a fill, an irrigation): an
observer that reads its meter and changes nothing.

Pins: bCloseCycle (rising edge: closes the cycle, e.g. the pump's start command), ipMeter (required), bPumpRunning
(optional: the pump runs; its fall keeps the totals), dtLocalTime (optional), refData -> FB_Object's outputs.
tot.fThisCycle counts every rise of the meter's total since the last rollover (a fall, e.g. the meter's total reset,
is not counted). A rollover (bCloseCycle or the record's bCmdCloseCycle) moves tot.fThisCycle to tot.fLastCycle and starts the
next cycle from zero, counts it (tot.nCycleCount) and stamps it (tot.dtLastCycleEnd from dtLocalTime: blank when unwired, the
boards have no real-time clock). A rollover from a timer (every 15 min ...) gives interval quantities. tot is kept
over a power cut: at each rollover, when bPumpRunning falls and hourly. *)

FUNCTION_BLOCK FB_MeterCycle EXTENDS FB_Object
  VAR_INPUT
    bCloseCycle : BOOL := FALSE; (* rising edge: close the cycle *)
    ipMeter : I_Meter; (* required *)
    bPumpRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    dtLocalTime : DT; (* optional: the local time, for tot.dtLastCycleEnd *)
    refData : REFERENCE TO ST_MeterCycleData; (* the block's record *)
  END_VAR
  VAR RETAIN
    stKeptTot : ST_MeterCycleTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
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
  bRolloverPrev := bCloseCycle;     // a rollover held at power-up is not a new cycle
  bRunningWas := bPumpRunning;
  tKeptAt := tNow;
  bFirstScan := FALSE;
END_IF;

(* count the meter's rises *)
IF fTotal > fLastTotal THEN
  refData.tot.fThisCycle := refData.tot.fThisCycle + (fTotal - fLastTotal);
END_IF;
fLastTotal := fTotal;

(* the rollover *)
IF (bCloseCycle AND NOT bRolloverPrev) OR refData.bCmdCloseCycle THEN
  refData.tot.fLastCycle := refData.tot.fThisCycle;
  refData.tot.fThisCycle := 0.0;
  refData.tot.nCycleCount := refData.tot.nCycleCount + 1;
  refData.tot.dtLastCycleEnd := dtLocalTime;
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRolloverPrev := bCloseCycle;
refData.bCmdCloseCycle := FALSE;

(* keep *)
IF (bRunningWas AND NOT bPumpRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bPumpRunning;

bError := FALSE;
bWarning := FALSE;
eErrorId := E_UtError.None;
eState := E_State.Running;

END_FUNCTION_BLOCK