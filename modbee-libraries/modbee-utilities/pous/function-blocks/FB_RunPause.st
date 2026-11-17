FUNCTION_BLOCK FB_RunPause EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipRun : I_Run; (* required *)
    bPause : BOOL R_EDGE;
    bResume : BOOL R_EDGE;
    refData : REFERENCE TO ST_RunPauseData;
  END_VAR
  VAR_OUTPUT
    bPaused : BOOL;
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
    bRunning : BOOL;              // the run's equipment is running (not used: ipRun.bIsActive is the run)
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT bCalled AND bPaused THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF NOT ipRun.bIsActive THEN     (* bRunning is the equipment, off while paused: ask the run itself *)
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
    ipNext : I_Part;
  END_VAR
  THIS^.ipNext := ipNext;
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
IF bPause THEN bPauseReq := TRUE; END_IF;
IF bResume THEN bResumeReq := TRUE; END_IF;
IF __ISVALIDREF(refData) THEN
  IF refData.bCmdPause THEN bPauseReq := TRUE; refData.bCmdPause := FALSE; END_IF;
  IF refData.bCmdResume THEN bResumeReq := TRUE; refData.bCmdResume := FALSE; END_IF;
  refData.bPaused := bPaused;
END_IF;
bError := FALSE;
bWarning := FALSE;
eErrorId := E_UtError.None;
IF bPaused THEN eState := E_State.Held; ELSE eState := E_State.Idle; END_IF;

END_FUNCTION_BLOCK