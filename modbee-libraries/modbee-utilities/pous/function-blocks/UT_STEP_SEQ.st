(* UT_STEP_SEQ — timed / conditional step sequence (backwash, CIP, fill-mix-
drain, kiln and dryer cycles).

Steps is the recipe: the project's UT_STEP instances (any count, called
before the sequence; each keeps its own settings). Each step switches on the outputs in its `outputs`
pattern (bit n = the n-th element of Outputs, counted from the first) and
lasts `duration`, or until `cond` when `waitCond`, or both (the time AND
the condition). A step with neither ends on the next scan. `timeout` caps a
step; `onTimeout` then holds there with a fault (outputs go to
pauseOutputs until Reset or Next), carries on, or goes to the stop step.

Positions: steps are numbered from 1 = the first element, whatever the
array's lower bound. `next` (0 = the following step), `stopStep`,
`cmdJump`, CurrentStep and timedOutStep all use positions.

Jumps and loops: `next` sends the sequence to another step. A jump back
(to this step or an earlier one) repeats `loops` times and then carries on
to the following step; its loopCount starts again from 0 each time the
loop is left, so loops can nest. A jump back with loops = 0 would never
end: the recipe is refused with a config fault, as is a `next` or
`stopStep` outside the recipe. Skipped steps are passed over.

Stop goes to stopStep and carries on from there to the end (put the safe
end steps last); stopStep = 0 ends at once with every output off. Done
pulses for one scan when the recipe completes without a stop, and counts
`cycles` (since the PLC started; not kept over a power cut).

Run held runs it from step 1 and its drop is a Stop; Interlock FALSE acts
as Abort; Permissive FALSE holds back a start. Abort (a level, e.g. NOT
e-stop healthy) ends a run at once with every
output off, without the stop steps, and no start or jump is taken while it
is on. lastResult (UT_STOP) says how the last run ended: UT_STOP_DONE,
UT_STOP_OPERATOR (Stop or cmdStop, after the stop steps), UT_STOP_ABORTED,
UT_STOP_STEP_TIMEOUT (onTimeout STOP), UT_STOP_REFUSED (a bad next met
while running).

Pause (pin, or cmdPause until a Start) holds the step: outputs go to
pauseOutputs and the step's time is kept. After a power cut the sequence is
idle with every output off; it never resumes by itself (cmdJump can start
it at any step). *)

FUNCTION_BLOCK UT_STEP_SEQ
  VAR_INPUT
    Run : BOOL; (* held: run from step 1; dropping = Stop *)
    Start : BOOL R_EDGE; (* run from step 1 (resumes an HMI pause) *)
    Stop : BOOL R_EDGE; (* go to the stop step (or end) *)
    Pause : BOOL; (* hold: outputs go to pauseOutputs, time is kept *)
    Next : BOOL R_EDGE; (* end this step now (manual stepping) *)
    Reset : BOOL R_EDGE; (* clear a fault *)
    Abort : BOOL; (* level: end at once, every output off, no stop steps; no start while on *)
    Interlock : BOOL := TRUE; (* FALSE = Abort *)
    Permissive : BOOL := TRUE; (* FALSE holds back a start *)
  END_VAR
  VAR_OUTPUT
    Busy : BOOL;
    Done : BOOL; (* one scan: the recipe completed *)
    CurrentStep : INT; (* position running (0 = idle) *)
    Remaining : TIME; (* time left in this step *)
    Fault : BOOL;
    Warning : BOOL; (* a bad setting at first boot *)
  END_VAR
  VAR_IN_OUT
    Steps : ARRAY [*] OF UT_STEP;
    Outputs : ARRAY [*] OF BOOL;
    Data : UT_STEP_SEQ_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_STEP_SEQ_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    okSet : BOOL;
    zs : UT_STEP_SET;
    stepEl : TIME;
    x : BOOL;
    runPrev : BOOL;
    byRun : BOOL;
    started : BOOL;
    tCur : TIME;
    tPrev : TIME;
    dtScan : TIME;
    lo : DINT;
    hi : DINT;
    n : DINT;
    olo : DINT;
    ohi : DINT;
    i : DINT;
    j : DINT;
    p : DINT;
    nx : DINT;
    guard : DINT;
    cur : DINT; (* position running (0 = idle) *)
    tmo : TIME; (* time toward the timeout *)
    going : BOOL;
    stopping : BOOL;
    hmiPause : BOOL;
    held : BOOL; (* held on a step timeout *)
    cfgBad : BOOL;
    finish : BOOL;
    toStop : BOOL;
    endNow : BOOL;
    complete : BOOL;
    cycles : UDINT;
    pattern : DWORD;
    startPrev : BOOL;
    stopPrev : BOOL;
    nextPrev : BOOL;
    resetPrev : BOOL;
    startSeen : BOOL;
    stopSeen : BOOL;
    pauseSeen : BOOL;
    nextSeen : BOOL;
    resetSeen : BOOL;
    startReq : BOOL;
    stopReq : BOOL;
    nextReq : BOOL;
    resetReq : BOOL;
    pauseReq : BOOL;
    jumpTo : DINT;
    cfgKind : UT_FAULT; (* the recipe problem *)
    cfgStep : DINT; (* ... in this step *)
    sc : UT_STATUS; (* status code *)
    sf : UT_FAULT; (* and what it is about *)
    shownSt : UT_STATUS; (* the status the text was set for *)
    shownF : UT_FAULT;
    shown : BOOL;
    stopWhy : UT_STOP; (* why the stop steps are running: a Stop, or a step timeout *)
    result : UT_STOP; (* how this run ended (UT_STOP_NONE = it did not end this scan) *)
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
okSet := Data.set.stopStep >= 0;
IF NOT okSet AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_STOP_STEP;
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
n := hi - lo + 1;
olo := LOWER_BOUND(Outputs, 1);
ohi := UPPER_BOUND(Outputs, 1);
Done := FALSE;
IF NOT started THEN
  (* first scan, also after a power cut: idle, every output off *)
  started := TRUE;
  tPrev := tCur;
  startPrev := Start;
  runPrev := Run;                (* a Run held at power-up does not start it *)
  stopPrev := Stop;
  nextPrev := Next;
  resetPrev := Reset;
  FOR i := lo TO hi DO
    x := Steps[i].SetActive(On := FALSE);
    x := Steps[i].SetLoops(Count := 0);
  END_FOR;
  Data.sts.stepTimeout := FALSE;
  Data.sts.config := FALSE;
  Data.sts.timedOutStep := 0;
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
stopReq := (Stop AND NOT stopPrev) OR (Data.cmdStop AND NOT stopSeen) OR (NOT Run AND runPrev AND byRun);
IF Run AND NOT runPrev THEN
  byRun := TRUE;                 (* a held Run: its drop is a Stop *)
ELSIF stopReq OR NOT going THEN
  byRun := FALSE;                (* a resume does not change who started it *)
END_IF;
runPrev := Run;
IF NOT Permissive AND NOT going THEN
  startReq := FALSE;             (* a start is held back *)
END_IF;
stopPrev := Stop;
stopSeen := Data.cmdStop;
Data.cmdStop := FALSE;
nextReq := (Next AND NOT nextPrev) OR (Data.cmdNext AND NOT nextSeen);
nextPrev := Next;
nextSeen := Data.cmdNext;
Data.cmdNext := FALSE;
resetReq := (Reset AND NOT resetPrev) OR (Data.cmdReset AND NOT resetSeen);
resetPrev := Reset;
resetSeen := Data.cmdReset;
Data.cmdReset := FALSE;
pauseReq := Data.cmdPause AND NOT pauseSeen;
pauseSeen := Data.cmdPause;
Data.cmdPause := FALSE;
jumpTo := 0;
IF Data.cmdJump >= 0 THEN
  IF Data.cmdJump >= 1 AND INT_TO_DINT(Data.cmdJump) <= n THEN
    jumpTo := INT_TO_DINT(Data.cmdJump);
  END_IF;
  Data.cmdJump := -1;
END_IF;

