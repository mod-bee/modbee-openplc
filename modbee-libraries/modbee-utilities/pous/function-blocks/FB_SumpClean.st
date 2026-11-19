(* FB_SumpClean — sump cleaning: every set.nPumpCyclesBetweenCleans pump cycles (or bCleanNow / bCmdCleanNow) the sump is pumped down past
its normal stop to set.fCleanLevel and the pump runs on set.tRunOnAtCleanLevel there, to clear the settled solids. A part
of an EMPTY FB_LevelControl: it asks for a normal run (E_PartAction.Request; the low-low cut-out and start limits
still apply). Not reaching fCleanLevel within set.tCleanTimeout gives up: a warning (CleanFailed) until the next good
clean or a reset. A cycle is one start of the owner's run. A bad level stops a clean. The record shows the
clean under way's time (tElapsedTime). *)

FUNCTION_BLOCK FB_SumpClean EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the EMPTY level control *)
    ipLevel : I_Measurement; (* required: the sump level *)
    bCleanNow : BOOL R_EDGE; (* clean now *)
    refData : REFERENCE TO ST_SumpCleanData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bCleaning : BOOL; (* a clean is running *)
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


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.nPumpCyclesBetweenCleans >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (ABS(refData.set.fCleanLevel) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.tRunOnAtCleanLevel >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tCleanTimeout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;              // the owner is running
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
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
  IF bOwnerRunCommand AND NOT bRunPrev AND NOT bCleaning THEN
    refData.sts.nPumpCycleCount := refData.sts.nPumpCycleCount + 1;
    IF refData.set.nPumpCyclesBetweenCleans > 0 AND refData.sts.nPumpCycleCount >= refData.set.nPumpCyclesBetweenCleans THEN
      bAsk := TRUE;
    END_IF;
  END_IF;
  bRunPrev := bOwnerRunCommand;
  IF bAsk AND NOT bCleaning AND bGood THEN
    bCleaning := TRUE;
    bReached := FALSE;
    tStart := tN;
  END_IF;
  bAsk := FALSE;
  IF bCleaning THEN
    IF NOT bGood THEN
      bCleaning := FALSE;
    ELSIF refData.set.tCleanTimeout > T#0s AND NOT bReached AND tN - tStart >= refData.set.tCleanTimeout THEN
      bCleaning := FALSE;
      refData.sts.bCleanFailed := TRUE;
    ELSIF ipLevel.fActValue <= refData.set.fCleanLevel OR bReached THEN
      IF NOT bReached THEN
        bReached := TRUE;
        tAt := tN;
      END_IF;
      IF tN - tAt >= refData.set.tRunOnAtCleanLevel THEN
        bCleaning := FALSE;
        refData.sts.bCleanFailed := FALSE;
        refData.sts.nPumpCycleCount := 0;
      END_IF;
    END_IF;
  END_IF;
  IF bCleaning THEN refData.sts.tElapsedTime := tN - tStart; ELSE refData.sts.tElapsedTime := T#0s; END_IF;
  IF bCleaning THEN
    Evaluate := E_PartAction.Request;
  ELSIF refData.sts.bCleanFailed THEN
    eErrorId := E_UtError.CleanFailed;
    Evaluate := E_PartAction.Warn;
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
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
IF bCleanNow THEN bAsk := TRUE; END_IF;
IF refData.bCmdCleanNow THEN
  bAsk := TRUE;
  refData.bCmdCleanNow := FALSE;
END_IF;
IF refData.bCmdClearCleanFailed OR SystemReset() THEN
  refData.bCmdClearCleanFailed := FALSE;
  refData.sts.bCleanFailed := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
refData.sts.bCleaning := bCleaning;
IF bCleaning THEN refData.sts.tElapsedTime := TIME() - tStart; ELSE refData.sts.tElapsedTime := T#0s; END_IF;
bError := FALSE;
bWarning := refData.sts.bCleanFailed OR refData.sts.bSettingRefused;
IF refData.sts.bCleanFailed THEN
  eErrorId := E_UtError.CleanFailed;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bCleaning THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK