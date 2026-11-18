(* FB_Protection — one protection on any condition, as a part of its owner: a thermistor, a drive fault, an external
fault, a seal leak, a phase failure, a maximum run time
(eCause := Running, a long delay).

Pins: bIn (TRUE = the condition is present), eCause (when it counts: always, only while the owner runs,
only while it is stopped), ipOwner (the motor / pump / valve it protects), refData (its record: settings with
the error it raises, status). It adds itself to its owner on its first call; the owner evaluates it in its
own cycle and stops on a trip. Its own rung samples bIn.
A protection that is not Clear and whose rung stops being called raises PartLost on its owner until reset.
A thermistor: set.eErrorId := E_UtError.Thermistor; while it is tripped, a motor holds its coil off (bHoldOff),
even against an IO-page force.
A bad settings write is put back (bRefused / eRefusedWhy) and warns its owner (SettingRefused) until its reset
(bCmdReset) or the owner's. *)

FUNCTION_BLOCK FB_Protection EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bIn : BOOL; (* TRUE = the condition is present *)
    eCause : E_Cause; (* when it counts *)
    ipOwner : I_PartOwner; (* the equipment it protects (required) *)
    refData : REFERENCE TO ST_ProtectionData;
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
  IF NOT (refData.set.tDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRecover >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.nMaxRetries >= 0) THEN
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
    bCause : BOOL;
    bTrip : BOOL;
    bOwnReset : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := refData.set.eErrorId;
  IF NOT bCalled AND refData.sts.eState <> E_ProtState.Clear THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  CASE eCause OF
    E_Cause.Running: bCause := bInNow AND bRunning;
    E_Cause.Stopped: bCause := bInNow AND NOT bRunning;
  ELSE
    bCause := bInNow;
  END_CASE;
  bOwnReset := refData.bCmdReset;
  refData.bCmdReset := FALSE;
  IF bResetWanted OR bOwnReset THEN
    refData.bRefused := FALSE;
    refData.eRefusedWhy := E_UtError.None;
  END_IF;
  bTrip := F_Protect(tNow := TIME(), bCause := bCause, bResetReq := bResetWanted OR bOwnReset,
                     tRetryWindow := T#1h, stSet := refData.set, stSts := refData.sts, stWork := stWork);
  IF stWork.bTrip THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWork.bSignal THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWork.bWarn OR stWork.bBadSetting THEN
    Evaluate := E_PartAction.Warn;
  ELSIF refData.bRefused THEN
    eErrorId := E_UtError.SettingRefused;
    Evaluate := E_PartAction.Warn;
  ELSE
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
  refData.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF NOT bAdded AND ipOwner <> NULL THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bInNow := bIn;
bCalled := TRUE;
bError := stWork.bTrip;
bWarning := stWork.bWarn OR refData.bRefused;
IF ipOwner = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoMotor;              // a part without an owner protects nothing
ELSIF bError OR stWork.bWarn THEN
  eErrorId := refData.set.eErrorId;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;

END_FUNCTION_BLOCK