IF resetReq THEN
  Data.sts.config := FALSE;
  IF held THEN
    held := FALSE;               (* the step carries on, with a fresh timeout *)
    tmo := T#0s;
  END_IF;
  Data.sts.stepTimeout := FALSE;
END_IF;

(* check the recipe before a start or a jump *)
IF (startReq AND NOT going) OR jumpTo > 0 THEN
  cfgBad := FALSE;
  cfgStep := 0;
  IF n < 1 THEN
    cfgBad := TRUE;
    cfgKind := UT_F_NO_STEPS;
  END_IF;
  IF Data.set.stopStep < 0 OR INT_TO_DINT(Data.set.stopStep) > n THEN
    cfgBad := TRUE;
    cfgKind := UT_F_STOP_STEP;
  END_IF;
  FOR i := lo TO hi DO
    p := i - lo + 1;
    zs := Steps[i].Settings();
    nx := INT_TO_DINT(zs.next);
    IF NOT cfgBad AND (nx < 0 OR nx > n) THEN
      cfgBad := TRUE;
      cfgKind := UT_F_BAD_NEXT;
      cfgStep := p;
    ELSIF NOT cfgBad AND nx > 0 AND nx <= p AND zs.loops <= 0 THEN
      cfgBad := TRUE;
      cfgKind := UT_F_ENDLESS_LOOP;
      cfgStep := p;
    ELSIF NOT cfgBad AND (zs.duration < T#0s OR zs.timeout < T#0s
                          OR NOT (zs.onTimeout = UT_STEP_FAULT OR zs.onTimeout = UT_STEP_NEXT
                                  OR zs.onTimeout = UT_STEP_STOP)) THEN
      cfgBad := TRUE;
      cfgKind := UT_F_STEP_SETTING;
      cfgStep := p;
    END_IF;
  END_FOR;
  IF cfgBad THEN
    Data.sts.config := TRUE;
    Data.sts.configStep := DINT_TO_INT(cfgStep);
    going := FALSE;
    held := FALSE;
    stopping := FALSE;
    hmiPause := FALSE;
    cur := 0;
    FOR i := lo TO hi DO
      x := Steps[i].SetActive(On := FALSE);
    END_FOR;
    startReq := FALSE;
    jumpTo := 0;
  ELSE
    Data.sts.config := FALSE;
  END_IF;
END_IF;

(* commands *)
endNow := FALSE;
toStop := FALSE;
finish := FALSE;
result := UT_STOP_NONE;
p := 0;                          (* position to enter this scan (0 = none) *)
IF Abort OR NOT Interlock THEN
  (* everything off at once, no stop steps; nothing starts while it is on *)
  startReq := FALSE;
  jumpTo := 0;
  IF going THEN
    endNow := TRUE;
    result := UT_STOP_ABORTED;
  END_IF;
END_IF;
IF NOT going THEN
  hmiPause := FALSE;
  IF (jumpTo > 0 OR startReq) AND NOT stopReq THEN
    going := TRUE;
    stopping := FALSE;
    held := FALSE;
    Data.sts.stepTimeout := FALSE;
    Data.sts.timedOutStep := 0;
    FOR i := lo TO hi DO
      x := Steps[i].SetLoops(Count := 0);
      x := Steps[i].SetActive(On := FALSE);
    END_FOR;
    IF jumpTo > 0 THEN
      p := jumpTo;
    ELSE
      p := 1;
    END_IF;
  END_IF;
ELSE
  IF stopReq THEN
    hmiPause := FALSE;
    IF NOT stopping THEN
      toStop := TRUE;
      stopWhy := UT_STOP_OPERATOR;
    END_IF;
  ELSIF jumpTo > 0 THEN
    held := FALSE;
    stopping := FALSE;           (* a jump leaves the stop steps: a Stop works again *)
    Data.sts.stepTimeout := FALSE;
    IF cur >= 1 THEN
      x := Steps[lo + cur - 1].SetActive(On := FALSE);
    END_IF;
    p := jumpTo;
  ELSIF nextReq THEN
    held := FALSE;
    Data.sts.stepTimeout := FALSE;
    finish := TRUE;
  ELSIF startReq THEN
    hmiPause := FALSE;           (* a start resumes an HMI pause *)
  END_IF;
  IF pauseReq THEN
    hmiPause := TRUE;
  END_IF;
END_IF;
Data.sts.paused := going AND (Pause OR hmiPause);

(* the running step *)
IF going AND p = 0 AND NOT toStop AND NOT finish AND NOT held AND NOT Data.sts.paused AND cur >= 1 AND NOT endNow THEN
  i := lo + cur - 1;
  zs := Steps[i].Settings();
  stepEl := stepEl + dtScan;
  tmo := tmo + dtScan;
  complete := (zs.duration <= T#0s OR stepEl >= zs.duration)
              AND (NOT zs.waitCond OR Steps[i].CondNow());
  IF complete THEN
    finish := TRUE;
  ELSIF zs.timeout > T#0s AND tmo >= zs.timeout THEN
    Data.sts.timedOutStep := DINT_TO_INT(cur);
    CASE zs.onTimeout OF
    UT_STEP_NEXT:
      finish := TRUE;
    UT_STEP_STOP:
      IF stopping THEN
        endNow := TRUE;          (* the stop step itself timed out *)
      ELSE
        toStop := TRUE;
        stopWhy := UT_STOP_STEP_TIMEOUT;
      END_IF;
    ELSE
      held := TRUE;
      Data.sts.stepTimeout := TRUE;
    END_CASE;
  END_IF;
END_IF;

(* where to go next *)
IF finish AND cur >= 1 THEN
  i := lo + cur - 1;
  zs := Steps[i].Settings();
  x := Steps[i].SetActive(On := FALSE);
  nx := INT_TO_DINT(zs.next);
  IF nx < 0 OR nx > n OR (nx > 0 AND nx <= cur AND zs.loops <= 0) THEN
    (* changed while running: refuse it, outputs safe *)
    Data.sts.config := TRUE;
    cfgStep := cur;
    Data.sts.configStep := DINT_TO_INT(cur);
    IF nx < 0 OR nx > n THEN
      cfgKind := UT_F_BAD_NEXT;
    ELSE
      cfgKind := UT_F_ENDLESS_LOOP;
    END_IF;
    going := FALSE;
    stopping := FALSE;
    cur := 0;
    result := UT_STOP_REFUSED;
  ELSIF nx > 0 AND nx <= cur THEN
    IF Steps[i].LoopCount() < zs.loops THEN
      x := Steps[i].SetLoops(Count := Steps[i].LoopCount() + 1);
      p := nx;
    ELSE
      x := Steps[i].SetLoops(Count := 0);
      p := cur + 1;
    END_IF;
  ELSIF nx > 0 THEN
    p := nx;
  ELSE
    p := cur + 1;
  END_IF;
END_IF;
IF toStop THEN
  stopping := TRUE;
  held := FALSE;
  IF cur >= 1 THEN
    x := Steps[lo + cur - 1].SetActive(On := FALSE);
  END_IF;
  IF Data.set.stopStep >= 1 AND INT_TO_DINT(Data.set.stopStep) <= n THEN
    p := INT_TO_DINT(Data.set.stopStep);
  ELSE
    endNow := TRUE;
  END_IF;
END_IF;

(* enter the new step, passing skipped ones; past the last step = the end *)
IF going AND p > 0 AND NOT endNow THEN
  FOR guard := 0 TO n DO             (* at most one pass over the recipe *)
    IF p > n THEN
      EXIT;
    END_IF;
    zs := Steps[lo + p - 1].Settings();
    IF NOT zs.skip THEN
      EXIT;
    END_IF;
    p := p + 1;
  END_FOR;
  IF p > n THEN
    IF NOT stopping THEN
      Done := TRUE;
      cycles := cycles + 1;
      result := UT_STOP_DONE;
    END_IF;
    endNow := TRUE;
  ELSE
    cur := p;
    i := lo + p - 1;
    x := Steps[i].SetActive(On := TRUE);
    stepEl := T#0s;
    tmo := T#0s;
  END_IF;
END_IF;
IF endNow AND going AND result = UT_STOP_NONE THEN
  IF stopping AND stopWhy <> UT_STOP_NONE THEN
    result := stopWhy;           (* the stop steps have run (or a stop with none) *)
  ELSE
    result := UT_STOP_OPERATOR;
  END_IF;
END_IF;
IF result <> UT_STOP_NONE THEN
  Data.sts.lastResult := result;
END_IF;
IF endNow THEN
  IF cur >= 1 THEN
    x := Steps[lo + cur - 1].SetActive(On := FALSE);
  END_IF;
  going := FALSE;
  stopping := FALSE;
  held := FALSE;
  hmiPause := FALSE;
  cur := 0;
END_IF;
IF NOT going THEN
  cur := 0;
  held := FALSE;
  Data.sts.stepTimeout := FALSE;
END_IF;
Data.sts.paused := going AND (Pause OR hmiPause);

(* outputs: the step's pattern, the pause pattern, or all off *)
IF NOT going OR cur < 1 THEN
  pattern := 0;
ELSIF Data.sts.paused OR held THEN
  pattern := Data.set.pauseOutputs;
ELSE
  zs := Steps[lo + cur - 1].Settings();
  pattern := zs.outputs;
END_IF;
FOR j := olo TO ohi DO
  IF j - olo < 32 THEN
    Outputs[j] := (SHR(pattern, DINT_TO_INT(j - olo)) AND 16#1) <> 0;
  ELSE
    Outputs[j] := FALSE;
  END_IF;
END_FOR;

Busy := going;
CurrentStep := DINT_TO_INT(cur);
IF going AND cur >= 1 THEN
  i := lo + cur - 1;
  zs := Steps[i].Settings();
  Data.det.elapsed := stepEl;
  IF zs.duration > stepEl THEN
    Remaining := zs.duration - stepEl;
  ELSE
    Remaining := T#0s;
  END_IF;
ELSE
  Data.det.elapsed := T#0s;
  Remaining := T#0s;
END_IF;
Data.det.remaining := Remaining;
Data.sts.activeStep := CurrentStep;
Data.sts.busy := going;
Data.sts.stopping := stopping;
Data.sts.cycles := cycles;
Data.sts.fault := Data.sts.stepTimeout OR Data.sts.config;
Fault := Data.sts.fault;
Data.sts.faultCode := 0;
IF Data.sts.stepTimeout THEN Data.sts.faultCode := Data.sts.faultCode OR 16#1; END_IF;
IF Data.sts.config THEN Data.sts.faultCode := Data.sts.faultCode OR 16#2; END_IF;
IF NOT Data.sts.config THEN
  Data.sts.configStep := 0;
END_IF;

(* status: the one main thing, in the order config, fault, held, normal,
   idle. activeStep, remaining and configStep carry the numbers *)
sf := UT_F_NONE;
IF Data.sts.config THEN
  sc := UT_ST_CONFIG;
  sf := cfgKind;
ELSIF NOT going OR cur < 1 THEN
  sc := UT_ST_IDLE;
ELSE
  i := lo + cur - 1;
  zs := Steps[i].Settings();
  IF Data.sts.stepTimeout THEN
    sc := UT_ST_FAULT_RESET;
    sf := UT_F_STEP_TIMEOUT;
  ELSIF Data.sts.paused AND hmiPause THEN
    sc := UT_ST_PAUSED_START;
  ELSIF Data.sts.paused THEN
    sc := UT_ST_PAUSED_INPUT;
  ELSIF zs.waitCond AND NOT Steps[i].CondNow() AND Remaining <= T#0s THEN
    sc := UT_ST_WAIT_CONDITION;
  ELSIF stopping THEN
    sc := UT_ST_STOPPING;
  ELSE
    sc := UT_ST_RUN_STEP;
  END_IF;
END_IF;
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
Data.sts.ne107 := UT_NE107_RUN(Fault := Fault, Check := NOT Interlock, OutOfSpec := Warning, Maint := FALSE);

END_FUNCTION_BLOCK