(* FB_Pump — one pump: its owner link, its run decision and the motor it drives.

Pins: ipMotor (the motor, required: an FB_Motor or a variant), plus FB_Equipment's bInterlock, bPermissive,
ipSystem and FB_Object's bError / bWarning / eErrorId / eState. refData: the pump's record. Owners (a level
control, a group, a run) drive it through I_Equipment.Request; others read it through its properties.
The pump has its own Off / Hand / Auto; the motor has its own too and follows the pump only
while the motor is in Auto: a motor in Hand bypasses the pump ("motor in Hand": not available to the owner).
set.bWarnWhenNotAuto warns NotAuto while the pump or its motor is not in Auto (and the plant is).
Auto: the owner's request after set.tStartDelay (it must last that long), kept for set.tMinRunTime and until it has
been gone set.tStopDelay; after a stop, set.tMinOffTime (a power-up counts as a stop).
Built in: start fail (asked, motor ready, not running) and dropped (stopped by itself while asked: a warning
kept until reset, never holding the pump). The start mask (set.tMaskAfterStart after each start) is offered to
parts that mask at start (low pressure, no flow ...). A faulted motor is a warning on the pump.
Parts placed beside it: FB_LevelCheck (pressure, flow, dry run ...), FB_Protection (seal leak, external
fault, maximum run), FB_PumpPrime, FB_Starts (an idle pump's exercise is a part of its level control or group).
Detail (det): tThisRunTime (this run), tIdleTime (since the last stop, 0 while running: with tThisRunTime, the time in
the present phase), tTimeLeft (of the start delay, minimum run or stop delay now counting), tHandTimeLeft (a Hand
run's time left under set.tMaxHandRunTime, 0 = none counting).
set.ePumpRole (duty, jockey, booster) and set.fFlowAtFullSpeed
(flow at full speed) are read by stations and cascades through I_Pump. *)

FUNCTION_BLOCK FB_Pump EXTENDS FB_Equipment IMPLEMENTS I_Pump
  VAR_INPUT
    ipMotor : I_Motor; (* the motor it drives (required) *)
    refData : REFERENCE TO ST_PumpData; (* the block's record *)
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
    ipMotor.Request(bRun := bRun, bHoldOff := FALSE, fSpeedSetpointPct := fSpeedReq, bOverflowUrgent := bUrgentReq);
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
PROPERTY PUBLIC eActRole : E_PumpRole    // its role in a station: Duty, Jockey or Booster
  GET
    eActRole := E_PumpRole.Duty;
    IF __ISVALIDREF(refData) THEN
      eActRole := refData.set.ePumpRole;
    END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActCapacity : REAL    // flow at full speed (0 = not known)
  GET
    fActCapacity := 0.0;
    IF __ISVALIDREF(refData) THEN
      fActCapacity := refData.set.fFlowAtFullSpeed;
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
  ELSIF tNow - tRunStart < refData.set.tMinRunTime THEN
    ShapeRun := TRUE;
    tLeft := refData.set.tMinRunTime - (tNow - tRunStart);
  ELSIF tNow - tGoneSince < refData.set.tStopDelay THEN
    ShapeRun := TRUE;
    tLeft := refData.set.tStopDelay - (tNow - tGoneSince);
  ELSE
    ShapeRun := FALSE;
  END_IF;
END_METHOD

METHOD PROTECTED OVERRIDE PartMasked : BOOL
  PartMasked := bRunCmd AND tNow - tRunStart < refData.set.tMaskAfterStart;
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

PROPERTY PUBLIC fActSpeedPct : REAL    // the speed now, % (0 when stopped)
  GET
    IF ipMotor <> NULL THEN fActSpeedPct := ipMotor.fActSpeedPct; ELSE fActSpeedPct := 0.0; END_IF;
  END_GET
END_PROPERTY

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tMinOffTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tStartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tStopDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMinRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tMaskAfterStart >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.stStartFailFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stStartFailFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stDroppedOutFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stDroppedOutFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.fFlowAtFullSpeed >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fFlowAtFullSpeed <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.ePumpRole = E_PumpRole.Duty OR refData.set.ePumpRole = E_PumpRole.Jockey
             OR refData.set.ePumpRole = E_PumpRole.Booster) THEN
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
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
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
bTrip := F_Protect(tNow := tNow, bConditionPresent := bRunCmd AND ipMotor.bIsAvailable AND NOT ipMotor.bIsRunning AND NOT bMotorRan,
                   bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stStartFailFault, stStatus := refData.sts.stStartFailFault, stWorking := stWStartFail);
bTrip := F_Protect(tNow := tNow, bConditionPresent := bRunCmd AND bMotorRan AND NOT ipMotor.bIsRunning,
                   bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                   stSettings := refData.set.stDroppedOutFault, stStatus := refData.sts.stDroppedOutFault, stWorking := stWDropped);
bTrip := stWStartFail.bTripping;                  // dropped never holds the pump: a warning at most
bWarn := stWStartFail.bWarning OR stWDropped.bWarning OR stWDropped.bTripping OR ipMotor.bIsFaulted;
eOwn := E_UtError.None;
IF stWStartFail.bTripping OR stWStartFail.bWarning THEN
  eOwn := E_UtError.StartFail;
ELSIF stWDropped.bWarning OR stWDropped.bTripping THEN
  eOwn := E_UtError.Dropped;
ELSIF ipMotor.bIsFaulted THEN
  eOwn := ipMotor.eActError;
END_IF;
bCmdPrev := bRunCmd;

Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset,
       tRestartDelay := refData.set.tMinOffTime);

refData.sts.bMotorInHand := ipMotor.eActMode = E_Mode.Hand;
refData.sts.bMotorFaulted := ipMotor.bIsFaulted;
refData.sts.bStartMaskOn := PartMasked();
IF bRunCmd THEN
  refData.det.tThisRunTime := tNow - tRunStart;
END_IF;
refData.det.tTimeLeft := tLeft;
refData.det.tIdleTime := tIdleNow;
refData.det.tHandTimeLeft := tHandLeftNow;

END_FUNCTION_BLOCK