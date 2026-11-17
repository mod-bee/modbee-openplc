(* FB_StepSeq — a timed / conditional step sequence: backwash, CIP, fill-mix-drain, kiln and dryer cycles (src-v2
UT_STEP_SEQ + UT_STEP, rows instead of element blocks, DESIGN-0.2.md section 5.6; the same rules).
Tables the project declares (VAR_IN_OUT): aStepSet (the recipe, one row per step, at most 16 kept), aStep (each
step's live row: the project writes aStep[i].bCond, the step's wait condition), aOutputs (the outputs). Each step
switches on the outputs in its nOutputs pattern (bit n = the n-th element of aOutputs, counted from the first)
and lasts tDuration, or until its bCond when bWaitCond, or both (the time AND the condition); a step with neither
ends on the next scan. tTimeout caps a step; eOnTimeout then holds there with a fault (outputs to set.nPauseOutputs
until a reset or bNext: StepTimeout), carries on, or goes to the stop step.
Positions count from 1 = the first element. nNext (0 = the following step) sends the sequence elsewhere; a jump
back repeats nLoops times, then carries on (its count restarts each time the loop is left, so loops can nest); a
jump back with nLoops 0 would never end and is refused (RecipeBad), as is an nNext or set.nStopStep outside the
recipe; bSkip steps are passed over. A stop goes to set.nStopStep and carries on from there to the end (put the
safe end steps last); nStopStep 0 ends at once with every output off. bDone pulses when the recipe completes
without a stop (sts.nCycles counts them since power-up). sts.eLastResult: Done, Manual (a stop, after the stop
steps), Abort, Fault (a step timeout sent to the stop steps, or a bad nNext met while running).
bRun held runs it from step 1 and its drop is a stop; bInterlock FALSE acts as bAbort; bPermissive FALSE holds
back a start. bAbort (a level) ends a run at once, every output off, no stop steps, and no start or jump while
on. bPause (or bCmdPause, until a start) holds the step: outputs to nPauseOutputs, the step's time kept. After a
power cut the sequence is idle with every output off and never resumes by itself (nCmdJump starts it at any step).
HMI commands act once per write. Kept (a retained last-good copy, restored at power-up, a bad write put back):
set, and the recipe rows (up to 16). *)

FUNCTION_BLOCK FB_StepSeq EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL; (* held: run from step 1; its drop = a stop *)
    bStart : BOOL R_EDGE; (* run from step 1 (resumes an HMI pause) *)
    bStop : BOOL R_EDGE; (* go to the stop step (or end) *)
    bPause : BOOL; (* hold: outputs to nPauseOutputs, time kept *)
    bNext : BOOL R_EDGE; (* end this step now (manual stepping) *)
    bReset : BOOL R_EDGE; (* clear a fault *)
    bAbort : BOOL; (* level: end at once, every output off, no stop steps *)
    bInterlock : BOOL := TRUE; (* FALSE = abort *)
    bPermissive : BOOL := TRUE; (* FALSE holds back a start *)
    refData : REFERENCE TO ST_StepSeqData;
  END_VAR
  VAR_IN_OUT
    aStepSet : ARRAY [*] OF ST_STEPSET;
    aStep : ARRAY [*] OF ST_STEP;
    aOutputs : ARRAY [*] OF BOOL;
  END_VAR
  VAR_OUTPUT
    bBusy : BOOL;
    bDone : BOOL; (* one scan: the recipe completed *)
    nCurrentStep : INT; (* position running (0 = idle) *)
    tRemaining : TIME; (* time left in this step *)
  END_VAR
  VAR RETAIN
    stKept : ST_StepSeqSet;
    aKeptStep : ARRAY [1..16] OF ST_STEPSET;
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxKept : INT := 16;
  END_VAR
  VAR
    tStepEl : TIME;
    tTmo : TIME; (* time toward the timeout *)
    tPrev : TIME;
    nCur : DINT; (* position running (0 = idle) *)
    bGoing : BOOL;
    bStopping : BOOL;
    bHmiPause : BOOL;
    bHeld : BOOL; (* held on a step timeout *)
    bRunPrev : BOOL;
    bByRun : BOOL;
    nCycles : UDINT;
    bStartSeen : BOOL;
    bStopSeen : BOOL;
    bPauseSeen : BOOL;
    bNextSeen : BOOL;
    bResetSeen : BOOL;
    eStopWhy : E_StopReason; (* why the stop steps are running *)
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bRowsOk : BOOL;
    tScan : TIME;
    nLo : DINT;
    nSLo : DINT;
    nN : DINT;
    nOLo : DINT;
    nOHi : DINT;
    nI : DINT;
    nS : DINT;
    nJ : DINT;
    nP : DINT;
    nNx : DINT;
    nGuard : DINT;
    bCfgBad : BOOL;
    nCfgStep : DINT;
    bFinish : BOOL;
    bToStop : BOOL;
    bEndNow : BOOL;
    bComplete : BOOL;
    nPattern : DWORD;
    bStartReq : BOOL;
    bStopReq : BOOL;
    bNextReq : BOOL;
    bResetReq : BOOL;
    bPauseReq : BOOL;
    nJumpTo : DINT;
    eResult : E_StopReason;
    bAbortNow : BOOL;
  END_VAR


METHOD PRIVATE StepOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StepSet;
  END_VAR
  StepOk := stS.tDuration >= T#0s AND stS.tTimeout >= T#0s AND stS.nLoops >= 0
            AND (stS.eOnTimeout = E_StepTimeout.Hold OR stS.eOnTimeout = E_StepTimeout.Next
                 OR stS.eOnTimeout = E_StepTimeout.Stop);
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aStep, 1);
nSLo := LOWER_BOUND(aStepSet, 1);
nN := MIN(UPPER_BOUND(aStep, 1) - nLo + 1, UPPER_BOUND(aStepSet, 1) - nSLo + 1);
nOLo := LOWER_BOUND(aOutputs, 1);
nOHi := UPPER_BOUND(aOutputs, 1);
bDone := FALSE;

(* kept settings and recipe; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nN, INT_TO_DINT(nKeptRows)) DO
      aStepSet[nSLo + nI - 1] := aKeptStep[nI];
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  (* first scan, also after a power cut: idle, every output off *)
  tPrev := tNow;
  bRunPrev := bRun;               (* a bRun held at power-up does not start it *)
  FOR nI := 1 TO nN DO
    aStep[nLo + nI - 1].bActive := FALSE;
    aStep[nLo + nI - 1].nLoopCount := 0;
  END_FOR;
END_IF;
bOkSet := refData.set.nStopStep >= 0;
IF bOkSet THEN
  stKept := refData.set;
ELSIF stKept.nStopStep >= 0 THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
FOR nI := 1 TO nN DO
  nS := nSLo + nI - 1;
  IF StepOk(stS := aStepSet[nS]) THEN
    IF nI <= cMaxKept THEN aKeptStep[nI] := aStepSet[nS]; END_IF;
  ELSIF nI <= INT_TO_DINT(nKeptRows) THEN
    aStepSet[nS] := aKeptStep[nI];
    refData.sts.bRefused := TRUE;
  ELSE
    bRowsOk := FALSE;
  END_IF;
END_FOR;
IF bRowsOk AND nN > INT_TO_DINT(nKeptRows) THEN
  nKeptRows := DINT_TO_INT(MIN(nN, cMaxKept));
END_IF;

tScan := tNow - tPrev;
tPrev := tNow;
IF tScan < T#0s THEN
  tScan := T#0s;
END_IF;

(* pins act on a rising edge; HMI commands once per write, then cleared *)
bStartReq := bStart OR (refData.bCmdStart AND NOT bStartSeen) OR (bRun AND NOT bRunPrev);
bStartSeen := refData.bCmdStart;
refData.bCmdStart := FALSE;
bStopReq := bStop OR (refData.bCmdStop AND NOT bStopSeen) OR (NOT bRun AND bRunPrev AND bByRun);
IF bRun AND NOT bRunPrev THEN
  bByRun := TRUE;                 (* a held run: its drop is a stop *)
ELSIF bStopReq OR NOT bGoing THEN
  bByRun := FALSE;
END_IF;
bRunPrev := bRun;
IF NOT bPermissive AND NOT bGoing THEN
  bStartReq := FALSE;             (* a start is held back *)
END_IF;
bStopSeen := refData.bCmdStop;
refData.bCmdStop := FALSE;
bNextReq := bNext OR (refData.bCmdNext AND NOT bNextSeen);
bNextSeen := refData.bCmdNext;
refData.bCmdNext := FALSE;
bResetReq := bReset OR SystemReset() OR (refData.bCmdReset AND NOT bResetSeen);
bResetSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;
bPauseReq := refData.bCmdPause AND NOT bPauseSeen;
bPauseSeen := refData.bCmdPause;
refData.bCmdPause := FALSE;
nJumpTo := 0;
IF refData.nCmdJump >= 0 THEN
  IF refData.nCmdJump >= 1 AND INT_TO_DINT(refData.nCmdJump) <= nN THEN
    nJumpTo := INT_TO_DINT(refData.nCmdJump);
  END_IF;
  refData.nCmdJump := -1;
END_IF;
IF bResetReq THEN
  refData.sts.bRecipeBad := FALSE;
  refData.sts.bRefused := FALSE;
  IF bHeld THEN
    bHeld := FALSE;               (* the step carries on, with a fresh timeout *)
    tTmo := T#0s;
  END_IF;
  refData.sts.bStepTimeout := FALSE;
END_IF;

(* check the recipe before a start or a jump *)
IF (bStartReq AND NOT bGoing) OR nJumpTo > 0 THEN
  bCfgBad := nN < 1 OR refData.set.nStopStep < 0 OR INT_TO_DINT(refData.set.nStopStep) > nN;
  nCfgStep := 0;
  FOR nI := 1 TO nN DO
    nS := nSLo + nI - 1;
    nNx := INT_TO_DINT(aStepSet[nS].nNext);
    IF NOT bCfgBad AND (nNx < 0 OR nNx > nN OR (nNx > 0 AND nNx <= nI AND aStepSet[nS].nLoops <= 0)
                        OR NOT StepOk(stS := aStepSet[nS])) THEN
      bCfgBad := TRUE;
      nCfgStep := nI;
    END_IF;
  END_FOR;
  IF bCfgBad THEN
    refData.sts.bRecipeBad := TRUE;
    refData.sts.nConfigStep := DINT_TO_INT(nCfgStep);
    bGoing := FALSE;
    bHeld := FALSE;
    bStopping := FALSE;
    bHmiPause := FALSE;
    nCur := 0;
    FOR nI := 1 TO nN DO
      aStep[nLo + nI - 1].bActive := FALSE;
    END_FOR;
    bStartReq := FALSE;
    nJumpTo := 0;
  ELSE
    refData.sts.bRecipeBad := FALSE;
  END_IF;
END_IF;

(* commands *)
bEndNow := FALSE;
bToStop := FALSE;
bFinish := FALSE;
eResult := E_StopReason.None;
nP := 0;                          (* position to enter this scan (0 = none) *)
bAbortNow := bAbort OR NOT bInterlock;
IF bAbortNow THEN
  bStartReq := FALSE;             (* everything off at once, no stop steps; nothing starts while on *)
  nJumpTo := 0;
  IF bGoing THEN
    bEndNow := TRUE;
    eResult := E_StopReason.Abort;
  END_IF;
END_IF;
IF NOT bGoing THEN
  bHmiPause := FALSE;
  IF (nJumpTo > 0 OR bStartReq) AND NOT bStopReq THEN
    bGoing := TRUE;
    bStopping := FALSE;
    bHeld := FALSE;
    refData.sts.bStepTimeout := FALSE;
    refData.sts.nTimedOutStep := 0;
    FOR nI := 1 TO nN DO
      aStep[nLo + nI - 1].nLoopCount := 0;
      aStep[nLo + nI - 1].bActive := FALSE;
    END_FOR;
    IF nJumpTo > 0 THEN nP := nJumpTo; ELSE nP := 1; END_IF;
  END_IF;
ELSE
  IF bStopReq THEN
    bHmiPause := FALSE;
    IF NOT bStopping THEN
      bToStop := TRUE;
      eStopWhy := E_StopReason.Manual;
    END_IF;
  ELSIF nJumpTo > 0 THEN
    bHeld := FALSE;
    bStopping := FALSE;           (* a jump leaves the stop steps: a stop works again *)
    refData.sts.bStepTimeout := FALSE;
    IF nCur >= 1 THEN
      aStep[nLo + nCur - 1].bActive := FALSE;
    END_IF;
    nP := nJumpTo;
  ELSIF bNextReq THEN
    bHeld := FALSE;
    refData.sts.bStepTimeout := FALSE;
    bFinish := TRUE;
  ELSIF bStartReq THEN
    bHmiPause := FALSE;           (* a start resumes an HMI pause *)
  END_IF;
  IF bPauseReq THEN
    bHmiPause := TRUE;
  END_IF;
END_IF;
refData.sts.bPaused := bGoing AND (bPause OR bHmiPause);

(* the running step *)
IF bGoing AND nP = 0 AND NOT bToStop AND NOT bFinish AND NOT bHeld AND NOT refData.sts.bPaused AND nCur >= 1
   AND NOT bEndNow THEN
  nS := nSLo + nCur - 1;
  tStepEl := tStepEl + tScan;
  tTmo := tTmo + tScan;
  bComplete := (aStepSet[nS].tDuration <= T#0s OR tStepEl >= aStepSet[nS].tDuration)
               AND (NOT aStepSet[nS].bWaitCond OR aStep[nLo + nCur - 1].bCond);
  IF bComplete THEN
    bFinish := TRUE;
  ELSIF aStepSet[nS].tTimeout > T#0s AND tTmo >= aStepSet[nS].tTimeout THEN
    refData.sts.nTimedOutStep := DINT_TO_INT(nCur);
    CASE aStepSet[nS].eOnTimeout OF
    E_StepTimeout.Next:
      bFinish := TRUE;
    E_StepTimeout.Stop:
      IF bStopping THEN
        bEndNow := TRUE;          (* the stop step itself timed out *)
      ELSE
        bToStop := TRUE;
        eStopWhy := E_StopReason.Fault;
      END_IF;
    ELSE
      bHeld := TRUE;
      refData.sts.bStepTimeout := TRUE;
    END_CASE;
  END_IF;
END_IF;

(* where to go next *)
IF bFinish AND nCur >= 1 THEN
  nS := nSLo + nCur - 1;
  nI := nLo + nCur - 1;
  aStep[nI].bActive := FALSE;
  nNx := INT_TO_DINT(aStepSet[nS].nNext);
  IF nNx < 0 OR nNx > nN OR (nNx > 0 AND nNx <= nCur AND aStepSet[nS].nLoops <= 0) THEN
    refData.sts.bRecipeBad := TRUE;  (* changed while running: refuse it, outputs safe *)
    refData.sts.nConfigStep := DINT_TO_INT(nCur);
    bGoing := FALSE;
    bStopping := FALSE;
    nCur := 0;
    eResult := E_StopReason.Fault;
  ELSIF nNx > 0 AND nNx <= nCur THEN
    IF aStep[nI].nLoopCount < aStepSet[nS].nLoops THEN
      aStep[nI].nLoopCount := aStep[nI].nLoopCount + 1;
      nP := nNx;
    ELSE
      aStep[nI].nLoopCount := 0;
      nP := nCur + 1;
    END_IF;
  ELSIF nNx > 0 THEN
    nP := nNx;
  ELSE
    nP := nCur + 1;
  END_IF;
END_IF;
IF bToStop THEN
  bStopping := TRUE;
  bHeld := FALSE;
  IF nCur >= 1 THEN
    aStep[nLo + nCur - 1].bActive := FALSE;
  END_IF;
  IF refData.set.nStopStep >= 1 AND INT_TO_DINT(refData.set.nStopStep) <= nN THEN
    nP := INT_TO_DINT(refData.set.nStopStep);
  ELSE
    bEndNow := TRUE;
  END_IF;
END_IF;

(* enter the new step, passing skipped ones; past the last step = the end *)
IF bGoing AND nP > 0 AND NOT bEndNow THEN
  FOR nGuard := 0 TO nN DO        (* at most one pass over the recipe *)
    IF nP > nN THEN
      EXIT;
    END_IF;
    IF NOT aStepSet[nSLo + nP - 1].bSkip THEN
      EXIT;
    END_IF;
    nP := nP + 1;
  END_FOR;
  IF nP > nN THEN
    IF NOT bStopping THEN
      bDone := TRUE;
      nCycles := nCycles + 1;
      eResult := E_StopReason.Done;
    END_IF;
    bEndNow := TRUE;
  ELSE
    nCur := nP;
    aStep[nLo + nP - 1].bActive := TRUE;
    tStepEl := T#0s;
    tTmo := T#0s;
  END_IF;
END_IF;
IF bEndNow AND bGoing AND eResult = E_StopReason.None THEN
  IF bStopping AND eStopWhy <> E_StopReason.None THEN
    eResult := eStopWhy;          (* the stop steps have run (or a stop with none) *)
  ELSE
    eResult := E_StopReason.Manual;
  END_IF;
END_IF;
IF eResult <> E_StopReason.None THEN
  refData.sts.eLastResult := eResult;
END_IF;
IF bEndNow THEN
  IF nCur >= 1 THEN
    aStep[nLo + nCur - 1].bActive := FALSE;
  END_IF;
  bGoing := FALSE;
  bStopping := FALSE;
  bHeld := FALSE;
  bHmiPause := FALSE;
  nCur := 0;
END_IF;
IF NOT bGoing THEN
  nCur := 0;
  bHeld := FALSE;
  refData.sts.bStepTimeout := FALSE;
END_IF;
refData.sts.bPaused := bGoing AND (bPause OR bHmiPause);

(* outputs: the step's pattern, the pause pattern, or all off *)
IF NOT bGoing OR nCur < 1 THEN
  nPattern := DWORD#0;
ELSIF refData.sts.bPaused OR bHeld THEN
  nPattern := refData.set.nPauseOutputs;
ELSE
  nPattern := aStepSet[nSLo + nCur - 1].nOutputs;
END_IF;
FOR nJ := nOLo TO nOHi DO
  IF nJ - nOLo < 32 THEN
    aOutputs[nJ] := (SHR(nPattern, DINT_TO_INT(nJ - nOLo)) AND DWORD#16#1) <> DWORD#0;
  ELSE
    aOutputs[nJ] := FALSE;
  END_IF;
END_FOR;
bBusy := bGoing;
nCurrentStep := DINT_TO_INT(nCur);
IF bGoing AND nCur >= 1 THEN
  nS := nSLo + nCur - 1;
  refData.sts.tElapsed := tStepEl;
  IF aStepSet[nS].tDuration > tStepEl THEN
    tRemaining := aStepSet[nS].tDuration - tStepEl;
  ELSE
    tRemaining := T#0s;
  END_IF;
ELSE
  refData.sts.tElapsed := T#0s;
  tRemaining := T#0s;
END_IF;
refData.sts.tRemaining := tRemaining;
refData.sts.nActiveStep := nCurrentStep;
refData.sts.bBusy := bGoing;
refData.sts.bStopping := bStopping;
refData.sts.nCycles := nCycles;
IF NOT refData.sts.bRecipeBad THEN
  refData.sts.nConfigStep := 0;
END_IF;

(* errors *)
bError := refData.sts.bRecipeBad OR refData.sts.bStepTimeout OR NOT bRowsOk;
bWarning := NOT bError AND (NOT bOkSet OR refData.sts.bRefused);
IF refData.sts.bRecipeBad OR NOT bRowsOk THEN
  eErrorId := E_UtError.RecipeBad;
ELSIF refData.sts.bStepTimeout THEN
  eErrorId := E_UtError.StepTimeout;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bGoing THEN
  eState := E_State.Idle;
ELSIF refData.sts.bPaused THEN
  eState := E_State.Held;
ELSIF bStopping THEN
  eState := E_State.Stopping;
ELSE
  eState := E_State.Running;
  IF nCur >= 1 THEN               (* IEC AND does not short-circuit: index only a real step *)
    IF aStepSet[nSLo + nCur - 1].bWaitCond AND NOT aStep[nLo + nCur - 1].bCond AND tRemaining <= T#0s THEN
      eState := E_State.Waiting;
    END_IF;
  END_IF;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK