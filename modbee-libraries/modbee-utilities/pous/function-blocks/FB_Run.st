(* FB_Run — one run of any equipment (DESIGN-0.2.md section 5.5; src-v2 UT_RUN_LIMIT + UT_RUN_CORE): a held
request, or a latched start, ended by its time target, a stop, an abort, its maximum time, the interlock, a
part, or a power cut.

Pins: bRun (held request: the run lasts while it is held), bStart (rising edge: a latched run), bStop
(rising edge: ends it, wins), bReset, bInterlock (FALSE ends the run and refuses a start), bPermissive (FALSE:
a new run waits), bPause (held: no run command, no counting), bAbort (rising edge: ends it with eAbortCode),
eAbortCode, bEquipRunning (the equipment runs: time counts only then) -> bRunCmd. ipTarget (optional): the equipment the run drives directly (a pump, a valve, a group: it is
requested every scan and its running counts as bEquipRunning); else wire bRunCmd to a
level control's bDemand), bActive, bPaused, plus FB_Object's outputs. refData: its record.
set.bByTime: the run ends after set.tRunTime of running. set.tMaxTime > 0: it ends there, running or not (a
warning). set.tMaxPause > 0: a pause that long ends it. After a run ends, a new one needs the request to drop
and come again.
Power cut: the progress is kept on events and every set.tProgressSave. set.eResume Resume: a latched run goes
on from its progress; a held one goes on if its request is back within set.tResumeWindow, else it ends
(PowerCut). Restart: the same from zero. None: it ends (PowerCut).
Parts: a trip ends it (Fault); a signal pauses it; Done ends it normally (FB_RunVolume's target); Cap ends it at
a part's safety time cap (stop reason TimeCap, a warning RunCapped until a reset or the next run); a hold makes a
new run wait. Its parts: FB_RunVolume (volume target, safety cap), FB_RunPause (operator pause / resume), FB_RunGate
(wait for a permissive), FB_LevelCheck (source low, destination full); observer FB_RunLog. *)

FUNCTION_BLOCK FB_Run EXTENDS FB_Object IMPLEMENTS I_Run
  VAR_INPUT
    bRun : BOOL := FALSE;
    bStart : BOOL R_EDGE;
    bStop : BOOL R_EDGE;
    bReset : BOOL R_EDGE;
    bInterlock : BOOL := TRUE;
    bPermissive : BOOL := TRUE;
    bPause : BOOL;
    bAbort : BOOL R_EDGE;
    eAbortCode : E_StopReason := E_StopReason.Abort;
    bEquipRunning : BOOL; (* the equipment runs (or ipTarget's own running) *)
    ipTarget : I_Equipment; (* optional: the equipment this run drives (Request every scan; Ladder-ready) *)
    refData : REFERENCE TO ST_RunData;
  END_VAR
  VAR_OUTPUT
    bRunCmd : BOOL;
    bActive : BOOL;
    bPaused : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_RunSet;
    nKeptLayout : UINT;
    stProgress : ST_RunProgress; (* kept on events and every tProgressSave *)
    stKeptTot : ST_RunTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bLatched : BOOL;
    bWaiting : BOOL;
    bRunPrev : BOOL;
    tLast : TIME;
    tStartedAt : TIME;
    tPausedAt : TIME;
    bPausedPrev : BOOL;
    tSavedAt : TIME;
    bResumeWait : BOOL; (* after a power cut: a held run waits for its request *)
    tPowerUp : TIME;
    bMaxWarn : BOOL;
    bCapWarn : BOOL; (* a part's safety time cap ended a run (cleared by a reset or a new run) *)
  END_VAR
  VAR_TEMP
    bResetNow : BOOL;
    bNew : BOOL;
    bPauseNow : BOOL;
    bEqRun : BOOL; (* the equipment runs (bEquipRunning or ipTarget) *)
    eReqErr : E_UtError;
  END_VAR


PROPERTY PUBLIC bIsActive : BOOL
  GET
    bIsActive := bActive;
  END_GET
END_PROPERTY

PROPERTY PUBLIC tActElapsed : TIME
  GET
    IF __ISVALIDREF(refData) THEN tActElapsed := refData.det.tElapsed; ELSE tActElapsed := T#0s; END_IF;
  END_GET
END_PROPERTY

PROPERTY PUBLIC eActStopReason : E_StopReason
  GET
    IF __ISVALIDREF(refData) THEN eActStopReason := refData.sts.eStopReason; ELSE eActStopReason := E_StopReason.None; END_IF;
  END_GET
END_PROPERTY

(* ends the active run *)
METHOD PRIVATE EndRun
  VAR_INPUT
    eWhy : E_StopReason;
  END_VAR
  IF bActive THEN
    refData.sts.eStopReason := eWhy;
    refData.tot.nRuns := refData.tot.nRuns + 1;
    refData.tot.tLastRun := refData.det.tElapsed;
    stKeptTot := refData.tot;
  END_IF;
  bActive := FALSE;
  bLatched := FALSE;
  bWaiting := FALSE;
  bResumeWait := FALSE;
  stProgress.bActive := FALSE;
  stProgress.bLatched := FALSE;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := refData.set.tRunTime >= T#0s AND refData.set.tMaxTime >= T#0s AND refData.set.tMaxPause >= T#0s
           AND refData.set.tResumeWindow >= T#0s AND refData.set.tProgressSave > T#0s;
END_METHOD

(* the equipment: ipTarget (driven from here, every scan) or the bEquipRunning wire *)
bEqRun := bEquipRunning;
IF ipTarget <> NULL THEN
  bEqRun := bEqRun OR ipTarget.bIsRunning;
END_IF;
IF NOT __ISVALIDREF(refData) THEN
  bRunCmd := FALSE;
  IF ipTarget <> NULL THEN
    eReqErr := ipTarget.Request(bRun := FALSE, bHold := FALSE);
  END_IF;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings and progress, power-up *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    stProgress.bActive := FALSE;
    nKeptLayout := cLayout;
  END_IF;
  tLast := tNow;
  tSavedAt := tNow;
  tPowerUp := tNow;
  bRunPrev := TRUE;               // a request held at power-up is not a new run
  IF stProgress.bActive THEN
    CASE refData.set.eResume OF
      E_RunResume.Resume, E_RunResume.Restart:
        bActive := TRUE;
        bLatched := stProgress.bLatched;
        IF refData.set.eResume = E_RunResume.Resume THEN
          refData.det.tElapsed := stProgress.tElapsed;
        ELSE
          refData.det.tElapsed := T#0s;
        END_IF;
        bResumeWait := NOT bLatched;
        tStartedAt := tNow;
    ELSE
      bActive := TRUE;
      EndRun(eWhy := E_StopReason.PowerCut);
    END_CASE;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

bResetNow := bReset OR refData.bCmdReset OR SystemReset();
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  bMaxWarn := FALSE;
  bCapWarn := FALSE;
END_IF;
IF bResetNow THEN
  bMaxWarn := FALSE;
  bCapWarn := FALSE;
END_IF;

(* a held run after a power cut: its request must come back within the window *)
IF bResumeWait THEN
  IF bRun THEN
    bResumeWait := FALSE;
  ELSIF tNow - tPowerUp >= refData.set.tResumeWindow THEN
    EndRun(eWhy := E_StopReason.PowerCut);
  END_IF;
END_IF;

(* a new run *)
bNew := (bRun AND NOT bRunPrev) OR bStart OR refData.bCmdStart;
IF NOT bActive AND bNew THEN
  IF bInterlock THEN
    bActive := TRUE;
    bLatched := bStart OR refData.bCmdStart;
    bWaiting := TRUE;
    refData.det.tElapsed := T#0s;
    refData.sts.eStopReason := E_StopReason.None;
    bCapWarn := FALSE;
    tStartedAt := tNow;
    stProgress.bActive := TRUE;
    stProgress.bLatched := bLatched;
    stProgress.tElapsed := T#0s;
    tSavedAt := tNow;
  END_IF;
END_IF;
refData.bCmdStart := FALSE;
bRunPrev := bRun;

(* parts *)
EvaluateParts(bRunning := bRunCmd AND bEqRun, bResetWanted := bResetNow, bMasked := FALSE);

(* the run ends *)
IF bActive THEN
  IF bStop OR refData.bCmdStop THEN
    EndRun(eWhy := E_StopReason.Request);
  ELSIF NOT bInterlock THEN
    EndRun(eWhy := E_StopReason.Interlock);
  ELSIF bAbort THEN
    EndRun(eWhy := eAbortCode);
  ELSIF bPartTrip THEN
    EndRun(eWhy := E_StopReason.Fault);
  ELSIF bPartDone THEN
    EndRun(eWhy := E_StopReason.Done);
  ELSIF bPartCap THEN
    bCapWarn := TRUE;
    EndRun(eWhy := E_StopReason.TimeCap);
  ELSIF NOT bLatched AND NOT bRun AND NOT bResumeWait THEN
    EndRun(eWhy := E_StopReason.Request);   // the held request dropped
  ELSIF refData.set.bByTime AND refData.det.tElapsed >= refData.set.tRunTime THEN
    EndRun(eWhy := E_StopReason.Done);
  ELSIF refData.set.tMaxTime > T#0s AND tNow - tStartedAt >= refData.set.tMaxTime THEN
    bMaxWarn := TRUE;
    EndRun(eWhy := E_StopReason.MaxRun);
  END_IF;
END_IF;
refData.bCmdStop := FALSE;

(* waiting, pause *)
IF bActive AND bWaiting AND bPermissive AND NOT bPartHold THEN
  bWaiting := FALSE;
END_IF;
bPauseNow := bActive AND NOT bWaiting AND (bPause OR bPartStop OR bResumeWait);
IF bPauseNow AND NOT bPausedPrev THEN
  tPausedAt := tNow;
END_IF;
bPausedPrev := bPauseNow;
IF bPauseNow AND refData.set.tMaxPause > T#0s AND tNow - tPausedAt >= refData.set.tMaxPause THEN
  EndRun(eWhy := E_StopReason.PauseMax);
  bPauseNow := FALSE;
END_IF;
bPaused := bPauseNow;
bRunCmd := bActive AND NOT bWaiting AND NOT bPauseNow AND bInterlock;

(* counting: only while the equipment runs *)
IF bRunCmd AND bEqRun THEN
  refData.det.tElapsed := refData.det.tElapsed + (tNow - tLast);
END_IF;
tLast := tNow;
IF bActive AND tNow - tSavedAt >= refData.set.tProgressSave THEN
  stProgress.tElapsed := refData.det.tElapsed;
  stKeptTot := refData.tot;
  tSavedAt := tNow;
END_IF;
IF refData.set.bByTime AND bActive THEN
  refData.det.tTimeLeft := refData.set.tRunTime - refData.det.tElapsed;
  IF refData.det.tTimeLeft < T#0s THEN refData.det.tTimeLeft := T#0s; END_IF;
ELSE
  refData.det.tTimeLeft := T#0s;
END_IF;

(* status *)
bError := bPartTrip;
bWarning := bPartWarn OR bMaxWarn OR bCapWarn OR refData.sts.bRefused;
IF bPartTrip THEN
  eErrorId := ePartTrip;
ELSIF bMaxWarn THEN
  eErrorId := E_UtError.RunMaxTime;
ELSIF bCapWarn THEN
  eErrorId := E_UtError.RunCapped;
ELSIF bPartWarn THEN
  eErrorId := ePartWarn;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF NOT bActive THEN
  eState := E_State.Idle;
ELSIF bWaiting THEN
  eState := E_State.Waiting;
ELSIF bPauseNow THEN
  eState := E_State.Held;
ELSIF bRunCmd AND bEqRun THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Starting;
END_IF;
IF ipTarget <> NULL THEN
  eReqErr := ipTarget.Request(bRun := bRunCmd, bHold := FALSE);
END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.bActive := bActive;
refData.sts.bPaused := bPauseNow;
refData.sts.bWaiting := bWaiting;
bFirstScan := FALSE;

END_FUNCTION_BLOCK