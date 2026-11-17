(* FB_Sequencer — a start / stop chain: conveyors, crushing, process trains.
Tables the project declares (VAR_IN_OUT, the same size, at most 32): aStepSet (each machine's settings, in START
order) and aStep (each machine's live row: the block writes bCmd, the project writes bFeedback and bReady from
the machine, e.g. m1.Request(bRun := aStep[1].bCmd, bHold := FALSE); aStep[1].bFeedback := m1.bIsRunning;
aStep[1].bReady := m1.bIsReady).
bRun (held) starts it and its drop stops it; bStart / bStop are edges; bInterlock FALSE = bAbort; bPermissive FALSE
refuses a start. A start runs the steps one at a time: a step's bCmd goes on, its bFeedback must prove within
tTimeout, then tStartDelay passes before the next step (bNoFeedback: proved by the delay alone; bBypass: not
started). A stop runs them per set.eStopMode (Reverse: last started first stopped; AllAtOnce; Forward), each
waiting for its feedback to go and then its tStopDelay. A step losing its feedback while running, or failing to
prove at start, is a fault (FeedbackLost / NoFeedback) and set.eOnLoss decides what stops: Cascade (the failed step
and every step after it at once, then the rest in reverse), StopAll, DownstreamOnly (the steps before it keep
running: sts.eMode Partial). A step whose feedback will not go when stopped holds the stop there and raises Stuck
once its timeout has passed; bAbort is the way out. bHold pauses a START (never a stop). bAbort (a level) drops
every bCmd at once.
Auto restart (set.bAutoRestart): after a fault stop it starts again by itself once every step is ready and bRun is
still TRUE, after set.tRestartDelay (bRestarting on: wire it to a pre-start siren), at most set.nMaxRetries times in
set.tRetryWindow. A stop or abort cancels the run request, so it never restarts by itself after those.
Nothing is kept over a power cut but the settings: the chain comes back idle with every bCmd off and must be
started again. Faults clear on a start, a stop or a reset. Kept (a retained last-good copy, a bad write put back):
set, and the step rows packed into two DWORDs each (the times in 100 ms steps up to 109 min). *)

FUNCTION_BLOCK FB_Sequencer EXTENDS FB_Object
  VAR_INPUT
    bRun : BOOL; (* held run request: its rise starts it, it must stay on for an auto restart *)
    bStart : BOOL R_EDGE;
    bStop : BOOL R_EDGE;
    bAbort : BOOL; (* level: everything off at once (e.g. NOT e-stop healthy) *)
    bHold : BOOL; (* pause a start where it is *)
    bReset : BOOL R_EDGE; (* clear the fault *)
    bInterlock : BOOL := TRUE; (* FALSE = abort *)
    bPermissive : BOOL := TRUE; (* FALSE refuses a start *)
    refData : REFERENCE TO ST_SequencerData;
  END_VAR
  VAR_IN_OUT
    aStepSet : ARRAY [*] OF ST_SEQSTEPSET;
    aStep : ARRAY [*] OF ST_SEQSTEP;
  END_VAR
  VAR_OUTPUT
    bRunning : BOOL; (* every step up *)
    bBusy : BOOL; (* starting, held or stopping *)
    nCurrentStep : INT; (* the step being started or stopped (0 = none) *)
    bRestarting : BOOL; (* auto restart countdown: wire to a pre-start siren *)
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


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SequencerSet;
  END_VAR
  SetOk := (stS.eStopMode = E_SeqStopMode.Reverse OR stS.eStopMode = E_SeqStopMode.AllAtOnce
            OR stS.eStopMode = E_SeqStopMode.Forward)
           AND (stS.eOnLoss = E_SeqLoss.Cascade OR stS.eOnLoss = E_SeqLoss.StopAll
                OR stS.eOnLoss = E_SeqLoss.DownstreamOnly)
           AND stS.tRestartDelay >= T#0s AND stS.nMaxRetries >= 0 AND stS.tRetryWindow >= T#0s;
END_METHOD

(* one step's settings are usable and fit the kept form *)
METHOD PRIVATE RowOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  RowOk := stS.tStartDelay >= T#0s AND TIME_TO_LINT(stS.tStartDelay) / 100 <= 16#FFFF
           AND stS.tStopDelay >= T#0s AND TIME_TO_LINT(stS.tStopDelay) / 100 <= 16#FFFF
           AND stS.tTimeout >= T#0s AND TIME_TO_LINT(stS.tTimeout) / 100 <= 16#FFFF;
END_METHOD

METHOD PRIVATE Pack : BOOL
  VAR_INPUT
    nRow : DINT;
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  aKeptStep[2 * nRow - 1] := LINT_TO_DWORD(TIME_TO_LINT(stS.tStartDelay) / 100)
                             OR SHL(LINT_TO_DWORD(TIME_TO_LINT(stS.tStopDelay) / 100), 16);
  aKeptStep[2 * nRow] := LINT_TO_DWORD(TIME_TO_LINT(stS.tTimeout) / 100) OR SHL(BOOL_TO_DWORD(stS.bBypass), 16)
                         OR SHL(BOOL_TO_DWORD(stS.bNoFeedback), 17);
  Pack := TRUE;
END_METHOD

METHOD PRIVATE Unpack : BOOL
  VAR_INPUT
    nRow : DINT;
    stS : REFERENCE TO ST_SeqStepSet;
  END_VAR
  stS.tStartDelay := LINT_TO_TIME(DWORD_TO_LINT(aKeptStep[2 * nRow - 1] AND DWORD#16#FFFF) * 100);
  stS.tStopDelay := LINT_TO_TIME(DWORD_TO_LINT(SHR(aKeptStep[2 * nRow - 1], 16)) * 100);
  stS.tTimeout := LINT_TO_TIME(DWORD_TO_LINT(aKeptStep[2 * nRow] AND DWORD#16#FFFF) * 100);
  stS.bBypass := (aKeptStep[2 * nRow] AND DWORD#16#10000) <> DWORD#0;
  stS.bNoFeedback := (aKeptStep[2 * nRow] AND DWORD#16#20000) <> DWORD#0;
  Unpack := TRUE;
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
bTooMany := nN > cMaxRows;
IF bTooMany THEN
  nN := cMaxRows;                 (* up to 32 steps; more: a config fault *)
END_IF;

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    FOR nI := 1 TO MIN(nN, INT_TO_DINT(nKeptRows)) DO
      Unpack(nRow := nI, stS := aStepSet[nSLo + nI - 1]);
    END_FOR;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  (* first scan, also after a power cut: stopped and safe *)
  tPrev := tNow;
  bRunPrev := bRun;               (* a bRun held over a power cut is not a new start *)
  FOR nI := 1 TO nN DO
    aStep[nLo + nI - 1].bCmd := FALSE;
    aStep[nLo + nI - 1].eState := E_SeqStepState.Off;
    aStep[nLo + nI - 1].tElapsed := T#0s;
  END_FOR;
  eMd := E_SeqMode.Idle;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bRowsOk := TRUE;
nCfgAt := 0;
FOR nI := 1 TO nN DO
  nS := nSLo + nI - 1;
  IF RowOk(stS := aStepSet[nS]) THEN
    Pack(nRow := nI, stS := aStepSet[nS]);
  ELSIF nI <= INT_TO_DINT(nKeptRows) THEN
    Unpack(nRow := nI, stS := aStepSet[nS]);
    refData.sts.bRefused := TRUE;
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
bResetReq := bReset OR SystemReset() OR (refData.bCmdReset AND NOT bResetSeen);
bResetSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;
nFailAt := 0;
bFailTimeout := FALSE;
bCfgSet := NOT bOkSet OR bTooMany OR NOT bRowsOk;

bAbortNow := bAbort OR NOT bInterlock;
IF bAbortNow THEN
  (* everything off at once; no restart by itself *)
  FOR nI := 1 TO nN DO
    aStep[nLo + nI - 1].bCmd := FALSE;
    aStep[nLo + nI - 1].eState := E_SeqStepState.Off;
  END_FOR;
  eMd := E_SeqMode.Aborted;
  bRunReq := FALSE;
  nCur := 0;
  nSub := 0;
  bSeqStop := FALSE;
ELSE
  (* any start, stop or reset clears the faults *)
  IF bStartReq OR bStopReq OR bResetReq THEN
    refData.sts.bFltTimeout := FALSE;
    refData.sts.bFltLoss := FALSE;
    refData.sts.bFltConfig := FALSE;
    refData.sts.nFaultStep := 0;
    refData.sts.bRefused := FALSE;
    FOR nI := 1 TO nN DO
      IF aStep[nLo + nI - 1].eState = E_SeqStepState.Fault THEN
        aStep[nLo + nI - 1].eState := E_SeqStepState.Off;
      END_IF;
    END_FOR;
  END_IF;
  IF bStopReq THEN
    bRunReq := FALSE;
    IF eMd = E_SeqMode.Aborted THEN
      eMd := E_SeqMode.Idle;
    END_IF;
    IF eMd <> E_SeqMode.Idle AND (eMd <> E_SeqMode.Stopping OR NOT bSeqStop) THEN
      IF refData.set.eStopMode = E_SeqStopMode.AllAtOnce THEN
        FOR nI := 1 TO nN DO
          nR := nLo + nI - 1;
          IF aStep[nR].bCmd THEN
            aStep[nR].bCmd := FALSE;
            aStep[nR].eState := E_SeqStepState.Stopping;
            aStep[nR].tElapsed := T#0s;
          END_IF;
        END_FOR;
        bSeqStop := FALSE;
      ELSE
        bSeqStop := TRUE;
        bFwdStop := refData.set.eStopMode = E_SeqStopMode.Forward;
      END_IF;
      nCur := 0;
      nSub := 0;
      eMd := E_SeqMode.Stopping;
    END_IF;
  ELSIF bStartReq AND eMd <> E_SeqMode.Starting AND eMd <> E_SeqMode.Held AND eMd <> E_SeqMode.Running THEN
    nRun := 0;
    FOR nI := 1 TO nN DO
      IF NOT aStepSet[nSLo + nI - 1].bBypass OR aStep[nLo + nI - 1].bCmd THEN
        nRun := nRun + 1;
      END_IF;
    END_FOR;
    IF bCfgSet OR nRun = 0 THEN
      refData.sts.bFltConfig := TRUE;   (* refused *)
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
    IF aStep[nR].eState = E_SeqStepState.Stopping THEN
      aStep[nR].tElapsed := aStep[nR].tElapsed + tScan;
      IF NOT aStep[nR].bFeedback OR aStepSet[nS].bNoFeedback THEN
        aStep[nR].eState := E_SeqStepState.Off;
      ELSIF aStepSet[nS].tTimeout > T#0s AND aStep[nR].tElapsed >= aStepSet[nS].tTimeout THEN
        refData.sts.bFltTimeout := TRUE;
        IF refData.sts.nFaultStep = 0 THEN
          refData.sts.nFaultStep := DINT_TO_INT(nI);
          eFlt := E_UtError.Stuck;
        END_IF;
      END_IF;
    ELSIF aStep[nR].bCmd AND aStep[nR].eState = E_SeqStepState.Running AND NOT aStepSet[nS].bNoFeedback
          AND NOT aStep[nR].bFeedback AND nFailAt = 0 THEN
      nFailAt := nI;
    END_IF;
  END_FOR;

  (* the start, one step at a time *)
  IF nFailAt = 0 AND (eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held) THEN
    IF bHold THEN
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
          IF aStep[nK].bCmd AND aStep[nK].eState = E_SeqStepState.Running THEN
            nCur := nCur + 1;     (* already running and proven *)
          ELSIF aStepSet[nKS].bBypass AND NOT aStep[nK].bCmd THEN
            aStep[nK].eState := E_SeqStepState.Bypassed;
            nCur := nCur + 1;
          ELSE
            IF aStep[nK].eState <> E_SeqStepState.Starting THEN
              aStep[nK].bCmd := TRUE;
              aStep[nK].eState := E_SeqStepState.Starting;
              aStep[nK].tElapsed := T#0s;
            ELSE
              aStep[nK].tElapsed := aStep[nK].tElapsed + tScan;
            END_IF;
            IF aStepSet[nKS].bNoFeedback OR aStep[nK].bFeedback THEN
              aStep[nK].eState := E_SeqStepState.Running;
              tAcc := T#0s;
              IF aStepSet[nKS].tStartDelay > T#0s THEN
                nSub := 1;
                EXIT;
              END_IF;
              nCur := nCur + 1;
            ELSIF aStepSet[nKS].tTimeout > T#0s AND aStep[nK].tElapsed >= aStepSet[nKS].tTimeout THEN
              nFailAt := nCur;
              bFailTimeout := TRUE;
              EXIT;
            ELSE
              EXIT;
            END_IF;
          END_IF;
        ELSE
          tAcc := tAcc + tScan;
          IF tAcc >= aStepSet[nKS].tStartDelay THEN
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
            IF aStep[nLo + nI - 1].bCmd THEN nCur := nI; END_IF;
          END_FOR;
        ELSE
          FOR nI := 1 TO nN DO
            IF aStep[nLo + nI - 1].bCmd THEN nCur := nI; END_IF;
          END_FOR;
        END_IF;
        IF nCur = 0 THEN
          bSeqStop := FALSE;
          EXIT;
        END_IF;
        nK := nLo + nCur - 1;
        aStep[nK].bCmd := FALSE;
        aStep[nK].eState := E_SeqStepState.Stopping;
        aStep[nK].tElapsed := T#0s;
        nSub := 0;
        EXIT;                     (* its feedback is checked from the next scan *)
      END_IF;
      nK := nLo + nCur - 1;
      nKS := nSLo + nCur - 1;
      IF nSub = 0 THEN
        IF aStep[nK].eState = E_SeqStepState.Stopping THEN
          EXIT;                   (* still running down *)
        END_IF;
        nSub := 1;
        tAcc := T#0s;
        bAnyOn := FALSE;
        FOR nI := 1 TO nN DO
          bAnyOn := bAnyOn OR aStep[nLo + nI - 1].bCmd;
        END_FOR;
        IF bAnyOn AND aStepSet[nKS].tStopDelay > T#0s THEN
          EXIT;
        END_IF;
        nCur := 0;
      ELSE
        tAcc := tAcc + tScan;
        IF tAcc >= aStepSet[nKS].tStopDelay THEN
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
      refData.sts.bFltTimeout := TRUE;
    ELSE
      refData.sts.bFltLoss := TRUE;
    END_IF;
    IF refData.sts.nFaultStep = 0 THEN
      refData.sts.nFaultStep := DINT_TO_INT(nFailAt);
      IF bFailTimeout THEN eFlt := E_UtError.NoFeedback; ELSE eFlt := E_UtError.FeedbackLost; END_IF;
    END_IF;
    aStep[nK].bCmd := FALSE;
    aStep[nK].eState := E_SeqStepState.Fault;
    FOR nI := 1 TO nN DO
      nR := nLo + nI - 1;
      IF aStep[nR].bCmd AND (nI > nFailAt OR refData.set.eOnLoss = E_SeqLoss.StopAll) THEN
        aStep[nR].bCmd := FALSE;
        aStep[nR].eState := E_SeqStepState.Stopping;
        aStep[nR].tElapsed := T#0s;
      END_IF;
    END_FOR;
    CASE refData.set.eOnLoss OF
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
      bAnyOn := bAnyOn OR aStep[nR].bCmd;
      bAnyStopping := bAnyStopping OR aStep[nR].eState = E_SeqStepState.Stopping;
    END_FOR;
    IF NOT bAnyStopping THEN
      nCur := 0;
      IF bAnyOn THEN eMd := E_SeqMode.Partial; ELSE eMd := E_SeqMode.Idle; END_IF;
    END_IF;
  END_IF;
END_IF;
IF bCfgSet THEN
  refData.sts.bFltConfig := TRUE; (* a bad setting is shown as a config fault while it lasts *)
END_IF;
refData.sts.nConfigStep := DINT_TO_INT(nCfgAt);

(* auto restart: wanted running, bRun held, every step ready *)
bArmed := FALSE;
IF bResetReq OR bStartReq OR (nRsCount > 0 AND tNow - tRsWinAt >= refData.set.tRetryWindow) THEN
  nRsCount := 0;
  bRsLocked := FALSE;
END_IF;
IF refData.set.bAutoRestart AND bRunReq AND bRun AND NOT bAbortNow AND bPermissive AND NOT bHold AND NOT bCfgSet
   AND NOT bRsLocked AND (eMd = E_SeqMode.Idle OR eMd = E_SeqMode.Partial) THEN
  bAllReady := TRUE;
  FOR nI := 1 TO nN DO
    nR := nLo + nI - 1;
    IF NOT (aStepSet[nSLo + nI - 1].bBypass AND NOT aStep[nR].bCmd) THEN
      bAllReady := bAllReady AND (aStep[nR].bReady OR aStep[nR].bFeedback);
    END_IF;
    IF aStep[nR].eState = E_SeqStepState.Stopping THEN
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
bRestarting := FALSE;
refData.sts.tRestartIn := T#0s;
IF bArmed THEN
  IF tRsAcc >= refData.set.tRestartDelay THEN
    refData.sts.bFltTimeout := FALSE;
    refData.sts.bFltLoss := FALSE;
    refData.sts.bFltConfig := FALSE;
    refData.sts.nFaultStep := 0;
    FOR nI := 1 TO nN DO
      IF aStep[nLo + nI - 1].eState = E_SeqStepState.Fault THEN
        aStep[nLo + nI - 1].eState := E_SeqStepState.Off;
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
    IF nRsCount >= refData.set.nMaxRetries THEN
      bRsLocked := TRUE;          (* no more by itself until a reset or a start *)
    END_IF;
  ELSE
    bRestarting := TRUE;
    refData.sts.tRestartIn := refData.set.tRestartDelay - tRsAcc;
  END_IF;
END_IF;

(* step states: idle steps show Off, or Bypassed; each step's countdown *)
FOR nI := 1 TO nN DO
  nR := nLo + nI - 1;
  nS := nSLo + nI - 1;
  IF NOT aStep[nR].bCmd AND aStep[nR].eState <> E_SeqStepState.Stopping AND aStep[nR].eState <> E_SeqStepState.Fault THEN
    IF aStepSet[nS].bBypass THEN
      aStep[nR].eState := E_SeqStepState.Bypassed;
    ELSE
      aStep[nR].eState := E_SeqStepState.Off;
    END_IF;
  END_IF;
  aStep[nR].tLeft := T#0s;
  IF (aStep[nR].eState = E_SeqStepState.Starting OR aStep[nR].eState = E_SeqStepState.Stopping)
     AND aStepSet[nS].tTimeout > aStep[nR].tElapsed THEN
    aStep[nR].tLeft := aStepSet[nS].tTimeout - aStep[nR].tElapsed;
  END_IF;
END_FOR;
refData.sts.tTimeLeft := T#0s;
IF nSub = 1 AND nCur >= 1 AND nCur <= nN THEN
  nK := nLo + nCur - 1;
  nKS := nSLo + nCur - 1;
  IF (eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held) AND aStepSet[nKS].tStartDelay > tAcc THEN
    aStep[nK].tLeft := aStepSet[nKS].tStartDelay - tAcc;
    refData.sts.tTimeLeft := aStep[nK].tLeft;
  ELSIF eMd = E_SeqMode.Stopping AND bSeqStop AND aStepSet[nKS].tStopDelay > tAcc THEN
    aStep[nK].tLeft := aStepSet[nKS].tStopDelay - tAcc;
    refData.sts.tTimeLeft := aStep[nK].tLeft;
  END_IF;
END_IF;

(* outputs and status *)
bRunning := eMd = E_SeqMode.Running;
bBusy := eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held OR eMd = E_SeqMode.Stopping;
IF eMd = E_SeqMode.Starting OR eMd = E_SeqMode.Held OR (eMd = E_SeqMode.Stopping AND bSeqStop) THEN
  nCurrentStep := DINT_TO_INT(nCur);
ELSE
  nCurrentStep := 0;
END_IF;
IF NOT (refData.sts.bFltTimeout OR refData.sts.bFltLoss OR refData.sts.bFltConfig) THEN
  refData.sts.nFaultStep := 0;
END_IF;
refData.sts.eMode := eMd;
refData.sts.nRestarts := nRsCount;
refData.sts.bRestartLocked := bRsLocked;
bError := refData.sts.bFltTimeout OR refData.sts.bFltLoss OR refData.sts.bFltConfig;
bWarning := NOT bError AND (bRestarting OR refData.sts.bRefused);
IF refData.sts.bFltConfig THEN
  IF bTooMany OR NOT bRowsOk THEN
    eErrorId := E_UtError.RecipeBad;
  ELSIF NOT bOkSet THEN
    eErrorId := E_UtError.BadSetting;
  ELSE
    eErrorId := E_UtError.NoChannels;  (* nothing to run: every step bypassed, or none *)
  END_IF;
ELSIF refData.sts.bFltTimeout OR refData.sts.bFltLoss THEN
  eErrorId := eFlt;
ELSIF refData.sts.bRefused THEN
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
ELSIF bRestarting THEN
  eState := E_State.Waiting;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK