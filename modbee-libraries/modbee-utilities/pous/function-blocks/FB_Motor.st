(* FB_Motor — a direct-on-line motor or a run relay.

Pins: bRunFeedback (run feedback contact), bOverloadTripped (TRUE = overload relay tripped) -> bRunOutput (run output),
bHoldOutputOff (TRUE while the overload, or a part tripped as Thermistor, is tripped: wire it to the IO map's hold-off,
so a commissioning force can run the motor in Off, but never past a tripped overload or thermistor), plus FB_Equipment's bInterlock,
bPermissive, ipSystem and FB_Object's bError / bWarning / eErrorId / eState. refData: the motor's record.
Built in: overload, no feedback (never came after a start), feedback lost (went while running), stuck
(stays after a stop); run hours and starts. Everything else is a part placed beside it (FB_Protection for a
thermistor / drive fault / external fault, FB_LocalControl for Hand buttons and HOA, ...).
Detail (det): tMinOffTimeLeft, tThisRunTime (this run), tIdleTime (since the last stop, 0 while running), tHandTimeLeft (a
Hand run's time left under set.tMaxHandRunTime, 0 = none counting).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Motor EXTENDS FB_Equipment IMPLEMENTS I_Motor
  VAR_INPUT
    bRunFeedback : BOOL; (* run feedback contact *)
    bOverloadTripped : BOOL; (* TRUE = the overload relay has tripped *)
    refData : REFERENCE TO ST_MotorData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bRunOutput : BOOL; (* run output *)
    bHoldOutputOff : BOOL; (* TRUE: the overload or the thermistor is tripped: hold the output off, even forced *)
  END_VAR
  VAR RETAIN
    stKept : ST_MotorSet; (* last good settings *)
    nKeptLayout : UINT; (* their layout version *)
    stKeptTot : ST_MotorTot; (* totals, kept hourly and at each stop *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stWOverload : ST_ProtectionWork;
    stWNoFeedback : ST_ProtectionWork;
    stWFeedbackLost : ST_ProtectionWork;
    stWStuck : ST_ProtectionWork;
    bFbSeen : BOOL; (* feedback came during this run *)
    bQPrev : BOOL;
    tRunStart : TIME;
    tLastHours : TIME;
    tKeptAt : TIME;
    bDriveHold : BOOL; (* a variant's check holds a new start *)
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bTrip : BOOL;
    bWarn : BOOL;
    eOwn : E_UtError;
    bDTrip : BOOL;
    bDWarn : BOOL;
    bDHold : BOOL;
    eDrive : E_UtError;
  END_VAR


METHOD PROTECTED Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  bRunOutput := bRun;
  bHoldOutputOff := stWOverload.bTripping OR bPartHoldOff;
END_METHOD

METHOD PROTECTED FeedbackOk : BOOL
  (* owners call this (through bIsRunning) maybe before the motor's first scan: refData may not be bound yet *)
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF refData.set.bRunFeedbackFitted THEN
    FeedbackOk := bRunFeedback;
  ELSE
    FeedbackOk := bRunOutput;
  END_IF;
END_METHOD

(* a variant's hold (a drive not ready) blocks a new start *)
METHOD PROTECTED OVERRIDE RunHours : REAL
  IF __ISVALIDREF(refData) THEN
    RunHours := LREAL_TO_REAL(refData.tot.fRunHours);
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  ShapeRun := bWant AND (bRunOutput OR NOT bDriveHold);
END_METHOD

PROPERTY PUBLIC fActSpeedPct : REAL    // the speed now, % (0 when stopped)
  GET
    IF bRunOutput THEN fActSpeedPct := 100.0; ELSE fActSpeedPct := 0.0; END_IF;
  END_GET
END_PROPERTY

(* the variants' own checks (a drive's ready relay, speed deviation ...), added to the motor's protections in
   the same scan. Default: none. bHold: no new start (not a fault). *)
METHOD PROTECTED DriveChecks
  VAR_INPUT
    bReset : BOOL;
  END_VAR
  VAR_OUTPUT
    bTrip : BOOL;
    bWarn : BOOL;
    bHold : BOOL;
    eError : E_UtError;
  END_VAR
  bTrip := FALSE;
  bWarn := FALSE;
  bHold := FALSE;
  eError := E_UtError.None;
END_METHOD

(* a protection's settings are usable *)
METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tTripDelay >= T#0s AND stP.tAutoRecoverAfter >= T#0s AND stP.nMaxRetriesBeforeLockout >= 0;
END_METHOD

(* the settings as a whole are usable *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tMinOffTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ProtOk(stP := refData.set.stOverloadFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stNoRunFeedbackFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stRunFeedbackLostFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stStuckOnFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bRunOutput := FALSE;
  bHoldOutputOff := TRUE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;

(* kept settings: restored at power-up, a bad write put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);

(* own protections *)
IF bRunOutput AND bRunFeedback THEN
  bFbSeen := TRUE;
END_IF;
IF NOT bRunOutput THEN
  bFbSeen := FALSE;
END_IF;
bTrip := F_Protect(tNow := tNow, bConditionPresent := bOverloadTripped, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stOverloadFault, stStatus := refData.sts.stOverloadFault, stWorking := stWOverload);
bTrip := F_Protect(tNow := tNow, bConditionPresent := refData.set.bRunFeedbackFitted AND bRunOutput AND NOT bFbSeen AND NOT bRunFeedback,
                   bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stNoRunFeedbackFault, stStatus := refData.sts.stNoRunFeedbackFault, stWorking := stWNoFeedback);
bTrip := F_Protect(tNow := tNow, bConditionPresent := refData.set.bRunFeedbackFitted AND bRunOutput AND bFbSeen AND NOT bRunFeedback,
                   bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stRunFeedbackLostFault, stStatus := refData.sts.stRunFeedbackLostFault, stWorking := stWFeedbackLost);
bTrip := F_Protect(tNow := tNow, bConditionPresent := refData.set.bRunFeedbackFitted AND NOT bRunOutput AND bRunFeedback,
                   bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stStuckOnFault, stStatus := refData.sts.stStuckOnFault, stWorking := stWStuck);
bTrip := stWOverload.bTripping OR stWNoFeedback.bTripping OR stWFeedbackLost.bTripping OR stWStuck.bTripping;
bWarn := stWOverload.bWarning OR stWNoFeedback.bWarning OR stWFeedbackLost.bWarning OR stWStuck.bWarning;
eOwn := E_UtError.None;
IF stWOverload.bTripping OR stWOverload.bWarning THEN
  eOwn := E_UtError.Overload;
ELSIF stWNoFeedback.bTripping OR stWNoFeedback.bWarning THEN
  eOwn := E_UtError.NoFeedback;
ELSIF stWFeedbackLost.bTripping OR stWFeedbackLost.bWarning THEN
  eOwn := E_UtError.FeedbackLost;
ELSIF stWStuck.bTripping OR stWStuck.bWarning THEN
  eOwn := E_UtError.Stuck;
END_IF;
IF stWOverload.bSettingBad OR stWNoFeedback.bSettingBad OR stWFeedbackLost.bSettingBad OR stWStuck.bSettingBad THEN
  bWarn := TRUE;
  IF eOwn = E_UtError.None THEN eOwn := E_UtError.BadSetting; END_IF;
END_IF;

DriveChecks(bReset := bReset, bTrip => bDTrip, bWarn => bDWarn, bHold => bDHold, eError => eDrive);
IF (bDTrip OR bDWarn) AND eOwn = E_UtError.None THEN
  eOwn := eDrive;
END_IF;
bTrip := bTrip OR bDTrip;
bWarn := bWarn OR bDWarn;
bDriveHold := bDHold;

Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset,
       tRestartDelay := refData.set.tMinOffTime);

(* totals and live detail *)
IF bRunOutput AND NOT bQPrev THEN
  refData.tot.nStartCount := refData.tot.nStartCount + 1;
  tRunStart := tNow;
  tLastHours := tNow;
END_IF;
IF bRunOutput THEN
  refData.tot.fRunHours := refData.tot.fRunHours + TIME_TO_LREAL(tNow - tLastHours) / 3600000.0;
  tLastHours := tNow;
  refData.det.tThisRunTime := tNow - tRunStart;
END_IF;
IF refData.bCmdPresetTotals THEN
  refData.tot.fRunHours := refData.fPresetRunHours;
  refData.tot.nStartCount := refData.nPresetStartCount;
  stKeptTot := refData.tot;
  refData.bCmdPresetTotals := FALSE;
END_IF;
IF (bQPrev AND NOT bRunOutput) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;       // totals kept hourly and at each stop
  tKeptAt := tNow;
END_IF;
bQPrev := bRunOutput;
IF NOT bRunOutput AND tNow - tStoppedAt < refData.set.tMinOffTime THEN
  refData.det.tMinOffTimeLeft := refData.set.tMinOffTime - (tNow - tStoppedAt);
ELSE
  refData.det.tMinOffTimeLeft := T#0s;
END_IF;
refData.det.tIdleTime := tIdleNow;
refData.det.tHandTimeLeft := tHandLeftNow;

END_FUNCTION_BLOCK