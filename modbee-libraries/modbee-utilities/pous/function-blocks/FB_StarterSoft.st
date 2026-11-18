(* FB_StarterSoft — a soft starter's top-of-ramp check, as a part of its motor. The starter's run relay is the
motor's bFeedback, its fault relay an FB_Protection (eErrorId DriveFault). This part watches the top-of-ramp
relay: the motor's run command on and no top of ramp for set.stStartTooLong's delay is a trip (StartTooLong: the
ramp never finished, a stalled or overloaded start). bTopOfRamp is the starter's top-of-ramp / bypass relay, TRUE
= at full speed.
A soft stop: set the motor's stStuck delay longer than the starter's stop ramp (the run relay stays on while
it ramps down).
Pins: bTopOfRamp, ipOwner (the motor, required), refData -> bAtSpeed, plus FB_Object's outputs. It adds itself
to its motor on its first call; a check that is acting when its rung stops being called raises PartLost. *)

FUNCTION_BLOCK FB_StarterSoft EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bTopOfRamp : BOOL := FALSE; (* the starter's top-of-ramp relay (TRUE = at full speed) *)
    ipOwner : I_Equipment; (* the motor (required) *)
    refData : REFERENCE TO ST_StarterSoftData;
  END_VAR
  VAR_OUTPUT
    bAtSpeed : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_StarterSoftSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bTopNow : BOOL;
    stWork : ST_ProtectionWork;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.stStartTooLong.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stStartTooLong.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    bTrip : BOOL;
    bReset : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := E_UtError.StartTooLong;
  IF NOT bCalled AND stWork.bActive THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  bReset := bResetWanted OR refData.bCmdReset;
  refData.bCmdReset := FALSE;
  bTrip := F_Protect(tNow := TIME(), bCause := bRunning AND NOT bTopNow, bResetReq := bReset, tRetryWindow := T#1h,
                     stSet := refData.set.stStartTooLong, stSts := refData.stStartTooLong, stWork := stWork);
  IF stWork.bTrip THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWork.bSignal THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWork.bWarn THEN
    Evaluate := E_PartAction.Warn;
  ELSIF stWork.bBadSetting THEN
    eErrorId := E_UtError.BadSetting;
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNext : I_Part;
  END_VAR
  THIS^.ipNext := ipNext;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bAtSpeed := FALSE;
  bError := TRUE;
  IF ipOwner = NULL THEN
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
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
  refData.eRefusedWhy := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
bTopNow := bTopOfRamp;
bAtSpeed := bTopOfRamp;
refData.bAtSpeed := bTopOfRamp;
bError := stWork.bTrip;
bWarning := NOT bError AND (stWork.bWarn OR refData.bRefused);
IF stWork.bTrip OR stWork.bWarn THEN
  eErrorId := E_UtError.StartTooLong;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bTopOfRamp THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK