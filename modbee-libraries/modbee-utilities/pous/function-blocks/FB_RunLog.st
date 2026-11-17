(* FB_RunLog — the last run's time, volume and end reason, and run counts by how they ended (modular plan UT_RUN_LOG;
the src-v2 run blocks' kept last-run values). An observer, not a part: it reads its run (ipRun) and changes nothing,
so a missing rung never stops a run. Call it every scan after the run.
When the run ends: tot.tLastRun (counted run time), tot.tLastWall (from start to end, pauses included),
tot.fLastVolume (from ipMeter's total, optional), tot.eLastReason; tot.nRuns and one of nDone (Done), nStopped
(Request, Manual, Off, Hand), nPowerCuts (PowerCut), nFaults (any other reason: a fault, an interlock, an abort, a
maximum). tot is kept over a power cut (written once per run end); bCmdResetCounts clears the counts.
Pins: ipRun (required), ipMeter, refData -> bRunEnded (one scan, at each run end), plus FB_Object's outputs. *)

FUNCTION_BLOCK FB_RunLog EXTENDS FB_Object
  VAR_INPUT
    ipRun : I_Run; (* required *)
    ipMeter : I_Meter; (* optional: the volume of each run *)
    refData : REFERENCE TO ST_RunLogData;
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
    tStartAt : TIME;
    fStartTotal : LREAL;
    tElapsed : TIME; (* the run's counted time, last seen while it ran *)
    bCountSeen : BOOL;
  END_VAR
  VAR_TEMP
    bAct : BOOL;
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
  bActPrev := ipRun.bIsActive;    (* a run resumed after a power cut is logged when it ends *)
  tStartAt := tNow;
  IF ipMeter <> NULL THEN
    fStartTotal := ipMeter.fActTotal;
  END_IF;
END_IF;
IF refData.bCmdResetCounts AND NOT bCountSeen THEN
  refData.tot.nRuns := 0;
  refData.tot.nDone := 0;
  refData.tot.nStopped := 0;
  refData.tot.nFaults := 0;
  refData.tot.nPowerCuts := 0;
  stKeptTot := refData.tot;
END_IF;
bCountSeen := refData.bCmdResetCounts;
refData.bCmdResetCounts := FALSE;

bAct := ipRun.bIsActive;
IF bAct AND NOT bActPrev THEN
  tStartAt := tNow;
  IF ipMeter <> NULL THEN
    fStartTotal := ipMeter.fActTotal;
  END_IF;
END_IF;
IF bAct THEN
  tElapsed := ipRun.tActElapsed;
ELSIF bActPrev THEN
  (* the run ended *)
  eWhy := ipRun.eActStopReason;
  refData.tot.nRuns := refData.tot.nRuns + 1;
  CASE eWhy OF
  E_StopReason.Done:
    refData.tot.nDone := refData.tot.nDone + 1;
  E_StopReason.Request, E_StopReason.Manual, E_StopReason.Off, E_StopReason.Hand:
    refData.tot.nStopped := refData.tot.nStopped + 1;
  E_StopReason.PowerCut:
    refData.tot.nPowerCuts := refData.tot.nPowerCuts + 1;
  ELSE
    refData.tot.nFaults := refData.tot.nFaults + 1;
  END_CASE;
  refData.tot.tLastRun := tElapsed;
  refData.tot.tLastWall := tNow - tStartAt;
  IF ipMeter <> NULL THEN
    refData.tot.fLastVolume := MAX(ipMeter.fActTotal - fStartTotal, 0.0);
  ELSE
    refData.tot.fLastVolume := 0.0;
  END_IF;
  refData.tot.eLastReason := eWhy;
  stKeptTot := refData.tot;       (* kept once per run end *)
  bRunEnded := TRUE;
END_IF;
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