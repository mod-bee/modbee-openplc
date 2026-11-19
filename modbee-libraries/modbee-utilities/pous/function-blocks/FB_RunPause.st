(* FB_RunPause — operator pause / resume of a run. bPauseRun (a rising edge, or the record's bCmdPause) pauses the run
it belongs to; bResumeRun (or bCmdResumeRun) carries on. The pause ends with the run: a run that ends (done, aborted,
its maximum time or FB_Run's own set.tMaxPauseBeforeEnd) leaves no pause behind for the next one (no rung work-around needed). While paused the run is paused through the part list (E_PartAction.Stop): no run command,
no counting. *)

FUNCTION_BLOCK FB_RunPause EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    bPauseRun : BOOL R_EDGE; (* rising edge: pause the run *)
    bResumeRun : BOOL R_EDGE; (* rising edge: resume the run *)
    refData : REFERENCE TO ST_RunPauseData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bPaused : BOOL; (* the run is paused *)
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bPauseReq : BOOL; (* asked since the last evaluation *)
    bResumeReq : BOOL;
  END_VAR


METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;              // the run's equipment is running (not used: ipRun.bIsBusy is the run)
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT bCalled AND bPaused THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF NOT ipRun.bIsBusy THEN     (* bRunning is the equipment, off while paused: ask the run itself *)
    bPaused := FALSE;             (* the pause ends with the run *)
  ELSIF bResumeReq THEN
    bPaused := FALSE;
  ELSIF bPauseReq THEN
    bPaused := TRUE;
  END_IF;
  bPauseReq := FALSE;
  bResumeReq := FALSE;
  IF bPaused THEN
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

IF ipRun = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF NOT bAdded THEN
  ipRun.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
IF bPauseRun THEN bPauseReq := TRUE; END_IF;
IF bResumeRun THEN bResumeReq := TRUE; END_IF;
IF __ISVALIDREF(refData) THEN
  IF refData.bCmdPause THEN bPauseReq := TRUE; refData.bCmdPause := FALSE; END_IF;
  IF refData.bCmdResumeRun THEN bResumeReq := TRUE; refData.bCmdResumeRun := FALSE; END_IF;
  refData.sts.bPaused := bPaused;
END_IF;
bError := FALSE;
bWarning := FALSE;
eErrorId := E_UtError.None;
IF bPaused THEN eState := E_State.Held; ELSE eState := E_State.Idle; END_IF;

END_FUNCTION_BLOCK