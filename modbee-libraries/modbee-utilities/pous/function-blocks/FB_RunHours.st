(* FB_RunHours — a run-hour and start meter with a service interval, for anything that runs (a blower, a heater, a
drive not driven through FB_Motor). Hours are counted in whole milliseconds (the rest
carried: F_HoursAdd) into the lifetime and since-service totals (LREAL hours, as FB_Motor), kept hourly and at each stop.
Pins: bRunning, bServiceDone (the service is done) -> fRunHours (lifetime), bServiceDue, plus FB_Object's outputs.
bServiceDue (a warning, ServiceDue) when the hours since the last service reach set.fServiceIntervalHours (0 = off).
bCmdPresetHours sets the lifetime hours (a replacement). No day totals: the board has no clock; SCADA makes days.
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_RunHours EXTENDS FB_Object
  VAR_INPUT
    bRunning : BOOL; (* it runs *)
    bServiceDone : BOOL R_EDGE; (* rising edge: the service is done *)
    refData : REFERENCE TO ST_RunHoursData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fRunHours : LREAL; (* run hours, lifetime *)
    bServiceDue : BOOL; (* the service is due (a warning) *)
  END_VAR
  VAR RETAIN
    stKept : ST_RunHoursSet;
    stKeptTot : ST_RunHoursTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stAcc : ST_HoursAcc;
    bRunPrev : BOOL;
    tRunAt : TIME;
    tKeptAt : TIME;
  END_VAR
  VAR_TEMP
    nMs : LINT;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.fServiceIntervalHours >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fServiceIntervalHours <= LREAL#1.0E7) THEN
    SetWhy := E_UtError.AboveMax;
  END_IF;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
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
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;

(* count *)
nMs := F_HoursAdd(bRunning := bRunning, tNow := tNow, stAccumulator := stAcc);
refData.tot.fRunHours := refData.tot.fRunHours + LINT_TO_LREAL(nMs) / 3600000.0;
refData.tot.fRunHoursSinceService := refData.tot.fRunHoursSinceService + LINT_TO_LREAL(nMs) / 3600000.0;
IF bRunning AND NOT bRunPrev THEN
  tRunAt := tNow;
  refData.tot.nStartCount := refData.tot.nStartCount + 1;
END_IF;
IF bRunning THEN
  refData.tThisRunTime := tNow - tRunAt;
ELSIF bRunPrev THEN
  refData.sts.tLastRunTime := tNow - tRunAt;
  refData.tThisRunTime := T#0s;
END_IF;

(* commands *)
IF bServiceDone OR refData.bCmdServiceDone THEN
  refData.bCmdServiceDone := FALSE;
  refData.tot.fRunHoursSinceService := 0.0;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
  stKeptTot := refData.tot;
END_IF;
IF refData.bCmdPresetHours THEN
  refData.bCmdPresetHours := FALSE;
  IF refData.fPresetRunHours >= 0.0 AND refData.fPresetRunHours <= LREAL#1.0E7 THEN
    refData.tot.fRunHours := refData.fPresetRunHours;
    stKeptTot := refData.tot;
  END_IF;
END_IF;
IF (bRunPrev AND NOT bRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;       (* kept hourly and at each stop *)
  tKeptAt := tNow;
END_IF;
bRunPrev := bRunning;

(* status *)
fRunHours := refData.tot.fRunHours;
refData.sts.fRunHours := fRunHours;
refData.sts.fHoursSinceService := refData.tot.fRunHoursSinceService;
IF refData.set.fServiceIntervalHours > 0.0 THEN
  refData.sts.fHoursToService := MAX(0.0, refData.set.fServiceIntervalHours - refData.sts.fHoursSinceService);
  bServiceDue := refData.sts.fHoursSinceService >= refData.set.fServiceIntervalHours;
ELSE
  refData.sts.fHoursToService := 0.0;
  bServiceDue := FALSE;
END_IF;
refData.sts.bServiceDue := bServiceDue;
bError := FALSE;
bWarning := bServiceDue OR refData.sts.bSettingRefused;
IF bServiceDue THEN
  eErrorId := E_UtError.ServiceDue;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bRunning THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK