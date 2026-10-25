(* UT_SEQUENCER — start / stop chain (conveyors, crushing, process trains).

Steps is the chain: the project's UT_SEQ_STEP instances (up to 32, called
before the chain), one per machine, in START order. Run (held) starts it
and its drop stops it; Start / Stop are edges; Interlock FALSE = Abort;
Permissive FALSE refuses a start. A start runs
the steps one at a time: each step's cmd goes on, its feedback must prove
within `timeout`, then `startDelay` passes before the next step. A stop runs
them in reverse (stopMode), each waiting for its feedback to go and then its
`stopDelay`.

A step that loses its feedback while running, or fails to prove at start,
is a fault, and onLoss decides what stops:
  CASCADE          the failed step and every step after it at once, then
                   the rest in reverse (the original behaviour)
  STOP_ALL         everything at once
  DOWNSTREAM_ONLY  the failed step and every step after it; the steps
                   before it keep running (mode PARTIAL)
A step whose feedback will not go when stopped holds the stop there (its
machine is still running, so the ones it feeds keep running) and raises a
fault once its timeout has passed. Abort is the way out.

Positions: CurrentStep, faultStep and configStep count steps from 1 = the
first element, whatever the array's lower bound.

Hold pauses a START (no further step is started, the current step's timers
stop). A stop is never held. Abort (level) drops every cmd at once.

Auto restart: after a fault stop it starts again by itself once every step
is ready and Run is still TRUE (a maintained run request), after
restartDelay with Restarting on, at most maxRetries times in retryWindow. A Stop edge or Abort cancels the run
request, so a stopped or aborted chain never restarts by itself.

Nothing is kept over a power cut: the chain comes back idle with every cmd
off and must be started again (a Start edge).

Faults clear on a Start edge, a Stop edge or Reset (and cmdXxx). A "did not
stop" fault comes back while the machine is still running. *)

