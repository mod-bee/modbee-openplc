(* FB_Exercise — keeps idle equipment from seizing: after set.tExerciseAfterIdle with its owner not running, it asks the owner
for a run of set.tExerciseRunTime. Its owner (ipOwner) is a block that honours a part's Request:
  FB_LevelControl  the run goes through its pump or group, so the group's rotation exercises each member in turn
                   (a pump always has an owner, so a pump's exercise is its level control's)
  a valve          FB_Valve, FB_ValveLatch, FB_ValveMotor, FB_Valve3Pos (to set.nAutoPosition), FB_ValveMod,
                   FB_ValveFloat (fully open): opened in Auto for tExerciseRunTime, then back to where its owner wants it;
                   the interlock, trips and the permissive still apply, and an owner's own request wins
bExerciseNow (a rising edge) or bCmdExerciseNow runs one now. Any run by the owner restarts the interval;
set.tExerciseAfterIdle 0 = off. The interval counts power-on time only (no clock). *)

FUNCTION_BLOCK FB_Exercise EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipOwner : I_PartOwner; (* required: the level control, or the valve *)
    bExerciseNow : BOOL R_EDGE; (* run one now *)
    refData : REFERENCE TO ST_ExerciseData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bExercising : BOOL; (* an exercise run is asked now *)
  END_VAR
  VAR RETAIN
    stKept : ST_ExerciseSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    tIdleSince : TIME;
    tRunAt : TIME;
    bAsk : BOOL; (* a run asked by the pin or the HMI *)
    bEvaluated : BOOL;
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tExerciseAfterIdle >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tExerciseRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;              // the owner is running
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  VAR
    tN : TIME;
  END_VAR
  eErrorId := E_UtError.None;
  IF NOT bCalled AND bExercising THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.None;   (* never trip a process for a lost exercise: just stop asking *)
    bExercising := FALSE;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  IF NOT bEvaluated THEN
    bEvaluated := TRUE;
    tIdleSince := tN;
  END_IF;
  IF NOT __ISVALIDREF(refData) THEN
    Evaluate := E_PartAction.None;
    RETURN;
  END_IF;
  IF bExercising THEN
    IF tN - tRunAt >= refData.set.tExerciseRunTime THEN
      bExercising := FALSE;       (* done *)
      tIdleSince := tN;
    END_IF;
  ELSIF bOwnerRunCommand THEN
    tIdleSince := tN;             (* a real run restarts the interval *)
  ELSIF bAsk OR (refData.set.tExerciseAfterIdle > T#0s AND tN - tIdleSince >= refData.set.tExerciseAfterIdle) THEN
    bExercising := TRUE;
    tRunAt := tN;
  END_IF;
  bAsk := FALSE;
  IF refData.set.tExerciseAfterIdle > T#0s AND NOT bExercising THEN
    IF bOwnerRunCommand THEN
      refData.sts.tNextExerciseTimeLeft := refData.set.tExerciseAfterIdle;
    ELSE
      refData.sts.tNextExerciseTimeLeft := MAX(T#0s, refData.set.tExerciseAfterIdle - (tN - tIdleSince));
    END_IF;
  ELSE
    refData.sts.tNextExerciseTimeLeft := T#0s;
  END_IF;
  IF bExercising THEN
    Evaluate := E_PartAction.Request;   (* a normal run: start limits and cut-outs still apply *)
  ELSE
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNextPart : I_Part;    // the next part in the owner's chain
  END_VAR
  THIS^.ipNext := ipNextPart;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
IF bExerciseNow THEN bAsk := TRUE; END_IF;
IF refData.bCmdExerciseNow THEN
  bAsk := TRUE;
  refData.bCmdExerciseNow := FALSE;
END_IF;
refData.sts.bExercising := bExercising;
bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF bExercising THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK