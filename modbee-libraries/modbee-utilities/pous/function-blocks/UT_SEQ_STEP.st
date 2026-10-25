(* One machine of a UT_SEQUENCER chain (an element block: the project calls it before the chain). It owns
its motor (Unit, Request with By = chain tag + step) or, with no Unit, drives Cmd and reads Feedback / Ready. *)

FUNCTION_BLOCK UT_SEQ_STEP
  VAR_INPUT
    Unit : UT_I_MOTOR; (* the machine's motor; NULL = Cmd / Feedback / Ready *)
    Feedback : BOOL; (* running / proven (no Unit) *)
    Ready : BOOL := TRUE; (* healthy (no Unit) *)
  END_VAR
  VAR_OUTPUT
    Cmd : BOOL; (* run this machine (no Unit) *)
    Running : BOOL;
    Fault : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_SEQ_STEP_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_SEQ_STEP_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    ok : BOOL;
    cur : UT_SEQ_STEP_SET;
    wRun : BOOL;
    wNo : INT;
    wBy : STRING(12);
    qFb : BOOL;
    qReady : BOOL;
    qState : UT_STATE;
    qEl : TIME;
    qLeft : TIME;
    refusedU : BOOL;
    zero : REAL;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
    stCode : UT_STATUS;
    stF : UT_FAULT;
  END_VAR


METHOD PUBLIC Command : BOOL     // the chain's command each scan; FALSE = refused
  VAR_INPUT
    Run : BOOL;
    No : INT;
    Owner : STRING(12);
  END_VAR
  wRun := Run;
  wNo := No;
  wBy := Owner;
  Command := NOT refusedU;
END_METHOD
METHOD PUBLIC SetState : BOOL    // the chain's view of this step, for its status
  VAR_INPUT
    State : UT_STATE;
    Elapsed : TIME;
    Left : TIME;
  END_VAR
  qState := State;
  qEl := Elapsed;
  qLeft := Left;
  SetState := TRUE;
END_METHOD
METHOD PUBLIC FeedbackNow : BOOL
  FeedbackNow := qFb;
END_METHOD
METHOD PUBLIC IsRunning : BOOL
  IsRunning := qFb;
END_METHOD
METHOD PUBLIC IsReady : BOOL
  IsReady := qReady;
END_METHOD
METHOD PUBLIC IsBypassed : BOOL
  IsBypassed := cur.bypass;
END_METHOD
METHOD PUBLIC NoFeedback : BOOL
  NoFeedback := cur.noFeedback;
END_METHOD
METHOD PUBLIC StartDelay : TIME
  StartDelay := cur.startDelay;
END_METHOD
METHOD PUBLIC StopDelay : TIME
  StopDelay := cur.stopDelay;
END_METHOD
METHOD PUBLIC Timeout : TIME
  Timeout := cur.timeout;
END_METHOD
METHOD PUBLIC Settings : UT_SEQ_STEP_SET
  Settings := cur;
END_METHOD

keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := Data.set.startDelay >= T#0s AND Data.set.stopDelay >= T#0s AND Data.set.timeout >= T#0s;
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_STEP_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := TRUE;
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;
cur := Data.set;                 (* a bad first-boot setting is the chain's config fault *)
refusedU := FALSE;
IF Unit <> NULL THEN
  refusedU := NOT Unit.Request(ReqRun := wRun, Hold := FALSE, ReqSpeed := zero / zero,
                               Owner := CONCAT(wBy, CONCAT(' ', INT_TO_STRING(wNo))));
  qFb := Unit.IsRunning();
  qReady := Unit.IsReady() OR Unit.IsRunning();
ELSE
  qFb := Feedback;
  qReady := Ready;
END_IF;
Cmd := wRun;
Running := qFb;
Fault := qState = UT_STATE_FAULT OR refusedU;
stF := UT_F_NONE;
CASE qState OF
UT_STATE_FAULT: stCode := UT_ST_FAULT; stF := UT_F_STEP_FB_LOST;
UT_STATE_STARTING: stCode := UT_ST_STARTING;
UT_STATE_STOPPING: stCode := UT_ST_STOPPING;
UT_STATE_ON: stCode := UT_ST_RUNNING;
UT_STATE_OOS: stCode := UT_ST_OOS;
ELSE
  stCode := UT_ST_OFF;
END_CASE;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.state := qState;
Data.det.elapsed := qEl;
Data.det.timeLeft := qLeft;

END_FUNCTION_BLOCK