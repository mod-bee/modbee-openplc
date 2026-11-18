FUNCTION_BLOCK FB_RunGate EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    bPermit : BOOL := TRUE;
    refData : REFERENCE TO ST_RunGateData;
  END_VAR
  VAR_OUTPUT
    bWaiting : BOOL;
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
  IF NOT (refData.set.tMaxWait >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;              // the run's equipment is running (not used: ipRun.bIsActive is the run)
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    tN : TIME;
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT bCalled AND bWaiting THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF NOT ipRun.bIsActive THEN      (* bRunning is the equipment, off while waiting: ask the run *)
    bWaiting := FALSE;            (* a timeout stays shown until the permit returns or a new run waits *)
  ELSIF bPermit THEN
    bWaiting := FALSE;
    bTimedOut := FALSE;
  ELSIF NOT bWaiting THEN
    bWaiting := TRUE;
    bTimedOut := FALSE;
    tWaitSince := tN;
  END_IF;
  IF bWaiting AND __ISVALIDREF(refData) THEN
    IF refData.set.tMaxWait > T#0s AND tN - tWaitSince >= refData.set.tMaxWait THEN
      bTimedOut := TRUE;
    END_IF;
  END_IF;
  IF bTimedOut AND ipRun.bIsActive THEN
    eErrorId := E_UtError.GateTimeout;
    Evaluate := E_PartAction.Trip;
  ELSIF bWaiting THEN
    Evaluate := E_PartAction.Stop;
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
  refData.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.bRefused := FALSE;
  refData.eRefusedWhy := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipRun.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
refData.bWaiting := bWaiting;
IF bWaiting THEN refData.tWaited := tNow - tWaitSince; ELSE refData.tWaited := T#0s; END_IF;
bError := bTimedOut;
bWarning := NOT bError AND refData.bRefused;
IF bTimedOut THEN
  eErrorId := E_UtError.GateTimeout;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bWaiting THEN eState := E_State.Waiting; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK