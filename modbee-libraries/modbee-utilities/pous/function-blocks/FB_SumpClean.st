(* FB_SumpClean — sump cleaning: every set.nEvery pump cycles (or bClean / bCmdClean) the sump is pumped down past
its normal stop to set.fCleanLevel and the pump runs on set.tCleanTime there, to clear the settled solids. A part
of an EMPTY FB_LevelControl: it asks for a normal run (E_PartAction.Request; the low-low cut-out and start limits
still apply). Not reaching fCleanLevel within set.tMaxClean gives up: a warning (CleanFailed) until the next good
clean or a reset. A cycle is one start of the owner's run. A bad level stops a clean. *)

FUNCTION_BLOCK FB_SumpClean EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the EMPTY level control *)
    ipLevel : I_Measurement; (* required: the sump level *)
    bClean : BOOL R_EDGE; (* clean now *)
    refData : REFERENCE TO ST_SumpCleanData;
  END_VAR
  VAR_OUTPUT
    bCleaning : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_SumpCleanSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bAsk : BOOL;
    bRunPrev : BOOL;
    bReached : BOOL;
    tStart : TIME;
    tAt : TIME;
  END_VAR


METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;              // the owner is running
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    tN : TIME;
    bGood : BOOL;
  END_VAR
  eErrorId := E_UtError.None;
  Evaluate := E_PartAction.None;
  IF NOT bCalled OR NOT __ISVALIDREF(refData) OR ipLevel = NULL THEN
    bCleaning := FALSE;           (* never trip a sump for its cleaning: just stop asking *)
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  bGood := ipLevel.bIsGood;
  (* cycles: each start of the owner's run (not a clean's own) *)
  IF bRunning AND NOT bRunPrev AND NOT bCleaning THEN
    refData.nCycles := refData.nCycles + 1;
    IF refData.set.nEvery > 0 AND refData.nCycles >= refData.set.nEvery THEN
      bAsk := TRUE;
    END_IF;
  END_IF;
  bRunPrev := bRunning;
  IF bAsk AND NOT bCleaning AND bGood THEN
    bCleaning := TRUE;
    bReached := FALSE;
    tStart := tN;
  END_IF;
  bAsk := FALSE;
  IF bCleaning THEN
    IF NOT bGood THEN
      bCleaning := FALSE;
    ELSIF refData.set.tMaxClean > T#0s AND NOT bReached AND tN - tStart >= refData.set.tMaxClean THEN
      bCleaning := FALSE;
      refData.bFailed := TRUE;
    ELSIF ipLevel.fActValue <= refData.set.fCleanLevel OR bReached THEN
      IF NOT bReached THEN
        bReached := TRUE;
        tAt := tN;
      END_IF;
      IF tN - tAt >= refData.set.tCleanTime THEN
        bCleaning := FALSE;
        refData.bFailed := FALSE;
        refData.nCycles := 0;
      END_IF;
    END_IF;
  END_IF;
  IF bCleaning THEN
    Evaluate := E_PartAction.Request;
  ELSIF refData.bFailed THEN
    eErrorId := E_UtError.CleanFailed;
    Evaluate := E_PartAction.Warn;
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

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL OR ipLevel = NULL THEN
  bError := TRUE;
  IF ipLevel = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
ELSIF refData.set.nEvery >= 0 AND ABS(refData.set.fCleanLevel) <= REAL#3.4E38 AND refData.set.tCleanTime >= T#0s
      AND refData.set.tMaxClean >= T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
IF bClean THEN bAsk := TRUE; END_IF;
IF refData.bCmdClean THEN
  bAsk := TRUE;
  refData.bCmdClean := FALSE;
END_IF;
IF refData.bCmdReset OR SystemReset() THEN
  refData.bCmdReset := FALSE;
  refData.bFailed := FALSE;
  refData.bRefused := FALSE;
END_IF;
refData.bCleaning := bCleaning;
bError := FALSE;
bWarning := refData.bFailed OR refData.bRefused;
IF refData.bFailed THEN
  eErrorId := E_UtError.CleanFailed;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bCleaning THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK