(* FB_Pump — one pump: its owner link, its run decision and the motor it drives.

Pins: ipMotor (the motor, required: an FB_Motor or a variant), plus FB_Equipment's bInterlock, bPermissive,
ipSystem and FB_Object's bError / bWarning / eErrorId / eState. refData: the pump's record. Owners (a level
control, a group, a run) drive it through I_Equipment.Request; others read it through its properties.
The pump has its own Off / Hand / Auto; the motor has its own too and follows the pump only
while the motor is in Auto: a motor in Hand bypasses the pump ("motor in Hand": not available to the owner).
set.bWarnNotAuto warns NotAuto while the pump or its motor is not in Auto (and the plant is).
Auto: the owner's request after set.tStartDelay (it must last that long), kept for set.tMinRun and until it has
been gone set.tStopDelay; after a stop, set.tMinOff (a power-up counts as a stop).
Built in: start fail (asked, motor ready, not running) and dropped (stopped by itself while asked: a warning
kept until reset, never holding the pump). The start mask (set.tStartMask after each start) is offered to
parts that mask at start (low pressure, no flow ...). A faulted motor is a warning on the pump.
Parts placed beside it: FB_LevelCheck (pressure, flow, dry run ...), FB_Protection (seal leak, external
fault, maximum run), FB_PumpPrime, FB_Starts (an idle pump's exercise is a part of its level control or group).
Detail (det): tRunTime (this run), tIdleTime (since the last stop, 0 while running: with tRunTime, the time in
the present phase), tTimeLeft (of the start delay, minimum run or stop delay now counting), tHandLeft (a Hand
run's time left under set.tHandMax, 0 = none counting).
set.eRole (duty, jockey, booster) and set.fCapacity
(flow at full speed) are read by stations and cascades through I_Pump. *)

FUNCTION_BLOCK FB_Pump EXTENDS FB_Equipment IMPLEMENTS I_Pump
  VAR_INPUT
    ipMotor : I_Motor; (* the motor it drives (required) *)
    refData : REFERENCE TO ST_PumpData;
  END_VAR
  VAR RETAIN
    stKept : ST_PumpSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stWStartFail : ST_ProtectionWork;
    stWDropped : ST_ProtectionWork;
    tWantSince : TIME;
    tGoneSince : TIME;
    bWantPrev : BOOL;
    tRunStart : TIME;
    bCmdPrev : BOOL;
    bMotorRan : BOOL; (* the motor ran during this run *)
    tLeft : TIME;
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bTrip : BOOL;
    bWarn : BOOL;
    eOwn : E_UtError;
  END_VAR


METHOD PROTECTED Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  IF ipMotor <> NULL THEN
    ipMotor.Request(bRun := bRun, bHold := FALSE, fSpeed := fSpeedReq, bUrgent := bUrgentReq);
  END_IF;
END_METHOD

METHOD PROTECTED FeedbackOk : BOOL
  IF ipMotor <> NULL THEN
    FeedbackOk := ipMotor.bIsRunning;
  ELSE
    FeedbackOk := FALSE;
  END_IF;
END_METHOD

(* Auto: start delay, minimum run, stop delay *)
PROPERTY PUBLIC eActRole : E_PumpRole
  GET
    eActRole := E_PumpRole.Duty;
    IF __ISVALIDREF(refData) THEN
      eActRole := refData.set.eRole;
    END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActCapacity : REAL
  GET
    fActCapacity := 0.0;
    IF __ISVALIDREF(refData) THEN
      fActCapacity := refData.set.fCapacity;
    END_IF;
  END_GET
END_PROPERTY

(* a pump is never out of service on its own: its motor is *)
METHOD PROTECTED OVERRIDE AllowOos : BOOL
  AllowOos := FALSE;
END_METHOD

METHOD PROTECTED OVERRIDE RunHours : REAL
  IF ipMotor <> NULL THEN
    RunHours := ipMotor.fActRunHours;
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  IF bWant AND NOT bWantPrev THEN tWantSince := tNow; END_IF;
  IF NOT bWant AND bWantPrev THEN tGoneSince := tNow; END_IF;
  bWantPrev := bWant;
  tLeft := T#0s;
  IF NOT bRunCmd THEN
    ShapeRun := bWant AND tNow - tWantSince >= refData.set.tStartDelay;
    IF bWant AND NOT ShapeRun THEN
      tLeft := refData.set.tStartDelay - (tNow - tWantSince);
    END_IF;
  ELSIF bWant THEN
    ShapeRun := TRUE;
  ELSIF tNow - tRunStart < refData.set.tMinRun THEN
    ShapeRun := TRUE;
    tLeft := refData.set.tMinRun - (tNow - tRunStart);
  ELSIF tNow - tGoneSince < refData.set.tStopDelay THEN
    ShapeRun := TRUE;
    tLeft := refData.set.tStopDelay - (tNow - tGoneSince);
  ELSE
    ShapeRun := FALSE;
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE PartMasked : BOOL
  PartMasked := bRunCmd AND tNow - tRunStart < refData.set.tStartMask;
END_METHOD

(* the NotAuto warning: the pump or its motor not in Auto (a motor left in Hand after a test) *)
METHOD PROTECTED OVERRIDE NotAuto : BOOL
  VAR_INPUT
    eMode : E_Mode;
  END_VAR
  NotAuto := eMode <> E_Mode.Auto;
  IF ipMotor <> NULL THEN
    NotAuto := NotAuto OR ipMotor.eActMode <> E_Mode.Auto;
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE Unavailable : BOOL
  IF ipMotor <> NULL THEN
    Unavailable := ipMotor.eActMode = E_Mode.Hand OR ipMotor.bIsFaulted OR NOT ipMotor.bIsAvailable;
  ELSE
    Unavailable := TRUE;
  END_IF;
END_METHOD

PROPERTY PUBLIC fActSpeed : REAL
  GET
    IF ipMotor <> NULL THEN fActSpeed := ipMotor.fActSpeed; ELSE fActSpeed := 0.0; END_IF;
  END_GET
END_PROPERTY

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tMinOff >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tStartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tStopDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMinRun >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tStartMask >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.stStartFail.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stStartFail.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stDropped.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stDropped.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fCapacity >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fCapacity <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.eRole = E_PumpRole.Duty OR refData.set.eRole = E_PumpRole.Jockey
             OR refData.set.eRole = E_PumpRole.Booster) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipMotor = NULL THEN
  bError := TRUE;
  IF ipMotor = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;

IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
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
IF bRunCmd AND NOT bCmdPrev THEN
  tRunStart := tNow;
  bMotorRan := FALSE;
END_IF;
IF ipMotor.bIsRunning THEN
  bMotorRan := TRUE;
END_IF;
bTrip := F_Protect(tNow := tNow, bCause := bRunCmd AND ipMotor.bIsAvailable AND NOT ipMotor.bIsRunning AND NOT bMotorRan,
                   bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stStartFail, stSts := refData.sts.stStartFail, stWork := stWStartFail);
bTrip := F_Protect(tNow := tNow, bCause := bRunCmd AND bMotorRan AND NOT ipMotor.bIsRunning,
                   bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                   stSet := refData.set.stDropped, stSts := refData.sts.stDropped, stWork := stWDropped);
bTrip := stWStartFail.bTrip;                  // dropped never holds the pump: a warning at most
bWarn := stWStartFail.bWarn OR stWDropped.bWarn OR stWDropped.bTrip OR ipMotor.bIsFaulted;
eOwn := E_UtError.None;
IF stWStartFail.bTrip OR stWStartFail.bWarn THEN
  eOwn := E_UtError.StartFail;
ELSIF stWDropped.bWarn OR stWDropped.bTrip THEN
  eOwn := E_UtError.Dropped;
ELSIF ipMotor.bIsFaulted THEN
  eOwn := ipMotor.eActError;
END_IF;
bCmdPrev := bRunCmd;

Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset,
       tRestartDelay := refData.set.tMinOff);

refData.sts.bMotorInHand := ipMotor.eActMode = E_Mode.Hand;
refData.sts.bMotorFaulted := ipMotor.bIsFaulted;
refData.sts.bMasked := PartMasked();
IF bRunCmd THEN
  refData.det.tRunTime := tNow - tRunStart;
END_IF;
refData.det.tTimeLeft := tLeft;
refData.det.tIdleTime := tIdleNow;
refData.det.tHandLeft := tHandLeftNow;

END_FUNCTION_BLOCK