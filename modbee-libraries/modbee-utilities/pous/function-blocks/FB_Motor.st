(* FB_Motor — a direct-on-line motor or a run relay.

Pins: bFeedback (run feedback contact), bOverload (TRUE = overload relay tripped) -> bQ (run output),
bHoldOff (TRUE while the overload, or a part tripped as Thermistor, is tripped: wire it to the IO map's hold-off,
so a commissioning force can run the motor in Off, but never past a tripped overload or thermistor), plus FB_Equipment's bInterlock,
bPermissive, ipSystem and FB_Object's bError / bWarning / eErrorId / eState. refData: the motor's record.
Built in: overload, no feedback (never came after a start), feedback lost (went while running), stuck
(stays after a stop); run hours and starts. Everything else is a part placed beside it (FB_Protection for a
thermistor / drive fault / external fault, FB_LocalControl for Hand buttons and HOA, ...).
Detail (det): tRestartIn, tRunTime (this run), tIdleTime (since the last stop, 0 while running), tHandLeft (a
Hand run's time left under set.tHandMax, 0 = none counting).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Motor EXTENDS FB_Equipment IMPLEMENTS I_Motor
  VAR_INPUT
    bFeedback : BOOL; (* run feedback contact *)
    bOverload : BOOL; (* TRUE = the overload relay has tripped *)
    refData : REFERENCE TO ST_MotorData;
  END_VAR
  VAR_OUTPUT
    bQ : BOOL; (* run output *)
    bHoldOff : BOOL; (* TRUE: the overload or the thermistor is tripped: hold the output off, even forced *)
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
  bQ := bRun;
  bHoldOff := stWOverload.bTrip OR bPartHoldOff;
END_METHOD

METHOD PROTECTED FeedbackOk : BOOL
  (* owners call this (through bIsRunning) maybe before the motor's first scan: refData may not be bound yet *)
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF refData.set.bUseFeedback THEN
    FeedbackOk := bFeedback;
  ELSE
    FeedbackOk := bQ;
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
  ShapeRun := bWant AND (bQ OR NOT bDriveHold);
END_METHOD

PROPERTY PUBLIC fActSpeed : REAL
  GET
    IF bQ THEN fActSpeed := 100.0; ELSE fActSpeed := 0.0; END_IF;
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
  ProtOk := stP.tDelay >= T#0s AND stP.tRecover >= T#0s AND stP.nMaxRetries >= 0;
END_METHOD

(* the settings as a whole are usable *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tRestartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ProtOk(stP := refData.set.stOverload)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stNoFeedback)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stFeedbackLost)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := refData.set.stStuck)) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bQ := FALSE;
  bHoldOff := TRUE;
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
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);

(* own protections *)
IF bQ AND bFeedback THEN
  bFbSeen := TRUE;
END_IF;
IF NOT bQ THEN
  bFbSeen := FALSE;
END_IF;
bTrip := F_Protect(tNow := tNow, bCause := bOverload, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stOverload, stSts := refData.sts.stOverload, stWork := stWOverload);
bTrip := F_Protect(tNow := tNow, bCause := refData.set.bUseFeedback AND bQ AND NOT bFbSeen AND NOT bFeedback,
                   bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stNoFeedback, stSts := refData.sts.stNoFeedback, stWork := stWNoFeedback);
bTrip := F_Protect(tNow := tNow, bCause := refData.set.bUseFeedback AND bQ AND bFbSeen AND NOT bFeedback,
                   bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stFeedbackLost, stSts := refData.sts.stFeedbackLost, stWork := stWFeedbackLost);
bTrip := F_Protect(tNow := tNow, bCause := refData.set.bUseFeedback AND NOT bQ AND bFeedback,
                   bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stStuck, stSts := refData.sts.stStuck, stWork := stWStuck);
bTrip := stWOverload.bTrip OR stWNoFeedback.bTrip OR stWFeedbackLost.bTrip OR stWStuck.bTrip;
bWarn := stWOverload.bWarn OR stWNoFeedback.bWarn OR stWFeedbackLost.bWarn OR stWStuck.bWarn;
eOwn := E_UtError.None;
IF stWOverload.bTrip OR stWOverload.bWarn THEN
  eOwn := E_UtError.Overload;
ELSIF stWNoFeedback.bTrip OR stWNoFeedback.bWarn THEN
  eOwn := E_UtError.NoFeedback;
ELSIF stWFeedbackLost.bTrip OR stWFeedbackLost.bWarn THEN
  eOwn := E_UtError.FeedbackLost;
ELSIF stWStuck.bTrip OR stWStuck.bWarn THEN
  eOwn := E_UtError.Stuck;
END_IF;
IF stWOverload.bBadSetting OR stWNoFeedback.bBadSetting OR stWFeedbackLost.bBadSetting OR stWStuck.bBadSetting THEN
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
       tRestartDelay := refData.set.tRestartDelay);

(* totals and live detail *)
IF bQ AND NOT bQPrev THEN
  refData.tot.nStarts := refData.tot.nStarts + 1;
  tRunStart := tNow;
  tLastHours := tNow;
END_IF;
IF bQ THEN
  refData.tot.fRunHours := refData.tot.fRunHours + TIME_TO_LREAL(tNow - tLastHours) / 3600000.0;
  tLastHours := tNow;
  refData.det.tRunTime := tNow - tRunStart;
END_IF;
IF refData.bCmdPreset THEN
  refData.tot.fRunHours := refData.fPresetHours;
  refData.tot.nStarts := refData.nPresetStarts;
  stKeptTot := refData.tot;
  refData.bCmdPreset := FALSE;
END_IF;
IF (bQPrev AND NOT bQ) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;       // totals kept hourly and at each stop
  tKeptAt := tNow;
END_IF;
bQPrev := bQ;
IF NOT bQ AND tNow - tStoppedAt < refData.set.tRestartDelay THEN
  refData.det.tRestartIn := refData.set.tRestartDelay - (tNow - tStoppedAt);
ELSE
  refData.det.tRestartIn := T#0s;
END_IF;
refData.det.tIdleTime := tIdleNow;
refData.det.tHandLeft := tHandLeftNow;

END_FUNCTION_BLOCK