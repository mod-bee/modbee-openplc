(* FB_RunHours — a run-hour and start meter with a service interval, for anything that runs (a blower, a heater, a
drive not driven through FB_Motor). Hours are counted exactly (whole milliseconds, the rest
carried: F_HoursAdd) into the lifetime and since-service totals, kept hourly and at each stop.
Pins: bRunning, bResetService (the service is done) -> fHours (lifetime), bServiceDue, plus FB_Object's outputs.
bServiceDue (a warning, ServiceDue) when the hours since the last service reach set.fServiceInterval (0 = off).
bCmdPreset sets the lifetime hours (a replacement). No day totals: the board has no clock; SCADA makes days.
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_RunHours EXTENDS FB_Object
  VAR_INPUT
    bRunning : BOOL;
    bResetService : BOOL R_EDGE;
    refData : REFERENCE TO ST_RunHoursData;
  END_VAR
  VAR_OUTPUT
    fHours : LREAL;
    bServiceDue : BOOL;
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
  IF NOT (refData.set.fServiceInterval >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fServiceInterval <= LREAL#1.0E7) THEN
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
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

(* count *)
nMs := F_HoursAdd(bRunning := bRunning, tNow := tNow, stAcc := stAcc);
refData.tot.nTotalMs := refData.tot.nTotalMs + nMs;
refData.tot.nServiceMs := refData.tot.nServiceMs + nMs;
IF bRunning AND NOT bRunPrev THEN
  tRunAt := tNow;
  refData.tot.nStarts := refData.tot.nStarts + 1;
END_IF;
IF bRunning THEN
  refData.tCurrentRun := tNow - tRunAt;
ELSIF bRunPrev THEN
  refData.sts.tLastRun := tNow - tRunAt;
  refData.tCurrentRun := T#0s;
END_IF;

(* commands *)
IF bResetService OR refData.bCmdResetService THEN
  refData.bCmdResetService := FALSE;
  refData.tot.nServiceMs := 0;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
  stKeptTot := refData.tot;
END_IF;
IF refData.bCmdPreset THEN
  refData.bCmdPreset := FALSE;
  IF refData.fPresetHours >= 0.0 AND refData.fPresetHours <= LREAL#1.0E7 THEN
    refData.tot.nTotalMs := LREAL_TO_LINT(refData.fPresetHours * 3600000.0);
    stKeptTot := refData.tot;
  END_IF;
END_IF;
IF (bRunPrev AND NOT bRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;       (* kept hourly and at each stop *)
  tKeptAt := tNow;
END_IF;
bRunPrev := bRunning;

(* status *)
fHours := LINT_TO_LREAL(refData.tot.nTotalMs) / 3600000.0;
refData.sts.fHours := fHours;
refData.sts.fServiceHours := LINT_TO_LREAL(refData.tot.nServiceMs) / 3600000.0;
IF refData.set.fServiceInterval > 0.0 THEN
  refData.sts.fServiceLeft := MAX(0.0, refData.set.fServiceInterval - refData.sts.fServiceHours);
  bServiceDue := refData.sts.fServiceHours >= refData.set.fServiceInterval;
ELSE
  refData.sts.fServiceLeft := 0.0;
  bServiceDue := FALSE;
END_IF;
refData.sts.bServiceDue := bServiceDue;
bError := FALSE;
bWarning := bServiceDue OR refData.sts.bRefused;
IF bServiceDue THEN
  eErrorId := E_UtError.ServiceDue;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bRunning THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK