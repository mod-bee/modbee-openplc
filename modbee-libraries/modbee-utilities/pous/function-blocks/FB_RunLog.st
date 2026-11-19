(* FB_RunLog — the last run's time, volume and end reason, and run counts by how they ended. An observer,
not a part: it reads its run (ipRun) and changes nothing, so a missing rung never stops a run. Call it every scan
after the run.
When the run ends: tot.tLastRunTime (counted run time), tot.tLastRunStartToEnd (from start to end, pauses included),
tot.fLastRunVolume (from ipMeter's total, optional), tot.eLastStopReason; tot.nRunCount and one of nDoneRunCount (Done), nStoppedRunCount
(Request, Manual, Off, Hand, Restart), nPowerCutRunCount (PowerCut), nFaultedRunCount (any other reason: a fault, an interlock, an
abort, a maximum). A restart (ipRun.nActRunId changes while it stays active) ends the run (Restart) and starts the
next one. tot is kept over a power cut (written once per run end); bCmdResetCounters clears the counts.
Pins: ipRun (required), ipMeter, refData -> bRunEnded (one scan, at each run end), plus FB_Object's outputs. *)

FUNCTION_BLOCK FB_RunLog EXTENDS FB_Object
  VAR_INPUT
    ipRun : I_Run; (* required *)
    ipMeter : I_Meter; (* optional: the volume of each run *)
    refData : REFERENCE TO ST_RunLogData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bRunEnded : BOOL; (* one scan at each run end *)
  END_VAR
  VAR RETAIN
    stKeptTot : ST_RunLogTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bActPrev : BOOL;
    nRunSeen : UDINT; (* ipRun.nActRunId last seen *)
    tStartAt : TIME;
    fStartTotal : LREAL;
    tElapsed : TIME; (* the run's counted time, last seen while it ran *)
    bCountSeen : BOOL;
  END_VAR
  VAR_TEMP
    bAct : BOOL;
    bRestarted : BOOL; (* the run restarted (a new run while it stays active) *)
    eWhy : E_StopReason;
  END_VAR


bRunEnded := FALSE;
IF ipRun = NULL OR NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.tot := stKeptTot;
  ELSE
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  bActPrev := ipRun.bIsBusy;    (* a run resumed after a power cut is logged when it ends *)
  nRunSeen := ipRun.nActRunId;
  tStartAt := tNow;
  IF ipMeter <> NULL THEN
    fStartTotal := ipMeter.fActTotal;
  END_IF;
END_IF;
IF refData.bCmdResetCounters AND NOT bCountSeen THEN
  refData.tot.nRunCount := 0;
  refData.tot.nDoneRunCount := 0;
  refData.tot.nStoppedRunCount := 0;
  refData.tot.nFaultedRunCount := 0;
  refData.tot.nPowerCutRunCount := 0;
  stKeptTot := refData.tot;
END_IF;
bCountSeen := refData.bCmdResetCounters;
refData.bCmdResetCounters := FALSE;

bAct := ipRun.bIsBusy;
bRestarted := bAct AND bActPrev AND ipRun.nActRunId <> nRunSeen;
IF bActPrev AND (NOT bAct OR bRestarted) THEN
  (* the run ended (a restart ends it too) *)
  IF bRestarted THEN
    eWhy := E_StopReason.Restart;
  ELSE
    eWhy := ipRun.eActStopReason;
  END_IF;
  refData.tot.nRunCount := refData.tot.nRunCount + 1;
  CASE eWhy OF
  E_StopReason.Done:
    refData.tot.nDoneRunCount := refData.tot.nDoneRunCount + 1;
  E_StopReason.Request, E_StopReason.Manual, E_StopReason.Off, E_StopReason.Hand, E_StopReason.Restart:
    refData.tot.nStoppedRunCount := refData.tot.nStoppedRunCount + 1;
  E_StopReason.PowerCut:
    refData.tot.nPowerCutRunCount := refData.tot.nPowerCutRunCount + 1;
  ELSE
    refData.tot.nFaultedRunCount := refData.tot.nFaultedRunCount + 1;
  END_CASE;
  refData.tot.tLastRunTime := tElapsed;
  refData.tot.tLastRunStartToEnd := tNow - tStartAt;
  IF ipMeter <> NULL THEN
    refData.tot.fLastRunVolume := MAX(ipMeter.fActTotal - fStartTotal, 0.0);
  ELSE
    refData.tot.fLastRunVolume := 0.0;
  END_IF;
  refData.tot.eLastStopReason := eWhy;
  stKeptTot := refData.tot;       (* kept once per run end *)
  bRunEnded := TRUE;
END_IF;
IF bAct AND (NOT bActPrev OR bRestarted) THEN
  (* a new run *)
  tStartAt := tNow;
  IF ipMeter <> NULL THEN
    fStartTotal := ipMeter.fActTotal;
  END_IF;
END_IF;
IF bAct THEN
  tElapsed := ipRun.tActElapsed;
END_IF;
nRunSeen := ipRun.nActRunId;
bActPrev := bAct;
bError := FALSE;
bWarning := FALSE;
eErrorId := E_UtError.None;
IF bAct THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK