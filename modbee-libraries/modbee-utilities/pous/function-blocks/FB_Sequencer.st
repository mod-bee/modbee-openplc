(* FB_Sequencer — a start / stop chain: conveyors, crushing, process trains.
Tables the project declares (VAR_IN_OUT, the same size, at most 32): aStepSettings (each machine's settings, in START
order) and aSteps (each machine's live row: the block writes bRunCommand, the project writes bRunFeedback and bMachineReady from
the machine, e.g. m1.Request(bRun := aSteps[1].bRunCommand, bPause := FALSE); aSteps[1].bRunFeedback := m1.bIsRunning;
aSteps[1].bMachineReady := m1.bIsReady).
bRun (held) starts it and its drop stops it; bStart / bStop are edges; bInterlock FALSE = bAbortWhileHeld; bPermissive FALSE
refuses a start. A start runs the steps one at a time: a step's bRunCommand goes on, its bRunFeedback must prove within
tFeedbackTimeout, then tNextStartDelay passes before the next step (bNoFeedbackFitted: proved by the delay alone; bSkipStep: not
started). A stop runs them per set.eStopOrder (Reverse: last started first stopped; AllAtOnce; Forward), each
waiting for its feedback to go and then its tNextStopDelay. A step losing its feedback while running, or failing to
prove at start, is a fault (FeedbackLost / NoFeedback) and set.eWhenStepLost decides what stops: Cascade (the failed step
and every step after it at once, then the rest in reverse), StopAll, DownstreamOnly (the steps before it keep
running: sts.eChainState Partial). A step whose feedback will not go when stopped holds the stop there and raises Stuck
once its timeout has passed; bAbortWhileHeld is the way out. bPause pauses a START (never a stop). bAbortWhileHeld (a level) drops
every bRunCommand at once.
Auto restart (set.bAutoRestart): after a fault stop it starts again by itself once every step is ready and bRun is
still TRUE, after set.tAutoRestartAfter (bAutoRestartPending on: wire it to a pre-start siren), at most set.nMaxRetriesBeforeLockout times in
set.tRetryCountWindow. A stop or abort cancels the run request, so it never restarts by itself after those.
Nothing is kept over a power cut but the settings: the chain comes back idle with every bRunCommand off and must be
started again. Faults clear on a start, a stop or a reset. Kept (a retained last-good copy, a bad write put back):
set, and the step rows packed into two DWORDs each (the times in 100 ms steps up to 109 min). *)

FUNCTION_BLOCK FB_Sequencer EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL; (* held run request: its rise starts it, it must stay on for an auto restart *)
    bStart : BOOL R_EDGE; (* rising edge: start the chain *)
    bStop : BOOL R_EDGE; (* rising edge: stop the chain *)
    bAbortWhileHeld : BOOL; (* level: everything off at once (e.g. NOT e-stop healthy) *)
    bPause : BOOL; (* pause a start where it is *)
    bResetFaults : BOOL R_EDGE; (* clear the fault *)
    bInterlock : BOOL := TRUE; (* FALSE = abort *)
    bPermissive : BOOL := TRUE; (* FALSE refuses a start *)
    refData : REFERENCE TO ST_SequencerData; (* the block's record *)
  END_VAR
  VAR_IN_OUT
    aStepSettings : ARRAY [*] OF ST_SEQSTEPSET; (* each machine's settings, in start order *)
    aSteps : ARRAY [*] OF ST_SEQSTEP; (* each machine's live row: the block writes bRunCommand, the project bRunFeedback and bMachineReady *)
  END_VAR
  VAR_OUTPUT
    bAllRunning : BOOL; (* every step up *)
    bInTransition : BOOL; (* starting, held or stopping *)
    nCurrentStep : INT; (* the step being started or stopped (0 = none) *)
    bAutoRestartPending : BOOL; (* auto restart countdown: wire to a pre-start siren *)
  END_VAR
  VAR RETAIN
    stKept : ST_SequencerSet;
    aKeptStep : ARRAY [1..64] OF DWORD; (* two per step *)
    nKeptRows : INT;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
    cMaxRows : DINT := 32;
  END_VAR
  VAR
    tPrev : TIME;
    bRunPrev : BOOL;
    nRsCount : INT;
    tRsWinAt : TIME;
    bRsLocked : BOOL;
    bRunReq : BOOL; (* the chain is wanted running (a start sets it, a stop or abort clears it) *)
    eMd : E_SeqMode;
    nCur : DINT; (* the step being started or stopped (0 = none) *)
    nSub : INT; (* 0 waiting for the feedback, 1 waiting the delay *)
    tAcc : TIME; (* time in the delay *)
    bSeqStop : BOOL; (* stopping one step at a time *)
    bFwdStop : BOOL; (* ... first started, first stopped *)
    bStartSeen : BOOL;
    bStopSeen : BOOL;
    bResetSeen : BOOL;
    bArmedPrev : BOOL;
    tRsAcc : TIME;
    eFlt : E_UtError; (* the machine fault shown *)
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bRowsOk : BOOL;
    bTooMany : BOOL;
    tScan : TIME;
    nLo : DINT;
    nSLo : DINT;
    nN : DINT;
    nI : DINT;
    nR : DINT;
    nS : DINT;
    nK : DINT;
    nKS : DINT;
    nGuard : DINT;
    bStartReq : BOOL;
    bStopReq : BOOL;
    bResetReq : BOOL;
    nFailAt : DINT;
    bFailTimeout : BOOL;
    bAnyOn : BOOL;
    bAnyStopping : BOOL;
    bAllReady : BOOL;
    bArmed : BOOL;
    nRun : DINT;
    bCfgSet : BOOL;
    nCfgAt : DINT;
    bAbortNow : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_SequencerSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.eStopOrder = E_SeqStopMode.Reverse OR stS.eStopOrder = E_SeqStopMode.AllAtOnce
          OR stS.eStopOrder = E_SeqStopMode.Forward) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eWhenStepLost = E_SeqLoss.Cascade OR stS.eWhenStepLost = E_SeqLoss.StopAll
             OR stS.eWhenStepLost = E_SeqLoss.DownstreamOnly) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.tAutoRestartAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SequencerSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* one step's settings are usable and fit the kept form *)
METHOD PRIVATE RowWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  RowWhy := E_UtError.None;
  IF NOT (stS.tNextStartDelay >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tNextStartDelay) / 100 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tNextStopDelay >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tNextStopDelay) / 100 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tFeedbackTimeout >= T#0s) THEN
    RowWhy := E_UtError.TimeBad;
  ELSIF NOT (TIME_TO_LINT(stS.tFeedbackTimeout) / 100 <= 16#FFFF) THEN
    RowWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE RowOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  RowOk := RowWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PRIVATE Pack : BOOL
  VAR_INPUT
    nRow : DINT;
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  aKeptStep[2 * nRow - 1] := LINT_TO_DWORD(TIME_TO_LINT(stS.tNextStartDelay) / 100)
                             OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tNextStopDelay) / 100), 16);
  aKeptStep[2 * nRow] := LINT_TO_DWORD(TIME_TO_LINT(stS.tFeedbackTimeout) / 100) OR SHL(BOOL_TO_DWORD(stS.bSkipStep), 16)
                         OR SHL(BOOL_TO_DWORD(stS.bNoFeedbackFitted), 17);
  Pack := TRUE;
END_METHOD

METHOD PRIVATE Unpack : BOOL
  VAR_INPUT
    nRow : DINT;
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  stS.tNextStartDelay := LINT_TO_TIME(DWORD_TO_LINT(aKeptStep[2 * nRow - 1] AND DWORD#16#FFFF) * 100);
  stS.tNextStopDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(aKeptStep[2 * nRow - 1], 16)) * 100);
  stS.tFeedbackTimeout := LINT_TO_TIME(DWORD_TO_LINT(aKeptStep[2 * nRow] AND DWORD#16#FFFF) * 100);
  stS.bSkipStep := (aKeptStep[2 * nRow] AND DWORD#16#10000) <> DWORD#0;
  stS.bNoFeedbackFitted := (aKeptStep[2 * nRow] AND DWORD#16#20000) <> DWORD#0;
  Unpack := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
nLo := LOWER_BOUND(aSteps, 1);
nSLo := LOWER_BOUND(aStepSettings, 1);
nN := MIN(UPPER_BOUND(aSteps, 1) - nLo + 1, UPPER_BOUND(aStepSettings, 1) - nSLo + 1);
bTooMany := nN > cMaxRows;
IF bTooMany THEN
  nN := cMaxRows;                 (* up to 32 steps; more: a config fault *)
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nN, INT_TO_DINT(nKeptRows)) DO
      Unpack(nRow := nI, stS := aStepSettings[nSLo + nI - 1]);
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  (* first scan, also after a power cut: stopped and safe *)
  tPrev := tNow;
  bRunPrev := bRun;               (* a bRun held over a power cut is not a new start *)
  FOR nI := 1 TO nN DO
    aSteps[nLo + nI - 1].bRunCommand := FALSE;
    aSteps[nLo + nI - 1].eStepState := E_SeqStepState.Off;
    aSteps[nLo + nI - 1].tElapsedTime := T#0s;
  END_FOR;
  eMd := E_SeqMode.Idle;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
nCfgAt := 0;
FOR nI := 1 TO nN DO
  nS := nSLo + nI - 1;
  IF RowOk(stS := aStepSettings[nS]) THEN
    Pack(nRow := nI, stS := aStepSettings[nS]);
  ELSIF nI <= INT_TO_DINT(nKeptRows) THEN
    refData.sts.eSettingRefusedErrorId := RowWhy(stS := aStepSettings[nS]);
    Unpack(nRow := nI, stS := aStepSettings[nS]);
    refData.sts.bSettingRefused := TRUE;
  ELSE
    bRowsOk := FALSE;
    IF nCfgAt = 0 THEN nCfgAt := nI; END_IF;
  END_IF;
END_FOR;
IF bRowsOk AND nN > INT_TO_DINT(nKeptRows) THEN
  nKeptRows := DINT_TO_INT(nN);
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
bStopReq := bStop OR (refData.bCmdStop AND NOT bStopSeen) OR (NOT bRun AND bRunPrev);
bRunPrev := bRun;
IF NOT bPermissive THEN
  bStartReq := FALSE;             (* a start is refused *)
END_IF;
bStopSeen := refData.bCmdStop;
refData.bCmdStop := FALSE;
bResetReq := bResetFaults OR SystemReset() OR (refData.bCmdResetFaults AND NOT bResetSeen);
bResetSeen := refData.bCmdResetFaults;
refData.bCmdResetFaults := FALSE;
nFailAt := 0;
bFailTimeout := FALSE;
bCfgSet := NOT bOkSet OR bTooMany OR NOT bRowsOk;

bAbortNow := bAbortWhileHeld OR NOT bInterlock;
IF bAbortNow THEN
  (* everything off at once; no restart by itself *)
  FOR nI := 1 TO nN DO
    aSteps[nLo + nI - 1].bRunCommand := FALSE;
    aSteps[nLo + nI - 1].eStepState := E_SeqStepState.Off;
  END_FOR;
  eMd := E_SeqMode.Aborted;
  bRunReq := FALSE;
  nCur := 0;
  nSub := 0;
  bSeqStop := FALSE;
ELSE
  (* any start, stop or reset clears the faults *)
  IF bStartReq OR bStopReq OR bResetReq THEN
    refData.sts.bStepTimedOut := FALSE;
    refData.sts.bStepLostFeedback := FALSE;
    refData.sts.bSettingBad := FALSE;
    refData.sts.nFirstFaultStep := 0;
    refData.sts.bSettingRefused := FALSE;
    refData.sts.eSettingRefusedErrorId := E_UtError.None;
    FOR nI := 1 TO nN DO
      IF aSteps[nLo + nI - 1].eStepState = E_SeqStepState.Fault THEN
        aSteps[nLo + nI - 1].eStepState := E_SeqStepState.Off;
      END_IF;
    END_FOR;
  END_IF;
  IF bStopReq THEN
    bRunReq := FALSE;
    IF eMd = E_SeqMode.Aborted THEN
      eMd := E_SeqMode.Idle;
    END_IF;
    IF eMd <> E_SeqMode.Idle AND (eMd <> E_SeqMode.Stopping OR NOT bSeqStop) THEN
      IF refData.set.eStopOrder = E_SeqStopMode.AllAtOnce THEN
        FOR nI := 1 TO nN DO
          nR := nLo + nI - 1;
          IF aSteps[nR].bRunCommand THEN
            aSteps[nR].bRunCommand := FALSE;
            aSteps[nR].eStepState := E_SeqStepState.Stopping;
            aSteps[nR].tElapsedTime := T#0s;
          END_IF;
        END_FOR;
        bSeqStop := FALSE;
      ELSE
        bSeqStop := TRUE;
        bFwdStop := refData.set.eStopOrder = E_SeqStopMode.Forward;
      END_IF;
      nCur := 0;
      nSub := 0;
      eMd := E_SeqMode.Stopping;
    END_IF;
  ELSIF bStartReq AND eMd <> E_SeqMode.Starting AND eMd <> E_SeqMode.Held AND eMd <> E_SeqMode.Running THEN
    nRun := 0;
    FOR nI := 1 TO nN DO
      IF NOT aStepSettings[nSLo + nI - 1].bSkipStep OR aSteps[nLo + nI - 1].bRunCommand THEN
        nRun := nRun + 1;
      END_IF;
    END_FOR;
    IF bCfgSet OR nRun = 0 THEN
      refData.sts.bSettingBad := TRUE;   (* refused *)
      IF eMd = E_SeqMode.Aborted THEN
        eMd := E_SeqMode.Idle;
      END_IF;
    ELSE
      bRunReq := TRUE;
      eMd := E_SeqMode.Starting;
      nCur := 1;
      nSub := 0;
      bSeqStop := FALSE;
    END_IF;
  ELSIF bResetReq AND eMd = E_SeqMode.Aborted THEN
    eMd := E_SeqMode.Idle;
  END_IF;

  (* supervision: steps stopping, and running steps losing their feedback *)
  FOR nI := 1 TO nN DO
    nR := nLo + nI - 1;
    nS := nSLo + nI - 1;
    IF aSteps[nR].eStepState = E_SeqStepState.Stopping THEN
      aSteps[nR].tElapsedTime := aSteps[nR].tElapsedTime + tScan;
      IF NOT aSteps[nR].bRunFeedback OR aStepSettings[nS].bNoFeedbackFitted THEN
        aSteps[nR].eStepState := E_SeqStepState.Off;
      ELSIF aStepSettings[nS].tFeedbackTimeout > T#0s AND aSteps[nR].tElapsedTime >= aStepSettings[nS].tFeedbackTimeout THEN
        refData.sts.bStepTimedOut := TRUE;
        IF refData.sts.nFirstFaultStep = 0 THEN
          refData.sts.nFirstFaultStep := DINT_TO_INT(nI);
          eFlt := E_UtError.Stuck;
        END_IF;
      END_IF;
    ELSIF aSteps[nR].bRunCommand AND aSteps[nR].eStepState = E_SeqStepState.Running AND NOT aStepSettings[nS].bNoFeedbackFitted
          AND NOT aSteps[nR].bRunFeedback AND nFailAt = 0 THEN
      nFailAt := nI;
    END_IF;
  END_FOR;

  (* the start, one step at a time *)
  IF nFailAt = 0 AND (eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held) THEN
    IF bPause THEN
      eMd := E_SeqMode.Held;
    ELSE
      eMd := E_SeqMode.Starting;
      FOR nGuard := 0 TO nN DO    (* at most one pass over the chain *)
        IF eMd <> E_SeqMode.Starting THEN
          EXIT;
        END_IF;
        IF nCur > nN OR nCur < 1 THEN
          eMd := E_SeqMode.Running;
          nCur := 0;
          nSub := 0;
          EXIT;
        END_IF;
        nK := nLo + nCur - 1;
        nKS := nSLo + nCur - 1;
        IF nSub = 0 THEN
          IF aSteps[nK].bRunCommand AND aSteps[nK].eStepState = E_SeqStepState.Running THEN
            nCur := nCur + 1;     (* already running and proven *)
          ELSIF aStepSettings[nKS].bSkipStep AND NOT aSteps[nK].bRunCommand THEN
            aSteps[nK].eStepState := E_SeqStepState.Bypassed;
            nCur := nCur + 1;
          ELSE
            IF aSteps[nK].eStepState <> E_SeqStepState.Starting THEN
              aSteps[nK].bRunCommand := TRUE;
              aSteps[nK].eStepState := E_SeqStepState.Starting;
              aSteps[nK].tElapsedTime := T#0s;
            ELSE
              aSteps[nK].tElapsedTime := aSteps[nK].tElapsedTime + tScan;
            END_IF;
            IF aStepSettings[nKS].bNoFeedbackFitted OR aSteps[nK].bRunFeedback THEN
              aSteps[nK].eStepState := E_SeqStepState.Running;
              tAcc := T#0s;
              IF aStepSettings[nKS].tNextStartDelay > T#0s THEN
                nSub := 1;
                EXIT;
              END_IF;
              nCur := nCur + 1;
            ELSIF aStepSettings[nKS].tFeedbackTimeout > T#0s AND aSteps[nK].tElapsedTime >= aStepSettings[nKS].tFeedbackTimeout THEN
              nFailAt := nCur;
              bFailTimeout := TRUE;
              EXIT;
            ELSE
              EXIT;
            END_IF;
          END_IF;
        ELSE
          tAcc := tAcc + tScan;
          IF tAcc >= aStepSettings[nKS].tNextStartDelay THEN
            nCur := nCur + 1;
            nSub := 0;
          ELSE
            EXIT;
          END_IF;
        END_IF;
      END_FOR;
    END_IF;
  END_IF;

  (* the stop, one step at a time (never held) *)
  IF nFailAt = 0 AND eMd = E_SeqMode.Stopping AND bSeqStop THEN
    FOR nGuard := 0 TO nN + 1 DO  (* at most one pass over the chain *)
      IF NOT bSeqStop THEN
        EXIT;
      END_IF;
      IF nCur < 1 OR nCur > nN THEN
        nCur := 0;                (* the next step to stop *)
        IF bFwdStop THEN
          FOR nI := nN TO 1 BY -1 DO
            IF aSteps[nLo + nI - 1].bRunCommand THEN nCur := nI; END_IF;
          END_FOR;
        ELSE
          FOR nI := 1 TO nN DO
            IF aSteps[nLo + nI - 1].bRunCommand THEN nCur := nI; END_IF;
          END_FOR;
        END_IF;
        IF nCur = 0 THEN
          bSeqStop := FALSE;
          EXIT;
        END_IF;
        nK := nLo + nCur - 1;
        aSteps[nK].bRunCommand := FALSE;
        aSteps[nK].eStepState := E_SeqStepState.Stopping;
        aSteps[nK].tElapsedTime := T#0s;
        nSub := 0;
        EXIT;                     (* its feedback is checked from the next scan *)
      END_IF;
      nK := nLo + nCur - 1;
      nKS := nSLo + nCur - 1;
      IF nSub = 0 THEN
        IF aSteps[nK].eStepState = E_SeqStepState.Stopping THEN
          EXIT;                   (* still running down *)
        END_IF;
        nSub := 1;
        tAcc := T#0s;
        bAnyOn := FALSE;
        FOR nI := 1 TO nN DO
          bAnyOn := bAnyOn OR aSteps[nLo + nI - 1].bRunCommand;
        END_FOR;
        IF bAnyOn AND aStepSettings[nKS].tNextStopDelay > T#0s THEN
          EXIT;
        END_IF;
        nCur := 0;
      ELSE
        tAcc := tAcc + tScan;
        IF tAcc >= aStepSettings[nKS].tNextStopDelay THEN
          nCur := 0;
        ELSE
          EXIT;
        END_IF;
      END_IF;
    END_FOR;
  END_IF;

  (* a step lost its feedback, or did not prove at start *)
  IF nFailAt > 0 THEN
    nK := nLo + nFailAt - 1;
    IF bFailTimeout THEN
      refData.sts.bStepTimedOut := TRUE;
    ELSE
      refData.sts.bStepLostFeedback := TRUE;
    END_IF;
    IF refData.sts.nFirstFaultStep = 0 THEN
      refData.sts.nFirstFaultStep := DINT_TO_INT(nFailAt);
      IF bFailTimeout THEN eFlt := E_UtError.NoFeedback; ELSE eFlt := E_UtError.FeedbackLost; END_IF;
    END_IF;
    aSteps[nK].bRunCommand := FALSE;
    aSteps[nK].eStepState := E_SeqStepState.Fault;
    FOR nI := 1 TO nN DO
      nR := nLo + nI - 1;
      IF aSteps[nR].bRunCommand AND (nI > nFailAt OR refData.set.eWhenStepLost = E_SeqLoss.StopAll) THEN
        aSteps[nR].bRunCommand := FALSE;
        aSteps[nR].eStepState := E_SeqStepState.Stopping;
        aSteps[nR].tElapsedTime := T#0s;
      END_IF;
    END_FOR;
    CASE refData.set.eWhenStepLost OF
    E_SeqLoss.StopAll:
      bSeqStop := FALSE;
    E_SeqLoss.DownstreamOnly:
      IF eMd <> E_SeqMode.Stopping THEN
        bSeqStop := FALSE;
      END_IF;
    ELSE
      bSeqStop := TRUE;           (* the rest stop in reverse, the first after the failed step's stop delay *)
      bFwdStop := FALSE;
      nCur := nFailAt;
      nSub := 1;
      tAcc := T#0s;
    END_CASE;
    IF NOT bSeqStop THEN
      nCur := 0;
      nSub := 0;
    END_IF;
    eMd := E_SeqMode.Stopping;
  END_IF;

  (* the stop is over once nothing is running down *)
  IF eMd = E_SeqMode.Stopping AND NOT bSeqStop THEN
    bAnyOn := FALSE;
    bAnyStopping := FALSE;
    FOR nI := 1 TO nN DO
      nR := nLo + nI - 1;
      bAnyOn := bAnyOn OR aSteps[nR].bRunCommand;
      bAnyStopping := bAnyStopping OR aSteps[nR].eStepState = E_SeqStepState.Stopping;
    END_FOR;
    IF NOT bAnyStopping THEN
      nCur := 0;
      IF bAnyOn THEN eMd := E_SeqMode.Partial; ELSE eMd := E_SeqMode.Idle; END_IF;
    END_IF;
  END_IF;
END_IF;
IF bCfgSet THEN
  refData.sts.bSettingBad := TRUE; (* a bad setting is shown as a config fault while it lasts *)
END_IF;
refData.sts.nBadSettingStep := DINT_TO_INT(nCfgAt);

(* auto restart: wanted running, bRun held, every step ready *)
bArmed := FALSE;
IF bResetReq OR bStartReq OR (nRsCount > 0 AND tNow - tRsWinAt >= refData.set.tRetryCountWindow) THEN
  nRsCount := 0;
  bRsLocked := FALSE;
END_IF;
IF refData.set.bAutoRestart AND bRunReq AND bRun AND NOT bAbortNow AND bPermissive AND NOT bPause AND NOT bCfgSet
   AND NOT bRsLocked AND (eMd = E_SeqMode.Idle OR eMd = E_SeqMode.Partial) THEN
  bAllReady := TRUE;
  FOR nI := 1 TO nN DO
    nR := nLo + nI - 1;
    IF NOT (aStepSettings[nSLo + nI - 1].bSkipStep AND NOT aSteps[nR].bRunCommand) THEN
      bAllReady := bAllReady AND (aSteps[nR].bMachineReady OR aSteps[nR].bRunFeedback);
    END_IF;
    IF aSteps[nR].eStepState = E_SeqStepState.Stopping THEN
      bAllReady := FALSE;
    END_IF;
  END_FOR;
  bArmed := bAllReady;
END_IF;
IF bArmed AND bArmedPrev THEN
  tRsAcc := tRsAcc + tScan;
ELSE
  tRsAcc := T#0s;
END_IF;
bArmedPrev := bArmed;
bAutoRestartPending := FALSE;
refData.sts.tAutoRestartTimeLeft := T#0s;
IF bArmed THEN
  IF tRsAcc >= refData.set.tAutoRestartAfter THEN
    refData.sts.bStepTimedOut := FALSE;
    refData.sts.bStepLostFeedback := FALSE;
    refData.sts.bSettingBad := FALSE;
    refData.sts.nFirstFaultStep := 0;
    FOR nI := 1 TO nN DO
      IF aSteps[nLo + nI - 1].eStepState = E_SeqStepState.Fault THEN
        aSteps[nLo + nI - 1].eStepState := E_SeqStepState.Off;
      END_IF;
    END_FOR;
    eMd := E_SeqMode.Starting;
    nCur := 1;
    nSub := 0;
    bSeqStop := FALSE;
    bArmedPrev := FALSE;
    IF nRsCount = 0 THEN
      tRsWinAt := tNow;
    END_IF;
    nRsCount := nRsCount + 1;
    IF nRsCount >= refData.set.nMaxRetriesBeforeLockout THEN
      bRsLocked := TRUE;          (* no more by itself until a reset or a start *)
    END_IF;
  ELSE
    bAutoRestartPending := TRUE;
    refData.sts.tAutoRestartTimeLeft := refData.set.tAutoRestartAfter - tRsAcc;
  END_IF;
END_IF;

(* step states: idle steps show Off, or Bypassed; each step's countdown *)
FOR nI := 1 TO nN DO
  nR := nLo + nI - 1;
  nS := nSLo + nI - 1;
  IF NOT aSteps[nR].bRunCommand AND aSteps[nR].eStepState <> E_SeqStepState.Stopping AND aSteps[nR].eStepState <> E_SeqStepState.Fault THEN
    IF aStepSettings[nS].bSkipStep THEN
      aSteps[nR].eStepState := E_SeqStepState.Bypassed;
    ELSE
      aSteps[nR].eStepState := E_SeqStepState.Off;
    END_IF;
  END_IF;
  aSteps[nR].tTimeLeft := T#0s;
  IF (aSteps[nR].eStepState = E_SeqStepState.Starting OR aSteps[nR].eStepState = E_SeqStepState.Stopping)
     AND aStepSettings[nS].tFeedbackTimeout > aSteps[nR].tElapsedTime THEN
    aSteps[nR].tTimeLeft := aStepSettings[nS].tFeedbackTimeout - aSteps[nR].tElapsedTime;
  END_IF;
END_FOR;
refData.sts.tTimeLeft := T#0s;
IF nSub = 1 AND nCur >= 1 AND nCur <= nN THEN
  nK := nLo + nCur - 1;
  nKS := nSLo + nCur - 1;
  IF (eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held) AND aStepSettings[nKS].tNextStartDelay > tAcc THEN
    aSteps[nK].tTimeLeft := aStepSettings[nKS].tNextStartDelay - tAcc;
    refData.sts.tTimeLeft := aSteps[nK].tTimeLeft;
  ELSIF eMd = E_SeqMode.Stopping AND bSeqStop AND aStepSettings[nKS].tNextStopDelay > tAcc THEN
    aSteps[nK].tTimeLeft := aStepSettings[nKS].tNextStopDelay - tAcc;
    refData.sts.tTimeLeft := aSteps[nK].tTimeLeft;
  END_IF;
END_IF;

(* outputs and status *)
bAllRunning := eMd = E_SeqMode.Running;
bInTransition := eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held OR eMd = E_SeqMode.Stopping;
IF eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held OR (eMd = E_SeqMode.Stopping AND bSeqStop) THEN
  nCurrentStep := DINT_TO_INT(nCur);
ELSE
  nCurrentStep := 0;
END_IF;
IF NOT (refData.sts.bStepTimedOut OR refData.sts.bStepLostFeedback OR refData.sts.bSettingBad) THEN
  refData.sts.nFirstFaultStep := 0;
END_IF;
refData.sts.eChainState := eMd;
refData.sts.nRetriesUsed := nRsCount;
refData.sts.bAutoRestartLocked := bRsLocked;
bError := refData.sts.bStepTimedOut OR refData.sts.bStepLostFeedback OR refData.sts.bSettingBad;
bWarning := NOT bError AND (bAutoRestartPending OR refData.sts.bSettingRefused);
IF refData.sts.bSettingBad THEN
  IF bTooMany OR NOT bRowsOk THEN
    eErrorId := E_UtError.RecipeBad;
  ELSIF NOT bOkSet THEN
    eErrorId := E_UtError.BadSetting;
  ELSE
    eErrorId := E_UtError.NoChannels;  (* nothing to run: every step bypassed, or none *)
  END_IF;
ELSIF refData.sts.bStepTimedOut OR refData.sts.bStepLostFeedback THEN
  eErrorId := eFlt;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
CASE eMd OF
  E_SeqMode.Starting: eState := E_State.Starting;
  E_SeqMode.Running, E_SeqMode.Partial: eState := E_State.Running;
  E_SeqMode.Stopping: eState := E_State.Stopping;
  E_SeqMode.Held: eState := E_State.Held;
ELSE
  eState := E_State.Off;
END_CASE;
IF bError THEN
  eState := E_State.Fault;
ELSIF bAutoRestartPending THEN
  eState := E_State.Waiting;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK