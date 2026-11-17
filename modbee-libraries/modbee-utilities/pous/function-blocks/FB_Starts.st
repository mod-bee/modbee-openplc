(* FB_Starts — anti-cycling for a motor or pump, as a part of its owner (FB_Motor, FB_Pump ...)
(DESIGN-0.2.md section 5.2; src-v2 UT_START_LIMIT / UT_STARTS).

Pins: ipOwner (the equipment), bStartFailed (a start attempt failed: its rising edge; wire the owner's start
fault, e.g. a drive's start failure or a no-feedback trip), refData, stConfig (tWindow: the sliding window, T#1h)
-> bHolding, plus FB_Object's bWarning / eErrorId / eState.
- Starts per window (set.nMaxPerHour, 0 = no limit, 1..60) and a minimum time between starts
  (set.tMinBetween, 0 = none). A start is the owner's run command coming on (Evaluate's bRunning); a command
  already on at power-up is not a start.
- After a failed start (bStartFailed rises) the next start waits set.tFailWait (0 = no wait) so a fault is not
  retried at once; it counts from the failure. A failed start is not a start in the window. bCmdReset ends the wait.
- A start that would break a limit waits (E_PartAction.HoldStart: the owner makes no new start, never a trip);
  a running owner is never stopped by it.
- The sliding window without a history: every start adds one window's worth to a load that drains at
  nMaxPerHour windows per window; a start is allowed while the load leaves room for one more. The load is not
  retained (only the settings are): after a power cut the count starts again.
- Status: sts.nStartsInHour (the load in starts, rounded up), sts.tWait (until a start is allowed).
Its rung stopping while it holds a start is PartLost on its owner.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Starts EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the motor or pump *)
    bStartFailed : BOOL; (* a start attempt failed (its rising edge starts the wait set.tFailWait) *)
    refData : REFERENCE TO ST_StartsData;
    stConfig : ST_StartsConfig; (* engineering constants (set at the declaration) *)
  END_VAR
  VAR_OUTPUT
    bHolding : BOOL;
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
    nLoad : DINT; (* ms x starts: each start adds the window, it drains nMaxPerHour ms per ms *)
    bHaveStart : BOOL;
    tLastStart : TIME;
    bFailPrev : BOOL;
    bFailing : BOOL;
    bCmdSeen : BOOL; (* bCmdReset was written (the owner's Evaluate takes it) *)
    tFailAt : TIME;
  END_VAR


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
  IF NOT bCalled AND bHolding THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF NOT bEvaluated THEN
    bEvaluated := TRUE;
    bRunPrev := bRunning;         // already on at power-up: not a new start
    tPrev := tN;
  END_IF;
  nN := INT_TO_DINT(refData.set.nMaxPerHour);
  nWin := TIME_TO_DINT(stConfig.tWindow);
  IF stConfig.tWindow <= T#0s OR stConfig.tWindow > T#8h THEN
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
  IF bRunning AND NOT bRunPrev THEN
    IF nN > 0 THEN
      nLoad := nLoad + nWin;
    END_IF;
    tLastStart := tN;
    bHaveStart := TRUE;
  END_IF;
  bRunPrev := bRunning;
  (* the waits *)
  nWaitMs := 0;
  IF nN > 0 AND nLoad > (nN - 1) * nWin THEN
    nWaitMs := (nLoad - (nN - 1) * nWin + nN - 1) / nN;
  END_IF;
  tGap := T#0s;
  IF bHaveStart AND tN - tLastStart < refData.set.tMinBetween THEN
    tGap := refData.set.tMinBetween - (tN - tLastStart);
  END_IF;
  (* a failed start: the next one waits *)
  IF bStartFailed AND NOT bFailPrev THEN
    tFailAt := tN;
    bFailing := TRUE;
  END_IF;
  bFailPrev := bStartFailed;
  IF bResetWanted OR bCmdSeen THEN
    bFailing := FALSE;
    bCmdSeen := FALSE;
  END_IF;
  IF bFailing AND tN - tFailAt >= refData.set.tFailWait THEN
    bFailing := FALSE;
  END_IF;
  IF bFailing AND refData.set.tFailWait - (tN - tFailAt) > tGap THEN
    tGap := refData.set.tFailWait - (tN - tFailAt);
  END_IF;
  refData.sts.bFailWaiting := bFailing;
  refData.sts.tWait := MAX(DINT_TO_TIME(nWaitMs), tGap);
  IF nWin > 0 THEN
    refData.sts.nStartsInHour := DINT_TO_INT((nLoad + nWin - 1) / nWin);
  ELSE
    refData.sts.nStartsInHour := 0;
  END_IF;
  bHolding := NOT bRunning AND refData.sts.tWait > T#0s;
  refData.sts.bHolding := bHolding;
  IF bHolding THEN
    Evaluate := E_PartAction.HoldStart;
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

METHOD PRIVATE SetOk : BOOL
  SetOk := refData.set.nMaxPerHour >= 0 AND refData.set.nMaxPerHour <= 60 AND refData.set.tMinBetween >= T#0s
           AND refData.set.tFailWait >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  IF ipOwner = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF stConfig.tWindow <= T#0s OR stConfig.tWindow > T#8h THEN
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
IF refData.bCmdReset THEN
  bCmdSeen := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;
bCalled := TRUE;

(* status *)
bError := FALSE;
bWarning := refData.sts.bRefused;
IF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bHolding THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK