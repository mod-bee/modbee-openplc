(* FB_Protection — one protection on any condition, as a part of its owner: a thermistor, a drive fault, an external
fault, a seal leak, a phase failure, a maximum run time
(eCountsWhen := Running, a long delay).

Pins: bConditionPresent (TRUE = the condition is present), eCountsWhen (when it counts: always, only while the owner runs,
only while it is stopped), ipOwner (the motor / pump / valve it protects), refData (its record: settings with
the error it raises, status). It adds itself to its owner on its first call; the owner evaluates it in its
own cycle and stops on a trip. Its own rung samples bConditionPresent.
A protection that is not Clear and whose rung stops being called raises PartLost on its owner until reset.
A thermistor: set.eErrorRaised := E_UtError.Thermistor; while it is tripped, a motor holds its coil off (bHoldOutputOff),
even against an IO-page force.
A bad settings write is put back (bSettingRefused / eSettingRefusedErrorId) and warns its owner (SettingRefused) until its reset
(bCmdResetFaults) or the owner's. *)

FUNCTION_BLOCK FB_Protection EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bConditionPresent : BOOL; (* TRUE = the condition is present *)
    eCountsWhen : E_Cause; (* when it counts *)
    ipOwner : I_PartOwner; (* the equipment it protects (required) *)
    refData : REFERENCE TO ST_ProtectionData; (* the protection's record *)
  END_VAR
  VAR RETAIN
    stKept : ST_ProtectionPartSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL; (* the rung ran since the owner's last Evaluate *)
    bInNow : BOOL;
    stWork : ST_ProtectionWork;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;    // the owner is running (its run command)
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  VAR
    bCause : BOOL;
    bTrip : BOOL;
    bOwnReset : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := refData.set.eErrorRaised;
  IF NOT bCalled AND refData.sts.eFaultState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  CASE eCountsWhen OF
    E_Cause.Running: bCause := bInNow AND bOwnerRunCommand;
    E_Cause.Stopped: bCause := bInNow AND NOT bOwnerRunCommand;
  ELSE
    bCause := bInNow;
  END_CASE;
  bOwnReset := refData.bCmdResetFaults;
  refData.bCmdResetFaults := FALSE;
  IF bResetRequest OR bOwnReset THEN
    refData.bSettingRefused := FALSE;
    refData.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  bTrip := F_Protect(tNow := TIME(), bConditionPresent := bCause, bResetRequest := bResetRequest OR bOwnReset,
                     tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set, stStatus := refData.sts, stWorking := stWork);
  IF stWork.bTripping THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWork.bSignalling THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWork.bWarning OR stWork.bSettingBad THEN
    Evaluate := E_PartAction.Warn;
  ELSIF refData.bSettingRefused THEN
    eErrorId := E_UtError.SettingRefused;
    Evaluate := E_PartAction.Warn;
  ELSE
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

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  bFirstScan := FALSE;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.bSettingRefused := TRUE;
END_IF;
IF NOT bAdded AND ipOwner <> NULL THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bInNow := bConditionPresent;
bCalled := TRUE;
bError := stWork.bTripping;
bWarning := stWork.bWarning OR refData.bSettingRefused;
IF ipOwner = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoMotor;              // a part without an owner protects nothing
ELSIF bError OR stWork.bWarning THEN
  eErrorId := refData.set.eErrorRaised;
ELSIF refData.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;

END_FUNCTION_BLOCK