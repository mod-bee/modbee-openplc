(* FB_RunGate — a run waits for a permissive: while the run is active and bPermissive is FALSE the run is paused
(E_PartAction.Stop: the equipment waits, nothing counts). Waiting longer than set.tPermissiveWaitTimeout (0 = no limit) in one
stretch trips the run (GateTimeout; the run ends as a fault). Typical: a run waits for its supply tank, a valve's
open confirmation, a pressure. The wait restarts each time bPermissive comes back. *)

FUNCTION_BLOCK FB_RunGate EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    bPermissive : BOOL := TRUE; (* the run may go on (FALSE: it waits) *)
    refData : REFERENCE TO ST_RunGateData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bWaitingForPermissive : BOOL; (* the run waits for bPermissive *)
  END_VAR
  VAR RETAIN
    stKept : ST_RunGateSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    tWaitSince : TIME;
    bTimedOut : BOOL;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tPermissiveWaitTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;              // the run's equipment is running (not used: ipRun.bIsBusy is the run)
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  VAR
    tN : TIME;
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT bCalled AND bWaitingForPermissive THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF NOT ipRun.bIsBusy THEN      (* bRunning is the equipment, off while waiting: ask the run *)
    bWaitingForPermissive := FALSE;            (* a timeout stays shown until the permit returns or a new run waits *)
  ELSIF bPermissive THEN
    bWaitingForPermissive := FALSE;
    bTimedOut := FALSE;
  ELSIF NOT bWaitingForPermissive THEN
    bWaitingForPermissive := TRUE;
    bTimedOut := FALSE;
    tWaitSince := tN;
  END_IF;
  IF bWaitingForPermissive AND __ISVALIDREF(refData) THEN
    IF refData.set.tPermissiveWaitTimeout > T#0s AND tN - tWaitSince >= refData.set.tPermissiveWaitTimeout THEN
      bTimedOut := TRUE;
    END_IF;
  END_IF;
  IF bTimedOut AND ipRun.bIsBusy THEN
    eErrorId := E_UtError.GateTimeout;
    Evaluate := E_PartAction.Trip;
  ELSIF bWaitingForPermissive THEN
    Evaluate := E_PartAction.Stop;
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

IF NOT __ISVALIDREF(refData) OR ipRun = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
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
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipRun.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
refData.sts.bWaitingForPermissive := bWaitingForPermissive;
IF bWaitingForPermissive THEN refData.sts.tWaitedFor := tNow - tWaitSince; ELSE refData.sts.tWaitedFor := T#0s; END_IF;
bError := bTimedOut;
bWarning := NOT bError AND refData.sts.bSettingRefused;
IF bTimedOut THEN
  eErrorId := E_UtError.GateTimeout;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bWaitingForPermissive THEN eState := E_State.Waiting; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK