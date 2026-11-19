(* FB_Booster — a series booster pump that runs with a station's duty pumps, as a part of the station's
FB_LevelControl (one booster, not in the duty rotation).
While the station runs (its request on and its pumps running): set.eStartBoosterBy Delay starts the booster
set.tStartDelay after the duty pumps run; Pressure starts it while ipPressure is at or below set.fStartAtOrBelow, until it
is at or above set.fStopAtOrAbove (with a pressure that is not good: as Delay). At a cycle end the booster stops at
once; give the duty pumps a stop delay (FB_Pump set.tStopDelay = the gap) so they stop that much later.
set.bBoosterRequired: wanted and not running for set.stBoosterLostFault's delay -> BoosterLost (a trip stops the station).
bPermissive FALSE (default TRUE) keeps the booster off whatever the rule says (it stops at once).
Pins: ipBoosterPump (the booster pump, required), ipPressure (optional), ipOwner (the station's level control,
required), bPermissive, refData -> bBoosterRunCommand, plus FB_Object's outputs. It adds itself to the station on its first call; a check
that is acting when its rung stops being called raises PartLost. *)

FUNCTION_BLOCK FB_Booster EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipBoosterPump : I_Equipment; (* the booster pump (required) *)
    ipPressure : I_Measurement; (* Pressure start (optional) *)
    ipOwner : I_PartOwner; (* the station's level control (required) *)
    bPermissive : BOOL := TRUE; (* FALSE: the booster does not run now (it stops at once) *)
    refData : REFERENCE TO ST_BoosterData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bBoosterRunCommand : BOOL; (* the booster is asked to run now *)
  END_VAR
  VAR RETAIN
    stKept : ST_BoosterSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bRunWas : BOOL;
    tRunAt : TIME;
    bPressCall : BOOL; (* the pressure hysteresis *)
    stWLost : ST_ProtectionWork;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_BoosterSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tStartDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eStartBoosterBy = E_BoostStart.Delay OR stS.eStartBoosterBy = E_BoostStart.Pressure) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (ABS(stS.fStartAtOrBelow) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fStopAtOrAbove) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.eStartBoosterBy <> E_BoostStart.Pressure OR stS.fStartAtOrBelow < stS.fStopAtOrAbove) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.stBoosterLostFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stBoosterLostFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_BoosterSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;               // the station's request on and its pumps running
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  VAR
    tN : TIME;
    bPGood : BOOL;
    bTrip : BOOL;
    bReset : BOOL;
    eReqErr : E_UtError;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := E_UtError.BoosterLost;
  IF NOT bCalled AND (stWLost.bActive OR bBoosterRunCommand) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    ipBoosterPump.Request(bRun := FALSE, bHoldOff := FALSE);
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  bReset := bResetRequest OR refData.bCmdResetFaults;
  refData.bCmdResetFaults := FALSE;
  IF bOwnerRunCommand AND NOT bRunWas THEN
    tRunAt := tN;
  END_IF;
  bRunWas := bOwnerRunCommand;
  bPGood := FALSE;
  IF ipPressure <> NULL THEN
    bPGood := ipPressure.bIsFitted AND ipPressure.bIsGood;
  END_IF;
  IF NOT bOwnerRunCommand THEN
    bPressCall := FALSE;
    bBoosterRunCommand := FALSE;
  ELSIF refData.set.eStartBoosterBy = E_BoostStart.Pressure AND bPGood THEN
    IF ipPressure.fActValue <= refData.set.fStartAtOrBelow THEN
      bPressCall := TRUE;
    ELSIF ipPressure.fActValue >= refData.set.fStopAtOrAbove THEN
      bPressCall := FALSE;
    END_IF;
    bBoosterRunCommand := bPressCall;
  ELSE
    bBoosterRunCommand := tN - tRunAt >= refData.set.tStartDelay;   (* Delay, or a pressure that cannot be trusted *)
  END_IF;
  bBoosterRunCommand := bBoosterRunCommand AND bPermissive;
  eReqErr := ipBoosterPump.Request(bRun := bBoosterRunCommand, bHoldOff := FALSE);
  bTrip := F_Protect(tNow := tN, bConditionPresent := refData.set.bBoosterRequired AND bBoosterRunCommand AND NOT ipBoosterPump.bIsRunning,
                     bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stBoosterLostFault,
                     stStatus := refData.sts.stBoosterLostFault, stWorking := stWLost);
  IF stWLost.bTripping THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWLost.bSignalling THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWLost.bWarning THEN
    Evaluate := E_PartAction.Warn;
  ELSIF stWLost.bSettingBad THEN
    eErrorId := E_UtError.BadSetting;
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNextPart : I_Part;    // the next part in the owner's chain
  END_VAR
  THIS^.ipNext := ipNextPart;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL OR ipBoosterPump = NULL THEN
  bBoosterRunCommand := FALSE;
  bError := TRUE;
  IF ipOwner = NULL OR ipBoosterPump = NULL THEN
    eErrorId := E_UtError.NoMotor;
  ELSE
    eErrorId := E_UtError.NoRecord;
  END_IF;
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
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
refData.sts.bBoosterRunCommand := bBoosterRunCommand;
bError := stWLost.bTripping;
bWarning := NOT bError AND (stWLost.bWarning OR refData.sts.bSettingRefused);
IF stWLost.bTripping OR stWLost.bWarning THEN
  eErrorId := E_UtError.BoosterLost;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bBoosterRunCommand THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK