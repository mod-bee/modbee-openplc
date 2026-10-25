(* UT_MIXER — stirrer / agitator controller: decides when the stirrer runs and
holds the pump for the pre-run. The stirrer motor is the Mixer plug
(UT_I_MOTOR: Request(Run, no hold, NaN, tag), IsReady, IsRunning) or, with
no plug, the MixerReady / MixerRunning wires and the Run output.

Run is on (while the level is OK) for any of:
  pre-run    PumpCall came on: Run on, StartHold holds the pump until the
             stirrer has run preRunTime (time already run counts); PumpCall
             going before the pump starts ends it.
  with pump  while PumpRunning (withPump).
  post-run   postRunTime after the pump stops, counted only while the level
             is OK (held while it is low, like the cycle; it ends when the
             pump runs again).
  start now  while StartNow.
  cycle      off for offTime, on for onTime, over and over (off first);
             any other run restarts the off time.
The pump is never held for a stirrer that cannot run: StartHold drops at
once with StartNow, a low level or a stirrer not ready, and after
preRunTime + 1 min if it still has not run (Warning "no pre-run" until
PumpCall ends). Level OK = LevelOk AND the Level plug: its value at / above
minLevel (back on at minLevel + minDeadband), or not in its L band; a bad
level counts as low (never stir blind). Wanted but held by the level for
lowLevel.delay -> warning. Settings kept; a bad write is put back. *)

FUNCTION_BLOCK UT_MIXER
  VAR_INPUT
    Enable : BOOL; (* the mixer logic works; FALSE: no run, the pump never held *)
    Cycle : BOOL := TRUE; (* the periodic timer may run *)
    PumpCall : BOOL; (* the pump is called: pre-run first *)
    PumpRunning : BOOL;
    StartNow : BOOL; (* run now, no pre-run, never hold the pump *)
    LevelOk : BOOL := TRUE; (* level at / above the minimum (AND-ed with Level) *)
    Level : UT_I_MEAS; (* tank level; NULL = LevelOk only *)
    Mixer : UT_I_MOTOR; (* the stirrer motor; NULL = the wires below *)
    MixerReady : BOOL := TRUE; (* only when Mixer is NULL *)
    MixerRunning : BOOL; (* only when Mixer is NULL *)
  END_VAR
  VAR_OUTPUT
    Run : BOOL; (* run the stirrer (also the link's request) *)
    StartHold : BOOL; (* the pump must wait: pre-run *)
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_MIXER_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_MIXER_SET;
    keptGood : BOOL;
  END_VAR
  VAR
    keep : UT_KEEP;
    sLow : UT_PROT_ST;
    ok : BOOL;
    cfgId : UT_FAULT;
    x : BOOL;
    tCur : TIME;
    tPrev : TIME;
    tStep : TIME;
    begun : BOOL;
    zero : REAL;
    nan : REAL;
    preT : TIME;
    postT : TIME;
    cycOk : BOOL;
    ready : BOOL;
    running : BOOL;
    lvlOk : BOOL;
    lvlHigh : BOOL; (* the value part (with its deadband) *)
    runPrev : BOOL;
    runSince : TIME;
    callPrev : BOOL;
    callSince : TIME;
    let : BOOL;
    noPre : BOOL;
    pumpPrev : BOOL;
    post : BOOL;
    postEl : TIME; (* the post-run's time so far (counts only while the level is OK) *)
    cycOn : BOOL;
    cycEl : TIME;
    otherRun : BOOL;
    wantPre : BOOL;
    want : BOOL;
    ranFor : TIME;
    stCode : UT_STATUS;
    stF : UT_FAULT;
    shownSt : UT_STATUS;
    shownF : UT_FAULT;
  END_VAR


tCur := TIME();
IF begun THEN
  tStep := tCur - tPrev;
ELSE
  tStep := T#0s;
  begun := TRUE;
  nan := zero / zero;
END_IF;
tPrev := tCur;
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
ok := UT_MIXER_CHECK(S := Data.set, Id => cfgId);
IF NOT ok AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := cfgId;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  ok := UT_MIXER_CHECK(S := Data.set, Id => cfgId);
END_IF;
IF keep.SaveSet AND (ok OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := ok;
END_IF;

preT := T#0s;
IF Data.set.preRun AND Data.set.preRunTime > T#0s THEN
  preT := Data.set.preRunTime;
END_IF;
postT := T#0s;
IF Data.set.postRun AND Data.set.postRunTime > T#0s THEN
  postT := Data.set.postRunTime;
END_IF;
cycOk := Data.set.cycle AND Data.set.onTime > T#0s AND Data.set.offTime > T#0s AND Cycle;

(* the stirrer and the level *)
IF Mixer <> NULL THEN
  ready := Mixer.IsReady();
  running := Mixer.IsRunning();
ELSE
  ready := MixerReady;
  running := MixerRunning;
END_IF;
lvlOk := LevelOk;
IF Level <> NULL THEN
  IF NOT Level.IsFitted() THEN
    ;
  ELSIF NOT Level.GoodNow() THEN
    lvlOk := FALSE;              (* bad = low: never stir blind *)
  ELSIF Level.HasValue() THEN
    IF Level.GetValue() >= Data.set.minLevel + Data.set.minDeadband THEN
      lvlHigh := TRUE;
    ELSIF Level.GetValue() < Data.set.minLevel THEN
      lvlHigh := FALSE;
    END_IF;
    lvlOk := lvlOk AND lvlHigh;
  ELSIF Level.HasBand(Band := UT_LVL_LO) THEN
    lvlOk := lvlOk AND NOT Level.IsLoNow();
  END_IF;
END_IF;

(* how long the stirrer has been running *)
IF running AND NOT runPrev THEN
  runSince := tCur;
END_IF;
runPrev := running;
IF running THEN
  ranFor := tCur - runSince;
ELSE
  ranFor := T#0s;
END_IF;

(* pre-run: hold the pump until the stirrer has run preT *)
IF PumpCall AND NOT callPrev THEN
  callSince := tCur;
  let := FALSE;
  noPre := FALSE;
END_IF;
callPrev := PumpCall;
wantPre := FALSE;
IF NOT Enable OR NOT PumpCall THEN
  let := FALSE;
  noPre := FALSE;
ELSIF NOT let THEN
  IF preT = T#0s OR StartNow OR NOT lvlOk OR PumpRunning OR ranFor >= preT THEN
    let := TRUE;                 (* no pre-run wanted, or it is done *)
  ELSIF NOT ready OR tCur - callSince >= preT + T#1m THEN
    let := TRUE;                 (* never hold the pump for a stirrer that cannot run *)
    noPre := TRUE;
  ELSE
    wantPre := TRUE;
  END_IF;
END_IF;
StartHold := wantPre;

(* post-run *)
IF Enable AND pumpPrev AND NOT PumpRunning AND postT > T#0s THEN
  post := TRUE;
  postEl := T#0s;
END_IF;
pumpPrev := PumpRunning;
IF post AND lvlOk THEN
  postEl := postEl + tStep;      (* a stirrer held by the level is not stirring: its post-run waits *)
END_IF;
IF post AND (NOT Enable OR PumpRunning OR postEl >= postT) THEN
  post := FALSE;
END_IF;
otherRun := Enable AND (wantPre OR (PumpCall AND let AND NOT noPre AND preT > T#0s)
                        OR (Data.set.withPump AND PumpRunning) OR post OR StartNow);

(* the cycle: off first; held while the level is low; restarted by other runs *)
IF NOT Enable OR NOT cycOk OR otherRun THEN
  cycOn := FALSE;
  cycEl := T#0s;
ELSIF lvlOk THEN
  cycEl := cycEl + tStep;
  IF cycOn THEN
    IF cycEl >= Data.set.onTime THEN
      cycOn := FALSE;
      cycEl := cycEl - Data.set.onTime;
      IF cycEl >= Data.set.offTime THEN cycEl := T#0s; END_IF;
    END_IF;
  ELSIF cycEl >= Data.set.offTime THEN
    cycOn := TRUE;
    cycEl := cycEl - Data.set.offTime;
    IF cycEl >= Data.set.onTime THEN cycEl := T#0s; END_IF;
  END_IF;
END_IF;
want := otherRun OR (Enable AND cycOn);
Run := want AND lvlOk;
IF Mixer <> NULL THEN
  x := Mixer.Request(ReqRun := Run, Hold := FALSE, ReqSpeed := nan, Owner := Data.set.tag);
END_IF;
x := UT_PROT_RUN(TNow := tCur, Cause := want AND NOT lvlOk, ResetReq := FALSE, RetryWindow := T#1h,
                 Prot := Data.set.lowLevel, Sts := Data.sts.lowLevel, St := sLow);
Warning := noPre OR sLow.warn OR sLow.trip;

(* time left *)
IF wantPre THEN
  Data.det.timeLeft := preT - ranFor;
ELSIF post AND NOT (Data.set.withPump AND PumpRunning) AND NOT StartNow THEN
  Data.det.timeLeft := postT - postEl;
ELSIF Enable AND cycOk AND NOT otherRun THEN
  IF cycOn THEN Data.det.timeLeft := Data.set.onTime - cycEl; ELSE Data.det.timeLeft := Data.set.offTime - cycEl; END_IF;
ELSE
  Data.det.timeLeft := T#0s;
END_IF;

(* status *)
stF := UT_F_NONE;
IF NOT Enable THEN
  stCode := UT_ST_OFF;
ELSIF noPre THEN
  stCode := UT_ST_WARNING;
  stF := UT_F_NO_PRE_RUN;
ELSIF NOT ok THEN
  stCode := UT_ST_WARN_SETTING;
  stF := cfgId;
ELSIF want AND NOT lvlOk THEN
  stCode := UT_ST_STOPPED_LOW;
ELSIF want AND NOT ready THEN
  stCode := UT_ST_MOTOR_NOT_READY;
ELSIF wantPre THEN
  stCode := UT_ST_PRE_RUN;
ELSIF Data.set.withPump AND PumpRunning THEN
  stCode := UT_ST_RUN_WITH_PUMP;
ELSIF StartNow THEN
  stCode := UT_ST_RUN_DEMAND;
ELSIF post THEN
  stCode := UT_ST_POST_RUN;
ELSIF otherRun THEN
  stCode := UT_ST_RUN_WITH_PUMP;     (* the pre-run is done: running on for the pump's call *)
ELSIF cycOk AND NOT lvlOk THEN
  stCode := UT_ST_STOPPED_LOW;       (* the cycle clock is held by the level, not resting *)
ELSIF cycOn THEN
  stCode := UT_ST_RUN_TIMED;
ELSIF cycOk THEN
  stCode := UT_ST_TIMED_REST;
ELSE
  stCode := UT_ST_IDLE;
END_IF;
IF stCode <> shownSt OR stF <> shownF OR LEN(Data.sts.statusText) = 0 THEN
  shownSt := stCode;
  shownF := stF;
  Data.sts.statusText := UT_STATUS_TEXT(stCode, stF);
END_IF;
Data.sts.statusCode := stCode;
Data.sts.faultId := stF;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := NOT Enable, OutOfSpec := Warning, Maint := FALSE);
Data.sts.wanted := want;
Data.sts.levelOk := lvlOk;

END_FUNCTION_BLOCK