FUNCTION_BLOCK UT_SEQUENCER
  VAR_INPUT
    Run : BOOL; (* held run request: its rise starts, it must stay on for an auto restart *)
    Start : BOOL R_EDGE;
    Stop : BOOL R_EDGE;
    Abort : BOOL; (* level: everything off at once (e.g. NOT e-stop healthy) *)
    Hold : BOOL; (* pause a start where it is *)
    Reset : BOOL R_EDGE; (* clear the fault *)
    Interlock : BOOL := TRUE; (* FALSE = Abort *)
    Permissive : BOOL := TRUE; (* FALSE refuses a start *)
  END_VAR
  VAR_OUTPUT
    Running : BOOL; (* every step up *)
    Busy : BOOL; (* starting, held or stopping *)
    Fault : BOOL;
    CurrentStep : INT; (* position of the step being started or stopped (0 = none) *)
    Restarting : BOOL; (* auto restart countdown: wire to a pre-start siren *)
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Steps : ARRAY [*] OF UT_SEQ_STEP;
    Data : UT_SEQ_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SEQ_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    okSet : BOOL;
    rCmd : ARRAY [0..31] OF BOOL; (* the chain's view of each step (up to 32) *)
    rState : ARRAY [0..31] OF UT_STATE;
    rEl : ARRAY [0..31] OF TIME;
    rLeft : ARRAY [0..31] OF TIME;
    x : BOOL;
    runPrev : BOOL;
    tooMany : BOOL;
    rsCount : INT; (* auto restarts in this window *)
    rsWinAt : TIME;
    rsLocked : BOOL;
    runReq : BOOL; (* the chain is wanted running (a start sets it, a stop or abort clears it) *)
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    dtScan : TIME;
    lo : DINT;
    hi : DINT;
    n : DINT;
    i : DINT;
    k : DINT;
    guard : DINT;
    md : UT_SEQ_MODE;
    cur : DINT; (* position of the step being started or stopped (0 = none) *)
    sub : INT; (* 0 waiting for the feedback, 1 waiting the delay *)
    tAcc : TIME; (* time in the delay *)
    seqStop : BOOL; (* stopping one step at a time *)
    fwdStop : BOOL; (* ... first started, first stopped *)
    startPrev : BOOL;
    stopPrev : BOOL;
    resetPrev : BOOL;
    startSeen : BOOL;
    stopSeen : BOOL;
    resetSeen : BOOL;
    startReq : BOOL;
    stopReq : BOOL;
    resetReq : BOOL;
    failAt : DINT; (* position of a step that failed this scan (0 = none) *)
    failTimeout : BOOL; (* ... by not proving at start *)
    anyOn : BOOL;
    anyStopping : BOOL;
    allReady : BOOL;
    armed : BOOL;
    armedPrev : BOOL;
    rsAcc : TIME;
    nRun : DINT;
    cfgSet : BOOL; (* a setting is invalid: no start (running on, a negative time acts as 0) *)
    cfgAt : DINT; (* position of the first step with a bad setting (0 = a chain setting) *)
    fltKind : UT_FAULT; (* the machine fault shown: no feedback at start, feedback lost, did not stop *)
    tShow : TIME; (* status: the time shown *)
    sc : UT_STATUS; (* status code *)
    sf : UT_FAULT; (* and what it is about *)
    shownSt : UT_STATUS; (* the status the text was set for *)
    shownF : UT_FAULT;
    shown : BOOL;
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
okSet := (Data.set.stopMode = UT_SEQ_REVERSE OR Data.set.stopMode = UT_SEQ_ALL_AT_ONCE OR Data.set.stopMode = UT_SEQ_FORWARD)
         AND (Data.set.onLoss = UT_SEQ_CASCADE OR Data.set.onLoss = UT_SEQ_STOP_ALL OR Data.set.onLoss = UT_SEQ_DOWNSTREAM_ONLY)
         AND Data.set.restartDelay >= T#0s AND Data.set.maxRetries >= 0 AND Data.set.retryWindow >= T#0s;
IF NOT okSet AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_CHAIN;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  okSet := TRUE;
END_IF;
IF keep.SaveSet AND (okSet OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := okSet;
END_IF;
lo := LOWER_BOUND(Steps, 1);
hi := UPPER_BOUND(Steps, 1);
tooMany := hi - lo + 1 > 32;
IF tooMany THEN
  hi := lo + 31;                 (* up to 32 steps; more: a config fault *)
END_IF;
n := hi - lo + 1;
IF NOT started THEN
  (* first scan, also after a power cut: stopped and safe *)
  started := TRUE;
  tPrev := tCur;
  startPrev := Start;
  runPrev := Run;                (* a Run held over a power cut is not a new start *)
  stopPrev := Stop;
  resetPrev := Reset;
  FOR i := lo TO hi DO
    rCmd[i - lo] := FALSE;
    rState[i - lo] := UT_STATE_OFF;
    rEl[i - lo] := T#0s;
  END_FOR;
  md := UT_SEQ_IDLE;
  Data.sts.fltTimeout := FALSE;
  Data.sts.fltLoss := FALSE;
  Data.sts.fltConfig := FALSE;
  Data.sts.faultStep := 0;
END_IF;
dtScan := tCur - tPrev;
tPrev := tCur;
IF dtScan < T#0s THEN
  dtScan := T#0s;
END_IF;

(* pins act on a rising edge; HMI commands once per request, then cleared *)
startReq := (Start AND NOT startPrev) OR (Data.cmdStart AND NOT startSeen) OR (Run AND NOT runPrev);
startPrev := Start;
startSeen := Data.cmdStart;
Data.cmdStart := FALSE;
stopReq := (Stop AND NOT stopPrev) OR (Data.cmdStop AND NOT stopSeen) OR (NOT Run AND runPrev);
runPrev := Run;
IF NOT Permissive THEN
  startReq := FALSE;             (* a start is refused *)
END_IF;
stopPrev := Stop;
stopSeen := Data.cmdStop;
Data.cmdStop := FALSE;
resetReq := (Reset AND NOT resetPrev) OR (Data.cmdReset AND NOT resetSeen);
resetPrev := Reset;
resetSeen := Data.cmdReset;
Data.cmdReset := FALSE;

failAt := 0;
failTimeout := FALSE;

(* settings *)
cfgSet := NOT (Data.set.stopMode = UT_SEQ_REVERSE OR Data.set.stopMode = UT_SEQ_ALL_AT_ONCE OR Data.set.stopMode = UT_SEQ_FORWARD)
          OR NOT (Data.set.onLoss = UT_SEQ_CASCADE OR Data.set.onLoss = UT_SEQ_STOP_ALL OR Data.set.onLoss = UT_SEQ_DOWNSTREAM_ONLY)
          OR Data.set.restartDelay < T#0s OR tooMany;
cfgAt := 0;
FOR i := lo TO hi DO
  IF cfgAt = 0 AND (Steps[i].StartDelay() < T#0s OR Steps[i].StopDelay() < T#0s OR Steps[i].Timeout() < T#0s) THEN
    cfgAt := i - lo + 1;
  END_IF;
END_FOR;
cfgSet := cfgSet OR cfgAt > 0;

IF Abort OR NOT Interlock THEN
  (* everything off at once; no restart by itself *)
  FOR i := lo TO hi DO
    rCmd[i - lo] := FALSE;
    rState[i - lo] := UT_STATE_OFF;
  END_FOR;
  md := UT_SEQ_ABORTED;
  runReq := FALSE;
  cur := 0;
  sub := 0;
  seqStop := FALSE;
ELSE
  (* any start, stop or reset clears the faults *)
  IF startReq OR stopReq OR resetReq THEN
    Data.sts.fltTimeout := FALSE;
    Data.sts.fltLoss := FALSE;
    Data.sts.fltConfig := FALSE;
    Data.sts.faultStep := 0;
    FOR i := lo TO hi DO
      IF rState[i - lo] = UT_STATE_FAULT THEN
        rState[i - lo] := UT_STATE_OFF;
      END_IF;
    END_FOR;
  END_IF;

  IF stopReq THEN
    runReq := FALSE;
    IF md = UT_SEQ_ABORTED THEN
      md := UT_SEQ_IDLE;
    END_IF;
    IF md <> UT_SEQ_IDLE AND (md <> UT_SEQ_STOPPING OR NOT seqStop) THEN
      IF Data.set.stopMode = UT_SEQ_ALL_AT_ONCE THEN
        FOR i := lo TO hi DO
          IF rCmd[i - lo] THEN
            rCmd[i - lo] := FALSE;
            rState[i - lo] := UT_STATE_STOPPING;
            rEl[i - lo] := T#0s;
          END_IF;
        END_FOR;
        seqStop := FALSE;
      ELSE
        seqStop := TRUE;
        fwdStop := Data.set.stopMode = UT_SEQ_FORWARD;
      END_IF;
      cur := 0;
      sub := 0;
      md := UT_SEQ_STOPPING;
    END_IF;
  ELSIF startReq AND md <> UT_SEQ_STARTING AND md <> UT_SEQ_HELD AND md <> UT_SEQ_RUNNING THEN
    nRun := 0;
    FOR i := lo TO hi DO
      IF NOT Steps[i].IsBypassed() OR rCmd[i - lo] THEN
        nRun := nRun + 1;
      END_IF;
    END_FOR;
    IF cfgSet THEN
      Data.sts.fltConfig := TRUE;    (* refused: the fault is shown below *)
      IF md = UT_SEQ_ABORTED THEN
        md := UT_SEQ_IDLE;
      END_IF;
    ELSIF nRun = 0 THEN
      Data.sts.fltConfig := TRUE;
      IF md = UT_SEQ_ABORTED THEN
        md := UT_SEQ_IDLE;
      END_IF;
    ELSE
      runReq := TRUE;
      md := UT_SEQ_STARTING;
      cur := 1;
      sub := 0;
      seqStop := FALSE;
    END_IF;
  ELSIF resetReq AND md = UT_SEQ_ABORTED THEN
    md := UT_SEQ_IDLE;
  END_IF;

  (* supervision: steps stopping, and running steps losing their feedback *)
  FOR i := lo TO hi DO
    IF rState[i - lo] = UT_STATE_STOPPING THEN
      rEl[i - lo] := rEl[i - lo] + dtScan;
      IF NOT Steps[i].FeedbackNow() OR Steps[i].NoFeedback() THEN
        rState[i - lo] := UT_STATE_OFF;
      ELSIF Steps[i].Timeout() > T#0s AND rEl[i - lo] >= Steps[i].Timeout() THEN
        Data.sts.fltTimeout := TRUE;
        IF Data.sts.faultStep = 0 THEN
          Data.sts.faultStep := DINT_TO_INT(i - lo + 1);
          fltKind := UT_F_STEP_NO_STOP;
        END_IF;
      END_IF;
    ELSIF rCmd[i - lo] AND rState[i - lo] = UT_STATE_ON AND NOT Steps[i].NoFeedback()
          AND NOT Steps[i].FeedbackNow() AND failAt = 0 THEN
      failAt := i - lo + 1;
    END_IF;
  END_FOR;

  (* the start, one step at a time *)
  IF failAt = 0 AND (md = UT_SEQ_STARTING OR md = UT_SEQ_HELD) THEN
    IF Hold THEN
      md := UT_SEQ_HELD;
    ELSE
      md := UT_SEQ_STARTING;
      FOR guard := 0 TO n DO           (* at most one pass over the chain *)
        IF md <> UT_SEQ_STARTING THEN
          EXIT;
        END_IF;
        IF cur > n OR cur < 1 THEN
          md := UT_SEQ_RUNNING;
          cur := 0;
          sub := 0;
          EXIT;
        END_IF;
        k := lo + cur - 1;
        IF sub = 0 THEN
          IF rCmd[k - lo] AND rState[k - lo] = UT_STATE_ON THEN
            cur := cur + 1;          (* already running and proven *)
          ELSIF Steps[k].IsBypassed() AND NOT rCmd[k - lo] THEN
            rState[k - lo] := UT_STATE_OOS;
            cur := cur + 1;
          ELSE
            IF rState[k - lo] <> UT_STATE_STARTING THEN
              rCmd[k - lo] := TRUE;
              rState[k - lo] := UT_STATE_STARTING;
              rEl[k - lo] := T#0s;
            ELSE
              rEl[k - lo] := rEl[k - lo] + dtScan;
            END_IF;
            IF Steps[k].NoFeedback() OR Steps[k].FeedbackNow() THEN
              rState[k - lo] := UT_STATE_ON;
              tAcc := T#0s;
              IF Steps[k].StartDelay() > T#0s THEN
                sub := 1;
                EXIT;
              END_IF;
              cur := cur + 1;
            ELSIF Steps[k].Timeout() > T#0s AND rEl[k - lo] >= Steps[k].Timeout() THEN
              failAt := cur;
              failTimeout := TRUE;
              EXIT;
            ELSE
              EXIT;
            END_IF;
          END_IF;
        ELSE
          tAcc := tAcc + dtScan;
          IF tAcc >= Steps[k].StartDelay() THEN
            cur := cur + 1;
            sub := 0;
          ELSE
            EXIT;
          END_IF;
        END_IF;
      END_FOR;
    END_IF;
  END_IF;

  (* the stop, one step at a time (never held) *)
  IF failAt = 0 AND md = UT_SEQ_STOPPING AND seqStop THEN
    FOR guard := 0 TO n + 1 DO         (* at most one pass over the chain *)
      IF NOT seqStop THEN
        EXIT;
      END_IF;
      IF cur < 1 OR cur > n THEN
        (* the next step to stop *)
        cur := 0;
        IF fwdStop THEN
          FOR i := hi TO lo BY -1 DO
            IF rCmd[i - lo] THEN
              cur := i - lo + 1;
            END_IF;
          END_FOR;
        ELSE
          FOR i := lo TO hi DO
            IF rCmd[i - lo] THEN
              cur := i - lo + 1;
            END_IF;
          END_FOR;
        END_IF;
        IF cur = 0 THEN
          seqStop := FALSE;
          EXIT;
        END_IF;
        k := lo + cur - 1;
        rCmd[k - lo] := FALSE;
        rState[k - lo] := UT_STATE_STOPPING;
        rEl[k - lo] := T#0s;
        sub := 0;
        EXIT;                        (* its feedback is checked from the next scan *)
      END_IF;
      k := lo + cur - 1;
      IF sub = 0 THEN
        IF rState[k - lo] = UT_STATE_STOPPING THEN
          EXIT;                      (* still running down *)
        END_IF;
        sub := 1;
        tAcc := T#0s;
        anyOn := FALSE;
        FOR i := lo TO hi DO
          anyOn := anyOn OR rCmd[i - lo];
        END_FOR;
        IF anyOn AND Steps[k].StopDelay() > T#0s THEN
          EXIT;
        END_IF;
        cur := 0;
      ELSE
        tAcc := tAcc + dtScan;
        IF tAcc >= Steps[k].StopDelay() THEN
          cur := 0;
        ELSE
          EXIT;
        END_IF;
      END_IF;
    END_FOR;
  END_IF;

  (* a step lost its feedback, or did not prove at start *)
  IF failAt > 0 THEN
    k := lo + failAt - 1;
    IF failTimeout THEN
      Data.sts.fltTimeout := TRUE;
    ELSE
      Data.sts.fltLoss := TRUE;
    END_IF;
    IF Data.sts.faultStep = 0 THEN
      Data.sts.faultStep := DINT_TO_INT(failAt);
      IF failTimeout THEN
        fltKind := UT_F_STEP_NO_FB;
      ELSE
        fltKind := UT_F_STEP_FB_LOST;
      END_IF;
    END_IF;
    rCmd[k - lo] := FALSE;
    rState[k - lo] := UT_STATE_FAULT;
    FOR i := lo TO hi DO
      IF rCmd[i - lo] AND (i > k OR Data.set.onLoss = UT_SEQ_STOP_ALL) THEN
        rCmd[i - lo] := FALSE;
        rState[i - lo] := UT_STATE_STOPPING;
        rEl[i - lo] := T#0s;
      END_IF;
    END_FOR;
    CASE Data.set.onLoss OF
    UT_SEQ_STOP_ALL:
      seqStop := FALSE;
    UT_SEQ_DOWNSTREAM_ONLY:
      IF md <> UT_SEQ_STOPPING THEN
        seqStop := FALSE;
      END_IF;
    ELSE
      (* the rest stop in reverse, the first after the failed step's stopDelay *)
      seqStop := TRUE;
      fwdStop := FALSE;
      cur := failAt;
      sub := 1;
      tAcc := T#0s;
    END_CASE;
    IF NOT seqStop THEN
      cur := 0;
      sub := 0;
    END_IF;
    md := UT_SEQ_STOPPING;
  END_IF;

  (* the stop is over once nothing is running down *)
  IF md = UT_SEQ_STOPPING AND NOT seqStop THEN
    anyOn := FALSE;
    anyStopping := FALSE;
    FOR i := lo TO hi DO
      anyOn := anyOn OR rCmd[i - lo];
      anyStopping := anyStopping OR rState[i - lo] = UT_STATE_STOPPING;
    END_FOR;
    IF NOT anyStopping THEN
      cur := 0;
      IF anyOn THEN
        md := UT_SEQ_PARTIAL;
      ELSE
        md := UT_SEQ_IDLE;
      END_IF;
    END_IF;
  END_IF;
END_IF;

(* a bad setting is shown as a config fault while it lasts *)
IF cfgSet THEN
  Data.sts.fltConfig := TRUE;
END_IF;
Data.sts.configStep := DINT_TO_INT(cfgAt);

(* auto restart: wanted running, Start held, every step ready *)
armed := FALSE;
IF resetReq OR startReq OR (rsCount > 0 AND tCur - rsWinAt >= Data.set.retryWindow) THEN
  rsCount := 0;
  rsLocked := FALSE;
END_IF;
IF Data.set.autoRestart AND runReq AND Run AND NOT Abort AND Interlock AND Permissive AND NOT Hold AND NOT cfgSet
   AND NOT rsLocked
   AND (md = UT_SEQ_IDLE OR md = UT_SEQ_PARTIAL) THEN
  allReady := TRUE;
  FOR i := lo TO hi DO
    IF NOT (Steps[i].IsBypassed() AND NOT rCmd[i - lo]) THEN
      allReady := allReady AND Steps[i].IsReady();
    END_IF;
    IF rState[i - lo] = UT_STATE_STOPPING THEN
      allReady := FALSE;
    END_IF;
  END_FOR;
  armed := allReady;
END_IF;
IF armed AND armedPrev THEN
  rsAcc := rsAcc + dtScan;
ELSE
  rsAcc := T#0s;
END_IF;
armedPrev := armed;
Restarting := FALSE;
Data.det.restartIn := T#0s;
IF armed THEN
  IF rsAcc >= Data.set.restartDelay THEN
    Data.sts.fltTimeout := FALSE;
    Data.sts.fltLoss := FALSE;
    Data.sts.fltConfig := FALSE;
    Data.sts.faultStep := 0;
    FOR i := lo TO hi DO
      IF rState[i - lo] = UT_STATE_FAULT THEN
        rState[i - lo] := UT_STATE_OFF;
      END_IF;
    END_FOR;
    md := UT_SEQ_STARTING;
    cur := 1;
    sub := 0;
    seqStop := FALSE;
    armedPrev := FALSE;
    IF rsCount = 0 THEN
      rsWinAt := tCur;
    END_IF;
    rsCount := rsCount + 1;
    IF rsCount >= Data.set.maxRetries THEN
      rsLocked := TRUE;          (* no more by itself until a Reset or a start *)
    END_IF;
  ELSE
    Restarting := TRUE;
    Data.det.restartIn := Data.set.restartDelay - rsAcc;
  END_IF;
END_IF;

(* step states: idle steps show OFF, or OOS when bypassed *)
FOR i := lo TO hi DO
  IF NOT rCmd[i - lo] AND rState[i - lo] <> UT_STATE_STOPPING AND rState[i - lo] <> UT_STATE_FAULT THEN
    IF Steps[i].IsBypassed() THEN
      rState[i - lo] := UT_STATE_OOS;
    ELSE
      rState[i - lo] := UT_STATE_OFF;
    END_IF;
  END_IF;
END_FOR;

(* each step's countdown: its timeout while starting or stopping, its
   delay while the chain waits on it *)
FOR i := lo TO hi DO
  rLeft[i - lo] := T#0s;
  IF (rState[i - lo] = UT_STATE_STARTING OR rState[i - lo] = UT_STATE_STOPPING)
     AND Steps[i].Timeout() > rEl[i - lo] THEN
    rLeft[i - lo] := Steps[i].Timeout() - rEl[i - lo];
  END_IF;
END_FOR;
IF sub = 1 AND cur >= 1 AND cur <= n THEN
  k := lo + cur - 1;
  IF (md = UT_SEQ_STARTING OR md = UT_SEQ_HELD) AND Steps[k].StartDelay() > tAcc THEN
    rLeft[k - lo] := Steps[k].StartDelay() - tAcc;
  ELSIF md = UT_SEQ_STOPPING AND seqStop AND Steps[k].StopDelay() > tAcc THEN
    rLeft[k - lo] := Steps[k].StopDelay() - tAcc;
  END_IF;
END_IF;

Running := md = UT_SEQ_RUNNING;
Busy := md = UT_SEQ_STARTING OR md = UT_SEQ_HELD OR md = UT_SEQ_STOPPING;
IF md = UT_SEQ_STARTING OR md = UT_SEQ_HELD OR (md = UT_SEQ_STOPPING AND seqStop) THEN
  CurrentStep := DINT_TO_INT(cur);
ELSE
  CurrentStep := 0;
END_IF;
Data.sts.fault := Data.sts.fltTimeout OR Data.sts.fltLoss OR Data.sts.fltConfig;
Fault := Data.sts.fault;
Data.sts.faultCode := 0;
IF Data.sts.fltTimeout THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1; END_IF;
IF Data.sts.fltLoss THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2; END_IF;
IF Data.sts.fltConfig THEN Data.sts.faultCode := Data.sts.faultCode OR 16#4; END_IF;
IF NOT Data.sts.fault THEN
  Data.sts.faultStep := 0;
END_IF;
Data.sts.mode := md;

(* status: the one main thing, in the order config, fault, held, normal,
   off. CurrentStep, faultStep, configStep and timeLeft carry the numbers *)
sf := UT_F_NONE;
tShow := T#0s;
IF Data.sts.fltConfig THEN
  sc := UT_ST_CONFIG;
  IF NOT cfgSet THEN
    sf := UT_F_NO_STEPS;         (* nothing to run *)
  ELSIF cfgAt > 0 THEN
    sf := UT_F_STEP_SETTING;
  ELSE
    sf := UT_F_CHAIN;
  END_IF;
ELSIF Data.sts.fltLoss OR Data.sts.fltTimeout THEN
  sf := fltKind;
  IF Restarting THEN
    sc := UT_ST_FAULT_RETRY;
    tShow := Data.det.restartIn;
  ELSE
    sc := UT_ST_FAULT_RESET;
  END_IF;
ELSIF Abort THEN
  sc := UT_ST_ABORT;
ELSIF md = UT_SEQ_HELD THEN
  sc := UT_ST_HELD;
ELSIF Restarting THEN
  sc := UT_ST_AUTO_RESTART;
  tShow := Data.det.restartIn;
ELSIF md = UT_SEQ_STARTING THEN
  sc := UT_ST_STARTING;
  IF sub = 1 AND cur >= 1 AND cur <= n THEN
    tShow := Steps[lo + cur - 1].StartDelay() - tAcc;
  END_IF;
ELSIF md = UT_SEQ_STOPPING THEN
  sc := UT_ST_STOPPING;
  IF CurrentStep >= 1 AND sub = 1 AND INT_TO_DINT(CurrentStep) <= n THEN
    tShow := Steps[lo + INT_TO_DINT(CurrentStep) - 1].StopDelay() - tAcc;
  END_IF;
ELSIF md = UT_SEQ_RUNNING THEN
  sc := UT_ST_RUN_ALL;
ELSIF md = UT_SEQ_PARTIAL THEN
  sc := UT_ST_RUN_PART;
ELSIF md = UT_SEQ_ABORTED THEN
  sc := UT_ST_OFF_ABORTED;
ELSE
  sc := UT_ST_OFF;
END_IF;
IF tShow < T#0s THEN
  tShow := T#0s;
END_IF;
Data.det.timeLeft := tShow;
(* the text is set only when the status changes *)
IF NOT shown OR sc <> shownSt OR sf <> shownF THEN
  shown := TRUE;
  shownSt := sc;
  shownF := sf;
  Data.sts.statusText := UT_STATUS_TEXT(sc, sf);
END_IF;
Data.sts.statusCode := sc;
Data.sts.faultId := sf;
Warning := NOT okSet;
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := Abort OR NOT Interlock, OutOfSpec := Warning, Maint := FALSE);
Data.sts.restart.retries := rsCount;
Data.sts.restart.locked := rsLocked;
Data.sts.restart.active := Restarting;
Data.sts.restart.timeLeft := Data.det.restartIn;
(* the steps: the command and the chain's view *)
FOR i := lo TO hi DO
  x := Steps[i].Command(Run := rCmd[i - lo], No := DINT_TO_INT(i - lo + 1), Owner := Data.set.tag);
  x := Steps[i].SetState(State := rState[i - lo], Elapsed := rEl[i - lo], Left := rLeft[i - lo]);
END_FOR;

END_FUNCTION_BLOCK