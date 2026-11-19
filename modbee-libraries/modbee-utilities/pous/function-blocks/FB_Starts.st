(* FB_Starts — anti-cycling for a motor or pump, as a part of its owner (FB_Motor, FB_Pump ...).

Pins: ipOwner (the equipment), bStartFailed (a start attempt failed: its rising edge; wire the owner's start
fault, e.g. a drive's start failure or a no-feedback trip), refData, stConfig (tStartsWindow: the sliding window, T#1h)
-> bStartHeld, plus FB_Object's bWarning / eErrorId / eState.
- Starts per window (set.nMaxStartsPerWindow, 0 = no limit, 1..60) and a minimum time between starts
  (set.tMinTimeBetweenStarts, 0 = none). A start is the owner's run command coming on (Evaluate's bRunning); a command
  already on at power-up is not a start.
- After a failed start (bStartFailed rises) the next start waits set.tWaitAfterFailedStart (0 = no wait) so a fault is not
  retried at once; it counts from the failure. A failed start is not a start in the window. bCmdClearRefused ends the wait.
- A start that would break a limit waits (E_PartAction.HoldStart: the owner makes no new start, never a trip);
  a running owner is never stopped by it.
- The sliding window without a history: every start adds one window's worth to a load that drains at
  nMaxStartsPerWindow windows per window; a start is allowed while the load leaves room for one more. The load is not
  retained (only the settings are): after a power cut the count starts again.
- Status: sts.nStartCountInWindow (the load in starts, rounded up), sts.tStartHeldTimeLeft (until a start is allowed).
Its rung stopping while it holds a start is PartLost on its owner.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Starts EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the motor or pump *)
    bStartFailed : BOOL; (* a start attempt failed (its rising edge starts the wait set.tWaitAfterFailedStart) *)
    refData : REFERENCE TO ST_StartsData; (* the block's record *)
    stConfig : ST_StartsConfig; (* engineering constants (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    bStartHeld : BOOL; (* a start is held back by a limit *)
  END_VAR
  VAR RETAIN
    stKept : ST_StartsSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bEvaluated : BOOL; (* Evaluate has run since power-up *)
    bRunPrev : BOOL;
    tPrev : TIME;
    nLoad : DINT; (* ms x starts: each start adds the window, it drains nMaxStartsPerWindow ms per ms *)
    bHaveStart : BOOL;
    tLastStart : TIME;
    bFailPrev : BOOL;
    bFailing : BOOL;
    bCmdSeen : BOOL; (* bCmdClearRefused was written (the owner's Evaluate takes it) *)
    tFailAt : TIME;
  END_VAR


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
    tN : TIME;
    nN : DINT;
    nWin : DINT;
    nDt : DINT;
    nWaitMs : DINT;
    tGap : TIME;
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND bStartHeld THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF NOT bEvaluated THEN
    bEvaluated := TRUE;
    bRunPrev := bOwnerRunCommand;         // already on at power-up: not a new start
    tPrev := tN;
  END_IF;
  nN := INT_TO_DINT(refData.set.nMaxStartsPerWindow);
  nWin := TIME_TO_DINT(stConfig.tStartsWindow);
  IF stConfig.tStartsWindow <= T#0s OR stConfig.tStartsWindow > T#8h THEN
    nN := 0;                       // an unusable window: no per-window limit
    nWin := 0;
  END_IF;

  (* the load drains *)
  nDt := TIME_TO_DINT(tN - tPrev);
  tPrev := tN;
  IF nN > 0 AND nDt > 0 THEN
    nLoad := nLoad - nDt * nN;
  END_IF;
  IF nLoad < 0 OR nN <= 0 THEN
    nLoad := 0;
  END_IF;
  (* a start *)
  IF bOwnerRunCommand AND NOT bRunPrev THEN
    IF nN > 0 THEN
      nLoad := nLoad + nWin;
    END_IF;
    tLastStart := tN;
    bHaveStart := TRUE;
  END_IF;
  bRunPrev := bOwnerRunCommand;
  (* the waits *)
  nWaitMs := 0;
  IF nN > 0 AND nLoad > (nN - 1) * nWin THEN
    nWaitMs := (nLoad - (nN - 1) * nWin + nN - 1) / nN;
  END_IF;
  tGap := T#0s;
  IF bHaveStart AND tN - tLastStart < refData.set.tMinTimeBetweenStarts THEN
    tGap := refData.set.tMinTimeBetweenStarts - (tN - tLastStart);
  END_IF;
  (* a failed start: the next one waits *)
  IF bStartFailed AND NOT bFailPrev THEN
    tFailAt := tN;
    bFailing := TRUE;
  END_IF;
  bFailPrev := bStartFailed;
  IF bResetRequest OR bCmdSeen THEN
    bFailing := FALSE;
    bCmdSeen := FALSE;
  END_IF;
  IF bFailing AND tN - tFailAt >= refData.set.tWaitAfterFailedStart THEN
    bFailing := FALSE;
  END_IF;
  IF bFailing AND refData.set.tWaitAfterFailedStart - (tN - tFailAt) > tGap THEN
    tGap := refData.set.tWaitAfterFailedStart - (tN - tFailAt);
  END_IF;
  refData.sts.bWaitingAfterFailedStart := bFailing;
  refData.sts.tStartHeldTimeLeft := MAX(DINT_TO_TIME(nWaitMs), tGap);
  IF nWin > 0 THEN
    refData.sts.nStartCountInWindow := DINT_TO_INT((nLoad + nWin - 1) / nWin);
  ELSE
    refData.sts.nStartCountInWindow := 0;
  END_IF;
  bStartHeld := NOT bOwnerRunCommand AND refData.sts.tStartHeldTimeLeft > T#0s;
  refData.sts.bStartHeld := bStartHeld;
  IF bStartHeld THEN
    Evaluate := E_PartAction.HoldStart;
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

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.nMaxStartsPerWindow >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.nMaxStartsPerWindow <= 60) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (refData.set.tMinTimeBetweenStarts >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tWaitAfterFailedStart >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  IF ipOwner = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF stConfig.tStartsWindow <= T#0s OR stConfig.tStartsWindow > T#8h THEN
  bError := TRUE;                 // an unusable window: no per-window limit (the owner is never blocked by it)
  eErrorId := E_UtError.BadSetting;
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
ELSIF SetOk() THEN
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
IF refData.bCmdClearRefused THEN
  bCmdSeen := TRUE;
  refData.bCmdClearRefused := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bCalled := TRUE;

(* status *)
bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bStartHeld THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK